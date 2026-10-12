-- Run from the server/ folder: luajit tests/map_marks_test.lua (and lua5.3; CI runs both)
-- Pure logic of the map overlay marks (map_marks_core.lua): mark validation, the per-tile de-duplication, the rift
-- square of a slot (against rift_core.lua's slotOfPos with the real rift_config.lua grid) and the trim order.
dofile("data/scripts/chaos/map_marks_core.lua")
dofile("data/scripts/chaos/rift_core.lua")
local M = ChaosMapMarksCore
local R = ChaosRiftCore
local riftCfg = dofile("data/scripts/chaos/rift_config.lua")

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- marks
local m = M.mark("party", {x = 100.7, y = 200, z = 7}, "Ana")
eq(m.k, "party", "kind")
eq(m.x, 100, "x floored")
eq(m.n, "Ana", "label")
eq(M.mark("party", {x = 1, y = 1, z = 7}, "").n, nil, "an empty label is left out")
eq(M.mark("unknown", {x = 1, y = 1, z = 7}), nil, "unknown kind")
eq(M.mark("npc", nil), nil, "no position")
eq(M.mark("npc", {x = 0, y = 5, z = 7}), nil, "x 0 is no map position")
eq(M.mark("npc", {x = 5, y = 5, z = 16}), nil, "floor out of range")
eq(M.mark("npc", {x = "a", y = 5, z = 7}), nil, "not a number")

local list, seen = {}, {}
assert(M.add(list, seen, "depot", {x = 10, y = 10, z = 7}))
eq(M.add(list, seen, "depot", {x = 10, y = 10, z = 7}), nil, "same kind on the same tile once")
assert(M.add(list, seen, "npc", {x = 10, y = 10, z = 7}), "another kind on that tile is kept")
eq(#list, 2, "two marks")

eq(M.distance({x = 0, y = 0, z = 7}, {x = 3, y = -5, z = 7}), 5, "chebyshev")
eq(M.distance({x = 0, y = 0, z = 7}, {x = 0, y = 0, z = 6}), math.huge, "other floor")

-- ---------------------------------------------------------------- rift square
local g = riftCfg.grid
for slot = 0, g.cols * g.rows - 1 do
	local a = M.riftArea(g, slot)
	assert(a, "area of slot " .. slot)
	eq(a.x2 - a.x1 + 1, g.spacing, "width")
	eq(a.y2 - a.y1 + 1, g.spacing, "height")
	eq(a.z, g.origin.z, "floor")
	-- every corner and the centre belong to this slot and nothing outside does
	for _, p in ipairs({{a.x1, a.y1}, {a.x2, a.y2}, {a.x1, a.y2}, {a.x2, a.y1}}) do
		eq(R.slotOfPos(riftCfg, {x = p[1], y = p[2], z = a.z}), slot, "corner of slot " .. slot)
	end
	local c = R.slotCenter(riftCfg, slot)
	eq(R.slotOfPos(riftCfg, c), slot, "centre of slot " .. slot)
	assert(R.slotOfPos(riftCfg, {x = a.x1 - 1, y = a.y1, z = a.z}) ~= slot, "left of slot " .. slot)
	assert(R.slotOfPos(riftCfg, {x = a.x1, y = a.y2 + 1, z = a.z}) ~= slot, "below slot " .. slot)
end
eq(M.riftArea(nil, 0), nil, "no grid")
eq(M.riftArea(g, nil), nil, "no slot")

-- ---------------------------------------------------------------- trim
local center = {x = 100, y = 100, z = 7}
local many = {}
for i = 1, 30 do
	many[#many + 1] = M.mark("npc", {x = 100 + i, y = 100, z = 7}, "npc" .. i)
end
many[#many + 1] = M.mark("party", {x = 400, y = 400, z = 7}, "far friend")
many[#many + 1] = M.mark("worldboss", {x = 900, y = 900, z = 7}, "boss")
M.trim(many, center, 10)
eq(#many, 10, "trimmed")
eq(many[1].k ~= "npc" and many[2].k ~= "npc", true, "party and the world boss stay")
eq(many[3].n, "npc1", "then the nearest")
eq(many[10].n, "npc8", "the farthest kept")
local few = {M.mark("npc", {x = 1, y = 1, z = 7})}
eq(#M.trim(few, center, 10), 1, "short lists unchanged")

print("map_marks_test: ok")
