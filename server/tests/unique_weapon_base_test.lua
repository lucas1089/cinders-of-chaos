-- Run from the server/ folder: luajit tests/unique_weapon_base_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Unique weapons and their base (server/README.md "Unique weapons and their base (O520)").
-- A unique is a copy of a stock base item, and the engine's weapon check belongs to the base item id: the item type
-- says what kind of weapon it is (items.xml weaponType), and the weapons.xml entry of that id says from which level
-- and for which classes it hits. A class that is not on the entry's list gets no hit at all (Weapon::playerWeaponCheck
-- returns 0, no engine patch changes it). install_unique_equip.py only loosens the Equip entry, so a unique whose
-- equip rule names a class its base's weapon entry refuses can be worn and never hits.
-- Found by the equip tooltip audit (O490): the Misericorde of the Pale Vow, a Thief dagger, sat on 27193, a wand of
-- the Mystic and Necromancer lines that only looks like a dagger. It is on 7408 now, a one-handed sword.
-- This test holds every unique weapon of data/items/chaos_items.xml to the snapshot of the stock weapons
-- (data/items/base_weapons.csv, tools/survey_base_weapons.py):
--   * the base is a weapon of the kind the unique says (sword, axe, club, distance, wand);
--   * every class the unique's equip rule names is in the row's class list (or the row lets every class hit);
--   * the unique's level is not below the row's level (below it the hit is halved or nothing).
-- A unique without an equip rule follows its base in both checks, so only its kind is held.
-- The row's classes and level are the weapons.xml entry narrowed by the base's stock Equip rule (the survey joins the
-- two: who hits with a plain copy). That is the strict side: a base whose Equip rule alone is narrower fails here too,
-- although the unique equip step would open it. Read the base's weapons.xml entry before picking it then.
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
dofile("data/lib/chaos_unique_specs.lua")
dofile("data/lib/chaos_unique_items.lua")
local SPECS = ChaosUniqueSpecs

local function readFile(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

-- ------------------------------------------------------------------------------------------------ the stock weapons
-- id -> {kind, level, classes = nil (every class) or {name = true}}
local FIRST_CHAOS_ID = 36654 -- tools/survey_base_weapons.py: the snapshot keeps the stock items only
local base, rows = {}, 0
local header
for line in readFile("data/items/base_weapons.csv"):gmatch("[^\r\n]+") do
	local cols = {}
	for cell in (line .. ","):gmatch("([^,]*),") do cols[#cols + 1] = cell end
	if not header then
		header = {}
		for i, name in ipairs(cols) do header[name] = i end
	else
		local classes
		if cols[header.classes] ~= "*" then
			classes = {}
			for name in cols[header.classes]:gmatch("[^|]+") do classes[name] = true end
		end
		base[tonumber(cols[header.id])] = {kind = cols[header.kind], level = tonumber(cols[header.level]) or 0,
			classes = classes}
		rows = rows + 1
	end
end
check(header and header.id and header.kind and header.level and header.classes, "base_weapons.csv has id, kind, level, classes")
check(rows > 300, "the snapshot lists the stock weapons: " .. rows)

-- the kinds of the snapshot a unique's weaponType may sit on
local KINDS = {sword = {sword = true}, axe = {axe = true}, club = {club = true},
	distance = {bow = true, crossbow = true, throw = true}, wand = {wand = true}}
-- the 21 classes, for a rule with an empty class list (every class)
local ALL = {"Warrior", "Juggernaut", "Berserker", "Ranger", "Deadeye", "Beastmaster", "Mystic", "Elementalist",
	"Illusionist", "Thief", "Ninja", "Samurai", "Monk", "Shadowfist", "Iron Sage", "Necromancer", "Lich", "Bone Lord",
	"Templar", "Inquisitor", "Sentinel"}

-- the problems of one unique weapon against its base row: a list of sentences (pure, tested below)
local function problems(name, weaponType, rule, row)
	local out = {}
	if not row then
		out[1] = name .. ": its base has no row in base_weapons.csv (no weapon of items.xml with a weapons.xml entry)"
		return out
	end
	if not (KINDS[weaponType] and KINDS[weaponType][row.kind]) then
		out[#out + 1] = string.format("%s: a %s on a base that is a %s", name, weaponType, row.kind)
	end
	if rule then
		if row.classes then
			local names = rule.vocations
			if not names or #names == 0 then names = ALL end
			local refused = {}
			for _, voc in ipairs(names) do
				if not row.classes[voc] then refused[#refused + 1] = voc end
			end
			if #refused > 0 then
				out[#out + 1] = string.format("%s: a plain copy of the base gives no hit to %s", name, table.concat(refused, ", "))
			end
		end
		if (rule.level or 0) < row.level then
			out[#out + 1] = string.format("%s: worn from level %d, a plain copy of the base hits from %d", name, rule.level or 0, row.level)
		end
	end
	return out
end

-- the rule itself, on made-up rows
local thief = {level = 1900, vocations = {"Thief", "Ninja", "Samurai"}}
local casterWand = {kind = "wand", level = 180, classes = {Mystic = true, Elementalist = true, Necromancer = true}}
local found = problems("old Misericorde", "sword", thief, casterWand)
eq(#found, 2, "the shape of the finding: wrong kind and refused classes")
check(found[1]:find("a sword on a base that is a wand", 1, true), "it names the kind: " .. tostring(found[1]))
check(found[2]:find("no hit to Thief, Ninja, Samurai", 1, true), "it names the classes: " .. tostring(found[2]))
eq(#problems("x", "sword", thief, {kind = "sword", level = 25}), 0, "a sword every class hits with: fine")
eq(#problems("x", "sword", thief, {kind = "sword", level = 300, classes = {Thief = true, Ninja = true, Samurai = true}}), 0,
	"an entry that lists the unique's classes: fine")
eq(#problems("x", "sword", thief, {kind = "sword", level = 300, classes = {Thief = true, Ninja = true}}), 1, "one class missing")
eq(#problems("x", "sword", {level = 10, vocations = {}}, {kind = "sword", level = 0, classes = {Warrior = true}}), 1,
	"an empty class list is every class: a class entry refuses most")
eq(#problems("x", "sword", {level = 20, vocations = {}}, {kind = "sword", level = 25}), 1, "a level below the entry's")
eq(#problems("x", "distance", nil, {kind = "crossbow", level = 60}), 0, "a distance unique on a crossbow, no rule: follows its base")
eq(#problems("x", "sword", nil, {kind = "wand", level = 60, classes = {Mystic = true}}), 1, "no rule: the kind is still held")
eq(#problems("x", "axe", nil, nil), 1, "no row")

-- ------------------------------------------------------------------------------------------------ every unique weapon
local xml = readFile("data/items/chaos_items.xml")
local weapons, withRule = 0, 0
for id, body in xml:gmatch('<item id="(%d+)"[^>]*>(.-)</item>') do
	id = tonumber(id)
	local weaponType = body:match('key="weaponType" value="(%w+)"')
	-- a shield, a quiver, a spellbook or a fist weapon (weaponType shield) has no weapons.xml entry of this kind
	if weaponType and weaponType ~= "shield" and id < FIRST_CHAOS_ID then
		weapons = weapons + 1
		local spec = SPECS[id]
		check(spec ~= nil, "a spec for unique " .. id)
		local rule = spec and spec.equip
		if rule then withRule = withRule + 1 end
		for _, text in ipairs(problems((spec and spec.name or "?") .. " (" .. id .. ")", weaponType, rule, base[id])) do
			check(false, text .. ". Pick a base of the unique's kind whose weapon entry lets its classes hit "
				.. "(README \"Unique weapons and their base (O520)\")")
		end
	end
end
check(weapons >= 50, "the unique weapons on stock bases were read: " .. weapons)
check(withRule >= 20, "the ones with an equip rule of their own: " .. withRule)

-- ------------------------------------------------------------------------------------------------ the finding (O520)
local mis = ChaosUniqueByName["Misericorde of the Pale Vow"]
check(mis ~= nil, "the Misericorde of the Pale Vow drops")
eq(mis and mis.id, 7408, "its base")
eq(SPECS[27193], nil, "no unique on the wand 27193 any more")
local row = base[7408]
check(row and row.kind == "sword" and row.classes == nil and row.level <= 1900,
	"7408 is a sword every class hits with, from a level below the unique's")
check(base[27193] and base[27193].kind == "wand" and base[27193].classes and not base[27193].classes.Thief,
	"27193 is a wand whose entry refuses the Thief (why the unique left it)")
local rule = SPECS[7408] and SPECS[7408].equip
check(rule and rule.level == 1900 and #rule.vocations == 3 and rule.vocations[1] == "Thief", "its rule: the Thief line from 1900")
-- the other Thief daggers stay on swords every class hits with
for _, id in ipairs({2403, 2402, 2404, 2411, 7404}) do
	check(base[id] and base[id].kind == "sword" and base[id].classes == nil, "Thief dagger base " .. id .. " is an open sword")
end

print(string.format("unique_weapon_base_test: %d checks, %d failures", count, failures))
if failures > 0 then os.exit(1) end
