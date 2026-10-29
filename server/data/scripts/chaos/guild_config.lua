-- Guild levels and guild halls: every number (guild.lua, guild_hall.lua, guild_core.lua). Loaded with
--     Chaos.guildConfig = dofile("data/scripts/chaos/guild_config.lua")
-- Overview: server/README.md "Guild levels and guild halls". Lua 5.1 / LuaJIT compatible. Item ids are SERVER ids.

return {
	-- ------------------------------------------------------------------ guild level
	maxLevel = 20,
	-- guild XP (GXP) from level L to L + 1 = round(curve.base * L ^ curve.power / curve.round) * curve.round
	-- (L 1: 300, L 5: 3,350, L 10: 9,490, L 19: 24,850; 5,110 GXP to level 5, 33,320 to 10, 201,410 to 20)
	curve = {base = 300, power = 1.5, round = 10},

	-- where guild XP comes from. Member contributions are counted per member and day (chaos_guild_contrib).
	sources = {
		-- 1% of the experience a member gains from monsters, counted in "levels": a full level's worth of experience
		-- (at the member's level) gives levelUnit x share = 10 GXP. At most dailyCap GXP per member and day.
		exp = {share = 0.01, levelUnit = 1000, dailyCap = 60},
		-- ChaosLeaderboard.record(board, player, value): GXP per call = flat + perValue x value, at most max
		-- (bounty: per contract; rift: value = tier; worldboss: one call per rewarded participant; siege: value =
		-- the participant's points; goblin: per kill; defender: per rewarded defender of an invasion (invasion.lua);
		-- invasion*: any later board whose key starts with "invasion")
		boards = {
			bounty = {flat = 15},
			rift = {flat = 10, perValue = 2, max = 40},
			worldboss = {flat = 40, max = 40},
			siege = {flat = 10, perValue = 0.02, max = 40},
			goblin = {flat = 5},
			defender = {flat = 20, stat = "invasion"},
			invasion = {flat = 20, prefix = true, stat = "invasion"}
		},
		-- once per guild and siege (rows of chaos_siege_results): the bracket winner / every other guild that fought
		siegeResult = {winner = 500, others = 150},
		dailyCapAll = 400 -- GXP per member and day from all sources together (exp included)
	},

	-- ------------------------------------------------------------------ perks (online members, while in the guild)
	-- Each entry adds to the guild's perks from that level on. Totals are clamped by `caps`.
	perks = {
		{level = 2, xp = 1},
		{level = 3, scroll = true},
		{level = 4, loot = 2},
		{level = 5, hall = true},
		{level = 6, xp = 1},
		{level = 7, respec = 10},
		{level = 8, depotSlots = 20},
		{level = 9, loot = 2},
		{level = 10, aura = true, xp = 1},
		{level = 12, respec = 5},
		{level = 13, depotSlots = 20},
		{level = 14, xp = 1},
		{level = 15, loot = 1},
		{level = 17, respec = 5},
		{level = 18, depotSlots = 20},
		{level = 20, xp = 1}
	},
	caps = {xp = 5, loot = 5, respec = 20, depotSlots = 60}, -- percent, percent, percent off, extra depot entries
	scroll = {itemId = 6119, actionId = 47601, uses = 1, perDay = 1}, -- guild hall scroll (one per member per day)
	aura = {id = 4}, -- data/XML/auras.xml (4 = Fireflies), given while the member's guild is at the aura level

	-- ------------------------------------------------------------------ guild bank (gold of the guild)
	bank = {
		minDeposit = 1000,
		depositRank = 1, -- every member may deposit
		withdrawRank = 3 -- only the leader may withdraw (to the leader's bank balance)
	},

	-- ------------------------------------------------------------------ guild hall
	hall = {
		level = 5, -- guild level needed to buy one (the `hall` perk)
		cost = 5000000, -- gold, from the guild bank or the leader's own money (carried, then bank)
		buyRank = 3, -- the leader buys
		upgradeRank = 2, -- the leader and vice-leaders buy upgrades and pay the rent
		-- weekly upkeep: base + perTier x every upgrade tier owned. Paid from the guild bank when due; if the bank is
		-- short the hall goes into `graceHours`, then the upgrades lock until the rent is paid (nothing is deleted)
		rent = {base = 300000, perTier = 100000, periodDays = 7, graceHours = 24},

		-- slots: built with Game.createTile where the real map has no tiles (checked in the OTBM: no tile area between
		-- x/y 3000 and 16000 except 4352 / 5632 x 1790; other runtime areas: tower 2000+, tutorial 4600+,
		-- world boss 5000+, siege 5100+, PvP arena 6000+, rifts 8192-8447)
		origin = {x = 9216, y = 9216, z = 7},
		columns = 8, stride = 40, maxSlots = 64,
		inner = {w = 21, h = 15}, -- inner floor size (walls around it)

		-- entry: the Guild Hall Portal of every town, placed by cityportals.lua (cityportals_config.lua: the Hall of
		-- Services' portal room in Cinderhold and Mirewake, a fixed spot next to every other temple; these offsets only
		-- when neither is free), or at fixed positions ({x, y, z, town?}; set: replaces all of that)
		portalPositions = {},
		portalOffsets = {{3, -2}, {-3, -2}, {3, 2}, {-3, 2}, {4, 0}, {-4, 0}, {0, 4}, {0, -4}},
		exitPosition = nil, -- where the hall's exit forcefield leads ({x, y, z}); nil = the player's temple

		ids = {
			portal = 1387, -- magic forcefield (teleport type), used without destination + action id
			wall = 5648, -- stone wall (tier 0)
			ground = 413, -- stone floor (tier 0)
			basin = 1481, -- coal basin (light)
			flag = 1436, -- castle flag
			bench = 2555, -- anvil: the crafting bench
			depot = 1750, -- large trunk: the Guild Stash
			dummies = {27751, 27752}, -- exercise dummies of the base server (work with the store's exercise weapons)
			trophies = {1444, 1445, 1444, 1445} -- hero statue, monument: their look text is the trophy
		},
		dummyMonsters = {"Chaos Dummy", "Training Dummy"}, -- the first one this server knows stands in the training room
		aid = {enter = 47602, exit = 47603, hub = 47604, bench = 47605, depot = 47606, trophy = 47607, hubBack = 47616},

		-- teleport hub destinations (hunting areas). The positions are spawn centres of the late-game areas
		-- (tools/late_game_spawns.csv); the player lands on the nearest free walkable tile within 3 tiles, and a
		-- destination without one is refused. Put the areas' real entrances here before going live.
		-- `back`: the way back (owner, 2026-10-21: "every hunt reachable by a hub teleport needs a way back"). At startup
		-- guild_hall.lua puts a magic forcefield (ids.portal, action id aid.hubBack) there: a member of a guild with a
		-- hall steps into the hall's arrival, anyone else into the temple. Chosen on the installed map with the hunt
		-- hall's rule (tools/check_hunt_returns.py pick_return_tile, radius 4: reached on foot from the landing tile,
		-- free, not splitting a corridor); tools/check_hub_destinations.py checks them.
		hub = {
			{name = "Nightglass Core", pos = {x = 34206, y = 31047, z = 11}, level = 650, back = {x = 34206, y = 31046, z = 11}},
			{name = "Putrefactory", pos = {x = 34058, y = 31145, z = 11}, level = 700, back = {x = 34059, y = 31144, z = 11}},
			{name = "Jaded Roots", pos = {x = 34334, y = 31208, z = 9}, level = 800, back = {x = 34333, y = 31207, z = 9}},
			{name = "Gloom Pillars", pos = {x = 34494, y = 31257, z = 9}, level = 900, back = {x = 34493, y = 31258, z = 9}}
		},

		-- upgrades: key -> tiers (most have one). level = guild level needed, requires = other upgrades first
		upgrades = {
			{key = "hub", name = "Teleport Hub", info = "Portals to the hunting areas.",
				tiers = {{level = 6, cost = 2000000}}},
			{key = "training", name = "Training Room", info = "Exercise dummies (store exercise weapons) and a dummy to test your damage on.",
				tiers = {{level = 7, cost = 1500000}}},
			{key = "crafting", name = "Crafting Bench", info = "An anvil that opens the crafting bench.",
				tiers = {{level = 8, cost = 1000000}}},
			{key = "depot", name = "Guild Stash", info = "A chest shared by the members, with a log of who put in and took out what.",
				tiers = {{level = 9, cost = 2500000}}},
			{key = "trophy", name = "Trophy Room", info = "Statues with the guild's siege wins, world bosses and records.",
				tiers = {{level = 10, cost = 1000000, requires = {"hub"}}}},
			{key = "decor", name = "Decoration", info = "Floors and walls of the hall change look.",
				tiers = {{level = 12, cost = 1500000, requires = {"trophy"}}, {level = 16, cost = 3000000}, {level = 20, cost = 6000000}}}
		},
		-- decoration tiers (0 = none): floor and wall item ids, coal basins become braziers of the tier.
		-- `dark`: names in the dark tile set (data/lib/chaos_dark_tiles.lua) used instead when it is installed
		decor = {
			[0] = {name = "Bare stone", ground = 413, wall = 5648},
			[1] = {name = "White marble", ground = 406, wall = 1111},
			[2] = {name = "Obsidian", ground = 407, wall = 1049, dark = {ground = "obsidian_floor", wall = "obsidian_wall"}},
			[3] = {name = "Gilded", ground = 415, wall = 1025}
		}
	},

	-- ------------------------------------------------------------------ Guild Stash
	depot = {
		slots = 30, -- entries (one item or one stack each) before the depot perks
		maxStack = 100,
		takeRank = 1, -- members may take items out
		takePerDay = 20, -- entries a member below the vice-leader rank may take per day
		-- custom attributes copied with an item (the rarity system's, uniques, keys, scrolls). Standard attributes
		-- (description, name, text, charges, attack, defense, armor, ...) are always copied.
		customKeys = {"rarity", "combatPowerLevel", "chaos_unique", "rift_tier", "rift_mods", "chaos_uses", "chaos_realm",
			"chaos_sockets", "chaos_tmog"}, -- sockets; the transmog look (transmog.lua)
		customPrefixes = {"rarity_"} -- every key of ChaosCrafting's modifier lists with these prefixes
	},

	-- ------------------------------------------------------------------ the weekly "Top guild" board
	week = {resetHour = 6, rows = 10}, -- Monday 06:00 server time, like the leaderboards

	window = {logRows = 15, members = 60},
	logKeepDays = 180, -- chaos_guild_log rows (money, hall, depot, levels) older than this are deleted at startup
	staffAccess = true, -- /guild staff commands for groups with access

	storage = {scrollDay = 7101300, auraOn = 7101301}, -- 7101300 - 7101309 reserved for guilds

	tables = {
		guilds = "chaos_guild", contrib = "chaos_guild_contrib", log = "chaos_guild_log", stats = "chaos_guild_stats",
		hall = "chaos_guild_hall", upgrades = "chaos_guild_upgrades", depot = "chaos_guild_depot"
	}
}
