-- Orange name labels over tiles (tile_labels.lua, pure part tile_labels_core.lua; server/README.md "Tile labels").
-- Owner 2026-10-18: the area of the new NPCs shows their names as orange text. Since 2026-10-22 that area is the hub
-- (the market of Cinderhold's teleport room, npc_booths_config.lua). Plain table, loaded with dofile. Lua 5.1 / LuaJIT
-- and 5.3.
return {
	enabled = true,
	-- the text colour: the client palette byte of TEXTCOLOR_ORANGE (combat_fx.lua M.label sends one byte)
	color = 198,
	intervalMs = 3000, -- the animated text fades after about two seconds; it is sent again this often
	-- Every stall of the hub with a Chaos NPC (npc_booths_config.lua) shows the NPC's name over its tile (derived: a
	-- stall given an NPC there is labelled without an edit here).
	booths = true,
	-- Extra labels at fixed tiles: {text = "Name", pos = {x = 0, y = 0, z = 7}}. Empty until the owner gives the tiles.
	labels = {}
}
