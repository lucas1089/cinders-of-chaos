-- The Ascended Omens and the Cinderheart (uber.lua, uber_core.lua): every number of the top challenge above the Omen
-- Keys. Loaded with  ChaosUberConfig = dofile("data/scripts/chaos/uber_config.lua")
-- Plain data, no engine calls (tests/uber_test.lua and tools/install_ascended.py read it). Lua 5.1 / LuaJIT and 5.3.
-- Overview: server/README.md "Ascended Omens and the Cinderheart". Player-facing words: "Ascended" and "Cinderheart".
--
-- The chain:
--   Omen guardian killed (rift.lua)          every finisher: shardChance.omen % of an Ascended Shard of that omen
--   rift of tier 13-15 sealed (rift.lua)      every finisher: shardChance.rift[tier] % of a shard of a random omen
--   4 shards of one omen (use one)           -> an Ascended Sigil of that omen
--   Ascended Sigil (use in a protection zone) -> that omen's Ascended arena; the kill gives every finisher its relic
--   one relic of each omen (use one)         -> a Cinderheart Sigil -> the Cinderheart's arena
return {
	enabled = true,

	-- ------------------------------------------------------------------ the items (tools/install_ascended.py)
	-- New items.otb nodes: copies of the stock node sourceId with the new server id (the client keeps the stock look,
	-- so the client needs no change). Shards are stackable, one id per omen; the sigil and the relic carry the kind as
	-- the custom attribute "ascended_kind". Ids 32073..32077 (omens 32071..32072, pouches 32081..32083).
	items = {
		shards = {
			bloodmoon = {id = 32073, sourceId = 18424, name = "ascended shard of the bloodmoon",
				plural = "ascended shards of the bloodmoon", article = "an", weight = 20,
				description = "A clot of the red night that would not die. Four of them bind an Ascended Sigil of the Bloodmoon."},
			hollow = {id = 32074, sourceId = 18414, name = "ascended shard of the hollow crown",
				plural = "ascended shards of the hollow crown", article = "an", weight = 20,
				description = "A splinter of an empty crown, still cold. Four of them bind an Ascended Sigil of the Hollow Crown."},
			storm = {id = 32075, sourceId = 18413, name = "ascended shard of the storm",
				plural = "ascended shards of the storm", article = "an", weight = 20,
				description = "A shard that hums with trapped thunder. Four of them bind an Ascended Sigil of the Storm."}
		},
		sigil = {id = 32076, sourceId = 5809, name = "ascended sigil", plural = "ascended sigils", article = "an", weight = 60,
			description = "It burns with a name that should have stayed dead. Use it in a protection zone."},
		relic = {id = 32077, sourceId = 2353, name = "ascended relic", plural = "ascended relics", article = "an", weight = 80,
			description = "Torn from an Ascended Omen. Three different relics wake the Cinderheart."}
	},
	shardCost = 4, -- shards of one omen per sigil
	shardChance = {
		omen = 40, -- percent per finisher of an Omen guardian kill: one shard of that omen
		rift = {[13] = 4, [14] = 7, [15] = 10} -- percent per finisher of a sealed rift of this tier: a shard of a random omen
	},

	-- ------------------------------------------------------------------ opening
	partyRange = 8,
	maxPlayers = 5,
	needProtectionZone = true,
	useCooldown = 3,
	startDelay = 8, -- seconds between the arrival and the boss
	exitDelay = 25, -- seconds after the kill before everyone is sent back
	tickMs = 250,
	hudEvery = 2, -- seconds between HUD refreshes (the rift HUD, opcode 228; the client counts down in between)

	-- ------------------------------------------------------------------ the arenas (runtime-built, like the rift slots)
	-- Slot i of a grid far from the map: origin + (i % cols, i // cols) x spacing; x/y 7600-7700 (between the ascension
	-- trial grid 7000-7100 and the rift grid 8192+). Each slot: a square arena (floor half-size `half`, walls around)
	-- and, south of it behind a wall, the antechamber where the fallen wait for the Ember Gate (a portal tile).
	grid = {origin = {x = 7600, y = 7600, z = 7}, cols = 2, slots = 4, spacing = 48},
	arena = {half = 9, anteGap = 2, anteHalfW = 3, anteHalfH = 1},
	groundId = 407, -- black marble floor (stock); with the dark tile set: painted in `dark.style`
	wallId = 5648,
	basinId = 1481,
	portalId = 1387, -- magic forcefield, used as a tile with the action id below
	portalActionId = 47411,
	dark = {enabled = true, style = "hall", wall = "obsidian_wall", basin = "brazier"},

	-- ------------------------------------------------------------------ lives (shared, like the rift lives)
	-- A lethal hit is caught: the player is thrown into the antechamber (no death, no loss), the run loses one life and
	-- the Ember Gate lets the player back after reenterSeconds (shieldSeconds without damage from the arena). The fall
	-- that takes the last life ends the run.
	lives = {reenterSeconds = 8, shieldSeconds = 3},

	-- ------------------------------------------------------------------ telegraphs, hazards, enrage
	-- A telegraph marks its tiles (warning effect) at once and again one turn later, then hits warnMs after the first
	-- mark: share x max health to every player still on a marked tile (enraged: enragedShare, warn enragedWarnMs).
	telegraph = {warnMs = 2000, turnMs = 1000, enragedWarnMs = 1000, share = 0.55, enragedShare = 0.8,
		warnEffect = "warning_zone", fillEffect = "warning_fill"},
	-- hazard tiles hurt share x max health per second while stood on (effect every second)
	hazard = {share = 0.07, pulseMs = 1000},
	-- enraged: the boss and its adds hit damageMult harder, telegraphs come twice as often, and every pulseMs a pulse
	-- of pulseShare x max health hits everyone in the arena
	enrage = {damageMult = 1.75, everyMult = 0.5, pulseShare = 0.08, pulseMs = 4000},
	addHealthPerExtraPlayer = 0.5,

	-- ------------------------------------------------------------------ rewards (per finisher, into the backpack / inbox)
	-- gold to the bank, orbs, uniqueRolls rolls over the Ascended uniques of this boss (ChaosUniqueItems entries with
	-- ascended = true that list the boss), x uniqueFind; gearRolls items of the boss's loot at the boss loot tier.
	reward = {
		ascended = {gold = 15000000, chaos = 20, divine = 10, exalted = 1, uniqueRolls = 2, uniqueFind = 6, gearRolls = 4,
			relic = true},
		cinder = {gold = 40000000, chaos = 40, divine = 20, exalted = 3, uniqueRolls = 3, uniqueFind = 10, gearRolls = 6}
	},
	orbs = {chaos = 29856, divine = 29857, exalted = 29855},

	-- ------------------------------------------------------------------ leaderboards (ChaosLeaderboard, mode "min")
	-- fastest Cinderheart kill this week, seconds, per party size bucket; the board's class tabs filter by class
	boards = {{max = 1, key = "cinder_solo"}, {max = 3, key = "cinder_small"}, {max = 5, key = "cinder_party"}},

	-- ------------------------------------------------------------------ the bosses
	-- health: the XML health x (1 + healthPerExtraPlayer x (players - 1)); phases: at = health fraction where the phase
	-- starts (the first one at 1); patterns: telegraphs drawn at random every `every` ms; hazard: tiles that hurt while
	-- the phase lasts; adds: count = base + perPlayer x players, every `every` ms (0 = once at the phase start); heal:
	-- the boss heals perAdd x max health per living add every 5 s (Harvest). enrageAt / limit: seconds after the boss
	-- appears. lives = base + perExtraPlayer x (players - 1).
	-- Balance (server/README.md "Ascended Omens and the Cinderheart", Balance): health and enrage from the measured
	-- level 1000 damage of the classes (data/spells/README.md "Classes with the passive trees"), uber_core.lua U.killTime.
	kinds = {
		{key = "bloodmoon", name = "Bloodmoon", boss = "Ascended Sangrith", omenBoss = "Sangrith the Bloodmoon Herald",
			minLevel = 900, healthPerExtraPlayer = 0.45, enrageAt = 600, limit = 780, lives = {base = 3, perExtraPlayer = 1},
			add = "Bloodmoon Thrall", element = "physical", hitEffect = "px197_crimson", unique = "Sanguine Crescent",
			phases = {
				{at = 1.0, name = "The Red Night", every = 9000, patterns = {"cone", "ring", "marks"},
					yell = "THE MOON RISES AGAIN, AND IT IS MINE!"},
				{at = 0.70, name = "Blood Pools", every = 8000, patterns = {"cone", "ring", "marks"},
					hazard = {kind = "pools", count = 3, perPlayer = 1, radius = 1, effect = "bleeding", lastMs = 20000},
					adds = {base = 1, perPlayer = 1, every = 0}, yell = "DRINK, MY CHILDREN!"},
				{at = 0.35, name = "Harvest", every = 7000, patterns = {"cone", "ring", "marks", "cross"},
					adds = {base = 1, perPlayer = 1, every = 30000}, heal = {perAdd = 0.01},
					yell = "EVERY DROP RETURNS TO ME!"}
			}},
		{key = "hollow", name = "Hollow Crown", boss = "Ascended Morvane", omenBoss = "Morvane the Hollow Crown",
			minLevel = 900, healthPerExtraPlayer = 0.45, enrageAt = 600, limit = 780, lives = {base = 3, perExtraPlayer = 1},
			add = "Hollow Wraith", element = "death", hitEffect = "shadow_eruption", unique = "Hollow Crown of Morvane",
			phases = {
				{at = 1.0, name = "The Empty Throne", every = 9000, patterns = {"cross", "circle", "half"},
					yell = "KNEEL BEFORE A CROWN WITH NO KING!"},
				{at = 0.70, name = "Wraith Court", every = 8000, patterns = {"cross", "circle", "half"},
					adds = {base = 2, perPlayer = 1, every = 35000}, yell = "MY COURT RETURNS FROM THE GRAVE!"},
				{at = 0.35, name = "Creeping Dark", every = 7000, patterns = {"cross", "circle", "half", "ring"},
					hazard = {kind = "edge", stepMs = 20000, maxDepth = 3, effect = "cursed"},
					yell = "THE DARK CLOSES IN. THERE IS NOWHERE LEFT."}
			}},
		{key = "storm", name = "Storm", boss = "Ascended Thalcyra", omenBoss = "Thalcyra the Stormbound Seer",
			minLevel = 900, healthPerExtraPlayer = 0.45, enrageAt = 600, limit = 780, lives = {base = 3, perExtraPlayer = 1},
			add = "Storm Shard", element = "energy", hitEffect = "lightning_strike", unique = "Eye of the Unbroken Storm",
			phases = {
				{at = 1.0, name = "Gathering Storm", every = 9000, patterns = {"marks", "lines", "eye"},
					yell = "I HAVE SEEN HOW YOU DIE. HOLD STILL."},
				{at = 0.70, name = "Storm Columns", every = 8000, patterns = {"marks", "lines", "eye"},
					hazard = {kind = "columns", count = 4, perPlayer = 1, radius = 0, effect = "lightning_hit", moveMs = 10000},
					yell = "THE SKY ANSWERS ONLY ME!"},
				{at = 0.35, name = "Shattered Sky", every = 7000, patterns = {"marks", "lines", "eye", "circle"},
					adds = {base = 2, perPlayer = 1, every = 30000}, yell = "BREAK, AND BE SCATTERED!"}
			}},
		-- the Cinderheart: the sigil comes from one relic of each Ascended Omen
		{key = "cinder", name = "Cinderheart", boss = "Ysgrath the Cinderheart", final = true,
			minLevel = 1000, healthPerExtraPlayer = 0.58, enrageAt = 900, limit = 1080, lives = {base = 2, perExtraPlayer = 1},
			add = "Cinderspawn", element = "fire", hitEffect = "meteor_strike", unique = "Cinderheart Signet",
			phases = {
				{at = 1.0, name = "Red Night Remembered", every = 8000, patterns = {"cone", "ring", "marks"},
					hazard = {kind = "pools", count = 3, perPlayer = 1, radius = 1, effect = "burning", lastMs = 18000},
					yell = "THREE OMENS FELL. I AM WHAT THEY WERE HIDING."},
				{at = 0.75, name = "The Hollow Court", every = 7500, patterns = {"cross", "circle", "half"},
					adds = {base = 1, perPlayer = 1, every = 35000}, yell = "A THRONE OF ASH NEEDS A COURT!"},
				{at = 0.50, name = "Storm of Cinders", every = 7000, patterns = {"marks", "lines", "eye"},
					hazard = {kind = "columns", count = 4, perPlayer = 1, radius = 0, effect = "fire_explosion", moveMs = 9000},
					yell = "BURN, AND LET THE SKY CARRY YOUR ASHES!"},
				{at = 0.25, name = "The Last Cinder", every = 6000, patterns = {"cone", "ring", "cross", "eye", "half", "marks"},
					hazard = {kind = "edge", stepMs = 18000, maxDepth = 3, effect = "burning"},
					adds = {base = 1, perPlayer = 1, every = 30000}, heal = {perAdd = 0.005},
					yell = "IF I GO OUT, I TAKE THE WORLD'S LAST LIGHT WITH ME!"}
			}}
	},

	-- the pattern shapes (uber_core.lua U.pattern): sizes in sqm
	patterns = {
		cone = {length = 7, spread = 3}, -- in front of the boss, towards its target
		ring = {inner = 3, outer = 7}, -- around the boss: safe next to it and far away
		circle = {radius = 3}, -- around the boss
		marks = {radius = 1}, -- under every player: spread out
		cross = {halfWidth = 1}, -- through the boss, wall to wall
		half = {}, -- one half of the arena (N, E, S or W of the boss's row / column)
		lines = {count = 3}, -- whole rows or columns
		eye = {safe = 2} -- everything but a circle round one marked tile: stack in it
	},

	-- the balance model (U.killTime): a well-geared level 1000 character deals refDps to one target (the level 1000
	-- median of data/spells/README.md "Classes with the passive trees" plus the Ascended / boss uniques), the healer
	-- of a party healerDps; uptime = the share of the fight spent hitting the boss (moving out of telegraphs, adds)
	model = {refDps = 3000, healerDps = 2000, uptimeSolo = 0.75, uptimeParty = 0.8},
	-- the targets the health and enrage numbers were set for (seconds); tests/uber_test.lua keeps them in line
	targets = {
		ascended = {solo = 540, party5 = 300},
		cinder = {solo = 730, party5 = 480}
	},

	staffGroup = 4 -- /ascended
}
