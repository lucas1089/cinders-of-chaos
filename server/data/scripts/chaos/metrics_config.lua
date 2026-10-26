-- Progress metrics (metrics.lua, metrics_core.lua, sql/chaos_progress_metrics.sql; server/README.md "Progress metrics
-- (O253)" and "Funnel metrics (O258)"). Every number of the system. Returned as a table, loaded as Chaos.metricsConfig. Plain data, Lua 5.1 /
-- LuaJIT and Lua 5.3.
return {
	enabled = true,

	-- level bands: the upper level of each band; the last band is open ("901+"). 1-5, 6-10, ... 26-30, 31-40, ...
	-- Changing this later only splits new counts: old rows keep their labels.
	bands = {5, 10, 15, 20, 25, 30, 40, 50, 60, 80, 100, 150, 200, 300, 400, 500, 700, 900},

	-- churn: a character counts as gone when its last login is older than this many days (and it logged in at all);
	-- computed from `players` by one GROUP BY at startup and then every churnEverySeconds. Nothing is stored per player.
	churnDays = 14,
	churnEverySeconds = 24 * 3600,
	churnDelaySeconds = 60, -- the first computation runs this long after the start (the database is busy loading)

	-- the counters live in memory and are added to the table every flushSeconds, and at shutdown
	flushSeconds = 300,
	-- distinct keys held in memory between two flushes (a flood of names is dropped, not stored)
	maxKeys = 4000,
	-- names (monsters, areas) are cut to this many characters
	nameMax = 48,

	-- first session of a new character (first login ever): minutes played, counted at the logout in these buckets
	-- (upper limits; longer is the last bucket "inf")
	sessionBuckets = {5, 10, 20, 30, 45, 60, 90, 120, 180, 240, 360, 480},

	-- time to level: the played minutes (players.onlinetime) a character had when it first reached each level
	-- O258: 9 milestones, one bit each in the mask (the first five keep their bits, so old masks stay valid)
	milestones = {10, 25, 50, 100, 200, 500, 1000, 1500, 2000},
	-- bucket upper limits in minutes (longer is "inf"); the median is read inside the bucket by interpolation, so the
	-- buckets are finer where most characters are (an hour or two) and coarser later
	timeBuckets = {5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 360, 480, 720, 960, 1440, 2160, 2880, 4320, 5760,
		8640, 11520, 17280, 23040, 34560, 57600, 86400, 129600, 172800, 259200},

	-- where a death happened: the instance (Chaos.registerInstance label) when the character stood in one, else the
	-- nearest hunt (data/lib/chaos_hunt_places.lua: a hunt's arrival tile) on the same floor within this many tiles
	-- (Chebyshev distance), else "Outside hunts, floor N"
	areaRadius = 80,
	otherArea = "Outside hunts, floor %d",
	-- killers that are not a monster
	killerPlayer = "Player (PvP)",
	killerSummon = "Player's summon",
	killerOther = "Environment or unknown",

	-- small-number suppression in every report (progress_metrics.py MIN_SHOWN, metrics_core.lua M.suppress): a count
	-- of 1 to minShown - 1 is shown as "<5", with its share and median left out. Keep both in step.
	minShown = 5,

	-- who is left out: a staff character (group id above this) and a tester bot (Chaos.isTester)
	maxGroupId = 1,

	-- player storage: bit mask of the milestones already recorded for the character (+0), so a level lost at a death
	-- and gained again counts once. A game flag of the character; no metric row holds it. 7102830 - 7102839 reserved
	storage = 7102830,

	-- O258 return: the first login of a character stores `day * 8 + flags` in this storage (day = whole days since the
	-- epoch in server time; flags bit 0 / 1 / 2 = d1 / d3 / d7 counted). A login on a calendar day >= first + N counts
	-- return:dN once. Characters that existed before the install have no value and are not counted.
	returnStorage = 7102831,
	returnDays = {1, 3, 7},

	-- O258 first use of a system: one bit per system, in this order (bit 0 = dungeon), in this storage. Each system's
	-- success path calls ChaosMetrics.firstUse(player, key) (metrics.lua installHooks wraps the existing APIs).
	firstStorage = 7102832,
	systems = {"dungeon", "rift", "waystone", "tower", "pocketboss", "worldboss", "invasion", "party", "guild",
		"market", "bounty", "craft"},

	-- O258 where they stop: the gone characters are grouped by level band and by a cell of this many tiles of their
	-- last position (posx / posy / posz of `players`); the area of a cell is its centre's nearest hunt (areaFor).
	-- There is no row per player: a row is (area, band) and a count.
	stopCell = 8,
	-- the first-use / stop / return checks of party and guild membership run in the 60 s think for the open sessions
	memberCheckSeconds = 60
}
