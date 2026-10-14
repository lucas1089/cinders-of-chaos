-- Everfull Ration (store_food.lua; server/tools/install_store_food.py reads `item`): the store's infinite food.
-- The engine also loads this file as a script because it lives under data/scripts; it only sets a table.
-- README "Store pouches and the Everfull Ration". Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosStoreFoodConfig = {
	-- the item: a new items.otb node (install_store_food.py), a copy of the stock dragon ham node `sourceId` (flags,
	-- attributes, stackable like it: the client reads a count for a stackable look), with the server id `id`. Its look:
	-- the dragon ham's client id until the client pair has our art; then ownLook = true gives it `clientId`
	-- (client/tools/sprites/gen_store_food_art.py, appended by import_art_things.py with art_import/store_food.csv;
	-- client MANIFEST.md "Everfull Ration look").
	item = {id = 32084, sourceId = 2672, clientId = 33904, ownLook = false, weight = 300, article = "an",
		name = "everfull ration", plural = "everfull rations",
		description = "Store item: never runs out, cannot be traded, sold or dropped. Eat from it like the best food: " ..
			"12 minutes of regeneration a bite, until you are full."},

	-- one bite = the best stock food (the dragon ham, the marlin and the roasted meat of the base food.lua: 60 x 12 s
	-- of regeneration); "You are full." at the same cap as every food (1200 s of regeneration)
	foodValue = 60,
	secondsPerValue = 12,
	maxSeconds = 1200,
	sound = "Chomp.",
	exhaustMs = 1000, -- one bite a second at most (the engine's own action exhaust is shorter)

	-- player storage (chaos_constants.lua store services range 7100100 - 7100159): 1 = a ration lost with a dropped
	-- backpack, given back at the next login
	storage = {regrant = 7100151},

	-- custom attributes (the same keys as the store pouches: pouches.lua refuses ground, mail, trade, the player market
	-- and other players' containers for any item with chaos_storebound)
	attr = {owner = "chaos_food_owner", storebound = "chaos_storebound", lock = "chaos_locked"}
}
return ChaosStoreFoodConfig
