-- Hunt teleports (hunt_teleports.lua, hunt_teleports_core.lua; server/README.md "Hunt teleports"): the way into the
-- planned content hunts (server/tools/areaplan/plans/) from the teleport room of Cinderhold. Plain table, loaded with
--     ChaosHuntTeleportsConfig = dofile("data/scripts/chaos/hunt_teleports_config.lua")
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- server/tools/install_content_areas.py reads this file too (through tools/hunt_teleports_dump.lua): it places every
-- plan at its own origin, extends the room by copying its modules (`room`), adds the display monsters to the spawn
-- file and writes data/lib/chaos_hunt_places.lua (each plan's slot, arrival tile, exit tile and level band). This file
-- holds what a person edits: the room, the order of the plans, their labels and display monsters.
return {
	enabled = true,

	-- action id of the hunt teleports (free block 47930-47939; 47930 the teleports, the rest free)
	aid = 47930,
	items = {
		portal = 1387, -- magic forcefield, the same item as the room's own teleports
		sign = 5360, -- the sign on the counter behind each teleport (its text is written at startup)
		-- the counter piece on the tile behind a teleport (room.cellRows): where a teleport has no free cell beside it
		-- the install takes it off and the monster stands there (hall_order.spare_cell; z 6 31659)
		counter = 1642,
		-- the base quests' other teleport items: the entry floor's Inquisition alcove (5023) and the two quest sites'
		-- own ways back (5023, 11796); read with the portal so the quest hall can move them (hall_quests.py)
		questPortals = {5023, 11796}
	},
	-- floating label over each teleport, in the player's language, like the base server's own labels of the room
	-- (a "monster say" text sent only to players within `range`, every `interval` ms; 0 turns it off)
	floatText = {interval = 5000, range = 6},
	effects = {
		go = 11, -- CONST_ME_TELEPORT, at the room and at the arrival
		refuse = 3 -- CONST_ME_POFF, when the level is too low
	},

	-- The teleport room of Cinderhold (town 2): three floors (z 5, 6, 7) of one hall, 16 teleports a floor in
	-- alcoves of 4 columns, a carpet corridor between them, the stairs in the middle and a teleport to the temple at
	-- each end. The hunts take floor 6. Each side grows by `modules` alcove modules: the columns of `module` are
	-- copied again and again past the old end, and the end (`cap`, with its temple teleport) moves out by 4 per
	-- module. Every new tile lands on a tile the map does not have (floor 6 is empty around the hall), except the
	-- old cap, which is replaced. Rows `rows` (inclusive) are copied.
	room = {
		town = 2,
		z = 6,
		rows = {32250, 32262},
		teleportRows = {32254, 32258}, -- the teleport of each alcove, north and south side
		cellRows = {32253, 32259}, -- the closed cells beside the counter behind each teleport (display monsters)
		signRows = {32252, 32260}, -- the counter with the sign behind each teleport
		east = {module = {31664, 31667}, cap = {31668, 31670}, modules = 6},
		west = {module = {31629, 31632}, cap = {31626, 31628}, modules = 6},
		-- the middle of the corridor (the stairs' column): where a plan's exit portal sends players when its places
		-- entry has no `front` (the tile in front of its own teleport) and the room has no teleport rows; the end
		-- teleports' fronts face this column
		back = {x = 31648, y = 32256, z = 6},
		-- The other floors grow the same way (owner, 2026-10-18: the ground floor z 7 holds the hunts of levels 1-500,
		-- more than its 16 alcoves): `from` is the floor whose alcoves are copied (bare of rewards and signs), the
		-- ends are the floor's own; `sweep`: the new tiles may replace the open lawn beside the hall (checked: no
		-- house, nothing but decoration). 8 modules a side: 32 new slots, 48 on z 7.
		wings = {
			{z = 7, from = 6, sweep = true, east = {modules = 8}, west = {modules = 8}}
		}
	},

	-- The whole hall in level order (owner, 2026-10-16; server/README.md "Hall order"): every hunt teleport of the hall,
	-- the base server's (tools/hall_hunts.csv, from tools/hall_order.py derive) and the planned hunts', by level band:
	-- the entry floor (z 7) first along the corridor from west to east, then each floor up. install_content_areas.py
	-- writes it; --remove-hall puts the base hunts back. `floors`: the hall's floors, lowest bands first; `x`: the
	-- hall's span; `endRow`: the corridor's end teleports (a hunt unless it leads to `temple`); `labels`: the floor's
	-- floating label ("Floor 7: levels 1-80") over `at`, and over `up` (the stairs up) the next floor's.
	-- `levels`: the owner's rule of 2026-10-18 (server/README.md "Hall order"): a hunt stands on the floor of its level,
	-- the hunt's level being the weighted median of its monsters (a plan: the middle of its `level`). The ground floor
	-- z 7 holds levels 1-500, z 6 501-1000, z 5 the rest; `max` is the highest level of a floor. Same order as `floors`.
	-- `quests`: the quest hall (tools/hall_quests.py): the base quests' alcoves move, with their rewards on show and
	-- their quest signs, to the plaza south of the hall, where the daily and weekly reward booths stood (owner,
	-- 2026-10-20: "you can overwrite this green region"): `north` the row of the base room's north alcoves (`y` its sign
	-- row, the teleports on y + 2, `x` the teleport columns: the hall's own, the gap in the middle the way from the
	-- hall's south door), `south` the row of the south alcoves (`y` its teleport row, the signs on y + 2; the west
	-- columns two tiles off the hall's so that no front is a tile of the plaza's two event teleports), `corridor` the
	-- floor between them in the hall's carpet (the plaza's aisle; its own teleports stay). `previous`: the quest hall of
	-- 2026-10-18 over the pond east of the plaza (origin, connector, step; `fill`: deep water for a tile the map's
	-- backup does not have), taken away once its quests have moved on. `chests`: the base server's daily and weekly
	-- reward chests of the plaza (royal chest 29327, unique ids 34801-34804; scripts data/scripts/customs/daily_chests)
	-- taken away with their booth (the rows `rows`), owner 2026-10-18.
	hall = {
		enabled = true,
		floors = {7, 6, 5},
		levels = {{z = 7, max = 500}, {z = 6, max = 1000}, {z = 5}},
		-- the hunt slots of each floor as the install counts them on the live map (2 a module a side, plus the base
		-- room's); install_content_areas_test.py refuses more hunts on a floor (the base hunts of hall_hunts.csv and every
		-- plan, by `levels`) than it has, so CI says "grow it" before an update fails on the server. Raise it with the room.
		capacity = {{z = 7, slots = 48}, {z = 6, slots = 41}, {z = 5, slots = 18}},
		quests = {
			z = 7,
			north = {y = 32263, x = {31630, 31634, 31638, 31642, 31654, 31658, 31662, 31666}},
			south = {y = 32270, x = {31628, 31632, 31636, 31640, 31654, 31658, 31662, 31666}},
			corridor = {x = {31628, 31668}, y = {32266, 32269}},
			previous = {origin = {x = 31676, y = 32263}, connector = {x = 31665}, step = 4, fill = 28915},
			-- the cell row an old quest alcove gets once its quest has moved (the rewards stood on all three tiles:
			-- both cells and the counter between): the hunt alcove of this teleport column on floor `z` is the model
			-- (bare cells without protection zone, so the display monsters can stand there, and the counter)
			model = {x = 31666, z = 6},
			-- the teleport item of a quest whose teleport an earlier install lost (a hunt's took its alcove): the
			-- quest hall makes it again to the CSV's destination with this item (default items.portal)
			portalItems = {base_7_31654_32254 = 5023},
			chests = {
				{x = 31639, y = 32265, item = 29327, uid = 34801, rows = {32263, 32265}}, -- daily reward
				{x = 31633, y = 32265, item = 29327, uid = 34802, rows = {32263, 32265}}, -- weekly: Nightmare Coin
				{x = 31657, y = 32265, item = 29327, uid = 34803, rows = {32263, 32265}}, -- weekly: Stamina Extension
				{x = 31663, y = 32265, item = 29327, uid = 34804, rows = {32263, 32265}} -- weekly: Star Inlay Stone
			}
		},
		-- a room no hunt takes (the floors have more rooms than hunts) is closed: the room's own wall piece of the
		-- teleport row (`wall`) on its teleport tile, the ring and the sparkle (`decor`) off; a hunt that takes it later
		-- opens it again (beta 2026-10-20: "many unused spawns")
		closed = {wall = 29306, decor = {8047, 1421}},
		-- The black squares round the hall (owner, 2026-10-21): the island of the hall lies in a sea with no tile
		-- beyond it, and the ground floor's wings reach past the sea's edge, so their ends and the plaza looked out on
		-- black. tools/patch_map_fixes.py (install step mapfixes) gives every tile of `box` on floor `z` that the map
		-- does not have the deep water of the base map around the island (`water`, picked by position), puts the
		-- base map's water border pieces (`borders`, the side where the water lies; d = two sides and the corner,
		-- c = a corner only) on the shore tiles (grounds `shore`) next to the new water, and gives a tile of the box
		-- with no ground (walls standing on nothing) the ground most of its four neighbours have.
		fill = {
			z = 7, x = {31578, 31724}, y = {32216, 32312},
			water = {28915, 28916, 28917, 28918},
			shore = {29238, 4526, 4527, 4528, 4529, 4530, 4531, 4532, 4533, 4534, 4535, 4536, 4537},
			borders = {n = 29166, e = 29167, w = 29168, s = 29177, dnw = 29169, dne = 29170, dsw = 29171, dse = 29172,
				cnw = 29173, cne = 29174, csw = 29175, cse = 29176}
		},
		x = {31590, 31712},
		endRow = 32256,
		temple = {32369, 32241, 7},
		labels = {
			{z = 7, at = {x = 31648, y = 32255}, up = {x = 31648, y = 32253}},
			{z = 6, at = {x = 31648, y = 32255}, up = {x = 31648, y = 32257}},
			{z = 5, at = {x = 31648, y = 32255}}
		}
	},

	-- the display monsters stand in the two cells beside each teleport, like the room's own (spawn file, radius 1)
	displaySpawntime = 120,
	-- where display monsters stand: the cell rows (room.cellRows) of the hall's floors, across the grown floor 6.
	-- A monster there (no master) is a display: no boss mechanics, no tier roll, no treasure goblin, and it never hits
	-- anyone (onTargetCombat). The base room's own display cells on floors 5 and 7 are covered too.
	display = {x = {31594, 31706}, floors = {5, 7}},

	-- 66 plans. With the base hunts they fill every slot of the hall since 2026-10-22 (server/README.md "Hall order":
	-- 48 of 48 on z 7, 37 of 37 on z 6, 18 of 18 on z 5). 2026-10-25: Sunken Mirewood is the 38th hunt of z 6, so floor 6
	-- grew one module a side (5 -> 6, 41 slots; hall.capacity).
	-- The order here does not count: install_content_areas.py gives the slots by level band ascending (the plan's
	-- `level`), along the corridor from west to east, the north teleport of a column before the south one; a new
	-- hunt lands in its place by itself. A plan of tools/areaplan/plans/ missing here still gets a teleport, with its
	-- most frequent monster on display (check its look; list it here to choose). `slot` (1 = the westmost north
	-- teleport) pins a plan to a slot.
	-- `monster` is the display monster: a frequent monster of the plan whose look renders (checked against the pair)
	-- and is at most 2x2 tiles (pair 28, 2026-10-16: a bigger sprite spills over the one-tile cell's walls; the base
	-- room's own display monsters are 2x2). `display = false`: no display monster (every monster of the plan is
	-- bigger).
	-- `minLevel` overrides the floor of the plan's level band.
	-- `standIn = true`: the display monster is not one of the plan's (all of them too big for a cell).
	-- One monster per slot (owner 2026-10-22: "one slot per monster, no repeats"): no two plans show the same monster,
	-- and where the plan allows it no two show the same look (several monsters share a sprite).
	plans = {
		{id = "bonechoir_catacomb", monster = "Deathrattle"},
		{id = "sulphur_gallery", monster = "Hellflayer"},
		{id = "widowmere", monster = "Nightfang Widow"},
		-- every monster of the plan is a 4x4 or 5x5 sprite (it spilled over the cell walls into the corridor): the 2x2
		-- Elder Wyrm of the base server stands in (owner 2026-10-22: "Wyrmspine Hollows has no showcase monsters"); it
		-- shows the hunt's level like every display (hunt_teleports_core.lua H.displayLevel)
		{id = "wyrmspine_hollows", monster = "Elder Wyrm", standIn = true},
		{id = "pyrarch_crucible", monster = "Hellmaw Brute"},
		{id = "hexwood_thicket", monster = "Black Stag"},
		{id = "corsairs_reach", monster = "Scourgejaw"},
		{id = "mirefang_basin", monster = "Elite Tidecrest Serpent"},
		{id = "rimecrown_depths", monster = "Vorkhaz"}, -- 2x2; the 3x3 Celestial Wyrm spilled
		{id = "cinderglass_sanctum", monster = "Spiky Carnivor"},
		{id = "slagmourn_foundry", monster = "Twisted Shaper"}, -- 2x2; the 5x4 Scaleborn spilled
		{id = "hollowmass_reliquary", monster = "Silicron"},
		{id = "gallowfen_mire", monster = "Facetis"},
		{id = "voidscar_chasm", monster = "Winterstride"},
		{id = "gravehorn_deeps", monster = "Cinderhorn Juggernaut"},
		{id = "duskmarrow_crater", monster = "Mirecoil Wyrm"}, -- not the 5x5 Pyrewing Tyrant in a one-tile cell
		-- pair 27 trial area (levels 300-400); its boss is the Hollow Rider. 2x2; the 3x3 Bonecrusher spilled
		{id = "hollow_crypt", monster = "Sopping Carcass"},
		-- the hall fill (owner, 2026-10-22: "the hunts of the upper floors"): 31 hunts on z 6 (500-1050),
		-- 10 on z 5 (1050-2000), in the east block of server/tools/areaplan/plans; every display monster is 2x2 or smaller
		{id = "gloomtooth_caverns", monster = "Ashmaw Raider"},
		{id = "brackwater_sloughs", monster = "Ashmaw Bonecaller"},
		{id = "sablemourn_ossuary", monster = "Mange Hound"},
		{id = "thornmantle_glade", monster = "Slagborer"},
		{id = "embergut_rift", monster = "Slagback Hound"}, -- the rift's own hound (pair 54 look 3363 once ChaosAutospriteArt.PAIR54 is on)
		{id = "frostvein_reach", monster = "Orclops Ravager"},
		{id = "graveknell_catacombs", monster = "Mercenary Ranger"},
		{id = "umbral_sink", monster = "Garack"},
		{id = "cinderscour_barrens", monster = "Blazebringer"},
		{id = "grimlock_vaults", monster = "Grove Keeper"},
		{id = "blackmarble_halls", monster = "Dreamgorger"},
		{id = "rotbloom_sanctum", monster = "Shroud Brood"},
		{id = "hollowmaw_grotto", monster = "Blight Hound"},
		{id = "leechwater_fen", monster = "Ironmask Taskmaster"},
		{id = "dreadmourn_crypt", monster = "Royal Man"},
		{id = "gallowroot_wilds", monster = "Cursed Ape"},
		{id = "scorchpit_delve", monster = "Tundra Troll"},
		{id = "glacierfang_shelf", monster = "Azure Dragon"},
		{id = "bonewright_galleries", monster = "Chained Runt"},
		{id = "nightrend_abyss", monster = "Leechwing"},
		{id = "sunderstone_wastes", monster = "Lacewing Moth"},
		{id = "ironwick_treasury", monster = "Jungle Beasts"},
		{id = "obsidian_colonnade", monster = "Blight Bloom"},
		{id = "mildewveil_sanctum", monster = "Reedgrave"},
		{id = "deepgrudge_warrens", monster = "Bloom Husk"},
		{id = "sorrowfen_marsh", monster = "Deepforge Fiend"},
		{id = "shroudhallow_tomb", monster = "Ice Lich"},
		{id = "hagthorn_weald", monster = "Lady bug"},
		{id = "pyreglass_chasm", monster = "Elite Twisted Shaper"},
		{id = "rimeblood_glacier", monster = "Rustguard"},
		{id = "lanternless_catacombs", monster = "Quicksilver Wraith"},
		{id = "scaldmoor_expanse", monster = "Masque Dancer"},
		{id = "vespergloom_halls", monster = "Carrion Drake"},
		{id = "wormcoil_depths", monster = "Maw Grub"},
		{id = "shiverspine_ridge", monster = "Bonepicker"},
		{id = "hushbone_barrows", monster = "Hollowhorn"},
		{id = "carrionwood", monster = "Bloodantler Fiend"},
		{id = "dreadcoffer_vaults", monster = "Gnawbone Swarm"},
		{id = "paleflame_sanctum", monster = "Wraithbone Stalker"},
		{id = "blightmaw_bog", monster = "Gnarlback"},
		{id = "worldscar_abyss", monster = "Ironmask Warbreaker"},
		-- O139 (owner, 2026-10-23: hunts for the levels 200, 450, 700, 1000, 1500 and 2000; server/README.md "Hall coverage
		-- (O139)"): eight new plans in the free row y 15156 of the east block, display monsters 2x2 or smaller. Four plans
		-- were rewritten in place (same id, origin, size and layout): gallowroot_wilds (Bramblegrave Reach, 700),
		-- shroudhallow_tomb (Hollowbell Mausoleum, 1000), carrionwood (Antlerwight Brake, 1500), blightmaw_bog (Gloomsilt
		-- Mire, 2000)
		{id = "ironhorn_slagworks", monster = "Ironhorn Forgepriest"},
		{id = "venomthread_fen", monster = "Cobra Vizier"},
		{id = "azuregate_reliquary", monster = "Azure Guard"},
		{id = "drownbell_depths", monster = "Frost Larva"},
		{id = "wanwick_cloister", monster = "Distorted Phantom"},
		{id = "brinescar_strand", monster = "Saltkin Raider"},
		{id = "rustcog_warrens", monster = "Mechanic Goblin"},
		{id = "mossgrave_tangle", monster = "Waterglow Conjurer"}
	},

	-- The ways back (owner, 2026-10-20: "many teleports to hunts have no teleport back"; server/README.md "Hall order",
	-- "Ways back from the added hunts"). The base hunts have their way back on the map beside the arrival (checked on
	-- the base map: 35 of 35) and the planned hunts their camp portal (areagen exit, ChaosHuntTeleports.backFor). The
	-- hunts added to the hall without a base teleport (hall_hunts.csv rows without a place, `low_*`) had none, nor the
	-- base hunts whose destination hall_hunts.csv moved away from the base arrival (note "destination moved"). At
	-- startup each one listed here gets a magic forcefield (items.portal, action id `aid`) on `at` that leads in front
	-- of the hunt's own teleport of the hall, wherever the hall order put it, and the label "Back to the teleport room"
	-- floats over it like the hall's labels. `at`: chosen on the base map with ChaosHuntTeleportsCore.pickReturnTile
	-- (reached on foot from the arrival, a free tile: no stairs, no protection zone, no house, nothing on it, not
	-- splitting a corridor). When `at` cannot take it on the live map, startup picks the nearest such tile within
	-- `radius` of the arrival. tests/hunt_teleports_test.lua fails when a hunt of the CSV without a base teleport is
	-- missing here; tools/check_hunt_returns.py checks the map.
	returns = {
		radius = 4,
		list = {
			{id = "low_jungle_camp", at = {x = 32769, y = 32503, z = 9}},
			{id = "low_quara_grotto", at = {x = 32073, y = 32769, z = 12}},
			-- base hunts whose destination moved to their monsters (beta report 2026-10-22: a dead end with no
			-- monster, or a room the named monster cannot reach); the base way back stays at the old arrival
			{id = "base_5_31630_32254", at = {x = 34148, y = 31339, z = 8}}, -- Freakish Lost Soul
			{id = "base_5_31642_32254", at = {x = 33897, y = 31155, z = 9}}, -- Skeleton Elite Warrior
			{id = "base_5_31658_32254", at = {x = 32188, y = 31428, z = 7}}, -- Frost Dragon
			{id = "base_6_31654_32258", at = {x = 33193, y = 31776, z = 12}}, -- Blightwalker
			{id = "base_6_31662_32258", at = {x = 33634, y = 31689, z = 13}}, -- Rustheap Golem
			-- hunts whose arrival moved to a monster area of their band (O333, tools/audit_hunt_bands.py --apply: a mixed
			-- band, few monsters or a stock portal into far stronger ones); the base way back stays at the old arrival
			{id = "base_5_31630_32258", at = {x = 32041, y = 32610, z = 9}}, -- Fire Elemental
			{id = "base_5_31634_32254", at = {x = 33025, y = 32417, z = 11}}, -- Demon Skeleton
			{id = "base_5_31638_32258", at = {x = 33011, y = 32366, z = 7}}, -- Sandcrawler
			{id = "base_5_31662_32258", at = {x = 33019, y = 31932, z = 7}}, -- Scaledrake
			{id = "base_6_31634_32254", at = {x = 32936, y = 32772, z = 7}}, -- Wasp (was the Elephant hunt)
			{id = "base_6_31637_32258", at = {x = 33210, y = 32726, z = 11}}, -- Cave Rat
			{id = "base_6_31642_32254", at = {x = 32795, y = 32546, z = 11}}, -- Dawnfire Asura
			{id = "base_6_31666_32254", at = {x = 33589, y = 31648, z = 15}}, -- Behemoth
			{id = "base_6_31666_32258", at = {x = 32009, y = 31056, z = 9}}, -- Hellspawn
			-- O335 (tools/audit_hunts.py --suggest --apply): the sign monster was not at the arrival, or the hunt was sparse or tiny
			{id = "base_5_31642_32258", at = {x = 32680, y = 31294, z = 7}}, -- Nomad
			{id = "base_5_31658_32258", at = {x = 33226, y = 32115, z = 9}}, -- grothar
			{id = "base_5_31662_32254", at = {x = 32539, y = 31045, z = 6}}, -- Fleshcarver
			{id = "base_6_31638_32254", at = {x = 32196, y = 30997, z = 14}}, -- Ice Witch
			{id = "base_6_31639_32258", at = {x = 32737, y = 31326, z = 7}}, -- Minotaur
			{id = "base_6_31654_32254", at = {x = 32123, y = 32371, z = 9}}, -- Gutworm
			{id = "base_6_31657_32254", at = {x = 32069, y = 31078, z = 9}} -- Novice of the Cult
		}
	},

	-- texts: the English one is the key; pt-BR beside it
	texts = {
		["pt-BR"] = {
			["%s, levels %d-%d"] = "%s, níveis %d-%d",
			["Floor %d: levels %d-%d"] = "Andar %d: níveis %d-%d",
			["Up: floor %d, levels %d-%d"] = "Acima: andar %d, níveis %d-%d",
			["Floor %d: levels %d+"] = "Andar %d: níveis %d+",
			["Up: floor %d, levels %d+"] = "Acima: andar %d, níveis %d+",
			["Quests"] = "Missões",
			["Back to the teleport room"] = "Voltar à sala de teleportes",
			["%s is for level %d and above."] = "%s é para nível %d ou mais.",
			["%s: monsters of level %d-%d. The portal at the camp leads back to the teleport room."] =
				"%s: monstros de nível %d-%d. O portal do acampamento leva de volta à sala de teleportes."
		}
	}
}
