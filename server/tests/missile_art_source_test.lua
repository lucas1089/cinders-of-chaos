-- Run from the server/ folder: luajit tests/missile_art_source_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- O528: a missile name may only point at an id whose art came from the source the name says.
-- Pair 51 refilled 62 missile ids (pair51_missiles.csv: 147-152, 189-250 but 200 205 208 228 229 249) with donor
-- missiles. So in every ChaosVfxMissile / ChaosFxMissile / ChaosPair51Missile table and in every catalog csv:
--   * an id of the donor set carries only its own p51_<name> (the name of the csv row), no pack name (proj_*, mega_*,
--     rep41_m*, a pair 27 / 29 name) and no procedural one;
--   * the pack36 missile spec rows (art_import/pack36_missiles.csv, ids 189 and on by position) are either a donor id
--     (no pack name) or still named in the ids file at that id (the 6 ids the donors did not touch).
-- A new pack table that names a donor id fails here, whoever writes it (donor_missile_names.py is the fix for the
-- generated ones).
local failures = 0
local function ok(c, msg)
	if not c then
		failures = failures + 1
		print("FAIL " .. msg)
	end
end
local function readFile(p)
	local f = io.open(p, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

-- the donor set
local donor, nDonor = {}, 0
for line in (readFile("../client/tools/sprites/pair51_missiles.csv") or ""):gmatch("[^\n]+") do
	local id, name = line:match("^(%d+),%u,%d+,([%w_]+),")
	if id then
		donor[tonumber(id)] = name
		nDonor = nDonor + 1
	end
end
ok(nDonor == 62, "pair51_missiles.csv lists 62 donor missiles (" .. nDonor .. ")")

-- every name table
local libs = {}
local okp, p = pcall(io.popen, "ls data/lib/chaos_*.lua")
if okp and p then
	for l in p:lines() do libs[#libs + 1] = l end
	p:close()
end
if #libs == 0 then
	for _, f in ipairs({"chaos_vfx", "chaos_vfx_art", "chaos_pack_fx_ids", "chaos_pack27_fx_ids", "chaos_pack29_fx_ids",
		"chaos_pack29_vfx_ids", "chaos_pack30_fx_ids", "chaos_pack36_fx_ids", "chaos_pack41_fx_ids", "chaos_class_fx_ids",
		"chaos_big_fx_ids", "chaos_status_fx_ids"}) do
		libs[#libs + 1] = "data/lib/" .. f .. ".lua"
	end
end
ChaosVfx, ChaosVfxMissile, ChaosFxMissile = nil, nil, nil
pcall(dofile, "data/lib/chaos_fx.lua")
for _, f in ipairs(libs) do
	pcall(dofile, f)
end
dofile("data/lib/chaos_pack36_fx.lua")
ok(ChaosPack36Fx.live() == true, "pair 36 ids load (C.live)")
ok(ChaosVfxMissile ~= nil and ChaosVfxMissile.p51_dynamite ~= nil, "the p51_ names load with them")

local seen = {}
for name, e in pairs(ChaosVfxMissile or {}) do
	local id = type(e) == "table" and e.id or nil
	if id and donor[id] then
		seen[id] = (seen[id] or 0) + 1
		ok(name == "p51_" .. donor[id], "ChaosVfxMissile." .. name .. " is id " .. id .. ", which draws donor art: only p51_" .. donor[id] .. " may name it")
	end
end
for id, name in pairs(donor) do
	ok(seen[id] == 1, "donor id " .. id .. " (" .. name .. ") has exactly one ChaosVfxMissile name (" .. tostring(seen[id]) .. ")")
end
for name, id in pairs(ChaosFxMissile or {}) do
	ok(not (type(id) == "number" and donor[id]), "ChaosFxMissile." .. name .. " is id " .. tostring(id) .. ", which draws donor art")
end
for name, id in pairs(ChaosPair51Missile or {}) do
	ok(donor[id] == name, "ChaosPair51Missile." .. name .. " is a row of pair51_missiles.csv at its id")
end

-- the catalogs (server/data/spells/*_catalog.csv) name no donor id either
local cats = {}
local okc, pc = pcall(io.popen, "ls data/spells/*_catalog.csv")
if okc and pc then
	for l in pc:lines() do cats[#cats + 1] = l end
	pc:close()
end
ok(#cats >= 10, "the catalog csv files are found (" .. #cats .. ")")
for _, f in ipairs(cats) do
	for line in (readFile(f) or ""):gmatch("[^\n]+") do
		local id, name = line:match("^missile,(%d+),([%w_]+),")
		ok(not (id and donor[tonumber(id)]), f .. ": missile " .. tostring(name) .. " names donor id " .. tostring(id))
	end
end

-- the pack36 missile spec: ids 189 and on by position, a donor id has no name, any other keeps its pack name
local n = 0
local named = {}
for name, e in pairs(ChaosVfxMissile or {}) do
	if type(e) == "table" and e.id then named[e.id] = name end
end
local kept = 0
for line in (readFile("../client/tools/sprites/art_import/pack36_missiles.csv") or ""):gmatch("[^\n]+") do
	local name = line:match("^missile,([%w_]+),")
	if name then
		n = n + 1
		local id = 188 + n
		if donor[id] then
			ok(named[id] ~= name, "pack36 missile " .. name .. " (id " .. id .. ") must not keep its name: donor art")
		else
			kept = kept + 1
			ok(named[id] == name, "pack36 missile " .. name .. " (id " .. id .. ") keeps its art and its name (" .. tostring(named[id]) .. ")")
		end
	end
end
ok(n == 62, "the pack36 missile spec has 62 rows (" .. n .. ")")
ok(kept == 6, "six pack36 missile ids were not refilled by donors (" .. kept .. ")")

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("missile_art_source_test: OK")
