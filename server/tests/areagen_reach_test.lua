-- Run from the server/ folder: luajit tests/areagen_reach_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- Reachability repair of the area generator (O738, server/README.md "Area planner candidates and reach repair (O738)"):
-- ChaosAreaGenCore.linkPath on synthetic grids (shortest 4-neighbour link, the margin, never through a boss room),
-- then a planned layout with a path piece cut off from the zones: without def.repairReach the pocket is closed with
-- rock as before (the same checksum as a def without the field), with it the pocket is joined by a carved link, the
-- model validates and model.reach counts it; then many seeds of the configured cave and dungeon areas with the repair
-- on: every model valid, nothing left cut off.
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

-- ====================================================================== linkPath on a synthetic grid
local F = {w = 30, h = 20}
local function I(x, y)
	return (y - 1) * F.w + x
end
local from, to = {[I(5, 10)] = true, [I(6, 10)] = true}, {[I(20, 10)] = true, [I(20, 11)] = true}
local path = A.linkPath(F, from, to, 3, {})
ok(path ~= nil, "linkPath: a link exists")
eq(#path, 15, "linkPath: the shortest 4-neighbour link from 6,10 to 20,10 has 15 cells")
eq(path[1], I(6, 10), "linkPath: starts on the nearest pocket cell")
eq(path[#path], I(20, 10), "linkPath: ends on the main region")
local bossRoom = {{kind = "boss", x1 = 10, y1 = 5, x2 = 14, y2 = 15}}
local around = A.linkPath(F, from, to, 3, bossRoom)
ok(around ~= nil and #around > 15, "linkPath: a boss room is walked around (" .. tostring(around and #around) .. " cells)")
local through = false
for _, i in ipairs(around or {}) do
	local x, y = (i - 1) % F.w + 1, math.floor((i - 1) / F.w) + 1
	if x >= 9 and x <= 15 and y >= 4 and y <= 16 then
		through = true
	end
end
ok(not through, "linkPath: no cell in the boss room or the cell around it")
local wall = {{kind = "boss", x1 = 10, y1 = 1, x2 = 14, y2 = 20}}
eq(A.linkPath(F, from, to, 3, wall), nil, "linkPath: no link when a boss room cuts the grid in two")
eq(A.linkPath(F, from, to, 3, {{kind = "hunt", x1 = 10, y1 = 1, x2 = 14, y2 = 20}}) ~= nil, true,
	"linkPath: a hunt room is no wall")
local same = A.linkPath(F, from, to, 3, bossRoom)
ok(table.concat(same, ",") == table.concat(around, ","), "linkPath: deterministic")

-- ====================================================================== a planned layout with a cut-off path piece
local base
for _, def in ipairs(cfg.areas) do
	if def.id == "cinderfall" then
		base = def
	end
end
local function planned(seed, repair)
	local def = copy(base)
	def.size, def.floors, def.linksPerFloor, def.seed = {64, 48}, 1, 1, seed
	def.spawns.band = nil
	def.arrival = {12, 20}
	def.bossAt = {46, 21}
	def.boss.radius = 3
	def.layout = {plan = {{
		zones = {{x1 = 7, y1 = 14, x2 = 20, y2 = 27, shape = "room", kind = "hunt"},
			{x1 = 38, y1 = 14, x2 = 54, y2 = 28, shape = "room", kind = "hunt"}},
		paths = {{width = 3, style = "road", points = {{20, 21}, {38, 21}}},
			{width = 3, style = "road", points = {{24, 38}, {34, 38}}}}}}}
	if repair then
		def.repairReach = true
	end
	return def
end
local function walkCount(m)
	local n = 0
	for _, set in pairs(m.walk) do
		for _ in pairs(set) do
			n = n + 1
		end
	end
	return n
end
local off = A.generate(cfg, planned(4242, false), {})
local plain = planned(4242, false)
plain.repairReach = nil
eq(A.checksum(A.generate(cfg, plain, {})), A.checksum(off), "repair off: the same model as a def without the field")
ok(off.reach.pockets >= 1 and off.reach.cut > 0, "repair off: the cut-off path piece is a pocket (" .. off.reach.cut .. " tiles)")
eq(off.reach.left, off.reach.cut, "repair off: the pocket is closed with rock")
eq(off.reach.carved, 0, "repair off: nothing carved")
eq(#A.validate(cfg, off, {}), 0, "repair off: valid (the pocket is rock)")
local on = A.generate(cfg, planned(4242, true), {})
eq(on.reach.cut, off.reach.cut, "repair on: the same pockets found")
eq(on.reach.repaired, on.reach.pockets, "repair on: every pocket joined (" .. on.reach.repaired .. ")")
eq(on.reach.left, 0, "repair on: nothing left cut off")
ok(on.reach.carved > 0 and on.reach.carved <= 20, "repair on: a short carved link (" .. on.reach.carved .. " cells)")
local problems = A.validate(cfg, on, {})
eq(#problems, 0, "repair on: the model validates (" .. tostring(problems[1]) .. ")")
ok(walkCount(on) >= walkCount(off) + off.reach.cut, "repair on: the pocket's tiles are walkable ("
	.. walkCount(on) .. " against " .. walkCount(off) .. ")")
eq(A.checksum(A.generate(cfg, planned(4242, true), {})), A.checksum(on), "repair on: deterministic")
eq(on.reach.floors[1].repaired, on.reach.repaired, "repair on: counted per floor")
print(string.format("  planned: %d walkable design tiles, %d cut off in %d pocket(s), %d joined by %d carved cells",
	off.reach.walk, off.reach.cut, off.reach.pockets, on.reach.repaired, on.reach.carved))

-- ====================================================================== many seeds of caves and dungeons with the repair on
local byId = {}
for _, def in ipairs(cfg.areas) do
	byId[def.id] = def
end
local variants = {
	{from = "emberdeep", size = {44, 34}, floors = 2},
	{from = "cinderfall", size = {50, 40}, floors = 1},
	{from = "vault", size = {50, 44}, floors = 1}
}
local bad, runs, cut, left, pockets, repaired = 0, 0, 0, 0, 0, 0
for _, v in ipairs(variants) do
	for seed = 1, 8 do
		local def = copy(byId[v.from])
		def.size, def.floors, def.linksPerFloor, def.seed = v.size, v.floors, 1, seed * 7919
		def.spawns.band = nil
		if def.kind == "dungeon" then
			def.layout.rooms = {5, 7}
			def.layout.bossRoom = 9
		end
		def.repairReach = true
		local m = A.generate(cfg, def, {})
		runs = runs + 1
		cut, left = cut + m.reach.cut, left + m.reach.left
		pockets, repaired = pockets + m.reach.pockets, repaired + m.reach.repaired
		local p = A.validate(cfg, m, {})
		if #p > 0 then
			bad = bad + 1
			print("  seed " .. seed .. " " .. v.from .. ": " .. p[1])
		end
	end
end
eq(bad, 0, "repair on: small areas over many seeds are valid (" .. runs .. " runs)")
print(string.format("  %d runs: %d pockets (%d tiles), %d joined, %d tiles left cut off", runs, pockets, cut, repaired, left))
ok(left <= cut, "repair on: never more cut off than found")

print(string.format("areagen reach: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
