-- The Weekly Chest (weeklychest.lua, weeklychest_core.lua; client game_weeklychest; server/README.md "The Weekly Chest
-- (O261)"): every number. Plain table, loaded with
--     ChaosWeeklyChestConfig = dofile("data/scripts/chaos/weeklychest_config.lua")
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then restart (or /reload scripts).
--
-- Retention pass, owner 2026-10-26: a reason to come back every week and to try more than one system. Six activities
-- count once each per week: a dungeon, a rift, a waystone run, an Infinity Tower floor, a world boss or invasion share and
-- a bounty contract. 4 of 6 open the chest (given at once, like the Ember Cache); all of the unlocked ones add a bonus roll.
-- The week is the bounty board's and the leaderboard's: it starts Monday at resetHour (ChaosBounty.week).
-- An activity the character has not unlocked yet is left out, and the needed count drops with it, to 2 at the least.
-- Rewards are hours of hunting gold plus a few orbs (the Ember Cache's income table and orb values), scaled by level band.
return {
	enabled = true,

	-- extended opcode (ChaosOpcodes.weeklyChest; server/README.md "Opcode collision check")
	opcode = 117,

	-- the week turns at this hour (server time), like the bounty board (bounty_config.lua rollHour)
	resetHour = 6,

	-- player storages 7103020 - 7103029 (server/README.md "Storage keys")
	storage = {
		base = 7103020, last = 7103029,
		week = 0, -- YYYYMMDD of the Monday of the week the other values belong to
		done = 1, -- bit i (value 2^(i-1)) is set when `order`[i] was done this week
		chest = 2, -- 1 once this week's chest was given
		bonus = 3, -- 1 once this week's bonus roll was given
		chests = 4 -- chests given in all (the window shows it)
	},

	-- the six activities, in the order the window lists them. `level`: the level the system itself needs (the activity is
	-- left out of the needed count below it). This table mirrors the systems' own gates (each is checked against the
	-- system's config in tests/weeklychest_test.lua where that config is a plain table): rifts rift_config.lua tiers[1].minLevel,
	-- the world boss Chaos.worldBoss.minLevel (300) or an invasion invasion_config.lua minLevel (30, the lower one counts for
	-- "boss"), bounty contracts the first band of bounty_config.lua, waystones the first tier of waystone_tiers_config.lua,
	-- dungeons the first base dungeon (bossspawns_config.lua, 150), the Infinity Tower its run minLevel (100). The levels shared
	-- with unlocks_config.lua (dungeons, rifts, tower) are checked against it in tests/weeklychest_test.lua.
	activities = {
		{key = "dungeon", level = 150},
		{key = "rift", level = 100},
		{key = "waystone", level = 1100},
		{key = "tower", level = 100},
		{key = "boss", level = 30},
		{key = "bounty", level = 8}
	},

	-- ChaosAchievements.progress counters (wrapped) -> activity; ChaosSeasonJourney.emit counters (wrapped) -> activity.
	-- The tower (ChaosTower.recordRun with a floor cleared) and the waystone (ChaosWaystoneTiers.startRun, the opener of the
	-- run) have their own hooks.
	stats = {rift_runs = "rift", bounty_done = "bounty", wb_kills = "boss", invasion_fought = "boss"},
	emits = {dungeon_clears = "dungeon"},

	-- how many it takes: `need` of the unlocked activities, every unlocked one for the bonus roll. Each locked activity
	-- takes one off `need`, but never below `minNeed`. The bonus roll needs more activities unlocked than `need`.
	need = 4,
	minNeed = 2,

	-- level bands of the rewards (the bounty board's): the first level of each band, and the factor on the orb counts
	bands = {
		{min = 1, orbs = 1}, {min = 50, orbs = 1}, {min = 150, orbs = 2}, {min = 300, orbs = 2}, {min = 500, orbs = 3},
		{min = 800, orbs = 3}
	},

	-- hunting gold per hour by level: the Ember Cache's table (one source, embercache_config.lua)
	income = dofile("data/scripts/chaos/embercache_config.lua").income,

	-- hours of hunting one orb is worth (embercache_config.lua notes: Upheaval, Awakening, Whetstone 2 minutes, Tempering 5,
	-- Fate 6, Sockets 10). Item ids: 29856 Orb of Upheaval, 29851 Orb of Awakening, 29857 Orb of Fate, 32256 Whetstone,
	-- 32251 Orb of Tempering, 24692 Orb of Sockets (loot_config.lua).
	orbHours = {[29856] = 2 / 60, [29851] = 2 / 60, [32256] = 2 / 60, [32251] = 5 / 60, [29857] = 6 / 60, [24692] = 10 / 60},

	-- the chest: `hours` of hunting gold and the items (counts x the band's `orbs`)
	chest = {hours = 1.0, items = {{id = 29856, count = 2}, {id = 29851, count = 1}, {id = 32256, count = 1}, {id = 32251, count = 1}}},

	-- the bonus roll: one of these, picked at random
	bonus = {
		{hours = 0.8},
		{hours = 0.3, items = {{id = 29857, count = 1}, {id = 32251, count = 1}}},
		{hours = 0.4, items = {{id = 24692, count = 1}}}
	},

	-- limits in hours of hunting (value of gold plus orbs) at every level band; tests/weeklychest_test.lua checks them.
	-- The Ember Cache's top weekly milestone is worth 3.95 hours (embercache_config.lua): the chest with its bonus stays
	-- clearly under it, so the Weekly Chest is an addition for variety and never the better reason to play one system.
	limits = {chestHours = 2.0, bonusHours = 1.0, totalHours = 3.0},

	-- an open window gets a fresh state at most this often (ms)
	pushMs = 2000
}
