-- Professions (professions.lua, professions_core.lua): every number of the gathering professions. server/README.md
-- "Professions". Plain table, loaded with  ChaosProfessionsConfig = dofile("data/scripts/chaos/professions_config.lua")
-- server/tools/install_professions.py reads `materials` and `nodes` (id, sourceId, name, plural, article, weight,
-- description), `broker.npc` and `hooks`. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- The owner's rule: professions gather materials to SELL TO NPCs and to earn an EXPERIENCE BONUS. They make no gear
-- and no orbs. O395 (owner 2026-11-03): they also FEED THE BASE CRAFTING TABLES (mining, herbalist, armorsmith books):
-- by-products (a base crafting material now and then, `byproducts`) and refining recipes (`refine`, added to the
-- base books by data/lib/chaos_profession_recipes.lua). Perks at profession levels 25 / 50 / 75 (`perks`), nodes in
-- the hunts of the teleport hall by level band (`huntNodes`). Gathering still earns less than hunting (`balance`).
--
-- Four gathering professions, each with its own level 1..100 (own curve, below) per character:
--   delving      ore veins (node items placed in hunting areas)     tool: a pick (stock 2553)
--   wortcunning  herb patches (node items placed in hunting areas)  tool: a sickle (stock 2405)
--   flaying      fresh corpses of beasts and reptiles               tool: an obsidian knife (stock 5908)
--   angling      the base server's own fishing, extended            tool: a fishing rod (stock 2580 / 10223)
-- They are separate from the base server's engine skills of the same trades (the skills window's Mining, Herbalist,
-- Fishing ...), which stay as they are: items and passive nodes raise those, never a profession level, so the
-- experience bonus cannot be pumped with gear.

local C = {}

C.enabled = true
C.opcode = 195 -- ChaosOpcodes.professions (server/README.md "Opcode collision check")
C.tables = {levels = "chaos_professions", sales = "chaos_professions_sales"}
C.staffGroup = 4 -- /professions for this group id and above
C.requestMs = 300 -- the client may send this often at most
-- O368: the window, gathering, flaying and the Angling roll need this character level (stock fishing stays open). The
-- first levels are for hunting; the top menu shows Professions from here on (unlocks_config.lua key "professions")
C.minLevel = 20

-- ------------------------------------------------------------------ professions
-- order = the order everywhere (window, achievements, codex). tools: item ids that work; channelMs: the gather time
-- (moving, attacking or taking damage interrupts it). Angling has no channel: the stock fishing cast is the action.
C.professions = {
	{key = "delving", name = "Delving", verb = "Delving", noun = "ore vein", tools = {2553}, toolName = "a pick",
		channelMs = 3000, fx = "CONST_ME_BLOCKHIT", desc = "Break ore from the veins that run through the hunting grounds."},
	{key = "wortcunning", name = "Wortcunning", verb = "Gathering herbs", noun = "herb patch", tools = {2405},
		toolName = "a sickle", channelMs = 3000, fx = "CONST_ME_SMALLPLANTS",
		desc = "Cut the bitter herbs that grow where blood was spilled."},
	{key = "flaying", name = "Flaying", verb = "Flaying", noun = "corpse", tools = {5908}, toolName = "an obsidian knife",
		channelMs = 2500, fx = "CONST_ME_DRAWBLOOD", desc = "Take hides and scales from the beasts you slay."},
	{key = "angling", name = "Angling", verb = "Angling", noun = "water", tools = {2580, 10223}, toolName = "a fishing rod",
		channelMs = 0, fx = "CONST_ME_LOSEENERGY", desc = "Fish the dark waters: now and then a catch is worth selling."}
}

-- ------------------------------------------------------------------ levels
-- experience for level L -> L + 1 (L = 1..maxLevel - 1): floor(base + linear x L + square x L^2)
-- 190,327 in total to 100: about 4,000 gathers of the right tier (35 to 45 hours of gathering per profession).
C.maxLevel = 100
C.curve = {base = 30, linear = 8, square = 0.45}
-- a gather of a material tier below the highest one the character may gather gives less: 1 tier below x0.6, 2+ x0.25
C.greyXp = {[0] = 1.0, [1] = 0.6, [2] = 0.25}

-- ------------------------------------------------------------------ tiers
-- A gather yields a material of tier min(the place's tier, the profession's tier, the character's tier):
--   profLevel   the profession level that opens the tier
--   charLevel   the character level that opens the tier (and the hunting level of the places of that tier)
--   price       the Material Broker's base price per unit, gold
--   xp          profession experience per gather
--   name        tier word in the window
C.tiers = {
	{profLevel = 1, charLevel = 8, price = 20, xp = 10, name = "Common", color = "#b8b0a0"},
	{profLevel = 20, charLevel = 40, price = 80, xp = 18, name = "Fine", color = "#7ec46a"},
	{profLevel = 40, charLevel = 100, price = 350, xp = 30, name = "Rare", color = "#6fa8ff"},
	{profLevel = 60, charLevel = 250, price = 800, xp = 45, name = "Grim", color = "#c07ae0"},
	{profLevel = 80, charLevel = 500, price = 4000, xp = 65, name = "Infernal", color = "#ff8a3d"}
}

-- yield per gather: 1, +1 with chance min(extraMax, (profession level - the tier's profLevel) / extraPerLevel),
-- +1 more with chance lucky (both can happen)
C.yield = {extraPerLevel = 100, extraMax = 0.6, lucky = 0.03}

-- character experience per gather: this share of the experience the character needs for its next level (at least 1);
-- added without stages or bonuses (Player:addExperience, no monster source)
C.charXpShare = 0.001

-- ------------------------------------------------------------------ the experience bonus (passive)
-- +perLevel % monster experience per profession level above 1, all four together (4 x 99 = 396 levels -> +10.02%, so
-- the cap of +10% is reached with every profession at 100; a new character has +0%).
-- EventCallback onGainExperience at index 6 (after the world buff, before the dungeon / rift caps), monster kills only.
C.bonus = {perLevel = 0.0253, cap = 10.0, index = 6}

-- ------------------------------------------------------------------ materials
-- server ids 32351..32370: new items.otb nodes (install_professions.py), copies of the stock node `sourceId` (its look;
-- no client change), all stackable (their stock nodes are). Tiers 1..5 per profession in order.
local function m(id, prof, tier, sourceId, name, plural, desc)
	return {id = id, key = name:gsub("[^%w]+", "_"):lower(), prof = prof, tier = tier, sourceId = sourceId, article = "a",
		name = name, plural = plural, weight = 50, description = desc .. " Sell it to a Material Broker."}
end
C.materials = {
	m(32351, "delving", 1, 5880, "ashstone ore", "ashstone ores", "Grey ore with a smell of old fires."),
	m(32352, "delving", 2, 5888, "bloodiron ore", "bloodiron ores", "Ore veined with rust as red as blood."),
	m(32353, "delving", 3, 18414, "duskglass shard", "duskglass shards", "A violet shard that drinks the light."),
	m(32354, "delving", 4, 5887, "wraithsilver ore", "wraithsilver ores", "Pale silver, cold to the touch."),
	m(32355, "delving", 5, 18424, "emberheart crystal", "emberheart crystals", "A crystal that still glows from the depths."),
	m(32356, "wortcunning", 1, 4838, "gravemoss", "gravemosses", "Moss from the shade of old graves."),
	m(32357, "wortcunning", 2, 2799, "bitterroot", "bitterroots", "A gnarled root, bitter enough to wake the dying."),
	m(32358, "wortcunning", 3, 2804, "nightshade bloom", "nightshade blooms", "A dark bloom that opens only at night."),
	m(32359, "wortcunning", 4, 2792, "wraithcap", "wraithcaps", "A grey mushroom that grows on haunted ground."),
	m(32360, "wortcunning", 5, 2798, "emberbloom", "emberblooms", "A red herb that grows in the ash of hellfire."),
	m(32361, "flaying", 1, 5883, "matted pelt", "matted pelts", "A coarse pelt, still smelling of the wild."),
	m(32362, "flaying", 2, 5878, "tough hide", "tough hides", "A thick hide, scarred by many fights."),
	m(32363, "flaying", 3, 5881, "scaled hide", "scaled hides", "Hard scales on a supple skin."),
	m(32364, "flaying", 4, 5948, "dire pelt", "dire pelts", "The dark pelt of a monstrous beast."),
	m(32365, "flaying", 5, 5882, "wyrmscale", "wyrmscales", "A scale as hard as forged steel."),
	m(32366, "angling", 1, 2667, "mudfin", "mudfins", "A grey fish from muddy water."),
	m(32367, "angling", 2, 7159, "gloomcarp", "gloomcarps", "A carp from the shadowed pools."),
	m(32368, "angling", 3, 7158, "bloodfin trout", "bloodfin trouts", "A trout with fins the colour of blood."),
	m(32369, "angling", 4, 2669, "dusk pike", "dusk pikes", "A pike that hunts at nightfall."),
	m(32370, "angling", 5, 2144, "drowned pearl", "drowned pearls", "A black pearl from the deepest waters.")
}

-- node items: server ids 32371..32380, copies of the base server's vein and herb nodes (their looks; not pickupable, not
-- moveable, as their stock nodes). Placed at startup on the tiles of the areas below.
local function node(id, prof, tier, sourceId, name, desc)
	return {id = id, prof = prof, tier = tier, sourceId = sourceId, article = "a", name = name, plural = name .. "s",
		weight = 0, description = desc}
end
C.nodes = {
	node(32371, "delving", 1, 26405, "ashstone vein", "Use a pick on it (Delving)."),
	node(32372, "delving", 2, 26406, "bloodiron vein", "Use a pick on it (Delving 20)."),
	node(32373, "delving", 3, 26410, "duskglass vein", "Use a pick on it (Delving 40)."),
	node(32374, "delving", 4, 26407, "wraithsilver vein", "Use a pick on it (Delving 60)."),
	node(32375, "delving", 5, 26408, "emberheart vein", "Use a pick on it (Delving 80)."),
	node(32376, "wortcunning", 1, 26717, "gravemoss patch", "Use a sickle on it (Wortcunning)."),
	node(32377, "wortcunning", 2, 26718, "bitterroot patch", "Use a sickle on it (Wortcunning 20)."),
	node(32378, "wortcunning", 3, 26719, "nightshade patch", "Use a sickle on it (Wortcunning 40)."),
	node(32379, "wortcunning", 4, 26720, "wraithcap patch", "Use a sickle on it (Wortcunning 60)."),
	node(32380, "wortcunning", 5, 26721, "emberbloom patch", "Use a sickle on it (Wortcunning 80)."),
}

-- ------------------------------------------------------------------ nodes and places
-- Per-player node cooldown (chosen over shared depletion): a node never disappears; after a character gathers it, it is
-- ready again FOR THAT CHARACTER after respawnMin minutes (kept in memory; a restart makes every node ready). Nobody
-- can camp or steal a node, players hunting the same ground do not compete, and the node's look never needs to change.
C.respawnMin = 6
C.nodeSpacing = 3 -- nodes of one area stay at least this many tiles apart

-- Areas: existing hunting grounds of the real map (centres from bestiary_spawns.lua, the busiest spawn squares of the
-- named monsters), box = centre +- r on floor z. At startup `nodes` node items per profession are put on suitable
-- tiles (walkable ground with nothing on it, no protection zone, house, teleport or stairs), chosen by a seed from the
-- area key: the same tiles after every restart. `pos` lists add fixed spots (used before the random picks).
-- tier: the place's tier (C.tiers); fishing: true = water in the box fishes at this tier (Angling).
C.areas = {
	{key = "gutworm_burrows", name = "Gutworm Burrows", tier = 1, center = {x = 32224, y = 32746, z = 8}, r = 20,
		nodes = {delving = 10}, monsters = "gutworms"},
	{key = "wolf_meadows", name = "Wolf Meadows", tier = 1, center = {x = 32580, y = 32036, z = 7}, r = 22,
		nodes = {wortcunning = 10}, fishing = true, monsters = "wolves, bears"},
	{key = "cyclops_crags", name = "Cyclops Crags", tier = 2, center = {x = 32448, y = 32073, z = 8}, r = 20,
		nodes = {delving = 10}, monsters = "cyclopes"},
	{key = "lions_rest", name = "Lion's Rest", tier = 2, center = {x = 32661, y = 32103, z = 7}, r = 20,
		nodes = {wortcunning = 10}, fishing = true, monsters = "lions"},
	{key = "dragon_scar", name = "Dragon Scar", tier = 3, center = {x = 33215, y = 31297, z = 7}, r = 24,
		nodes = {delving = 10, wortcunning = 10}, fishing = true, monsters = "dragons"},
	{key = "behemoth_depths", name = "Behemoth Depths", tier = 4, center = {x = 33521, y = 31643, z = 13}, r = 22,
		nodes = {delving = 12}, monsters = "behemoths"},
	{key = "hydra_fens", name = "Hydra Fens", tier = 4, center = {x = 33700, y = 31657, z = 14}, r = 20,
		nodes = {wortcunning = 12}, fishing = true, monsters = "hydras"},
	{key = "infernal_rift", name = "Infernal Rift", tier = 5, center = {x = 33841, y = 31312, z = 12}, r = 22,
		nodes = {delving = 10, wortcunning = 10}, monsters = "infernal demons"}
}

-- ------------------------------------------------------------------ flaying
-- A monster of these bestiary families (bestiary_config.lua categories) leaves a corpse that can be flayed once
-- (the corpse owner and the owner's party, as the loot). Tier by the monster's hunting level (ChaosBestiaryCore
-- .estimateLevel: the tier's charLevel); chance: a hide at all, per flay.
C.flaying = {families = {beasts = true, reptiles = true}, chance = 0.4, exclude = {rabbit = true}, maxAgeSec = 300}

-- ------------------------------------------------------------------ angling
-- Every stock fishing cast on fishable water (data/actions/scripts/tools/fishing.lua, hooked by install_professions.py)
-- rolls once, at most every rollMs per character: chance of a material of the ground's tier (an area with
-- fishing = true whose box holds the water tile; elsewhere `defaultTier`). The stock catch (fish, the Fishing skill,
-- worms) is not changed.
C.angling = {rollMs = 3000, chance = 0.1, defaultTier = 1}

-- ------------------------------------------------------------------ selling
-- The Material Broker (one per town, next to the temple; data/npc/Material Broker.xml) opens the Professions window on
-- its Broker tab; the sale itself is checked here (a broker within `range` tiles, the items in the backpack).
-- Per material and character and day (server local day): the first fullPerDay units at the full price, then the
-- price x lateMult up to capPerDay, then the broker refuses more of it that day.
C.broker = {
	npc = "Material Broker", range = 4, towns = "all", -- "all" = every town of the map; or a list of town ids / names
	offsets = {{-3, -4}, {3, -4}, {-4, -1}, {4, -1}, {-3, 4}, {3, 4}, {-6, 0}, {6, 0}, {0, -6}, {0, 6}, {-2, -2}, {2, -2},
		{-2, 2}, {2, 2}},
	fullPerDay = 100, capPerDay = 200, lateMult = 0.5,
	-- the stock tools, sold in the broker's trade window ("trade"): {id, price}
	tools = {{id = 2553, price = 50}, {id = 2405, price = 20}, {id = 5908, price = 600}, {id = 2580, price = 150}}
}

-- weekly demand: per profession and week (the leaderboards' week, bounty_config.lua rollHour) the five materials get
-- these multipliers in an order drawn from the week's seed (the same for every character and after a restart)
C.demand = {slots = {1.5, 1.25, 1.0, 1.0, 0.75}, seed = 7919}
-- days and weeks start at this hour (server local time), as the bounty board and the leaderboards (rollHour 6)
C.rollHour = 6

-- ------------------------------------------------------------------ balance (checked by tests/professions_test.lua)
-- Hunting gold per hour at a character level (server/README.md "Respec": tools/respec_income.py from level 100; levels 8
-- and 40 from the same model on Gutworm / Troll / Orc and Cyclops / Dwarf Guard / Minotaur Guard hunts). Linear between.
-- The best gold per hour of a profession at its tier (profession 100, the best demand week, no daily cap) must stay
-- below maxShare of the hunting income at the tier's charLevel. Model: gathers per hour = min(3600 / (channel + walkSec),
-- nodes of the tier x 60 / respawnMin) for the node professions, 3600 / (channel + killSec) x flaying chance for
-- flaying, 3600 / rollMs x angling chance for angling; x the best average yield; x price x the best demand.
C.balance = {
	maxShare = 0.4, walkSec = 12, killSec = 10,
	hunting = {{8, 19000}, {40, 83000}, {100, 358839}, {300, 881866}, {500, 5548330}, {1000, 9519711}}
}

-- ------------------------------------------------------------------ O395: feeding the base crafting
-- By-products: a gather that yields a material has `chance[prof]` (+ the perks) of one base crafting material more,
-- of the gather's tier (`ids[prof][tier]`, one picked at random). The base server's own gathering materials (ore pieces
-- of the mining book, herbs of the herbalist book); they have no NPC price of their own, the item price table pays
-- `price` for each (data/lib/chaos_item_prices_data.lua, checked by the test), which the gold model counts.
-- Flaying has none (its hides refine at the armorsmith instead).
C.byproducts = {
	price = 120,
	chance = {delving = 0.10, wortcunning = 0.10, angling = 0.04},
	ids = {
		delving = {{26398}, {26399}, {26404, 26401}, {26400}, {26402, 26403}},
		wortcunning = {{26729, 26731}, {26732, 26730}, {26726, 26725}, {26727, 26724}, {26723, 26728}},
		-- water plants caught on the line
		angling = {{26731}, {26730}, {26725}, {26724}, {26728}}
	}
}

-- Refining recipes, added to the base crafting books (data/lib/chaos_profession_recipes.lua; the loader line in each
-- book: tools/install_professions.py). `ins` units of the profession material of `tier` (+ `cost` gold) make `count`
-- of `out`, at the book's crafting skill `level`. Rule (tests/professions_test.lua against the item price table): the
-- inputs at the broker's base price plus the gold are worth at least the product, so no recipe makes gold.
local function refine(prof, tier, book, ins, out, count, level, cost)
	return {prof = prof, tier = tier, book = book, ins = ins, out = out, count = count, level = level, cost = cost}
end
C.refine = {
	refine("delving", 1, "mining", 2, 26398, 1, 10, 100),
	refine("delving", 2, "mining", 1, 26399, 1, 10, 50),
	refine("delving", 3, "mining", 1, 26404, 2, 15, 50),
	refine("delving", 4, "mining", 1, 26400, 3, 20, 50),
	refine("delving", 5, "mining", 1, 5880, 2, 25, 50),
	refine("wortcunning", 1, "herbalist", 2, 26729, 1, 10, 100),
	refine("wortcunning", 2, "herbalist", 1, 26732, 1, 10, 50),
	refine("wortcunning", 3, "herbalist", 1, 26726, 2, 15, 50),
	refine("wortcunning", 4, "herbalist", 1, 26727, 3, 20, 50),
	refine("wortcunning", 5, "herbalist", 1, 26724, 4, 25, 50),
	refine("flaying", 1, "armorsmith", 2, 12435, 1, 10, 50),
	refine("flaying", 2, "armorsmith", 1, 5920, 1, 10, 50),
	refine("flaying", 3, "armorsmith", 1, 5920, 2, 15, 50),
	refine("flaying", 4, "armorsmith", 1, 5948, 3, 20, 50),
	refine("flaying", 5, "armorsmith", 1, 5882, 4, 25, 50)
}

-- Perks: a profession at `level` gets these, for good (the window lists them). Kinds:
--   channel    the gather channel x value (Delving, Wortcunning, Flaying)
--   byproduct  + value to the by-product chance
--   lucky      + value to the chance of one more unit
--   flay       + value to the chance a flay gives a hide
-- The gold model counts every perk at profession 100.
local function perk(level, kind, value, name, pt)
	return {level = level, kind = kind, value = value, name = name, pt = pt}
end
C.perks = {
	delving = {perk(25, "channel", 0.8, "Steady Swing", "Golpe Firme"), perk(50, "byproduct", 0.05, "Keen Eye", "Olho Atento"),
		perk(75, "lucky", 0.02, "Rich Seam", "Veio Rico")},
	wortcunning = {perk(25, "channel", 0.8, "Quick Blade", "Lâmina Ágil"), perk(50, "byproduct", 0.05, "Keen Eye", "Olho Atento"),
		perk(75, "lucky", 0.02, "Deep Roots", "Raízes Fundas")},
	flaying = {perk(25, "channel", 0.8, "Clean Cuts", "Cortes Limpos"), perk(50, "flay", 0.05, "Sure Hand", "Mão Segura"),
		perk(75, "lucky", 0.02, "Whole Hide", "Couro Inteiro")},
	angling = {perk(25, "byproduct", 0.02, "Weedy Hook", "Anzol de Algas"), perk(50, "lucky", 0.02, "Heavy Catch", "Pesca Farta"),
		perk(75, "byproduct", 0.01, "Old Nets", "Redes Velhas")}
}

-- Nodes in the hunts (O395): at startup every hunt of the teleport hall (hunt_teleports.lua: the placed content hunts
-- and the base server's hunts of tools/hall_hunts.csv) gets `nodes` per profession around its arrival (box +- r, the
-- arrival's floor), at the tier of its level band (the band's first level, `C.tiers` charLevel), with fishing at that
-- tier. A hunt whose arrival lies within `gap` tiles of a fixed area (`C.areas`, same floor) is left alone.
C.huntNodes = {enabled = true, r = 12, gap = 30, nodes = {delving = 4, wortcunning = 4}, fishing = true}

-- leaderboard (leaderboard_config.lua board "professions"): materials gathered this week, sent every minute and at logout
C.board = "professions"

return C
