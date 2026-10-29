-- Chaos spell ids against the base server's (2026-10-15): the install step "spells" (tools/register_spells.py) refuses a
-- Chaos spellid that a base spell already uses, and tools/patch_spell_ids.py moves the base spells over 255 to ids of
-- its own. The base list is the base server's data/spells/spells.xml (ids below 256, windows-assets 50645056; the
-- conjure spells keep their ids in the client for the rune cooldown icons even after the server drops them).
-- Run from server/: luajit tests/spell_ids_test.lua
local BASE = {
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
	32, 33, 36, 38, 39, 42, 43, 44, 45, 48, 49, 50, 51, 54, 55, 56, 57, 59, 61, 62, 75, 76, 77, 78, 79, 80, 81, 82,
	83, 84, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 101, 102, 103, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114,
	115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 138, 139,
	140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 163, 166,
	167, 169, 172, 173, 174, 175, 176, 177, 178, 192, 193, 237
}
-- Ids of the base's ammunition conjure spells (Arrow Call 176, Fletch Crystal Arrows 192, Fletch Wraith Bolts 193). The
-- "archery" step (patch_base_archery.py) comments them out of spells.xml and tools/register_spells.py does not count them
-- as taken, so the Chaos block may reuse them (the Necromancer's Raise Bone Warrior / Archer / Mage, 2026-10-18): every
-- other id below 256 was in use until the cure spells were retired (RETIRED below). The ids the tools freed and nothing uses
-- are the pool of data/scripts/chaos/spell_id_pool_config.lua (checked at the end of this test). The client's stock entry of Arrow Call is moved off the byte range by spellfix.lua.
local AMMO_CONJURE = {176, 192, 193}
-- Ids of the other conjure spells the "runes" step (install_rune_supply.py, chaos_rune_supply.lua R.otherConjures)
-- removes: Conjure Rations 42, Charge Staff 92, Hallow Spear 110. No rune carries them (a rune's cooldown icon uses its
-- conjure spell's id), so register_spells.py does not count them as taken either; Grave Nova (Necromancer line,
-- 2026-10-22) uses 42. The client's stock Conjure Rations entry moves off it (spellfix.lua, chaosIds).
local OTHER_CONJURE = {42, 92, 110}
-- Ids of the stock cure (status cleansing) spells that tools/retire_cure_spells.py comments out of spells.xml (owner
-- 2026-10-20, C6): Purge Venom 29, Wash Taint 58, Staunch Blood 144, Douse Embers 145, Ground Static 146, Lift Hex 147,
-- Break Glamour 164. The Chaos block uses them for the new late spells of the ascended classes. The same tool retires
-- the stock Sharpshooter (Hawkeye, 135; owner 2026-10-20: its slow kept the Ranger's bow from firing): Tautstring has it;
-- and the stock Protector (Bulwark, 132) and Swift Foot (Windrunner, 134), which pacified the caster: Ironhold and
-- Wildstride have them. And the three stock light spells (owner 2026-10-28): Lantern 10, Greater Lantern 11, Radiant Lantern 75.
local RETIRED = {10, 11, 29, 58, 75, 132, 134, 135, 144, 145, 146, 147, 164}
do
	local tool = io.open("tools/retire_cure_spells.py"):read("*a")
	local rows = {}
	for id in tool:gmatch("': %((%d+), '") do rows[#rows + 1] = tonumber(id) end
	table.sort(rows)
	for i, id in ipairs(RETIRED) do
		if rows[i] ~= id then error("spell_ids_test: RETIRED " .. id .. " is not in retire_cure_spells.py CURES") end
	end
	if #rows ~= #RETIRED then error("spell_ids_test: RETIRED and retire_cure_spells.py CURES differ") end
end
local taken = {}
for _, id in ipairs(BASE) do taken[id] = "base" end
for _, id in ipairs(AMMO_CONJURE) do taken[id] = nil end
for _, id in ipairs(OTHER_CONJURE) do taken[id] = nil end
do -- the three are really removed: their scripts are R.otherConjures of the rune supply config
	local rs = io.open("data/lib/chaos_rune_supply.lua"):read("*a")
	for _, script in ipairs({"support/food.lua", "conjuring/enchant_staff.lua", "conjuring/enchant_spear.lua"}) do
		if not rs:find('script = "' .. script .. '"', 1, true) then
			error("spell_ids_test: " .. script .. " is not in R.otherConjures (chaos_rune_supply.lua)")
		end
	end
end
for _, id in ipairs(RETIRED) do taken[id] = nil end
-- Ids of the stock spells the 15-spell cap retires (tools/patch_spell_cap.py CAP rows with no class left, owner
-- 2026-10-20; the instant is commented out, or kept in the monster-only form without a spellid, so its id is free). The
-- attack kit (owner 2026-10-23, 37 attack spells) takes the first of them. Read from the tool, so a CAP change cannot
-- leave a kit spell on an id that is taken again.
local CAP_RETIRED = {}
do
	local tool = io.open("tools/patch_spell_cap.py"):read("*a")
	local block = tool:match("\nCAP = {(.-)\n}\n")
	if not block then error("spell_ids_test: CAP table not found in patch_spell_cap.py") end
	for id in block:gmatch("%((%d+), [^\n]-, %(%)%)") do
		CAP_RETIRED[#CAP_RETIRED + 1] = tonumber(id)
	end
	if #CAP_RETIRED < 40 then error("spell_ids_test: only " .. #CAP_RETIRED .. " retired ids parsed from CAP") end
	for _, id in ipairs(CAP_RETIRED) do taken[id] = nil end
end
-- Ids tools/patch_spell_ids.py gives to the base spells over 255 (NEW_IDS), read from the tool: a spell that the cap
-- retired (a CAP row with no class, CAP_RETIRED_SCRIPTS) keeps no id, so only the others are taken. Before 2026-10-28 the
-- test counted all 14 as taken, which hid nine free ids (35 40 41 47 52 60 165 168 171).
do
	local tool = io.open("tools/patch_spell_ids.py"):read("*a")
	local block = tool:match("\nNEW_IDS = {(.-)\n}\n")
	if not block then error("spell_ids_test: NEW_IDS table not found in patch_spell_ids.py") end
	local cap = io.open("tools/patch_spell_cap.py"):read("*a"):match("\nCAP = {(.-)\n}\n")
	local n, live = 0, 0
	for script, id in block:gmatch("'([^']+)': (%d+),") do
		n = n + 1
		if cap:find("'" .. script .. "': %(%d+, [^\n]-, %(%)%)") then
			-- retired by the cap: no id
		else
			taken[tonumber(id)] = "patch_spell_ids.py"; live = live + 1
		end
	end
	if n ~= 14 then error("spell_ids_test: " .. n .. " NEW_IDS rows parsed, 14 expected") end
	if live ~= 5 then error("spell_ids_test: " .. live .. " moved spells keep an id, 5 expected (34 37 46 53 85)") end
end
-- the three ids are really switched off: their conjure scripts are in the archery config
local arch = io.open("data/lib/chaos_archery_config.lua"):read("*a")
for _, name in ipairs({"arrow_call.lua", "conjure_diamond_arrow.lua", "spectral_bolt.lua"}) do
	if not arch:find('"' .. name .. '"', 1, true) then
		print("FAIL " .. name .. " is not in conjureScripts (chaos_archery_config.lua)")
		error("spell_ids_test: the ammunition conjure ids are not free")
	end
end
local xml = io.open("data/spells/chaos/spells_chaos.xml"):read("*a"):gsub("<!%-%-.-%-%->", "")
local fails, seen, n = 0, {}, 0
for tag in xml:gmatch("<instant[^>]*>") do
	local id, name = tonumber(tag:match('spellid="(%d+)"')), tag:match('name="([^"]+)"')
	n = n + 1
	if not id or id > 255 then
		fails = fails + 1; print("FAIL " .. tostring(name) .. ": spellid missing or over 255")
	elseif taken[id] then
		fails = fails + 1; print("FAIL " .. name .. ": spellid " .. id .. " is used by " .. taken[id])
	elseif seen[id] then
		fails = fails + 1; print("FAIL " .. name .. ": spellid " .. id .. " also used by " .. seen[id])
	end
	if id then seen[id] = name end
end
if fails > 0 then error("spell_ids_test: " .. fails .. " failure(s)") end

-- The pool for the 21 line-quest spells (data/scripts/chaos/spell_id_pool_config.lua): every id is free in the install.
-- freed = ids a retiring tool took out of the install (not an id of the conjure lists, which the client keeps for icons)
local freed = {}
for _, id in ipairs(RETIRED) do freed[id] = true end
for _, id in ipairs(CAP_RETIRED) do freed[id] = true end
local pool = dofile("data/scripts/chaos/spell_id_pool_config.lua")
if #pool.ids ~= 21 then error("spell_ids_test: the pool holds " .. #pool.ids .. " ids, 21 expected") end
-- the quest spells take their ids from the pool (phase 2: the level 500 attacks; 3 per line in the order of the pool)
local questName = {}
for _, line in ipairs(dofile("data/scripts/chaos/spellquest_config.lua").lines) do
	for _, name in ipairs(line.spells) do questName[name] = true end
end
local inPool = {}
for _, group in ipairs({{"ids", pool.ids}, {"spare", pool.spare}}) do
	for _, id in ipairs(group[2]) do
		if type(id) ~= "number" or id < 1 or id > 255 or id ~= math.floor(id) then
			error("spell_ids_test: pool " .. group[1] .. " " .. tostring(id) .. " is not a spell id of one byte")
		end
		if inPool[id] then error("spell_ids_test: pool id " .. id .. " listed twice") end
		inPool[id] = group[1]
		if taken[id] then error("spell_ids_test: pool id " .. id .. " is used by " .. taken[id]) end
		if seen[id] and not (group[1] == "ids" and questName[seen[id]]) then
			error("spell_ids_test: pool id " .. id .. " is used by the Chaos spell " .. seen[id])
		end
		if not freed[id] then error("spell_ids_test: pool id " .. id .. " is not freed by a retiring tool") end
	end
end
-- a quest spell uses an id of the pool, never another one
for id, name in pairs(seen) do
	if questName[name] and inPool[id] ~= "ids" then error("spell_ids_test: the quest spell " .. name .. " has id " .. id .. ", not a pool id") end
end
local free = 0
for id = 1, 255 do
	if not taken[id] and not seen[id] then free = free + 1 end
end
print("spell_ids_test: " .. n .. " Chaos spells, no id taken by the base server; " .. free .. " ids free, pool " ..
	#pool.ids .. " + " .. #pool.spare .. " spare")
