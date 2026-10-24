-- treasure_goblin_config.lua: every number of the Treasure Goblin (treasure_goblin.lua, treasure_goblin_core.lua).
-- Plain table, loaded as ChaosTreasureGoblinConfig = dofile("data/scripts/chaos/treasure_goblin_config.lua").
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then /reload scripts (or restart). See server/README.md
-- "Treasure goblins".
return {
	name = "Treasure Goblin", -- the monster of data/monster/monsters/chaos/treasure_goblin.xml

	-- ------------------------------------------------------------------ spawn
	spawn = {
		-- 1 in `oneIn` natural respawns of an eligible monster is replaced by a Treasure Goblin (0 disables)
		oneIn = 3000,
		-- also roll on the spawns created when the server starts (no players around then; the goblin waits idle)
		atStartup = false,
		-- one goblin per area cell (cellSize x cellSize tiles on one floor) every `areaCooldown` seconds
		cellSize = 64,
		areaCooldown = 1800,
		-- no new goblin while this many are alive on the whole server
		maxAlive = 3,
		-- monsters below this max health (critters) and these names never turn into a goblin (lowercase)
		minMaxHealth = 40,
		skipNames = {},
		-- extra excluded rectangles {x1, y1, x2, y2, z} (z nil = every floor): quest rooms, event areas.
		-- Runtime instances (rifts, arenas, siege, tower, world boss) are excluded anyway: their monsters are created by
		-- scripts (artificial spawns) and only natural map respawns roll, and the guarded area checks in
		-- treasure_goblin.lua ask those modules again.
		excludedAreas = {},
		-- the goblin is placed this many ms after the replaced spawn was cancelled
		delayMs = 50
	},

	-- ------------------------------------------------------------------ Treasure Goblin Chance (the item modifier)
	-- The Chaos item modifier "goblinchance" (data/lib/chaos_item_mods.lua: helmets and jewellery, +10-40% per item by
	-- tier, at most +100% per character) raises the 1-in-oneIn roll of a respawn: the respawn takes the highest total
	-- among the players within `radius` tiles of the spawn point on the same floor (one lucky player is enough; bonuses
	-- of several players do not add up). oneIn / (1 + bonus%): +100% = 1 in 1500. Natural respawns are held back while a
	-- player stands within view of the spawn point, so the radius reaches past the screen. The world event multiplier
	-- (ChaosEvents.bonus "goblin") applies on top. maxAlive and the per-area cooldown stay as they are.
	spoor = {
		modKey = "goblinchance",
		radius = 24,
		cap = 100 -- the same cap as the modifier's; a safety net here as well
	},

	-- ------------------------------------------------------------------ variants
	-- Each goblin is one of these, by weight. All share the behaviour (flee, blinks, escape), the experience, the
	-- leaderboard and the loot rays; the name (one monster XML each: data/monster/monsters/chaos/), the stock look type
	-- and the outfit shader (data/XML/shaders.xml) tell them apart. `loot` overrides parts of the shared loot table
	-- below for that variant (only the keys given; gems, socketOrb, shards and orbs exist only there).
	-- Expected loot per goblin (area level L, no item find):
	--   Hoarder (70%): gold 2000 + 400 L, 3 Orbs of Upheaval (+1 per 150 L, at most 10), 25% Orb of Fate, 2-4 rolled gear,
	--     the unique roll x3 and the hoard roll.
	--   Gem Goblin (20%): half the gold, 2.5 gems (+1 per 250 L, at most 5; tier by L as monster gem drops, 25% one
	--     tier better), 1.25 Orbs of Sockets, 1 rolled gear, the unique roll x1. About 2.5 gems at L 100, 3.5 at L 300.
	--   Shard Goblin (10%): half the gold, rune shards (10 + L/10) x 80-120% (at most 60): about 20 at L 100, 40 at
	--     L 300; 1.5 Orbs of Upheaval (+1 per 300 L, at most 4), 1 random crafting orb (the salvage orb weights), 1 rolled
	--     gear, the unique roll x1. 25 shards make an Orb of Upheaval at the bench, so a Shard Goblin is worth about the
	--     Hoarder's orbs, less its gear.
	--   Across all goblins: about 0.5 gems and 2 (L 100) to 4 (L 300) rune shards per goblin on average.
	variants = {
		{key = "hoarder", name = "Treasure Goblin", weight = 70, look = 297, shader = 12},
		{key = "gem", name = "Gem Goblin", weight = 20, look = 296, shader = 9,
			loot = {
				goldMult = 50,
				chaosOrb = {id = 29856, min = 0, max = 0, perLevels = 1000000, cap = 0},
				divineOrb = {id = 29857, chance = 0},
				items = {min = 1, max = 1},
				unique = {tier = "legendary", mult = 1},
				uniqueHoard = {chance = 0, levelSlack = 20},
				-- gems of chaos_gems.lua: random(min, max) + floor(L / perLevels), at most cap; the tier by
				-- ChaosGems.levelWeights(L), then tierUp percent for one tier better
				gems = {min = 2, max = 3, perLevels = 250, cap = 5, tierUp = 25},
				-- Orb of Sockets (ChaosGems.config.socketOrb.id): count, plus extraChance percent for one more
				socketOrb = {count = 1, extraChance = 25}
			}},
		{key = "shard", name = "Shard Goblin", weight = 10, look = 61, shader = 10,
			loot = {
				goldMult = 50,
				chaosOrb = {id = 29856, min = 1, max = 2, perLevels = 300, cap = 4},
				divineOrb = {id = 29857, chance = 0},
				items = {min = 1, max = 1},
				unique = {tier = "legendary", mult = 1},
				uniqueHoard = {chance = 0, levelSlack = 20},
				-- Rune Shards (salvage_config.lua shard.id): (base + L / perLevel) x random(minMult..maxMult)%, at most cap
				shards = {id = 32051, base = 10, perLevel = 10, minMult = 80, maxMult = 120, cap = 60},
				-- crafting orbs (ChaosCrafting orb keys), count of them, picked by weight (salvage_config.lua orbWeights)
				orbs = {count = 1, weights = {{"transmutation", 35}, {"chaos", 25}, {"scouring", 12}, {"alchemy", 10},
					{"annulment", 8}, {"divine", 5}, {"sockets", 3}, {"exalted", 2}}}
			}}
	},

	-- ------------------------------------------------------------------ area level and health
	level = {
		-- area level = the replaced monster's level (Monster:getMonsterLevel()) when it has one; otherwise the average
		-- level of the players within `playerRadius` tiles; otherwise its max health / healthPerLevel
		playerRadius = 30,
		healthPerLevel = 20,
		min = 1,
		max = 1500
	},
	health = {
		base = 300, -- + perLevel x area level
		perLevel = 40,
		monsterMult = 3.0, -- and at least this multiple of the replaced monster's max health
		max = 2000000
	},
	-- engine trick for "flees only once hit": the XML runonhealth is `runThreshold`; until the first hit the goblin's
	-- health sits above it (threshold + real health), the first hit drops it to the real health, which is below it,
	-- so the engine flee logic (keep distance, run from the target) starts exactly then. Must equal the XML value.
	runThreshold = 100000000,

	-- ------------------------------------------------------------------ behaviour
	behaviour = {
		escapeSeconds = 30, -- after the first hit: escape (portal, "Ha ha!", despawn, no loot) unless killed
		lifetimeSeconds = 1800, -- never hit: vanishes quietly after this long
		tickMs = 500, -- think step of the script (announce, blink, escape check)
		-- flee speed: the attacker's speed x this (at least the goblin's own speed + minBoost); a bit under 1 so a
		-- chaser can close in on foot, the blinks win the distance back
		fleeSpeedMult = 0.95,
		minBoost = 80,
		maxSpeed = 1500,
		-- blink: short teleport away from the attackers
		blinkEveryMs = {2500, 4500}, -- random gap between blinks
		blinkChance = 70, -- percent per due blink
		blinkRange = {3, 5}, -- tiles
		tauntCooldownMs = 2500,
		tauntChance = 60, -- percent per hit (after the cooldown)
		announceRadius = 10, -- "A Treasure Goblin appears!" to players within this many tiles (once per player)
		toast = true, -- also a toast through the notification module (game_chaosnotify), when present
		shader = 12 -- outfit shader (data/XML/shaders.xml, 12 = yellow energizer: a golden glow; 15 drew as stripes in the test client); 0 = none
	},
	taunts = {
		"Ha! Too slow!", "Mine! All mine!", "You'll never catch me!", "Shiny, shiny!", "Nyah nyah!",
		"Hands off my sack!", "Hee hee hee!", "Catch me if you can!"
	},
	appearLine = "Ooh, shiny...",
	escapeLine = "Ha ha!",
	-- %s / the second %s = the variant's name (Treasure Goblin, Gem Goblin, Shard Goblin)
	appearText = "A %s appears!",
	escapeText = "The %s escaped through a portal with its loot!",
	killText = "%s slew a %s!",

	-- ------------------------------------------------------------------ loot (corpse owner = most damage)
	loot = {
		-- gold value: base + perLevel x area level, then x random(minMult..maxMult)%; paid in crystal/platinum/gold
		gold = {base = 2000, perLevel = 400, minMult = 80, maxMult = 130},
		-- Orbs of Upheaval (Orb of Upheaval 29856): count = random(min, max) + floor(area level / perLevels), capped
		chaosOrb = {id = 29856, min = 2, max = 4, perLevels = 150, cap = 10},
		-- Orb of Fate (29857): chance in percent (x item find), count 1
		divineOrb = {id = 29857, chance = 25},
		-- guaranteed gear rolls through the Chaos loot layer (rarity from ChaosLoot.upgradeRarity per tier)
		items = {min = 2, max = 4},
		-- weights of the tier each gear roll is treated as; floor = minimum rarity of that roll
		itemTiers = {{tier = "magic", weight = 50, floor = 2}, {tier = "rare", weight = 35, floor = 3},
			{tier = "legendary", weight = 15, floor = 4}},
		-- gear comes from the replaced monster's loot table (its gear entries); otherwise from this pool,
		-- by area level band {minLevel, {item ids}}
		pool = {
			{0, {2457, 2463, 2647, 2509, 2385, 2428, 2398, 2190, 2182}}, -- steel helmet, plate armor, plate legs ...
			{50, {2491, 2487, 2488, 2519, 2392, 2432, 2436, 2187, 2183, 2195}},
			{120, {2475, 2466, 2470, 2514, 2400, 2407, 2414, 2453, 8922, 8910}},
			{250, {2472, 2493, 2495, 2520, 2390, 2415, 2421, 2408, 8918}}
		},
		-- unique items: ChaosLoot.rollUniques as this tier with the replaced monster's name, x mult on item find
		unique = {tier = "legendary", mult = 3},
		-- if that found nothing: chance in 1/10000 for any non boss-only unique whose level <= area level + slack
		uniqueHoard = {chance = 300, levelSlack = 20},
		messageType = "MESSAGE_LOOT" -- looked up in _G
	},

	-- experience: the replaced monster's experience x mult, capped by area level x capPerLevel (modest on purpose)
	experience = {mult = 3, min = 50, capPerLevel = 60},

	-- optional hooks (guarded; nothing is created here)
	leaderboard = {board = "goblin", mode = "add"} -- ChaosLeaderboard.record when Chaos.leaderboardConfig has it
}
