-- Area generator, pure logic (no engine calls; tests/areagen_test.lua). Builds a tile model of a hunting area or a
-- dungeon from a seed: the layout (cave, rooms and corridors, open waste), several floors joined by holes and ladders,
-- ground variation, borders picked per neighbour pattern like the map editor's auto-border, walls, decoration, lights,
-- spawns, a boss room, the arrival and the exit. One seed always gives the same model in LuaJIT and Lua 5.3.
-- areagen.lua builds the model with Game.createTile at startup; server/tools/areagen_export.py writes it as an OTBM
-- piece for the map editor and renders previews. Numbers and palettes: areagen_config.lua. server/README.md
-- "Generated areas", docs/MAP_GUIDE.md "Generated areas".
--
--   ChaosAreaGenCore.rng(seed) / hash(text)          seeded generator (Park-Miller), r:int(a, b), r:chance(pct)
--   ChaosAreaGenCore.generate(cfg, def, opts)         the tile model of one area (opts.dark: use the dark tile set)
--   ChaosAreaGenCore.borderPieces(n, e, s, w, ne, nw, se, sw)   border piece names for one tile (see below)
--   ChaosAreaGenCore.wallPiece(n, e, s, w)            wall piece type for one wall tile
--   ChaosAreaGenCore.levelScale(native, target)       health / damage / experience multipliers for a target level
--   ChaosAreaGenCore.validate(cfg, model)             problems of a model (connectivity, items, spawns, links)
--   ChaosAreaGenCore.allowedIds(cfg, def, opts)       every item id the area may use
--   ChaosAreaGenCore.checksum(model)                  one number over every tile, item and spawn
--
-- The model (absolute map positions):
--   {name, kind, origin, w, h, floors = {{z, walkable = n}}, tiles = {{x, y, z, ground, items = {id, ...}}},
--    arrival = pos, exit = pos (the exit portal), links = {{hole = pos, ladder = pos, up = pos}},
--    spawns = {{x, y, z, monster, level, count, spawntime}}, boss = spawn or nil, bossRoom = {x1, y1, x2, y2, z},
--    stats = {walkable, monsters, density, lights, deco, floors = {...}}}
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible: integer maths only, no 5.3-only syntax.

ChaosAreaGenCore = ChaosAreaGenCore or {}
local A = ChaosAreaGenCore
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

-- opts.tick (A.generate): called now and then in the long loops (never inside a sort), so a caller running the
-- generator in a coroutine can yield there and spread one big layout over many short game loop tasks (rift.lua).
-- It never draws a random number, so a model is the same with or without it.
local tickFn
local function T()
	if tickFn then
		tickFn()
	end
end
local tickCount = 0
-- (every 1024 steps of a hot loop)
local function T2048()
	tickCount = tickCount + 1
	if tickCount >= 1024 then
		tickCount = 0
		T()
	end
end

-- ====================================================================== random
local MOD, MULT = 2147483647, 48271
local Rng = {}
Rng.__index = Rng

function Rng:next()
	self.s = (self.s * MULT) % MOD
	return self.s
end

function Rng:int(a, b)
	if b <= a then
		return a
	end
	return a + self:next() % (b - a + 1)
end

-- true with pct percent (fractions allowed)
function Rng:chance(pct)
	if (pct or 0) <= 0 then
		return false
	end
	return self:next() % 100000 < floor(pct * 1000 + 0.5)
end

-- rows = {{value, weight}, ...}
function Rng:weighted(rows)
	local total = 0
	for _, row in ipairs(rows) do
		total = total + max(0, row[2])
	end
	if total <= 0 then
		return nil
	end
	local roll = self:int(1, total)
	for _, row in ipairs(rows) do
		roll = roll - max(0, row[2])
		if roll <= 0 then
			return row[1]
		end
	end
	return rows[#rows][1]
end

function Rng:shuffle(list)
	for i = #list, 2, -1 do
		local j = self:int(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

function A.rng(seed)
	local s = floor(tonumber(seed) or 1) % MOD
	if s <= 0 then
		s = s + MOD - 1
	end
	local r = setmetatable({s = s}, Rng)
	r:next()
	return r
end

-- a seed from a string (same in every interpreter)
function A.hash(text)
	local h = 5381
	text = tostring(text)
	for i = 1, #text do
		h = (h * 33 + text:byte(i)) % MOD
	end
	return h
end

-- ====================================================================== grids
-- a floor is w x h cells, index i = (y - 1) * w + x (1-based local coordinates)
local D8 = {{0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}} -- clockwise from north
local D4 = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}}

local VOID, ROCK, OPEN, WALL = 0, 1, 2, 3

local function newGrid(w, h, v)
	local g = {}
	for i = 1, w * h do
		g[i] = v
	end
	return g
end

local function inside(F, x, y)
	return x >= 1 and y >= 1 and x <= F.w and y <= F.h
end

local function idx(F, x, y)
	return (y - 1) * F.w + x
end

local function xy(F, i)
	local y = floor((i - 1) / F.w) + 1
	return i - (y - 1) * F.w, y
end

-- flood fill (8 neighbours) over cells where pass(i) is true; returns a set {i = true} and its size
local function flood(F, start, pass)
	local seen, n, stack = {[start] = true}, 1, {start}
	while #stack > 0 do
		T2048()
		local i = table.remove(stack)
		local x, y = xy(F, i)
		for _, d in ipairs(D8) do
			local nx, ny = x + d[1], y + d[2]
			if inside(F, nx, ny) then
				local j = idx(F, nx, ny)
				if not seen[j] and pass(j) then
					seen[j] = true
					n = n + 1
					stack[#stack + 1] = j
				end
			end
		end
	end
	return seen, n
end

-- the regions of `pass` cells (8 neighbours), largest first
local function regions(F, pass)
	local done, out = {}, {}
	for i = 1, F.w * F.h do
		T2048()
		if not done[i] and pass(i) then
			local set, n = flood(F, i, pass)
			for j in pairs(set) do
				done[j] = true
			end
			out[#out + 1] = {set = set, n = n, first = i}
		end
	end
	table.sort(out, function(a, b)
		if a.n ~= b.n then
			return a.n > b.n
		end
		return a.first < b.first
	end)
	return out
end

-- breadth-first distances (8 neighbours) from `from` over pass(i) cells
local function distances(F, from, pass)
	local dist, queue, head = {[from] = 0}, {from}, 1
	while head <= #queue do
		T2048()
		local i = queue[head]
		head = head + 1
		local x, y = xy(F, i)
		for _, d in ipairs(D8) do
			local nx, ny = x + d[1], y + d[2]
			if inside(F, nx, ny) then
				local j = idx(F, nx, ny)
				if dist[j] == nil and pass(j) then
					dist[j] = dist[i] + 1
					queue[#queue + 1] = j
				end
			end
		end
	end
	return dist
end

-- one shortest path from `from` to `to` (list of cells, both ends), or nil
local function pathBetween(F, from, to, pass)
	local dist = distances(F, to, pass)
	if dist[from] == nil then
		return nil
	end
	local out, i = {from}, from
	while i ~= to do
		local x, y = xy(F, i)
		local best
		for _, d in ipairs(D8) do
			local nx, ny = x + d[1], y + d[2]
			if inside(F, nx, ny) then
				local j = idx(F, nx, ny)
				if dist[j] ~= nil and dist[j] == dist[i] - 1 and (not best or j < best) then
					best = j
				end
			end
		end
		i = best
		out[#out + 1] = i
	end
	return out
end

-- carve a disc of radius r (open cells), kept inside the margin
local function carveDisc(F, cx, cy, r, margin)
	margin = margin or 2
	for dy = -r, r do
		for dx = -r, r do
			if dx * dx + dy * dy <= r * r + r then
				local x, y = cx + dx, cy + dy
				if x > margin and y > margin and x <= F.w - margin and y <= F.h - margin then
					F.open[idx(F, x, y)] = true
				end
			end
		end
	end
end

local function carveRect(F, x1, y1, x2, y2)
	for y = y1, y2 do
		for x = x1, x2 do
			if inside(F, x, y) then
				F.open[idx(F, x, y)] = true
			end
		end
	end
end

-- a winding tunnel from (x, y) to (tx, ty): steps toward the target, sometimes aside
-- wild: the radius swells and narrows by one tile and the route strays more, for ragged open-air trails
local function tunnel(F, r, x, y, tx, ty, radius, wild)
	local guard = 0
	while (x ~= tx or y ~= ty) and guard < 4 * (F.w + F.h) do
		guard = guard + 1
		carveDisc(F, x, y, wild and max(1, radius + r:int(-1, 1)) or radius)
		local dx, dy = tx - x, ty - y
		if r:chance(wild and 40 or 25) then
			local d = D4[r:int(1, 4)]
			x, y = x + d[1], y + d[2]
		elseif abs(dx) > abs(dy) or (abs(dx) == abs(dy) and r:chance(50)) then
			x = x + (dx > 0 and 1 or -1)
		else
			y = y + (dy > 0 and 1 or -1)
		end
		x = min(max(x, 3), F.w - 2)
		y = min(max(y, 3), F.h - 2)
	end
	carveDisc(F, tx, ty, radius)
end

-- ====================================================================== layouts
-- every layout sets F.open (the walkable design) and F.rooms; required points (arrival, links, boss) are open and joined

-- ruined chambers of a mixed layout: p.rooms = {min, max} rectangles of p.room = {min, max} sides, p.gap apart and
-- away from the required points; carved into F.open (the cave's join pass links them), listed in F.rooms / F.roomIdx
local function mixedRooms(F, r, p, required)
	local w, h = F.w, F.h
	local want = r:int(p.rooms[1], p.rooms[2])
	local rooms = F.rooms
	F.roomIdx = F.roomIdx or {}
	local gap = p.gap or 3
	for _ = 1, want * 8 do
		if #rooms >= want then
			break
		end
		T()
		local rw, rh = r:int(p.room[1], p.room[2]), r:int(p.room[1], p.room[2])
		local x1, y1 = r:int(5, w - rw - 4), r:int(5, h - rh - 4)
		local x2, y2 = x1 + rw - 1, y1 + rh - 1
		local fits = true
		for _, q in ipairs(rooms) do
			if x1 - gap <= q.x2 and x2 + gap >= q.x1 and y1 - gap <= q.y2 and y2 + gap >= q.y1 then
				fits = false
			end
		end
		for _, q in ipairs(required) do
			local m = (q.r or 2) + gap
			if q.x >= x1 - m and q.x <= x2 + m and q.y >= y1 - m and q.y <= y2 + m then
				fits = false
			end
		end
		if fits then
			local q = {x1 = x1, y1 = y1, x2 = x2, y2 = y2, cx = floor((x1 + x2) / 2), cy = floor((y1 + y2) / 2), kind = "hunt"}
			rooms[#rooms + 1] = q
			for y = y1, y2 do
				for x = x1, x2 do
					-- the corners cut, so a chamber does not read as a pasted box
					if not ((x == x1 or x == x2) and (y == y1 or y == y2)) then
						F.open[idx(F, x, y)] = true
						F.roomIdx[idx(F, x, y)] = #rooms
					end
				end
			end
		end
	end
end

-- cellular automata cave (also the open waste with a lower fill)
-- the cellular automaton on grid G (w, h): rock = true; border cells stay rock
local function automaton(G, r, p)
	local w, h = G.w, G.h
	local rock = newGrid(w, h, true)
	for y = 4, h - 3 do
		for x = 4, w - 3 do
			rock[idx(G, x, y)] = r:int(1, 1000) <= p.fill * 1000
		end
	end
	local function count(g, x, y, rad)
		local n = 0
		for dy = -rad, rad do
			for dx = -rad, rad do
				local nx, ny = x + dx, y + dy
				if not inside(G, nx, ny) or g[idx(G, nx, ny)] then
					n = n + 1
				end
			end
		end
		return n
	end
	for step = 1, p.steps do
		local nextG = {}
		for y = 1, h do
			T()
			for x = 1, w do
				local i = idx(G, x, y)
				if x < 4 or y < 4 or x > w - 3 or y > h - 3 then
					nextG[i] = true
				else
					local r1 = count(rock, x, y, 1)
					if step <= p.steps - 2 then
						nextG[i] = r1 >= 5 or count(rock, x, y, 2) <= (p.spread or 2)
					else
						nextG[i] = r1 >= 5
					end
				end
			end
		end
		rock = nextG
	end
	return rock, count
end

local function caveLayout(F, r, p, required)
	local w, h = F.w, F.h
	local rock
	local s = p.scale or 1
	if s <= 1 then
		rock = automaton(F, r, p)
	else
		-- p.scale: the automaton on a grid s times coarser, scaled up and smoothed (p.smooth passes): the chambers
		-- and passages of a big layout come out s times wider instead of a fine maze
		local G = {w = floor((w + s - 1) / s), h = floor((h + s - 1) / s)}
		local coarse = automaton(G, r, p)
		rock = newGrid(w, h, true)
		for y = 1, h do
			for x = 1, w do
				rock[idx(F, x, y)] = coarse[idx(G, floor((x - 1) / s) + 1, floor((y - 1) / s) + 1)]
			end
		end
		for _ = 1, p.smooth or 1 do
			local nextG = {}
			for y = 1, h do
				T()
				for x = 1, w do
					local i = idx(F, x, y)
					if x < 4 or y < 4 or x > w - 3 or y > h - 3 then
						nextG[i] = true
					else
						local n = 0
						for dy = -1, 1 do
							for dx = -1, 1 do
								if rock[idx(F, x + dx, y + dy)] then
									n = n + 1
								end
							end
						end
						nextG[i] = n >= 5
					end
				end
			end
			rock = nextG
		end
	end
	F.open = {}
	for i = 1, w * h do
		F.open[i] = not rock[i] or nil
	end
	-- the boss chamber and the required points
	for _, q in ipairs(required) do
		carveDisc(F, q.x, q.y, q.r or 2, 3)
	end
	-- mixed layouts (p.rooms): ruined chambers cut into the cave, joined to it like any other pocket below
	F.rooms = {}
	if p.rooms then
		mixedRooms(F, r, p, required)
	end
	-- drop small pockets, join the rest to the largest
	local regs = regions(F, function(i) return F.open[i] end)
	local keep = {}
	for k, reg in ipairs(regs) do
		local needed = false
		for _, q in ipairs(required) do
			if reg.set[idx(F, q.x, q.y)] then
				needed = true
			end
		end
		for _, q in ipairs(F.rooms) do
			if reg.set[idx(F, q.cx, q.cy)] then
				needed = true
			end
		end
		if k == 1 or needed or reg.n >= (p.minRegion or 40) then
			keep[#keep + 1] = reg
		else
			for i in pairs(reg.set) do
				F.open[i] = nil
			end
		end
	end
	for k = 2, #keep do
		T()
		-- the nearest pair of cells (sampled) between this region and the open set so far
		local a = keep[k]
		local best, bi, bj = nil, nil, nil
		local mainCells = {}
		for i in pairs(keep[1].set) do
			mainCells[#mainCells + 1] = i
		end
		table.sort(mainCells)
		local own = {}
		for i in pairs(a.set) do
			own[#own + 1] = i
		end
		table.sort(own)
		local stepA = max(1, floor(#own / 60))
		local stepB = max(1, floor(#mainCells / 400))
		for s = 1, #own, stepA do
			T()
			local ax, ay = xy(F, own[s])
			for t = 1, #mainCells, stepB do
				local bx, by = xy(F, mainCells[t])
				local d = abs(ax - bx) + abs(ay - by)
				if not best or d < best then
					best, bi, bj = d, own[s], mainCells[t]
				end
			end
		end
		local ax, ay = xy(F, bi)
		local bx, by = xy(F, bj)
		tunnel(F, r, ax, ay, bx, by, p.tunnelRadius or 1)
		for i in pairs(a.set) do
			keep[1].set[i] = true
		end
	end
	-- single rock specks inside the open area open up (only adds walkable cells)
	for y = 4, h - 3 do
		T()
		for x = 4, w - 3 do
			local i = idx(F, x, y)
			if not F.open[i] then
				local n = 0
				for _, d in ipairs(D8) do
					if F.open[idx(F, x + d[1], y + d[2])] then
						n = n + 1
					end
				end
				if n >= 7 then
					F.open[i] = true
				end
			end
		end
	end
end

-- rooms joined by corridors (a spanning tree plus a few loops); the first room is the arrival room
local function roomsLayout(F, r, p, required, bossWanted)
	local w, h = F.w, F.h
	F.open = {}
	local rooms = {}
	local function overlaps(x1, y1, x2, y2)
		for _, q in ipairs(rooms) do
			if x1 - p.gap <= q.x2 and x2 + p.gap >= q.x1 and y1 - p.gap <= q.y2 and y2 + p.gap >= q.y1 then
				return true
			end
		end
		return false
	end
	-- a room of rw x rh; with an anchor the room covers the anchor (and the cell south of it) or is not placed
	local function place(rw, rh, kind, ax, ay)
		for t = 1, 400 do
			local x1, y1
			if ax then
				x1 = min(max(ax - r:int(1, rw - 2), 4), w - rw - 3)
				y1 = min(max(ay - r:int(1, rh - 3), 4), h - rh - 3)
			else
				x1 = r:int(4, w - rw - 3)
				y1 = r:int(4, h - rh - 3)
			end
			local x2, y2 = x1 + rw - 1, y1 + rh - 1
			local covers = not ax or (ax >= x1 and ax <= x2 and ay >= y1 and ay + 1 <= y2)
			if covers and not overlaps(x1, y1, x2, y2) then
				local q = {x1 = x1, y1 = y1, x2 = x2, y2 = y2, cx = floor((x1 + x2) / 2), cy = floor((y1 + y2) / 2), kind = kind}
				rooms[#rooms + 1] = q
				return q
			end
			if ax and t > 200 then
				-- give up the anchor's room; the anchor gets a corridor of its own below
				return nil
			end
		end
		return nil
	end
	-- the arrival room in the north-west, the boss room far from it, the required points get rooms of their own
	place(r:int(p.room[1], p.room[2]), r:int(p.room[1], p.room[2]), "arrival", required[1].x, required[1].y)
	if bossWanted then
		local bx, by = w - floor(p.bossRoom / 2) - 6, h - floor(p.bossRoom / 2) - 6
		if p.bossAnchor then
			bx, by = p.bossAnchor[1], p.bossAnchor[2]
		end
		place(p.bossRoom, p.bossRoom, "boss", bx, by)
	end
	for k = 2, #required do
		local q = required[k]
		if not q.boss then
			place(r:int(p.room[1], p.room[1] + 2), r:int(p.room[1], p.room[1] + 2), "link", q.x, q.y)
		end
	end
	local want = r:int(p.rooms[1], p.rooms[2])
	local tries = 0
	while #rooms < want and tries < want * 6 do
		tries = tries + 1
		T()
		place(r:int(p.room[1], p.room[2]), r:int(p.room[1], p.room[2]), "hunt")
	end
	F.roomIdx = {}
	for k, q in ipairs(rooms) do
		carveRect(F, q.x1, q.y1, q.x2, q.y2)
		for y = q.y1, q.y2 do
			for x = q.x1, q.x2 do
				F.roomIdx[idx(F, x, y)] = k
			end
		end
	end
	-- spanning tree (Prim) over the room centres, then loops
	local inTree, edges = {[1] = true}, {}
	local function dist(a, b)
		return abs(a.cx - b.cx) + abs(a.cy - b.cy)
	end
	for _ = 2, #rooms do
		T()
		local bestD, ba, bb
		for a = 1, #rooms do
			if inTree[a] then
				for b = 1, #rooms do
					if not inTree[b] then
						local d = dist(rooms[a], rooms[b])
						if not bestD or d < bestD then
							bestD, ba, bb = d, a, b
						end
					end
				end
			end
		end
		if not bb then
			break
		end
		inTree[bb] = true
		edges[#edges + 1] = {ba, bb}
	end
	-- loops: extra corridors between rooms that are close on the map but far apart in the tree (3+ hops), so a
	-- party can run a circuit (the guide asks every hunt for one)
	local loops = r:int(p.loops[1], p.loops[2])
	local adj = {}
	for _, e in ipairs(edges) do
		adj[e[1]] = adj[e[1]] or {}
		adj[e[2]] = adj[e[2]] or {}
		adj[e[1]][#adj[e[1]] + 1] = e[2]
		adj[e[2]][#adj[e[2]] + 1] = e[1]
	end
	local function hops(a, b)
		local seen, queue, head = {[a] = 0}, {a}, 1
		while head <= #queue do
			local c = queue[head]
			head = head + 1
			for _, n in ipairs(adj[c] or {}) do
				if seen[n] == nil then
					seen[n] = seen[c] + 1
					queue[#queue + 1] = n
				end
			end
		end
		return seen[b] or 99
	end
	local pairs_ = {}
	for a = 1, #rooms do
		T()
		for b = a + 1, #rooms do
			if hops(a, b) >= 3 then
				pairs_[#pairs_ + 1] = {a, b, dist(rooms[a], rooms[b])}
			end
		end
	end
	table.sort(pairs_, function(x, y)
		if x[3] ~= y[3] then
			return x[3] < y[3]
		end
		return x[1] * 1000 + x[2] < y[1] * 1000 + y[2]
	end)
	local used = {}
	for _, pr in ipairs(pairs_) do
		if loops <= 0 then
			break
		end
		if not used[pr[1]] and not used[pr[2]] and hops(pr[1], pr[2]) >= 3 and r:chance(70) then
			edges[#edges + 1] = {pr[1], pr[2]}
			adj[pr[1]][#adj[pr[1]] + 1] = pr[2]
			adj[pr[2]][#adj[pr[2]] + 1] = pr[1]
			used[pr[1]], used[pr[2]] = true, true
			loops = loops - 1
		end
	end
	local half = floor((p.corridor - 1) / 2)
	F.corridor = {}
	local function hseg(y, x1, x2)
		for x = min(x1, x2), max(x1, x2) do
			for k = -half, p.corridor - 1 - half do
				local i = idx(F, x, y + k)
				if not F.open[i] then
					F.corridor[i] = true
				end
				F.open[i] = true
			end
		end
	end
	local function vseg(x, y1, y2)
		for y = min(y1, y2), max(y1, y2) do
			for k = -half, p.corridor - 1 - half do
				local i = idx(F, x + k, y)
				if not F.open[i] then
					F.corridor[i] = true
				end
				F.open[i] = true
			end
		end
	end
	-- an L: horizontal then vertical or the other way round
	local function corridorL(ax, ay, bx, by)
		if r:chance(50) then
			hseg(ay, ax, bx)
			vseg(bx, ay, by)
		else
			vseg(ax, ay, by)
			hseg(by, ax, bx)
		end
	end
	for _, e in ipairs(edges) do
		T()
		local a, b = rooms[e[1]], rooms[e[2]]
		corridorL(a.cx, a.cy, b.cx, b.cy)
	end
	-- a required point outside every room gets a corridor to the nearest room
	for _, q in ipairs(required) do
		local inRoom = false
		for _, room in ipairs(rooms) do
			if q.x >= room.x1 and q.x <= room.x2 and q.y >= room.y1 and q.y + 1 <= room.y2 then
				inRoom = true
			end
		end
		if not inRoom and #rooms > 0 then
			local best, bd
			for _, room in ipairs(rooms) do
				local d = abs(room.cx - q.x) + abs(room.cy - q.y)
				if not bd or d < bd then
					best, bd = room, d
				end
			end
			carveRect(F, q.x - 1, q.y - 1, q.x + 1, q.y + 2)
			corridorL(q.x, q.y, best.cx, best.cy)
		end
	end
	F.rooms = rooms
end

-- ====================================================================== pieces
-- Border pieces of one tile from which of its 8 neighbours belong to the higher ground. Names follow the map editor:
-- n, e, s, w = that side only; cnw, cne, csw, cse = that corner only (outer corner); dnw, dne, dsw, dse = the two
-- sides and the corner between them (inner corner). The pieces were checked against the live map
-- (tools/map/derive_borders.py edges): the piece is named after the side where the higher ground lies.
function A.borderPieces(n, e, s, w, ne, nw, se, sw)
	local out, used = {}, {}
	local function pair(name, a, b)
		out[#out + 1] = name
		used[a], used[b] = true, true
	end
	if n and w then
		pair("dnw", "n", "w")
	end
	if n and e and not used.n then
		pair("dne", "n", "e")
	end
	if s and e and not used.e then
		pair("dse", "s", "e")
	end
	if s and w and not used.s and not used.w then
		pair("dsw", "s", "w")
	end
	for _, side in ipairs({{"n", n}, {"e", e}, {"s", s}, {"w", w}}) do
		if side[2] and not used[side[1]] then
			out[#out + 1] = side[1]
			used[side[1]] = true
		end
	end
	if nw and not used.n and not used.w then
		out[#out + 1] = "cnw"
	end
	if ne and not used.n and not used.e then
		out[#out + 1] = "cne"
	end
	if sw and not used.s and not used.w then
		out[#out + 1] = "csw"
	end
	if se and not used.s and not used.e then
		out[#out + 1] = "cse"
	end
	return out
end

-- The wall piece of one wall tile from which of its 4 neighbours are walls too. Measured on the live map
-- (tools/map/derive_borders.py walls, stone and ruin walls): a run east-west is horizontal, north-south vertical, the
-- north-west corner of a room (walls east and south) a pole, the south-east corner (walls north and west) the corner
-- piece, the south-west corner (north and east) vertical, the north-east corner (south and west) horizontal.
function A.wallPiece(n, e, s, w)
	local h, v = e or w, n or s
	if not h and not v then
		return "pole"
	end
	if n and w then
		return "corner"
	end
	if h and v then
		if e and s and not n and not w then
			return "pole"
		end
		if n and e and not w then
			return "vertical"
		end
		if s and w and not n then
			return "horizontal"
		end
		return "corner"
	end
	return h and "horizontal" or "vertical"
end

-- multipliers that make a monster of level `native` behave like one of level `target` (the engine's own level
-- formulas: health x(1 + 0.0074 L), damage x(1 + 0.0015 L), experience x0.03 L; config.lua monsterBonus*)
function A.levelScale(native, target, k)
	k = k or {}
	local hp, dmg = k.health or 0.0074, k.damage or 0.0015
	native = max(1, native or 1)
	target = max(1, target or native)
	return {
		health = (1 + hp * target) / (1 + hp * native),
		damage = (1 + dmg * target) / (1 + dmg * native),
		experience = target / native
	}
end

-- ====================================================================== palette helpers
local function resolve(theme, opts, kind)
	-- the theme with its dark overrides when the dark tile set is installed; a theme used by several layout kinds
	-- (the rift themes) may hold byKind[kind] overrides, and so may its dark part
	local byKind = theme.byKind and kind and theme.byKind[kind]
	local dark = opts and opts.dark and theme.dark
	local darkKind = dark and dark.byKind and kind and dark.byKind[kind]
	if not (dark or byKind) then
		return theme
	end
	local out = {}
	for _, src in ipairs({theme, byKind or {}, dark or {}, darkKind or {}}) do
		for k, v in pairs(src) do
			out[k] = v
		end
	end
	return out
end

-- an id or a dark tile name -> id
local function idOf(cfg, opts, v)
	if type(v) == "number" then
		return v
	end
	local ids = (opts and opts.darkIds) or cfg.darkIds or {}
	return ids[v]
end

local function weightedIds(cfg, opts, rows)
	local out = {}
	for _, row in ipairs(rows or {}) do
		local id = idOf(cfg, opts, row[1])
		if id then
			out[#out + 1] = {id, row[2]}
		end
	end
	return out
end

-- ====================================================================== generation
local function point(F, i, z)
	local x, y = xy(F, i)
	return {x = x, y = y, z = z}
end

local function absPos(model, F, x, y)
	return {x = model.origin.x + x - 1, y = model.origin.y + y - 1, z = F.z}
end

-- the floors' link anchors: a hole on floor k at (x, y) with the climb arrival (x, y + 1), a ladder on floor k + 1
local function pickLinks(r, def, w, h)
	local links = {}
	if def.links then
		-- def.links = {{floor = k, x, y}, ...}: the link anchors given (the area planner, tools/area_planner.py); no draw
		for _, l in ipairs(def.links) do
			links[#links + 1] = {floor = l.floor, x = l.x, y = l.y}
		end
		return links
	end
	local per = def.linksPerFloor or 1
	for k = 1, (def.floors or 1) - 1 do
		for j = 1, per do
			local x, y
			-- spread: the first link of a floor in the far half, the second elsewhere
			local tries = 0
			repeat
				tries = tries + 1
				if (k + j) % 2 == 0 then
					x, y = r:int(floor(w / 2), w - 10), r:int(10, h - 11)
				else
					x, y = r:int(10, floor(w / 2)), r:int(floor(h / 2), h - 11)
				end
				-- def.linkAvoid = {{x, y, r}, ...}: no link within r cells of these points (the rifts' arena); only
				-- drawn again when the def asks for it
				local near = false
				for _, q in ipairs(def.linkAvoid or {}) do
					if abs(x - q[1]) <= q[3] and abs(y - q[2]) <= q[3] then
						near = true
					end
				end
			until not near or tries >= 30
			links[#links + 1] = {floor = k, x = x, y = y}
		end
	end
	return links
end

-- mark rings (Chebyshev radius) around a point
local function ring(F, x, y, rad, set)
	for dy = -rad, rad do
		for dx = -rad, rad do
			if inside(F, x + dx, y + dy) then
				set[idx(F, x + dx, y + dy)] = true
			end
		end
	end
end

-- removing cell i keeps its walkable neighbours joined (they form one group around it): a "simple point"
local function simple(F, i)
	local x, y = xy(F, i)
	local ringW = {}
	for k, d in ipairs(D8) do
		local nx, ny = x + d[1], y + d[2]
		ringW[k] = inside(F, nx, ny) and F.walk[idx(F, nx, ny)] or false
	end
	-- count groups of walkable ring cells; two ring cells touch when they are 8-neighbours of each other
	local groups, seen = 0, {}
	for k = 1, 8 do
		if ringW[k] and not seen[k] then
			groups = groups + 1
			local stack = {k}
			seen[k] = true
			while #stack > 0 do
				local a = table.remove(stack)
				local ax, ay = D8[a][1], D8[a][2]
				for b = 1, 8 do
					if ringW[b] and not seen[b] then
						local bx, by = D8[b][1], D8[b][2]
						if abs(ax - bx) <= 1 and abs(ay - by) <= 1 then
							seen[b] = true
							stack[#stack + 1] = b
						end
					end
				end
			end
		end
	end
	return groups <= 1
end

local function blockCell(F, i)
	F.walk[i] = nil
	F.blocked[i] = true
end

-- an irregular blob around (cx, cy): one disc of radius rad and 1-3 smaller lobes beside it, with a rough rim;
-- calls fn(i) once for each cell
local function blob(F, r, cx, cy, rad, fn)
	local lobes = {{cx, cy, rad}}
	for _ = 1, r:int(1, 3) do
		local d = D8[r:int(1, 8)]
		local off = r:int(1, max(1, rad))
		lobes[#lobes + 1] = {cx + d[1] * off, cy + d[2] * off, max(1, rad - r:int(0, 1))}
	end
	local seen = {}
	for _, lb in ipairs(lobes) do
		local lr = lb[3]
		for dy = -lr - 1, lr + 1 do
			for dx = -lr - 1, lr + 1 do
				local x, y = lb[1] + dx, lb[2] + dy
				if inside(F, x, y) then
					local i = idx(F, x, y)
					if not seen[i] and dx * dx + dy * dy <= lr * lr + r:int(0, lr) then
						seen[i] = true
						fn(i)
					end
				end
			end
		end
	end
end

-- a planned layout (the area planner, tools/area_planner.py): the zones, paths and spots of one floor are given, in
-- local cells. p.zones = {{x1, y1, x2, y2, shape = "room" | "cave" | "arena", kind = "hunt" | "boss" | ..., ragged}},
-- p.paths = {{width = n, style = "corridor" | "tunnel" | "wild", points = {{x, y}, ...}}}, p.spots = {{x, y, r}} (landings
-- under a hole). Zones become F.rooms (room floors, paths kept free, spawn caps); corridor cells F.corridor.
local function plannedLayout(F, r, p, required)
	F.open, F.rooms, F.roomIdx, F.corridor = {}, {}, {}, {}
	local function mark(k, i)
		F.open[i] = true
		F.roomIdx[i] = k
	end
	for k, z in ipairs(p.zones or {}) do
		T()
		local x1, y1, x2, y2 = z.x1, z.y1, z.x2, z.y2
		local cx, cy = floor((x1 + x2) / 2), floor((y1 + y2) / 2)
		local function inZone(x, y)
			return x >= x1 and x <= x2 and y >= y1 and y <= y2 and inside(F, x, y)
		end
		if z.shape == "cave" then
			-- blobs along the long side, kept inside the zone; the centre always open
			local w, h = x2 - x1 + 1, y2 - y1 + 1
			local rad = max(1, floor((min(w, h) - 1) / 2) - 1)
			local n = max(1, floor(max(w, h) / max(2, 2 * rad)) + 1)
			for j = 0, n - 1 do
				local bx, by
				if w >= h then
					bx, by = x1 + rad + floor(j * max(0, w - 1 - 2 * rad) / max(1, n - 1)), cy
				else
					bx, by = cx, y1 + rad + floor(j * max(0, h - 1 - 2 * rad) / max(1, n - 1))
				end
				blob(F, r, bx, by, rad, function(i)
					local x, y = xy(F, i)
					if inZone(x, y) then
						mark(k, i)
					end
				end)
			end
			for dy = -1, 1 do
				for dx = -1, 1 do
					if inZone(cx + dx, cy + dy) then
						mark(k, idx(F, cx + dx, cy + dy))
					end
				end
			end
		elseif z.shape == "arena" then
			local rad = floor((min(x2 - x1, y2 - y1)) / 2)
			for y = y1, y2 do
				for x = x1, x2 do
					local dx, dy = x - cx, y - cy
					if inZone(x, y) and dx * dx + dy * dy <= rad * rad + rad then
						mark(k, idx(F, x, y))
					end
				end
			end
		else
			for y = y1, y2 do
				for x = x1, x2 do
					if inZone(x, y) then
						mark(k, idx(F, x, y))
					end
				end
			end
		end
		if z.ragged then
			-- ragged sides: each side bites in by a depth that wanders 0-4 tiles along it (paths carve after this)
			local deep = min(4, floor(min(x2 - x1, y2 - y1) / 6))
			local function bite(n, cut)
				local d = r:int(0, deep)
				for j = 0, n - 1 do
					d = min(deep, max(0, d + r:int(-1, 1)))
					for e = 0, d - 1 do
						local i = cut(j, e)
						if i and F.roomIdx[i] == k then
							F.open[i], F.roomIdx[i] = nil, nil
						end
					end
				end
			end
			local function at(x, y)
				return inZone(x, y) and idx(F, x, y) or nil
			end
			bite(x2 - x1 + 1, function(j, e) return at(x1 + j, y1 + e) end)
			bite(x2 - x1 + 1, function(j, e) return at(x1 + j, y2 - e) end)
			bite(y2 - y1 + 1, function(j, e) return at(x1 + e, y1 + j) end)
			bite(y2 - y1 + 1, function(j, e) return at(x2 - e, y1 + j) end)
		end
		F.rooms[k] = {x1 = x1, y1 = y1, x2 = x2, y2 = y2, cx = cx, cy = cy, kind = z.kind or "hunt"}
	end
	local function open(i)
		if not F.open[i] then
			F.corridor[i] = true
		end
		F.open[i] = true
	end
	for _, pa in ipairs(p.paths or {}) do
		T()
		local wd = max(1, pa.width or 3)
		local half = floor((wd - 1) / 2)
		local pts = pa.points or {}
		for j = 1, #pts - 1 do
			local ax, ay, bx, by = pts[j][1], pts[j][2], pts[j + 1][1], pts[j + 1][2]
			if pa.style == "tunnel" or pa.style == "wild" then
				local before = {}
				for i in pairs(F.open) do
					before[i] = true
				end
				tunnel(F, r, ax, ay, bx, by, half, pa.style == "wild")
				for i in pairs(F.open) do
					if not before[i] then
						F.corridor[i] = true
					end
				end
			else
				-- straight runs (horizontal, then vertical when the points are not in line)
				for x = min(ax, bx), max(ax, bx) do
					for d = -half, wd - 1 - half do
						if inside(F, x, ay + d) then
							open(idx(F, x, ay + d))
						end
					end
				end
				for y = min(ay, by), max(ay, by) do
					for d = -half, wd - 1 - half do
						if inside(F, bx + d, y) then
							open(idx(F, bx + d, y))
						end
					end
				end
			end
		end
	end
	for _, s in ipairs(p.spots or {}) do
		carveDisc(F, s[1], s[2], s[3] or 1, 3)
	end
	for _, q in ipairs(required) do
		carveDisc(F, q.x, q.y, min(q.r or 1, 1), 3)
	end
end

-- the generator of one floor
local function buildFloor(cfg, def, theme, opts, r, F, required, bossWanted)
	local lay = def.layout or {}
	if lay.plan then
		plannedLayout(F, r, lay.plan[F.k] or {}, required)
	elseif def.kind == "dungeon" then
		roomsLayout(F, r, lay, required, bossWanted)
	else
		caveLayout(F, r, lay, required)
	end
	-- cells: OPEN = the 8-neighbourhood of the design; rock (or walls in a dungeon) around it
	F.cell = newGrid(F.w, F.h, VOID)
	for i = 1, F.w * F.h do
		T2048()
		if F.open[i] then
			F.cell[i] = OPEN
		end
	end
	local function nearOpen(x, y, rad)
		for dy = -rad, rad do
			for dx = -rad, rad do
				local nx, ny = x + dx, y + dy
				if inside(F, nx, ny) and F.open[idx(F, nx, ny)] then
					return true
				end
			end
		end
		return false
	end
	if def.kind == "dungeon" then
		for y = 1, F.h do
			T()
			for x = 1, F.w do
				local i = idx(F, x, y)
				if F.cell[i] == VOID and nearOpen(x, y, 1) then
					F.cell[i] = WALL
				end
			end
		end
	else
		-- the floor reaches one cell past the design (those cells carry the rock edge pieces); rock rim behind it
		local grow = {}
		for y = 1, F.h do
			T()
			for x = 1, F.w do
				local i = idx(F, x, y)
				if F.cell[i] == VOID and nearOpen(x, y, 1) then
					grow[#grow + 1] = i
				end
			end
		end
		for _, i in ipairs(grow) do
			F.cell[i] = OPEN
		end
		-- rock within rimWidth of the floor, and every enclosed rock island whole (no holes of void inside the area);
		-- deep rock that reaches the grid border stays void (nothing is built there)
		local rim = theme.rimWidth or 2
		local deep = {}
		for y = 1, F.h do
			T()
			for x = 1, F.w do
				local i = idx(F, x, y)
				if F.cell[i] == VOID then
					if nearOpen(x, y, 1 + rim) then
						F.cell[i] = ROCK
					else
						deep[i] = true
					end
				end
			end
		end
		local outside = {}
		for y = 1, F.h do
			T()
			for x = 1, F.w do
				local i = idx(F, x, y)
				if deep[i] and not outside[i] and (x == 1 or y == 1 or x == F.w or y == F.h) then
					for j in pairs(flood(F, i, function(k) return deep[k] end)) do
						outside[j] = true
					end
				end
			end
		end
		for i in pairs(deep) do
			if not outside[i] then
				F.cell[i] = ROCK
			end
		end
	end
	-- walkable: open cells with no rock or wall around them (the edge cells carry blocking pieces)
	F.walk, F.blocked = {}, {}
	for y = 1, F.h do
		T()
		for x = 1, F.w do
			local i = idx(F, x, y)
			if F.cell[i] == OPEN then
				local ok = true
				for _, d in ipairs(D8) do
					local nx, ny = x + d[1], y + d[2]
					local c = inside(F, nx, ny) and F.cell[idx(F, nx, ny)] or VOID
					if c ~= OPEN and def.kind ~= "dungeon" then
						ok = false
					end
				end
				if ok then
					F.walk[i] = true
				end
			end
		end
	end
	-- keep the region of the first required point; anything walkable elsewhere is closed with rock (a planned layout
	-- keeps every region that holds a zone or a required point: zones may be joined by a teleport only)
	local main = flood(F, idx(F, required[1].x, required[1].y), function(i) return F.walk[i] end)
	if lay.plan then
		local anchors = {}
		for _, q in ipairs(F.rooms or {}) do
			anchors[#anchors + 1] = idx(F, q.cx, q.cy)
		end
		for _, q in ipairs(required) do
			anchors[#anchors + 1] = idx(F, q.x, q.y)
		end
		for _, a in ipairs(anchors) do
			if F.walk[a] and not main[a] then
				for i in pairs(flood(F, a, function(j) return F.walk[j] end)) do
					main[i] = true
				end
			end
		end
	end
	for i in pairs(F.walk) do
		if not main[i] then
			F.walk[i] = nil
			F.blocked[i] = true
		end
	end
end

-- outer corners of a shape (a cell with two perpendicular sides in the shape and the cell between them too) are
-- cut with chance pct, so blobs read round instead of boxy; is(i) tells the shape, cut(i) removes a cell
local function chamfer(F, r, cells, is, cut, pct)
	for _, i in ipairs(cells) do
		if is(i) then
			local x, y = xy(F, i)
			local s = {}
			for k, d in ipairs(D4) do
				s[k] = is(idx(F, x + d[1], y + d[2]))
			end
			local n = (s[1] and 1 or 0) + (s[2] and 1 or 0) + (s[3] and 1 or 0) + (s[4] and 1 or 0)
			if n == 2 and not (s[1] and s[3]) and not (s[2] and s[4]) and r:chance(pct) then
				cut(i)
			end
		end
	end
end

-- grounds, patches, pools: fills F.fam (family name per cell) and F.ground (id per cell)
local function paintGrounds(cfg, def, theme, opts, r, F, reserved)
	F.fam, F.ground, F.pool = {}, {}, {}
	local base = theme.floor
	local rooms = def.kind == "dungeon" and F.rooms or {}
	-- dungeon rooms each get a floor family of their own; corridors and walls the corridor floor
	local roomFam = {}
	if def.kind == "mixed" and theme.mixedFloors then
		rooms = F.rooms or {}
	end
	if def.kind == "dungeon" or (def.kind == "mixed" and theme.mixedFloors) then
		for k, q in ipairs(rooms) do
			local list = (def.kind == "mixed" and theme.mixedFloors) or theme.roomFloors or {base}
			local fam = list[r:int(1, #list)]
			if q.kind == "boss" and theme.bossFloor then
				fam = theme.bossFloor
			end
			for y = q.y1, q.y2 do
				for x = q.x1, q.x2 do
					roomFam[idx(F, x, y)] = fam
				end
			end
		end
	end
	for i = 1, F.w * F.h do
		T2048()
		local c = F.cell[i]
		if c == OPEN or c == WALL then
			F.fam[i] = roomFam[i] or base
		elseif c == ROCK then
			F.fam[i] = theme.rock
		end
	end
	-- patches of a second walkable ground (blobs on walkable cells, never next to another patch family)
	local function otherNear(i, fam)
		local x, y = xy(F, i)
		for _, d in ipairs(D8) do
			local nx, ny = x + d[1], y + d[2]
			if inside(F, nx, ny) then
				local f = F.fam[idx(F, nx, ny)]
				if f and f ~= fam and f ~= base and f ~= theme.rock then
					return true
				end
				if F.pool[idx(F, nx, ny)] then
					return true
				end
			end
		end
		return false
	end
	local walkList = {}
	for i = 1, F.w * F.h do
		T2048()
		if F.walk[i] then
			walkList[#walkList + 1] = i
		end
	end
	local nWalk = #walkList
	for _, pt in ipairs(theme.patches or {}) do
		local target = floor(nWalk * pt.share)
		local painted, guard = 0, 0
		while painted < target and guard < (pt.tries or 200) and nWalk > 0 do
			guard = guard + 1
			T()
			local c = walkList[r:int(1, nWalk)]
			local cx, cy = xy(F, c)
			local rad = r:int(pt.radius[1], pt.radius[2])
			local cells = {}
			blob(F, r, cx, cy, rad, function(i)
				if F.walk[i] and F.fam[i] == base and not reserved[i] then
					cells[#cells + 1] = i
				end
			end)
			-- smooth: a cell stays when at least 2 of its 4 sides are in the blob (no single-cell spikes)
			local inBlob = {}
			for _, i in ipairs(cells) do
				inBlob[i] = true
			end
			for _, i in ipairs(cells) do
				local x, y = xy(F, i)
				local n = 0
				for _, d in ipairs(D4) do
					if inBlob[idx(F, x + d[1], y + d[2])] then
						n = n + 1
					end
				end
				if (n >= 2 or i == c) and not otherNear(i, pt.family) then
					F.fam[i] = pt.family
					painted = painted + 1
				end
			end
			chamfer(F, r, cells, function(i) return F.fam[i] == pt.family end, function(i)
				F.fam[i] = base
				painted = painted - 1
			end, 60)
		end
	end
	-- pools: blocking grounds (lava) inside the walkable area, cell by cell so the area stays joined
	local function unpool(i)
		F.pool[i] = nil
		F.blocked[i] = nil
		F.walk[i] = true
		F.fam[i] = base
	end
	for _, pl in ipairs(theme.pools or {}) do
		local target = floor(nWalk * pl.share)
		local made, guard = 0, 0
		while made < target and guard < (pl.tries or 300) and nWalk > 0 do
			guard = guard + 1
			T()
			local c = walkList[r:int(1, nWalk)]
			local cx, cy = xy(F, c)
			local rad = r:int(pl.radius[1], pl.radius[2])
			local cells, placed = {}, {}
			blob(F, r, cx, cy, rad, function(i)
				cells[#cells + 1] = i
			end)
			table.sort(cells, function(a, b)
				local ax, ay = xy(F, a)
				local bx, by = xy(F, b)
				local da = (ax - cx) * (ax - cx) + (ay - cy) * (ay - cy)
				local db = (bx - cx) * (bx - cx) + (by - cy) * (by - cy)
				if da ~= db then
					return da < db
				end
				return a < b
			end)
			for _, i in ipairs(cells) do
				local x, y = xy(F, i)
				local ok = F.walk[i] and F.fam[i] == base and not reserved[i] and not F.path[i]
				if ok then
					-- every neighbour walkable floor or pool (a pool never touches rock or a patch)
					for _, d in ipairs(D8) do
						local j = idx(F, x + d[1], y + d[2])
						if not (F.walk[j] or F.pool[j]) or (F.fam[j] ~= base and not F.pool[j]) or reserved[j] then
							ok = false
						end
					end
				end
				if ok and simple(F, i) then
					blockCell(F, i)
					F.pool[i] = true
					F.fam[i] = pl.family
					placed[#placed + 1] = i
				end
			end
			chamfer(F, r, placed, function(i) return F.pool[i] end, unpool, 70)
			-- no slivers: a pool cell needs two pool sides, a pool at least 4 cells (else the floor comes back)
			local changed = true
			while changed do
				changed = false
				for _, i in ipairs(placed) do
					if F.pool[i] then
						local x, y = xy(F, i)
						local n = 0
						for _, d in ipairs(D4) do
							if F.pool[idx(F, x + d[1], y + d[2])] then
								n = n + 1
							end
						end
						if n < 2 then
							unpool(i)
							changed = true
						end
					end
				end
			end
			local left = 0
			for _, i in ipairs(placed) do
				if F.pool[i] then
					left = left + 1
				end
			end
			if left < 4 then
				for _, i in ipairs(placed) do
					if F.pool[i] then
						unpool(i)
					end
				end
				left = 0
			end
			made = made + left
		end
	end
	-- ground ids: a weighted pick of the family's grounds (several ids per block, as the guide asks)
	for i = 1, F.w * F.h do
		T2048()
		local fam = F.fam[i]
		if fam then
			local fd = cfg.families[fam]
			F.ground[i] = r:weighted(weightedIds(cfg, opts, fd.grounds))
		end
	end
end

-- borders over each tile from the higher families around it, then the wall pieces of a dungeon
local function paintBorders(cfg, def, theme, opts, F)
	F.items = {}
	for i = 1, F.w * F.h do
		T2048()
		F.items[i] = {}
	end
	local fams = cfg.families
	for y = 1, F.h do
		T()
		for x = 1, F.w do
			local i = idx(F, x, y)
			local f = F.fam[i]
			if f then
				local zf = fams[f].z
				local over = {}
				for _, d in ipairs(D8) do
					local nx, ny = x + d[1], y + d[2]
					local g = inside(F, nx, ny) and F.fam[idx(F, nx, ny)] or nil
					if g and g ~= f and fams[g].z > zf and not over[g] then
						local set = cfg.borders[g] and (cfg.borders[g][f] or cfg.borders[g]["*"])
						if set then
							over[g] = set
						end
					end
				end
				local list = {}
				for g, set in pairs(over) do
					list[#list + 1] = {g = g, set = set}
				end
				table.sort(list, function(a, b)
					return fams[a.g].z < fams[b.g].z
				end)
				for _, e in ipairs(list) do
					local function is(dx, dy)
						local nx, ny = x + dx, y + dy
						return inside(F, nx, ny) and F.fam[idx(F, nx, ny)] == e.g
					end
					local pieces = A.borderPieces(is(0, -1), is(1, 0), is(0, 1), is(-1, 0), is(1, -1), is(-1, -1), is(1, 1),
						is(-1, 1))
					local set = cfg.pieces[e.set]
					for _, name in ipairs(pieces) do
						local id = idOf(cfg, opts, set[name])
						if id then
							local list2 = F.items[i]
							list2[#list2 + 1] = id
						end
					end
				end
			end
		end
	end
	if def.kind == "dungeon" then
		local ws = cfg.walls[theme.wall]
		for y = 1, F.h do
			T()
			for x = 1, F.w do
				local i = idx(F, x, y)
				if F.cell[i] == WALL then
					local function isW(dx, dy)
						local nx, ny = x + dx, y + dy
						return inside(F, nx, ny) and F.cell[idx(F, nx, ny)] == WALL
					end
					local kind = A.wallPiece(isW(0, -1), isW(1, 0), isW(0, 1), isW(-1, 0))
					F.wallKind = F.wallKind or {}
					F.wallKind[i] = kind
				end
			end
		end
		F.wallSet = ws
	end
end

-- paths: the shortest walks from the arrival to the links, the boss and the rooms (kept free of obstacles)
local function markPaths(F, from, targets, fast)
	F.path = {}
	if fast then
		-- one breadth-first search from the entry and a walk back along it for each target (big layouts: the rifts)
		local parent, queue, head = {[from] = from}, {from}, 1
		while head <= #queue do
			T2048()
			local i = queue[head]
			head = head + 1
			local x, y = xy(F, i)
			for _, d in ipairs(D8) do
				local nx, ny = x + d[1], y + d[2]
				if inside(F, nx, ny) then
					local j = idx(F, nx, ny)
					if parent[j] == nil and F.walk[j] then
						parent[j] = i
						queue[#queue + 1] = j
					end
				end
			end
		end
		for _, t in ipairs(targets) do
			local i = parent[t] and t or nil
			while i and not F.path[i] do
				F.path[i] = true
				i = i ~= from and parent[i] or nil
			end
		end
		F.path[from] = true
		return
	end
	for _, t in ipairs(targets) do
		T()
		local p = pathBetween(F, from, t, function(i) return F.walk[i] end)
		for _, i in ipairs(p or {}) do
			F.path[i] = true
		end
	end
end

local function addItem(F, i, id)
	local list = F.items[i]
	list[#list + 1] = id
end

-- decoration: clusters of walkable pieces, single pieces, blocking obstacles; never on paths or reserved cells
local function decorate(cfg, theme, opts, r, F, reserved, stats)
	local walkList = {}
	for i = 1, F.w * F.h do
		T2048()
		if F.walk[i] then
			walkList[#walkList + 1] = i
		end
	end
	local n = #walkList
	if n == 0 then
		return
	end
	local deco = theme.decor or {}
	local hasDeco = {}
	local function free(i)
		return F.walk[i] and not reserved[i] and not F.path[i] and not hasDeco[i]
	end
	-- 1. clusters
	local clusters = deco.clusters or {}
	for _, cl in ipairs(clusters) do
		local count = floor(n * cl.per1000 / 1000)
		local rows = weightedIds(cfg, opts, cl.items)
		for _ = 1, count do
			T2048()
			local c = walkList[r:int(1, n)]
			local cx, cy = xy(F, c)
			local k = r:int(cl.size[1], cl.size[2])
			for _ = 1, k * 3 do
				if k <= 0 then
					break
				end
				local x, y = cx + r:int(-cl.radius, cl.radius), cy + r:int(-cl.radius, cl.radius)
				if inside(F, x, y) then
					local i = idx(F, x, y)
					if free(i) and #rows > 0 then
						addItem(F, i, r:weighted(rows))
						hasDeco[i] = true
						stats.deco = stats.deco + 1
						k = k - 1
					end
				end
			end
		end
	end
	-- 2. single walkable pieces, spread evenly: one draw per 4x4 block cell list
	local rows = weightedIds(cfg, opts, deco.scatter)
	local share = deco.share or 0
	if #rows > 0 and share > 0 then
		for _, i in ipairs(walkList) do
			T2048()
			if free(i) and r:int(1, 10000) <= share * 10000 then
				addItem(F, i, r:weighted(rows))
				hasDeco[i] = true
				stats.deco = stats.deco + 1
			end
		end
	end
	-- 3. blocking obstacles (boulders, dead trees): off the paths, never next to another one, the area stays joined
	local obs = weightedIds(cfg, opts, theme.obstacles and theme.obstacles.items)
	local oshare = theme.obstacles and theme.obstacles.share or 0
	if #obs > 0 and oshare > 0 then
		local order = {}
		for k = 1, n do
			order[k] = walkList[k]
		end
		r:shuffle(order)
		local target = floor(n * oshare)
		local made = 0
		for _, i in ipairs(order) do
			if made >= target then
				break
			end
			T2048()
			if free(i) then
				local x, y = xy(F, i)
				local ok = true
				for _, d in ipairs(D8) do
					local j = idx(F, x + d[1], y + d[2])
					if not F.walk[j] or reserved[j] then
						ok = false
					end
				end
				if ok and simple(F, i) then
					addItem(F, i, r:weighted(obs))
					blockCell(F, i)
					hasDeco[i] = true
					stats.deco = stats.deco + 1
					made = made + 1
				end
			end
		end
	end
	F.hasDeco = hasDeco
end

-- pieces against the walls (a walkable cell next to the edge), spaced out: the lights, then the furniture (props);
-- in a dungeon never in a corridor (they would narrow it), only in the rooms
local function edgePieces(cfg, theme, opts, r, F, reserved, stats, L, statKey)
	if not L then
		return
	end
	local rows = weightedIds(cfg, opts, L.items)
	if #rows == 0 then
		return
	end
	local cand, nWalk = {}, 0
	for i = 1, F.w * F.h do
		T2048()
		if F.walk[i] then
			nWalk = nWalk + 1
			local x, y = xy(F, i)
			local edge = false
			for _, d in ipairs(D4) do
				local j = idx(F, x + d[1], y + d[2])
				if not F.walk[j] and not F.pool[j] then
					edge = true
				end
			end
			if edge and not reserved[i] and not F.path[i] and not F.hasDeco[i] and not (F.corridor and F.corridor[i]) then
				cand[#cand + 1] = i
			end
		end
	end
	r:shuffle(cand)
	local target = floor(nWalk * L.per100 / 100 + 0.5)
	local placed = {}
	local made = 0
	for _, i in ipairs(cand) do
		if made >= target then
			break
		end
		T2048()
		local x, y = xy(F, i)
		local near = false
		for _, p in ipairs(placed) do
			if abs(p[1] - x) < L.spacing and abs(p[2] - y) < L.spacing then
				near = true
				break
			end
		end
		if not near and F.walk[i] and not F.hasDeco[i] and simple(F, i) then
			addItem(F, i, r:weighted(rows))
			if L.blocking ~= false then
				blockCell(F, i)
			end
			F.hasDeco[i] = true
			placed[#placed + 1] = {x, y}
			made = made + 1
		end
	end
	stats[statKey] = stats[statKey] + made
end

-- spawn points: Poisson-disc spread over the walkable cells away from the arrival, holes and ladders
local function spawns(cfg, def, r, F, safe, model, floorNo)
	local sp = def.spawns
	local cand = {}
	local hunt = 0
	for i = 1, F.w * F.h do
		T2048()
		if F.walk[i] and not safe[i] then
			hunt = hunt + 1
			cand[#cand + 1] = i
		end
	end
	r:shuffle(cand)
	-- in a dungeon the rooms fill first, the corridors only take what the rooms cannot hold
	if F.corridor then
		local rooms, halls = {}, {}
		for _, i in ipairs(cand) do
			if F.corridor[i] then
				halls[#halls + 1] = i
			else
				rooms[#rooms + 1] = i
			end
		end
		for _, i in ipairs(halls) do
			rooms[#rooms + 1] = i
		end
		cand = rooms
	end
	local target = floor(hunt * sp.density / 100 + 0.5)
	local out, monsters = {}, 0
	-- a cap per room (monsters per 100 walkable tiles), so no room is packed while another stays empty
	local roomCap, roomHas = {}, {}
	if F.roomIdx and sp.roomCap then
		local roomWalk = {}
		for _, i in ipairs(cand) do
			local k = F.roomIdx[i]
			if k then
				roomWalk[k] = (roomWalk[k] or 0) + 1
			end
		end
		for k, n in pairs(roomWalk) do
			roomCap[k] = max(1, floor(n * sp.roomCap / 100 + 0.5))
		end
	end
	local grid = {}
	local cell = sp.minDistance
	local function key(x, y)
		return floor(x / cell) * 4096 + floor(y / cell)
	end
	for _, i in ipairs(cand) do
		if monsters >= target then
			break
		end
		local x, y = xy(F, i)
		local ok = true
		local gx, gy = floor(x / cell), floor(y / cell)
		for ax = gx - 1, gx + 1 do
			for ay = gy - 1, gy + 1 do
				for _, q in ipairs(grid[ax * 4096 + ay] or {}) do
					local ddx, ddy = q[1] - x, q[2] - y
					if ddx * ddx + ddy * ddy < sp.minDistance * sp.minDistance then
						ok = false
					end
				end
			end
		end
		local room = F.roomIdx and F.roomIdx[i]
		if ok and room and roomCap[room] and (roomHas[room] or 0) >= roomCap[room] then
			ok = false
		end
		if ok then
			local k = key(x, y)
			grid[k] = grid[k] or {}
			grid[k][#grid[k] + 1] = {x, y}
			local count = r:chance(sp.packChance or 0) and r:int(sp.packMin or 2, sp.packMax or 2) or 1
			count = min(count, target - monsters)
			if room and roomCap[room] then
				count = max(1, min(count, roomCap[room] - (roomHas[room] or 0)))
				roomHas[room] = (roomHas[room] or 0) + count
			end
			local pos = absPos(model, F, x, y)
			out[#out + 1] = {x = pos.x, y = pos.y, z = pos.z, monster = r:weighted(sp.monsters),
				level = r:int(sp.level[1], sp.level[2]), count = count, spawntime = sp.spawntime, floor = floorNo}
			monsters = monsters + count
		end
	end
	return out, monsters, hunt
end

local generate

-- def.fastPaths: one search for the paths kept free (big layouts); def.noExit: no exit portal (the rifts);
-- def.bossAt = {x, y}: the boss point (default the south-east corner); def.boss.clear: no decoration, patch or
-- obstacle within this many cells of the boss (an open arena); opts.tick: see T() above
function A.generate(cfg, def, opts)
	opts = opts or {}
	local prev = tickFn
	tickFn, tickCount = opts.tick, 0
	local ok, model = pcall(generate, cfg, def, opts)
	tickFn = prev
	if not ok then
		error(model, 0)
	end
	return model
end

generate = function(cfg, def, opts)
	local theme = resolve(cfg.themes[def.theme], opts, def.kind)
	assert(theme, "unknown theme " .. tostring(def.theme))
	local seed = def.seed or A.hash(def.name)
	local r = A.rng(seed)
	local w, h = def.size[1], def.size[2]
	local model = {name = def.name, kind = def.kind, origin = def.origin, w = w, h = h, floors = {}, tiles = {},
		links = {}, spawns = {}, stats = {walkable = 0, monsters = 0, lights = 0, deco = 0, hunt = 0, floors = {}}}
	local nFloors = def.floors or 1
	local links = pickLinks(r, def, w, h)
	local arrival = {x = def.arrival and def.arrival[1] or 8, y = def.arrival and def.arrival[2] or 8}
	local bossFloor = def.boss and (def.boss.floor or nFloors) or nil
	local bossAt = def.bossAt and {x = def.bossAt[1], y = def.bossAt[2]} or {x = w - 12, y = h - 12}
	local Fs = {}
	for k = 1, nFloors do
		local F = {w = w, h = h, z = def.origin.z + k - 1, k = k}
		Fs[k] = F
		-- required points of this floor: its entry first (the arrival, or the ladder from the floor above)
		local req = {}
		if k == 1 then
			req[1] = {x = arrival.x, y = arrival.y, r = 3}
		end
		local planned = def.layout and def.layout.plan and def.layout.plan[k]
		if k > 1 and planned and planned.anchor then
			-- a planned floor reached by a teleport only has no ladder: its anchor (a zone centre) is its entry
			local hasLink = false
			for _, l in ipairs(links) do
				if l.floor == k - 1 then
					hasLink = true
				end
			end
			if not hasLink then
				req[1] = {x = planned.anchor[1], y = planned.anchor[2], r = 1}
			end
		end
		for _, l in ipairs(links) do
			if l.floor == k - 1 then
				req[#req + 1] = {x = l.x, y = l.y, r = 2}
			end
		end
		for _, l in ipairs(links) do
			if l.floor == k then
				req[#req + 1] = {x = l.x, y = l.y, r = 2}
			end
		end
		if bossFloor == k then
			req[#req + 1] = {x = bossAt.x, y = bossAt.y, r = def.kind == "dungeon" and 1 or (def.boss.radius or 6), boss = true}
		end
		local fr = A.rng(seed + k * 7919)
		buildFloor(cfg, def, theme, opts, fr, F, req, bossFloor == k)
		F.req = req
		if def.kind == "dungeon" and bossFloor == k then
			for _, q in ipairs(F.rooms) do
				if q.kind == "boss" then
					bossAt = {x = q.cx, y = q.cy}
					F.bossRoom = q
				end
			end
		elseif bossFloor == k then
			local rad = def.boss.radius or 6
			F.bossRoom = {x1 = bossAt.x - rad, y1 = bossAt.y - rad, x2 = bossAt.x + rad, y2 = bossAt.y + rad}
		end
	end
	-- the links: hole on floor k (and its climb arrival south of it), ladder below
	for _, l in ipairs(links) do
		local up, down = Fs[l.floor], Fs[l.floor + 1]
		local ok = up.walk[idx(up, l.x, l.y)] and up.walk[idx(up, l.x, l.y + 1)] and down.walk[idx(down, l.x, l.y)]
		if ok then
			model.links[#model.links + 1] = {hole = absPos(model, up, l.x, l.y), up = absPos(model, up, l.x, l.y + 1),
				ladder = absPos(model, down, l.x, l.y), lx = l.x, ly = l.y, floor = l.floor}
		end
	end
	for k, F in ipairs(Fs) do
		local fr = A.rng(seed + k * 104729)
		local reserved, safe = {}, {}
		local entry = F.req[1]
		if k == 1 then
			ring(F, arrival.x, arrival.y, 2, reserved)
			ring(F, arrival.x, arrival.y, def.spawns.safeRadius or 10, safe)
		end
		local targets = {}
		for _, l in ipairs(model.links) do
			if l.floor == k then
				ring(F, l.lx, l.ly, 1, reserved)
				ring(F, l.lx, l.ly + 1, 1, reserved)
				ring(F, l.lx, l.ly, 4, safe)
				targets[#targets + 1] = idx(F, l.lx, l.ly)
			elseif l.floor + 1 == k then
				ring(F, l.lx, l.ly, 1, reserved)
				ring(F, l.lx, l.ly, 4, safe)
				targets[#targets + 1] = idx(F, l.lx, l.ly)
			end
		end
		if F.bossRoom then
			ring(F, bossAt.x, bossAt.y, def.boss.clear or 1, reserved)
			targets[#targets + 1] = idx(F, bossAt.x, bossAt.y)
		end
		for _, q in ipairs(F.rooms or {}) do
			targets[#targets + 1] = idx(F, q.cx, q.cy)
		end
		local from = idx(F, entry.x, entry.y)
		markPaths(F, from, targets, def.fastPaths)
		paintGrounds(cfg, def, theme, opts, fr, F, reserved)
		paintBorders(cfg, def, theme, opts, F)
		local stats = model.stats
		decorate(cfg, theme, opts, fr, F, reserved, stats)
		edgePieces(cfg, theme, opts, fr, F, reserved, stats, theme.lights, "lights")
		edgePieces(cfg, theme, opts, fr, F, reserved, stats, theme.props, "deco")
		-- links
		for _, l in ipairs(model.links) do
			if l.floor == k then
				addItem(F, idx(F, l.lx, l.ly), cfg.items.hole)
			elseif l.floor + 1 == k then
				addItem(F, idx(F, l.lx, l.ly), cfg.items.ladder)
			end
		end
		-- the exit portal next to the arrival
		if k == 1 then
			local ex = def.exit or {0, -1}
			model.arrival = absPos(model, F, arrival.x, arrival.y)
			if def.noExit then
				model.exit = model.arrival
			else
				model.exit = absPos(model, F, arrival.x + ex[1], arrival.y + ex[2])
				addItem(F, idx(F, arrival.x + ex[1], arrival.y + ex[2]), cfg.items.portal)
			end
		end
		-- spawns (the boss room only holds the boss)
		if F.bossRoom then
			local q = F.bossRoom
			for y = q.y1 - 1, q.y2 + 1 do
				for x = q.x1 - 1, q.x2 + 1 do
					if inside(F, x, y) then
						safe[idx(F, x, y)] = true
					end
				end
			end
		end
		local list, monsters, hunt = spawns(cfg, def, fr, F, safe, model, k)
		for _, s in ipairs(list) do
			model.spawns[#model.spawns + 1] = s
		end
		if F.bossRoom and def.boss then
			local b = def.boss
			local pos = absPos(model, F, bossAt.x, bossAt.y)
			model.boss = {x = pos.x, y = pos.y, z = pos.z, monster = b.monster, name = b.name, level = b.level, count = 1,
				spawntime = b.spawntime, healthMult = b.healthMult, damageMult = b.damageMult, boss = true, floor = k}
			local q = F.bossRoom
			local a1, a2 = absPos(model, F, q.x1, q.y1), absPos(model, F, q.x2, q.y2)
			model.bossRoom = {x1 = a1.x, y1 = a1.y, x2 = a2.x, y2 = a2.y, z = F.z}
		end
		-- the rooms of a dungeon layout (absolute), for the statistics
		for _, q in ipairs(F.rooms or {}) do
			local a1, a2 = absPos(model, F, q.x1, q.y1), absPos(model, F, q.x2, q.y2)
			model.rooms = model.rooms or {}
			model.rooms[#model.rooms + 1] = {x1 = a1.x, y1 = a1.y, x2 = a2.x, y2 = a2.y, z = F.z, kind = q.kind}
		end
		-- tiles
		local walkable = 0
		for y = 1, F.h do
			T()
			for x = 1, F.w do
				local i = idx(F, x, y)
				if F.walk[i] then
					walkable = walkable + 1
				end
				if F.fam[i] then
					local items = {}
					for _, id in ipairs(F.items[i]) do
						items[#items + 1] = id
					end
					if F.wallKind and F.wallKind[i] then
						-- the wall piece stands over the borders of its tile
						items[#items + 1] = fr:weighted(F.wallSet[F.wallKind[i]])
					end
					local pos = absPos(model, F, x, y)
					model.tiles[#model.tiles + 1] = {x = pos.x, y = pos.y, z = pos.z, ground = F.ground[i], items = items}
				end
			end
		end
		model.floors[k] = {z = F.z, walkable = walkable, hunt = hunt, monsters = monsters}
		model.stats.walkable = model.stats.walkable + walkable
		model.stats.hunt = model.stats.hunt + hunt
		model.stats.monsters = model.stats.monsters + monsters
		F.walkSet = F.walk
	end
	model.stats.density = model.stats.hunt > 0 and model.stats.monsters * 100 / model.stats.hunt or 0
	-- the walkable cells per floor (absolute keys) for the validator and the tests
	model.walk = {}
	for k, F in ipairs(Fs) do
		local set = {}
		for i in pairs(F.walk) do
			local x, y = xy(F, i)
			set[(def.origin.y + y - 1) * 65536 + def.origin.x + x - 1] = true
		end
		model.walk[F.z] = set
	end
	model.def = def
	return model
end

-- ====================================================================== checks
local function key(x, y)
	return y * 65536 + x
end

-- every item id the area may use (theme, families, borders, walls, links, portal)
function A.allowedIds(cfg, def, opts)
	local theme = resolve(cfg.themes[def.theme], opts, def.kind)
	local ok = {}
	local function addRows(rows)
		for _, row in ipairs(weightedIds(cfg, opts, rows)) do
			ok[row[1]] = true
		end
	end
	local fams = {theme.floor, theme.rock, theme.bossFloor}
	for _, f in ipairs(theme.roomFloors or {}) do
		fams[#fams + 1] = f
	end
	for _, f in ipairs(theme.mixedFloors or {}) do
		fams[#fams + 1] = f
	end
	for _, p in ipairs(theme.patches or {}) do
		fams[#fams + 1] = p.family
	end
	for _, p in ipairs(theme.pools or {}) do
		fams[#fams + 1] = p.family
	end
	local famSet = {}
	for _, f in pairs(fams) do
		if f then
			famSet[f] = true
			addRows(cfg.families[f].grounds)
		end
	end
	for over in pairs(famSet) do
		for under, set in pairs(cfg.borders[over] or {}) do
			if under == "*" or famSet[under] then
				for _, v in pairs(cfg.pieces[set]) do
					local id = idOf(cfg, opts, v)
					if id then
						ok[id] = true
					end
				end
			end
		end
	end
	if theme.wall then
		for _, rows in pairs(cfg.walls[theme.wall]) do
			for _, row in ipairs(rows) do
				ok[row[1]] = true
			end
		end
	end
	local deco = theme.decor or {}
	for _, cl in ipairs(deco.clusters or {}) do
		addRows(cl.items)
	end
	addRows(deco.scatter)
	addRows(theme.obstacles and theme.obstacles.items)
	addRows(theme.lights and theme.lights.items)
	addRows(theme.props and theme.props.items)
	ok[cfg.items.hole], ok[cfg.items.ladder], ok[cfg.items.portal] = true, true, true
	return ok
end

local validate

-- problems of a model: [] when it is fine (opts.tick as in A.generate)
function A.validate(cfg, model, opts)
	local prev = tickFn
	tickFn, tickCount = opts and opts.tick, 0
	local ok, res = pcall(validate, cfg, model, opts)
	tickFn = prev
	if not ok then
		error(res, 0)
	end
	return res
end

validate = function(cfg, model, opts)
	local out = {}
	local def = model.def
	local allowed = A.allowedIds(cfg, def, opts)
	for _, t in ipairs(model.tiles) do
		T2048()
		if not t.ground or not allowed[t.ground] then
			out[#out + 1] = string.format("ground %s at %d,%d,%d is not in the palette", tostring(t.ground), t.x, t.y, t.z)
			break
		end
		for _, id in ipairs(t.items) do
			if not allowed[id] then
				out[#out + 1] = string.format("item %d at %d,%d,%d is not in the palette", id, t.x, t.y, t.z)
				break
			end
		end
	end
	-- connectivity over the floors: from the arrival through holes (down) and ladders (up), every walkable cell
	local walk = model.walk
	local seen, stack = {}, {}
	local function push(x, y, z)
		local s = seen[z]
		if not s then
			s = {}
			seen[z] = s
		end
		local k = key(x, y)
		if walk[z] and walk[z][k] and not s[k] then
			s[k] = true
			stack[#stack + 1] = {x, y, z}
		end
	end
	local holeAt, ladderAt = {}, {}
	for _, l in ipairs(model.links) do
		holeAt[l.hole.z .. ":" .. key(l.hole.x, l.hole.y)] = l
		ladderAt[l.ladder.z .. ":" .. key(l.ladder.x, l.ladder.y)] = l
	end
	push(model.arrival.x, model.arrival.y, model.arrival.z)
	if #stack == 0 then
		out[#out + 1] = "the arrival is not walkable"
	end
	while #stack > 0 do
		T2048()
		local c = table.remove(stack)
		local x, y, z = c[1], c[2], c[3]
		for _, d in ipairs(D8) do
			push(x + d[1], y + d[2], z)
		end
		local h = holeAt[z .. ":" .. key(x, y)]
		if h then
			push(h.ladder.x, h.ladder.y, h.ladder.z)
		end
		local l = ladderAt[z .. ":" .. key(x, y)]
		if l then
			push(l.up.x, l.up.y, l.up.z)
		end
	end
	local unreached = 0
	for z, set in pairs(walk) do
		for k in pairs(set) do
			T2048()
			if not (seen[z] and seen[z][k]) then
				unreached = unreached + 1
			end
		end
	end
	if unreached > 0 then
		out[#out + 1] = unreached .. " walkable tiles cannot be reached from the arrival"
	end
	-- links
	local wantLinks = def.links and #def.links or ((def.floors or 1) - 1) * (def.linksPerFloor or 1)
	if #model.links ~= wantLinks then
		out[#out + 1] = string.format("%d links, %d wanted", #model.links, wantLinks)
	end
	for _, l in ipairs(model.links) do
		if l.ladder.x ~= l.hole.x or l.ladder.y ~= l.hole.y or l.ladder.z ~= l.hole.z + 1 then
			out[#out + 1] = "a ladder is not under its hole"
		end
		if l.up.x ~= l.hole.x or l.up.y ~= l.hole.y + 1 or l.up.z ~= l.hole.z then
			out[#out + 1] = "the climb arrival is not south of the hole"
		end
		for _, p in ipairs({l.hole, l.up, l.ladder}) do
			if not (walk[p.z] and walk[p.z][key(p.x, p.y)]) then
				out[#out + 1] = string.format("link tile %d,%d,%d is not walkable", p.x, p.y, p.z)
			end
		end
	end
	-- spawns: walkable, not on a link or the arrival, spread, density inside the band
	local special = {}
	for _, l in ipairs(model.links) do
		special[l.hole.z .. ":" .. key(l.hole.x, l.hole.y)] = true
		special[l.ladder.z .. ":" .. key(l.ladder.x, l.ladder.y)] = true
	end
	special[model.exit.z .. ":" .. key(model.exit.x, model.exit.y)] = true
	local all = {}
	for _, s in ipairs(model.spawns) do
		all[#all + 1] = s
	end
	if model.boss then
		all[#all + 1] = model.boss
	end
	for _, s in ipairs(all) do
		if not (walk[s.z] and walk[s.z][key(s.x, s.y)]) then
			out[#out + 1] = string.format("spawn %d,%d,%d is not walkable", s.x, s.y, s.z)
		end
		if special[s.z .. ":" .. key(s.x, s.y)] then
			out[#out + 1] = string.format("spawn %d,%d,%d is on a hole, ladder or portal", s.x, s.y, s.z)
		end
		local d = max(abs(s.x - model.arrival.x), abs(s.y - model.arrival.y))
		if s.z == model.arrival.z and d < (def.spawns.safeRadius or 10) then
			out[#out + 1] = string.format("spawn %d,%d,%d is %d sqm from the arrival", s.x, s.y, s.z, d)
		end
	end
	local band = def.spawns.band
	local dens = model.stats.density
	if band and (dens < band[1] or dens > band[2]) then
		out[#out + 1] = string.format("density %.2f monsters per 100 tiles outside %.1f-%.1f", dens, band[1], band[2])
	end
	return out
end

-- one number over the model (tiles, items, spawns, links): the same in LuaJIT and Lua 5.3
function A.checksum(model)
	local h = 7
	local function mix(v)
		h = (h * 31 + (v % 1000003)) % MOD
	end
	for _, t in ipairs(model.tiles) do
		mix(t.x)
		mix(t.y)
		mix(t.z)
		mix(t.ground or 0)
		for _, id in ipairs(t.items) do
			mix(id)
		end
	end
	for _, s in ipairs(model.spawns) do
		mix(s.x)
		mix(s.y)
		mix(s.level)
		mix(s.count)
		mix(A.hash(s.monster))
	end
	for _, l in ipairs(model.links) do
		mix(l.hole.x)
		mix(l.hole.y)
	end
	return h
end

return A
