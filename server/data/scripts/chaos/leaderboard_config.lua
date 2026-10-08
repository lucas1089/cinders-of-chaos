-- Leaderboards (leaderboard.lua, leaderboard_core.lua, client game_leaderboard). Returned as a table, loaded as
-- Chaos.leaderboardConfig. Server local time. See server/README.md "Leaderboards".
-- Lua 5.1 / LuaJIT compatible.
return {
	-- DB tables (server/sql/chaos.sql)
	tables = {scores = "chaos_leaderboard", titles = "chaos_leaderboard_titles"},
	-- server_config row: the week key of the last weekly reset that was processed
	resetConfigKey = "chaos_leaderboard_reset",

	-- the weekly boards reset on Monday at this hour: the same rule as the bounty board's weekly chest
	-- (ChaosBounty.week with the bounty rollHour; bounty_config.lua rollHour = 6)
	resetHour = 6,
	rows = 20, -- rows shown per board
	keepWeeks = 8, -- weekly score rows older than this are deleted at the reset
	-- characters of this group id and above (gamemasters, gods) are left out of the boards, titles and rewards
	staffGroup = 4,
	checkSeconds = 60, -- how often the reset is checked

	-- weekly boards, in tab order. mode: how ChaosLeaderboard.record merges a value ("add" sums, "max" keeps the best).
	-- value / count: column labels; count = how many times record() was called for the player this week
	-- (world boss kills participated, contracts, rift runs). title: given to the top `top` of the board for the next
	-- week (look text and the board). reward: per rank, orbs delivered to the inbox at the reset.
	boards = {
		{key = "worldboss", name = "World Boss", mode = "add", value = "Damage", count = "Kills", title = "Bossbane",
			info = "Damage dealt to world bosses this week."},
		{key = "bounty", name = "Bounty Hunter", mode = "add", value = "Contracts", title = "Warden of the Hunt",
			info = "Bounty contracts completed this week."},
		{key = "rift", name = "Rifts", mode = "max", value = "Highest Tier", count = "Runs", title = "Riftwalker",
			info = "Highest rift tier completed this week."},
		{key = "goblin", name = "Goblin Slayer", mode = "add", value = "Goblins", title = "Goblin Slayer",
			info = "Treasure goblins slain this week."},
		{key = "siege", name = "Guild Siege", mode = "add", value = "Points", title = "Siegebreaker",
			info = "Guild siege points this week: enemies struck down and seconds holding the obelisk."},
		{key = "arena1v1", name = "Arena 1v1", mode = "max", value = "Rating", title = "Duelist",
			info = "Best 1v1 arena rating reached this week."},
		{key = "arena2v2", name = "Arena 2v2", mode = "max", value = "Rating", title = "Gladiator",
			info = "Best 2v2 arena rating reached this week."}
	},
	top = 3,
	rewards = {
		{{id = 29857, count = 5}, {id = 29856, count = 10}}, -- 1st: Divine Orbs, Chaos Orbs
		{{id = 29857, count = 3}, {id = 29856, count = 6}}, -- 2nd
		{{id = 29857, count = 1}, {id = 29856, count = 3}} -- 3rd
	},
	rankNames = {"1st", "2nd", "3rd"},

	-- all-time ladder: highest level per class, from the players table
	ladder = {
		key = "ladder",
		name = "Class Ladder",
		cacheSeconds = 300,
		-- vocation id -> base class id. nil = Chaos.classes.baseOf (classes.lua owns it). A vocation missing from the
		-- mapping is grouped through Vocation(id):getDemotion() down to its base. Group names are read from the
		-- server: Vocation(base):getName().
		baseOf = nil,
		vocationsFile = "data/XML/vocations.xml", -- the class list: the vocation ids of this file (that the engine knows)
		maxVocationId = 30 -- fallback when the file cannot be read: ids 1..this are asked from the engine
	}
}
