-- The Scorched Marches (open-world PvP zone): the pure part (no engine calls), shared by pvpzone.lua and
-- tests/pvpzone_test.lua.
--   map        instance slots per realm, the layout (gates, safe exits, the Cinder Shrine, ruins, spawn points), the
--              footprint, map mode (an existing rectangle)
--   entering   who may enter (level, Hardcore rule, confirmation, protection zone, combat, cooldown, ...), login
--              inside (hold, then the safe exit), protection, the exit channel
--   embers     carry cap, monster embers, the death pile, who may take how much, banking
--   kills      anti-farming verdict (as guild wars), faction reputation (pledge, rival, daily cap)
--   shrine     the contest (warden, capture, contested, decay), control and the faction-wide buff
--   vendor     prices, weekly limits, cosmetics
--   pvp        damage scaling like the battleground (its normalise numbers)
-- Settings: pvpzone_config.lua (passed in as `cfg`). Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosPvpZoneCore = ChaosPvpZoneCore or {}
local K = ChaosPvpZoneCore

local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local DAY, WEEK = 86400, 7 * 86400

local function clamp(x, lo, hi)
	return max(lo, min(hi, x))
end

-- ====================================================================== time keys (Monday / day at `hour`, local)
local function startOfDay(t, hour)
	local d = os.date("*t", t)
	local s = os.time({year = d.year, month = d.month, day = d.day, hour = hour or 0, min = 0, sec = 0})
	if s > t then
		s = s - DAY
	end
	return s
end

-- a number that changes once a day at `hour`
function K.dayKey(t, hour)
	local s = startOfDay(t, hour)
	local d = os.date("*t", s)
	return d.year * 10000 + d.month * 100 + d.day
end

-- a number that changes every Monday at `hour`
function K.weekKey(t, hour)
	local s = startOfDay(t, hour)
	local wday = tonumber(os.date("%w", s)) -- 0 = Sunday
	local back = (wday + 6) % 7 -- days since Monday
	local d = os.date("*t", s - back * DAY + 3600) -- +1 h: safe over a DST change
	return d.year * 10000 + d.month * 100 + d.day
end

-- ====================================================================== map
function K.slotForRealm(cfg, realm)
	realm = tonumber(realm) or 0
	if cfg.mode == "map" then
		return 0
	end
	if realm <= 0 then
		return 0
	end
	local n = max(1, cfg.grid.slots - 1)
	return 1 + (floor(realm) - 1) % n
end

function K.slotOrigin(cfg, slot)
	local g = cfg.grid
	return {x = g.origin.x + (slot % g.cols) * g.spacing, y = g.origin.y + floor(slot / g.cols) * g.spacing, z = g.origin.z}
end

-- the ruins of one half in local coordinates (1..W, 1..H); the other half is the 180-degree turn (fair to both gates)
local RUIN_WALLS = {
	-- an L near the south-west gate's way to the shrine
	{18, 38}, {19, 38}, {20, 38}, {21, 38}, {22, 38}, {18, 39}, {18, 40}, {18, 41},
	-- a broken wall west of the shrine
	{26, 24}, {26, 25}, {26, 26}, {26, 30}, {26, 31}, {26, 32},
	-- a ruined hall in the north-west
	{10, 10}, {11, 10}, {12, 10}, {14, 10}, {15, 10}, {10, 11}, {10, 12}, {10, 14}, {15, 11}, {15, 12}, {15, 14},
	-- cover in the south
	{40, 46}, {41, 46}, {42, 46}, {43, 46},
	{30, 12}, {30, 13}, {30, 14}
}
local RUIN_PILLARS = {{24, 44}, {12, 24}, {33, 40}, {20, 18}, {46, 50}}

-- ---------------------------------------------------------------------- the look of the field
-- Deterministic: the same field in LuaJIT and Lua 5.3, in every slot, on every run (integer hashes of the tile's
-- coordinates, never the clock or math.random). Everything is laid in one half and turned 180 degrees for the other
-- (the hash reads the lower of the two coordinates), so both gates have the same cover.
if not ChaosAreaGenCore then
	dofile("data/scripts/chaos/areagen_core.lua") -- borderPieces: the border piece names of one tile
end

local function hashN(a, b, c)
	local h = (a * 73856093 + b * 19349663 + (c or 0) * 83492791) % 2147483629
	h = (h * 48271) % 2147483629
	return (h * 48271 + 12345) % 2147483629
end

-- 0 .. 99.99
local function roll(a, b, c)
	return hashN(a, b, c) % 10000 / 100
end

local D8 = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}, {1, -1}, {-1, -1}, {1, 1}, {-1, 1}}

-- the ring test: do the free cardinal neighbours of a tile stay joined without it? (then blocking the tile cannot cut
-- the field in two). free(dx, dy) -> bool.
local function ringJoined(free)
	local card = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
	local corner = {{1, -1}, {1, 1}, {-1, 1}, {-1, -1}} -- between card[i] and card[i % 4 + 1]
	local n, comps = 0, 0
	local f = {}
	for i = 1, 4 do
		f[i] = free(card[i][1], card[i][2])
		if f[i] then
			n = n + 1
		end
	end
	if n <= 1 then
		return true
	end
	-- components of the free cardinals around the ring (neighbours joined through a free corner)
	local joined = {}
	for i = 1, 4 do
		local j = i % 4 + 1
		joined[i] = f[i] and f[j] and free(corner[i][1], corner[i][2])
	end
	local links = 0
	for i = 1, 4 do
		if joined[i] then
			links = links + 1
		end
	end
	comps = n - links
	if n == 4 and links == 4 then
		comps = 1
	end
	return comps <= 1
end

local function pick(list, a, b, c)
	return list[hashN(a, b, c) % #list + 1]
end

local function weighted(list, a, b, c)
	local total = 0
	for _, e in ipairs(list) do
		total = total + e[2]
	end
	local r = hashN(a, b, c) % total
	for _, e in ipairs(list) do
		if r < e[2] then
			return e[1]
		end
		r = r - e[2]
	end
	return list[1][1]
end

-- the layout of a slot (build mode): rectangles and positions in map coordinates, the ground of every tile, the
-- cover, the decoration, the lights
local function buildLayout(cfg, slot)
	local o = K.slotOrigin(cfg, slot)
	local W, H = cfg.field.innerW, cfg.field.innerH
	local z = o.z
	local look = cfg.look
	local function at(x, y)
		return {x = o.x + x, y = o.y + y, z = z}
	end
	local function turn(x, y)
		return W + 1 - x, H + 1 - y
	end
	local function canon(x, y)
		local tx, ty = turn(x, y)
		if x < tx or (x == tx and y <= ty) then
			return x, y
		end
		return tx, ty
	end
	local function key(x, y)
		return y * 128 + x
	end
	local function inside(x, y)
		return x >= 1 and x <= W and y >= 1 and y <= H
	end
	local cx, cy = floor((W + 1) / 2), floor((H + 1) / 2)
	local L = {slot = slot, z = z, x1 = o.x, y1 = o.y, x2 = o.x + W + 1, y2 = o.y + H + 1, shrine = at(cx, cy),
		exits = {}, gates = {}, walls = {}, pillars = {}, flags = {}, spawns = {}, entrySpots = {}, cover = {},
		decor = {}, fixtures = {}, tiles = {}}
	local blocked = {} -- local key -> true (ruin walls, pillars, flags, fixtures, the shrine)
	local function block(x, y)
		blocked[key(x, y)] = true
	end
	-- two safe exits: south-west and (turned) north-east, each in a gate yard of 11 x 11
	local ex, ey = 7, H - 6
	local exitsLocal = {}
	for i, p in ipairs({{ex, ey}, {turn(ex, ey)}}) do
		local e = at(p[1], p[2])
		exitsLocal[i] = p
		L.exits[i] = e
		L.gates[i] = {x1 = e.x - 5, y1 = e.y - 5, x2 = e.x + 5, y2 = e.y + 5}
		L.flags[#L.flags + 1] = {x = e.x - 3, y = e.y - 3, z = z}
		L.flags[#L.flags + 1] = {x = e.x + 3, y = e.y - 3, z = z}
		-- where a player arrives: the ring 2 tiles around the exit circle
		local spots = {}
		for dx = -2, 2 do
			for dy = -2, 2 do
				if max(abs(dx), abs(dy)) == 2 then
					spots[#spots + 1] = {x = e.x + dx, y = e.y + dy, z = z}
				end
			end
		end
		L.entrySpots[i] = spots
	end
	for _, w in ipairs(RUIN_WALLS) do
		L.walls[#L.walls + 1] = at(w[1], w[2])
		L.walls[#L.walls + 1] = at(turn(w[1], w[2]))
	end
	for _, q in ipairs(RUIN_PILLARS) do
		L.pillars[#L.pillars + 1] = at(q[1], q[2])
		L.pillars[#L.pillars + 1] = at(turn(q[1], q[2]))
	end
	-- the lights beside the objectives (blocking, never in the way: the capture circle keeps its centre and sides free)
	if look then
		local sx, sy = cx, cy
		local function fixture(def, bx, by)
			for _, d in ipairs(def.at) do
				local f = at(bx + d[1], by + d[2])
				f.id = def.id
				L.fixtures[#L.fixtures + 1] = f
			end
		end
		fixture(look.shrineLights, sx, sy)
		fixture(look.shrineBeacons, sx, sy)
		for _, p in ipairs(exitsLocal) do
			fixture(look.gateLights, p[1], p[2])
		end
	end
	for _, list in ipairs({L.walls, L.pillars, L.flags, L.fixtures, {L.shrine}}) do
		for _, p in ipairs(list) do
			block(p.x - o.x, p.y - o.y)
		end
	end
	-- spawn points: a grid, away from the gates and the shrine, never on a wall, a pillar or a light
	local m = cfg.monsters
	local step = m.spawnSpacing or 9
	local spawnNear = {} -- tiles next to a spawn point stay free of cover
	for y = 4, H - 3, step do
		for x = 4, W - 3, step do
			local p = at(x, y)
			local far = true
			for _, e in ipairs(L.exits) do
				if max(abs(p.x - e.x), abs(p.y - e.y)) < (m.keepAway.exit or 9) then
					far = false
				end
			end
			if max(abs(p.x - L.shrine.x), abs(p.y - L.shrine.y)) < (m.keepAway.shrine or 7) then
				far = false
			end
			if far and not blocked[key(x, y)] then
				L.spawns[#L.spawns + 1] = p
				for dx = -1, 1 do
					for dy = -1, 1 do
						spawnNear[key(x + dx, y + dy)] = true
					end
				end
			end
		end
	end
	if not look then
		return L
	end

	-- ------------------------------------------------------------ ground: natural patches, paved places, roads
	local nat = {} -- local key -> "rock" | "basalt" | "cracks"
	local pav = {} -- local key -> "ring" | "gate" | "road" | "hall"
	for y = 1, H do
		for x = 1, W do
			nat[key(x, y)] = "rock"
		end
	end
	local function paintPatch(pt, px, py)
		for y = max(1, floor(py - pt.ry - 2)), min(H, floor(py + pt.ry + 2)) do
			for x = max(1, floor(px - pt.rx - 2)), min(W, floor(px + pt.rx + 2)) do
				local kx, ky = canon(x, y)
				local noise = (roll(kx, ky, 11) - 50) / 50 * 0.4
				local ex2, ey2 = (x - px) / pt.rx, (y - py) / pt.ry
				if ex2 * ex2 + ey2 * ey2 + noise < 1 then
					nat[key(x, y)] = pt.kind
				end
			end
		end
	end
	for _, pt in ipairs(look.patches) do
		paintPatch(pt, pt.x, pt.y)
		local tx, ty = turn(pt.x, pt.y)
		paintPatch(pt, tx, ty)
	end
	-- a basalt field never touches the crack ground (no border piece joins them): the basalt tile gives way to rock
	for y = 1, H do
		for x = 1, W do
			if nat[key(x, y)] == "basalt" then
				for _, d in ipairs(D8) do
					if nat[key(x + d[1], y + d[2])] == "cracks" then
						nat[key(x, y)] = "rock"
						break
					end
				end
			end
		end
	end
	for y = 1, H do
		for x = 1, W do
			local pos = at(x, y)
			if K.inShrine(cfg, L, pos) or K.exitAt(cfg, L, pos) then
				pav[key(x, y)] = "ring"
			end
		end
	end
	local function paveRect(x1, y1, x2, y2, kind)
		for y = max(1, y1), min(H, y2) do
			for x = max(1, x1), min(W, x2) do
				if not pav[key(x, y)] then
					pav[key(x, y)] = kind
				end
			end
		end
	end
	for _, p in ipairs(exitsLocal) do
		paveRect(p[1] - 5, p[2] - 5, p[1] + 5, p[2] + 5, "gate")
	end
	local pr = look.plazaRadius or 6
	paveRect(cx - pr, cy - pr, cx + pr, cy + pr, "gate")
	for _, w in ipairs({{11, 11, 14, 14}}) do -- the floor of the ruined hall (its turn is the other hall)
		paveRect(w[1], w[2], w[3], w[4], "hall")
		paveRect(W + 1 - w[3], H + 1 - w[4], W + 1 - w[1], H + 1 - w[2], "hall")
	end
	local function paveRoad(wp)
		for i = 1, #wp - 1 do
			local a, b = wp[i], wp[i + 1]
			local dx, dy = b[1] > a[1] and 1 or (b[1] < a[1] and -1 or 0), b[2] > a[2] and 1 or (b[2] < a[2] and -1 or 0)
			local x, y = a[1], a[2]
			assert(dx == 0 or dy == 0, "roads run along one axis")
			while true do
				for w = -1, 1 do
					local px, py = x + (dy ~= 0 and w or 0), y + (dx ~= 0 and w or 0)
					if inside(px, py) and not pav[key(px, py)] and not blocked[key(px, py)] then
						pav[key(px, py)] = "road"
					end
				end
				if x == b[1] and y == b[2] then
					break
				end
				x, y = x + dx, y + dy
			end
		end
	end
	for _, road in ipairs(look.roads) do
		paveRoad(road)
		local t = {}
		for i, p in ipairs(road) do
			local tx, ty = turn(p[1], p[2])
			t[i] = {tx, ty}
		end
		paveRoad(t)
	end

	-- ------------------------------------------------------------ cover: clumps that never cut the field
	local covered = {}
	local freeTotal = 0
	for y = 1, H do
		for x = 1, W do
			if not blocked[key(x, y)] then
				freeTotal = freeTotal + 1
			end
		end
	end
	local function isFree(x, y)
		return inside(x, y) and not blocked[key(x, y)]
	end
	local function reachable()
		local seen, queue, head = {}, {}, 1
		local sx, sy = exitsLocal[1][1], exitsLocal[1][2]
		seen[key(sx, sy)] = true
		queue[1] = key(sx, sy)
		local n = 1
		while queue[head] do
			local k = queue[head]
			head = head + 1
			local x, y = k % 128, floor(k / 128)
			for i = 1, 4 do
				local d = D8[i]
				local nx, ny = x + d[1], y + d[2]
				local nk = key(nx, ny)
				if isFree(nx, ny) and not seen[nk] then
					seen[nk] = true
					n = n + 1
					queue[#queue + 1] = nk
				end
			end
		end
		return n
	end
	local keepClear = look.keepClear or 2
	local function nearGate(x, y)
		for _, p in ipairs(exitsLocal) do
			if max(abs(x - p[1]), abs(y - p[2])) <= 5 + keepClear then
				return true
			end
		end
		return false
	end
	local function coverOk(x, y, grp)
		local k = key(x, y)
		if not inside(x, y) or blocked[k] or pav[k] or spawnNear[k] or nearGate(x, y) then
			return false
		end
		if grp.on and nat[k] ~= grp.on then
			return false
		end
		return true
	end
	local function tryBlock(x, y, tx, ty)
		-- both tiles (a tile and its turn) or none
		local was = {}
		for _, p in ipairs({{x, y}, {tx, ty}}) do
			local ok = ringJoined(function(dx, dy)
				return isFree(p[1] + dx, p[2] + dy)
			end)
			was[#was + 1] = ok
			block(p[1], p[2])
		end
		local joined = was[1] and was[2]
		freeTotal = freeTotal - 2
		if not joined and reachable() ~= freeTotal then
			blocked[key(x, y)], blocked[key(tx, ty)] = nil, nil
			freeTotal = freeTotal + 2
			return false
		end
		return true
	end
	for gi, grp in ipairs(look.cover) do
		local centres = {}
		for _, cl in ipairs(grp.clumps) do
			centres[#centres + 1] = cl
			local tx, ty = turn(cl.x, cl.y)
			centres[#centres + 1] = {x = tx, y = ty, r = cl.r, chance = cl.chance}
		end
		for _, cl in ipairs(centres) do
			for dy = -cl.r, cl.r do
				for dx = -cl.r, cl.r do
					local x, y = cl.x + dx, cl.y + dy
					if dx * dx + dy * dy <= cl.r * cl.r + 1 and not covered[key(x, y)] and coverOk(x, y, grp) then
						local kx, ky = canon(x, y)
						local tx, ty = turn(x, y)
						if roll(kx, ky, 100 + gi) < cl.chance and (tx ~= x or ty ~= y) and not covered[key(tx, ty)]
								and coverOk(tx, ty, grp) and tryBlock(x, y, tx, ty) then
							local id = pick(grp.ids, kx, ky, 200 + gi)
							covered[key(x, y)], covered[key(tx, ty)] = id, id
							L.cover[#L.cover + 1] = {x = o.x + x, y = o.y + y, z = z, id = id}
							L.cover[#L.cover + 1] = {x = o.x + tx, y = o.y + ty, z = z, id = id}
						end
					end
				end
			end
		end
	end

	-- ------------------------------------------------------------ decoration (never blocks)
	local dec = look.decor
	local function decorate(x, y, set, salt)
		local kx, ky = canon(x, y)
		if set and roll(kx, ky, salt) < set.chance then
			local id = pick(set.ids, kx, ky, salt + 1)
			L.decor[#L.decor + 1] = {x = o.x + x, y = o.y + y, z = z, id = id}
			return true
		end
		return false
	end
	for y = 1, H do
		for x = 1, W do
			local k = key(x, y)
			if not blocked[k] then
				local kind = pav[k]
				if kind == "gate" then
					local d = max(abs(x - cx), abs(y - cy))
					if d <= pr then
						decorate(x, y, dec.plaza, 300)
					end
				elseif not kind then
					local n = nat[k]
					local edge = x == 1 or x == W or y == 1 or y == H
					if not (edge and decorate(x, y, dec.wall, 310)) then
						if n == "cracks" then
							decorate(x, y, dec.cracks, 320)
						elseif not decorate(x, y, dec.rock, 330) then
							decorate(x, y, dec.bones, 340)
						end
					end
				end
			end
		end
	end

	-- ------------------------------------------------------------ the ground items of every tile
	for y = 1, H do
		for x = 1, W do
			local k = key(x, y)
			local kx, ky = canon(x, y)
			local kind, gid, edges = pav[k], nil, {}
			if kind == "ring" then
				gid = cfg.ids.ring
			elseif kind == "gate" then
				gid = cfg.ids.gateGround
			elseif kind == "road" then
				gid = weighted(look.road, kx, ky, 400)
			elseif kind == "hall" then
				gid = look.hall
			else
				kind = "ground"
				local n = nat[k]
				gid = (n == "cracks" and look.cracks[1]) or (n == "basalt" and pick(look.basalt, kx, ky, 410)) or
					pick(look.rock, kx, ky, 420)
				local function is(fam, dx, dy)
					return nat[key(x + dx, y + dy)] == fam and not pav[key(x + dx, y + dy)]
				end
				local higher, set
				if n == "rock" then
					higher, set = "basalt", look.basaltEdge
				elseif n == "cracks" then
					higher, set = "rock", look.crackEdge
				end
				if higher then
					local names = ChaosAreaGenCore.borderPieces(is(higher, 0, -1), is(higher, 1, 0), is(higher, 0, 1),
						is(higher, -1, 0), is(higher, 1, -1), is(higher, -1, -1), is(higher, 1, 1), is(higher, -1, 1))
					for _, name in ipairs(names) do
						if set[name] then
							edges[#edges + 1] = set[name]
						end
					end
				end
				L.tiles[k] = {ground = kind, nat = n, gid = gid, edges = edges}
				kind = nil
			end
			if kind then
				L.tiles[k] = {ground = kind, gid = gid, edges = edges}
			end
		end
	end
	return L
end

local layoutCache = setmetatable({}, {__mode = "k"})

-- the layout of a slot (build mode), cached per config
function K.layout(cfg, slot)
	local c = layoutCache[cfg]
	if not c then
		c = {}
		layoutCache[cfg] = c
	end
	local m = cfg.monsters or {}
	local ka = m.keepAway or {}
	local k = table.concat({slot, cfg.field.innerW, cfg.field.innerH, cfg.grid.origin.x, cfg.grid.origin.y, cfg.grid.cols,
		cfg.grid.spacing, m.spawnSpacing or 9, ka.exit or 9, ka.shrine or 7, tostring(cfg.look)}, ":")
	if not c[k] then
		c[k] = buildLayout(cfg, slot)
	end
	return c[k]
end

-- map mode: the configured rectangle of the loaded map
function K.mapLayout(cfg)
	local a = cfg.area
	if not a then
		return nil
	end
	local L = {slot = 0, z = a.z, x1 = a.x1, y1 = a.y1, x2 = a.x2, y2 = a.y2, shrine = a.shrine, exits = a.exits or {},
		gates = {}, walls = {}, pillars = {}, flags = {}, spawns = a.spawns or {}, entrySpots = {}, map = true}
	for i, e in ipairs(L.exits) do
		local spots = {}
		for dx = -2, 2 do
			for dy = -2, 2 do
				if max(abs(dx), abs(dy)) == 2 then
					spots[#spots + 1] = {x = e.x + dx, y = e.y + dy, z = e.z or a.z}
				end
			end
		end
		L.entrySpots[i] = spots
	end
	return L
end

local function inRect(r, z, pos)
	return pos ~= nil and pos.z == z and pos.x >= r.x1 and pos.x <= r.x2 and pos.y >= r.y1 and pos.y <= r.y2
end
K.inRect = inRect

function K.inLayout(L, pos)
	return L ~= nil and inRect(L, L.z, pos)
end

-- the instance slot a position belongs to (the outer wall included), or nil
function K.slotOfPos(cfg, pos)
	if not pos then
		return nil
	end
	if cfg.mode == "map" then
		local L = K.mapLayout(cfg)
		return (L and K.inLayout(L, pos)) and 0 or nil
	end
	local g = cfg.grid
	if pos.z ~= g.origin.z then
		return nil
	end
	local dx, dy = pos.x - g.origin.x, pos.y - g.origin.y
	if dx < 0 or dy < 0 then
		return nil
	end
	local col, row = floor(dx / g.spacing), floor(dy / g.spacing)
	if col >= g.cols then
		return nil
	end
	local slot = row * g.cols + col
	if slot >= g.slots then
		return nil
	end
	local lx, ly = dx - col * g.spacing, dy - row * g.spacing
	if lx > cfg.field.innerW + 1 or ly > cfg.field.innerH + 1 then
		return nil
	end
	return slot
end

-- index of the safe exit whose circle holds pos, or nil
function K.exitAt(cfg, L, pos)
	if not pos or pos.z ~= L.z then
		return nil
	end
	local r = cfg.exit.radius
	for i, e in ipairs(L.exits) do
		if abs(pos.x - e.x) <= r and abs(pos.y - e.y) <= r then
			return i
		end
	end
	return nil
end

-- the safe exit nearest to pos (index)
function K.nearestExit(L, pos)
	local best, bd
	for i, e in ipairs(L.exits) do
		local d = max(abs(pos.x - e.x), abs(pos.y - e.y))
		if not bd or d < bd then
			best, bd = i, d
		end
	end
	return best
end

function K.inShrine(cfg, L, pos)
	return pos ~= nil and L.shrine ~= nil and pos.z == L.z and abs(pos.x - L.shrine.x) <= cfg.contest.capture.radius
		and abs(pos.y - L.shrine.y) <= cfg.contest.capture.radius
end

-- every tile of a build-mode instance once: {x, y, z, wall = bool, ground = "ground" | "gate" | "ring" | "road" | "hall",
-- gid = the ground item, edges = border pieces over it}
function K.footprint(cfg, L)
	local walls = {}
	for _, w in ipairs(L.walls) do
		walls[w.x .. "," .. w.y] = true
	end
	local list = {}
	for x = L.x1, L.x2 do
		for y = L.y1, L.y2 do
			local wall = x == L.x1 or x == L.x2 or y == L.y1 or y == L.y2 or walls[x .. "," .. y] == true
			local info = L.tiles and L.tiles[(y - L.y1) * 128 + (x - L.x1)]
			local t = {x = x, y = y, z = L.z, wall = wall, ground = "ground", edges = {}}
			if info then
				t.ground, t.gid, t.edges = info.ground, info.gid, info.edges
			else
				local pos = {x = x, y = y, z = L.z}
				if K.inShrine(cfg, L, pos) or K.exitAt(cfg, L, pos) then
					t.ground = "ring"
				else
					for _, g in ipairs(L.gates) do
						if inRect(g, L.z, pos) then
							t.ground = "gate"
						end
					end
				end
			end
			list[#list + 1] = t
		end
	end
	return list
end

-- the tiles nothing can walk on: ruin walls, pillars, flags, lights, cover, the shrine (the outer wall is the footprint's)
function K.blockedSet(L)
	local set = {}
	for _, list in ipairs({L.walls, L.pillars, L.flags, L.fixtures or {}, L.cover or {}, {L.shrine}}) do
		for _, p in ipairs(list) do
			set[p.x .. "," .. p.y] = true
		end
	end
	return set
end

-- ====================================================================== entering, login, protection, exit
-- p = {level, enabled, inside, hc, hcAccept, accept, inPz, inCombat, elsewhere (text), multiClient, cooldown (seconds
-- left), realmOk, staff}. Returns nil (may enter) or the reason. accept = the confirmation was given.
function K.entryRefusal(cfg, p)
	if not cfg.enabled or p.enabled == false then
		return string.format("%s are closed.", cfg.name)
	end
	if p.inside then
		return string.format("You are already in %s.", cfg.name)
	end
	if (p.level or 0) < cfg.minLevel then
		return string.format("You need level %d to enter %s.", cfg.minLevel, cfg.name)
	end
	if p.hc and not p.staff then
		if not (cfg.hardcore and cfg.hardcore.allow) then
			return "Hardcore characters cannot enter the Marches: a Hardcore life is not staked in open PvP."
		end
		if not p.hcAccept then
			return "Hardcore: confirm that a defeat in the Marches may end your Hardcore run."
		end
	end
	if p.realmOk == false then
		return string.format("Characters of your realm cannot enter %s.", cfg.name)
	end
	if (p.cooldown or 0) > 0 then
		return string.format("You were defeated in the Marches. You can enter again in %d seconds.", floor(p.cooldown + 0.5))
	end
	if p.multiClient then
		return "You cannot enter the Marches while another character from your connection is online."
	end
	if p.elsewhere then
		return string.format("You cannot enter the Marches while in %s.", p.elsewhere)
	end
	if p.inCombat then
		return "You cannot enter the Marches while in combat."
	end
	if cfg.entry.needPz and not p.inPz then
		return "You can only enter the Marches from a protection zone."
	end
	if not p.accept then
		return "Read and accept the rules of the Marches first."
	end
	return nil
end

-- login inside: held (no damage) until moveAt, then moved to the nearest safe exit and protected until protectUntil
function K.loginTimes(cfg, now)
	local moveAt = now + cfg.login.holdSeconds
	return moveAt, moveAt + cfg.login.protectSeconds
end

function K.protected(untilAt, now)
	return (tonumber(untilAt) or 0) > now
end

-- the battle lock inside the Marches (the engine's CONDITION_INFIGHT: the PvP lock and the white skull ride on it; every
-- player hit renews it with the server's pzLocked time). ticks = what is left of it (ms). Returns the ticks to set when
-- it runs longer than cfg.combatLock.maxSeconds, else nil (leave it).
function K.lockTicks(cfg, ticks)
	local cap = (cfg.combatLock or {}).maxSeconds
	ticks = tonumber(ticks)
	if not cap or cap <= 0 or not ticks then
		return nil
	end
	cap = floor(cap * 1000)
	if ticks > cap then
		return cap
	end
	return nil
end

-- where a defeated player goes: "temple" (the home town's temple, as a death anywhere else) or "entry" (where he
-- entered the Marches). entryOk = that place is still a valid tile outside the zone.
function K.defeatDestination(cfg, entryOk)
	local want = (cfg.death or {}).respawn or "temple"
	if want == "entry" and entryOk then
		return "entry"
	end
	return "temple"
end

-- the exit channel: standing in a safe exit circle since `since` (nil = not in one), last damage dealt or taken at
-- `lastCombat`. Returns nil (not channelling), or the share done (0..1) and true once it is complete.
function K.exitProgress(cfg, since, lastCombat, now)
	if not since then
		return nil
	end
	local from = max(since, tonumber(lastCombat) or 0)
	local need = max(1, cfg.exit.channelSeconds)
	local share = clamp((now - from) / need, 0, 1)
	return share, share >= 1
end

-- ====================================================================== embers
function K.addCarried(cfg, carried, amount)
	carried, amount = max(0, floor(carried or 0)), max(0, floor(amount or 0))
	local room = max(0, cfg.carry.max - carried)
	local added = min(room, amount)
	return carried + added, added, amount - added
end

function K.monsterEmbers(cfg, tier)
	return cfg.monsterEmbers[tier or "normal"] or cfg.monsterEmbers.normal or 0
end

-- a defeat: the pile that falls and what burns
function K.deathPile(cfg, carried)
	carried = max(0, floor(carried or 0))
	local pile = floor(carried * clamp(cfg.death.dropShare or 1, 0, 1))
	return pile, carried - pile
end

-- a new pile record. killerGuid = nil: a monster's victim (anyone at once); counted = false: the defeat failed the
-- anti-farming rules (the pile burns at once: amount 0)
function K.newPile(cfg, amount, victimGuid, killerGuid, counted, now)
	local p = {amount = max(0, floor(amount or 0)), victim = victimGuid, owner = killerGuid, taken = {}, at = now,
		expiresAt = now + cfg.death.pileSeconds}
	p.ownerUntil = killerGuid and (now + cfg.death.ownerSeconds) or now
	if counted == false then
		p.burned, p.amount = p.amount, 0
	end
	return p
end

-- what `picker` = {guid, carried, dayPicked, ssf} may take from pile now. Returns the amount, the reason when 0
-- ("gone", "owner", "ssf", "kill cap", "daily cap", "full"), and whether it counts for the daily cap (not the own pile).
function K.pickup(cfg, pile, picker, now)
	if not pile or pile.amount <= 0 or now >= pile.expiresAt then
		return 0, "gone", false
	end
	local own = picker.guid == pile.victim
	if not own and pile.owner and now < pile.ownerUntil and picker.guid ~= pile.owner then
		return 0, "owner", false
	end
	if not own and picker.ssf and not (cfg.ssf and cfg.ssf.takePiles) then
		return 0, "ssf", false
	end
	local take = pile.amount
	if not own then
		take = min(take, max(0, cfg.pickup.perKillMax - (pile.taken[picker.guid] or 0)))
		if take <= 0 then
			return 0, "kill cap", false
		end
		take = min(take, max(0, cfg.pickup.perDayMax - (picker.dayPicked or 0)))
		if take <= 0 then
			return 0, "daily cap", true
		end
	end
	take = min(take, max(0, cfg.carry.max - (picker.carried or 0)))
	if take <= 0 then
		return 0, "full", not own
	end
	return take, nil, not own
end

-- take `n` from the pile (after K.pickup said so)
function K.takeFrom(pile, guid, n)
	pile.amount = max(0, pile.amount - n)
	pile.taken[guid] = (pile.taken[guid] or 0) + n
	return pile.amount
end

-- banking at a safe exit: new banked balance, moved, lost (over the bank cap)
function K.bank(cfg, banked, carried)
	banked, carried = max(0, floor(banked or 0)), max(0, floor(carried or 0))
	local room = max(0, cfg.bankMax - banked)
	local moved = min(room, carried)
	return banked + moved, moved, carried - moved
end

-- ====================================================================== player rows
function K.newRow()
	return {banked = 0, total = 0, kills = 0, defeats = 0, captures = 0, haul = 0, pledge = "", pledgeAt = 0,
		day = 0, dayRep = 0, dayPicked = 0, week = 0, weekBanked = 0}
end

-- new day / week: the counters start again
function K.roll(row, day, week)
	if row.day ~= day then
		row.day, row.dayRep, row.dayPicked = day, 0, 0
	end
	if row.week ~= week then
		row.week, row.weekBanked = week, 0
	end
	return row
end

-- the saved columns of a row as one string: pvpzone.lua writes a row only when this changed since it was loaded or
-- last written (most characters never enter the Marches, and their logout wrote the same row every time)
function K.rowSig(row)
	return table.concat({row.banked or 0, row.total or 0, row.kills or 0, row.defeats or 0, row.captures or 0,
		row.haul or 0, row.pledge or "", row.pledgeAt or 0, row.day or 0, row.dayRep or 0, row.dayPicked or 0,
		row.week or 0, row.weekBanked or 0}, "|")
end

-- ====================================================================== kills: anti-farming and reputation
-- k = {killerAccount, victimAccount, killerIp, victimIp, killerLevel, victimLevel, enteredAt (the victim's entry),
-- at, lastCounted (this killer's last counted defeat of this victim, or nil)}. Returns counted, reason ("ok" or why not).
function K.killVerdict(cfg, k)
	local r = cfg.antiFarm
	if r.sameAccount and (k.killerAccount or 0) ~= 0 and k.killerAccount == k.victimAccount then
		return false, "same account"
	end
	if r.sameIp and (k.killerIp or 0) ~= 0 and k.killerIp == k.victimIp then
		return false, "same IP"
	end
	local vl, kl = tonumber(k.victimLevel) or 0, tonumber(k.killerLevel) or 0
	if vl < cfg.minLevel then
		return false, "low level"
	end
	if r.minLevelRatio and vl < kl * r.minLevelRatio then
		return false, "level gap"
	end
	if r.minSecondsInside and k.enteredAt and (k.at or 0) - k.enteredAt < r.minSecondsInside then
		return false, "just arrived"
	end
	if k.lastCounted and r.sameVictimMinutes and (k.at or 0) - k.lastCounted < r.sameVictimMinutes * 60 then
		return false, "repeat"
	end
	return true, "ok"
end

-- reputation for a counted defeat: killer pledged to `kf`, victim to `vf` (nil / "" = none), `rivalOf` = faction key ->
-- its sworn rival, `given` = reputation from Marches kills given today. Returns amount, reason.
function K.repFor(cfg, kf, vf, rivalOf, given)
	local r = cfg.reputation
	if not kf or kf == "" then
		return 0, "not pledged"
	end
	if not vf or vf == "" then
		return 0, "victim not pledged"
	end
	if kf == vf then
		return 0, "same faction"
	end
	local mult = (rivalOf and rivalOf[kf] == vf) and r.rivalMult or r.otherMult
	local amount = floor(r.perKill * mult + 0.5)
	local room = max(0, r.dailyCap - (given or 0))
	if room <= 0 then
		return 0, "daily cap"
	end
	return min(amount, room), nil
end

-- may a character pledge to `key`? ranks = factions_config.lua ranks, rep = its reputation with that faction,
-- current / changedAt = the pledge now and when it was made. Returns nil or the reason.
function K.pledgeRefusal(cfg, factions, ranks, key, rep, current, changedAt, now)
	local f
	for _, x in ipairs(factions or {}) do
		if x.key == key then
			f = x
		end
	end
	if not f then
		return "Unknown faction."
	end
	if current == key then
		return string.format("You already fight for %s.", f.name)
	end
	local need
	for _, r in ipairs(ranks or {}) do
		if r.key == cfg.reputation.minRank then
			need = r
		end
	end
	if need and (tonumber(rep) or 0) < need.min then
		return string.format("%s does not trust you enough: you need the rank %s.", f.name, need.name)
	end
	local wait = (tonumber(changedAt) or 0) + cfg.reputation.changeHours * 3600 - now
	if current and current ~= "" and wait > 0 then
		return string.format("You can change your pledge in %d hour(s).", math.ceil(wait / 3600))
	end
	return nil
end

-- ====================================================================== PvP scaling (the battleground's numbers)
-- damage of a level-ls player to a level-lt player is multiplied by this; the target's battleground bracket sets the
-- reference level (battleground_core.lua normFactor with its `normalise`)
function K.pvpFactor(bg, ls, lt)
	if not bg or not bg.normalise then
		return 1
	end
	lt = max(1, tonumber(lt) or 1)
	local ref
	for _, b in ipairs(bg.brackets or {}) do
		if lt >= b.min and (not b.max or lt <= b.max) then
			ref = b.ref
		end
	end
	ref = ref or (bg.brackets and bg.brackets[1] and bg.brackets[1].ref) or lt
	local n = bg.normalise
	local out = clamp((ref / max(1, tonumber(ls) or 1)) ^ n.exponent, n.minFactor, n.maxFactor)
	local inn = clamp((lt / ref) ^ n.exponent, n.minFactor, n.maxFactor)
	return out * inn
end

-- ====================================================================== the Cinder Shrine
function K.newContest(cfg, now)
	return {phase = "idle", nextAt = now + cfg.contest.firstMinutes * 60, progress = {}}
end

-- one capture step: counts = faction key -> pledged players in the circle, dt seconds. Returns the faction that
-- reached 100, or nil; and "contested" when two or more factions stand inside.
function K.captureStep(cfg, progress, counts, dt)
	local c = cfg.contest.capture
	local present = {}
	for key, n in pairs(counts or {}) do
		if n > 0 then
			present[#present + 1] = key
		end
	end
	if #present >= 2 then
		return nil, "contested"
	end
	local only = present[1]
	for key, v in pairs(progress) do
		if key ~= only then
			progress[key] = max(0, v - c.decayPerSecond * dt)
		end
	end
	if not only then
		return nil, nil
	end
	local n = counts[only]
	local rate = (100 / c.seconds) * min(c.maxRate, 1 + c.perExtra * (n - 1))
	progress[only] = min(100, (progress[only] or 0) + rate * dt)
	if progress[only] >= 100 then
		return only, nil
	end
	return nil, nil
end

-- the contest clock. info = {counts, wardenAlive, dt}. Returns a list of events:
--   {kind = "start"}       the warden must be spawned (phase "warden")
--   {kind = "warden"}      the warden fell: the shrine can be taken (phase "capture")
--   {kind = "captured", faction}
--   {kind = "expired"}     the window closed without a holder
function K.contestTick(cfg, c, now, info)
	local ev = {}
	local cc = cfg.contest
	if c.phase == "idle" then
		if now >= c.nextAt then
			c.phase, c.startedAt, c.endsAt = "warden", now, now + cc.windowMinutes * 60
			c.nextAt = now + cc.everyMinutes * 60
			c.progress, c.contested = {}, false
			ev[#ev + 1] = {kind = "start"}
		end
		return ev
	end
	if now >= (c.endsAt or now) then
		c.phase, c.contested = "idle", false
		ev[#ev + 1] = {kind = "expired"}
		return ev
	end
	if c.phase == "warden" then
		if not info.wardenAlive then
			c.phase = "capture"
			ev[#ev + 1] = {kind = "warden"}
		end
		return ev
	end
	if c.phase == "capture" then
		local winner, state = K.captureStep(cfg, c.progress, info.counts, info.dt or 1)
		c.contested = state == "contested"
		if winner then
			c.phase, c.winner, c.contested = "idle", winner, false
			ev[#ev + 1] = {kind = "captured", faction = winner}
		end
	end
	return ev
end

function K.newControl(cfg, faction, now)
	return {faction = faction, at = now, untilAt = now + cfg.contest.holdMinutes * 60}
end

-- the faction holding the shrine now (nil when nobody or the hold ran out)
function K.holder(control, now)
	if control and control.faction and control.faction ~= "" and (control.untilAt or 0) > now then
		return control.faction
	end
	return nil
end

-- the faction-wide buff: 1 + percent / 100 for a character pledged to the holder, else 1. kind "exp" | "loot"
function K.buffMult(cfg, control, pledge, now, kind)
	local h = K.holder(control, now)
	if h and pledge and pledge == h then
		return 1 + (cfg.contest.buff[kind] or 0) / 100
	end
	return 1
end

-- ====================================================================== vendor
function K.offer(cfg, key)
	for _, o in ipairs(cfg.vendor) do
		if o.key == key then
			return o
		end
	end
	return nil
end

-- may it be bought? banked = the balance, bought = purchases of it this week, owns(cosmeticKey) -> bool
function K.vendorCheck(cfg, key, banked, bought, owns)
	local o = K.offer(cfg, key)
	if not o then
		return false, "Unknown offer.", nil
	end
	if o.kind == "cosmetic" and owns and owns(o.cosmetic) then
		return false, "You already own it.", o
	end
	if o.weekly and (bought or 0) >= o.weekly then
		return false, string.format("Weekly limit reached (%d).", o.weekly), o
	end
	if (banked or 0) < o.cost then
		return false, string.format("You need %d more banked embers.", o.cost - (banked or 0)), o
	end
	return true, nil, o
end

return K
