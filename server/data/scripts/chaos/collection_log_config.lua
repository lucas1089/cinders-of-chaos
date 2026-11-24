-- collection_log_config.lua: the Collection log (O753; collection_log.lua, collection_log_core.lua, client game_collectionlog).
-- Plain table. server/README.md "Collection log (O753)".
return {
	enabled = true,
	opcode = 170, -- ChaosOpcodes.collectionLog (server/README.md "Opcode collision check")
	table = "chaos_collection_log", -- one row per character and item (server/sql/chaos_collection_log.sql)
	rateLimitMs = 1500, -- one sync a character in this time
	-- the groups, in the window's order; a set group is "set:<key>" and takes the set's name
	groupOrder = {"pinnacle", "ascended", "raid", "boss", "endgame", "set", "hunt", "card"},
	-- the English labels (pt-BR in the client's pt_br.lua); %s = the set's name
	labels = {
		pinnacle = "Pinnacle bosses", ascended = "Ascended bosses", raid = "Raid: Ashen Sepulchre", boss = "Boss uniques",
		endgame = "Endgame uniques", set = "Set: %s", hunt = "Hunting uniques", card = "Cards"
	}
}
