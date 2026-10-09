-- Invasions and world events (invasion.lua, worldevents.lua, pure logic invasion_core.lua). Returned as a table,
-- loaded as Chaos.invasionConfig. Plain data only: the Wandering Merchant NPC script reads it too (its own Lua state).
-- Server local time. See server/README.md "Invasions and world events". Lua 5.1 / LuaJIT compatible.
return {
	enabled = true, -- the automatic schedule and the random daily invasion (the staff commands work either way)

	-- ======================================================================= when
	-- weekdays: 1 = Sunday .. 7 = Saturday (nil = every day). area / faction: a key below or "random"
	-- (the random pick depends only on the start time, so the warnings and the calendar name the real one).
	-- The guild siege is Saturday 20:00 and the world boss 03/09/15/21:00: keep clear of them.
	schedule = {
		{weekdays = {4}, hour = 19, minute = 30, area = "random", faction = "random"}, -- Wednesday evening
		{weekdays = {1}, hour = 17, minute = 30, area = "random", faction = "random"} -- Sunday afternoon
	},
	-- one surprise invasion on `chance` percent of the days, at a random minute between fromHour and toHour, at least
	-- minGapMinutes away from a scheduled one and from the world boss hours (avoidHours). Decided by the date alone,
	-- so a restart does not roll again. Not shown in the calendar; announced 30 / 10 / 1 minutes before like the others.
	random = {chance = 35, fromHour = 12, toHour = 23, minGapMinutes = 90, avoidHours = {15, 21}, salt = 7919},
	warnMinutes = {30, 10, 1},
	calendarName = "Invasion",
	calendarColors = {"#c8402a", "#6a1a10"},

	-- ======================================================================= the fight
	timeLimitMinutes = 20, -- from the start to the end of the last wave and the boss
	firstWaveSeconds = 30, -- the start announcement, then the first wave
	hudSeconds = 2, -- HUD refresh to every player online (minLevel)
	hudTop = 3, -- top contributors shown
	minLevel = 30, -- players below see the toasts but not the HUD, and get no reward
	templeRadius = 6, -- invaders never spawn within this many tiles of a temple (Game.getTowns)
	moveMs = 400, -- invader movement step check (each invader steps at most at its own speed)
	waves = {
		count = 5, -- the last one brings the boss
		base = 10, perWave = 4, -- monsters in wave i = (base + perWave x (i - 1)) x player factor
		packSize = {3, 5}, -- a pack arrives together at one edge point
		nextAtLeft = 0.25, -- the next wave comes when this fraction of the current one is left ...
		maxWaveSeconds = 150, -- ... or after this long
		edgeDepth = 3 -- spawn points: the outer 3 rows of the area border (only walkable tiles, never protection
		-- zones, houses, depots, teleports, floor changes or the area's `exclude` rectangles)
	},
	-- defenders online near the area (within playerRadius of it, level >= minLevel) make waves and boss bigger
	players = {perPlayer = 0.15, maxFactor = 3.0, radius = 30},
	-- percent chance per invader {base, + per wave}: wave 5 = magic 26%, rare 10%, legendary 4%
	tiers = {magic = {10, 4}, rare = {2, 2}, legendary = {0, 1}},
	-- invaders are brought to the area level: ratio = area level / monster level, health x ratio^hpExp, damage x
	-- ratio^dmgExp, experience x ratio^xpExp, each clamped [minMult, max*]. rosterLow/High: the faction's monsters
	-- within [0.35, 1.25] x area level are used (at least minTypes, the closest by level)
	scaling = {hpExp = 1.0, dmgExp = 0.4, xpExp = 0.8, minMult = 0.5, maxHp = 10, maxDmg = 2.5, maxXp = 6,
		rosterLow = 0.35, rosterHigh = 1.25, minTypes = 3},
	-- the boss: health = hpPerLevel x area level x player factor; damage scaled like the waves (boss level -> area
	-- level); it gets the legendary tier (modifiers and shader) and the client's boss frame
	boss = {hpPerLevel = 2500, minHealth = 40000, dmgExp = 0.6, minMult = 0.3, maxDmg = 2.5, xpMult = 3, tier = "legendary"},
	-- breach meter (percent): invaders within `radius` of the target point push it up, perInvader per second each
	-- (the boss counts bossWeight), at most maxPerSecond; it falls by decay per second while none is there. 100 = lost.
	breach = {radius = 2, perInvader = 0.25, bossWeight = 4, maxPerSecond = 1.5, decay = 0.25},

	-- ======================================================================= rewards (a defended invasion)
	-- score = damage dealt to invaders x damage + healing done to other players inside the area x healing
	--         + kills x kill x the average invader health (so a kill is worth a quarter of a monster)
	-- a player needs minPercent % of the total invader health in score to be rewarded
	contribution = {damage = 1.0, healing = 0.6, kill = 0.25, minPercent = 0.2},
	rewards = {
		goldBase = 200, goldPool = 8000, -- gold to the bank: area level x (goldBase + goldPool x share)
		base = {{id = 29856, count = 1}}, -- every rewarded player: 1 Orb of Upheaval
		pool = {{id = 29856, count = 20}, {id = 29857, count = 6}}, -- split by share: Orbs of Upheaval, Orbs of Fate
		top = { -- extras for the top 3
			{{id = 29857, count = 3}, {id = 29855, count = 1}},
			{{id = 29857, count = 2}},
			{{id = 29857, count = 1}}
		},
		-- a unique through the Chaos loot layer: chance per 10000 = uniqueChance + share x uniqueShareBonus; first the
		-- loot layer's own roll for the boss (boss tier), else any unique (not boss-only) up to area level + levelSlack
		uniqueChance = 100, uniqueShareBonus = 600, uniqueLevelSlack = 20,
		liberationMult = 0.25, -- clearing an occupied area pays this share of gold and orbs (no unique)
		-- weekly Defender board (leaderboard_config.lua "defender"): base + share x sharePoints per invasion
		defender = {base = 10, sharePoints = 100},
		mcReward = false -- multi-client characters (Chaos.isMultiClient) fight but get no reward
	},
	-- a won invasion: +10% experience for an hour, everywhere ("server") or inside the area only ("area")
	victory = {minutes = 60, xp = 1.10, scope = "server"},
	-- a lost one: the invaders occupy the area. The survivors stop pushing and get hpMult more health, a garrison of
	-- `garrison` rare / legendary invaders joins them at the target; they leave after `minutes` or when all are slain
	-- (the area is liberated: everyone who fought them gets liberationMult of the rewards). NPC shop prices are not
	-- changed (the NPC trade code is the base server's; see README).
	occupation = {minutes = 30, garrison = 6, garrisonTiers = {rare = 70, legendary = 30}, hpMult = 1.5},

	-- ======================================================================= factions
	-- monsters: existing monster types with their hunting level (bounty_pool.lua estimates). bosses: an existing
	-- boss look, renamed (rename) when given; the one with the highest level not above the area level is used.
	factions = {
		orcs = {name = "Orc Warband", color = "#7fb04a", monsters = {
			{name = "Orc", level = 8}, {name = "Orc Spearman", level = 10}, {name = "Orc Warrior", level = 11},
			{name = "Orc Shaman", level = 17}, {name = "Orc Rider", level = 17}, {name = "Orc Berserker", level = 22},
			{name = "Orc Marauder", level = 23}, {name = "Orc Leader", level = 26}, {name = "Orc Warlord", level = 41}
		}, bosses = {
			{name = "Orc Warlord", level = 41, rename = "Warchief Grashnak"}
		}},
		undead = {name = "Undead Legion", color = "#9ab0c8", monsters = {
			{name = "Skeleton", level = 9}, {name = "Ghoul", level = 15}, {name = "Mummy", level = 20},
			{name = "Zombie", level = 27}, {name = "Vampire", level = 28}, {name = "Grave Guard", level = 35},
			{name = "Bonebeast", level = 39}, {name = "Necromancer", level = 39}, {name = "Lich", level = 48},
			{name = "Banshee", level = 48}, {name = "Vampire Bride", level = 52}, {name = "Betrayed Wraith", level = 95},
			{name = "Lost Soul", level = 101}, {name = "Grim Reaper", level = 119}, {name = "Skeleton Elite Warrior", level = 130},
			{name = "Undead Elite Gladiator", level = 133}, {name = "Undead Dragon", level = 139}, {name = "Blightwalker", level = 148}
		}, bosses = {
			{name = "Dracola", level = 110, rename = "Dracola the Unburied"},
			{name = "The Pale Count", level = 200}
		}},
		demons = {name = "Infernal Host", color = "#e0603a", monsters = {
			{name = "Fire Devil", level = 19}, {name = "Fire Elemental", level = 24}, {name = "Demon Skeleton", level = 25},
			{name = "Destroyer", level = 80}, {name = "Diabolic Imp", level = 86}, {name = "Defiler", level = 97},
			{name = "Hellfire Fighter", level = 100}, {name = "Dark Torturer", level = 122}, {name = "Hellhound", level = 132},
			{name = "Juggernaut", level = 284}
		}, bosses = {
			{name = "Orshabaal", level = 150},
			{name = "Ghazbaran", level = 300}
		}},
		minotaurs = {name = "Minotaur Horde", color = "#c89a5a", monsters = {
			{name = "Minotaur", level = 11}, {name = "Minotaur Archer", level = 13}, {name = "Minotaur Guard", level = 20},
			{name = "Minotaur Mage", level = 20}, {name = "Mooh'Tah Warrior", level = 48}, {name = "Worm Priestess", level = 62},
			{name = "Minotaur Hunter", level = 66}, {name = "Minotaur Amazon", level = 75}, {name = "Execowtioner", level = 78},
			{name = "Moohtant", level = 82}
		}, bosses = {
			{name = "Bullwark", level = 250, rename = "Bullwark the Gorer"}
		}},
		-- the pack monsters (data/monster/monsters/chaos/goblins, wildwood; server/README.md "Pack items and monsters")
		goblins = {name = "Goblin Tribe", color = "#8fbf3f", monsters = {
			{name = "Goblin Grunt", level = 15}, {name = "Goblin Spearman", level = 18}, {name = "Goblin Archer", level = 18},
			{name = "Goblin Sneak", level = 20}, {name = "Goblin Bomber", level = 22}, {name = "Goblin Sapper", level = 22},
			{name = "Goblin Trapper", level = 24}, {name = "Goblin War-Drummer", level = 25}, {name = "Goblin Shaman", level = 28},
			{name = "Goblin Witch", level = 30}, {name = "Goblin Brute", level = 50}, {name = "Goblin Wolf Rider", level = 55},
			{name = "Hobgoblin Captain", level = 65}, {name = "Goblin Warlock", level = 70}
		}, bosses = {
			{name = "Goblin Chieftain", level = 80}
		}},
		wildwood = {name = "Wildwood Uprising", color = "#5fa860", monsters = {
			{name = "Forest Wolf", level = 10}, {name = "Shroomling", level = 12}, {name = "Wild Boar", level = 18},
			{name = "Giant Hornet", level = 20}, {name = "Morel Imp", level = 22}, {name = "Moss Slime", level = 22},
			{name = "Forest Pixie", level = 25}, {name = "Glowcap Cluster", level = 28}, {name = "Treant Sapling", level = 30},
			{name = "Inkcap Creeper", level = 32}, {name = "Myconid Shaman", level = 38}, {name = "Grove Dryad", level = 40},
			{name = "Dire Bear", level = 60}, {name = "Giant Thornback Toad", level = 65}, {name = "Owlbear", level = 70},
			{name = "Giant Forest Spider", level = 70}, {name = "Giant Stag Beetle", level = 75}, {name = "Snapjaw Flytrap", level = 80},
			{name = "Puffball Brute", level = 85}, {name = "Bracket Fungus Golem", level = 95}, {name = "Elk Guardian", level = 110},
			{name = "Mycelium Horror", level = 120}
		}, bosses = {
			{name = "Mushroom King", level = 100}, {name = "Ancient Treant", level = 140}
		}}
	},

	-- ======================================================================= areas
	-- key, name, kind ("town" / "hunt"), level (the area level the invaders are scaled to), the rectangle from/to on
	-- floor z, target (the point they push to: walkable, outside protection zones) and targetName, edges the waves
	-- come from (nil = all four), exclude = rectangles {x1, y1, x2, y2} where nothing spawns (temple surroundings),
	-- factions (nil = all), invasion = false / worldEvents = false to keep an area out of one of them,
	-- merchantSpots = fixed spots for the Wandering Merchant (else a random free tile of the area).
	-- The coordinates are for the real map (realmap): check them with `/invasion check <key>` on the live server.
	areas = {
		-- towns: the temple +- 45 tiles; the target is the first walkable tile outside the temple's protection zone
		{key = "thais", name = "Thais", kind = "town", level = 80, town = 2,
			from = {x = 32324, y = 32196}, to = {x = 32414, y = 32286}, z = 7,
			target = {x = 32365, y = 32245, z = 7}, targetName = "the temple steps"},
		{key = "carlin", name = "Carlin", kind = "town", level = 60, town = 4,
			from = {x = 32315, y = 31737}, to = {x = 32405, y = 31827}, z = 7,
			target = {x = 32355, y = 31782, z = 7}, targetName = "the temple steps"},
		-- Venore: its streets are bridges over water, split into small pieces (no long walkable way from the border to
		-- the temple was found in the map file); enable it only after `/invasion check venore` on the live map
		{key = "venore", name = "Venore", kind = "town", level = 120, town = 1, enabled = false,
			from = {x = 32912, y = 32031}, to = {x = 33002, y = 32121}, z = 7,
			target = {x = 32959, y = 32069, z = 7}, targetName = "the temple bridge", edges = {"south", "east"}},
		-- hunting grounds
		{key = "thaisfields", name = "the Thais fields", kind = "hunt", level = 150,
			from = {x = 32290, y = 32292}, to = {x = 32400, y = 32338}, z = 7,
			target = {x = 32345, y = 32315, z = 7}, targetName = "the old crossroads"},
		{key = "carlinwilds", name = "the Carlin wilds", kind = "hunt", level = 100,
			from = {x = 32300, y = 31685}, to = {x = 32440, y = 31735}, z = 7,
			target = {x = 32370, y = 31710, z = 7}, targetName = "the hunters' camp"}
	},

	-- ======================================================================= small world events (worldevents.lua)
	worldEvents = {
		enabled = true,
		firstMinutes = {20, 60}, -- first one after a (re)start
		intervalMinutes = {120, 240}, -- gap between two events
		quietMinutes = 45, -- no world event within this of an invasion start
		storm = {weight = 40, minutes = 15, tierMult = 3.0, -- magic / rare / legendary spawn chance x3 in the area
			effectSeconds = 2, -- lightning around the players inside
			name = "Chaos Storm"},
		golden = {weight = 30, minutes = 30, lootMult = 1.25, name = "Golden Hour"}, -- loot_config.lua rateMult x1.25
		merchant = {weight = 30, minutes = 20, name = "Wandering Merchant", npc = "Wandering Merchant",
			kinds = {"town"}, -- only in town areas
			-- what the NPC sells (gold): orbs and rare consumables a little below the usual value
			items = {
				{id = 29856, price = 40000, name = "orb of upheaval"},
				{id = 29857, price = 120000, name = "orb of fate"},
				{id = 29855, price = 200000, name = "orb of grafting"},
				{id = 24691, price = 60000, name = "orb of gilding"},
				{id = 24697, price = 80000, name = "orb of unmaking"},
				{id = 28095, price = 350000, name = "double experience potion"},
				{id = 26031, price = 900, name = "supreme health potion"}
			}}
	}
}
