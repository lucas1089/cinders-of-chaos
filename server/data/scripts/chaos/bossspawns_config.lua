-- Boss spawns tracker: the list of bosses, their category, place and respawn rule (bossspawns.lua, pure logic in
-- bossspawns_core.lua, client game_bossspawns). Returned as a table; loaded as Chaos.bossSpawnsConfig. Plain data,
-- Lua 5.1 / LuaJIT and Lua 5.3. Overview: server/README.md "Boss spawns".
--
-- Some categories are not listed here but read from the system that owns them, so they never drift:
--   world bosses      Chaos.worldBoss.bosses (chaos_constants.lua), rotation slots every intervalHours
--   invasion bosses   invasion_config.lua factions[*].bosses (the boss of an invasion depends on area and faction)
--   tower bosses      infinitytower_run.lua bosses (ChaosTowerRunConfig), one every bossEvery floors
--   trial bosses      trials_config.lua families[*].boss and ascension_quest_config.lua (the Ascension Warden)
--   dungeon bosses    Chaos.dungeons.extra[id].bossName + the base server DUNGEON_SYSTEM (level, entrance, cooldown)
--
-- Rules (rule.type):
--   rotation  the world boss event: a fixed time slot, the boss of each slot by the rotation (worldboss.lua)
--   weekly    times = {{day = 1..7 (1 = Sunday), hour, min}}: the base server's weekly island bosses
--   timer     seconds: a map spawn, back this long after its death (the engine waits while a player can see the spot)
--   raid      interval, margin (minutes): a base server raid (data/raids/raids.xml). The engine rolls every raid once a
--             minute with chance 1 / interval once `margin` minutes passed since the last raid of any kind ended, so
--             it comes back on average every `interval` minutes. The values are read again from raids.xml at startup.
--   invasion  the boss of the last wave of an invasion (scheduled and surprise invasions, invasion_config.lua)
--   ondemand  how = text: opened by the player (key, queue, NPC); cooldown = per-character wait read from a storage
-- short = the rule in a few words (the window's status column, about 24 characters); the full text is the tooltip
--   chance    text: a rare random spawn (treasure goblins)
--
-- Where (kill tracking): a spawn or death of a monster TYPE named `monster` counts for an entry when it is within
-- `radius` sqm (and 1 floor) of `pos`, or anywhere with anywhere = true. Entries without `monster` are not tracked.
-- loc = nil: the window shows "near <closest town>" from the temples of Game.getTowns(). note = the line under the place
-- when there are no coordinates to show.
return {
	enabled = true,

	-- persistence of the last kill of every boss (sql/chaos_boss_spawns.sql; bossspawns.lua also creates it)
	table = "chaos_boss_spawns",
	-- the client asks again this often while the window is open (seconds) and no faster than requestMs
	refreshSeconds = 30,
	requestMs = 1000,
	radius = 40, -- default tracking radius around `pos`
	-- a spawn found within this many sqm of the spawn point after the onSpawn callback (the creature id exists only
	-- once the engine has placed it)
	scanRadius = 3,

	categories = {
		{key = "world", name = "World Bosses", color = "#e8b84a",
			text = "Server event: portals at every temple."},
		{key = "island", name = "Island Bosses", color = "#4fb0c6",
			text = "Once a week each; they stay until slain."},
		{key = "raid", name = "Raid Bosses", color = "#e03a1e",
			text = "Random raids, rolled once a minute."},
		{key = "lair", name = "Lair Bosses", color = "#b070ff",
			text = "Map spawns, back a fixed time after the kill."},
		{key = "invasion", name = "Invasion Bosses", color = "#c8402a",
			text = "The last wave; the area level picks the boss."},
		{key = "omen", name = "Rift Guardians and Omens", color = "#9b59d6",
			text = "Rift Keys; 60 Omen Fragments bind an Omen Key."},
		{key = "ascended", name = "Ascended Omens", color = "#ff6a3a",
			text = "4 Ascended Shards bind a sigil; three relics wake the Cinderheart."},
		{key = "dungeon", name = "Dungeon Bosses", color = "#d6a050",
			text = "Adventure > Dungeons: queue alone or with a party."},
		{key = "tower", name = "Infinity Tower Bosses", color = "#2f9fd0",
			text = "Every 10th floor of the Infinity Tower holds a boss."},
		{key = "trial", name = "Trial and Quest Bosses", color = "#6fd8a8",
			text = "Personal fights, alone."},
		{key = "rare", name = "Rare Spawns", color = "#f6cf72",
			text = "May replace any natural respawn while you hunt."},
		{key = "descent", name = "The Ember Descent", color = "#ff7a2a",
			text = "A roguelike trial: 8-12 rooms, the boss in the last."},
		{key = "sepulchre", name = "The Ashen Sepulchre (Raid)", color = "#c8503a",
			text = "Weekly raid for 5-15: each boss's loot once a week per character."},
		{key = "guild", name = "Guild Boss", color = "#d89a3a",
			text = "Summoned in the guild hall with the guild's fuel: one kill per guild and week."}
	},

	-- read from the systems above (false = leave that category out)
	sources = {worldBoss = true, invasion = true, tower = true, trials = true, ascension = true, dungeons = true},

	-- world boss arena centre (Chaos.worldBoss.arena origin + (inner + 1) / 2)
	worldBoss = {loc = "World Boss Arena", note = "Portals at every temple", level = 300},
	invasion = {loc = "Cinderhold or Thornmere", note = "or nearby hunting grounds"},
	tower = {loc = "Infinity Tower", note = "Adventure > Infinity Tower", how = "Infinity Tower floor %s (Adventure > Infinity Tower)"},
	trials = {loc = "Keeper of Trials", note = "In the Hall of Services", how = "Vocation Trial of your class line (Passive Tree > Trials)",
		cooldownStorage = 7101764},
	ascension = {name = "Ascension Warden", monster = "Ascension Warden", loc = "Ascendant Oracle",
		note = "In the Hall of Services", level = 100,
		how = "Ascension Trial (Ascendant Oracle)", short = "Ascension Trial", cooldownStorage = 7101002, look = {type = 131, head = 95, body = 95,
		legs = 95, feet = 95, addons = 3}},
	dungeons = {how = "Dungeon queue (Adventure > Dungeons)", short = "Dungeon queue",
		-- shown until DUNGEON_SYSTEM is read (names and levels of the base server's dungeons)
		defaults = {
			[1] = {name = "Prince Skeletal", level = 150},
			[2] = {name = "Master of the Elements", level = 200},
			[3] = {name = "Forbidden Chevalier", level = 500},
			[4] = {name = "The Rootmaw", level = 600}
		}},

	bosses = {
		-- ------------------------------------------------------------------ island bosses (base server weekly timer,
		-- data/scripts/customs/worldbosses/world_boss_timer.lua; they spawn only if the last one is gone)
		{key = "dreadscale", category = "island", name = "Dreadscale the Ancient", monster = "Dreadscale The Ancient",
			loc = "Dreadscale Island", pos = {x = 32314, y = 31524, z = 9}, rule = {type = "weekly", times = {{day = 1, hour = 0, min = 0}}}},
		{key = "thalassa", category = "island", name = "Aquatic Overlord Thalassa", monster = "Aquatic Overlord Thalassa",
			loc = "Thalassa Island", pos = {x = 33239, y = 32096, z = 9}, rule = {type = "weekly", times = {{day = 2, hour = 16, min = 0}}}},
		{key = "drakthul", category = "island", name = "Drak'thul the Void Sovereign", monster = "Drak'thul The Void Sovereign",
			loc = "Sovereign Island", pos = {x = 32912, y = 31386, z = 10}, rule = {type = "weekly", times = {{day = 3, hour = 20, min = 0}}}},
		{key = "thalador", category = "island", name = "Thalador the Stormbringer", monster = "Thalador The Stormbringer",
			loc = "Thalador Island", pos = {x = 31985, y = 31984, z = 5}, rule = {type = "weekly", times = {{day = 4, hour = 20, min = 0}}}},
		{key = "vorondor", category = "island", name = "Vorondor the Eternal Flames", monster = "Vorondor The Eternal Flames",
			loc = "Eternal Island", pos = {x = 32973, y = 31944, z = 7}, rule = {type = "weekly", times = {{day = 5, hour = 20, min = 0}}}},
		{key = "azazel", category = "island", name = "Azazel the Infernal Seraph", monster = "Azazel The Infernal Seraph",
			loc = "Azazel Island", pos = {x = 33400, y = 31730, z = 6}, rule = {type = "weekly", times = {{day = 6, hour = 20, min = 0}}}},
		{key = "mortis", category = "island", name = "Mortis the Sovereign", monster = "Mortis The Sovereign",
			loc = "Horror Island", pos = {x = 32964, y = 30960, z = 8}, rule = {type = "weekly", times = {{day = 7, hour = 12, min = 0}}}},
		{key = "dreadbone", category = "island", name = "Dreadbone the Eternal", monster = "Dreadbone The Eternal",
			loc = "Horror Island", pos = {x = 32966, y = 30960, z = 8}, rule = {type = "weekly", times = {{day = 7, hour = 12, min = 0}}}},
		{key = "tymagron", category = "island", name = "Tymagron the Earthshaker", monster = "Tymagron The Earthshaker",
			loc = "Earthshaker Island", pos = {x = 32260, y = 31287, z = 7}, rule = {type = "weekly", times = {{day = 7, hour = 20, min = 0}}}},
		-- the monster file spells it "Frienzied"
		{key = "gorgul", category = "island", name = "Gor'gul the Frenzied", monster = "Gor'gul The Frienzied",
			loc = "Gor'gul Island", pos = {x = 32573, y = 31005, z = 9}, rule = {type = "weekly", times = {{day = 1, hour = 20, min = 0}}}},

		-- ------------------------------------------------------------------ raid bosses (base server data/raids/raids.xml;
		-- interval / margin and the position are taken from the installed files at startup)
		{key = "raid_vhalkareth", category = "raid", name = "Vhalkareth", monster = "Vhalkareth", loc = "Saltgrave",
			pos = {x = 32124, y = 32687, z = 4}, rule = {type = "raid", interval = 1440, margin = 120}},
		{key = "raid_vharagoth", category = "raid", name = "Vharagoth", monster = "Vharagoth", loc = "Saltgrave",
			pos = {x = 32063, y = 32612, z = 14}, rule = {type = "raid", interval = 1440, margin = 90}},
		{key = "raid_seriel", category = "raid", name = "Seriel the Fair", monster = "Seriel the Fair", loc = "Saltgrave",
			pos = {x = 32009, y = 32795, z = 10}, rule = {type = "raid", interval = 1440, margin = 180}},
		{key = "raid_morgashal", category = "raid", name = "Morgashal", monster = "Morgashal", loc = "Bellwatch",
			pos = {x = 33118, y = 31699, z = 7}, rule = {type = "raid", interval = 1440, margin = 100}},
		{key = "raid_valorcrest", category = "raid", name = "Sir Valorcrest", monster = "Sir Valorcrest", loc = "Bellwatch",
			pos = {x = 33264, y = 31768, z = 10}, rule = {type = "raid", interval = 1440, margin = 120}},
		{key = "raid_vargra", category = "raid", name = "Vargra", monster = "Vargra", loc = "Bellwatch",
			pos = {x = 33389, y = 31539, z = 11}, rule = {type = "raid", interval = 430, margin = 81}},
		{key = "raid_madmage", category = "raid", name = "Mad Mage", monster = "Mad Mage", loc = "Bellwatch",
			pos = {x = 33360, y = 31873, z = 9}, rule = {type = "raid", interval = 360, margin = 30}},
		{key = "raid_slurgoth", category = "raid", name = "Weakened Slurgoth", monster = "Weakened Slurgoth", loc = "Bellwatch",
			pos = {x = 33164, y = 31716, z = 9}, rule = {type = "raid", interval = 430, margin = 50}},
		{key = "raid_moloveth", category = "raid", name = "Moloveth", monster = "Moloveth", loc = "Rimeholt",
			pos = {x = 32228, y = 31163, z = 15}, rule = {type = "raid", interval = 1440, margin = 100}},
		{key = "raid_ishkara", category = "raid", name = "Ishkara", monster = "Ishkara", loc = "Rimeholt",
			pos = {x = 31941, y = 31388, z = 9}, rule = {type = "raid", interval = 6000, margin = 60}},
		{key = "raid_ulthazmor", category = "raid", name = "Ul'thazmor", monster = "Ul'thazmor", loc = "Nightwrack",
			pos = {x = 33538, y = 32381, z = 12}, rule = {type = "raid", interval = 1440, margin = 160}},
		{key = "raid_kazmorath", category = "raid", name = "Kazmorath", monster = "Kazmorath", loc = "Nightwrack",
			pos = {x = 33587, y = 32378, z = 12}, rule = {type = "raid", interval = 1440, margin = 80}},
		{key = "raid_gorehawk", category = "raid", name = "Gorehawk", monster = "Gorehawk", loc = "Nightwrack",
			pos = {x = 33704, y = 32461, z = 7}, rule = {type = "raid", interval = 410, margin = 20}},
		{key = "raid_ssylvath", category = "raid", name = "Ssylvath the Corruptor", monster = "Ssylvath the Corruptor",
			loc = "Slagdelve", pos = {x = 33348, y = 31609, z = 1}, rule = {type = "raid", interval = 1440, margin = 60}},
		{key = "raid_vizzaroth", category = "raid", name = "Vizzaroth the Warper", monster = "Vizzaroth the Warper",
			loc = "Slagdelve", pos = {x = 33344, y = 31605, z = 4}, rule = {type = "raid", interval = 1440, margin = 60}},
		{key = "raid_morvain", category = "raid", name = "Morvain Duskbringer", monster = "Morvain Duskbringer", loc = "Slagdelve",
			pos = {x = 32754, y = 31578, z = 11}, rule = {type = "raid", interval = 1440, margin = 90}},
		{key = "raid_ashencount", category = "raid", name = "The Ashen Count", monster = "The Ashen Count", loc = "Scorchveil",
			pos = {x = 32969, y = 32420, z = 15}, rule = {type = "raid", interval = 490, margin = 60}},
		{key = "raid_mortivex", category = "raid", name = "Mortivex", monster = "Mortivex", loc = "Scorchveil",
			pos = {x = 33044, y = 32401, z = 10}, rule = {type = "raid", interval = 1440, margin = 110}},
		{key = "raid_skarn", category = "raid", name = "Skarn", monster = "Skarn", loc = "Scorchveil",
			pos = {x = 33094, y = 32404, z = 13}, rule = {type = "raid", interval = 1440, margin = 50}},
		{key = "raid_vasrael", category = "raid", name = "Vasrael the Ancient One", monster = "Vasrael the Ancient One",
			loc = "Scorchveil", pos = {x = 32965, y = 32400, z = 12}, rule = {type = "raid", interval = 1440, margin = 80}},
		{key = "raid_greywidow", category = "raid", name = "The Grey Widow", monster = "The Grey Widow", loc = "Mirewake",
			pos = {x = 32776, y = 32296, z = 7}, rule = {type = "raid", interval = 1440, margin = 60}},
		{key = "raid_briarfang", category = "raid", name = "Briarfang", monster = "Briarfang", loc = "Mirewake",
			pos = {x = 32851, y = 32337, z = 6}, rule = {type = "raid", interval = 1440, margin = 80}},
		{key = "raid_elyndral", category = "raid", name = "Elyndral", monster = "Elyndral", loc = "Mirewake",
			pos = {x = 33038, y = 32176, z = 9}, rule = {type = "raid", interval = 500, margin = 70}},
		{key = "raid_coilwyrm", category = "raid", name = "The Coilwyrm", monster = "The Coilwyrm", loc = "Fevergate",
			pos = {x = 33026, y = 32660, z = 5}, rule = {type = "raid", interval = 440, margin = 60}},
		{key = "raid_ashenfox", category = "raid", name = "The Ashen Fox", monster = "the Ashen Fox", loc = "Anvildeep",
			pos = {x = 32463, y = 31954, z = 4}, rule = {type = "raid", interval = 1440, margin = 180}},

		-- ------------------------------------------------------------------ lair bosses (the real map's spawn file,
		-- spawntime in seconds; positions = spawn centre + offset)
		{key = "lair_apocalypse", category = "lair", name = "Apocalypse", monster = "Apocalypse",
			pos = {x = 32314, y = 31932, z = 6}, radius = 12, rule = {type = "timer", seconds = 60}},
		{key = "lair_ulthazmor", category = "lair", name = "Ul'thazmor", monster = "Ul'thazmor",
			pos = {x = 32322, y = 31932, z = 6}, radius = 12, rule = {type = "timer", seconds = 60}},
		{key = "lair_vhalkareth", category = "lair", name = "Vhalkareth Mortal Shell", monster = "Vhalkareth Mortal Shell",
			pos = {x = 31691, y = 32815, z = 15}, radius = 20, rule = {type = "timer", seconds = 120}},
		{key = "lair_morgashal", category = "lair", name = "Morgashal", monster = "Morgashal",
			pos = {x = 31663, y = 32758, z = 12}, radius = 20, rule = {type = "timer", seconds = 120}},
		{key = "lair_pyrevorn", category = "lair", name = "Pyrevorn", monster = "Pyrevorn", count = 3,
			pos = {x = 31702, y = 32841, z = 15}, radius = 12, rule = {type = "timer", seconds = 120}},
		{key = "lair_obliterath", category = "lair", name = "Obliterath", monster = "Obliterath", loc = "Inquisition throne halls",
			pos = {x = 33197, y = 31690, z = 11}, radius = 12, rule = {type = "timer", seconds = 60}},
		{key = "lair_kharnoth", category = "lair", name = "Kharnoth", monster = "Kharnoth", loc = "Inquisition throne halls",
			pos = {x = 33104, y = 31722, z = 11}, radius = 12, rule = {type = "timer", seconds = 60}},
		{key = "lair_velgoroth", category = "lair", name = "Velgoroth", monster = "Velgoroth", loc = "Inquisition throne halls",
			pos = {x = 33236, y = 31728, z = 11}, radius = 6, rule = {type = "timer", seconds = 60}},
		{key = "lair_morvatan", category = "lair", name = "Morvatan", monster = "Morvatan", loc = "Inquisition throne halls",
			pos = {x = 33228, y = 31728, z = 11}, radius = 6, rule = {type = "timer", seconds = 60}},
		{key = "lair_maldrith", category = "lair", name = "Maldrith", monster = "Maldrith", loc = "Inquisition throne halls",
			pos = {x = 33197, y = 31757, z = 11}, radius = 12, rule = {type = "timer", seconds = 60}},
		{key = "lair_asmorel", category = "lair", name = "Asmorel", monster = "Asmorel", loc = "Inquisition throne halls",
			pos = {x = 33166, y = 31728, z = 11}, radius = 12, rule = {type = "timer", seconds = 60}},
		{key = "lair_ghorzuul", category = "lair", name = "Ghorzuul", monster = "Ghorzuul", loc = "Inquisition throne halls",
			pos = {x = 33139, y = 31692, z = 11}, radius = 12, rule = {type = "timer", seconds = 60}},
		{key = "lair_koshei", category = "lair", name = "Koshei the Deathless", monster = "Koshei The Deathless",
			pos = {x = 33271, y = 32406, z = 12}, radius = 12, rule = {type = "timer", seconds = 15}},
		{key = "lair_collector", category = "lair", name = "The Collector", monster = "The Collector",
			pos = {x = 32028, y = 31817, z = 8}, radius = 12, rule = {type = "timer", seconds = 60}},
		{key = "lair_tibb", category = "lair", name = "Tibb the Butcher", monster = "Tibb the Butcher", loc = "Orc fortress",
			pos = {x = 32622, y = 31826, z = 7}, radius = 20, rule = {type = "timer", seconds = 3600}},

		-- ------------------------------------------------------------------ rifts and omens (rift_config.lua)
		{key = "rift_guardian", category = "omen", name = "Rift Guardian", loc = "Rift (instance)", level = 100,
			look = {type = 2103}, rule = {type = "ondemand", how = "Rift Key, any tier: the guardian comes at 75% of the rift slain",
			short = "Any Rift Key"}},
		{key = "omen_sangrith", category = "omen", name = "Sangrith the Bloodmoon Herald", monster = "Sangrith the Bloodmoon Herald",
			anywhere = true, loc = "Omen arena (instance)", level = 800, rule = {type = "ondemand", how = "Bloodmoon Omen Key", short = "Bloodmoon Omen Key"}},
		{key = "omen_morvane", category = "omen", name = "Morvane the Hollow Crown", monster = "Morvane the Hollow Crown",
			anywhere = true, loc = "Omen arena (instance)", level = 800, rule = {type = "ondemand", how = "Hollow Omen Key", short = "Hollow Omen Key"}},
		{key = "omen_thalcyra", category = "omen", name = "Thalcyra the Stormbound Seer", monster = "Thalcyra the Stormbound Seer",
			anywhere = true, loc = "Omen arena (instance)", level = 800, rule = {type = "ondemand", how = "Stormcall Omen Key", short = "Stormcall Omen Key"}},

		-- ------------------------------------------------------------------ Ascended Omens and the Cinderheart (uber_config.lua)
		{key = "ascended_sangrith", category = "ascended", name = "Ascended Sangrith", monster = "Ascended Sangrith",
			anywhere = true, loc = "Ascended arena (instance)", level = 900, rule = {type = "ondemand",
			how = "Ascended Sigil of the Bloodmoon (4 shards from Bloodmoon Omen kills and tier 13+ rifts)", short = "Bloodmoon Sigil"}},
		{key = "ascended_morvane", category = "ascended", name = "Ascended Morvane", monster = "Ascended Morvane",
			anywhere = true, loc = "Ascended arena (instance)", level = 900, rule = {type = "ondemand",
			how = "Ascended Sigil of the Hollow Crown (4 shards from Hollow Omen kills and tier 13+ rifts)", short = "Hollow Crown Sigil"}},
		{key = "ascended_thalcyra", category = "ascended", name = "Ascended Thalcyra", monster = "Ascended Thalcyra",
			anywhere = true, loc = "Ascended arena (instance)", level = 900, rule = {type = "ondemand",
			how = "Ascended Sigil of the Storm (4 shards from Stormcall Omen kills and tier 13+ rifts)", short = "Storm Sigil"}},
		{key = "ascended_cinderheart", category = "ascended", name = "Ysgrath the Cinderheart", monster = "Ysgrath the Cinderheart",
			anywhere = true, loc = "Ascended arena (instance)", level = 1000, rule = {type = "ondemand",
			how = "Cinderheart Sigil: one relic of each Ascended Omen", short = "Cinderheart Sigil"}},

		-- ------------------------------------------------------------------ the Ember Descent (descent_config.lua)
		-- its boss is the strongest monster type of the last room's level window in the rift guardian look of the room's
		-- theme, so it has no fixed type to track; the cooldown column shows when the free run of the day is ready
		{key = "descent_boss", category = "descent", name = "Ember Descent Boss", loc = "Ember Descent (instance)", level = 100,
			look = {type = 2107}, rule = {type = "ondemand", how = "The portal in the Hall of Services (beside the temple): one free run a day, " ..
			"one free weekly run, more with Ember Sigils", short = "Descent portal", cooldown = 7100411}},

		-- ------------------------------------------------------------------ the Ashen Sepulchre (raid_config.lua)
		-- the raid's bosses in order; the cooldown column shows the weekly loot lockout of the character (storage
		-- 7100441 + boss index - 1: the time of the reset while the boss is looted this week)
		{key = "raid_ulthar", category = "sepulchre", name = "Gravewarden Ulthar", monster = "Gravewarden Ulthar", anywhere = true,
			loc = "Ashen Sepulchre (raid)", level = 800, rule = {type = "ondemand",
			how = "The raid portal in the Hall of Services (beside the temple), a party of 5-15; loot once a week", short = "Raid, weekly loot",
			cooldown = 7100441}},
		{key = "raid_morwen", category = "sepulchre", name = "Morwen the Ash-Sister", monster = "Morwen the Ash-Sister",
			anywhere = true, loc = "Ashen Sepulchre (raid)", level = 800, rule = {type = "ondemand",
			how = "The raid's second boss; loot once a week", short = "Raid, weekly loot", cooldown = 7100442}},
		{key = "raid_colossus", category = "sepulchre", name = "The Marrow Colossus", monster = "The Marrow Colossus",
			anywhere = true, loc = "Ashen Sepulchre (raid)", level = 800, rule = {type = "ondemand",
			how = "The raid's third boss; loot once a week", short = "Raid, weekly loot", cooldown = 7100443}},
		{key = "raid_hexmaw", category = "sepulchre", name = "Vhoss the Hexmaw", monster = "Vhoss the Hexmaw", anywhere = true,
			loc = "Ashen Sepulchre (raid)", level = 800, rule = {type = "ondemand",
			how = "The raid's fourth boss; loot once a week", short = "Raid, weekly loot", cooldown = 7100444}},
		{key = "raid_sovereign", category = "sepulchre", name = "Varkhul the Ashen Sovereign", monster = "Varkhul the Ashen Sovereign",
			anywhere = true, loc = "Ashen Sepulchre (raid)", level = 800, rule = {type = "ondemand",
			how = "The raid's last boss; loot once a week", short = "Raid, weekly loot", cooldown = 7100445}},

		-- ------------------------------------------------------------------ the weekly guild boss (guildboss_config.lua)
		-- on demand at the Summoning Stone of a guild hall; the cooldown column shows the guild's weekly lockout (storage
		-- 7101302 = Chaos.storage.guildBossLockout: the next reset while the character's guild has its kill this week)
		{key = "guild_gorvath", category = "guild", name = "Gorvath the Banner-Eater", monster = "Gorvath the Banner-Eater",
			anywhere = true, loc = "Guild boss arena", level = 150, rule = {type = "ondemand",
			how = "The Summoning Stone in your guild hall, fuelled by the members; one kill per guild and week",
			short = "Guild, weekly", cooldown = 7101302}},

		-- ------------------------------------------------------------------ rare spawns (treasure_goblin_config.lua)
		{key = "treasure_goblin", category = "rare", name = "Treasure Goblin", monster = "Treasure Goblin", anywhere = true,
			loc = "Any hunting ground", rule = {type = "chance", text = "1 in 3000 natural respawns (Treasure Goblin Chance raises it), 3 at most",
			short = "1 in 3000 respawns"}}
	}
}
