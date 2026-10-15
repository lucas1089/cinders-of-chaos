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
local PATCHED = { -- tools/patch_spell_ids.py NEW_IDS
	34, 35, 37, 40, 41, 46, 47, 52, 53, 58, 60, 85, 164, 165, 168, 171
}
local taken = {}
for _, id in ipairs(BASE) do taken[id] = "base" end
for _, id in ipairs(PATCHED) do taken[id] = "patch_spell_ids.py" end
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
