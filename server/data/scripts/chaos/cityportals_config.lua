-- City portals: the labelled forcefields next to the temples (server/README.md "City portals"; cityportals_core.lua,
-- cityportals.lua, cityportals_fx.lua). One place for where the Hideout, Guild Hall and Hall of Services portals stand,
-- what their look text says and which effect marks them. No engine calls (server/tests/cityportals_test.lua reads it).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Where a portal goes, first match wins (cityportals_core.lua C.candidates):
--   1. the town's Hall of Services, when the kind has a tile there (`hall` keys of npc_booths_config.lua `portals`)
--      and the hall is on the map: the portal room, next to the Ember Descent and raid portals;
--   2. the town's fixed spot in `towns` (offsets from the temple), used only while the temple is where `temple` says
--      (another map keeps the fallback);
--   3. the caller's own offsets, then `offsets` below: the first free tile.
-- The spots in `towns` were chosen on the reference map (2026-10-16): bare floor of the temple area, two side by
-- side along a wall or the edge of the square, off every shortest way from the temple to its doors, stairs and edges,
-- not next to stairs or a door, never a tile the NPC placements around the temple pick first, and the temple area
-- stays connected with both portals placed.
return {
	item = 1387, -- magic forcefield (teleport type), used without destination + an action id
	pulseMs = 4000, -- every portal shows its effect this often (cityportals_fx.lua)

	-- name and look text (server texts, Chaos.t; pt-BR in i18n_strings.lua); effect: a CONST_ME_* name
	kinds = {
		hideout = {name = "Hideout Portal", effect = "CONST_ME_MAGIC_BLUE",
			text = "Step in to enter your own hideout. Its exit portal brings you back to this spot."},
		guildhall = {name = "Guild Hall Portal", effect = "CONST_ME_MAGIC_GREEN",
			text = "Members of a guild that owns a guild hall step in to enter it. Its exit portal leads to your temple."},
		services = {name = "Hall of Services Portal", effect = "CONST_ME_MAGIC_RED",
			text = "Step in to enter the Hall of Services: the town's Chaos NPCs behind their counters, the Ember Descent and the raid portals. Its exit portal leads back to this temple."},
		memorial = {name = "Memorial Portal", effect = "CONST_ME_PURPLEENERGY",
			text = "Step in to visit the Ember Memorial: the season's realm firsts, its records and its fallen. Its exit portal leads to your temple."},
		worldboss = {name = "World Boss Portal", effect = "CONST_ME_MORTAREA",
			text = "Open while a world boss is awake: step in to join the fight in its arena. The arena's exit portal leads to your temple."},
		chronicle = {name = "Chronicle Gate", effect = "CONST_ME_MAGIC_BLUE",
			text = "Step in to reach a chapter area of the Ashen Chronicle that the story has opened. Its exit portal leads to your temple."},
		descent = {name = "Ember Descent Portal", effect = "CONST_ME_FIREAREA",
			text = "Step in to open the Ember Descent: a roguelike trial for level 100+, alone or with up to three party members."},
		raid = {name = "Raid Portal", effect = "CONST_ME_MORTAREA",
			text = "Step in to open the raid window: the Ashen Sepulchre for a party of 5 to 15, level 800+."},
		hunt = {name = "Hunting Area Portal", effect = "CONST_ME_MAGIC_GREEN",
			text = "Step in to enter this hunting area; the portal refuses characters below its level. Its exit portal leads back here."},
		idlehall = {name = "Idle Hall Exit", effect = "CONST_ME_MAGIC_BLUE",
			text = "Step in to go back to your temple. Characters who stand idle in town are moved to this hall."},
		siege = {name = "Guild Siege Portal", effect = "CONST_ME_YELLOW_RINGS",
			text = "Open while a guild siege runs: members of a signed-up guild step in to reach their base. The base's exit portal leads to your temple."},
	},

	-- kinds that stand in the portal room of a Hall of Services (Cinderhold and Mirewake) when the hall is on the map
	-- (spots, not kinds: the two Chronicle Gates are kind `chronicle`, one spot each, chronicle.lua)
	hall = {hideout = true, guildhall = true, memorial = true, chronicle_cinderscar_breach = true,
		chronicle_ossuary_stair = true},

	-- town id -> {temple = {x, y, z} the spots were chosen for, [kind] = {dx, dy} from the temple}
	towns = {
		[1] = {temple = {32957, 32076, 7}, hideout = {4, -4}, guildhall = {3, -4}, memorial = {3, -3}, -- Mirewake (no hall)
			chronicle_cinderscar_breach = {2, -3}, chronicle_ossuary_stair = {4, -2}},
		[2] = {temple = {32369, 32241, 7}, hideout = {5, -4}, guildhall = {5, -3}, memorial = {5, -2}, -- Cinderhold (no hall)
			chronicle_cinderscar_breach = {4, -4}, chronicle_ossuary_stair = {5, -6}},
		[3] = {temple = {32649, 31925, 11}, hideout = {-2, 4}, guildhall = {-1, 4}}, -- Anvildeep
		[4] = {temple = {32360, 31782, 7}, hideout = {-3, -2}, guildhall = {-3, -3}}, -- Thornmere
		[5] = {temple = {32732, 31634, 7}, hideout = {1, -2}, guildhall = {1, -3}}, -- Gloamroot
		[6] = {temple = {32097, 32219, 7}, hideout = {-4, 2}, guildhall = {-4, 1}}, -- Kindle Isle
		[7] = {temple = {32317, 32826, 7}, hideout = {-4, -1}, guildhall = {-4, 0}}, -- Saltgrave
		[8] = {temple = {32594, 32745, 7}, hideout = {1, -4}, guildhall = {0, -4}}, -- Fevergate
		[9] = {temple = {33194, 32853, 8}, hideout = {3, 0}, guildhall = {3, -1}}, -- Dunescar
		[10] = {temple = {33213, 32454, 1}, hideout = {4, 2}, guildhall = {4, 1}}, -- Scorchveil
		[11] = {temple = {33217, 31814, 8}, hideout = {-2, -5}, guildhall = {-1, -5}}, -- Bellwatch
		[12] = {temple = {32212, 31132, 7}, hideout = {0, -4}, guildhall = {-1, -4}}, -- Rimeholt
		[13] = {temple = {32787, 31276, 7}, hideout = {-1, 3}, guildhall = {-2, 3}}, -- Hollowspire
		[14] = {temple = {33023, 31521, 11}, hideout = {5, -7}, guildhall = {6, -7}}, -- Slagdelve
		[28] = {temple = {33447, 31323, 9}, hideout = {1, 3}, guildhall = {0, 3}}, -- Ashstrand
		[29] = {temple = {33513, 32363, 6}, hideout = {-1, -2}, guildhall = {0, -2}}, -- Nightwrack
		[31] = {temple = {32316, 31942, 7}, hideout = {-2, 1}, guildhall = {-2, 0}}, -- Isle of Hush
		[32] = {temple = {32091, 32027, 7}, hideout = {1, 3}, guildhall = {2, 3}}, -- Isle of Oaths
		[33] = {temple = {33594, 31899, 6}, hideout = {0, -3}, guildhall = {-1, -3}}, -- Brassgate
		[34] = {temple = {33657, 31665, 8}, hideout = {0, 4}, guildhall = {1, 4}}, -- Wyrmscar
	},

	-- the last resort on any map: the first free tile (ground, nothing on it, no teleport, stairs or house)
	offsets = {{3, -3}, {-3, -3}, {3, 3}, {-3, 3}, {4, -2}, {-4, -2}, {4, 2}, {-4, 2}, {2, -4}, {-2, -4}, {2, 4}, {-2, 4}},
}
