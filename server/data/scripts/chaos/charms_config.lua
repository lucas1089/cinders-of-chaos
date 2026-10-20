-- Charms (charms.lua, charms_core.lua): every number of the system is here. server/README.md "Charms".
-- Plain table, loaded with  ChaosCharmsConfig = dofile("data/scripts/chaos/charms_config.lua")
-- server/tools/install_charms.py reads `items` (id, sourceId, name, plural, article, weight, description).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- A charm is an item with 1-2 small modifiers from the charm pool below. It is placed into the character's charm grid
-- (a window of its own: the 10.98 client has no free equipment slot). Placed charms add their numbers to the item
-- modifier totals (item_mods.lua, under the gear caps) and to the charm-only effects (damage to a monster family, one
-- element's resistance, orb find, out-of-combat speed, reputation, rift time). Every key has a charm cap (the most all
-- placed charms give together) and the best roll of the biggest charm stays below the best tier of one gear slot
-- (`gearRef`, checked by charms_core.lua validate and tests/charms_test.lua).

local C = {}

C.opcode = 198 -- ChaosOpcodes.charms (server/README.md "Opcode collision check")
C.table = "chaos_charms"
-- player storages 7100470 - 7100479 (chaos_constants.lua Chaos.storage.charms): +0 the serial of the last place / take
-- (the crash marker, saved with the items), +1 the Last Ember signature's cooldown end (os.time)
C.storage = {seq = 7100470, emberUntil = 7100471}

-- ------------------------------------------------------------------ the grid
-- cols x rows; cells are opened by `unlocks` in order (x, y from 1). A cell that is not open cannot take a charm; a
-- charm on a cell that closed again (the character lost a level) stays placed but gives nothing until it opens again.
C.grid = {cols = 5, rows = 4}
C.unlocks = {
	{key = "base", text = "Open from the start", cells = {{1, 1}, {2, 1}, {3, 1}, {1, 2}, {2, 2}, {3, 2}}},
	{key = "l200", level = 200, text = "Reach level 200", cells = {{4, 1}, {5, 1}, {4, 2}, {5, 2}}},
	{key = "l400", level = 400, text = "Reach level 400", cells = {{1, 3}, {2, 3}, {3, 3}}},
	{key = "l600", level = 600, text = "Reach level 600", cells = {{4, 3}, {5, 3}}},
	{key = "l800", level = 800, text = "Reach level 800", cells = {{1, 4}, {2, 4}, {3, 4}}},
	{key = "edge", achievement = "rift_t10", text = "Achievement \"Edge of Ruin\" (seal a tier 10 rift)",
		cells = {{4, 4}, {5, 4}}}
}

-- ------------------------------------------------------------------ the items
-- shape: w x h cells. Server ids 32301..32309 are new items.otb nodes (install_charms.py): copies of the stock node
-- `sourceId` (its client look; no client change). Charms are not stackable; the shard is.
C.shapes = {
	small = {w = 1, h = 1, name = "Small Charm", mult = 1.0},
	tall = {w = 1, h = 2, name = "Tall Charm", mult = 1.7},
	wide = {w = 2, h = 1, name = "Wide Charm", mult = 1.7},
	grand = {w = 2, h = 2, name = "Grand Charm", mult = 3.0}
}
C.items = {
	{id = 32301, key = "small", shape = "small", sourceId = 10137, article = "a", name = "small charm", plural = "small charms",
		weight = 50, description = "A charm for your charm grid (Character > Charms): one cell."},
	{id = 32302, key = "tall", shape = "tall", sourceId = 2122, article = "a", name = "tall charm", plural = "tall charms",
		weight = 80, description = "A charm for your charm grid (Character > Charms): one cell wide, two tall."},
	{id = 32303, key = "wide", shape = "wide", sourceId = 10141, article = "a", name = "wide charm", plural = "wide charms",
		weight = 80, description = "A charm for your charm grid (Character > Charms): two cells wide, one tall."},
	{id = 32304, key = "grand", shape = "grand", sourceId = 5799, article = "a", name = "grand charm", plural = "grand charms",
		weight = 150, description = "A charm for your charm grid (Character > Charms): two by two cells."},
	{id = 32305, key = "gravewarden", shape = "tall", unique = true, sourceId = 7289, article = "the", name = "Gravewarden's Seal",
		plural = "Gravewarden's Seals", weight = 80, description = "A unique charm (Character > Charms)."},
	{id = 32306, key = "compass", shape = "wide", unique = true, sourceId = 10138, article = "the", name = "Wanderer's Compass",
		plural = "Wanderer's Compasses", weight = 80, description = "A unique charm (Character > Charms)."},
	{id = 32307, key = "hoard", shape = "grand", unique = true, sourceId = 8974, article = "the", name = "Eye of the Hoard",
		plural = "Eyes of the Hoard", weight = 150, description = "A unique charm (Character > Charms)."},
	{id = 32308, key = "tally", shape = "small", unique = true, sourceId = 10140, article = "the", name = "Ashen Tally",
		plural = "Ashen Tallies", weight = 50, description = "A unique charm (Character > Charms)."},
	{id = 32309, key = "shard", stackable = true, sourceId = 24849, article = "a", name = "charm shard", plural = "charm shards",
		weight = 5, description = "Left when a charm is salvaged (Character > Charms). Reforge a charm's values with shards."}
}

-- rarity of a rolled charm: name, how many modifiers, the share of the roll range it reaches, its roll weight
C.rarities = {
	{name = "Faint", mods = 1, scale = 0.7, weight = 60, color = "#b8b0a0"},
	{name = "Glowing", mods = 1, scale = 0.85, weight = 30, color = "#6fa8ff"},
	{name = "Radiant", mods = 2, scale = 1.0, weight = 10, color = "#f2c94c"}
}
C.uniqueRarity = {name = "Unique", color = "#e0782a"}

-- item level 1..maxLevel: the value reaches (minScale + (1 - minScale) x level / maxLevel) of the roll
C.itemLevel = {max = 100, minScale = 0.5}

-- shape of a rolled charm by weight
C.shapeWeights = {{"small", 50}, {"tall", 20}, {"wide", 20}, {"grand", 10}}

-- ------------------------------------------------------------------ the pool
-- key: the effect key; gear = true: a key of the item modifier catalogue (chaos_item_mods.lua), summed into the gear
-- totals under the gear cap as well. range: the roll of a 1x1 charm at full scale (rarity Radiant, item level max);
-- a charm rolls lo..hi x its shape's mult x the rarity scale x the item level scale, rounded, at least 1.
-- cap: the most every placed charm gives together. gearRef: the best roll of one gear slot (T8 high) of the matching
-- gear modifier (raised on 2026-10-18, owner item 78); the best charm roll must stay below it. weight: roll weight.
local function family(key, name)
	return {key = "dmg_" .. key, family = key, label = "Damage to " .. name, fmt = "pct", range = {1, 3}, cap = 15,
		gearRef = 22, weight = 4, group = "family"}
end
local function element(key, name, combat)
	return {key = "res_" .. key, element = combat, label = name .. " Resistance", fmt = "pct", range = {1, 2}, cap = 8,
		gearRef = 14, weight = 3, group = "element"}
end
C.pool = {
	family("dragons", "Dragons"), family("demons", "Demons"), family("undead", "Undead"), family("humans", "Humans"),
	family("humanoids", "Humanoids"), family("beasts", "Beasts"), family("elementals", "Elementals"),
	family("vermin", "Insects and Arachnids"),
	element("fire", "Fire", "COMBAT_FIREDAMAGE"), element("ice", "Ice", "COMBAT_ICEDAMAGE"),
	element("energy", "Energy", "COMBAT_ENERGYDAMAGE"), element("earth", "Earth", "COMBAT_EARTHDAMAGE"),
	element("death", "Death", "COMBAT_DEATHDAMAGE"), element("holy", "Holy", "COMBAT_HOLYDAMAGE"),
	{key = "lifeonkill", gear = true, label = "Life on Kill", fmt = "flat", range = {4, 10}, cap = 60, gearRef = 260, weight = 8},
	{key = "goldfind", gear = true, label = "Gold Find", fmt = "pct", range = {1, 2}, cap = 10, gearRef = 34, weight = 8},
	{key = "orbfind", label = "Orb Find", fmt = "pct", range = {1, 3}, cap = 20, gearRef = 12, weight = 6},
	{key = "oocspeed", label = "Movement Speed out of Combat", fmt = "pct", range = {1, 2}, cap = 8, gearRef = 11, weight = 6},
	{key = "reputation", label = "Reputation", fmt = "pct", range = {1, 3}, cap = 15, weight = 5},
	{key = "rifttime", label = "Rift Time", text = "Rift Time +%d s", range = {5, 12}, cap = 90, weight = 5}
}
-- keys a unique charm or its signature adds that are no roll of the pool (gear catalogue keys, under the gear caps)
C.extraKeys = {
	goblinchance = {gear = true, label = "Treasure Goblin Chance", fmt = "pct", cap = 15, gearRef = 90},
	manaonkill = {gear = true, label = "Mana on Kill", fmt = "flat", cap = 30, gearRef = 170}
}

-- ------------------------------------------------------------------ uniques
-- fixed modifiers (no roll) and a small signature effect; the shape is the item's
C.uniques = {
	gravewarden = {mods = {{"dmg_undead", 6}, {"res_death", 4}}, signature = "lastember",
		signatureText = "Last Ember: once every 10 minutes a hit that would kill you leaves you at 1 health."},
	compass = {mods = {{"oocspeed", 5}, {"rifttime", 20}}, signature = "wayfarer",
		signatureText = "Wayfarer's Rest: out of combat you recover 1% of your health and mana every 2 seconds."},
	hoard = {mods = {{"orbfind", 8}, {"goldfind", 5}}, signature = "hoardsense", extra = {goblinchance = 15},
		signatureText = "Hoard Sense: +15% Treasure Goblin Chance."},
	tally = {mods = {{"lifeonkill", 12}}, signature = "harvester",
		signatureText = "Harvester: the Life on Kill of your charms also restores half as much mana."}
}
C.signature = {
	lastember = {cooldown = 600},
	wayfarer = {everyMs = 2000, healthPct = 1, manaPct = 1}
}

-- ------------------------------------------------------------------ drops
-- chance in percent per event and player; the item level of the charm. Only online characters get charms.
--   rift      a sealed rift of tier minTier+ (each finisher): base + perTier x (tier - minTier), at most max
--   bounty    a completed bounty contract
--   invasion  a rewarded invasion defender / liberator (rank 1: top)
--   dungeon   a cleared dungeon (each member): base + perDifficulty x difficulty
--   descent   an Ember Descent room cleared (each player in the run); the boss room: boss
C.drops = {
	rift = {minTier = 6, base = 6, perTier = 1, max = 15, ilvlBase = 40, ilvlPerTier = 4},
	bounty = {chance = 4, ilvlPerLevel = 0.1, ilvlMin = 30, ilvlMax = 80},
	invasion = {chance = 10, top = 25, ilvlPerLevel = 0.1, ilvlMin = 40, ilvlMax = 90},
	dungeon = {base = 8, perDifficulty = 2, ilvlBase = 50, ilvlPerDifficulty = 5},
	descent = {room = 3, boss = 15, ilvlBase = 40, ilvlPerDepth = 3},
	uniqueChance = 2 -- percent of the charm drops that are a unique instead (any of C.uniques, equal odds)
}

-- ------------------------------------------------------------------ shards
-- salvage: shards for a charm by shape (a unique gives `unique`); reforge: shards to roll a charm's values again
-- (same modifiers, same rarity and item level; uniques cannot be reforged)
C.salvage = {small = 2, tall = 4, wide = 4, grand = 8, unique = 15, radiantBonus = 2}
C.reforge = {small = 6, tall = 12, wide = 12, grand = 24}

-- ------------------------------------------------------------------ rules
C.minLevel = 8
C.maxPlaced = 20
-- placing, moving and taking out: anywhere but in combat (no fight condition, not PZ-locked)
C.outOfCombat = true
C.rate = {open = 400, place = 300, move = 250, take = 300, salvage = 400, reforge = 600}
C.thinkMs = 1000 -- out-of-combat speed and the Wayfarer's Rest

return C
