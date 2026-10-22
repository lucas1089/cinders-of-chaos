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
-- other id below 256 was in use until the cure spells were retired (RETIRED below). The client's stock entry of Arrow Call is moved off the byte range by spellfix.lua.
local AMMO_CONJURE = {176, 192, 193}
-- Ids of the other conjure spells the "runes" step (install_rune_supply.py, chaos_rune_supply.lua R.otherConjures)
-- removes: Conjure Rations 42, Charge Staff 92, Hallow Spear 110. No rune carries them (a rune's cooldown icon uses its
-- conjure spell's id), so register_spells.py does not count them as taken either; Grave Nova (Necromancer line,
-- 2026-10-22) uses 42. The client's stock Conjure Rations entry moves off it (spellfix.lua, chaosIds).
local OTHER_CONJURE = {42, 92, 110}
local PATCHED = { -- tools/patch_spell_ids.py NEW_IDS (Wash Taint 58 and Break Glamour 164 went with the cure spells)
	34, 35, 37, 40, 41, 46, 47, 52, 53, 60, 85, 165, 168, 171
}
-- Ids of the stock cure (status cleansing) spells that tools/retire_cure_spells.py comments out of spells.xml (owner
-- 2026-10-20, C6): Purge Venom 29, Wash Taint 58, Staunch Blood 144, Douse Embers 145, Ground Static 146, Lift Hex 147,
-- Break Glamour 164. The Chaos block uses them for the new late spells of the ascended classes. The same tool retires
-- the stock Sharpshooter (Hawkeye, 135; owner 2026-10-20: its slow kept the Ranger's bow from firing): Tautstring has it;
-- and the stock Protector (Bulwark, 132) and Swift Foot (Windrunner, 134), which pacified the caster: Ironhold and
-- Wildstride have them.
local RETIRED = {29, 58, 132, 134, 135, 144, 145, 146, 147, 164}
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
for _, id in ipairs(PATCHED) do taken[id] = "patch_spell_ids.py" end
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
print("spell_ids_test: " .. n .. " Chaos spells, no id taken by the base server")
