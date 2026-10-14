-- The Capital Memorial (memorial.lua, memorial_core.lua; client game_chronicle Memorial tab, extended opcode
-- ChaosOpcodes.chronicle = 171, actions mem / memset; website page.php?plugin=chaos&p=memorial). Every number lives
-- here. Returned as a table and loaded as Chaos.memorialConfig = dofile("data/scripts/chaos/memorial_config.lua").
-- Item ids are SERVER ids of stock items (the area planner's decoration kits). Overview: server/README.md "The Capital
-- Memorial". Lua 5.1 / LuaJIT and Lua 5.3.
return {
	enabled = true,
	opcode = 171,
	staffGroup = 4, -- staff characters are never on the Memorial
	tickSeconds = 60,
	refreshSeconds = 600, -- the entries are read again from the records, the firsts and the Hardcore falls
	rotateSeconds = 600, -- more entries than statues: the next page every 10 minutes

	-- DB tables (server/sql/chaos_memorial.sql; memorial.lua creates them at startup when missing)
	tables = {optin = "chaos_memorial_optin", entries = "chaos_memorial_entries"},

	-- the character setting "Show me on the Memorial" (client Adventure > Chronicle > Memorial; off any time). Without a
	-- row: records and realm firsts are shown (they are on the leaderboards already), a Hardcore fall is not; the fall
	-- asks at the next login (a modal window, and the client's dialog).
	defaults = {records = true, fallen = false},
	modalId = 7480, -- the question after a Hardcore fall

	-- the plaza: server/tools/areaplan/chronicle/capital_memorial.json, compiled and placed by the owner with
	-- `area_planner.py place OUT/capital_memorial.otbm WORLD.otbm COPY.otbm --at X Y Z` (docs/OWNER_TODO.md). Set `at`
	-- to that X Y Z: every slot below is an offset from the plan's ORIGIN (tools/chronicle_areas_test.py checks them on
	-- the compiled plan: free floor in the right hall, no route cut off). Until `at` is set nothing is placed.
	plaza = {plan = "capital_memorial", at = nil}, -- at = {x =, y =, z =}

	-- action ids 47930-47939
	aid = {first = 47930, record = 47931, fallen = 47932, stone = 47933},
	-- the items: realm firsts on guardian statues, records on statues, the fallen on grave stones, and the Memorial
	-- stone (a stone circle, walkable) in the middle of the plaza. Look at one: its text is the entry.
	items = {first = {8836, 8837}, record = {1443, 1448, 1450}, fallen = {1407, 1408}, stone = 1421},
	slots = {
		first = {{8, 15}, {5, 16}, {10, 16}, {4, 17}, {7, 17}, {10, 18}, {4, 19}, {4, 21}}, -- the hall of firsts (west)
		record = {{37, 15}, {36, 16}, {39, 16}, {41, 16}, {36, 18}, {42, 18}, {42, 20}, {36, 22}}, -- the hall of records (east)
		fallen = {{13, 4}, {18, 4}, {20, 4}, {24, 4}, {28, 4}, {36, 4}, {11, 5}, {15, 5}, {22, 5}, {26, 5}, {33, 5}, {16, 6}},
		stone = {23, 20}
	},

	-- the records on the statues: the season's best of each board and variant (any party size); order = statue order
	boards = {"wb_time", "ascended", "omen", "raid", "rift_tier", "tower_floor", "descent", "arena"},
	maxEntries = {first = 60, record = 60, fallen = 120} -- per season and kind (oldest firsts, best records, highest falls)
}
