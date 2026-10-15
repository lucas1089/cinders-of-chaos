-- The Halls of Services (npc_booths.lua, npc_booths_core.lua; server/README.md "Main city", "Halls of Services"):
-- every Chaos NPC of the main city (Cinderhold) and of Mirewake stands in a closed booth behind a stone counter, in a
-- hall reached by a portal next to the town's temple, like the base server's shop NPCs and its teleport room.
-- Owner decision 2026-10-15. Plain table, loaded with
--     ChaosNpcBoothsConfig = dofile("data/scripts/chaos/npc_booths_config.lua")
-- No engine calls (server/tests/npc_booths_test.lua and server/tools/services_halls_test.py read it). Lua 5.1 / 5.3.
--
-- The halls are area plans (server/tools/areaplan/rooms/services_*.json, biome townhall: the temples' white marble
-- and grey stone walls) placed by install step contentareas at their origin, where the map has no tile. Every offset
-- below is from the plan's ORIGIN; both halls have the same layout (same plan, other origin), so one `rows` serves all.
-- tools/services_halls_test.py compiles the plans and checks every booth, counter, light and portal tile: free floor
-- in its room, every other floor tile still reached from the arrival, each booth's front tile reached, and in front of
-- a booth its own NPC is the nearest one.
return {
	enabled = true,

	-- action ids (free block 47880-47889): the portal next to the temple, the hall's exit (the plan's exit portal is
	-- re-tagged at startup: it leads to the temple of the hall's town, not the character's), the fixtures
	aid = {entry = 47880, exit = 47881, fixture = 47882},

	-- one hall per town; `town` the town id, `plan` the area plan, `at` its ORIGIN and `size`, `arrival` and `exit` offsets
	-- (from the compiled plan; the test checks them)
	halls = {
		{town = 2, name = "Cinderhold", plan = "services_cinderhold", at = {x = 14560, y = 14820, z = 7}, size = {66, 34},
			arrival = {32, 7, 0}, exit = {32, 5, 0},
			entryOffsets = {{0, 2}}}, -- the south end of the temple, a dead end
		{town = 1, name = "Mirewake", plan = "services_mirewake", at = {x = 14560, y = 14870, z = 7}, size = {66, 34},
			arrival = {32, 7, 0}, exit = {32, 5, 0},
			entryOffsets = {{-3, 4}, {-2, 4}}} -- the south-west corner, off the way to the south doors
	},

	-- the way in: a magic forcefield next to the temple of each hall's town, on the first free tile of the hall's
	-- `entryOffsets` (checked on the base map: bare floor off every walking line), then of `offsets` (ground, nothing on
	-- it, no teleport or stairs).
	entry = {item = 1387, offsets = {{0, 2}, {1, 2}, {-1, 2}, {0, 3}, {0, -3}, {3, 1}, {-3, 1}, {1, -3}, {-1, -3}}},

	-- the fixtures, stock items: grey stone counters (as Cinderhold's temple booths), a coal basin between booths
	items = {counter = {1642, 1643}, partition = 1644, light = 1484},

	-- The booth rows. Each row lies along a wall of a room: `npcRow` the floor row against the wall (the NPCs, a
	-- partition counter on each side of every NPC, a coal basin on every other tile from `from` to `to`), `counterRow`
	-- the row in front of it (a counter on every tile from `from` to `to`): the booths are closed and nobody walks
	-- behind them. Players stand on the next row and talk across the counter (2 squares; NPC talk radius 3). Booths 5
	-- apart: in front of a booth its own NPC is always the nearest (npc lib chaos_npc_focus.lua answers the nearest).
	-- npc: a name, {[town id] = name} for a booth that differs per town, or false for a free slot (nothing is built
	-- until a name is set). A row with no NPC set is not built. An NPC listed here is placed in the booth by
	-- ChaosNpcPlace.place / the Keeper of Trials' own placement instead of next to the temple, in both towns.
	rows = {
		-- progression: ascension, the trials, tales and the town's faction
		{key = "progression", room = "progression", npcRow = 27, counterRow = 26, from = 3, to = 22, booths = {
			{x = 5, npc = "Ascendant Oracle"},
			{x = 10, npc = "Keeper of Trials"},
			{x = 15, npc = "Archivist Maelis"},
			{x = 20, npc = {[2] = "Warden Ysolde", [1] = "Forgemaster Brannoc"}}
		}},
		-- economy: selling loot, materials, the Gambler, Conquest Tokens, Candlemarks
		{key = "economy", room = "economy", npcRow = 27, counterRow = 26, from = 39, to = 62, booths = {
			{x = 41, npc = "Loot Buyer"},
			{x = 46, npc = "Material Broker"},
			{x = 51, npc = "Mordecai Ashwager"},
			{x = 56, npc = "Iselde Varrow"},
			{x = 61, npc = "Osric the Chandler"}
		}},
		-- free slots on the economy room's north wall, for NPCs whose files do not exist yet (2026-10-15): set the name
		{key = "economy_north", room = "economy", npcRow = 17, counterRow = 18, from = 39, to = 48, booths = {
			{x = 41, npc = false, slot = "stash keeper"},
			{x = 46, npc = false, slot = "pocket boss NPC"}
		}}
	},

	-- the portals of the systems that open a window (Ember Descent, the raid), in the hall's portal room: offsets from
	-- the ORIGIN. descent_config.lua and raid_config.lua `portal.positions` hold the world tiles (the test checks them).
	portals = {descent = {29, 23}, raid = {34, 23}}
}
