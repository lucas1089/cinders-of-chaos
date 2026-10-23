-- Run from the server/ folder: luajit tests/unique_mods_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Built-in Chaos modifiers of uniques and the leveling / endgame uniques (server/README.md "Leveling and endgame
-- uniques", 2026-10-23):
--   * spec.mods (attribute `mods` of data/items/chaos_items.xml, tools/gen_unique_specs.py) names only modifiers and
--     legendary powers of chaos_item_mods.lua / chaos_powers.lua, each once, no value above its cap;
--   * ChaosMakeUnique writes them as T8 modifiers that ChaosItemMods.read gives back as they are;
--   * the leveling uniques: level 10-35, an equip rule of that level for every class, magic monster drops with higher
--     odds than the other uniques; the endgame uniques: level 1200 and up, an equip rule, exactly one legendary power,
--     dropped by waystone monsters and bosses only (minMonsterLevel or boss only);
--   * the reworked level 800 / 1000 uniques carry built-in modifiers.
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
dofile("data/lib/chaos_item_mods.lua")
dofile("data/lib/chaos_unique_specs.lua")
dofile("data/lib/chaos_unique_items.lua")
local M, P, SPECS = ChaosItemMods, ChaosPowers, ChaosUniqueSpecs
check(M and M.byKey and P, "the modifier and power catalogues are loaded")

-- ------------------------------------------------------------------------------------------------ every spec.mods
local withMods = 0
for id, spec in pairs(SPECS) do
	if spec.mods then
		withMods = withMods + 1
		local seen = {}
		for _, m in ipairs(spec.mods) do
			local def = M.byKey[m[1]]
			check(def ~= nil, spec.name .. ": " .. tostring(m[1]) .. " is a modifier")
			check(not seen[m[1]], spec.name .. ": " .. tostring(m[1]) .. " once")
			seen[m[1]] = true
			check(type(m[2]) == "number" and m[2] > 0, spec.name .. ": " .. tostring(m[1]) .. " above 0")
			if def then
				check(m[2] <= def.cap, spec.name .. ": " .. m[1] .. " " .. m[2] .. " within the cap " .. def.cap)
			end
		end
	end
end
check(withMods >= 37, "at least 37 uniques with built-in modifiers (" .. withMods .. ")")

-- ------------------------------------------------------------------------------------------------ ChaosMakeUnique
local function fakeItem(id)
	local it = {id = id, attrs = {}, custom = {}}
	function it:getId() return self.id end
	function it:setAttribute(k, v) self.attrs[k] = v end
	function it:removeAttribute(k) self.attrs[k] = nil end
	function it:setCustomAttribute(k, v) self.custom[k] = v end
	function it:removeCustomAttribute(k) self.custom[k] = nil end
	function it:getCustomAttribute(k) return self.custom[k] end
	function it:getType() return nil end
	return it
end
local byName = {}
for id, spec in pairs(SPECS) do
	byName[spec.name] = id
end
local verdict = fakeItem(byName["Ashfall Verdict"])
check(ChaosMakeUnique(verdict), "the Ashfall Verdict is made")
eq(verdict.custom.chaos_unique, 1, "it is a unique")
local got = {}
for _, m in ipairs(M.read(verdict)) do
	got[m.key] = m
end
eq(got.attackspeed and got.attackspeed.value, 15, "attack speed written")
eq(got.critecho and got.critecho.value, 22, "its power written")
eq(got.critecho and got.critecho.tier, 8, "as a T8 modifier")
check(got.critecho and M.isPower(got.critecho.def), "Critical Echo is a legendary power")
local totals = M.totals({verdict})
eq(totals.bossdamage, 20, "the equipped totals count it")

-- a capped power keeps a value inside its T8 range (Smoldering Aura reads as the top of its tier at most)
local robe = fakeItem(byName["Vestments of the Hollow Choir"])
ChaosMakeUnique(robe)
eq(M.value(robe, "smolderaura"), 30, "Smoldering Aura stored")
local aura
for _, m in ipairs(M.read(robe)) do
	if m.key == "smolderaura" then aura = m.value end
end
check(aura and aura <= 35, "Smoldering Aura read within its T8 top")

-- ------------------------------------------------------------------------------------------------ the drop entries
local drop = {}
for _, e in ipairs(ChaosUniqueItems) do
	drop[e.name] = e
end
local LEVELING = {"Ashen Pilgrim's Blade", "Hatchet of the First Winter", "Tallow-Bell Mace", "Fenwatch Longbow",
	"Cinder-Wick Wand", "Hood of the Roaming Pyre", "Pathfinder's Treads", "Band of the Second Dawn",
	"Moth-Lantern Pendant", "Gutter-Saint's Mail", "Wanderer's Leggings", "Lantern-Ward Buckler"}
local ENDGAME = {"Ashfall Verdict", "Wyrmgrave Cleaver", "Maul of the Sunken Choir", "Stormherald's Recurve",
	"Diadem of the Ninth Pyre", "Vestments of the Hollow Choir", "Bastion of the Last Dawn",
	"Greaves of the Endless Road", "Legguards of Unmaking", "Band of the Severed Star", "Rampart of Grey Tides",
	"Choirless Pendant"}
local REWORKED = {"Sanguine Crescent", "Hollow Crown of Morvane", "Eye of the Unbroken Storm", "Cinderheart Signet",
	"Gravewarden's Verdict", "Shroud of the Ash-Sister", "Marrowforged Greaves", "Eye of the Hexmaw",
	"Crown of the Last Sovereign", "Ashwarden Visor", "Ashwarden Cuirass", "Ashwarden Bulwark", "Ashwarden Seal"}

local function powers(spec)
	local n = 0
	for _, m in ipairs(spec.mods or {}) do
		if M.byKey[m[1]] and M.isPower(M.byKey[m[1]]) then n = n + 1 end
	end
	return n
end
local ids = {}
local function common(name)
	local id = byName[name]
	local spec, e = id and SPECS[id], drop[name]
	check(spec ~= nil, name .. ": a spec")
	check(e ~= nil, name .. ": a drop entry")
	if not (spec and e) then
		return
	end
	check(not ids[id], name .. ": its own base id")
	ids[id] = true
	eq(e.id, id, name .. ": the drop entry's id")
	check(spec.mods and #spec.mods >= 2, name .. ": built-in modifiers")
	check(spec.equip ~= nil, name .. ": an equip rule")
	eq(spec.equip and spec.equip.level, e.level, name .. ": the rule's level is the drop entry's")
	eq(tonumber(spec.description:match("Requires level (%d+)")), e.level, name .. ": the description's level")
	check(#e.monsters > 0, name .. ": dropped by someone")
	return spec, e
end
for _, name in ipairs(LEVELING) do
	local spec, e = common(name)
	if spec then
		check(e.level >= 10 and e.level <= 35, name .. ": a leveling level")
		eq(#spec.equip.vocations, 0, name .. ": every class may wear it")
		eq(e.minTier, "magic", name .. ": magic monsters and up")
		check(e.chance >= 20, name .. ": higher odds than the other uniques")
		check(not e.bossOnly, name .. ": not boss only")
		eq(powers(spec), 0, name .. ": no legendary power")
	end
end
for _, name in ipairs(ENDGAME) do
	local spec, e = common(name)
	if spec then
		check(e.level >= 1200, name .. ": an endgame level")
		eq(powers(spec), 1, name .. ": exactly one legendary power")
		check(e.bossOnly or (e.minMonsterLevel or 0) >= 1000, name .. ": waystone-level kills only")
	end
end
for _, name in ipairs(REWORKED) do
	local id = byName[name]
	check(id and SPECS[id].mods and #SPECS[id].mods >= 2, name .. ": built-in modifiers")
end

-- ------------------------------------------------------------------------------------------------ the generator
local f = io.open("tools/gen_unique_specs.py")
local src = f and f:read("*a") or ""
if f then f:close() end
check(src:find("def built_in_mods", 1, true), "gen_unique_specs.py parses `mods`")

print(string.format("unique_mods_test: %d of %d failed", failures, count))
if failures > 0 then
	os.exit(1)
end
