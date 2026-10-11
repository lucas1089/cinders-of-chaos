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

	-- weekly boards, in tab order. mode: how ChaosLeaderboard.record merges a value ("add" sums, "max" keeps the best,
	-- "min" keeps the lowest and ranks lowest first).
	-- value / count: column labels; count = how many times record() was called for the player this week
	-- (world boss kills participated, contracts, rift runs). title: given to the top `top` of the board for the next
	-- week (look text and the board). reward: per rank, orbs delivered to the inbox at the reset.
	boards = {
		{key = "worldboss", name = "World Boss", mode = "add", value = "Damage", count = "Kills", title = "Bossbane",
			info = "Damage dealt to world bosses this week."},
		{key = "bosshealer", name = "Boss Healer", mode = "add", value = "Healing", count = "Kills", title = "Lifebinder",
			info = "Healing on other players during world boss fights this week."},
		{key = "bosstank", name = "Boss Tank", mode = "add", value = "Tanked", count = "Kills", title = "Ironwall",
			info = "Damage from world bosses and their adds survived this week."},
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
			info = "Best 2v2 arena rating reached this week."},
		-- arena 3v3 and the battleground (arena.lua, battleground.lua)
		{key = "arena3v3", name = "Arena 3v3", mode = "max", value = "Rating", title = "Triumvir",
			info = "Best 3v3 arena rating reached this week."},
		{key = "battleground", name = "Battleground", mode = "add", value = "Wins", title = "Wellkeeper",
			info = "Ember Wells battleground wins this week."},
		{key = "defender", name = "Defender", mode = "add", value = "Points", count = "Invasions", title = "Defender of the Realm",
			info = "Invasions defended this week: 10 points each plus your share of the defence in percent."},
		-- factions.lua: reputation gained with every faction this week (after diminishing returns and caps)
		{key = "factions", name = "Reputation", mode = "add", value = "Reputation", title = "Banner-Sworn",
			info = "Faction reputation gained this week (every faction together)."},
		-- the Cinderheart (uber.lua): fastest kill this week in seconds (mode "min": lower is better), per party size;
		-- byClass: class tabs (the class the character had at the kill); format "time": shown as m:ss
		{key = "cinder_solo", name = "Cinderheart Solo", mode = "min", value = "Fastest", count = "Kills", title = "Lone Cinder",
			byClass = true, format = "time", info = "Fastest Cinderheart kill alone this week."},
		{key = "cinder_small", name = "Cinderheart 2-3", mode = "min", value = "Fastest", count = "Kills", title = "Emberwarden",
			byClass = true, format = "time", info = "Fastest Cinderheart kill in a party of 2 or 3 this week."},
		{key = "cinder_party", name = "Cinderheart 4-5", mode = "min", value = "Fastest", count = "Kills", title = "Ashen Vanguard",
			byClass = true, format = "time", info = "Fastest Cinderheart kill in a party of 4 or 5 this week."},
		-- the Ember Descent (descent.lua): the deepest room of this week's seeded run (the same rooms for everyone)
		{key = "descent", name = "Ember Descent", mode = "max", value = "Depth", count = "Runs", title = "Emberlord",
			info = "Deepest room reached in this week's seeded Ember Descent."},
		-- the Ashen Sepulchre (raid.lua): the fastest full clear this week in seconds (first pull to the final kill, all
		-- bosses in one sitting; mode "min": lower is better), every raider present at the final kill
		{key = "raid_clear", name = "Sepulchre Clear", mode = "min", value = "Fastest", count = "Clears", title = "Sepulchre Breaker",
			format = "time", info = "Fastest full clear of the Ashen Sepulchre this week (all five bosses in one sitting)."},
		-- the Scorched Marches (pvpzone.lua): embers banked at a safe exit this week
		{key = "marches", name = "Scorched Marches", mode = "add", value = "Embers", count = "Exits", title = "Marchlord",
			info = "Embers banked from the Scorched Marches this week."}
	},
	top = 3,
	rewards = {
		{{id = 29857, count = 5}, {id = 29856, count = 10}}, -- 1st: Orbs of Fate, Orbs of Upheaval
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
