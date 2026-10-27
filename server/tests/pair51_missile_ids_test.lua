-- Run from the server/ folder: luajit tests/pair51_missile_ids_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Pair 51 missiles (client/tools/sprites/import_pair51_missiles.py, gen_pair51_missile_ids.py): 62 blank missile ids refilled
-- from two purchased sprite sources; data/lib/chaos_pair51_missile_ids.lua names them.
-- Checks: the ids file lists exactly the rows of pair51_missiles.csv (name -> id), every id is in 1..253 (254 is
-- CONST_ANI_WEAPONTYPE), the ids are those of the retired missiles in pair51_removed.csv
-- (the ids are the ones left free after the name-usage fix of the prune), and ChaosVfxMissile gets one p51_ entry per missile with the offset of its size.
local failures = 0
local function ok(c, msg)
	if not c then
		failures = failures + 1
		print("FAIL " .. msg)
	end
end
local function eq(a, b, msg)
	ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
local function lines(p)
	local f = io.open(p, "r")
	if not f then return nil end
	local t = {}
	for l in f:lines() do t[#t + 1] = l end
	f:close()
	return t
end

local csv = lines("../client/tools/sprites/pair51_missiles.csv")
ok(csv ~= nil, "pair51_missiles.csv readable")
local rows, byName = {}, {}
for i = 2, #csv do
	local id, src, sid, name, el, size, ph = csv[i]:match("^(%d+),(%u),(%d+),([%w_]+),(%a+),(%dx%d),(%d+)$")
	ok(id ~= nil, "csv row " .. i .. " parses")
	if id then
		rows[#rows + 1] = {id = tonumber(id), name = name, size = size}
		byName[name] = tonumber(id)
	end
end
eq(#rows, 62, "62 missiles")

local removed = lines("../client/tools/sprites/pair51_removed.csv")
local free = {}
for i = 2, #removed do
	local id = removed[i]:match("^missile,(%d+),")
	if id then free[tonumber(id)] = true end
end
local seen = {}
for _, r in ipairs(rows) do
	ok(free[r.id], "id " .. r.id .. " is a freed missile id")
	ok(r.id >= 1 and r.id <= 253, "id " .. r.id .. " in 1..253")
	ok(not seen[r.id], "id " .. r.id .. " once")
	seen[r.id] = true
end

dofile("data/lib/chaos_pair51_missile_ids.lua")
ok(type(ChaosPair51Missile) == "table", "ChaosPair51Missile exists")
local n = 0
for name, id in pairs(ChaosPair51Missile) do
	n = n + 1
	eq(byName[name], id, "name " .. name .. " -> id as in the csv")
end
eq(n, 62, "62 names in the Lua table")
for _, r in ipairs(rows) do
	local e = ChaosVfxMissile["p51_" .. r.name]
	ok(e ~= nil, "ChaosVfxMissile.p51_" .. r.name)
	if e then
		local w, h = r.size:match("(%d)x(%d)")
		eq(e.id, r.id, "vfx id of " .. r.name)
		eq(e.dx, math.floor(tonumber(w) / 2), "vfx dx of " .. r.name)
		eq(e.dy, math.floor(tonumber(h) / 2), "vfx dy of " .. r.name)
	end
end

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("pair51_missile_ids_test: ok")
