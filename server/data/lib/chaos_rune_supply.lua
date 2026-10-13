-- Rune supply (server/README.md "Rune supply"): no spell conjures a rune any more (owner: "Tire as spells de fazer runa.
-- Deixa as runas serem de vendedores e craft."). Every rune a stock spell conjured is sold by NPC vendors and made at the
-- general crafting tables. Read by:
--   server/tools/install_rune_supply.py  (install step "runes"): comments the conjure spells out of spells.xml, sets
--                                        every NPC's price of these runes, stocks the vendors below, and appends the
--                                        recipe loader to the crafting category file
--   the base crafting script (data/scripts/customs/crafting/<category>.lua, the loader line): R.addRecipes
--   server/tests/rune_supply_test.lua, tools/ci/check_content.py
-- The Python tool reads this file as text: keep one rune per line and the key = value layout below.
-- Must parse in Lua 5.3 and LuaJIT; no engine calls at load time.

local R = {}

-- the unscribed (blank) rune: sold by the vendors, the base of every recipe; its conjure spell goes too
R.blankRune = {id = 2260, name = "Unscribed Rune", script = "blank_rune.lua", price = 10}

-- the conjure spells that make no rune, removed too (owner, 2026-10-13: "Pode tirar, já que as ammos são infinitas"), by
-- their spells.xml script. The foods of Conjure Rations stay on sale at the food vendors (meat, ham, bread and cheese in
-- Mirewake); the enchanted spear and staff were only ever conjured. The rune scripts are conjuring/<script> (R.runes).
R.otherConjures = {
	{script = "support/food.lua", name = "Conjure Rations"},
	{script = "conjuring/enchant_spear.lua", name = "Hallow Spear"},
	{script = "conjuring/enchant_staff.lua", name = "Charge Staff"},
}

-- town ids (server/tools/base_towns.csv): the main hub (town 1, Mirewake: the temple NPCs stand there) and the towns a new
-- character may call home (website CHAOS_START_TOWNS, default "1"). Every rune must have a vendor in each.
R.hubTown = 1
R.startTowns = {1}

-- the vendors that sell every rune and the unscribed rune, by their Chaos name (data/npc/base_npc_names.csv gives the
-- file before the npcnames step renames it). Mirewake: the hub and the default home town; Cinderhold: the second city.
R.vendors = {
	{name = "Raloth", town = 1},
	{name = "Isora", town = 2},
}

-- The runes, by required level. id: the rune item; name: its Chaos name (spell_names.csv); level: the rune's level; the
-- stock conjure spell it replaces: script (data/spells/scripts/conjuring/), mana, soul, count (runes per blank rune);
-- price: gold per rune at every NPC that sells it; old: the lowest base NPC price before (0: no NPC sold it).
-- price = the conjure cost in gold, x the level band factor, never below old (docs: server/README.md "Rune supply"):
--   conjure gold = (mana x 0.5 + soul x 10 + blank rune 10) / count; 0.5 gold a mana point is what mana potions cost.
--   band factor: rune level 1-24 x1.0, 25-34 x1.1, 35+ x1.2. Rounded: under 100 to 1, under 1000 to 5, else to 10.
--   At least 2 x (blank rune / count), so a craft is always cheaper than the vendor.
R.runes = {
	{id = 23723, name = "Faint Dart Rune", level = 1, script = "lightest_missile_rune.lua", mana = 6, soul = 0, count = 10, price = 2, old = 0},
	{id = 19392, name = "Faint Hexdart Rune", level = 1, script = "practice_magic_missile_rune.lua", mana = 5, soul = 0, count = 10, price = 2, old = 0},
	{id = 23722, name = "Pebblestorm Rune", level = 1, script = "light_stone_shower_rune.lua", mana = 6, soul = 3, count = 4, price = 11, old = 0},
	{id = 2285, name = "Blightpatch Rune", level = 14, script = "poison_field_rune.lua", mana = 200, soul = 1, count = 3, price = 40, old = 21},
	{id = 2301, name = "Cinderpatch Rune", level = 15, script = "fire_field_rune.lua", mana = 240, soul = 1, count = 3, price = 47, old = 28},
	{id = 2287, name = "Hexdart Rune", level = 15, script = "light_magic_missile_rune.lua", mana = 120, soul = 1, count = 10, price = 8, old = 4},
	{id = 2265, name = "Mending Rune", level = 15, script = "intense_healing_rune.lua", mana = 120, soul = 2, count = 1, price = 95, old = 95},
	{id = 2266, name = "Purge Rune", level = 15, script = "cure_poison_rune.lua", mana = 200, soul = 1, count = 1, price = 120, old = 65},
	{id = 2290, name = "Beastbond Rune", level = 16, script = "convince_creature_rune.lua", mana = 200, soul = 3, count = 1, price = 140, old = 80},
	{id = 2261, name = "Dispel Rune", level = 17, script = "destroy_field_rune.lua", mana = 120, soul = 2, count = 3, price = 30, old = 15},
	{id = 2277, name = "Sparkmire Rune", level = 18, script = "energy_field_rune.lua", mana = 320, soul = 2, count = 3, price = 63, old = 38},
	{id = 2310, name = "Unmaking Rune", level = 21, script = "disintegrate_rune.lua", mana = 200, soul = 3, count = 3, price = 47, old = 26},
	{id = 2273, name = "Grand Mending Rune", level = 24, script = "ultimate_healing_rune.lua", mana = 400, soul = 3, count = 1, price = 240, old = 175},
	{id = 2292, name = "Stonefang Rune", level = 24, script = "stalagmite_rune.lua", mana = 350, soul = 2, count = 10, price = 20, old = 12},
	{id = 2286, name = "Blight Seed Rune", level = 25, script = "poison_bomb_rune.lua", mana = 520, soul = 2, count = 2, price = 160, old = 85},
	{id = 2311, name = "Greater Hexdart Rune", level = 25, script = "heavy_magic_missile_rune.lua", mana = 350, soul = 2, count = 10, price = 23, old = 12},
	{id = 2302, name = "Cinder Orb Rune", level = 27, script = "fireball_rune.lua", mana = 460, soul = 3, count = 5, price = 59, old = 30},
	{id = 2295, name = "Dawnshard Rune", level = 27, script = "holy_missile_rune.lua", mana = 300, soul = 3, count = 5, price = 42, old = 16},
	{id = 2305, name = "Ember Seed Rune", level = 27, script = "fire_bomb_rune.lua", mana = 600, soul = 4, count = 2, price = 195, old = 117},
	{id = 2316, name = "Gravecall Rune", level = 27, script = "animate_dead_rune.lua", mana = 600, soul = 5, count = 1, price = 395, old = 375},
	{id = 2291, name = "Mimic Rune", level = 27, script = "chameleon_rune.lua", mana = 600, soul = 2, count = 1, price = 365, old = 210},
	{id = 2308, name = "Soulpyre Rune", level = 27, script = "soulfire_rune.lua", mana = 420, soul = 3, count = 3, price = 92, old = 46},
	{id = 2269, name = "Thicket Rune", level = 27, script = "wild_growth_rune.lua", mana = 600, soul = 5, count = 2, price = 200, old = 160},
	{id = 2271, name = "Rimespike Rune", level = 28, script = "icicle_rune.lua", mana = 460, soul = 3, count = 5, price = 59, old = 30},
	{id = 2288, name = "Rockfall Rune", level = 28, script = "stone_shower_rune.lua", mana = 430, soul = 3, count = 4, price = 70, old = 37},
	{id = 2315, name = "Stormcall Rune", level = 28, script = "thunderstorm_rune.lua", mana = 430, soul = 3, count = 4, price = 70, old = 37},
	{id = 2289, name = "Blightwall Rune", level = 29, script = "poison_wall_rune.lua", mana = 640, soul = 3, count = 4, price = 99, old = 52},
	{id = 2274, name = "Frostfall Rune", level = 30, script = "avalanche_rune.lua", mana = 530, soul = 3, count = 4, price = 84, old = 45},
	{id = 2304, name = "Searing Orb Rune", level = 30, script = "great_fireball_rune.lua", mana = 530, soul = 3, count = 4, price = 84, old = 45},
	{id = 2313, name = "Concussion Rune", level = 31, script = "explosion_rune.lua", mana = 570, soul = 4, count = 6, price = 61, old = 31},
	{id = 2293, name = "Bastion Rune", level = 32, script = "magic_wall_rune.lua", mana = 750, soul = 5, count = 3, price = 160, old = 116},
	{id = 2303, name = "Pyrewall Rune", level = 33, script = "fire_wall_rune.lua", mana = 780, soul = 4, count = 4, price = 120, old = 61},
	{id = 2262, name = "Storm Seed Rune", level = 37, script = "energy_bomb_rune.lua", mana = 880, soul = 5, count = 2, price = 300, old = 162},
	{id = 2279, name = "Stormwall Rune", level = 41, script = "energy_wall_rune.lua", mana = 1000, soul = 5, count = 4, price = 170, old = 85},
	{id = 2268, name = "Reaper's Rune", level = 45, script = "sudden_death_rune.lua", mana = 985, soul = 5, count = 3, price = 220, old = 50},
	{id = 2278, name = "Shackle Rune", level = 54, script = "paralyze_rune.lua", mana = 1400, soul = 3, count = 1, price = 890, old = 700},
}

-- The recipes: the base crafting tables of this category (general crafting, skill 7, tables with action id 38823; the
-- crafting hall, z 4). One recipe per rune, appended after the stock recipes so their indexes stay. A recipe turns
-- `blanks` unscribed runes into blanks x the rune's conjure count, with herbs and ore pieces of the rune's level band
-- (the base server's own herbalist and mining gathering, not the Chaos professions, which feed no crafting) and gold:
-- recipe gold + the blank runes = goldShare of the vendor price of what it makes. The "Crafting bonus" roll (extra
-- pieces by skill) applies, as to every rune.
R.crafting = {
	category = "generalcrafting",
	blanks = 5,
	goldShare = 0.55,
	-- by the rune's level: the crafting skill the recipe needs, a herb (x2) and an ore piece (x1) of that band
	bands = {
		{maxLevel = 14, skill = 10, herb = 26729, ore = 26398},  -- delphinium, piece of bronze (beginner's tools)
		{maxLevel = 24, skill = 12, herb = 26732, ore = 26399},  -- bluebell, piece of silver (apprentice's tools)
		{maxLevel = 34, skill = 18, herb = 26726, ore = 26404},  -- scarlet flower, piece of sapphire (third tools)
		{maxLevel = 9999, skill = 25, herb = 26727, ore = 26401}, -- red lilly, piece of gold (expert's tools)
	},
	herbs = 2,
	ores = 1,
}

local function roundNice(x)
	if x < 100 then
		return math.floor(x + 0.5)
	elseif x < 1000 then
		return math.floor(x / 5 + 0.5) * 5
	end
	return math.floor(x / 10 + 0.5) * 10
end

function R.byId(id)
	if id == R.blankRune.id then
		return R.blankRune
	end
	for _, r in ipairs(R.runes) do
		if r.id == id then
			return r
		end
	end
	return nil
end

function R.price(id)
	local r = R.byId(id)
	return r and r.price or nil
end

function R.band(level)
	for _, b in ipairs(R.crafting.bands) do
		if level <= b.maxLevel then
			return b
		end
	end
	return R.crafting.bands[#R.crafting.bands]
end

-- the recipe of one rune, in the base crafting script's layout
function R.recipe(r)
	local c, b = R.crafting, R.band(r.level)
	local count = r.count * c.blanks
	local blankGold = c.blanks * R.blankRune.price
	local cost = math.max(0, roundNice(c.goldShare * r.price * count - blankGold))
	return {
		id = r.id, name = r.name, level = b.skill, cost = cost, count = count, storage = 0, storageText = "",
		materials = {{id = R.blankRune.id, count = c.blanks}, {id = b.herb, count = c.herbs}, {id = b.ore, count = c.ores}},
		chaosRune = true
	}
end

function R.recipes()
	local out = {}
	for _, r in ipairs(R.runes) do
		out[#out + 1] = R.recipe(r)
	end
	return out
end

-- appends the recipes to a category list (Crafting.generalcrafting); a list that has them already is left alone, so a
-- second load (a /reload of the scripts) adds nothing. Returns how many were added.
function R.addRecipes(list)
	if type(list) ~= "table" then
		return 0
	end
	for _, craft in ipairs(list) do
		if type(craft) == "table" and craft.chaosRune then
			return 0
		end
	end
	local n = 0
	for _, craft in ipairs(R.recipes()) do
		list[#list + 1] = craft
		n = n + 1
	end
	return n
end

-- gold one rune costs at the crafting table: the recipe gold and the blank runes it uses, per rune made (no bonus roll)
function R.craftGoldPerRune(r)
	local craft = R.recipe(r)
	return (craft.cost + R.crafting.blanks * R.blankRune.price) / craft.count
end

-- the rune conjure spell scripts that go (data/spells/scripts/conjuring/<name>)
function R.conjureScripts()
	local out = {R.blankRune.script}
	for _, r in ipairs(R.runes) do
		out[#out + 1] = r.script
	end
	return out
end

-- every spells.xml script whose spell goes: the rune conjures (conjuring/...) and R.otherConjures
function R.removedScripts()
	local out = {}
	for _, s in ipairs(R.conjureScripts()) do
		out[#out + 1] = "conjuring/" .. s
	end
	for _, c in ipairs(R.otherConjures) do
		out[#out + 1] = c.script
	end
	return out
end

-- consistency: a list of problems (empty when fine). The test and check_content read it.
function R.check()
	local errs = {}
	local function err(fmt, ...)
		errs[#errs + 1] = string.format(fmt, ...)
	end
	local seenId, seenScript = {}, {}
	for _, r in ipairs(R.runes) do
		if seenId[r.id] then err("rune %d twice", r.id) end
		if seenScript[r.script] then err("script %s twice", r.script) end
		seenId[r.id], seenScript[r.script] = true, true
		if r.price < r.old then err("%s: price %d below the old %d", r.name, r.price, r.old) end
		if r.price < 1 or r.count < 1 then err("%s: price or count below 1", r.name) end
		local per = R.craftGoldPerRune(r)
		if per >= r.price then err("%s: crafting %.2f gold a rune, not below the vendor's %d", r.name, per, r.price) end
	end
	local towns = {}
	for _, v in ipairs(R.vendors) do
		towns[v.town] = true
	end
	if not towns[R.hubTown] then err("no vendor in the hub town %d", R.hubTown) end
	for _, t in ipairs(R.startTowns) do
		if not towns[t] then err("no vendor in the start town %d", t) end
	end
	return errs
end

ChaosRuneSupply = R
return R
