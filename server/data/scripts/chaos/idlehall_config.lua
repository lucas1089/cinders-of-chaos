-- idlehall_config.lua: the numbers of the Idle Hall (server/README.md "Idle Hall"). Pure data, loaded with
--     ChaosIdleHallConfig = dofile("data/scripts/chaos/idlehall_config.lua")
-- Rules: idlehall_core.lua (server/tests/idlehall_test.lua). Engine glue: idlehall.lua. The hall's map:
-- server/tools/areaplan/rooms/idle_hall.json (install_all.py step contentareas; server/tools/idle_hall_test.py checks the
-- slots below on the compiled plan).
--
-- A character that stood idle in a town for idleMinutes is moved to the Idle Hall, a calm protected room with exercise
-- dummies, so the temples do not fill up with idle characters (owner request 2026-10-15; every online character earns
-- Candlemarks, idle or not, so many idle characters are expected). One warning comes warnSeconds before the move.
-- Idle = no action of the player: no step, no turn, no item moved, no trade, no spell, no public chat line, no request
-- of an interactive window (activityOpcodes). Being pushed by someone else is not an action.
-- Only in a town: a protection zone tile within town.radius sqm of a temple (town.floors floors up or down), not a
-- house tile, not in town.exclude, or a tile in town.include. Never staff, never in an instance (Chaos.inAnyInstance),
-- never while exercise training.

return {
	enabled = true,
	idleMinutes = 10, -- idle this long in a town: moved to the hall
	warnSeconds = 60, -- the warning comes this long before the move ("in 1 minute")

	-- the check: every thinkMs one of `slices` groups of characters (by creature id) is looked at, so each character is
	-- sampled every thinkMs x slices (10 s): one getPosition and one getDirection; the town check only once one is due
	thinkMs = 1000,
	slices = 10,
	recheckSeconds = 60, -- a character that is due but outside a town (or exempt) is checked again after this

	-- the towns: every town of the map (Game.getTowns(); townIds = a list limits it), around its temple
	town = {
		radius = 60, -- sqm from the temple in x and in y
		floors = 2, -- floors above and below the temple's
		townIds = nil, -- nil: every town
		-- boxes {from = {x, y, z}, to = {x, y, z}} (inclusive): include counts as town even far from a temple (still a
		-- protection zone, still not a house); exclude never counts (boats, an arena's waiting room, ...)
		include = {},
		exclude = {}
	},

	-- the base exercise script (data/actions/scripts/other/exercise_weapons.lua) sets this player storage to 1 while a
	-- character trains on a dummy (data/lib/core/storages.lua Exercise_Training.isTraining); a training character is
	-- never moved. The base table's value wins when it is loaded.
	trainingStorage = 37100,

	-- extended opcodes (names of ChaosOpcodes) that count as an action: the windows a player works in while standing
	-- (market, store, stash, bank, crafting, ...). Other opcodes do not count: some modules send on their own.
	activityOpcodes = {"market", "orbExchange", "shop", "stash", "bank", "crafting", "transmog", "candlemarks",
		"townPortal"},

	-- the hall: server/tools/areaplan/rooms/idle_hall.json, placed by install step contentareas at the plan's `origin`
	-- (14600, 14760, 7: the free band west of the Memorial's plaza, docs/MAP_GUIDE.md "Content plans"). `at` is that
	-- origin; arrival and every slot are offsets from it (tools/idle_hall_test.py checks them on the compiled plan:
	-- free floor in the right room, the arrival, no tile cut off). The plan's exit portal (action id 47951, areagen.lua)
	-- leads to the temple of the character's town.
	hall = {plan = "idle_hall", at = {x = 14600, y = 14760, z = 7}, arrival = {22, 13, 0}},
	slots = {
		dummies = {{4, 10}, {7, 10}, {11, 10}, {7, 13}}, -- the training room (west)
		benches = {{32, 10}, {35, 10}, {32, 13}, {37, 15}}, -- the rest room (east)
		sign = {21, 13} -- beside the arrival
	},
	-- base items: the exercise dummies (the store's exercise weapons work on them), a bench, a sign (read from afar)
	items = {dummies = {27751, 27752}, bench = 1662, sign = 1429},
	-- action ids 47910-47919: the hall's fixtures (placed at startup, found again after a reload)
	aid = {fixture = 47910},

	effect = 11 -- CONST_ME_TELEPORT, where the character leaves and where it arrives
}
