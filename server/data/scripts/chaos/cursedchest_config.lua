-- cursedchest_config.lua: every number of the Cursed Chest (cursedchest.lua, cursedchest_core.lua). A monster kill may
-- leave a cursed chest at the corpse. Using it wakes five hordes, one at a time; when the fifth is dead the chest opens
-- for its owner's party. Plain table, loaded as ChaosCursedChestConfig = dofile("data/scripts/chaos/cursedchest_config.lua").
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then /reload scripts (or restart). See server/README.md
-- "Cursed Chest". Nothing here is stored: events live in memory and end with the server (storage keys: none).
return {
	enabled = true,

	-- ------------------------------------------------------------------ the chance of a kill
	spawn = {
		-- percent per kill by the monster's tier (monster_tiers.lua ChaosTierOf); the owner is the corpse owner (most
		-- damage, or the master of the summon that did) and only that player rolls
		chance = {normal = 0.3, magic = 0.8, rare = 1.5, legendary = 2.2, boss = 3},
		maxChance = 6, -- never more than this, whatever multiplies it
		-- the level gap, as the Ember Blessings: a monster at most `grace` levels under the character counts in full;
		-- past that the chance follows the monster's level as a share of the character's (`ratio`: the first row the
		-- share reaches). Under the last row there is no chance at all.
		levelGap = {
			grace = 10,
			ratio = {{0.75, 1.0}, {0.6, 0.5}, {0.45, 0.2}}
		},
		-- per character: no new chest for this long after one appeared (the owner's), and at most this many unopened
		-- at once
		cooldownSec = 360,
		maxPerPlayer = 1,
		-- on the whole server: no new chest while this many exist
		maxAlive = 25,
		-- an unopened chest crumbles after this long
		expireSec = 150,
		-- monsters below this max health (critters), these names (lowercase) and monsters killed in these rectangles
		-- {x1, y1, x2, y2, z} (z nil = every floor) never leave a chest
		minMaxHealth = 40,
		excludeNames = {},
		excludedAreas = {},
		-- monsters that carry one of these death events are made by a system with its own rewards (treasure goblins,
		-- rifts, invasions, the Tower, areas ...) and never leave a chest; the chest's own monsters are tagged anyway
		excludeEvents = {"ChaosTreasureGoblinDeath", "ChaosRiftMonsterDeath", "ChaosInvasionDeath", "ChaosAreaGenDeath",
			"ChaosCursedChestDeath"},
		-- a chest is placed on the corpse's tile or the closest free one within this many tiles
		placeRadius = 2,
		-- the owner and the players within this many tiles see "a cursed chest appears" (the owner always does)
		announceRadius = 9
	},

	-- ------------------------------------------------------------------ the chest
	chest = {
		-- the look: every chest that spawns wears the one-tile look (client item 38642 redrawn in pair 53, server item 32281
		-- from tools/install_cursed_chest.py: 1x1, one phase, not moveable, a container); an id that is not installed on the
		-- server is left out of the draw. Pair 43's three 2x2 looks (32281-32283) were drawn at random before.
		itemIds = {32281},
		-- the other two looks of pair 43 (still in the pair and in items.otb): never drawn now, but a chest that already
		-- wears one (placed before the change) is still a cursed chest until it opens or crumbles
		legacyItemIds = {32282, 32283},
		-- the fallback while none of the looks is installed: the treasure chest of the Sealed Coffer (rift_config.lua
		-- coffer): 2x2, not moveable, a container. A chest wearing this id still counts as a cursed chest.
		itemId = 12664,
		actionId = 47730, -- 47720-47729 are the Harvest Portals; 47730 is free (server/README.md "Cursed Chest")
		name = "cursed chest",
		description = "A chest wrapped in dark chains. Something stirs inside. Whoever opened it first must face five hordes.",
		nameOpened = "unsealed cursed chest",
		-- a dark loop above it while it waits, wakes or is open: a magic effect name (CONST_ME_*) every `loopMs`
		loopEffect = "CONST_ME_MORTAREA",
		loopEffectAlt = "CONST_ME_PURPLEENERGY", -- every third loop
		loopMs = 1500,
		openEffect = "CONST_ME_FIREWORK_YELLOW",
		crumbleEffect = "CONST_ME_POFF",
		label = "CURSED CHEST", labelColor = 155 -- floating text (palette byte r*36 + g*6 + b)
	},

	-- ------------------------------------------------------------------ the event
	event = {
		-- the opener and the opener's party members within this many tiles of the chest take part
		joinRadius = 9,
		-- the event fails when nobody who takes part is within this many tiles of the chest (same floor, online,
		-- alive) for `emptyGraceSec` in a row; a warning comes after `warnSec`
		leaveRadius = 16,
		emptyGraceSec = 10,
		warnSec = 4,
		totalSec = 270, -- the whole event, from the use of the chest: fail past it
		firstDelayMs = 2500, -- the first horde comes this long after the use
		betweenMs = 3000, -- the next horde comes this long after the last monster of the one before died
		hordeTimerSec = 45, -- or this long after the horde before came, dead or not (the chest does not wait)
		aliveCap = 30, -- no horde while this many of the event's monsters live (the horde waits)
		tickMs = 1000,
		claimSec = 120, -- the open chest waits this long for its party, then crumbles
		remindSec = 30, -- whoever has not taken a share is reminded this long before it crumbles
		spreadMin = 2, spreadMax = 5, -- tiles from the chest a horde appears at
		-- extra monsters per extra player in the party: +this share of the horde (rounded), up to maxPartyScale
		partyHorde = 0.35, maxPartyScale = 2.0,
		-- the hordes. count: monsters (the leader included); tiers: percent of the others by monster tier (the rest
		-- normal); leader: percent of leader tiers (a horde with a leader replaces one monster); health / damage: x
		-- on top of the level scale
		hordes = {
			{count = 4, tiers = {magic = 0}, health = 1.0, damage = 1.0},
			{count = 5, tiers = {magic = 25}, health = 1.1, damage = 1.05},
			{count = 6, tiers = {magic = 40, rare = 10}, health = 1.2, damage = 1.1},
			{count = 7, tiers = {magic = 45, rare = 25}, health = 1.35, damage = 1.2},
			{count = 8, tiers = {magic = 40, rare = 30}, health = 1.5, damage = 1.3,
				leader = {rare = 70, legendary = 30}}
		},
		-- the monsters come from the corpse's area: the killed monster's name and the monsters (no bosses, goblins,
		-- summons or event monsters) within `nearRadius` tiles when it died, at most `maxKinds` kinds; fewer than
		-- `minKinds` kinds are filled from the themed list of the band of the monster's level
		pool = {
			nearRadius = 10, maxKinds = 4, minKinds = 2, killedWeight = 3,
			themed = {
				{0, {"Rotworm", "Cyclops", "Dwarf Soldier", "Wasp", "Skeleton", "Ghoul"}},
				{50, {"Dragon", "Hydra", "Wyvern", "Behemoth", "Vampire", "Giant Spider"}},
				{120, {"Demon Skeleton", "Frost Dragon", "Giant Spider", "Hellhound", "Plaguesmith", "Nightmare"}},
				{250, {"Hellhound", "Demon", "Behemoth", "Frost Dragon Hatchling", "Defiler", "Lost Soul"}}
			}
		},
		-- scale to the opener: the monsters' level is the highest of their own and levelShare x the opener's level, at
		-- most the opener's level (areagen_core.lua levelScale: x(1 + 0.0074 L) health, x(1 + 0.0015 L) damage). The
		-- factors are capped so a stock monster at a late level stays a hunt, not a boss fight.
		scale = {levelShare = 0.9, healthK = 0.0074, damageK = 0.0015, maxHealth = 3.0, maxDamage = 2.0}
	},

	-- ------------------------------------------------------------------ the loot (one roll per player who takes part)
	-- Value, so it stays inside the economy models: a player opens about 4-5 chests an hour of hunting (the chances
	-- above; at most 10 with the cooldown), each after a fight of 2-4 minutes whose monsters drop no loot (they are
	-- husks: experience only, at the hunt's pace). The gold is `goldMinutes` of hunting gold at the player's level
	-- (the "Respec" table = gamble_config.lua balance.hunting): 3 minutes x 4.5 an hour = 13% of an hour's gold,
	-- which the fight time (no regular drops) takes back. Orbs: one Orb of Upheaval (a rift tier 15 run gives 3-6 in
	-- about 8 minutes) and a few percent of an Orb of Fate. Gear: 1-2 pieces with a better rarity than a rare kill.
	loot = {
		hunting = {{8, 19000}, {40, 83000}, {100, 358839}, {300, 881866}, {500, 5548330}, {1000, 9519711}},
		goldMinutes = 3, goldMin = 80, goldMax = 125, -- percent of the average
		chaosOrb = {id = 29856, min = 1, max = 1, perLevels = 400, cap = 4},
		divineOrb = {id = 29857, chance = 3}, -- percent, x item find
		shards = {id = 32051, base = 4, perLevel = 25, cap = 30},
		-- crafting orbs: count and ChaosCrafting orb keys by weight (salvage_config.lua orbWeights)
		orbs = {count = 1, weights = {{"transmutation", 35}, {"chaos", 25}, {"scouring", 12}, {"alchemy", 10},
			{"annulment", 8}, {"divine", 5}, {"sockets", 3}, {"exalted", 2}}},
		items = {min = 1, max = 2},
		-- weights of the tier each gear roll is treated as (ChaosLoot.upgradeRarity); floor = the least rarity
		itemTiers = {{tier = "magic", weight = 30, floor = 2}, {tier = "rare", weight = 50, floor = 3},
			{tier = "legendary", weight = 20, floor = 4}},
		rarityMult = 1.5, -- on item find for the rarity roll
		-- fallback gear by monster level band {minLevel, {item ids}} when the killed monster's loot table has none
		pool = {
			{0, {2457, 2463, 2647, 2509, 2385, 2428, 2398, 2190, 2182}},
			{50, {2491, 2487, 2488, 2519, 2392, 2432, 2436, 2187, 2183, 2195}},
			{120, {2475, 2466, 2470, 2514, 2400, 2407, 2414, 2453, 8922, 8910}},
			{250, {2472, 2493, 2495, 2520, 2390, 2415, 2421, 2408, 8918}}
		},
		-- unique items: ChaosLoot.rollUniques as this tier with the killed monster's name, x mult on item find
		unique = {tier = "rare", mult = 1},
		-- each player's share of the loot by party size (the party's total grows slower than its size)
		partyShare = {1.0, 0.75, 0.6, 0.5, 0.45},
		partyShareMin = 0.4,
		messageType = "MESSAGE_LOOT"
	},

	-- the level of the loot: the chest's area level is the killed monster's level, but at least this share of the
	-- opener's level and at most the opener's level + `slack`
	level = {min = 1, max = 1500, floorShare = 0.5, slack = 0}
}
