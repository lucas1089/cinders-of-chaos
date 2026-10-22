-- The portal gallery at the temple of the main town (server/README.md "Temple portal gallery"). Owner 2026-10-22: "take
-- these NPCs out of the temple and do away with the Hall of Services. The portals of the Hall of Services go to the
-- temple, with decoration and the orange text saying where they go." Plain table, read by
-- server/tools/patch_map_fixes.py (through tools/hunt_teleports_dump.lua), which builds the gallery on the map, and by
-- server/tests/cityportals_test.lua (the portals' spots must match cityportals_config.lua, descent_config.lua and
-- raid_config.lua). No engine calls. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Cinderhold (town 2) is where every character starts and lives (newplayer_config.lua homeTown). The gallery takes
-- the lawn along the temple's south wall, on both sides of the entrance (the vestibule x 32367-32371 stays as it is),
-- where the NPC arcade of 2026-10-21 stood: a row against the wall (`portalRow`) with a portal tile every second
-- square (bare marble: the portal is put there at startup by its system), a marble pillar between two portals and a
-- coal basin at the outer end; a red carpet walk of three rows in front (`aisle`), all protection zone, white marble
-- floor. Each portal shows its destination in orange floating text (cityportals_config.lua `label`). The two lawn
-- columns beyond each outer end stay free (the footpaths along the temple's sides); a street lamp (`lamps`) mirrors
-- the west wing's.
return {
	enabled = true,
	items = {
		floor = 406, -- white marble floor, as the temple's
		pillar = 1515, -- marble pillar, between two portals
		light = 1484, -- coal basin, at a wing's outer end
		lamp = 1479, -- street lamp
		-- red carpet pieces: corners and edges of the walk (the temple vestibule's carpet)
		carpet = {nw = 4394, n = 4395, ne = 4396, w = 4397, c = 4398, e = 4399, sw = 4400, s = 4401, se = 4402}
	},
	towns = {
		{
			town = 2, name = "Cinderhold", temple = {x = 32369, y = 32241, z = 7}, z = 7,
			portalRow = 32245, aisle = {32246, 32247, 32248},
			-- the two wings: `outer` is the end away from the entrance (the coal basin)
			wings = {{from = 32356, to = 32365, outer = 32356}, {from = 32373, to = 32382, outer = 32382}},
			-- the portal tiles, by the kind of portal (cityportals_config.lua kinds; `descent` and `raid` are
			-- descent_config.lua's and raid_config.lua's portal.positions); the most used nearest the entrance
			portals = {
				{kind = "hideout", x = 32365},
				{kind = "descent", x = 32363},
				{kind = "memorial", x = 32361},
				{kind = "chronicle_cinderscar_breach", x = 32359},
				{kind = "worldboss", x = 32357},
				{kind = "guildhall", x = 32373},
				{kind = "raid", x = 32375},
				{kind = "chronicle_ossuary_stair", x = 32377},
				{kind = "harvest", x = 32379},
				{kind = "siege", x = 32381}
			},
			lamps = {{x = 32382, y = 32249}}
		}
	}
}
