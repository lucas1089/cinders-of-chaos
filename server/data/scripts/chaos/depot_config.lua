-- The depot, retired (O316, owner 2026-10-29, pt-BR: "Retire o depot do jogo"). The stash is the only item storage
-- (stash_config.lua). What stays of the depot is what the base engine needs: the lockers (they hold the inbox and the
-- market item that mail, house transfers and the market use), the depot chest (withdraw-only; its content moves into the
-- stash at the first locker opening) and the boxes the old depot tabs were made of.
-- Read by depot.lua (engine glue), depot_core.lua (the rules, through depot.lua), stash.lua (it finds the boxes when it
-- moves a depot), tools/patch_base_depot.py (box ids, names, slots) and server/tests/depot_test.lua.
-- The engine also loads this file as a script because it lives under data/scripts; it only returns a table.
-- See server/README.md "Depot (retired)". Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	-- the tab containers the old depot used: tab n is boxIds[n] (the base server's numbered depot boxes I..XVII, renamed and
	-- made 100 slots by tools/patch_base_depot.py). Nothing makes them any more; the ones that exist hold the old items.
	boxIds = {25453, 25454, 25455, 25456, 25457, 25458, 25459, 25460, 25461, 25462, 25463, 25464, 25465, 25466, 25467,
		25468, 25469},
	boxName = "depot tab %d", -- items.xml name of box n (patch_base_depot.py)
	boxSlots = 100, -- items.xml containerSize of the boxes (patch_base_depot.py)
	chestIds = {2594}, -- the depot chest (ITEM_DEPOT)
	lockerIds = {2589, 2590, 2591, 2592}, -- the lockers (type "depot")

	-- the inbox and the market item in every locker (the engine's mail and the market use them; players reach the inbox
	-- through the stash window and the market through the top bar)
	inboxId = 14404,
	marketId = 14405,

	-- the base server's locker Action (a sound) that calls ChaosDepot.onOpenLocker (patch_base_depot.py writes the
	-- hook); when this file is missing depot.lua registers its own locker Action instead
	lockerScript = "data/scripts/customs/actions/sounds/depot.lua",

	messages = {
		-- a move into the depot chest or a box (the depot is withdraw-only; the stash takes everything)
		closed = "The depot is retired: store items in the stash (Economy > Supply Stash). You can still take items out.",
		-- the line a locker opening shows
		locker = "The depot is retired: your things are in the stash. Open it from Economy > Supply Stash."
	}
}
