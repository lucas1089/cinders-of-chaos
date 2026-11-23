-- Run from the server/ folder: luajit tests/areagen_water_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- Rivers, lakes, shores, bridges and fords of the area generator (O739, server/README.md "Rivers, lakes, bridges and
-- fords (O739)"): ChaosAreaGenCore.shorePieces by neighbour pattern; a def without `water` leaves cfg and the model
-- alone; a planned layout with a river between two zones: the river separates them, at least one bridge joins them,
-- every walkable tile is reached, shore pieces lie only on water next to land and every such water tile has one, no
-- spawn on water or a crossing, the same seed gives the same model; then many seeds of a cave with a river and a lake.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/areagen_core.lua")
local A = ChaosAreaGenCore
local cfg = dofile("data/scripts/chaos/areagen_config.lua")
local W = cfg.water

local function copy(t)
	if type(t) ~= "table" then
		return t
	end
	local o = {}
	for k, v in pairs(t) do
		o[k] = copy(v)
	end
	return o
end

-- ====================================================================== shore pieces
local function names(list)
	return table.concat(list, ",")
end
eq(names(A.shorePieces(true, false, false, false, false, false, false, false)), "n", "shore: land north")
eq(names(A.shorePieces(false, false, false, true, false, false, false, false)), "w", "shore: land west")
eq(names(A.shorePieces(true, true, false, false, true, true, true, false)), "in_ne", "shore: land north and east")
eq(names(A.shorePieces(true, false, true, false, false, false, false, false)), "in_ns", "shore: a channel north-south land")
eq(names(A.shorePieces(false, true, false, true, false, false, false, false)), "in_ew", "shore: land east and west")
eq(names(A.shorePieces(true, true, true, false, false, false, false, false)), "in_nse", "shore: three sides")
eq(names(A.shorePieces(true, true, false, true, false, false, false, false)), "in_new", "shore: three sides, south open")
eq(names(A.shorePieces(true, true, true, true, false, false, false, false)), "in_nsew", "shore: a one-tile pond")
eq(names(A.shorePieces(false, false, false, false, true, false, false, false)), "ne", "shore: land on a diagonal only")
eq(names(A.shorePieces(true, false, false, false, false, false, true, true)), "n,se,sw",
	"shore: a side and the two far corners")
eq(names(A.shorePieces(false, false, false, false, false, false, false, false)), "", "shore: open water has none")
for _, name in ipairs({"n", "e", "s", "w", "ne", "nw", "se", "sw", "in_ne", "in_nw", "in_se", "in_sw", "in_ns", "in_ew",
	"in_nse", "in_new", "in_nsw", "in_sew", "in_nsew"}) do
	ok(type(W.shore[name]) == "number", "config: shore piece " .. name)
end

-- ====================================================================== a planned layout with a river between two zones
local base
for _, def in ipairs(cfg.areas) do
	if def.id == "cinderfall" then
		base = def
	end
end
local function planned(seed, water)
	local def = copy(base)
	def.size, def.floors, def.linksPerFloor, def.seed = {70, 44}, 1, 1, seed
	def.spawns.band = nil
	def.arrival = {12, 22}
	def.bossAt = {56, 22}
	def.boss.radius = 3
	def.layout = {plan = {{
		zones = {{x1 = 5, y1 = 10, x2 = 26, y2 = 34, shape = "room", kind = "hunt"},
			{x1 = 44, y1 = 10, x2 = 64, y2 = 34, shape = "room", kind = "hunt"}},
		paths = {{width = 4, style = "road", points = {{26, 22}, {44, 22}}},
			{width = 3, style = "road", points = {{20, 34}, {20, 40}, {50, 40}, {50, 34}}}}}}}
	def.water = water
	return def
end
local cfgFams = 0
for _ in pairs(cfg.families) do
	cfgFams = cfgFams + 1
end
local dry = A.generate(cfg, planned(707, nil), {})
local plain = planned(707, nil)
plain.water = nil
eq(A.checksum(A.generate(cfg, plain, {})), A.checksum(dry), "water off: the same model as a def without the field")
eq(dry.water, nil, "water off: no water numbers in the model")
local n2 = 0
for _ in pairs(cfg.families) do
	n2 = n2 + 1
end
eq(n2, cfgFams, "water off: cfg.families untouched")

local river = {rivers = {{course = "north-south", width = {3, 5}, at = 50}}, fords = 1}
local m = A.generate(cfg, planned(707, copy(river)), {})
local problems = A.validate(cfg, m, {})
eq(#problems, 0, "river: the model validates (" .. tostring(problems[1]) .. ")")
ok(m.water and m.water.rivers == 1, "river: one river")
ok(m.water.water > 0, "river: deep water tiles (" .. m.water.water .. ")")
ok(m.water.bridges >= 1, "river: at least one bridge (" .. m.water.bridges .. ")")
ok(m.water.bridges + m.water.fords >= 2, "river: a bridge and a ford (" .. m.water.bridges .. ", " .. m.water.fords .. ")")
eq(A.checksum(A.generate(cfg, planned(707, copy(river)), {})), A.checksum(m), "river: deterministic by seed")
ok(A.checksum(A.generate(cfg, planned(708, copy(river)), {})) ~= A.checksum(m), "river: another seed, another model")

local key = function(x, y)
	return y * 65536 + x
end
local tiles, ground = {}, {}
for _, t in ipairs(m.tiles) do
	tiles[key(t.x, t.y)] = t
	ground[key(t.x, t.y)] = t.ground
end
local fam = {}
for _, f in ipairs({"deep", "ford", "bridge"}) do
	for _, row in ipairs(cfg.families[W.fams[f]].grounds) do
		fam[row[1]] = f
	end
end
local shoreId = {}
for _, id in pairs(W.shore) do
	shoreId[id] = true
end
local walk = m.walk[m.origin.z]
local ox, oy = m.origin.x, m.origin.y
local wet, onLand, missing, crossings, deepWalk = 0, 0, 0, {}, 0
for k, t in pairs(tiles) do
	local f = fam[t.ground]
	local isWater = f == "deep" or f == "ford"
	local hasShore = false
	for _, id in ipairs(t.items) do
		if shoreId[id] then
			hasShore = true
		end
	end
	if hasShore and not isWater then
		onLand = onLand + 1
	end
	if f == "deep" and walk[k] then
		deepWalk = deepWalk + 1
	end
	if f == "bridge" or f == "ford" then
		crossings[k] = true
		ok(walk[k], "crossing tile walkable")
	end
	if isWater then
		wet = wet + 1
		local landSide = false
		for _, d in ipairs({{0, -1}, {1, 0}, {0, 1}, {-1, 0}}) do
			local n = tiles[key(t.x + d[1], t.y + d[2])]
			if n and not fam[n.ground] then
				landSide = true
			end
		end
		if landSide and not hasShore then
			missing = missing + 1
		end
	end
end
eq(onLand, 0, "shores: no shore piece on a land tile")
eq(missing, 0, "shores: every water tile beside land has a shore piece")
eq(deepWalk, 0, "deep water is never walkable")
-- the river separates the zones: without the crossing tiles the east zone is out of reach of the arrival
local function reach(skip)
	local seen, stack = {}, {key(m.arrival.x, m.arrival.y)}
	seen[stack[1]] = true
	while #stack > 0 do
		local k = table.remove(stack)
		local x, y = k % 65536, math.floor(k / 65536)
		for dy = -1, 1 do
			for dx = -1, 1 do
				local n = key(x + dx, y + dy)
				if walk[n] and not seen[n] and not skip[n] then
					seen[n] = true
					stack[#stack + 1] = n
				end
			end
		end
	end
	return seen
end
local east = key(ox + 54 - 1, oy + 22 - 1)
ok(walk[east], "the east zone centre is walkable")
ok(reach({})[east], "with the crossings the east zone is reached")
ok(not reach(crossings)[east], "without the crossing tiles the east zone is cut off: the river crosses the area")
local spawnOnCrossing = 0
for _, s in ipairs(m.spawns) do
	local k = key(s.x, s.y)
	if crossings[k] or fam[ground[k]] then
		spawnOnCrossing = spawnOnCrossing + 1
	end
end
eq(spawnOnCrossing, 0, "no spawn on water or a crossing (" .. #m.spawns .. " spawns)")
for _, c in ipairs(m.water.crossings) do
	ok(c.kind == "bridge" or c.kind == "ford", "crossing kind " .. tostring(c.kind))
	ok(c.length >= 1 and c.length <= W.maxRun, "crossing length " .. c.length)
end
print(string.format("  planned river: %d water tiles, %d bridge(s), %d ford(s), %d drowned, %d spawns",
	m.water.water, m.water.bridges, m.water.fords, m.water.drowned, #m.spawns))

-- a lake in a zone: an irregular blob, the zone stays one region
local lake = A.generate(cfg, planned(707, {lakes = {{x = 16, y = 28, radius = {4, 5}}}}), {})
eq(#A.validate(cfg, lake, {}), 0, "lake: the model validates")
ok(lake.water.lakes == 1 and lake.water.water >= 20, "lake: a lake of " .. lake.water.water .. " tiles")
local lw = {}
local rows = {}
for _, t in ipairs(lake.tiles) do
	if fam[t.ground] == "deep" then
		lw[#lw + 1] = t
		rows[t.y] = (rows[t.y] or 0) + 1
	end
end
local widths = {}
for _, n in pairs(rows) do
	widths[n] = true
end
local distinct = 0
for _ in pairs(widths) do
	distinct = distinct + 1
end
ok(distinct >= 3, "lake: not a box (" .. distinct .. " different row widths)")

-- ====================================================================== many seeds: caves with a river and a lake
local bad, runs, bridges, fords, water = 0, 0, 0, 0, 0
for _, course in ipairs({"west-east", "north-south"}) do
	for seed = 1, 6 do
		local def = copy(base)
		def.size, def.floors, def.linksPerFloor, def.seed = {54, 42}, 1, 1, seed * 7919
		def.spawns.band = nil
		def.water = {rivers = {{course = course}}, lakes = {{x = 40, y = 30}}, fords = 1}
		local mm = A.generate(cfg, def, {})
		runs = runs + 1
		bridges, fords, water = bridges + mm.water.bridges, fords + mm.water.fords, water + mm.water.water
		local p = A.validate(cfg, mm, {})
		if #p > 0 then
			bad = bad + 1
			print("  seed " .. seed .. " " .. course .. ": " .. p[1])
		end
		local wk = mm.walk[mm.origin.z]
		for _, s in ipairs(mm.spawns) do
			if fam[(function()
				for _, t in ipairs(mm.tiles) do
					if t.x == s.x and t.y == s.y then
						return t.ground
					end
				end
			end)()] then
				bad = bad + 1
				print("  seed " .. seed .. ": a spawn on water or a crossing at " .. s.x .. "," .. s.y)
			end
		end
		ok(wk ~= nil, "walk set")
	end
end
eq(bad, 0, "caves with water over many seeds are valid (" .. runs .. " runs)")
print(string.format("  %d cave runs: %d water tiles, %d bridges, %d fords", runs, water, bridges, fords))

print(string.format("areagen water: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
