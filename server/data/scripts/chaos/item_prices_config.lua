-- The Loot Buyer NPCs and the item price table (item_prices.lua, data/lib/chaos_item_prices.lua; server/README.md
-- "Item prices"). The prices themselves are generated: data/lib/chaos_item_prices_data.lua (tools/gen_item_prices.py).
-- Plain table. Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then restart (the NPCs are placed at startup).
return {
	enabled = true,
	-- the NPC (data/npc/Loot Buyer.xml, installed by tools/install_item_prices.py); one next to every temple
	npc = {
		name = "Loot Buyer",
		towns = "all", -- "all" = every town of the map; or a list of town ids
		delayMs = 2600, -- after the Material Brokers (1600); a tile another NPC took is skipped
		-- tiles next to the temple, tried in this order (the first free walkable one wins)
		offsets = {{-4, 3}, {4, 3}, {-5, 0}, {5, 0}, {0, -5}, {0, 5}, {-4, -3}, {4, -3}, {-2, 5}, {2, 5}, {-6, 2}, {6, 2}},
		-- no free tile near the temple (Nightwrack: a small temple room with stairs only): near the town's depot
		place = {depotFallback = true}
	},
	-- the NPC script reads these too (data/npc/scripts/loot_buyer.lua)
	appraiseLines = 12 -- items listed by "appraise", most valuable first
}
