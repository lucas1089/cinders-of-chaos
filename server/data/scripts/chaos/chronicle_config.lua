-- The Ashen Chronicle (chronicle.lua, chronicle_core.lua, chronicle_text.lua; client game_chronicle, extended opcode
-- ChaosOpcodes.chronicle = 171). Every number of the system lives here; the story text is chronicle_text.lua (same
-- chapter keys). Returned as a table and loaded as Chaos.chronicleConfig = dofile("data/scripts/chaos/chronicle_config.lua").
-- Item ids are SERVER ids of stock items (the area planner's decoration kits, checked on the pair by
-- `area_planner.py check-kits`). Overview: server/README.md "The Ashen Chronicle". Lua 5.1 / LuaJIT and Lua 5.3.
return {
	enabled = true,
	opcode = 171,
	staffGroup = 4, -- characters of this group or higher add nothing and are never ranked
	tickSeconds = 60, -- season check, flush of the contributions, the world state again
	topShown = 5, -- contributors per chapter in the window and on the website while the season runs
	topRecorded = 10, -- contributors per chapter written to the record at the season's end
	recordSeasons = 3, -- past seasons in the window's Record tab

	-- DB tables (server/sql/chaos_chronicle.sql; chronicle.lua creates them at startup when missing)
	tables = {state = "chaos_chronicle_state", chapters = "chaos_chronicle_chapters", progress = "chaos_chronicle_progress",
		contrib = "chaos_chronicle_contrib", record = "chaos_chronicle_record", levels = "chaos_chronicle_levels"},

	-- Global storages (Game.setStorageValue, engine-wide, read by NPC scripts in their own Lua state). Block
	-- 7102100-7102119 (server/README.md "Storage keys"): base + n = 1 once chapter n of the running arc is written;
	-- done = how many chapters are written; season = the season id the flags belong to. All 0 / -1 after a reset.
	globalStorage = {base = 7102100, done = 7102110, season = 7102111},

	-- action ids 47920-47929: the gate portals of the chapter areas (47920 + the area's index in `areas` below)
	gateAid = 47920,
	gateItem = 1387, -- magic forcefield (type teleport, no destination: chronicle.lua moves the player, as areagen.lua)

	-- the capital: its temple anchors the town changes (`town.anchor` overrides it). Cinderhold, the main city
	-- (server/README.md "Main city", owner request 2026-10-15; it was Mirewake, town 1)
	townId = 2,

	broadcast = true, -- chapter written, season start / end: a server broadcast
	discordEvent = "chronicle", -- the event type for the Discord queue (discord.lua), when that module is loaded

	-- points of one contribution, per kind (each member of a run gets them). A goal that is already met adds no points.
	points = {worldboss = 10, rift_b1 = 1, rift_b2 = 2, rift_b3 = 4, rift_t15 = 6, omen = 8, ascended = 15,
		cinderheart = 40, raid = 6, level = 5, event = 4},

	-- rift tier bands (the records' bands, records_config.lua `bands`)
	riftBands = {{key = "b1", min = 1, max = 5}, {key = "b2", min = 6, max = 10}, {key = "b3", min = 11, max = 14},
		{key = "t15", min = 15, max = 15}},

	-- which arc of chronicle_text.lua a season tells (season_config.lua season ids). A season without one has no Chronicle.
	arcs = {[1] = "s1"},

	-- the chapters of each arc, in order (4 to 6). One chapter is open at a time; it is written when every goal is met.
	-- goals: kind worldboss | rift (band) | omen | ascended | cinderheart | raid | level (level) | event (event), target
	--   worldboss    a world boss kill the records accept (ChaosRecords.submit "wb_time")
	--   rift         a sealed rift of the band (ChaosRecords.submit "rift_tier": the tier)
	--   omen         an Omen guardian slain (ChaosRecords.submit "omen")
	--   ascended     an Ascended Omen slain (ChaosRecords.submit "ascended", any variant but the Cinderheart)
	--   cinderheart  Ysgrath the Cinderheart slain (ChaosRecords.submit "ascended" variant "cinder")
	--   raid         an Ashen Sepulchre clear (ChaosRecords.submit "raid", once per raid run)
	--   level        a character reaches `level` this season (once per character; staff never)
	--   event        a world event done: "invasion" = an invasion repelled (ChaosInvasion.deliver), or any key another
	--                script passes to ChaosChronicle.event(key, players)
	-- world: what the chapter changes when it is written (replayed in order; undone at the next season's start)
	--   open = {area keys}      the gate portal of each area appears (and the global flag is set)
	--   town = {add = {set keys}, remove = {set keys}}   decoration sets of `town.sets` placed / taken away
	-- Season 1 sizes (decided 2026-10-14, owner delegated; the arithmetic: server/README.md "The Ashen Chronicle",
	-- "Goal sizes"): each chapter takes days at 100-300 online, about 37 days for the arc at 150 online.
	chapters = {
		s1 = {
			{key = "ash_thickens",
				goals = {{kind = "level", level = 300, target = 250}, {kind = "rift", band = "b1", target = 1200}},
				world = {town = {add = {"ashfall"}}}},
			{key = "wound_walls",
				goals = {{kind = "worldboss", target = 20}, {kind = "rift", band = "b2", target = 1200}},
				world = {open = {"cinderscar_breach"}, town = {add = {"rubble"}}}},
			{key = "omens_ashfall",
				goals = {{kind = "omen", target = 180}, {kind = "rift", band = "b3", target = 600}},
				world = {town = {add = {"wardfires"}}}},
			{key = "sepulchre_stirs",
				goals = {{kind = "raid", target = 12}, {kind = "ascended", target = 30}},
				world = {open = {"ossuary_stair"}}},
			{key = "embers_rekindled",
				goals = {{kind = "cinderheart", target = 10}, {kind = "level", level = 600, target = 80},
					{kind = "event", event = "invasion", target = 6}},
				world = {town = {remove = {"ashfall", "rubble"}, add = {"rebuilt"}}}}
		}
	},

	-- the chapter areas (plans in server/tools/areaplan/chronicle/<plan>.json, compiled with the area planner).
	--   at    {x, y, z}: the plan's ORIGIN on the world map. install_all.py step contentareas
	--         (tools/install_content_areas.py) places every chronicle plan at its own `origin`, so `at` must be that
	--         origin (tools/chronicle_areas_test.py checks it). Cells of the free block x/y 14336-15359, 10+ tiles from
	--         every other plan and generated area (docs/MAP_GUIDE.md "Content plans").
	--   gate  optional {x, y, z}: one fixed world tile for the area's gate (a staff override). Unset (2026-10-16, the owner
	--         found the temple's upper hall odd): the Chronicle Gate of each town of `gateTowns` is placed by
	--         cityportals.lua when the area opens: the Hall of Services' portal room (npc_booths_config.lua
	--         `portals.chronicle_<key>`), else beside the temple (cityportals_config.lua `towns`), with the area's name in
	--         its look text and an effect.
	-- arrival: the arrival tile's offset from the ORIGIN (from the compiled manifest; tools/chronicle_areas_test.py checks
	-- it). Until `at` (and `gate` or `gateTowns`) are set the area opens in the story only (the window says so).
	areas = {
		{key = "cinderscar_breach", name = "The Cinderscar Breach", plan = "chronicle_cinderscar_breach",
			arrival = {63, 82, 0}, minLevel = 400, at = {x = 14910, y = 15140, z = 7}},
		{key = "ossuary_stair", name = "The Ossuary Stair", plan = "chronicle_ossuary_stair",
			arrival = {59, 82, 0}, minLevel = 380, at = {x = 15100, y = 15140, z = 9}}
	},
	gateTowns = {2, 1}, -- Cinderhold and Mirewake (the towns with a Hall of Services): one gate each per open area

	-- the town changes: decoration placed at runtime around the anchor (the capital's temple, or `anchor`) and taken
	-- away again. Each piece goes on the first free tile of its offsets (ground, nothing blocking, no creature, no
	-- teleport or floor change); a piece with no free tile is skipped. Only non-blocking stock items, so no street is
	-- ever closed. Optional ground swaps between two prepared states: {dx, dy, from = id, to = id} turns the ground
	-- `from` into `to` and back (a tile whose ground is not `from` is left alone).
	town = {
		anchor = nil, -- {x =, y =, z =}
		sets = {
			ashfall = {
				pieces = {
					{id = 2249, at = {{-4, -3}, {-5, -2}, {-4, -4}}}, {id = 7349, at = {{4, -3}, {5, -2}, {4, -4}}},
					{id = 2249, at = {{-4, 3}, {-5, 2}, {-4, 4}}}, {id = 7349, at = {{4, 3}, {5, 2}, {4, 4}}},
					{id = 22509, at = {{-2, 5}, {-1, 5}, {-2, 6}}}, {id = 25834, at = {{2, 5}, {1, 5}, {2, 6}}},
					{id = 2249, at = {{0, -6}, {1, -6}, {-1, -6}}}, {id = 7349, at = {{-6, 0}, {6, 0}, {-6, 1}}}
				},
				swaps = {}
			},
			rubble = {
				pieces = {
					{id = 1308, at = {{-6, -4}, {-6, -5}, {-7, -4}}}, {id = 1311, at = {{6, -4}, {6, -5}, {7, -4}}},
					{id = 1320, at = {{-6, 4}, {-6, 5}, {-7, 4}}}, {id = 1325, at = {{6, 4}, {6, 5}, {7, 4}}},
					{id = 1336, at = {{-3, 6}, {-3, 7}, {-4, 6}}}, {id = 3124, at = {{3, 6}, {3, 7}, {4, 6}}}
				},
				swaps = {}
			},
			wardfires = {
				pieces = {
					{id = 21350, at = {{-3, -3}, {-3, -2}, {-2, -3}}}, {id = 21351, at = {{3, -3}, {3, -2}, {2, -3}}},
					{id = 21352, at = {{-3, 3}, {-3, 2}, {-2, 3}}}, {id = 21350, at = {{3, 3}, {3, 2}, {2, 3}}}
				},
				swaps = {}
			},
			rebuilt = {
				pieces = {
					{id = 6226, at = {{-4, -3}, {-5, -2}, {-4, -4}}}, {id = 6227, at = {{4, -3}, {5, -2}, {4, -4}}},
					{id = 6228, at = {{-4, 3}, {-5, 2}, {-4, 4}}}, {id = 6226, at = {{4, 3}, {5, 2}, {4, 4}}},
					{id = 6217, at = {{-2, 5}, {-1, 5}, {-2, 6}}}, {id = 6218, at = {{2, 5}, {1, 5}, {2, 6}}}
				},
				swaps = {}
			}
		}
	}
}
