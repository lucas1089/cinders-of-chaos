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
		sign = 5360 -- the sign on the counter behind each teleport (its text is written at startup)
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
		east = {module = {31664, 31667}, cap = {31668, 31670}, modules = 5},
		west = {module = {31629, 31632}, cap = {31626, 31628}, modules = 5},
		-- where a plan's exit portal sends players: the middle of the corridor
		back = {x = 31648, y = 32256, z = 6}
	},

	-- The whole hall in level order (owner, 2026-10-16; server/README.md "Hall order"): every hunt teleport of the hall,
	-- the base server's (tools/hall_hunts.csv, from tools/hall_order.py derive) and the planned hunts', by level band:
	-- the entry floor (z 7) first along the corridor from west to east, then each floor up. install_content_areas.py
	-- writes it; --remove-hall puts the base hunts back. `floors`: the hall's floors, lowest bands first; `x`: the
	-- hall's span; `endRow`: the corridor's end teleports (a hunt unless it leads to `temple`); `labels`: the floor's
	-- floating label ("Floor 7: levels 1-80") over `at`, and over `up` (the stairs up) the next floor's.
	hall = {
		enabled = true,
		floors = {7, 6, 5},
		x = {31600, 31696},
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
	display = {x = {31606, 31690}, floors = {5, 7}},

	-- 5 modules a side: 20 new teleports (17 plans, 3 spare).
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
	plans = {
		{id = "bonechoir_catacomb", monster = "Deathrattle"},
		{id = "sulphur_gallery", monster = "Hellflayer"},
		{id = "widowmere", monster = "Nightfang Widow"},
		-- every monster of the plan is a 4x4 or 5x5 sprite: no display (it spilled over the cell walls into the corridor)
		{id = "wyrmspine_hollows", monster = "Ashfang Wrym", display = false},
		{id = "pyrarch_crucible", monster = "Hellmaw Brute"},
		{id = "hexwood_thicket", monster = "Black Stag"},
		{id = "corsairs_reach", monster = "Ironhook Corsair"},
		{id = "mirefang_basin", monster = "Elite Tidecrest Serpent"},
		{id = "rimecrown_depths", monster = "Spirit of Purity"}, -- 2x2; the 3x3 Celestial Wyrm spilled
		{id = "cinderglass_sanctum", monster = "Black Vixen"},
		{id = "slagmourn_foundry", monster = "Twisted Shaper"}, -- 2x2; the 5x4 Scaleborn spilled
		{id = "hollowmass_reliquary", monster = "Silicron"},
		{id = "gallowfen_mire", monster = "Thal"},
		{id = "voidscar_chasm", monster = "Facetis"},
		{id = "gravehorn_deeps", monster = "Cinderskull Reaver"},
		{id = "duskmarrow_crater", monster = "Mirecoil Wyrm"}, -- not the 5x5 Pyrewing Tyrant in a one-tile cell
		-- pair 27 trial area (levels 300-400); its boss is the Hollow Rider. 2x2; the 3x3 Bonecrusher spilled
		{id = "hollow_crypt", monster = "Sopping Carcass"}
	},

	-- texts: the English one is the key; pt-BR beside it
	texts = {
		["pt-BR"] = {
			["%s, levels %d-%d"] = "%s, níveis %d-%d",
			["Floor %d: levels %d-%d"] = "Andar %d: níveis %d-%d",
			["Up: floor %d, levels %d-%d"] = "Acima: andar %d, níveis %d-%d",
			["%s is for level %d and above."] = "%s é para nível %d ou mais.",
			["%s: monsters of level %d-%d. The portal at the camp leads back to the teleport room."] =
				"%s: monstros de nível %d-%d. O portal do acampamento leva de volta à sala de teleportes."
		}
	}
}
