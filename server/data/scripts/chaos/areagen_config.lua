-- Area generator (areagen.lua, areagen_core.lua; server/README.md "Generated areas", docs/MAP_GUIDE.md
-- "Generated areas"): every number, palette and area. Plain table, loaded with
--     ChaosAreaGenConfig = dofile("data/scripts/chaos/areagen_config.lua")
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Item ids are server ids of the stock items (items.otb 3.57 of the live server) and, for the `dark` overrides, names
-- of our dark tile set (data/lib/chaos_dark_tiles.lua; used only when it is installed). Every id was checked against
-- the live items.otb and the live client pair with `server/tools/areagen_export.py check` (each id is known, has a
-- client sprite, and grounds are grounds, borders are borders). Border pieces and wall pieces were measured on the
-- live map with `tools/map/derive_borders.py` (the piece each neighbour pattern carries there).
return {
	enabled = true,

	-- action ids of the two portals (free block 47950-47959)
	aid = {entrance = 47950, exit = 47951},

	-- the generated areas tick: respawns and the leash (seconds)
	tickSeconds = 2,
	-- a monster farther than this from its spawn point and out of a fight is walked back there
	leash = 14,
	-- respawn: like the engine, a dead point waits its spawntime and starts again while a player sees the spot; the
	-- dynamic respawn's percent (respawn_core.lua, respawn_config.lua) applies to the hunters near the point
	viewRange = {x = 9, y = 7},

	items = {
		hole = 8972, -- large hole (floor change down, an item over the ground)
		ladder = 1386, -- ladder (stock "other/teleport.lua" action: up to the tile south of the hole)
		portal = 1387 -- magic forcefield (type teleport); entrance and exit carry the action ids above
	},

	-- ground families: grounds with their weights and the z order (the higher family draws its border over the lower)
	families = {
		cave = {z = 200, grounds = {{351, 6}, {352, 1}, {353, 1}, {354, 1}, {355, 1}}},
		cracks = {z = 100, grounds = {{5815, 1}}},
		lava = {z = 50, grounds = {{598, 7}, {599, 1}, {600, 1}, {601, 1}}, walk = false},
		mud = {z = 1100, grounds = {{11561, 1}}},
		earth = {z = 10500, grounds = {{101, 150}, {5711, 1}, {5712, 1}, {5713, 1}, {5714, 1}, {5715, 1}, {5716, 1},
			{5717, 1}, {5718, 1}, {5719, 1}, {5720, 1}, {5721, 1}, {5722, 1}, {5723, 1}, {5724, 1}, {5725, 1}, {5726, 1}},
			walk = false},
		mountain = {z = 9900, grounds = {{919, 1}}, walk = false},
		rockfloor = {z = 2000, grounds = {{9068, 1}, {9069, 1}, {9070, 1}, {9071, 1}, {9072, 1}, {9073, 1}}},
		basalt = {z = 5700, grounds = {{17625, 1}, {17626, 1}, {17627, 1}, {17628, 1}}},
		slate = {z = 1, grounds = {{10766, 25}, {10767, 20}, {10768, 20}, {10769, 10}, {10770, 5}, {10771, 3},
			{10772, 25}, {10773, 25}, {10774, 25}}, indoor = true},
		marble = {z = 1, grounds = {{407, 1}}, indoor = true},
		tiles = {z = 1, grounds = {{414, 1}}, indoor = true},
		flagstone = {z = 1, grounds = {{3152, 25}, {3153, 25}, {3154, 5}, {3155, 5}, {3156, 3}, {3157, 1}}, indoor = true},
		-- dark tile set (names, ids from ChaosDarkTiles when installed)
		darkmoss = {z = 3000, grounds = {{"dark_moss", 1}}},
		ash = {z = 2500, grounds = {{"ash_soil", 7}, {"bone_earth", 3}}},
		-- the rift themes (rift_layout_core.lua): the old rift floors (rift floor, dark sandy and rutted stone, gilded
		-- stone) and two more dark grounds
		riftfloor = {z = 2100, grounds = {{25549, 6}, {25704, 1}, {25705, 1}, {25706, 1}, {25707, 1}, {25708, 1}, {25709, 1}}},
		crypt = {z = 1500, grounds = {{13189, 3}, {12237, 2}}},
		gilded = {z = 1, grounds = {{415, 1}}, indoor = true},
		obsidian = {z = 2800, grounds = {{"obsidian_floor", 9}, {"magma_floor", 1}}},
		wetrock = {z = 2600, grounds = {{"wet_rock", 7}, {"mossy_rock", 3}}}
	},

	-- border pieces drawn over the lower family: borders[over][under] (or ["*"] for any lower family) = piece set
	borders = {
		earth = {["*"] = "dirt_wall"},
		mountain = {["*"] = "gravel"},
		cave = {lava = "cave_over_lava", cracks = "cave_edge"},
		mud = {cave = "mud"},
		rockfloor = {lava = "dark_rock", cracks = "dark_rock"},
		basalt = {rockfloor = "basalt_edge"},
		darkmoss = {["*"] = "dark_moss"},
		ash = {["*"] = "ash_soil"},
		obsidian = {["*"] = "obsidian_floor"},
		wetrock = {["*"] = "wet_rock"}
	},

	-- the 12 pieces of each set (n, e, s, w: that side; c..: that corner only; d..: two sides and the corner);
	-- measured on the live map, share of the winning piece in brackets
	pieces = {
		-- earth over cave floor (dirt walls, blocking; 56-86 %)
		dirt_wall = {n = 5632, e = 5637, s = 5638, w = 5631, cnw = 5635, cne = 5636, csw = 5634, cse = 5633,
			dnw = 5647, dne = 5651, dsw = 5650, dse = 5649},
		-- mountain over any walkable ground (blocking; 89-99 %)
		gravel = {n = 4471, e = 4468, s = 4469, w = 4472, cnw = 4475, cne = 4474, csw = 4473, cse = 4470,
			dnw = 4476, dne = 4478, dsw = 4477, dse = 4479},
		-- cave floor over lava pools (39-97 %)
		cave_over_lava = {n = 4808, e = 4809, s = 4810, w = 4811, cnw = 4812, cne = 4813, csw = 4814, cse = 4815,
			dnw = 4816, dne = 4817, dsw = 4818, dse = 4819},
		-- cave floor over small lava cracks (67-100 %)
		cave_edge = {n = 4796, e = 4797, s = 4798, w = 4799, cnw = 4800, cne = 4801, csw = 4802, cse = 4803,
			dnw = 4804, dne = 4805, dsw = 4806, dse = 4807},
		-- mud over cave floor (96-100 %)
		mud = {n = 11775, e = 11778, s = 11777, w = 11776, cnw = 11785, cne = 11786, csw = 11788, cse = 11787,
			dnw = 11789, dne = 11790, dsw = 11792, dse = 11791},
		-- rock floor over lava and lava cracks (43-100 %)
		dark_rock = {n = 7079, e = 7080, s = 7081, w = 7082, cnw = 7083, cne = 7084, csw = 7085, cse = 7086,
			dnw = 7087, dne = 7088, dsw = 7089, dse = 7090},
		-- basalt floor over rock floor (76-100 %)
		basalt_edge = {n = 17630, e = 17631, s = 17629, w = 17632, cnw = 17639, cne = 17640, csw = 17638, cse = 17637,
			dnw = 17635, dne = 17636, dsw = 17634, dse = 17633},
		-- dark tile set (chaos_dark_paint.lua pieces: outer = c.., inner = d..)
		dark_moss = {n = "dark_moss_border_n", e = "dark_moss_border_e", s = "dark_moss_border_s", w = "dark_moss_border_w",
			cnw = "dark_moss_border_outer_nw", cne = "dark_moss_border_outer_ne", csw = "dark_moss_border_outer_sw",
			cse = "dark_moss_border_outer_se", dnw = "dark_moss_border_inner_nw", dne = "dark_moss_border_inner_ne",
			dsw = "dark_moss_border_inner_sw", dse = "dark_moss_border_inner_se"},
		ash_soil = {n = "ash_soil_border_n", e = "ash_soil_border_e", s = "ash_soil_border_s", w = "ash_soil_border_w",
			cnw = "ash_soil_border_outer_nw", cne = "ash_soil_border_outer_ne", csw = "ash_soil_border_outer_sw",
			cse = "ash_soil_border_outer_se", dnw = "ash_soil_border_inner_nw", dne = "ash_soil_border_inner_ne",
			dsw = "ash_soil_border_inner_sw", dse = "ash_soil_border_inner_se"},
		obsidian_floor = {n = "obsidian_floor_border_n", e = "obsidian_floor_border_e", s = "obsidian_floor_border_s",
			w = "obsidian_floor_border_w", cnw = "obsidian_floor_border_outer_nw", cne = "obsidian_floor_border_outer_ne",
			csw = "obsidian_floor_border_outer_sw", cse = "obsidian_floor_border_outer_se",
			dnw = "obsidian_floor_border_inner_nw", dne = "obsidian_floor_border_inner_ne",
			dsw = "obsidian_floor_border_inner_sw", dse = "obsidian_floor_border_inner_se"},
		wet_rock = {n = "wet_rock_border_n", e = "wet_rock_border_e", s = "wet_rock_border_s", w = "wet_rock_border_w",
			cnw = "wet_rock_border_outer_nw", cne = "wet_rock_border_outer_ne", csw = "wet_rock_border_outer_sw",
			cse = "wet_rock_border_outer_se", dnw = "wet_rock_border_inner_nw", dne = "wet_rock_border_inner_ne",
			dsw = "wet_rock_border_inner_sw", dse = "wet_rock_border_inner_se"}
	},

	-- wall brushes (piece type -> weighted ids); the type per tile comes from A.wallPiece (measured on the live map)
	walls = {
		ruin = {horizontal = {{3362, 1}}, vertical = {{3361, 1}}, corner = {{3365, 1}}, pole = {{3363, 1}}},
		darkstone = {horizontal = {{25201, 1}, {25203, 1}}, vertical = {{25200, 1}, {25205, 1}}, corner = {{25204, 1}},
			pole = {{25202, 1}}}
	},

	themes = {
		-- a deep cave of dirt walls, mud and lava cracks, lava pools that glow
		emberdeep = {
			floor = "cave", rock = "earth", rimWidth = 2,
			patches = {
				{family = "mud", share = 0.05, radius = {2, 3}},
				{family = "cracks", share = 0.06, radius = {2, 4}}
			},
			pools = {{family = "lava", share = 0.025, radius = {1, 3}}},
			decor = {
				share = 0.10,
				scatter = {{3610, 4}, {3611, 3}, {3612, 4}, {3613, 3}, {3614, 2}, {3621, 3}, {3622, 2}, {3623, 2},
					{2229, 1}, {2230, 1}, {2231, 1}},
				clusters = {
					{per1000 = 6, size = {3, 6}, radius = 2, items = {{2792, 3}, {2793, 2}, {2794, 2}, {2797, 2}, {4182, 2},
						{4183, 1}}},
					{per1000 = 5, size = {3, 5}, radius = 1, items = {{3610, 3}, {3611, 3}, {3613, 2}, {3614, 2}}}
				}
			},
			obstacles = {share = 0.012, items = {{1356, 2}, {1357, 2}, {1358, 2}, {1359, 2}, {8361, 1}}},
			lights = {per100 = 2.5, spacing = 6, items = {{17586, 3}, {17750, 2}, {1484, 1}}},
			dark = {
				patches = {
					{family = "darkmoss", share = 0.06, radius = {2, 3}},
					{family = "cracks", share = 0.05, radius = {2, 4}}
				},
				decor = {
					share = 0.09,
					scatter = {{3610, 4}, {3612, 4}, {3621, 3}, {3613, 3}, {"rubble", 1}, {"bone_pile", 1}},
					clusters = {
						{per1000 = 6, size = {3, 6}, radius = 2, items = {{"glowcap_teal", 2}, {"glowcap_purple", 2},
							{2792, 2}, {2797, 1}}},
						{per1000 = 4, size = {3, 5}, radius = 1, items = {{3610, 3}, {3611, 3}, {"rubble", 1}}}
					}
				},
				obstacles = {share = 0.012, items = {{"dark_boulder", 3}, {"blood_crystals", 2}, {1356, 1}, {1358, 1}}},
				lights = {per100 = 2.5, spacing = 6, items = {{"standing_torch", 2}, {17586, 2}, {"brazier", 1}}}
			}
		},
		-- a sunken ruin: rooms of slate, marble and flagstone in old stone walls, rubble and bones
		ossuary = {
			floor = "slate", wall = "ruin", roomFloors = {"slate", "slate", "flagstone", "marble", "tiles"},
			bossFloor = "marble",
			decor = {
				share = 0.12,
				scatter = {{3653, 4}, {3654, 4}, {3655, 3}, {3656, 3}, {2229, 1}, {2230, 2}, {2231, 1}, {3102, 1},
					{3116, 1}},
				clusters = {
					{per1000 = 7, size = {3, 5}, radius = 1, items = {{3653, 3}, {3654, 3}, {3655, 2}, {3656, 2}}},
					{per1000 = 3, size = {2, 4}, radius = 1, items = {{2229, 2}, {2230, 3}, {2231, 2}}}
				}
			},
			obstacles = {share = 0.006, items = {{1356, 1}, {1358, 1}}},
			lights = {per100 = 4.5, spacing = 5, items = {{1484, 3}, {7059, 1}}},
			-- furniture against the room walls (guide: 0.012-0.036 per tile in dungeons)
			props = {per100 = 2.5, spacing = 3, items = {{1442, 2}, {1443, 2}, {22308, 2}, {22309, 2}, {22312, 1},
				{2034, 2}, {9419, 1}, {9420, 1}}},
			dark = {
				decor = {
					share = 0.09,
					scatter = {{3653, 3}, {3654, 3}, {"rubble", 1}, {"bone_pile", 2}, {2230, 1}},
					clusters = {
						{per1000 = 7, size = {3, 5}, radius = 1, items = {{3653, 3}, {3654, 3}, {"rubble", 1}}},
						{per1000 = 3, size = {2, 4}, radius = 1, items = {{"bone_pile", 2}, {2230, 2}, {2229, 1}}}
					}
				},
				obstacles = {share = 0.008, items = {{"broken_pillar", 2}, {"ruined_pillar", 1}}},
				lights = {per100 = 4.5, spacing = 5, items = {{"brazier", 2}, {1484, 1}, {7059, 1}}}
			}
		},
		-- an open waste of grey rock under the sky: basalt fields, lava cracks and pools, mountain cliffs, dead trees
		cinderfall = {
			floor = "rockfloor", rock = "mountain", rimWidth = 2,
			patches = {
				{family = "basalt", share = 0.10, radius = {3, 6}},
				{family = "cracks", share = 0.05, radius = {2, 4}}
			},
			pools = {{family = "lava", share = 0.03, radius = {2, 4}}},
			decor = {
				share = 0.08,
				scatter = {{3610, 4}, {3611, 3}, {3612, 4}, {3613, 3}, {3614, 2}, {3621, 3}, {3622, 2}, {3623, 2},
					{2230, 1}, {2231, 1}},
				clusters = {
					{per1000 = 5, size = {3, 6}, radius = 2, items = {{3610, 3}, {3611, 3}, {3613, 2}, {3621, 2}}}
				}
			},
			obstacles = {share = 0.02, items = {{2709, 2}, {2710, 2}, {2713, 1}, {2714, 1}, {2715, 1}, {2716, 1},
				{1356, 2}, {1357, 2}, {1358, 2}, {1359, 2}, {8361, 1}}},
			lights = {per100 = 2, spacing = 7, items = {{17787, 1}, {17586, 1}}},
			dark = {
				patches = {
					{family = "basalt", share = 0.08, radius = {3, 6}},
					{family = "ash", share = 0.06, radius = {2, 4}},
					{family = "cracks", share = 0.04, radius = {2, 4}}
				},
				obstacles = {share = 0.02, items = {{"dead_tree", 3}, {"twisted_tree", 3}, {"dark_boulder", 2},
					{"rock_outcrop", 1}, {1356, 1}, {1358, 1}}},
				lights = {per100 = 2, spacing = 7, items = {{"standing_torch", 1}, {17787, 1}}}
			}
		},
		-- the dungeon of the dungeon system: dark stone halls
		vault = {
			floor = "flagstone", wall = "darkstone", roomFloors = {"slate", "flagstone", "tiles"}, bossFloor = "marble",
			decor = {
				share = 0.11,
				scatter = {{3653, 3}, {3654, 3}, {3655, 2}, {3656, 2}, {2230, 1}, {2229, 1}, {3102, 1}, {3116, 1}},
				clusters = {
					{per1000 = 5, size = {3, 5}, radius = 1, items = {{3653, 2}, {3654, 2}, {3655, 2}}},
					{per1000 = 3, size = {2, 4}, radius = 1, items = {{3102, 2}, {3116, 2}, {2229, 1}, {2231, 1}}}
				}
			},
			lights = {per100 = 5, spacing = 5, items = {{1484, 2}, {7059, 1}}},
			props = {per100 = 3, spacing = 3, items = {{1442, 2}, {1443, 2}, {22308, 2}, {22309, 2}, {22312, 1}, {2034, 2},
				{9686, 1}, {9419, 1}, {9420, 1}}},
			dark = {
				lights = {per100 = 5, spacing = 5, items = {{"brazier", 2}, {1484, 1}}}
			}
		},

		-- ---------------------------------------------------------------- the rift themes (rift_layout_core.lua)
		-- One theme per rift theme of rift_config.lua; each serves every layout kind its rift theme rolls (a rock for
		-- caves, wastes and mixed layouts, walls and room floors for dungeons, room floors for the chambers of a mixed
		-- layout), byKind = overrides for one kind. Only ids of the palettes above, the old rift floors and the dark set.
		-- Abyssal Rift: an eldritch waste or cave of rift floor (dark set: obsidian and magma with ash, moss and lava)
		rift_abyss = {
			floor = "riftfloor", rock = "mountain", wall = "darkstone", roomFloors = {"marble"}, rimWidth = 2,
			decor = {
				share = 0.07,
				scatter = {{3610, 4}, {3611, 3}, {3612, 4}, {3613, 3}, {3621, 2}, {3622, 2}, {3623, 2}},
				clusters = {{per1000 = 4, size = {3, 5}, radius = 1, items = {{3610, 3}, {3611, 3}, {3613, 2}, {3614, 2}}}}
			},
			obstacles = {share = 0.012, items = {{1356, 2}, {1357, 2}, {1358, 2}, {1359, 2}, {8361, 1}}},
			lights = {per100 = 1.8, spacing = 7, items = {{17586, 2}, {17787, 1}}},
			dark = {
				floor = "obsidian",
				patches = {
					{family = "ash", share = 0.06, radius = {2, 4}},
					{family = "darkmoss", share = 0.03, radius = {2, 3}}
				},
				pools = {{family = "lava", share = 0.02, radius = {2, 3}}},
				decor = {
					share = 0.07,
					scatter = {{"rubble", 4}, {"bone_pile", 2}, {3610, 3}, {3612, 3}, {3621, 2}},
					clusters = {{per1000 = 5, size = {3, 6}, radius = 2, items = {{"glowcap_purple", 3}, {"rubble", 2},
						{3611, 2}}}}
				},
				obstacles = {share = 0.014, items = {{"blood_crystals", 3}, {"dark_boulder", 3}, {"rock_outcrop", 1}}},
				lights = {per100 = 1.8, spacing = 7, items = {{"standing_torch", 2}, {"brazier", 1}, {17586, 1}}}
			}
		},
		-- Obsidian Hall: a ruined complex of black marble halls in dark stone walls, or marble halls cut into rock
		rift_hall = {
			floor = "marble", rock = "mountain", wall = "darkstone", roomFloors = {"marble", "marble", "slate", "flagstone"},
			bossFloor = "tiles", mixedFloors = {"marble"}, rimWidth = 2,
			decor = {
				share = 0.09,
				scatter = {{3653, 3}, {3654, 3}, {3655, 2}, {3656, 2}, {2230, 1}, {2229, 1}},
				clusters = {{per1000 = 5, size = {3, 5}, radius = 1, items = {{3653, 2}, {3654, 2}, {3655, 2}}}}
			},
			obstacles = {share = 0.006, items = {{1356, 1}, {1358, 1}}},
			lights = {per100 = 4, spacing = 5, items = {{1484, 2}, {7059, 1}}},
			byKind = {
				dungeon = {props = {per100 = 2.5, spacing = 3, items = {{1442, 2}, {1443, 2}, {22308, 2}, {22309, 2},
					{2034, 2}, {9419, 1}, {9420, 1}}}},
				mixed = {floor = "rockfloor", lights = {per100 = 3, spacing = 6, items = {{1484, 2}, {7059, 1}}}}
			},
			dark = {
				decor = {
					share = 0.08,
					scatter = {{3653, 3}, {3654, 3}, {"rubble", 2}, {"bone_pile", 1}},
					clusters = {{per1000 = 5, size = {3, 5}, radius = 1, items = {{3653, 3}, {"rubble", 2}}}}
				},
				obstacles = {share = 0.008, items = {{"broken_pillar", 2}, {"ruined_pillar", 1}}},
				lights = {per100 = 4, spacing = 5, items = {{"brazier", 2}, {1484, 1}}},
				byKind = {
					mixed = {patches = {{family = "ash", share = 0.05, radius = {2, 3}}},
						lights = {per100 = 3, spacing = 6, items = {{"brazier", 2}, {"standing_torch", 1}}}}
				}
			}
		},
		-- Ashen Crypt: catacombs of slate and flagstone under dark sand (dark set: ash soil and bone earth, moss)
		rift_crypt = {
			floor = "crypt", rock = "earth", wall = "ruin", roomFloors = {"slate", "flagstone", "slate"}, bossFloor = "marble",
			mixedFloors = {"slate", "flagstone"}, rimWidth = 2,
			decor = {
				share = 0.10,
				scatter = {{3653, 3}, {3654, 3}, {2229, 1}, {2230, 2}, {2231, 1}, {3102, 1}},
				clusters = {{per1000 = 6, size = {3, 5}, radius = 1, items = {{2229, 2}, {2230, 3}, {2231, 2}}}}
			},
			obstacles = {share = 0.008, items = {{1356, 1}, {1358, 1}}},
			lights = {per100 = 3.5, spacing = 5, items = {{1484, 2}, {7059, 1}}},
			byKind = {
				dungeon = {props = {per100 = 2, spacing = 3, items = {{1442, 2}, {1443, 2}, {2034, 2}, {9419, 1}, {9420, 1}}}}
			},
			dark = {
				floor = "ash",
				patches = {{family = "darkmoss", share = 0.05, radius = {2, 3}}},
				decor = {
					share = 0.10,
					scatter = {{"bone_pile", 3}, {"rubble", 2}, {2230, 1}, {3653, 2}},
					clusters = {{per1000 = 6, size = {3, 5}, radius = 1, items = {{"bone_pile", 2}, {"glowcap_teal", 1},
						{2229, 1}}}}
				},
				obstacles = {share = 0.01, items = {{"dead_bush", 2}, {"broken_pillar", 2}, {"dark_boulder", 1}}},
				lights = {per100 = 3.5, spacing = 5, items = {{"standing_torch", 2}, {"brazier", 1}}}
			}
		},
		-- Forsaken Sanctum: a blighted cave system with gilded chambers (dark set: wet and mossy rock, moss, glowcaps)
		rift_sanctum = {
			floor = "cave", rock = "earth", wall = "ruin", roomFloors = {"flagstone"}, mixedFloors = {"flagstone", "slate"}, rimWidth = 2,
			patches = {
				{family = "mud", share = 0.06, radius = {2, 3}},
				{family = "cracks", share = 0.03, radius = {2, 3}}
			},
			decor = {
				share = 0.09,
				scatter = {{3610, 4}, {3611, 3}, {3612, 4}, {3613, 3}, {3621, 3}, {3622, 2}, {2230, 1}},
				clusters = {{per1000 = 7, size = {3, 6}, radius = 2, items = {{2792, 3}, {2793, 2}, {2794, 2}, {2797, 2},
					{4182, 2}, {4183, 1}}}}
			},
			obstacles = {share = 0.012, items = {{1356, 2}, {1357, 2}, {1358, 2}, {1359, 2}}},
			lights = {per100 = 2.5, spacing = 6, items = {{17586, 3}, {17750, 2}, {1484, 1}}},
			dark = {
				floor = "wetrock",
				patches = {
					{family = "darkmoss", share = 0.08, radius = {2, 4}},
					{family = "ash", share = 0.03, radius = {2, 3}}
				},
				decor = {
					share = 0.09,
					scatter = {{"glowcap_teal", 2}, {"glowcap_purple", 2}, {"rubble", 2}, {3610, 2}, {3612, 2}},
					clusters = {{per1000 = 8, size = {3, 6}, radius = 2, items = {{"glowcap_teal", 3}, {"glowcap_purple", 3},
						{2792, 1}}}}
				},
				obstacles = {share = 0.012, items = {{"dark_boulder", 3}, {"rock_outcrop", 1}, {1356, 1}, {1358, 1}}},
				lights = {per100 = 2.5, spacing = 6, items = {{"standing_torch", 2}, {17586, 1}}}
			}
		}
	},

	-- The areas. origin = top-left cell of the first floor (the map has no tiles at x/y 14336-15359; the other runtime
	-- areas use 2000-13824, server/README.md "Rifts"); floors go down (z + 1 each). entrance: the portal on the live map
	-- (chosen with the map data, docs/MAP_GUIDE.md "Generated areas"), back: where the exit portal puts players.
	-- spawns.density: monsters per 100 walkable tiles outside the arrival's safe radius (item 89: 2.7-4.4 in normal
	-- hunts; cave 2.7-3.2, dungeon 3.3-3.6, open land 1.2-2.0; the bulky level-scaled monsters are pulled three at a
	-- time, so a little lower), band = the bounds the tests hold it to. level: the level the monsters are scaled to
	-- (areagen_core.lua A.levelScale); spawntime in seconds (120 like the 600-1000 band).
	areas = {
		{
			id = "emberdeep", name = "Emberdeep Hollows", kind = "cave", theme = "emberdeep", enabled = true, seed = 1001,
			origin = {x = 14400, y = 14400, z = 9}, size = {66, 52}, floors = 2, linksPerFloor = 2,
			layout = {fill = 0.47, steps = 5, spread = 2, minRegion = 40, tunnelRadius = 1},
			arrival = {8, 8}, exit = {0, -1}, minLevel = 1000,
			spawns = {density = 2.4, band = {2.0, 3.0}, minDistance = 4, packChance = 15, packMax = 2, safeRadius = 10,
				spawntime = 120, level = {1000, 1100},
				monsters = {{"Tundra Troll", 3}, {"Loricate Orger", 3}, {"Lady bug", 2}, {"Lacewing Moth", 2},
					{"Grindmaw the Mauler", 2}}},
			boss = {monster = "Grindmaw the Mauler", name = "The Emberdeep Maw", level = 1100, healthMult = 8,
				damageMult = 1.25, spawntime = 3600, radius = 6},
			entrance = {x = 33221, y = 33135, z = 8}, back = {x = 33221, y = 33136, z = 8}
		},
		{
			id = "ossuary", name = "Sunken Ossuary", kind = "dungeon", theme = "ossuary", enabled = true, seed = 2002,
			origin = {x = 14560, y = 14400, z = 9}, size = {90, 70}, floors = 2, linksPerFloor = 1,
			layout = {rooms = {10, 13}, room = {7, 12}, gap = 3, corridor = 3, loops = {2, 4}, bossRoom = 13},
			arrival = {9, 9}, exit = {0, -1}, minLevel = 1100,
			spawns = {density = 2.8, band = {2.3, 3.5}, minDistance = 4, packChance = 20, packMax = 2, safeRadius = 9, roomCap = 5,
				spawntime = 120, level = {1100, 1200},
				monsters = {{"Royal Man", 3}, {"Golden Lord", 3}, {"Dawn Strayer", 2}, {"Frost Maiden", 2},
					{"Dreamgorger", 2}}},
			boss = {monster = "Dawn Strayer", name = "The Ossuary Warden", level = 1200, healthMult = 8, damageMult = 1.25,
				spawntime = 3600},
			entrance = {x = 34295, y = 31100, z = 13}, back = {x = 34295, y = 31101, z = 13}
		},
		{
			id = "cinderfall", name = "Cinderfall Wastes", kind = "waste", theme = "cinderfall", enabled = true, seed = 3003,
			origin = {x = 14400, y = 14560, z = 7}, size = {100, 80}, floors = 1,
			layout = {fill = 0.36, steps = 4, spread = 1, minRegion = 60, tunnelRadius = 2},
			arrival = {9, 9}, exit = {0, -1}, minLevel = 1200,
			spawns = {density = 1.6, band = {1.3, 2.0}, minDistance = 5, packChance = 25, packMax = 3, safeRadius = 12,
				spawntime = 120, level = {1200, 1300},
				monsters = {{"Azure Dragon", 3}, {"Jungle Beasts", 3}, {"Blazebringer", 2}, {"Swamp Snapper", 2},
					{"Garack", 1}}},
			boss = {monster = "Azure Dragon", name = "Cinderwing", level = 1300, healthMult = 8, damageMult = 1.25,
				spawntime = 3600, radius = 7},
			entrance = {x = 31667, y = 31269, z = 7}, back = {x = 31667, y = 31270, z = 7}
		},
		{
			-- a run of the dungeon system (dungeons.lua): registered as base dungeon `dungeon.id` at startup, monsters
			-- spawned at the start of each run (no respawn), the boss in the boss room
			id = "vault", name = "The Hollow Vault", kind = "dungeon", theme = "vault", enabled = true, seed = 4004,
			origin = {x = 14560, y = 14560, z = 9}, size = {76, 64}, floors = 1,
			layout = {rooms = {9, 11}, room = {6, 9}, gap = 3, corridor = 3, loops = {2, 3}, bossRoom = 11},
			arrival = {8, 8}, exit = {0, -1},
			spawns = {density = 2.8, minDistance = 4, packChance = 30, packMax = 3, safeRadius = 8, roomCap = 5.5, spawntime = 0,
				level = {800, 850},
				monsters = {{"Orclops Ravager", 3}, {"Shaper Matriarch", 3}, {"Grove Keeper", 2}, {"Blazebringer", 2},
					{"Garack", 2}}},
			-- the boss: Garack's 14,800 x the engine level bonus (1 + 0.0074 x 900) x healthMult 10 = 1.13M; difficulty
			-- multiplies it by bossHealth, not by the dungeon table's 100-1300%, so a solo run stays inside 30 minutes
			-- (server/README.md "Generated areas", The Hollow Vault)
			boss = {monster = "Garack", name = "Vault Keeper Ossrim", level = 900, healthMult = 10, damageMult = 1.4},
			dungeon = {id = 5, level = 800, party = 1, time = 1800, title = "The Hollow Vault",
				bossHealth = {100, 125, 150, 175, 200, 225},
				loot = {{id = 2160, count = 12}},
				challenges = {
					{key = "speed", title = "Speed Runner", points = 5, desc = "Finish in under 12 minutes.",
						maxMs = 12 * 60 * 1000},
					{key = "flawless", title = "Flawless", points = 10, desc = "Finish without anyone dying."}
				}}
		}
	}
}
