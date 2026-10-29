-- Rift layouts, pure logic (no engine calls; tests/rift_layout_test.lua). Every run of a rift gets a generated map
-- of its own (owner request: "make the rifts big"): a cave system, an open waste, a ruined complex or a cave with
-- ruined chambers, one or two floors, the arrival in one corner and the guardian's arena in the opposite one. The
-- tiles come from the area generator (areagen_core.lua) with the rift themes of areagen_config.lua; this file picks
-- the size, kind, floors and corners from rift_config.lua `layout`, and adds what a run needs on top of the tile
-- model: the walking distance from the arrival to every cell, the sections packs stand in, the arena. rift.lua
-- builds the tiles in short steps in a free slot of the grid (server/README.md "Rifts", Layouts).
--
--   ChaosRiftLayout.band(cfg, tier)                     size band of a key tier: index, side, time limit
--   ChaosRiftLayout.plan(cfg, req)                      the areagen def of a layout; req = {theme, band, seed, origin}
--   ChaosRiftLayout.generate(cfg, agCfg, req, opts)     the layout L (below); opts = areagen opts (dark, darkIds, tick)
--   ChaosRiftLayout.key(x, y, z) / unkey(k)             one number per position (sorted lists, sets)
--   ChaosRiftLayout.isFloor(L, x, y, z)                 a walkable cell of the layout
--   ChaosRiftLayout.visit(L, positions, visited, radius) sections the players reached; returns the farthest one's distance
--   ChaosRiftLayout.reinforceSection(L, positions, visited, minDistance, window)   where the next pack comes in
--   ChaosRiftLayout.sectionOrder(L, rand)               the sections in the order packs fill them, nearest first
--   ChaosRiftLayout.cellIn(L, section, rand) / near(L, pos, spread, rand)   spawn positions
--
-- The layout L (absolute positions):
--   {seed, theme, kind, band, side, floors = {z, ...}, origin, start = pos, bossSpawn = pos, arena = {x1, y1, x2, y2, z},
--    arenaStart = pos (the arena's mouth: omen arenas arrive there), sections = {{name, x, y, z, dist, cells = {key...}}},
--    byName = {name = section}, walkKeys = sorted keys of the walkable cells, walkable = n, route = walking distance
--    arrival -> arena, tiles = the areagen tiles to build (rift.lua drops them once built), tileKeys = the key of every
--    built tile (for the clean-up before the slot's next layout), stats = {tiles, items, walkable, route, attempts}}
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosAreaGenCore then
	dofile("data/scripts/chaos/areagen_core.lua")
end

ChaosRiftLayout = ChaosRiftLayout or {}
local RL = ChaosRiftLayout
local A = ChaosAreaGenCore
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local D8 = {{0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}}

function RL.key(x, y, z)
	return (z * 65536 + y) * 65536 + x
end

function RL.unkey(k)
	local x = k % 65536
	local r = floor(k / 65536)
	local y = r % 65536
	return x, y, floor(r / 65536)
end

-- the size band of a key tier: index, side (one floor), time limit in seconds
function RL.band(cfg, tier)
	local sizes = cfg.layout.sizes
	for i, row in ipairs(sizes) do
		if tier <= row[1] then
			return i, row[2], row[3]
		end
	end
	local last = sizes[#sizes]
	return #sizes, last[2], last[3]
end

-- the corners of a layout: 1 north-west, 2 north-east, 3 south-east, 4 south-west
local function cornerAt(c, side, inset)
	local lo, hi = inset, side - inset + 1
	if c == 1 then
		return lo, lo
	elseif c == 2 then
		return hi, lo
	elseif c == 3 then
		return hi, hi
	end
	return lo, hi
end

-- the areagen def of a layout: kind and floors weighted by the rift theme, the size of the band (x twoFloorScale
-- for two floors), arrival and arena in opposite corners; the counts of the kind's parameters scale with the area
function RL.plan(cfg, req)
	local lc = cfg.layout
	local lt = lc.themes[req.theme]
	assert(lt, "no layout for the rift theme " .. tostring(req.theme))
	local r = A.rng(req.seed)
	local kind = req.kind or r:weighted(lt.kinds)
	local floors = req.floors or r:weighted(lt.floors)
	local side = lc.sizes[req.band][2]
	if floors > 1 then
		side = floor(side * lc.twoFloorScale + 0.5)
	end
	-- a kind that fills more of its square (the open waste) gets a smaller square: the walkable tiles of a band stay close
	-- (tools/rift_layout_model.lua, rift_layout_balance_config.lua spreadMax)
	if lc.kindScale and lc.kindScale[kind] then
		side = floor(side * lc.kindScale[kind] + 0.5)
	end
	local corner = r:int(1, 4)
	local ax, ay = cornerAt(corner, side, lc.arrivalInset)
	local bx, by = cornerAt((corner + 1) % 4 + 1, side, lc.arena.inset)
	local area = side * side / 10000
	local p = {}
	for k, v in pairs(lc.kinds[kind]) do
		p[k] = v
	end
	local function scaled(range)
		return {max(1, floor(range[1] * area + 0.5)), max(1, floor(range[2] * area + 0.5))}
	end
	if p.roomsPer10k then
		p.rooms = scaled(p.roomsPer10k)
		p.roomsPer10k = nil
	end
	if p.loopsPer10k then
		p.loops = scaled(p.loopsPer10k)
		p.loopsPer10k = nil
	end
	if kind == "dungeon" then
		p.bossRoom = lc.arena.room
		p.bossAnchor = {bx, by}
	end
	local off = floor((cfg.grid.spacing - side) / 2)
	return {
		id = "rift", name = req.theme, kind = kind, theme = lt.areagen, seed = req.seed, floors = floors,
		linksPerFloor = lc.links, size = {side, side}, layout = p, arrival = {ax, ay}, bossAt = {bx, by},
		origin = {x = req.origin.x + off, y = req.origin.y + off, z = req.origin.z},
		noExit = true, fastPaths = true, linkAvoid = {{bx, by, lc.arena.radius + 12}, {ax, ay, lc.safeRadius}},
		spawns = {density = 0, minDistance = 4, safeRadius = lc.safeRadius, monsters = {{"none", 1}}, level = {1, 1},
			spawntime = 0},
		boss = {monster = "none", name = "guardian", level = 1, radius = lc.arena.radius,
			clear = kind == "dungeon" and floor(lc.arena.room / 2) - 2 or lc.arena.clear, floor = floors}
	}
end

-- ---------------------------------------------------------------------------------------------- derived data
-- walking distance (8 neighbours, holes down to their ladder, ladders up to the cell south of the hole) from the
-- arrival to every walkable cell; keys RL.key
local function routeDistances(model, tick)
	local walk = model.walk
	local function isWalk(x, y, z)
		local s = walk[z]
		return s ~= nil and s[y * 65536 + x] == true
	end
	local holes, ladders = {}, {}
	for _, l in ipairs(model.links) do
		holes[RL.key(l.hole.x, l.hole.y, l.hole.z)] = l.ladder
		ladders[RL.key(l.ladder.x, l.ladder.y, l.ladder.z)] = l.up
	end
	local a = model.arrival
	local start = RL.key(a.x, a.y, a.z)
	local dist, queue, head = {[start] = 0}, {start}, 1
	local n = 0
	while head <= #queue do
		n = n + 1
		if tick and n % 2048 == 0 then
			tick()
		end
		local k = queue[head]
		head = head + 1
		local x, y, z = RL.unkey(k)
		local d = dist[k] + 1
		for _, o in ipairs(D8) do
			local nx, ny = x + o[1], y + o[2]
			if isWalk(nx, ny, z) then
				local j = RL.key(nx, ny, z)
				if dist[j] == nil then
					dist[j] = d
					queue[#queue + 1] = j
				end
			end
		end
		local to = holes[k] or ladders[k]
		if to then
			local j = RL.key(to.x, to.y, to.z)
			if dist[j] == nil then
				dist[j] = d
				queue[#queue + 1] = j
			end
		end
	end
	return dist
end

-- the sections: square blocks of `section` cells per floor, with at least minCells walkable cells outside the
-- arrival's safe radius and outside the arena; centre = the cell nearest to the block's mean
local function sections(cfg, L, model, dist, tick)
	local lc = cfg.layout
	local S = lc.section
	local o = model.origin
	local blocks, order = {}, {}
	local a, ar = L.start, L.arena
	for _, fz in ipairs(L.floors) do
		for y = o.y, o.y + model.h - 1 do
			if tick then
				tick()
			end
			local set = model.walk[fz]
			for x = o.x, o.x + model.w - 1 do
				if set[y * 65536 + x] then
					local safe = fz == a.z and max(abs(x - a.x), abs(y - a.y)) <= lc.safeRadius
					local inArena = fz == ar.z and x >= ar.x1 - 1 and x <= ar.x2 + 1 and y >= ar.y1 - 1 and y <= ar.y2 + 1
					if not safe and not inArena and dist[RL.key(x, y, fz)] then
						local bk = (fz * 64 + floor((y - o.y) / S)) * 64 + floor((x - o.x) / S)
						local b = blocks[bk]
						if not b then
							b = {z = fz, cells = {}, sx = 0, sy = 0}
							blocks[bk] = b
							order[#order + 1] = bk
						end
						b.cells[#b.cells + 1] = RL.key(x, y, fz)
						b.sx, b.sy = b.sx + x, b.sy + y
					end
				end
			end
		end
	end
	table.sort(order)
	local out, byName = {}, {}
	for _, bk in ipairs(order) do
		local b = blocks[bk]
		if #b.cells >= lc.minCells then
			local mx, my = b.sx / #b.cells, b.sy / #b.cells
			local best, bd
			for _, k in ipairs(b.cells) do
				local x, y = RL.unkey(k)
				local d = (x - mx) * (x - mx) + (y - my) * (y - my)
				if not bd or d < bd then
					best, bd = k, d
				end
			end
			local x, y, z = RL.unkey(best)
			local s = {name = "s" .. (#out + 1), x = x, y = y, z = z, dist = dist[best], cells = b.cells}
			out[#out + 1] = s
			byName[s.name] = s
		end
	end
	return out, byName
end

-- the layout of one run: the areagen model plus routes, sections and the arena. A model the validator rejects (a
-- link that did not fit, rare) is made again with the next seed, up to layout.attempts times.
function RL.generate(cfg, agCfg, req, opts)
	opts = opts or {}
	local tick = opts.tick
	local model, def, problems
	local attempts = 0
	local seed = req.seed
	repeat
		attempts = attempts + 1
		def = RL.plan(cfg, {theme = req.theme, band = req.band, seed = seed, origin = req.origin, kind = req.kind,
			floors = req.floors})
		model = A.generate(agCfg, def, opts)
		problems = A.validate(agCfg, model, opts) -- opts.tick: the validator yields too
		if not model.boss or not model.bossRoom then
			problems[#problems + 1] = "no room for the guardian's arena"
		end
		seed = seed + 7919
	until #problems == 0 or attempts >= cfg.layout.attempts
	local floors = {}
	for k = 1, def.floors do
		floors[k] = def.origin.z + k - 1
	end
	local b = model.boss
	local L = {seed = req.seed, usedSeed = seed - 7919, theme = req.theme, kind = def.kind, band = req.band, side = def.size[1],
		floors = floors, origin = def.origin, w = model.w, h = model.h, start = model.arrival,
		bossSpawn = {x = b.x, y = b.y, z = b.z}, arena = model.bossRoom, problems = problems}
	local dist = routeDistances(model, tick)
	L.route = dist[RL.key(b.x, b.y, b.z)] or -1
	-- the arena's mouth: its walkable cell nearest to the arrival by walking
	local ar = L.arena
	local mouth, md
	for y = ar.y1, ar.y2 do
		for x = ar.x1, ar.x2 do
			local d = dist[RL.key(x, y, ar.z)]
			if d and (not md or d < md) then
				mouth, md = {x = x, y = y, z = ar.z}, d
			end
		end
	end
	L.arenaStart = mouth or L.bossSpawn
	L.sections, L.byName = sections(cfg, L, model, dist, tick)
	-- walkable cells (sorted keys) and the built tiles
	local walkKeys = {}
	for _, fz in ipairs(floors) do
		for k in pairs(model.walk[fz]) do
			walkKeys[#walkKeys + 1] = fz * 4294967296 + k
			if tick and #walkKeys % 2048 == 0 then
				tick()
			end
		end
	end
	table.sort(walkKeys) -- 10-30 thousand numbers: a few ms, the one step that cannot yield
	L.walkKeys, L.walkable = walkKeys, #walkKeys
	local tileKeys, items = {}, 0
	for i, t in ipairs(model.tiles) do
		tileKeys[i] = RL.key(t.x, t.y, t.z)
		items = items + 1 + #t.items
		if tick and i % 2048 == 0 then
			tick()
		end
	end
	L.tiles, L.tileKeys = model.tiles, tileKeys
	L.links = model.links
	L.stats = {tiles = #model.tiles, items = items, walkable = #walkKeys, route = L.route, attempts = attempts,
		sections = #L.sections, checksum = not opts.noChecksum and A.checksum(model) or nil}
	return L, model, def
end

-- ---------------------------------------------------------------------------------------------- run helpers
function RL.isFloor(L, x, y, z)
	local k = RL.key(x, y, z)
	local list = L.walkKeys
	local lo, hi = 1, #list
	while lo <= hi do
		local mid = floor((lo + hi) / 2)
		local v = list[mid]
		if v == k then
			return true
		elseif v < k then
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	return false
end

local function cheb(p, s)
	if p.z ~= s.z then
		return 100000
	end
	return max(abs(p.x - s.x), abs(p.y - s.y))
end

-- marks the sections whose centre a player came within `radius` of; returns the largest walking distance of a
-- visited section (the party's progress), 0 when none
function RL.visit(L, positions, visited, radius)
	local far = 0
	for _, s in ipairs(L.sections) do
		if not visited[s.name] then
			for _, p in ipairs(positions) do
				if cheb(p, s) <= radius then
					visited[s.name] = true
					break
				end
			end
		end
		if visited[s.name] and s.dist > far then
			far = s.dist
		end
	end
	return far
end

-- the section the next pack comes in: not visited, at least minDistance (Chebyshev, same floor) from every player;
-- among those up to `window` walking steps past the party's progress the one farthest from the players (the area
-- just ahead), else the nearest one by walking. nil when none qualifies.
function RL.reinforceSection(L, positions, visited, minDistance, window)
	local progress = 0
	for _, s in ipairs(L.sections) do
		if visited[s.name] and s.dist > progress then
			progress = s.dist
		end
	end
	local best, bestD, next_, nextDist
	for _, s in ipairs(L.sections) do
		if not visited[s.name] then
			local d = math.huge
			for _, p in ipairs(positions) do
				d = min(d, cheb(p, s))
			end
			if d >= minDistance then
				if s.dist <= progress + window then
					if not bestD or d > bestD then
						best, bestD = s, d
					end
				elseif not nextDist or s.dist < nextDist then
					next_, nextDist = s, s.dist
				end
			end
		end
	end
	return best or next_
end

-- the sections in the order the run's packs take them: the one nearest to the arrival first, then the rest shuffled
-- (rand(a, b)), so the first packs spread over the whole map
function RL.sectionOrder(L, rand)
	local list = {}
	for _, s in ipairs(L.sections) do
		list[#list + 1] = s
	end
	table.sort(list, function(a, b)
		if a.dist ~= b.dist then
			return a.dist < b.dist
		end
		return a.name < b.name
	end)
	local out = {}
	if #list > 0 then
		out[1] = table.remove(list, 1).name
	end
	for i = #list, 2, -1 do
		local j = rand(1, i)
		list[i], list[j] = list[j], list[i]
	end
	for _, s in ipairs(list) do
		out[#out + 1] = s.name
	end
	return out
end

-- a random walkable cell of a section
function RL.cellIn(L, section, rand)
	local x, y, z = RL.unkey(section.cells[rand(1, #section.cells)])
	return {x = x, y = y, z = z}
end

-- a walkable cell within `spread` of pos (a few tries), else pos
function RL.near(L, pos, spread, rand)
	for _ = 1, 6 do
		local x, y = pos.x + rand(-spread, spread), pos.y + rand(-spread, spread)
		if RL.isFloor(L, x, y, pos.z) then
			return {x = x, y = y, z = pos.z}
		end
	end
	return {x = pos.x, y = pos.y, z = pos.z}
end

-- the section nearest to pos by straight distance at least `minDistance` away (the treasure goblin: close enough to
-- chase), nil when none
function RL.sectionNear(L, pos, minDistance)
	local best, bd
	for _, s in ipairs(L.sections) do
		local d = cheb(pos, s)
		if d >= minDistance and (not bd or d < bd) then
			best, bd = s, d
		end
	end
	return best
end

return RL
