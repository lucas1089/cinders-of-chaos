-- The NPC arcade at the temple of the main town (server/README.md "Temple NPC arcade"; owner 2026-10-21: "the new NPCs
-- are scattered: put them at the temple, tidy, with nice decoration"). Plain table, loaded with dofile by
-- npc_place_core.lua (K.templeStand) and read by server/tools/patch_map_fixes.py (through tools/hunt_teleports_dump.lua),
-- which builds the arcade on the map. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Cinderhold (town 2) is where every character starts and lives (newplayer_config.lua homeTown). Its temple has no free
-- floor inside, so the arcade takes the lawn along the temple's south wall, on both sides of the entrance (the
-- vestibule x 32367-32371 stays as it is): a closed row of booths against the wall (`npcRow`: an NPC, a counter
-- partition between two NPCs, a coal basin at the outer end), a stone counter in front (`counterRow`), and a red carpet
-- walk of two rows in front of that (`aisle`), all protection zone, white marble floor. Players stand on the carpet and
-- talk across the counter (2 squares). NPCs stand 2 apart: on the carpet in front of a booth its own NPC is the nearest
-- (chaos_npc_focus.lua: same distance, the straighter line answers). The wings mirror each other around the entrance
-- (x 32369); the two lawn columns beyond each outer end stay free (the footpaths along the temple's sides), and a
-- street lamp (`lamps`) mirrors the west wing's.
-- Every NPC named in `stands` stands there in this town instead of in its Hall of Services booth
-- (npc_booths_config.lua leaves their Cinderhold booths free) or next to the temple. NPCs of a fixed place by design
-- (Widow Hessa in the Haunted Harvest, the Wandering Merchant, the faction NPCs of other towns) and the progression
-- NPCs of the hall (Ascendant Oracle, Keeper of Trials, Archivist Maelis, the town's faction NPC Warden Ysolde) are
-- not listed.
return {
	enabled = true,
	items = {
		floor = 406, -- white marble floor, as the temple's
		counter = {1642, 1643}, -- grey stone counter, as the Halls of Services' booths
		partition = 1644,
		light = 1484, -- coal basin
		plant = 8011, -- plants (a booth without an NPC)
		lamp = 1479, -- street lamp
		-- red carpet pieces: corners and edges of the walk (the temple vestibule's carpet)
		carpet = {nw = 4394, n = 4395, ne = 4396, w = 4397, c = 4398, e = 4399, sw = 4400, s = 4401, se = 4402}
	},
	towns = {
		{
			town = 2, name = "Cinderhold", temple = {x = 32369, y = 32241, z = 7}, z = 7,
			npcRow = 32245, counterRow = 32246, aisle = {32247, 32248},
			-- the two wings: `outer` is the end away from the entrance (the coal basin)
			wings = {{from = 32356, to = 32365, outer = 32356}, {from = 32373, to = 32382, outer = 32382}},
			-- economy west of the entrance, services east; the most used nearest the entrance
			stands = {
				{name = "Loot Buyer", x = 32365},
				{name = "Material Broker", x = 32363},
				{name = "Osric the Chandler", x = 32361},
				{name = "Mordecai Ashwager", x = 32359},
				{name = "Iselde Varrow", x = 32357},
				{name = "Cassian Auric", x = 32373},
				{name = "Tavish Coldhand", x = 32375},
				{name = "Halvard Deedkeeper", x = 32377},
				{name = "Vessa Hollowmark", x = 32379},
				{name = "Pell Ashmere", x = 32381}
			},
			free = {}, -- booths without an NPC (plants)
			lamps = {{x = 32382, y = 32249}}
		}
	}
}
