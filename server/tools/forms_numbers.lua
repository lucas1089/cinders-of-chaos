-- The Lua side of the Form band of tools/spell_upgrade_model.py (O686 phase 4, docs/SPELL_UPGRADES.md 2.1): the gain of every Form row of
-- data/spells/forms.csv from the real planner (data/scripts/chaos/spell_forms_core.lua), on one enemy and on a pack of five. Run from server/:
--   luajit tools/forms_numbers.lua < t5.txt        (stdin: one line per spell, "spell id" TAB "targets the spell hits of five")
--   luajit tools/forms_numbers.lua --kinds         (the standard numbers of the kinds, for the README)
-- Output, tab separated, one line per Form row: id tier pick kind gain-on-one gain-on-five situation utility(1 | 0).
-- The spell hits `t` of the five (1 for a single target spell; the rotation model's t5 for an area spell). A gain is the damage (heal) of
-- one cast with the Form over the cast without it. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
dofile("data/scripts/chaos/spell_forms_core.lua")
dofile("data/lib/chaos_spell_forms.lua")
local F = ChaosSpellFormsCore
local M = ChaosSpellForms

if arg and arg[1] == "--kinds" then
	local all = {}
	for _, list in ipairs({F.kinds1, F.kinds2, F.heal1, F.heal2}) do
		for _, k in ipairs(list) do
			all[#all + 1] = k
		end
	end
	for _, k in ipairs(all) do
		local keys = {}
		for key in pairs(F.numbers[k]) do
			keys[#keys + 1] = key
		end
		table.sort(keys)
		local parts = {}
		for _, key in ipairs(keys) do
			parts[#parts + 1] = key .. "=" .. tostring(F.numbers[k][key])
		end
		print(k .. "\t" .. (F.scope[k] or "") .. "\t" .. (F.situation[k] or "") .. "\t" .. table.concat(parts, " "))
	end
	os.exit(0)
end

local t5 = {}
for line in io.lines() do
	local id, v = line:match("^(%d+)%s+([%d%.]+)")
	if id then
		t5[tonumber(id)] = tonumber(v)
	end
end

local f = assert(io.open("data/spells/forms.csv", "r"))
local rows = assert(M.parse(f:read("*a")))
f:close()

local ids = {}
for id in pairs(rows) do
	ids[#ids + 1] = id
end
table.sort(ids)
for _, id in ipairs(ids) do
	local s = rows[id]
	local t = s.heal and 1 or math.max(1, math.min(5, math.floor((t5[id] or 1) + 0.5)))
	for tier = 1, 2 do
		for pick = 1, 2 do
			local spec = s[tier][pick]
			if spec then
				print(string.format("%d\t%d\t%d\t%s\t%.4f\t%.4f\t%s\t%d", id, tier, pick, spec.row.kind, F.gain(spec, 1, 1),
					F.gain(spec, 5, t), F.situation[spec.kind] or "both", F.utility[spec.kind] and 1 or 0))
			end
		end
	end
end
