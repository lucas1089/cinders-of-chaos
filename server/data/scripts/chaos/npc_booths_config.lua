-- The NPC booths of the hub (npc_booths.lua, npc_booths_core.lua; server/README.md "Hub NPC booths").
-- Owner 2026-10-22: "take these NPCs out of the temple and do away with the Hall of Services ... the NPCs go to the hub,
-- in the place where the current ones are. Take the current ones out and put ours there." The hub is the market of
-- Cinderhold's teleport room (the two great teleports north of the temple lead there): two rows of eight closed stalls
-- along a carpet walk, each with a counter in front and goods on display behind. The base server's shop NPCs stood in
-- them; every Chaos NPC of the main city stands there now, on the very tile the base NPC had (the spawn file's entry,
-- a bare floor tile inside the stall), and talks across the stall's counter.
-- Plain table, loaded with
--     ChaosNpcBoothsConfig = dofile("data/scripts/chaos/npc_booths_config.lua")
-- No engine calls (server/tests/npc_booths_test.lua and server/tools/patch_hub_npcs.py read it). Lua 5.1 / 5.3.
return {
	enabled = true,

	-- the town whose NPCs stand in the hub: ChaosNpcPlace.place(name, temple) with this temple, and the Keeper of
	-- Trials' placement for this town id, put an NPC named in `booths` on its booth tile instead of next to the temple
	town = 2, name = "Cinderhold", temple = {x = 32369, y = 32241, z = 7},

	-- The stalls, north row (y 32230) then south row (y 32236), west to east; x, y, z is the tile the NPC stands on.
	-- npc: the Chaos NPC of that stall, or false for a stall left empty (its counter and goods stay). Every stall is
	-- cleared of the base server's NPC (server/tools/patch_hub_npcs.py removes the spawn file entries on these tiles).
	-- The players come in from the south, through the gap in the middle of the walk (x 31646-31650): the most used NPCs
	-- stand next to it. Trade and the bank on the north row, progression and the menu services on the south row.
	booths = {
		{x = 31622, y = 32230, z = 7, npc = "Iselde Varrow"},
		{x = 31628, y = 32230, z = 7, npc = "Osric the Chandler"},
		{x = 31636, y = 32230, z = 7, npc = "Material Broker"},
		{x = 31642, y = 32230, z = 7, npc = "Loot Buyer"},
		{x = 31654, y = 32230, z = 7, npc = "Cassian Auric"},
		{x = 31660, y = 32230, z = 7, npc = "Mordecai Ashwager"},
		{x = 31666, y = 32230, z = 7, npc = "Tavish Coldhand"},
		{x = 31672, y = 32230, z = 7, npc = "Halvard Deedkeeper"},
		{x = 31622, y = 32236, z = 7, npc = "Warden Ysolde"},
		{x = 31628, y = 32236, z = 7, npc = "Archivist Maelis"},
		{x = 31636, y = 32236, z = 7, npc = "Keeper of Trials"},
		{x = 31642, y = 32236, z = 7, npc = "Ascendant Oracle"},
		{x = 31653, y = 32236, z = 7, npc = "Pell Ashmere"},
		{x = 31660, y = 32236, z = 7, npc = "Vessa Hollowmark"},
		{x = 31666, y = 32236, z = 7, npc = "Veyra the Apothecary"},
		{x = 31672, y = 32236, z = 7, npc = false}
	},

	-- The Halls of Services (2026-10-15 to 2026-10-22) are gone: no portal leads there any more. Their tiles may still
	-- be on a map that had them placed (a map master keeps them). A character who logs in inside one of these
	-- rectangles (the halls' plans: origin and size) is sent to the temple of the hall's town (npc_booths.lua).
	retiredHalls = {
		{town = 2, at = {x = 14560, y = 14820, z = 7}, size = {66, 34}},
		{town = 1, at = {x = 14560, y = 14870, z = 7}, size = {66, 34}}
	}
}
