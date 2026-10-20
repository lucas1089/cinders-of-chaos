-- Orange name labels over tiles (tile_labels.lua, pure part tile_labels_core.lua; server/README.md "Tile labels").
-- Owner 2026-10-18: the area of the new NPCs (the Halls of Services) shows their names as orange text, and the
-- corners of the area show its section titles. Plain table, loaded with dofile. Lua 5.1 / LuaJIT and 5.3.
return {
	enabled = true,
	-- the text colour: the client palette byte of TEXTCOLOR_ORANGE (combat_fx.lua M.label sends one byte)
	color = 198,
	intervalMs = 3000, -- the animated text fades after about two seconds; it is sent again this often
	-- Every NPC booth of every hall of npc_booths_config.lua shows its NPC's name over the NPC's tile (derived: a
	-- booth or hall added there is labelled without an edit here).
	booths = true,
	-- The section title of each booth row of the halls, shown at both ends of the row (its corners): [row key] = text.
	-- A row not listed (or false) has none.
	rowTitles = {progression = "Progression", economy = "Economy", economy_north = false},
	-- Extra labels at fixed tiles (the corners of an area whose layout is not in npc_booths_config.lua):
	-- {text = "Name", pos = {x = 0, y = 0, z = 7}}. Empty until the owner gives the tiles.
	labels = {}
}
