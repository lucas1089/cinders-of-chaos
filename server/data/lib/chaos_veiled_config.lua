-- Veiled modifiers (data/lib/chaos_veiled.lua reads it; server/README.md "Veiled modifiers"). Every number of the system:
-- which drops roll a veiled slot and how often, where the Orb of Unveiling drops, the veiled tiers and their item level
-- gates, and the veiled pool. Plain table, loaded with  ChaosVeiledConfig = dofile("data/lib/chaos_veiled_config.lua").
-- Lua 5.1 / LuaJIT and 5.3. Chances are per 10000.
--
-- The orb item itself (id 32257, its sprite and items.xml text) is a row of data/lib/chaos_orbs_config.lua `items`, so
-- server/tools/install_orbs.py installs it with the other orbs.

return {
	orbKey = "unveiling", -- the orb's key in chaos_orbs_config.lua and ChaosCrafting.orbByKey

	-- custom attributes on the item
	attrs = {
		state = "chaos_veil", -- 1 = veiled (not revealed yet), 2 = unveiled
		offer = "chaos_veil_offer", -- the three offered choices, "key:tier:value;key:tier:value;key:tier:value" (fixed once rolled)
		key = "chaos_veil_key", -- the chosen modifier (pool key), after the unveiling
		tier = "chaos_veil_tier", -- its veiled tier 1..4
		value = "chaos_veil_val" -- its value
	},

	-- which items may roll a veiled slot: gear with a rarity of at least minRarity (Rare); from highRarity (Legendary) on
	-- the `high` chance of the source counts. Uniques and set pieces never do.
	minRarity = 3,
	highRarity = 5,

	-- the sources and their chance per item (per 10000) for a veiled slot; the best source of a drop counts
	--   rift      a kill inside a rift of at least minTier, or that rift's chest
	--   omen      an Omen guardian arena (rift.lua run.omen)
	--   raid      the raid (raid.lua: kills inside and the boss rewards)
	--   descent   the Descent from depth minDepth on
	--   ascended  the Ascended pinnacle fights (uber.lua: kills inside and the spoils)
	sources = {
		rift = {minTier = 10, chance = 500, high = 1000},
		omen = {chance = 1000, high = 1800},
		raid = {chance = 1500, high = 2500},
		descent = {minDepth = 8, chance = 600, high = 1200},
		ascended = {chance = 1200, high = 2000}
	},
	-- the order a drop's source is picked in when more than one applies (the first that applies)
	sourceOrder = {"raid", "ascended", "omen", "descent", "rift"},

	-- the Orb of Unveiling from kills in the same content: perKill (per 10000) of the source x the monster tier's factor
	orbDrop = {
		perKill = {rift = 5, omen = 12, raid = 25, descent = 8, ascended = 30},
		tierMult = {normal = 1, magic = 2, rare = 4, legendary = 8, boss = 40}
	},

	-- the raid vendor's weekly bundle (raid_config.lua vendor pool "v_unveiling")
	vendorBundle = {count = 2, price = 90, weekly = 1},

	-- veiled tiers V1 .. V4: the item level each needs, the roll weight of each; an offer's tier is rolled among the best
	-- `window` tiers the item level allows
	tiers = {levels = {1, 90, 115, 135}, weights = {40, 30, 20, 10}, window = 3},

	offers = 3, -- choices offered by an unveiling (fewer when the item's kind allows fewer)

	-- caps of the veiled pool's own effects (the hook modifiers): the most a character gets from all its items together.
	-- The other veiled modifiers add to the catalogue's modifiers (chaos_item_mods.lua) under the catalogue's caps.
	hookCaps = {veil_firststrike = 40, veil_desperation = 40, veil_gravebound = 25, veil_soulharvest = 5,
		veil_bloodharvest = 5, veil_hexbreaker = 20, veil_ashenward = 15},
	-- the hook rules: health thresholds (percent), the most damage the three reductions take off together and the most
	-- Veilpiercer + Last Ember add together (each is capped at 40 by hookCaps; both at once were +80%)
	hook = {firstStrikeAbove = 80, desperationBelow = 50, graveboundBelow = 35, maxReduction = 40, maxDealt = 40},

	-- the veiled pool. key, name, text (format: the effects' values in order), kinds (chaos_item_mods.lua M.kindOf), minLevel
	-- (the item level the modifier needs at all), tiers V1 .. V4 {lo, hi}, effects {k = a catalogue key or a hook key,
	-- mul = the share of the rolled value this effect gets, default 1, at least 1 point}, weight (default 10)
	pool = {
		-- hook modifiers: effects of their own (item_mods.lua hit, damage taken and kill hooks)
		{key = "firststrike", name = "Veilpiercer", text = "+%d%% damage to monsters above 80%% health",
			kinds = {weapon = true, jewel = true}, minLevel = 1,
			tiers = {{8, 11}, {11, 14}, {14, 18}, {18, 22}}, effects = {{k = "veil_firststrike"}}},
		{key = "desperation", name = "Last Ember", text = "+%d%% damage while you are below 50%% health",
			kinds = {weapon = true, jewel = true, other = true}, minLevel = 1,
			tiers = {{10, 13}, {13, 17}, {17, 21}, {21, 26}}, effects = {{k = "veil_desperation"}}},
		{key = "gravebound", name = "Gravebound", text = "%d%% less damage from monsters while you are below 35%% health",
			kinds = {armor = true, helmet = true, legs = true, shield = true, boots = true}, minLevel = 1,
			tiers = {{6, 8}, {8, 10}, {10, 13}, {13, 16}}, effects = {{k = "veil_gravebound"}}},
		{key = "soulharvest", name = "Soul Harvest", text = "Kills restore %d%% of your maximum mana",
			kinds = {helmet = true, jewel = true, weapon = true}, minLevel = 100,
			tiers = {{1, 1}, {1, 2}, {2, 2}, {2, 3}}, effects = {{k = "veil_soulharvest"}}},
		{key = "bloodharvest", name = "Blood Harvest", text = "Kills restore %d%% of your maximum health",
			kinds = {armor = true, jewel = true, other = true, boots = true}, minLevel = 100,
			tiers = {{1, 1}, {1, 2}, {2, 2}, {2, 3}}, effects = {{k = "veil_bloodharvest"}}},
		{key = "hexbreaker", name = "Hexbreaker", text = "%d%% less damage from bosses",
			kinds = {armor = true, helmet = true, shield = true}, minLevel = 1,
			tiers = {{4, 6}, {6, 8}, {8, 10}, {10, 12}}, effects = {{k = "veil_hexbreaker"}}},
		{key = "ashenward", name = "Ashen Ward", text = "%d%% less elemental damage from monsters",
			kinds = {armor = true, legs = true, shield = true, helmet = true, boots = true}, minLevel = 1,
			tiers = {{3, 4}, {4, 6}, {6, 8}, {8, 10}}, effects = {{k = "veil_ashenward"}}},

		-- stronger or paired numbers of the catalogue's modifiers (their caps still hold)
		{key = "doombringer", name = "Doombringer", text = "Damage to Elites and Bosses +%d%%",
			kinds = {weapon = true, jewel = true}, minLevel = 90,
			tiers = {{12, 14}, {14, 17}, {17, 20}, {20, 24}}, effects = {{k = "bossdamage"}}},
		{key = "wraithstride", name = "Wraithstride", text = "Movement Speed +%d%%, Dodge +%d%%",
			kinds = {boots = true}, minLevel = 1,
			tiers = {{5, 6}, {6, 7}, {7, 8}, {8, 10}}, effects = {{k = "movespeed"}, {k = "dodge", mul = 0.5}}},
		{key = "bloodtithe", name = "Bloodtithe", text = "Health on Hit +%d, Life on Kill +%d",
			kinds = {weapon = true, jewel = true, other = true}, minLevel = 1,
			tiers = {{10, 14}, {14, 19}, {19, 25}, {25, 32}}, effects = {{k = "lifeonhit"}, {k = "lifeonkill", mul = 3}}},
		{key = "spellweave", name = "Spellweave", text = "Cooldown Reduction +%d%%, Mana Cost Reduction +%d%%",
			kinds = {helmet = true, jewel = true}, minLevel = 1,
			tiers = {{3, 4}, {4, 5}, {5, 6}, {6, 8}}, effects = {{k = "cdr"}, {k = "manacost"}}},
		{key = "sundering", name = "Sundering", text = "Physical and Elemental Penetration +%d%%",
			kinds = {weapon = true}, minLevel = 1,
			tiers = {{5, 7}, {7, 9}, {9, 11}, {11, 13}}, effects = {{k = "physpen"}, {k = "elepen"}}},
		{key = "plaguebearer", name = "Plaguebearer", text = "Damage over Time +%d%%, Chance to Poison +%d%%",
			kinds = {weapon = true, other = true}, minLevel = 1,
			tiers = {{12, 15}, {15, 19}, {19, 23}, {23, 28}}, effects = {{k = "dot"}, {k = "poisonchance", mul = 0.5}}},
		{key = "stormcaller", name = "Stormcaller", text = "Chance to Shock +%d%%, Chance to Chill +%d%%",
			kinds = {weapon = true}, minLevel = 1,
			tiers = {{7, 9}, {9, 11}, {11, 13}, {13, 16}}, effects = {{k = "shockchance"}, {k = "chillchance"}}},
		{key = "gildedomen", name = "Gilded Omen", text = "Rarity Find +%d%%, Gold Find +%d%%",
			kinds = {helmet = true, jewel = true}, minLevel = 1,
			tiers = {{8, 11}, {11, 14}, {14, 17}, {17, 20}}, effects = {{k = "rarityfind"}, {k = "goldfind"}}},
		{key = "veiledinsight", name = "Veiled Insight", text = "Experience +%d%%",
			kinds = {helmet = true, jewel = true}, minLevel = 90,
			tiers = {{4, 5}, {5, 6}, {6, 7}, {7, 9}}, effects = {{k = "experience"}}},
		{key = "bastion", name = "Bastion", text = "Block Chance +%d%%, Reflect Damage +%d%%",
			kinds = {shield = true}, minLevel = 1,
			tiers = {{5, 7}, {7, 8}, {8, 10}, {10, 12}}, effects = {{k = "block"}, {k = "reflect"}}},
		{key = "briarshroud", name = "Briar Shroud", text = "Thorns +%d, Reflect Damage +%d%%",
			kinds = {armor = true, legs = true, shield = true}, minLevel = 1,
			tiers = {{70, 95}, {95, 120}, {120, 150}, {150, 190}}, effects = {{k = "thorns"}, {k = "reflect", mul = 0.04}}},
		{key = "undyingroot", name = "Undying Root", text = "Health Regeneration +%d per Second, Damage Taken from Monsters -%d%%",
			kinds = {armor = true, legs = true, helmet = true, jewel = true, shield = true}, minLevel = 1,
			tiers = {{18, 24}, {24, 31}, {31, 39}, {39, 48}}, effects = {{k = "regen"}, {k = "monsterreduction", mul = 0.1}}},
		{key = "headsman", name = "Headsman", text = "Executes Monsters below %d%% Health, Chance to Bleed +%d%%",
			kinds = {weapon = true}, minLevel = 110,
			tiers = {{3, 4}, {4, 5}, {5, 6}, {6, 8}}, effects = {{k = "execute"}, {k = "bleedchance", mul = 2}}}
	}
}
