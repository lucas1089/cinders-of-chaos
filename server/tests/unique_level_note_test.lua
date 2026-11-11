-- Run from the server/ folder: luajit tests/unique_level_note_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- O510 (owner 2026-11-11: "the tag lies"): a unique without an equip rule of its own, whose base item the server lets
-- everyone wear (or from a lower level than the unique's own), does not "require" its level. The 58 of
-- data/items/unique_level_not_asked.csv (tools/gen_unique_specs.py reads it):
--   * their spec carries levelNotAsked = true and no `equip`; the spec text says "(Meant for level N.)", not "(Requires
--     level N.)", in English and pt-BR; a copy dropped before the change (the old English text) reads the same pt-BR text;
--   * every other unique keeps "(Requires level N.)" and has its own equip rule or is not in the list;
--   * the Codex row of the list is "Meant for level", of every other unique "Required level" (generated codex_data.lua);
--   * the passive line of an old or new description is cut at either sentence (T.refreshPassive), K.specLevel reads both.
-- The tooltip itself (no level chip) is tests/item_tooltip_test.lua; the audit is tools/audit_equip_tooltips_test.py.
local count, failures = 0, 0
local function check(cond, what)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what) check(a == b, (what or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^ITEM_ATTRIBUTE_") then return k end
end})
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/lib/chaos_crafting.lua")
dofile("data/lib/chaos_unique_items.lua")
dofile("data/lib/chaos_unique_desc_pt.lua")
dofile("data/scripts/chaos/item_tooltip_core.lua")
dofile("data/scripts/chaos/conquest_core.lua")
local T, K = ChaosItemTooltip, ChaosConquestCore

-- the list
local list, rows = {}, 0
local f = assert(io.open("data/items/unique_level_not_asked.csv", "r"))
local header = f:read("*l")
eq(header, "id,name,slot,unique_level,equip_entry_level,weapon_entry_level,set", "the columns")
for line in f:lines() do
	local id, name, slot, level, entry, weapon, set = line:match("^(%d+),([^,]*),([^,]*),(%d+),(%d+),(%d+),([^,]*)$")
	check(id ~= nil, "a well formed row: " .. line)
	if id then
		id = tonumber(id)
		rows = rows + 1
		check(not list[id], id .. ": once")
		list[id] = {name = name, slot = slot, level = tonumber(level), entry = tonumber(entry), weapon = tonumber(weapon), set = set}
	end
end
f:close()
eq(rows, 58, "the list: 35 found by the audit, 23 more with no rule at all in the installed files")

local noted, unnoted = 0, 0
for id, spec in pairs(ChaosUniqueSpecs) do
	local row = list[id]
	local entry = ChaosUniqueById[id]
	local d = spec.description
	if row then
		noted = noted + 1
		check(entry ~= nil, id .. ": a unique of the drop list")
		eq(spec.levelNotAsked, true, id .. ": the spec says so")
		eq(spec.equip, nil, id .. ": and has no equip rule of its own")
		eq(spec.name, row.name, id .. ": the name")
		eq(entry and entry.level, row.level, id .. ": the level of the list is the unique's level")
		check(row.level > math.max(row.entry, row.weapon), id .. ": the unique's level is above what the server asks")
		check(d:find("(Meant for level " .. row.level .. ".)", 1, true) ~= nil, id .. ": the text says meant for level N: " .. d)
		check(not d:find("Requires level", 1, true), id .. ": the text no longer says requires")
		local pt = ChaosUniqueDescPt[d]
		check(pt ~= nil and pt:find("(Feito para o n\195\173vel " .. row.level .. ".)", 1, true) ~= nil, id .. ": the pt-BR text")
		check(pt == nil or not pt:find("Requer", 1, true), id .. ": no requer in pt-BR")
		-- a copy dropped before the change carries the old text: its look reads the same pt-BR text
		local old = d:gsub("%(Meant for level", "(Requires level", 1)
		eq(ChaosUniqueDescPt[old], pt, id .. ": the old English text has the new pt-BR text")
		eq(K.specLevel(spec), row.level, id .. ": the conquest vendor still reads the level")
	elseif entry then
		unnoted = unnoted + 1
		eq(spec.levelNotAsked, nil, id .. ": not in the list: no flag")
		check(d:find("Meant for level", 1, true) == nil, id .. ": not in the list: no meant for level")
		check(d:find("(Requires level " .. entry.level, 1, true) ~= nil, id .. ": keeps its requires level")
	end
end
eq(noted, 58, "the list is in the specs")
check(unnoted > 100, "the others were read (" .. unnoted .. ")")

-- the passive line is cut at either sentence (a description of before and after)
local en = "Hungry Blade: Each kill restores 7.1% of your maximum health. For: Warrior."
for _, tail in ipairs({" (Requires level 120.)", " (Meant for level 120.)", " (Requer n\195\173vel 120.)", " (Feito para o n\195\173vel 120.)"}) do
	local out, changed = T.refreshPassive("Flavour. Hungry Blade: Each kill restores 5% of your maximum health." .. tail, en, "Hungry Blade")
	eq(out, "Flavour. " .. en .. tail, "refreshPassive keeps " .. tail)
	eq(changed, true, "and says it changed the line")
end
eq(K.specLevel({description = "x. (Meant for level 90.)"}), 90, "the conquest vendor reads Meant for level")
eq(K.specLevel({description = "x. (Requires level 90.)"}), 90, "and Requires level")

-- the Codex (generated client file): the row of the list says what the level is
local data = dofile("../client/overlay/modules/game_codex/codex_data.lua")
local function levelRow(entry)
	for _, sec in ipairs(entry.sections or {}) do
		if sec.h == "Item" then
			for _, r in ipairs(sec.rows or {}) do
				if r[1] == "Required level" or r[1] == "Meant for level" then
					return r[1], r[2]
				end
			end
		end
	end
end
local meantRows, requiredRows = 0, 0
local function walk(t)
	if type(t) ~= "table" then
		return
	end
	if type(t.id) == "string" and t.id:match("^unique:%d+$") and t.sections then
		local id = tonumber(t.id:match("%d+"))
		local label, value = levelRow(t)
		local row = list[id]
		if row then
			eq(label, "Meant for level", id .. ": the Codex row of the list")
			eq(value, tostring(row.level), id .. ": the Codex level")
			meantRows = meantRows + 1
		elseif label then
			eq(label, "Required level", id .. ": the Codex row of the others")
			requiredRows = requiredRows + 1
		end
		return
	end
	for _, v in pairs(t) do
		walk(v)
	end
end
walk(data)
eq(meantRows, 58, "the Codex rows of the list")
check(requiredRows > 100, "the Codex rows of the others (" .. requiredRows .. ")")

print(string.format("unique_level_note_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
print("unique_level_note_test: " .. count .. " checks OK")
