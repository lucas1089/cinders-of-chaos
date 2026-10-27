-- The look of the runtime-built fight arenas (O276): pure logic, no engine calls (tests/arenalook_test.lua).
-- Used by the Infinity Tower, the world / pocket / guild / Ascended boss arenas, the ranked PvP arena and the other
-- rooms built with Game.createTile. The Scorched Marches (pvpzone_core.lua) was the model: varied ground with border
-- pieces, a road to the middle, mirrored cover, lights and decoration, all from a hash of the coordinates (no
-- math.random), so every slot of a grid looks the same and a test can check it.
--
--   ChaosArenaLook.themeFor(key)                         theme name of a boss / band / room key (keywords, else a hash)
--   ChaosArenaLook.theme(name, darkIds)                  the theme table; "dark" needs darkIds (name -> server id or nil)
--                                                        and falls back to "ember" when the dark set is not installed
--   ChaosArenaLook.generate(spec)                        the look of a room (below)
--   ChaosArenaLook.apply(look, io)                       creates the items through io (below)
--   ChaosArenaLook.reachable(floor, blocked, from)       set of floor keys reachable from `from` (4 directions)
--   ChaosArenaLook.rectTiles(x1, y1, x2, y2)             floor tile list of a rectangle
--   ChaosArenaLook.key(x, y)
--
-- spec = {
--   tiles   list of {x, y}: the walkable floor tiles (any shape; walls are every tile that is not in the list)
--   theme   a theme table (ChaosArenaLook.theme)
--   seed    integer (default 1); the same spec gives the same look
--   keep    list of {x, y, r}: positions that stay open (spawn points, entry, exit, boss): nothing solid within r
--   mirror  true: cover and lights come in pairs turned 180 degrees (fair for PvP and for both ends of a hall); only
--           tiles whose mirror image is floor take part
--   roads   list of {from = {x, y}, to = {x, y}}: paved lanes, kept free of cover
--   lights  how many light fixtures at most (default 6; they stand against the wall, blocking, spaced out)
--   cover   percent of the floor that gets a cover piece, at most (default theme.cover.percent)
-- }
-- look = {tiles = {[key] = {x, y, gid, edges = {id...}, decor = id|nil, cover = id|nil, light = id|nil, road = bool,
--   rim = bool}}, order = {key...} (sorted), blocked = {[key] = true}, covers = n, lights = n, theme = name,
--   wallId = id, floorCount = n}
-- Guarantees (tests/arenalook_test.lua): the floor tiles that are not blocked stay one 4-connected field; every `keep`
-- point and every road tile is free and reachable; no two solid pieces touch (not even on a diagonal), so a lane is
-- never narrower than one tile and no corner pinches; the tiles within `r` (+1) of a keep point carry nothing solid.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosAreaGenCore then
	dofile("data/scripts/chaos/areagen_core.lua") -- borderPieces
end

ChaosArenaLook = ChaosArenaLook or {}
local A = ChaosArenaLook

local function key(x, y)
	return x .. "," .. y
end
A.key = key

local function hashN(a, b, c)
	local h = (a * 73856093 + b * 19349663 + (c or 0) * 83492791) % 2147483629
	h = (h * 48271) % 2147483629
	return (h * 48271 + 12345) % 2147483629
end

local function roll(a, b, c) -- 0 .. 99.99
	return hashN(a, b, c) % 10000 / 100
end

local function weighted(list, a, b, c)
	local total = 0
	for _, e in ipairs(list) do
		total = total + (e[2] or 1)
	end
	local r = hashN(a, b, c) % total
	for _, e in ipairs(list) do
		if r < (e[2] or 1) then
			return e[1]
		end
		r = r - (e[2] or 1)
	end
	return list[1][1]
end

local function pick(list, a, b, c)
	return list[hashN(a, b, c) % #list + 1]
end

-- ====================================================================== themes (stock ids only)
-- Every id is one the generated hunting areas or the Scorched Marches already use (areagen_config.lua families,
-- pvpzone_config.lua look). base: weighted grounds; patches: blobs of another ground (edge = border pieces drawn over
-- the neighbours, or around the blob when lower = true); rim: the ground along the wall; road: paved lanes; cover:
-- solid pieces; light: solid fixtures with light; decor: walkable pieces.
local BASALT_EDGE = {n = 17630, e = 17631, s = 17629, w = 17632, cnw = 17639, cne = 17640, csw = 17638, cse = 17637,
	dnw = 17635, dne = 17636, dsw = 17634, dse = 17633}
local CRACK_EDGE = {n = 7079, e = 7080, s = 7081, w = 7082, cnw = 7083, cne = 7084, csw = 7085, cse = 7086,
	dnw = 7087, dne = 7088, dsw = 7089, dse = 7090}
local FLAGSTONE = {{3152, 25}, {3153, 25}, {3154, 5}, {3155, 5}, {3156, 3}, {3157, 1}}

A.THEMES = {
	-- scorched rock, basalt fields and lava cracks: fire, ember, dragons
	ember = {
		wall = 5648,
		base = {{9068, 1}, {9069, 1}, {9070, 1}, {9071, 1}, {9072, 1}, {9073, 1}},
		patches = {
			{grounds = {{17625, 1}, {17626, 1}, {17627, 1}, {17628, 1}}, edge = BASALT_EDGE, count = {3, 5}, r = {2, 4}},
			{grounds = {{5815, 1}}, edge = CRACK_EDGE, lower = true, count = {1, 3}, r = {2, 3}}
		},
		rim = {413}, road = {{414, 1}},
		cover = {percent = 5, ids = {24939, 24940, 24941, 24942, 24943, 24944, 22110, 22111, 22112, 22113}},
		light = {1481, 1486},
		decor = {percent = 6, ids = {3610, 3611, 3613, 1320, 1325, 3124, 3125, 3126}},
		wallDecor = {percent = 14, ids = {1308, 1311, 1313, 1315, 1320, 1325}}
	},
	-- flagstone halls and marble: castles, guardians, stone giants
	stone = {
		wall = 5648,
		base = {{413, 8}, {407, 1}},
		patches = {{grounds = {{407, 1}}, count = {3, 5}, r = {2, 4}}, {grounds = {{414, 1}}, count = {1, 2}, r = {2, 3}}},
		rim = {407}, road = FLAGSTONE,
		cover = {percent = 5, ids = {1515, 24939, 24940}},
		light = {1481, 1486},
		decor = {percent = 5, ids = {1308, 1311, 1313, 1315, 3610, 3611}},
		wallDecor = {percent = 12, ids = {1308, 1311, 1313, 1315}}
	},
	-- slate, rock and bones: crypts, the dead, the cold
	crypt = {
		wall = 5648,
		base = {{10766, 25}, {10767, 20}, {10768, 20}, {10769, 10}, {10770, 5}, {10771, 3}},
		patches = {{grounds = {{9068, 1}, {9069, 1}, {9070, 1}}, count = {3, 5}, r = {2, 4}},
			{grounds = {{13189, 3}, {12237, 2}}, count = {1, 3}, r = {2, 3}}},
		rim = {413}, road = FLAGSTONE,
		cover = {percent = 5, ids = {6395, 6396, 6398, 6400, 11253, 24941, 24942}},
		light = {1481, 1486},
		decor = {percent = 7, ids = {3124, 3125, 3126, 6524, 7567, 3610}},
		wallDecor = {percent = 12, ids = {1308, 1311, 3124, 3125}}
	}
}
A.THEME_NAMES = {"ember", "stone", "crypt"}

-- the dark tile set (data/lib/chaos_dark_tiles.lua) as one more theme. darkIds(name) -> server id or nil.
local DARK_NAMES = {"obsidian_floor", "magma_floor", "ash_soil", "ruined_floor", "obsidian_wall", "brazier",
	"standing_torch", "dark_boulder", "broken_pillar", "rock_outcrop", "rubble", "bone_pile", "blood_crystals",
	"ash_soil_border_n", "ash_soil_border_e", "ash_soil_border_s", "ash_soil_border_w", "ash_soil_border_outer_ne",
	"ash_soil_border_outer_nw", "ash_soil_border_outer_se", "ash_soil_border_outer_sw", "ash_soil_border_inner_ne",
	"ash_soil_border_inner_nw", "ash_soil_border_inner_se", "ash_soil_border_inner_sw"}

local function darkTheme(darkIds)
	if type(darkIds) ~= "function" then
		return nil
	end
	local id = {}
	for _, n in ipairs(DARK_NAMES) do
		id[n] = darkIds(n)
		if not id[n] then
			return nil
		end
	end
	local p = "ash_soil_border_"
	local edge = {n = id[p .. "n"], e = id[p .. "e"], s = id[p .. "s"], w = id[p .. "w"],
		cnw = id[p .. "outer_nw"], cne = id[p .. "outer_ne"], csw = id[p .. "outer_sw"], cse = id[p .. "outer_se"],
		dnw = id[p .. "inner_nw"], dne = id[p .. "inner_ne"], dsw = id[p .. "inner_sw"], dse = id[p .. "inner_se"]}
	return {
		name = "dark",
		wall = id.obsidian_wall,
		base = {{id.obsidian_floor, 92}, {id.magma_floor, 8}},
		patches = {{grounds = {{id.ash_soil, 1}}, edge = edge, count = {3, 5}, r = {2, 3}}},
		rim = {id.ruined_floor}, road = {{id.ruined_floor, 1}},
		cover = {percent = 5, ids = {id.dark_boulder, id.broken_pillar, id.rock_outcrop, id.blood_crystals}},
		light = {id.brazier, id.standing_torch},
		decor = {percent = 6, ids = {id.rubble, id.bone_pile}},
		wallDecor = {percent = 12, ids = {id.rubble, id.bone_pile}},
		wallSize = 2, -- obsidian_wall is a 2x2 sprite
		dark = true
	}
end

-- name -> theme table (never nil: "dark" without the set, or an unknown name, gives "ember")
function A.theme(name, darkIds)
	if name == "dark" then
		local t = darkTheme(darkIds)
		if t then
			return t
		end
		name = "ember"
	end
	local t = A.THEMES[name]
	if not t then
		name = "ember"
		t = A.THEMES.ember
	end
	t.name = name
	return t
end

-- the walls of the dark set are 2x2 sprites (drawn one tile up and left of their tile): a look made for such a wall keeps
-- lights and decoration off the floor row / column in front of it (spec.wallSize)
local DARK_WALL_NAMES = {"dark_wall", "ruined_wall", "obsidian_wall"}
function A.wallSizeOf(wallId)
	for _, n in ipairs(DARK_WALL_NAMES) do
		if wallId ~= nil and A.darkIds(n) == wallId then
			return 2
		end
	end
	return 1
end

-- where a fixture of the layout (a corner basin) stands when the walls are `wallSize` big: the floor row south of a
-- 2x2 wall and the column east of it are drawn over, so the fixture moves one tile in. p = {x, y, z}; rects = floor
-- rectangles {x1, y1, x2, y2} (the one that holds p is used). Returns a new table.
function A.fixtureSpot(p, rects, wallSize)
	local out = {x = p.x, y = p.y, z = p.z}
	if (wallSize or 1) > 1 then
		for _, r in ipairs(rects) do
			if p.x >= r.x1 and p.x <= r.x2 and p.y >= r.y1 and p.y <= r.y2 then
				if p.x == r.x2 then
					out.x = p.x - (wallSize - 1)
				end
				if p.y == r.y2 then
					out.y = p.y - (wallSize - 1)
				end
				break
			end
		end
	end
	return out
end

local KEYWORDS = {
	{"dark", {"shadow", "abyss", "void", "dark", "nightmare", "demon", "hell", "infernal", "plague", "ascended", "cinder"}},
	{"ember", {"fire", "flame", "ember", "lava", "magma", "ash", "burn", "inferno", "dragon", "scorch", "ferumbras"}},
	{"crypt", {"bone", "death", "grave", "necro", "undead", "lich", "vampire", "ghost", "wraith", "ice", "frost", "cold",
		"crypt", "banshee", "soul"}}
}

-- the theme name for a key (a boss name, a band label, a room kind); "dark" is only a wish: A.theme falls back
function A.themeFor(k)
	local s = tostring(k or ""):lower()
	for _, entry in ipairs(KEYWORDS) do
		for _, w in ipairs(entry[2]) do
			if s:find(w, 1, true) then
				return entry[1]
			end
		end
	end
	local sum = 0
	for i = 1, #s do
		sum = (sum * 31 + s:byte(i)) % 1000003
	end
	return A.THEME_NAMES[sum % #A.THEME_NAMES + 1]
end

-- ====================================================================== flood fill
local D4 = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
local D8 = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}, {1, -1}, {-1, -1}, {1, 1}, {-1, 1}}

-- floor: {[key] = tile}; blocked: {[key] = true}; from = {x, y}. Returns the set of reachable keys.
function A.reachable(floor, blocked, from)
	local seen, queue, head = {}, {}, 1
	local k0 = key(from.x, from.y)
	if not floor[k0] or (blocked and blocked[k0]) then
		return seen
	end
	seen[k0] = true
	queue[1] = {from.x, from.y}
	while queue[head] do
		local c = queue[head]
		head = head + 1
		for _, d in ipairs(D4) do
			local x, y = c[1] + d[1], c[2] + d[2]
			local k = key(x, y)
			if floor[k] and not seen[k] and not (blocked and blocked[k]) then
				seen[k] = true
				queue[#queue + 1] = {x, y}
			end
		end
	end
	return seen
end

-- ====================================================================== generate
local function inBlob(c, x, y, seed)
	local dx, dy = (x - c[1]) / c[3], (y - c[2]) / c[4]
	return dx * dx + dy * dy < 0.75 + roll(x, y, seed) / 100 * 0.5
end

function A.generate(spec)
	local theme = spec.theme or A.theme("ember")
	local seed = spec.seed or 1
	local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
	local floor, floorCount = {}, 0
	for _, t in ipairs(spec.tiles) do
		local k = key(t.x, t.y)
		if not floor[k] then
			floor[k] = {x = t.x, y = t.y}
			floorCount = floorCount + 1
			minx, miny = math.min(minx, t.x), math.min(miny, t.y)
			maxx, maxy = math.max(maxx, t.x), math.max(maxy, t.y)
		end
	end
	local W, H = maxx - minx + 1, maxy - miny + 1
	local function canon(x, y)
		return x - minx + 1, y - miny + 1
	end
	local function mirrorOf(x, y) -- the tile turned 180 degrees about the middle of the bounding box
		return maxx - (x - minx), maxy - (y - miny)
	end
	local look = {tiles = {}, order = {}, blocked = {}, covers = 0, lights = 0, theme = theme.name, wallId = theme.wall,
		floorCount = floorCount, minx = minx, miny = miny, maxx = maxx, maxy = maxy}

	local function isFloor(x, y)
		return floor[key(x, y)] ~= nil
	end
	-- rim: floor tiles with a neighbour that is not floor (the wall's foot)
	local rim = {}
	for k, t in pairs(floor) do
		for _, d in ipairs(D8) do
			if not isFloor(t.x + d[1], t.y + d[2]) then
				rim[k] = true
				break
			end
		end
	end

	-- a wall sprite of size n (2 = 2x2) is drawn n-1 tiles up and left of its tile, so it overdraws the floor tiles to
	-- the north and west of it. Floor tiles with a wall to the south or east (or both) are `covered`: no light and no
	-- decoration stands there, or the wall hides it.
	local wallSize = spec.wallSize or theme.wallSize or 1
	local covered = {}
	if wallSize > 1 then
		for k, t in pairs(floor) do
			for dx = 0, wallSize - 1 do
				for dy = 0, wallSize - 1 do
					if (dx > 0 or dy > 0) and not isFloor(t.x + dx, t.y + dy) then
						covered[k] = true
					end
				end
			end
		end
	end

	local keeps = {}
	for _, p in ipairs(spec.keep or {}) do
		keeps[#keeps + 1] = {x = p.x, y = p.y, r = p.r or 1}
	end
	local keepGap = spec.keepGap or 1 -- extra tiles around a keep point that solid pieces stay away from
	local function nearKeep(x, y, extra)
		for _, p in ipairs(keeps) do
			if math.max(math.abs(x - p.x), math.abs(y - p.y)) <= p.r + (extra or 0) then
				return true
			end
		end
		return false
	end

	-- roads: an L-shaped lane (x first, then y), kept free
	local road = {}
	for _, r in ipairs(spec.roads or {}) do
		local x, y = r.from.x, r.from.y
		local function mark()
			local k = key(x, y)
			if floor[k] then
				road[k] = true
			end
		end
		mark()
		while x ~= r.to.x do
			x = x + (r.to.x > x and 1 or -1)
			mark()
		end
		while y ~= r.to.y do
			y = y + (r.to.y > y and 1 or -1)
			mark()
		end
	end

	-- ------------------------------------------------------------ ground: base, patches, borders
	local nat = {}
	for k in pairs(floor) do
		nat[k] = 0
	end
	for pi, pt in ipairs(theme.patches or {}) do
		local n = pt.count[1] + hashN(pi, seed, 7) % (pt.count[2] - pt.count[1] + 1)
		local centres = {}
		for i = 1, n do
			local cx = 2 + hashN(i, pi, seed + 11) % math.max(1, W - 2)
			local cy = 2 + hashN(i, pi, seed + 13) % math.max(1, H - 2)
			local rx = pt.r[1] + hashN(i, pi, seed + 17) % (pt.r[2] - pt.r[1] + 1)
			local ry = pt.r[1] + hashN(i, pi, seed + 19) % (pt.r[2] - pt.r[1] + 1)
			centres[#centres + 1] = {cx, cy, rx, ry}
			if spec.mirror then
				centres[#centres + 1] = {W + 1 - cx, H + 1 - cy, rx, ry}
			end
		end
		for k, t in pairs(floor) do
			if nat[k] == 0 then
				local x, y = canon(t.x, t.y)
				for _, c in ipairs(centres) do
					if inBlob(c, x, y, seed + pi) then
						nat[k] = pi
						break
					end
				end
			end
		end
	end

	for k, t in pairs(floor) do
		local cx, cy = canon(t.x, t.y)
		local pi = nat[k]
		local pt = pi > 0 and theme.patches[pi] or nil
		local gid
		local isRim = false
		if road[k] then
			gid = weighted(theme.road, cx, cy, seed + 400)
		elseif rim[k] and theme.rim and roll(cx, cy, seed + 450) < 70 then
			gid = pick(theme.rim, cx, cy, seed + 451)
			isRim = true
		elseif pt then
			gid = weighted(pt.grounds, cx, cy, seed + 410)
		else
			gid = weighted(theme.base, cx, cy, seed + 420)
		end
		local edges = {}
		if not road[k] and not isRim then
			for qi, q in ipairs(theme.patches or {}) do
				if q.edge and ((q.lower and pi == qi) or (not q.lower and pi ~= qi)) then
					local function is(dx, dy)
						local nk = key(t.x + dx, t.y + dy)
						if not floor[nk] or road[nk] then
							return false
						end
						if q.lower then
							return nat[nk] ~= qi
						end
						return nat[nk] == qi
					end
					local names = ChaosAreaGenCore.borderPieces(is(0, -1), is(1, 0), is(0, 1), is(-1, 0), is(1, -1),
						is(-1, -1), is(1, 1), is(-1, 1))
					for _, name in ipairs(names) do
						if q.edge[name] then
							edges[#edges + 1] = q.edge[name]
						end
					end
				end
			end
		end
		look.tiles[k] = {x = t.x, y = t.y, gid = gid, edges = edges, road = road[k] or nil, rim = rim[k] or nil}
		look.order[#look.order + 1] = k
	end
	table.sort(look.order, function(a, b)
		local ta, tb = look.tiles[a], look.tiles[b]
		if ta.y ~= tb.y then
			return ta.y < tb.y
		end
		return ta.x < tb.x
	end)

	-- ------------------------------------------------------------ solid pieces: lights, then cover
	local blocked = look.blocked
	local solidCount = 0
	local function touchesSolid(x, y, reach)
		for dx = -reach, reach do
			for dy = -reach, reach do
				if blocked[key(x + dx, y + dy)] then
					return true
				end
			end
		end
		return false
	end
	local start
	if keeps[1] and isFloor(keeps[1].x, keeps[1].y) then
		start = keeps[1]
	else
		local t = floor[look.order[1] ]
		start = {x = t.x, y = t.y}
	end
	local function stillJoined()
		local n = 0
		for _ in pairs(A.reachable(floor, blocked, start)) do
			n = n + 1
		end
		return n == floorCount - solidCount
	end
	-- try to put a solid piece (and its mirror) at (x, y); reach = spacing to other solid pieces
	local function place(x, y, reach, field, id)
		local cells = {{x, y}}
		if spec.mirror then
			local mx, my = mirrorOf(x, y)
			if not isFloor(mx, my) then
				return false, 0
			end
			if mx ~= x or my ~= y then
				cells[2] = {mx, my}
			end
		end
		for _, c in ipairs(cells) do
			local k = key(c[1], c[2])
			if blocked[k] or road[k] or nearKeep(c[1], c[2], keepGap) or touchesSolid(c[1], c[2], reach)
				or (field == "light" and covered[k]) then
				return false, 0
			end
		end
		if #cells == 2 and math.max(math.abs(cells[1][1] - cells[2][1]), math.abs(cells[1][2] - cells[2][2])) <= reach then
			return false, 0
		end
		for _, c in ipairs(cells) do
			blocked[key(c[1], c[2])] = true
		end
		solidCount = solidCount + #cells
		if not stillJoined() then
			for _, c in ipairs(cells) do
				blocked[key(c[1], c[2])] = nil
			end
			solidCount = solidCount - #cells
			return false, 0
		end
		for _, c in ipairs(cells) do
			look.tiles[key(c[1], c[2])][field] = id
		end
		return true, #cells
	end

	-- lights against the wall, spaced out (Chebyshev 5 apart)
	local maxLights = spec.lights or 6
	local lightAt = {}
	if maxLights > 0 and theme.light then
		local cands = {}
		-- lights stand on the rim; under a 2x2 wall the covered row / column is skipped and the lights stand one tile in
		-- there (so a mirrored pair never has one half hidden)
		local function nextToCovered(t)
			for _, d in ipairs(D8) do
				if covered[key(t.x + d[1], t.y + d[2])] then
					return true
				end
			end
			return false
		end
		for k, t in pairs(floor) do
			local cx, cy = canon(t.x, t.y)
			if not covered[k] and (rim[k] or nextToCovered(t)) then
				cands[#cands + 1] = {t.x, t.y, hashN(cx, cy, seed + 500)}
			end
		end
		table.sort(cands, function(a, b)
			if a[3] ~= b[3] then
				return a[3] < b[3]
			end
			if a[2] ~= b[2] then
				return a[2] < b[2]
			end
			return a[1] < b[1]
		end)
		for _, c in ipairs(cands) do
			if look.lights >= maxLights then
				break
			end
			local far = true
			for _, l in ipairs(lightAt) do
				if math.max(math.abs(l[1] - c[1]), math.abs(l[2] - c[2])) < 5 then
					far = false
					break
				end
			end
			if far then
				local cx, cy = canon(c[1], c[2])
				local ok, n = place(c[1], c[2], 1, "light", pick(theme.light, cx, cy, seed + 510))
				if ok then
					lightAt[#lightAt + 1] = {c[1], c[2]}
					look.lights = look.lights + n
					if n == 2 then
						lightAt[#lightAt + 1] = {mirrorOf(c[1], c[2])}
					end
				end
			end
		end
	end

	-- cover: single pieces away from the wall's foot (so the lane along the wall stays), never touching each other.
	-- First a thinned raster pass (the roll spreads the pieces); a small room that falls short of its share then gets a
	-- second pass over every free tile in hash order, so the pieces still come out scattered.
	local percent = spec.cover or (theme.cover and theme.cover.percent) or 0
	local wanted = math.floor(floorCount * percent / 100)
	if wanted > 0 and theme.cover then
		for _, k in ipairs(look.order) do
			if look.covers >= wanted then
				break
			end
			local t = floor[k]
			local cx, cy = canon(t.x, t.y)
			if not rim[k] and roll(cx, cy, seed + 600) < percent * 6 then
				local ok, n = place(t.x, t.y, 1, "cover", pick(theme.cover.ids, cx, cy, seed + 610))
				if ok then
					look.covers = look.covers + n
				end
			end
		end
		if look.covers < wanted then
			local rest = {}
			for _, k in ipairs(look.order) do
				local t = floor[k]
				if not rim[k] and not blocked[k] then
					local cx, cy = canon(t.x, t.y)
					rest[#rest + 1] = {t, hashN(cx, cy, seed + 620)}
				end
			end
			table.sort(rest, function(a, b)
				if a[2] ~= b[2] then
					return a[2] < b[2]
				end
				if a[1].y ~= b[1].y then
					return a[1].y < b[1].y
				end
				return a[1].x < b[1].x
			end)
			for _, e in ipairs(rest) do
				if look.covers >= wanted then
					break
				end
				local t = e[1]
				local cx, cy = canon(t.x, t.y)
				local ok, n = place(t.x, t.y, 1, "cover", pick(theme.cover.ids, cx, cy, seed + 610))
				if ok then
					look.covers = look.covers + n
				end
			end
		end
	end

	-- ------------------------------------------------------------ decoration (walkable, never on keep zones)
	local dec = theme.decor
	for _, k in ipairs(look.order) do
		local tile = look.tiles[k]
		if not blocked[k] and not tile.road and not covered[k] and not nearKeep(tile.x, tile.y, 0) then
			local cx, cy = canon(tile.x, tile.y)
			local chance = dec and dec.percent or 0
			local ids = dec and dec.ids
			if tile.rim and theme.wallDecor then
				chance, ids = theme.wallDecor.percent, theme.wallDecor.ids
			end
			if ids and roll(cx, cy, seed + 700) < chance then
				tile.decor = pick(ids, cx, cy, seed + 710)
			end
		end
	end
	return look
end

-- ====================================================================== apply
-- io.createItem(id, x, y) creates an item on the tile and returns it; io.hasGround(x, y) is true when the tile has a
-- ground already (a rebuild keeps it). Ground first, then border pieces, then decoration, cover, lights.
function A.apply(look, io)
	local made = 0
	for _, k in ipairs(look.order) do
		local t = look.tiles[k]
		if not io.hasGround(t.x, t.y) and io.createItem(t.gid, t.x, t.y) then
			made = made + 1
		end
		for _, e in ipairs(t.edges) do
			if io.createItem(e, t.x, t.y) then
				made = made + 1
			end
		end
	end
	for _, k in ipairs(look.order) do
		local t = look.tiles[k]
		for _, id in ipairs({t.decor or false, t.cover or false, t.light or false}) do
			if id and io.createItem(id, t.x, t.y) then
				made = made + 1
			end
		end
	end
	return made
end

function A.rectTiles(x1, y1, x2, y2)
	local out = {}
	for y = y1, y2 do
		for x = x1, x2 do
			out[#out + 1] = {x = x, y = y}
		end
	end
	return out
end

-- ====================================================================== engine glue (called at runtime only)
-- the dark set as a theme source: name -> server id when installed (data/lib/chaos_dark_tiles.lua), else nil
function A.darkIds(name)
	if ChaosDarkTiles and ChaosDarkTiles.id then
		return ChaosDarkTiles.id(name, nil)
	end
	return nil
end

-- creates the look's items with the engine API at height z; the look's own coordinates are shifted by ox, oy (a look
-- made in the room's local coordinates serves every slot of a grid). The tiles must exist (Game.createTile).
function A.paint(look, z, ox, oy)
	ox, oy = ox or 0, oy or 0
	local io = {
		hasGround = function(x, y)
			local tile = Tile(Position(x + ox, y + oy, z))
			return tile ~= nil and tile:getGround() ~= nil
		end,
		createItem = function(id, x, y)
			local ok, item = pcall(Game.createItem, id, 1, Position(x + ox, y + oy, z))
			return ok and item or false
		end
	}
	return A.apply(look, io)
end

-- generate + cache: one look per (cache key); layout-dependent specs must put what differs into the key
local cache = {}
function A.cached(cacheKey, makeSpec)
	if not cache[cacheKey] then
		cache[cacheKey] = A.generate(makeSpec())
	end
	return cache[cacheKey]
end

function A.forget(cacheKey)
	cache[cacheKey] = nil
end

-- ---------------------------------------------------------------------- owned ids and room dressing
-- every id the looks can place (stock themes and the dark set): what a repaint may remove, what a clean-up keeps
local ownedSet
function A.isOwned(id)
	if not ownedSet then
		ownedSet = {}
		local function add(v)
			if type(v) == "number" then
				ownedSet[v] = true
			elseif type(v) == "table" then
				for _, x in pairs(v) do
					add(x)
				end
			end
		end
		for _, t in pairs(A.THEMES) do
			add(t.base); add(t.patches); add(t.rim); add(t.road); add(t.cover.ids); add(t.light); add(t.decor.ids)
			add(t.wallDecor.ids)
		end
		ownedSet[1514] = true -- the stone pillar the stone theme used before the marble pillar
		if ChaosDarkTiles and ChaosDarkTiles.ids then
			add(ChaosDarkTiles.ids)
		end
	end
	return ownedSet[id] == true
end

A.painted = A.painted or {} -- room key -> signature of what is painted there

local function itemId(item)
	return type(item) == "number" and item or (item and item:getId())
end

-- Dress a rectangular room (floor x1..x2, y1..y2, height z) with the look of `themeName`. Everything the looks own on
-- those tiles (ground, borders, cover, lights, decoration) is removed first when the room was painted with another
-- theme or layout; loose items (loot, fields) and fixtures of the caller stay. The caller places its fixtures (basins,
-- pillars, gates) AFTER this call: a look's light may stand where a fixture goes.
--   o.keep   {{x, y, r}} absolute positions that stay open (arrival, boss, gates, fixtures), o.roads {{from, to}}
--   o.seed (default 1), o.mirror (default true), o.cover, o.lights, o.groundIds {id = true}: more grounds a repaint removes
-- Returns the look (local coordinates: x - x1 + 1, y - y1 + 1) and true when the room was (re)painted.
function A.dress(roomKey, rect, z, themeName, o)
	o = o or {}
	local theme = A.theme(themeName, A.darkIds)
	local seed = o.seed or 1
	local function loc(p, r)
		return {x = p.x - rect.x1 + 1, y = p.y - rect.y1 + 1, r = r or p.r}
	end
	local keep, kparts = {}, {}
	for _, p in ipairs(o.keep or {}) do
		local q = loc(p)
		if q.x >= 1 and q.y >= 1 and q.x <= rect.x2 - rect.x1 + 1 and q.y <= rect.y2 - rect.y1 + 1 then
			keep[#keep + 1] = q
			kparts[#kparts + 1] = q.x .. "," .. q.y .. "," .. (q.r or 1)
		end
	end
	local roads, rparts = {}, {}
	for _, r in ipairs(o.roads or {}) do
		roads[#roads + 1] = {from = loc(r.from), to = loc(r.to)}
		rparts[#rparts + 1] = roads[#roads].from.x .. "," .. roads[#roads].from.y .. ">" .. roads[#roads].to.x .. "," ..
			roads[#roads].to.y
	end
	local w, h = rect.x2 - rect.x1 + 1, rect.y2 - rect.y1 + 1
	local sig = table.concat({theme.name, seed, w, h, o.cover or "", o.lights or "", o.mirror == false and "n" or "m",
		o.keepGap or "", o.wallSize or "", table.concat(kparts, ";"), table.concat(rparts, ";")}, "|")
	local look = A.cached("room:" .. sig, function()
		return {tiles = A.rectTiles(1, 1, w, h), theme = theme, seed = seed, mirror = o.mirror ~= false, keep = keep,
			roads = roads, cover = o.cover, lights = o.lights, keepGap = o.keepGap, wallSize = o.wallSize}
	end)
	if A.painted[roomKey] == sig then
		return look, false
	end
	-- clear what a former painting left
	for dy = 1, h do
		for dx = 1, w do
			local tile = Tile(Position(rect.x1 + dx - 1, rect.y1 + dy - 1, z))
			if tile then
				for _, item in ipairs(tile:getItems() or {}) do
					if A.isOwned(itemId(item)) then
						item:remove()
					end
				end
				local g = tile:getGround()
				if g and type(g) ~= "number" and g.remove then
					local id = g:getId()
					if A.isOwned(id) or (o.groundIds and o.groundIds[id]) then
						g:remove()
					end
				end
			end
		end
	end
	A.paint(look, z, rect.x1 - 1, rect.y1 - 1)
	-- a tile the painter could not give a ground (an item the server does not know) gets the plain one: never a hole
	for dy = 1, h do
		for dx = 1, w do
			local pos = Position(rect.x1 + dx - 1, rect.y1 + dy - 1, z)
			local tile = Tile(pos)
			if tile and not tile:getGround() then
				pcall(Game.createItem, o.fallbackGround or 413, 1, pos)
			end
		end
	end
	A.painted[roomKey] = sig
	return look, true
end

function A.forgetRoom(roomKey)
	A.painted[roomKey] = nil
end

-- The boss arenas built on uber_core.lua's layout (Ascended, guild boss, pocket bosses): theme from cfg.look (themes[key],
-- theme, or the keyword of the boss's name), the arrival, the boss spot, the middle and the corner fixtures kept open,
-- a free lane from the entry to the boss (the boss spawns in sight of the arrival). Returns the look.
function A.bossArenaSpec(L, cfg, bossKey, extraKeep)
	local lk = cfg.look or {}
	local theme = (lk.themes and lk.themes[bossKey]) or lk.theme or A.themeFor(bossKey)
	local keep = {{x = L.entry.x, y = L.entry.y, r = 3}, {x = L.bossSpawn.x, y = L.bossSpawn.y, r = 3},
		{x = L.center.x, y = L.center.y, r = 2}}
	for _, b in ipairs(L.basins or {}) do
		keep[#keep + 1] = {x = b.x, y = b.y, r = 1}
	end
	if extraKeep then
		keep[#keep + 1] = {x = extraKeep.x, y = extraKeep.y, r = 1}
	end
	return theme, {keep = keep, roads = {{from = L.entry, to = L.bossSpawn}}, seed = lk.seed or 1, cover = lk.cover,
		lights = lk.lights, wallSize = A.wallSizeOf(cfg.wallId), groundIds = {[cfg.groundId] = true},
		fallbackGround = cfg.groundId}
end

function A.dressBossArena(roomName, L, cfg, bossKey, extraKeep)
	local theme, o = A.bossArenaSpec(L, cfg, bossKey, extraKeep)
	return A.dress(roomName .. L.center.x .. "," .. L.center.y, L.rect, L.z, theme, o)
end

return A
