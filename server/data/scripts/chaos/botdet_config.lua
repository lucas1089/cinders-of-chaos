-- Bot detection events and scores: the numbers (botdet.lua, pure logic botdet_core.lua, tests/botdet_test.lua,
-- tests/botdet_load_test.lua; sql/chaos_botdet.sql; server/README.md "Bot detection events and scores (O722)").
-- Loaded as Chaos.botdetConfig. Data only. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Nothing here punishes, kicks or moves anyone. Every number is a starting point from docs/BOT_DETECTION.md: adjust them
-- with the traces of known players and of a test account that runs a cavebot (docs/BOT_DETECTION.md "Plano de teste").
-- Testers (tester bots, journey bots) and staff are never collected.
return {
	enabled = true,
	staffGroup = 4, -- from this group a character is staff: never collected (as antibot_config.lua)

	-- ------------------------------------------------------------------ collection (botdet.lua)
	sampleMs = 1000, -- one position sample per online character every second; only a change of tile is kept
	flushSeconds = 300, -- the batched write to the database, per character, spread by guid; also at logout
	keepOfflineMinutes = 30, -- the state of a character that logged out is kept this long (a relog keeps its session)
	hourlySeconds = 3600, -- the six heuristics run once an hour per character, spread by guid over the hour
	retention = {eventDays = 7, scoreDays = 90},
	purgeChunk = 5000, -- rows a purge deletes per statement (a day's purge repeats until nothing is left)
	rings = {
		pos = 7200, -- position changes kept (two hours of walking at one change a second)
		intervals = 160, -- intervals kept per kind of action
		kinds = 8, -- kinds of action kept per character (the one used longest ago is dropped)
		heals = 160, -- hit point percentages kept at a heal
		react = 128, -- reaction times kept
		pending = 400 -- unwritten rows of one type kept per character (older ones are dropped, never grow without bound)
	},
	-- the table of the creatures that came into view lives in the engine (src-patch 0093); this is the cap of what one
	-- poll takes (the engine ring is 32)
	pollEvery = 5, -- the engine's signals (player:getBotSignals) are polled every N samples

	-- ------------------------------------------------------------------ the heuristics, scores 0 (human-like) .. 100
	-- total = sum(weight x score) / sum(weight) of the heuristics that have enough samples, times min(1, weight with data /
	-- minCoverage), plus the path bonus; flagged above flagAt
	weights = {route = 30, regularity = 25, reaction = 20, heal = 15, session = 10},
	minCoverage = 60, -- weight that must have data for the total to count in full (route + regularity + reaction ...)
	bonusMax = 10, -- the path precision signal only adds up to this many points
	flagAt = 70, -- a total above this goes on the review list (staff decide)

	route = {
		-- the walk cut into cellSize squares, one entry per change of cell; the loop is the shortest period whose cells come back
		cellSize = 6,
		minSpanSeconds = 1800, -- says nothing for a walk shorter than this (30 minutes of position changes)
		minCells = 60,
		maxCells = 1600, -- the last cells that are searched (bounded work)
		minPeriod = 4, maxPeriod = 400, -- loop length in cells (a lap of 300 tiles is about 80 cells)
		minDistinct = 5, -- a loop covers at least this many different cells (walking between two spots is no loop)
		lapsFrom = 3, lapsTo = 20, -- laps in the window: 0 at From, 1 at To (the plan: more than 20 in 2 hours)
		matchFrom = 0.6, matchTo = 0.9, -- share of cells that come back one period later
		devFrom = 1.0, devTo = 4.0 -- mean distance in sqm between the tile a lap entered a cell and the lap before: <= From 1, >= To 0
	},
	regularity = {
		-- intervals of the same spell (and of heals that are not a spell) as a coefficient of variation (std / mean)
		minMs = 300, maxMs = 20000, -- outside this an interval is a break or a double event, not rhythm
		minSamples = 30, fullSamples = 100, -- below minSamples no score; the score is cut by samples / fullSamples below
		cvHuman = 0.25, cvBot = 0.08 -- >= cvHuman scores 0, <= cvBot scores 100
	},
	reaction = {
		-- milliseconds between a creature coming into view and the first attack on it (needs src-patch 0093)
		maxMs = 5000, -- a first attack later than this is a choice, not a reaction
		minSamples = 20, fullSamples = 50,
		botMs = 120, humanMs = 260 -- the median: <= botMs scores 100, >= humanMs scores 0 (the round trip of the connection is inside it)
	},
	heal = {
		-- hit point % at each own heal (spell, rune, potion); a bot heals at one value
		topUpAt = 96, -- a heal at this % or more is a top-up, not a threshold
		minSamples = 30, fullSamples = 50,
		stdBot = 2, stdHuman = 6 -- standard deviation in percentage points: <= stdBot scores 100, >= stdHuman scores 0
	},
	session = {
		idleSeconds = 300, -- a pause this long without any action ends a stretch
		stretchFromHours = 5, stretchToHours = 8, -- the longest stretch without a pause (the plan: more than 6 hours)
		dayFromHours = 14, dayToHours = 20 -- hours with an action in the last 24 (the plan: 20 or more a day)
	},
	path = {
		-- weak signal, a bonus only: nearly every step comes from a path command (a click on the map) and the commands are long
		minSteps = 300,
		shareFrom = 0.8, shareTo = 0.98,
		lengthFrom = 4, lengthTo = 12 -- mean steps of a path command
	},

	-- ------------------------------------------------------------------ the client's signals (opcode ChaosOpcodes.botdet)
	integrity = {
		-- the client sends the digest of every module and mod folder (client game_chaosguard integrity.lua) in chunks; the
		-- server compares with data/lib/chaos_module_hashes.lua (client/tools/gen_module_hashes.py makes it at release).
		-- An empty list compares nothing. A module the list does not know, or whose digest differs, is one `integrity` event.
		listFile = "data/lib/chaos_module_hashes.lua",
		maxChunks = 8, maxEntries = 160, -- per login, per chunk
		maxExtras = 40 -- extras and changes kept in one event
	},
	tools = {
		-- known external tools: the client scans (Windows only) for the hashed names this table holds and answers with the
		-- CODES of the ones it found, never a process list. Staff keep the table: `hashes` are 16 hex digits of FNV-1a 64 of
		-- the lower-case process name or window title word (client/tools/chaostoolscan_test.cpp has the vector), `code` is the
		-- short code that is stored (kept as 3 to 16 letters or digits). Empty on purpose: staff add the tools they know.
		list = {},
		maxCodes = 8
	},

	-- ------------------------------------------------------------------ the policy switch (owner decision, docs/BOT_DETECTION.md part 5)
	-- The owner's own external route tool: how the report treats a character that runs it.
	--   "flag"      default: only flagged and shown in /botcheck as a tool, nothing else changes
	--   "allowed"   shown as allowed; a character that runs it is not flagged for the route, rhythm and session scores
	--   "forbidden" shown as forbidden; flagged as any other (the staff act by the rules)
	--   "areas"     allowed inside `areas` (boxes {x1, y1, x2, y2, z}), flagged outside them
	-- Never an automatic action in any of the four.
	rumo = {
		policy = "forbidden", -- owner 2026-11-22: no cavebot is allowed, any external tool is forbidden
		areas = {},
		moduleNames = {"game_rumolink"}, -- a client module of this name in the integrity list means the tool
		toolCode = "rumo" -- or this code from the client scan
	},

	-- ------------------------------------------------------------------ the staff report
	report = {
		topN = 20,
		logFile = "data/logs/botdet_top.log", -- the daily list (chaos-ctl.sh botcheck-top reads the table; this file is the log)
		logHour = 4 -- the daily top is written the first hour tick at or after this server hour
	}
}
