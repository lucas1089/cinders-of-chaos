-- The Ember Cache and the day book (embercache.lua, embercache_core.lua, daybook_core.lua; client game_embercache;
-- server/README.md "Ember Cache, Daily Spark and the day book"): every number. Plain table, loaded with
--     ChaosEmberCacheConfig = dofile("data/scripts/chaos/embercache_config.lua")
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then restart (or /reload scripts).
--
-- Owner goal 2026-10-15: fluid and fun for heavy and light players, everyone rewarded for effort. Every activity gives
-- Ember points: hunting, dungeons, rifts, bounties, kill tasks, bosses, the raid, the tower, the Descent, trials,
-- invasions, battlegrounds, sieges, crafting. No chore list: any mix fills the same bar.
--   Daily Spark   the first `daily.bonusPoints` points of a day count double, and `daily.goal` points in a day light
--                 the day's Spark (a small reward at once). A 30 minute session lights it.
--   Ember Cache   the week's points fill three milestones; each gives its reward at once (gold to the bank, items to
--                 the backpack or the inbox). The week starts Monday at resetHour.
--   Day book      what the character did today (experience, kills, loot, supplies, drops, deaths, time); the last
--                 day of play is shown once at the next login.
-- Rewards are hours of hunting income (see `income` below; owner left the sizes to our estimate, 2026-10-15).
return {
	enabled = true,

	-- extended opcode (ChaosOpcodes.emberCache; server/README.md "Opcode collision check")
	opcode = 174,

	-- the day and the week turn at this hour (server time), like the bounty board
	resetHour = 6,

	-- player storages 7102700 - 7102739 (server/README.md "Storage keys")
	storage = {
		base = 7102700, last = 7102719,
		week = 0, weekPoints = 1, tiersGiven = 2, weekSparks = 3, day = 4, dayPoints = 5, dayRaw = 6, spark = 7,
		killRest = 8, -- kills not yet worth a point
		capBase = 9 -- +9 .. +9 + #capped sources - 1: points of a capped source today (in the order of `capped`)
	},
	daybook = {
		base = 7102720, last = 7102739,
		day = 0, xpHi = 1, xpLo = 2, kills = 3, lootHi = 4, lootLo = 5, supHi = 6, supLo = 7, orbs = 8, uniques = 9,
		rares = 10, deaths = 11, levelStart = 12, seconds = 13, points = 14
	},

	-- sources with a daily cap, in storage order (storage.capBase + index - 1)
	capped = {"kill", "elite", "craft"},

	-- what one unit of each source is worth. `per`: units per point (kills); `cap`: points a day at most.
	sources = {
		kill = {per = 20, cap = 60}, -- 1 point per 20 monster kills (party kills near count for every member)
		elite = {points = 1, cap = 30}, -- a rare monster 1, a legendary monster 3 (amount below)
		dungeon = {points = 12}, -- a dungeon cleared
		rift = {points = 12}, -- a rift run finished
		descent = {points = 10}, -- an Ember Descent run
		tower = {points = 8}, -- an Infinity Tower run
		bounty = {points = 6}, -- a bounty contract done
		task = {points = 6}, -- a bestiary kill task done
		worldboss = {points = 15}, -- a world boss fought
		raid = {points = 10}, -- an Ashen Sepulchre boss
		omen = {points = 10}, -- an Omen or Ascended Omen guardian
		trial = {points = 8}, -- a Vocation Trial run
		invasion = {points = 6}, -- an invasion fought
		pvp = {points = 6}, -- a battleground match or a siege
		goblin = {points = 5}, -- a treasure goblin
		craft = {points = 1, cap = 15} -- a crafting orb used
	},
	-- the order the client lists the sources in
	order = {"kill", "elite", "dungeon", "rift", "descent", "tower", "bounty", "task", "worldboss", "raid", "omen",
		"trial", "invasion", "pvp", "goblin", "craft"},

	-- achievement counters (ChaosAchievements.progress, wrapped) -> {source, units per count}
	stats = {
		kills_rare = {"elite", 1}, kills_legendary = {"elite", 3}, rift_runs = {"rift", 1}, bounty_done = {"bounty", 1},
		bestiary_tasks = {"task", 1}, wb_kills = {"worldboss", 1}, raid_kills = {"raid", 1}, omen_kills = {"omen", 1},
		ascended_kills = {"omen", 1}, trial_runs = {"trial", 1}, invasion_fought = {"invasion", 1},
		bg_matches = {"pvp", 1}, siege_played = {"pvp", 1}, goblin_kills = {"goblin", 1}, orbs_used = {"craft", 1}
	},
	-- Seasonal Journey counters (ChaosSeasonJourney.emit, wrapped; dungeons.lua and descent.lua send them)
	emits = {dungeon_clears = {"dungeon", 1}, descent_runs = {"descent", 1}},

	-- kill credit: party members on the same floor within this many squares of the kill count it too
	partyRange = 30,

	-- hunting gold per hour by level (median class, NPC sell value; linear between the points, flat beyond): the
	-- "Respec" table (gamble_config.lua balance.hunting, tools/respec_income.py) x 1.12, the gold per hour of pack combat
	-- against the old model (server/README.md "Pack combat": 1.10-1.16 by band). Rewards are hours of this income.
	income = {{8, 21000}, {40, 93000}, {100, 402000}, {300, 988000}, {500, 6214000}, {1000, 10662000}},

	-- Reward sizes (owner answer 2026-10-15: our estimate; the Spark worth 10-15 minutes of normal hunting, the
	-- milestones about 1 / 2 / 4 hours). A reward is `hours` of hunting gold plus a few orbs. Orb values: per hour a
	-- median hunt finds roughly 1.5 Orb of Upheaval, 1.5 Orb of Awakening, 1.5 Whetstone, 0.6 Orb of Tempering, 0.5 Orb of
	-- Fate, 0.3 Orb of Sockets (loot_config.lua currency chances x the tier mix x the pack loot factor). Orbs sell to no
	-- NPC; counting them as 30% of an hour's income, shared by kind and worth more the rarer they are, one orb is
	-- 0.05 / (found per hour) hours: Upheaval, Awakening, Whetstone 2 minutes, Tempering 5, Fate 6, Sockets 10.
	-- Totals (gold + orbs): Spark 0.18 h (11 min), milestones 1.0 / 2.0 / 3.95 h. tests/embercache_test.lua checks them.
	daily = {
		bonusPoints = 40, -- the first 40 points of a day count double
		goal = 30, -- points (counted) that light the day's Spark
		reward = {hours = 0.15, items = {{id = 29851, count = 1}}} -- 9 minutes of gold + an Orb of Awakening: 11 min
	},

	-- the week's milestones (points, counted), each with its reward. Item ids: 29856 Orb of Upheaval, 29851 Orb of
	-- Awakening, 29857 Orb of Fate, 32256 Whetstone, 32251 Orb of Tempering, 24692 Orb of Sockets (loot_config.lua).
	tiers = {
		{points = 120, hours = 0.9, -- 1.0 h with the orbs
			items = {{id = 29856, count = 1}, {id = 29851, count = 1}, {id = 32256, count = 1}}},
		{points = 300, hours = 1.7, -- 2.0 h with the orbs
			items = {{id = 29856, count = 2}, {id = 29857, count = 1}, {id = 32256, count = 1}, {id = 32251, count = 1}}},
		{points = 600, hours = 3.4, -- 3.95 h with the orbs
			items = {{id = 29856, count = 4}, {id = 29857, count = 1}, {id = 32256, count = 2}, {id = 32251, count = 1},
				{id = 24692, count = 1}}}
	},

	-- day book: EventCallback onGainExperience index (after every bonus and after the hunt tracker at 1000)
	expIndex = 1001,
	-- the last day of play is told at the next login when it had at least this much play (seconds)
	recapMinSeconds = 300,

	-- an open window gets a fresh state at most this often (ms)
	pushMs = 2000
}
