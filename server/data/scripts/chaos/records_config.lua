-- Competitive records (records.lua, records_core.lua, client game_leaderboard "Records" view, website Leaderboards).
-- Returned as a table, loaded as Chaos.recordsConfig. Server local time. See server/README.md "Competitive records".
-- The boards are built by ChaosRecordsCore.catalogue from `boards` below and the content configs (world bosses, omens,
-- Ascended, trials, dungeons), so a new boss of those lists gets its boards without a change here.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	-- DB tables (server/sql/chaos_records.sql; records.lua creates them at startup when missing)
	tables = {best = "chaos_records", firsts = "chaos_records_firsts", awards = "chaos_records_awards",
		boards = "chaos_records_boards"},
	resetConfigKey = "chaos_records_reset", -- server_config: the week key of the last weekly award processed
	resetHour = 6, -- weeks start Monday 06:00, the leaderboards' rule (leaderboard_config.lua resetHour)
	rows = 20, -- rows shown per board
	top = 3, -- weekly top 3 of every board get the category title and the badge for the next week
	keepWeeks = 8, -- weekly rows older than this are deleted at the reset (season and all-time rows stay)
	staffGroup = 4, -- characters of this group and up never count (as on the leaderboards)
	checkSeconds = 60,

	-- views: this week, the season (ChaosSeason.current() while a season runs, else the calendar quarter) and all time
	periods = {{key = "week", name = "This week"}, {key = "season", name = "Season"}, {key = "all", name = "All time"}},

	-- party size brackets (filters of a board). A run whose size is in no bracket of its board does not count.
	sizes = {
		solo = {name = "Solo", min = 1, max = 1},
		small = {name = "2-3", min = 2, max = 3},
		party = {name = "4-5", min = 4, max = 5}
	},

	-- anti-abuse (ChaosRecordsCore.validate): every rule must hold for a run to count
	valid = {
		minSeconds = 10, -- a time below this is a broken clock or a staff spawn, never a real kill
		maxGroup = 40, -- no board takes a group above this (the world boss arena cap)
		staffTaints = true -- one staff character in the group voids the run for everyone
	},

	-- rewards
	badgeFrame = "laurel", -- name plate frame (nameplate_core.lua N.FRAMES) while a weekly top 3 is held
	titleColor = "#e8c15a", -- weekly category titles (gold, as the leaderboard titles)
	firstColor = "#f08a2c", -- realm first titles (orange)
	firstTitle = "First: %s", -- realm first title; the boss's short name; cut to 24 characters
	announceRecord = true, -- broadcast a beaten all-time record
	announceFirst = true, -- broadcast a realm first

	categories = {
		{key = "bosses", name = "Bosses", title = "Bossrunner", info = "Fastest boss kills: world bosses, Omen guardians, the Ascended, the guild boss, the Sepulchre and the dungeons."},
		{key = "tower", name = "Infinity Tower", title = "Spire Climber", info = "Highest floor and the fastest climbs to floors 50, 100 and 120."},
		{key = "rifts", name = "Rifts", title = "Rift Sprinter", info = "Highest tier sealed, the fastest tier 15 and the Rift Atlas completion."},
		{key = "descent", name = "Ember Descent", title = "Depth Seeker", info = "Deepest room of the weekly seeded run."},
		{key = "trials", name = "Vocation Trials", title = "Trial Breaker", info = "Fastest Vocation Trial clears per difficulty."},
		{key = "pvp", name = "Arena", title = "Warlord", info = "Best arena rating per bracket and battleground wins."},
		-- O260: the personal drop records. A category only for the boards below: never listed in the Records view, no weekly
		-- top 3, no title, not published to the website (hidden = true, personal = true on the boards)
		{key = "loot", name = "Treasure", title = "Treasure Hunter", info = "Personal bests: the best drop.", hidden = true}
	},

	-- board templates. mode "min" (fastest: seconds), "max" (highest), "add" (sum). format: "time" (m:ss), "pct"
	-- (value / 100 %), nil (number). variants: "worldboss" | "omens" | "ascended" | "bands" | "difficulties" |
	-- "trialTiers" | "towerFloors" | "arena" | nil (the catalogue fills them). sizes: bracket keys (nil = any size up
	-- to `maxGroup`). byClass: class filter. first: realm first per variant (a boss kill). hook: where its runs come from
	-- (documentation; "pending" = the source script has no hook point yet, server/README.md lists the line to add).
	boards = {
		{key = "wb_time", cat = "bosses", name = "World Boss Kill", mode = "min", format = "time", value = "Fastest",
			variants = "worldboss", byClass = true, first = true, maxGroup = 40, hook = "ChaosWorldBoss.computeRewards"},
		{key = "wb_share", cat = "bosses", name = "World Boss Damage", mode = "max", format = "pct", value = "Damage share",
			variants = "worldboss", byClass = true, maxGroup = 40, hook = "ChaosWorldBoss.computeRewards"},
		{key = "omen", cat = "bosses", name = "Omen Guardians", mode = "min", format = "time", value = "Fastest",
			variants = "omens", sizes = {"solo", "small", "party"}, byClass = true, first = true, hook = "ChaosRiftCore.atlasSealed"},
		{key = "ascended", cat = "bosses", name = "Ascended", mode = "min", format = "time", value = "Fastest",
			variants = "ascended", sizes = {"solo", "small", "party"}, byClass = true, first = true, hook = "ChaosExclusives.bossKill"},
		{key = "guildboss", cat = "bosses", name = "Guild Boss", mode = "min", format = "time", value = "Fastest",
			byClass = true, first = true, maxGroup = 15, hook = "ChaosExclusives.bossKill"},
		{key = "raid", cat = "bosses", name = "Sepulchre Clear", mode = "min", format = "time", value = "Fastest",
			byClass = true, first = true, maxGroup = 15, hook = "ChaosLeaderboard.record raid_clear"},
		{key = "hollowvault", cat = "bosses", name = "Hollow Vault", mode = "min", format = "time", value = "Fastest",
			variants = "difficulties", sizes = {"solo", "small", "party"}, byClass = true, first = true, hook = "pending"},
		{key = "dungeon", cat = "bosses", name = "Dungeons", mode = "min", format = "time", value = "Fastest",
			variants = "difficulties", sizes = {"solo", "small", "party"}, byClass = true, first = true, perDungeon = true,
			hook = "pending"},
		{key = "tower_floor", cat = "tower", name = "Highest Floor", mode = "max", value = "Floor", byClass = true,
			maxGroup = 5, hook = "ChaosTower.recordRun"},
		{key = "tower_time", cat = "tower", name = "Fastest Climb", mode = "min", format = "time", value = "Fastest",
			variants = "towerFloors", sizes = {"solo", "small", "party"}, byClass = true, hook = "ChaosRecords.towerFloor"},
		{key = "rift_tier", cat = "rifts", name = "Highest Tier", mode = "max", value = "Tier", byClass = true, maxGroup = 5,
			hook = "ChaosRiftCore.atlasSealed"},
		{key = "rift_band", cat = "rifts", name = "Fastest Seal", mode = "min", format = "time", value = "Fastest",
			variants = "bands", sizes = {"solo", "small", "party"}, byClass = true, hook = "ChaosRiftCore.atlasSealed"},
		{key = "atlas", cat = "rifts", name = "Atlas Completion", mode = "max", format = "pct", value = "Completed",
			byClass = true, hook = "ChaosRiftCore.atlasSealed"},
		{key = "descent", cat = "descent", name = "Deepest Room", mode = "max", value = "Depth", byClass = true, maxGroup = 4,
			hook = "ChaosLeaderboard.record descent"},
		{key = "trials", cat = "trials", name = "Trial Clear", mode = "min", format = "time", value = "Fastest",
			variants = "trialTiers", sizes = {"solo"}, byClass = true, first = true, hook = "ChaosAchievements.set trial_tier"},
		{key = "arena", cat = "pvp", name = "Arena Rating", mode = "max", value = "Rating", variants = "arena", byClass = true,
			maxGroup = 3, hook = "ChaosLeaderboard.record arena*"},
		{key = "battleground", cat = "pvp", name = "Battleground Wins", mode = "add", value = "Wins", byClass = true,
			maxGroup = 1, hook = "ChaosLeaderboard.record battleground"},
		-- O260 personal records (retention_loot.lua submits them; all-time value of a character only): the best drop of a
		-- character by rarity rank (Common 1 .. Divine 6, Unique 7) and by the NPC sell price of the item
		{key = "drop_rarity", cat = "loot", name = "Best Drop Rarity", mode = "max", value = "Rarity", maxGroup = 1, personal = true,
			hook = "ChaosRetentionLoot.onKill"},
		{key = "drop_value", cat = "loot", name = "Best Drop Value", mode = "max", value = "Gold", maxGroup = 1, personal = true,
			hook = "ChaosRetentionLoot.onKill"}
	},

	-- O260: what the personal records view lists (Inspect and the Records tab), by board key
	personal = {
		rarity = "drop_rarity", value = "drop_value", tower = "tower_floor", rift = "rift_tier",
		bossCat = "bosses", maxBossRows = 12,
		cacheSeconds = 600 -- a character's personal bests are read from the database once per this many seconds
	},

	-- rift tier bands of "rift_band" (the clear time of a sealed rift of that tier band); tier 15 is a band of its own
	bands = {{key = "b1", name = "Tiers 1-5", min = 1, max = 5}, {key = "b2", name = "Tiers 6-10", min = 6, max = 10},
		{key = "b3", name = "Tiers 11-14", min = 11, max = 14}, {key = "t15", name = "Tier 15", min = 15, max = 15}},
	towerFloors = {50, 100, 120}, -- "tower_time": seconds from the start of the run to the clear of this floor
	difficulties = 6, -- dungeons and the Hollow Vault (dungeons_difficulty.lua: six)
	difficultyName = "Difficulty %d", -- the dungeon window numbers its six difficulties
	arena = {{key = "1v1", name = "1v1"}, {key = "2v2", name = "2v2"}, {key = "3v3", name = "3v3"}},
	hollowVaultName = "Hollow Vault" -- the base dungeon of this title feeds "hollowvault" instead of "dungeon"
}
