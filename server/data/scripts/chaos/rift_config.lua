-- Rift settings (rift.lua, rift_core.lua). Loaded with
--     ChaosRiftConfig = dofile("data/scripts/chaos/rift_config.lua")
-- Every number of the rifts lives here. Lua 5.1 / LuaJIT compatible. Item ids are SERVER ids.
-- Overview: server/README.md "Rifts".

return {
	-- ------------------------------------------------------------------ the key item
	-- An existing non-stackable item no other script uses ("shadow orb"; one quest NPC lists it, Black Bert) with this
	-- action id. Tier and modifiers
	-- are custom attributes ("rift_tier", "rift_mods" = "key:value,key:value"); the name becomes "Rift Key (Tier N)" and
	-- the description lists the modifiers and the reward bonuses, so looking at a key shows them.
	-- maxMods: the most modifiers a key can carry (drops roll 1-3; the Exalted Orb adds up to this). alchemyCount: how
	-- many modifiers an Orb of Alchemy gives a key without any, {count, weight} (data/lib/chaos_crafting.lua)
	key = {itemId = 10155, actionId = 47401, nameFormat = "Rift Key (Tier %d)", maxMods = 3,
		alchemyCount = {{2, 60}, {3, 40}}},
	chest = {itemId = 1740, actionId = 47402}, -- the reward chest that appears where the rift boss died
	maxTier = 15,

	-- ------------------------------------------------------------------ opening
	partyRange = 8, -- party members within this many sqm (same floor) of the player using the key come along
	maxPlayers = 4,
	needProtectionZone = true,
	useCooldown = 3, -- seconds between two key uses of one player (exhaust)

	-- ------------------------------------------------------------------ the run
	timeLimit = 600, -- seconds; when it runs out the rift fails: everyone is sent out, the key is lost
	bossAt = 75, -- percent of the rift's monsters that must die before the boss appears
	exitDelay = 60, -- seconds after the boss died: time to open the chest and loot; then everyone is sent out
	hudEvery = 5, -- seconds between HUD refreshes (the client counts down by itself in between)

	-- packs: count = packs.base + floor(tier / packs.perTiers) + packs.perExtraPlayer x (players - 1);
	-- size = a random number in packs.size, + the Swarm modifier. One monster type per pack.
	packs = {base = 6, perTiers = 3, perExtraPlayer = 2, size = {3, 4}, types = 3, spread = 2},
	-- the boss: the strongest of the rift's monster types, made legendary (monster_tiers.lua), its base health x this
	boss = {healthMult = 3, perExtraPlayer = 1.0, tier = "legendary"},
	-- monster tiers inside a rift (percent per monster, before the Elites modifier; x (1 + perTier x tier))
	elite = {magic = 10, rare = 3, legendary = 0.6, perTier = 0.05},

	-- rift tier -> monster level window of the bounty pool (bounty_pool.lua "level") and the level needed to enter.
	-- Tiers above #tiers reuse the last window and add `beyond` per tier (health, damage, rewards).
	tiers = {
		{minLevel = 100, pick = {80, 180}},
		{minLevel = 150, pick = {140, 240}},
		{minLevel = 200, pick = {200, 320}},
		{minLevel = 300, pick = {280, 420}},
		{minLevel = 400, pick = {380, 520}},
		{minLevel = 500, pick = {480, 640}},
		{minLevel = 600, pick = {580, 740}},
		{minLevel = 700, pick = {680, 840}},
		{minLevel = 800, pick = {780, 940}},
		{minLevel = 900, pick = {880, 1100}}
	},
	beyond = {minLevelStep = 25, health = 0.15, damage = 0.15, reward = 0.10},
	minPoolHealth = 100, -- pool entries with less health are left out (odd custom entries)
	widenStep = 60, -- a window with fewer than packs.types monsters is widened by this much per side, up to 5 times

	-- ------------------------------------------------------------------ modifiers
	-- Rolled when the key drops: 1-3 different ones (modCount weights), each with a value in `range` (multiple of
	-- `step`). They make the rift harder and add reward bonuses: `reward` = percent bonus per point of value
	-- (fixed = flat percent). quantity: Chaos loot rate of kills and chest items; rarity: chest gear rarity;
	-- experience: kill experience in the rift (on top of the cap, see `exp`).
	modCount = {{1, 50}, {2, 35}, {3, 15}}, -- {count, weight}
	modCountBetter = {{1, 25}, {2, 45}, {3, 30}}, -- weights for a next-tier key from a completed rift
	mods = {
		{key = "vitality", name = "Vitality", text = "Monsters have +%d%% health", range = {20, 60}, step = 5,
			reward = {quantity = 0.5, experience = 0.25}},
		{key = "brutality", name = "Brutality", text = "Monsters deal +%d%% damage", range = {15, 40}, step = 5,
			reward = {rarity = 0.75, experience = 0.25}},
		{key = "haste", name = "Haste", text = "Monsters move +%d faster", range = {40, 120}, step = 10,
			reward = {quantity = 0.15}},
		{key = "elites", name = "Elites", text = "+%d%% magic, rare and legendary monsters", range = {50, 200}, step = 25,
			reward = {rarity = 0.15, quantity = 0.1}},
		{key = "reflection", name = "Reflection", text = "Monsters reflect %d%% of the damage they take", range = {5, 15}, step = 1,
			reward = {experience = 1.5, quantity = 1.0}},
		{key = "warding", name = "Warding", text = "Monsters resist %d%% elemental damage", range = {10, 30}, step = 5,
			reward = {quantity = 0.75, rarity = 0.5}},
		{key = "withering", name = "Withering", text = "Players do not regenerate health", range = {1, 1}, step = 1,
			reward = {fixed = {experience = 15, quantity = 15}}},
		{key = "swarm", name = "Swarm", text = "+%d monsters in every pack", range = {1, 3}, step = 1,
			reward = {quantity = 8, experience = 5}},
		-- map modifiers (second set). weight: relative roll weight (the first eight have the default 100); minTier: the
		-- lowest key tier that rolls it (a key of a lower tier never gets it from a drop or an orb); boon = true: a pure
		-- reward without a bonus of its own (shown in gold on the HUD). Effects in rift.lua, numbers in the blocks below.
		{key = "teeming", name = "Teeming", text = "+%d%% monster packs", range = {20, 50}, step = 10,
			weight = 80, reward = {quantity = 0.5, experience = 0.3}},
		{key = "gilded", name = "Gilded Trail", text = "%d%% chance of a fleeing Treasure Goblin",
			range = {30, 70}, step = 10, weight = 40, boon = true},
		{key = "warband", name = "Warbands", text = "%d%% of packs are rare warbands",
			range = {10, 30}, step = 5, weight = 60, minTier = 2, reward = {rarity = 1.0, quantity = 0.3}},
		{key = "coffer", name = "Sealed Coffer", text = "%d%% chance of a guarded coffer",
			range = {40, 100}, step = 20, weight = 50, boon = true},
		{key = "twin", name = "Twin Guardians", text = "Twin guardians, %d%% health each", range = {55, 75},
			step = 5, weight = 50, minTier = 3, reward = {rarity = 0.25, quantity = 0.2}},
		{key = "echo", name = "Echoing Spoils", text = "%d%% chance of double loot",
			range = {5, 15}, step = 5, weight = 35, minTier = 2, boon = true},
		{key = "cinder", name = "Cinderdeath", text = "Slain monsters burst for %d%% health",
			range = {5, 15}, step = 5, weight = 70, minTier = 3, reward = {quantity = 1.2, rarity = 0.8}},
		{key = "blight", name = "Blighted Mending", text = "Players receive %d%% less healing", range = {20, 50}, step = 10,
			weight = 70, minTier = 2, reward = {rarity = 0.5, experience = 0.3, quantity = 0.2}},
		{key = "waning", name = "Waning Veil", text = "The rift closes %d%% sooner", range = {15, 30}, step = 5,
			weight = 70, reward = {quantity = 1.0, experience = 0.5}},
		{key = "dread", name = "Dread Guardian", text = "Guardian +%d%% health and damage", range = {50, 150},
			step = 25, weight = 60, minTier = 4, reward = {rarity = 0.2, quantity = 0.1}}
	},
	-- caps of the summed reward bonuses of a key (percent). The highest three-modifier sums of the first eight
	-- modifiers (quantity 77, rarity 75, experience 53) stay under them, so they only bound the new combinations.
	bonusCap = {quantity = 80, rarity = 75, experience = 60},
	-- Gilded Trail: the goblin (treasure_goblin.lua, ChaosTreasureGoblin.spawn) appears in a random open room once
	-- this percent range of the rift's kills is done (rolled per run), at the level of the rift's strongest type
	gilded = {atKills = {25, 60}},
	-- Sealed Coffer: a treasure chest in a random open side room. Using it wakes a wave of rift monsters around it
	-- (wave.base + wave.perExtraPlayer x (players - 1), at least `waveTier`); once they are dead it opens with: gold
	-- coins goldPerTier2 x tier^2, Chaos / Divine Orbs and item rolls (as the reward chest, base + perTier x tier), all x
	-- (1 + quantity bonus). Wave kills do not count towards the guardian. A coffer nobody woke crumbles when the rift is
	-- sealed; a woken one opens then.
	coffer = {itemId = 1746, actionId = 47403, wave = {base = 5, perExtraPlayer = 1, spread = 2}, waveTier = "magic",
		goldPerTier2 = 4000, chaos = {base = 1, perTier = 0.25}, divine = {base = 0, perTier = 0.1},
		rolls = {base = 2, perTier = 0.25}},
	-- Cinderdeath: delayMs after a (non-guardian) monster dies, every player within `radius` sqm of it takes fire damage:
	-- value % of the monster's max health, at most capBase + capPerTier x tier
	cinder = {delayMs = 1500, radius = 1, capBase = 300, capPerTier = 150},
	-- Twin Guardians: the second guardian appears this many sqm east of the first
	twin = {offset = 2},
	-- Withering keeps mana regeneration: the food regeneration condition is replaced by one without health gain.

	-- ------------------------------------------------------------------ rewards (the chest, per player)
	-- gold (bank) = goldPerTier2 x tier^2; orbs = base + perTier x tier (fractions are a chance of one more);
	-- item rolls: each draws one entry of a random rift monster's loot table weighted by its chance (stack size x the
	-- quantity bonus); gear gets a rarity from the Chaos loot layer (ChaosLoot.upgradeRarity at the `lootTier` of the
	-- rift tier, x the rarity bonus); then one currency roll (ChaosLoot.rollCurrency) and one unique roll at that tier.
	-- Gold, orbs and the number of rolls are x (1 + quantity bonus). Tiers above 10: x (1 + beyond.reward x (t - 10)).
	reward = {
		goldPerTier2 = 10000,
		chaos = {base = 1, perTier = 0.5},
		divine = {base = 0, perTier = 0.25},
		rolls = {base = 2, perTier = 0.5},
		lootTier = {{3, "magic"}, {6, "rare"}, {10, "legendary"}, {999, "boss"}}, -- {up to tier, loot layer tier}
		items = {chaos = 29856, divine = 29857}
	},

	-- next key from a completed rift (one per run, to the player who used the key, else a random finisher):
	-- chance = base + perMod x modifiers (capped at max), and of those `nextTier` + perMod x modifiers are tier + 1
	keyDrop = {base = 30, perMod = 10, max = 60, nextTier = 50, nextPerMod = 10},
	-- rare / legendary monsters killed inside a rift: percent chance of a key of the rift's tier in the corpse
	eliteKeyChance = {rare = 2, legendary = 6},

	-- tier-1 keys from normal monsters (any map hunt, not inside a rift): per 100000 per kill, x tierMult of the
	-- monster's tier, when the monster's hunting level (bounty pool) is at least max(minMonsterLevel,
	-- killer level x levelShare) and the killer is at least minKillerLevel (tier 1 minLevel)
	monsterKey = {chance = 50, minMonsterLevel = 60, levelShare = 0.4,
		tierMult = {normal = 1, magic = 3, rare = 8, legendary = 20, boss = 40}},
	-- completed bounty contracts give a tier-1 key with this percent chance (players at tier 1 minLevel or more)
	bountyKey = {hunt = 25, elite = 50, boss = 100},

	-- ------------------------------------------------------------------ experience cap
	-- Experience comes from the kills only. So that a dense rift cannot beat open hunting, the BASE experience of rift
	-- kills (monster experience x the monster-level bonus x the stage x the magic/rare/legendary multiplier, before
	-- stamina, potions and the Chaos bonuses) is capped per player at capFactor x the leveling model's rate at the
	-- player's level, per minute spent in the run (at least capMinMinutes). Above the cap a kill gives overCapMult of its
	-- experience. The modifiers' Experience bonus applies on top (to what the cap lets through).
	-- model: the sorcerer's base hours per level band from server/README.md "The leveling model and the hours"
	-- (the fastest vocation, so the cap never cuts below open hunting for anyone). Levels past the last band use the
	-- last band's rate (the hours per level grow with the experience per level).
	exp = {
		capFactor = 1.1,
		overCapMult = 0.02,
		capMinMinutes = 1,
		model = {{1, 100, 0.3}, {100, 300, 2.6}, {300, 500, 7.3}, {500, 700, 21.8}, {700, 800, 17.2}, {800, 900, 21.1},
			{900, 1000, 25.5}}
	},

	-- ------------------------------------------------------------------ the instance (built at runtime)
	-- A grid of slots far from the map: slot i is at origin + (i % cols, i // cols) x spacing. The real map has no
	-- tiles there (its OTBM tile areas end below x/y 2600 apart from the main continent at 30720+ and two single
	-- areas at 16640,16384 and 18944,18944; other runtime areas: Infinity Tower 2000-2660, tutorial island 4600+,
	-- world boss 5000-5048, guild siege 5100+, PvP arena 6000-6100). The grid covers x/y 8192-8447.
	-- Each slot: a hub room and four side rooms (N, E, S, W) joined by corridors; every run opens 2-4 of them.
	grid = {origin = {x = 8192, y = 8192, z = 7}, cols = 4, rows = 4, spacing = 64},
	room = {hubHalf = 8, sideHalf = 6, corridor = 4, corridorHalf = 1}, -- half sizes include the wall
	openRooms = {2, 4}, -- side rooms opened per run (random)
	wallId = 5648, -- stone wall (also the blocker of a closed corridor)
	basinId = 1481, -- coal basin (light) in the hub corners
	-- dark tile set (server/README.md "Dark tile set"): when enabled and installed (items.otb, client pair), the walls
	-- and hub lights use these and each theme with a darkStyle is painted by data/lib/chaos_dark_paint.lua (a main
	-- ground, patches of a second ground with borders, decoration; solid pieces only against the walls). Without the
	-- set, or with enabled = false, the stock ids above and the theme `grounds` are used.
	dark = {enabled = true, wall = "obsidian_wall", basin = "brazier"},
	-- themes: grounds are picked at random per tile from the list (all full ground sprites, checked in the client)
	themes = {
		{name = "Abyssal Rift", grounds = {25549, 25704, 25705, 25706, 25707, 25708, 25709}, darkStyle = "abyss"}, -- "rift floor"
		{name = "Obsidian Hall", grounds = {407}, darkStyle = "hall"}, -- black marble floor
		{name = "Ashen Crypt", grounds = {13189, 12237}, darkStyle = "crypt"}, -- dark sandy floor, rutted stone floor
		{name = "Forsaken Sanctum", grounds = {415}, darkStyle = "sanctum"} -- gilded stone floor
	}
}
