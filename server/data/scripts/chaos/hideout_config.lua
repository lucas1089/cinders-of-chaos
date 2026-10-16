-- hideout_config.lua: personal Hideouts (hideout.lua, hideout_core.lua; client game_hideout, extended opcode
-- ChaosOpcodes.hideout = 192). Every number, theme and decoration lives here. Plain table, no engine calls (read by
-- server/tests/hideout_test.lua with plain Lua), loaded with  ChaosHideoutConfig = dofile("data/scripts/chaos/hideout_config.lua")
--
-- A hideout: one per character (a season character has its own, it is another character), an instanced room built at
-- runtime in a pooled slot of `grid` when someone enters and torn down when it is empty. Cosmetic only: decorations
-- change the look of the room and nothing else. The utilities are the ones every town has (the character's own depot,
-- the supply stash, exercise dummies); no buffs, no stats, no drops.
--
-- Themes: the room's floor, walls and lights. {key, name, desc, ground, walls = {v, h, pole, corner} (a wall family of
-- the base item set: the west / east walls, the north / south walls, the south-east post, the north-west corner),
-- dark = {ground, wall} (the dark tile set, chaos_dark_tiles.lua, when installed: its ground everywhere, its tall wall on
-- the north and west walls only, so it never hides the floor), light (item id of the four corner lights), maxDecor, source}
--
-- Decorations: {key, name, cat, layer, ids | rots | wall, block?, max?, source, trophy?, icon?}
--   key     stable text, unique; stored in chaos_hideout_decor / chaos_hideout_unlocks (never rename a live one)
--   cat     a key of `categories` (the window's filter)
--   layer   "object" (one per tile, may block walking), "floor" (a rug: under an object, walkable) or "wall" (hangs on
--           the north or the west wall; `wall = {n = id, w = id}`, the side picks the id)
--   ids     one tile; each id is a rotation (the client's Rotate button cycles them)
--   rots    several tiles: rots[r] = {{dx, dy, id}, ...} (offsets from the anchor tile, all >= 0)
--   block   true: players cannot walk through it (the room must keep a path to the exit, the depot, the stash and the
--           dummies; hideout_core.lua K.placeProblem)
--   max     how many of it one hideout may hold (default `defaultMax`)
--   source  how a character unlocks it (the first matching source is kept, chaos_hideout_unlocks):
--             {type = "default"}                         every character
--             {type = "achievement", id = <achievements_data.lua id>}   the account has the achievement
--             {type = "stat", stat = <achievement stat>, min = n, group = "trophy" | "event"}   the character's own
--                                                        counter (kills of that boss, invasions defended, ...)
--             {type = "faction", faction = <key>, rank = <rank key>}   the character's reputation rank (factions.lua)
--             {type = "descent", depth = n | clear = true} the Ember Descent: best depth / the boss slain once
--             {type = "journey", chapter = n}             a season journey chapter (only when that system is loaded:
--                                                        hideout.lua asks ChaosHideout.sourceProbes.journey)
--             {type = "store", price = n}                 sold in the store (category "Hideout Decorations", built by
--                                                        hideout_store.lua), per account, giftable, cosmetic only
--   trophy  {stat, boss}: the item's look text names the boss and how often the hideout's owner slew it
--   icon    item id shown in the window and the store (default: the first id)
-- Item ids are server ids of the base item set (non-moveable, not containers; checked by hand against items.otb).

return {
	opcode = 192, -- ChaosOpcodes.hideout (chaos_constants.lua)
	staffGroup = 4, -- may enter any hideout (moderation) and use /hideout

	-- player storages 7100180 - 7100189 (chaos_constants.lua): +0 .. +2 the spot a character entered from (x, y, z;
	-- the exit and a login inside a torn-down room lead back there), +3 0 = the temple instead
	storage = {returnX = 7100180, returnY = 7100181, returnZ = 7100182, returnSet = 7100183},

	tables = {
		hideouts = "chaos_hideouts", -- one row per character that changed something: theme, permission, counters
		decor = "chaos_hideout_decor", -- placed decorations (player, decor id, key, x, y, rotation)
		unlocks = "chaos_hideout_unlocks", -- unlocked decorations and themes (store: per account, player 0)
		visits = "chaos_hideout_visits", -- last visit of a character to a hideout (unique visitors per day)
		likes = "chaos_hideout_likes" -- one like per account and hideout
	},

	-- slots: built with Game.createTile where the real map has no tiles. Other runtime areas (each system's config):
	-- tower 2000+, tutorial island 4600+, world boss arena 5000+, siege 5100+, PvP arena grid 6000-6100, ascension
	-- trial 7000-7100, Ascended Omens 7600-7700, rifts 8192-8447, trials 9000-9160, guild halls 9216-9536, Ember Descent
	-- 10000-10255 x 10000-10127, raid 10400-10911 x 10000-10511, guild boss 11264-11456 x 10000-10144, battleground
	-- 11264-11456 x 11264-11456. This grid: x/y 12288-12799 (16 x 16 slots of 32 tiles), nothing else there.
	grid = {origin = {x = 12288, y = 12288, z = 7}, cols = 16, spacing = 32, maxSlots = 256},
	inner = {w = 15, h = 11}, -- the floor the decorations go on; walls around it (footprint 17 x 13)

	-- fixtures, in inner coordinates (1..w, 1..h): every theme has the same layout, so a theme change never moves a
	-- decoration. No decoration may stand on these tiles.
	fixtures = {
		arrival = {8, 10}, -- where you land
		exit = {8, 11}, -- forcefield back to where you came from
		depot = {2, 1}, -- a locker: the owner's own depot of their home town (engine patch 0017 sets its depot id)
		stash = {4, 1}, -- the supply stash (stash.lua window)
		dummies = {{13, 1}, {14, 1}}, -- exercise dummies of the base server (the store's exercise weapons work on them)
		lights = {{1, 1}, {15, 1}, {1, 11}, {15, 11}}
	},
	ids = {
		portal = 1387, -- magic forcefield (exit; the temple entry)
		depot = 2589, -- locker (type depot)
		stash = 10081, -- storage chest: opens the supply stash
		dummies = {27751, 27752}
	},
	aid = {enter = 47610, exit = 47611, depot = 47612, stash = 47613, decor = 47614, fixture = 47615},

	-- the Hideout Portal of every town: placed by cityportals.lua (cityportals_config.lua: the portal room of the Hall
	-- of Services in Cinderhold and Mirewake, a fixed spot next to every other temple); these offsets only when neither
	-- is free (another map)
	portalOffsets = {{2, -3}, {-2, -3}, {2, 3}, {-2, 3}, {5, 0}, {-5, 0}, {5, 1}, {-5, 1}},
	mainTown = 2, -- Cinderhold: the exit's last resort when the character's home town has no temple

	emptySeconds = 30, -- an empty room is torn down after this (its slot goes back to the pool)
	thinkMs = 3000,
	defaultMax = 4,
	defaultPermission = 1, -- friends
	permissions = {
		{id = 0, key = "private", name = "Private", desc = "Only you."},
		{id = 1, key = "friends", name = "Friends", desc = "You, your VIP list and your party."},
		{id = 2, key = "guild", name = "Guild", desc = "Friends and your guild."},
		{id = 3, key = "public", name = "Public", desc = "Everyone; listed in the showcase."}
	},
	likes = {perDay = 10, cooldownMs = 2000}, -- likes an account may give a day; one like per account and hideout
	requestMs = {edit = 250, list = 1000, visit = 1500}, -- rate limits of the window's requests
	showcaseSize = 15,
	visitListSize = 30,

	-- rank order of factions_config.lua `ranks` (a faction source needs this rank or better)
	factionRanks = {"hostile", "wary", "neutral", "trusted", "honored", "revered", "exalted"},

	categories = {
		{key = "furniture", name = "Furniture"},
		{key = "light", name = "Lights"},
		{key = "statue", name = "Statues"},
		{key = "nature", name = "Nature"},
		{key = "macabre", name = "Bones"},
		{key = "banner", name = "Banners"},
		{key = "wall", name = "Wall"},
		{key = "rug", name = "Rugs"},
		{key = "trophy", name = "Trophies"}
	},

	themes = {
		{key = "ashen_crypt", name = "Ashen Crypt", desc = "Cracked flagstones and soot-black walls.",
			ground = 413, walls = {v = 1049, h = 1050, pole = 1051, corner = 1052}, light = 1481,
			dark = {ground = "ruined_floor", wall = "ruined_wall"}, maxDecor = 24, source = {type = "default"}},
		{key = "ember_forge", name = "Ember Forge", desc = "Obsidian floors still warm from the Descent.",
			ground = 407, walls = {v = 1025, h = 1026, pole = 1027, corner = 1028}, light = 1486,
			dark = {ground = "obsidian_floor", wall = "obsidian_wall"}, maxDecor = 30, source = {type = "descent", depth = 5}},
		{key = "veiled_sanctum", name = "Veiled Sanctum", desc = "Pale marble where the Choir keeps its silences.",
			ground = 406, walls = {v = 1111, h = 1112, pole = 1113, corner = 1114}, light = 9439,
			maxDecor = 36, source = {type = "faction", faction = "choir", rank = "honored"}},
		{key = "thornbound_grove", name = "Thornbound Grove", desc = "Moss and roots behind a living wall.",
			ground = 4526, walls = {v = 3497, h = 3498, pole = 3500, corner = 3501}, light = 1481,
			dark = {ground = "dark_moss"}, maxDecor = 36, source = {type = "faction", faction = "circle", rank = "honored"}}
	},

	decorations = {
		-- ---------------------------------------------------------------- furniture
		{key = "ashen_throne", name = "Ashen Throne", cat = "furniture", layer = "object", ids = {1646, 1647, 1648, 1649},
			max = 2, source = {type = "default"}},
		{key = "stone_seat", name = "Stone Seat", cat = "furniture", layer = "object", ids = {7277, 7278, 7279, 7280},
			source = {type = "store", price = 120}},
		{key = "wyrmbone_throne", name = "Wyrmbone Throne", cat = "furniture", layer = "object", ids = {10950, 10951},
			max = 1, source = {type = "store", price = 300}},
		{key = "stone_table", name = "Stone Table", cat = "furniture", layer = "object", ids = {7273, 7274, 7275, 7276},
			block = true, source = {type = "default"}},
		{key = "weapon_rack", name = "Weapon Rack", cat = "furniture", layer = "object", ids = {5852, 5853}, block = true,
			max = 2, source = {type = "default"}},
		{key = "armor_stand", name = "Armor Stand", cat = "furniture", layer = "object", ids = {5860, 5861}, block = true,
			max = 2, source = {type = "faction", faction = "compact", rank = "trusted"}},
		-- ---------------------------------------------------------------- lights
		{key = "coal_basin", name = "Coal Basin", cat = "light", layer = "object", ids = {1481}, block = true,
			source = {type = "default"}},
		{key = "ember_basin", name = "Ember Basin", cat = "light", layer = "object", ids = {1486}, block = true,
			source = {type = "descent", depth = 9}},
		{key = "tall_candelabrum", name = "Tall Candelabrum", cat = "light", layer = "object", ids = {9439}, block = true,
			source = {type = "store", price = 150}},
		{key = "skull_candle", name = "Skull Candle", cat = "light", layer = "object", ids = {3744},
			source = {type = "achievement", id = "omen_1"}},
		{key = "wall_lamp", name = "Wall Lamp", cat = "light", layer = "wall", wall = {n = 2040, w = 2038},
			source = {type = "default"}},
		-- ---------------------------------------------------------------- statues
		{key = "gargoyle", name = "Gargoyle", cat = "statue", layer = "object", ids = {1452, 1453, 1454, 1455}, block = true,
			source = {type = "store", price = 200}},
		{key = "sacred_statue", name = "Pyrewarden Statue", cat = "statue", layer = "object", ids = {3697, 3698, 3699, 3700},
			block = true, max = 2, source = {type = "faction", faction = "vigil", rank = "revered"}},
		{key = "angel_statue", name = "Mourning Angel", cat = "statue", layer = "object", ids = {1448}, block = true,
			max = 2, source = {type = "store", price = 200}},
		{key = "hero_statue", name = "Hero Statue", cat = "statue", layer = "object", ids = {1444}, block = true, max = 1,
			source = {type = "achievement", id = "level_300"}},
		{key = "broken_obelisk", name = "Broken Obelisk", cat = "statue", layer = "object", ids = {1561}, block = true,
			source = {type = "default"}},
		{key = "obelisk", name = "Forge Obelisk", cat = "statue", layer = "object", ids = {1560}, block = true, max = 2,
			source = {type = "faction", faction = "compact", rank = "honored"}},
		{key = "crystal_column", name = "Choir Crystal", cat = "statue", layer = "object", ids = {9779}, block = true,
			max = 2, source = {type = "faction", faction = "choir", rank = "revered"}},
		{key = "black_crystal", name = "Black Crystal", cat = "statue", layer = "object", ids = {11753}, block = true,
			max = 2, source = {type = "store", price = 250}},
		-- ---------------------------------------------------------------- nature
		{key = "dead_tree", name = "Dead Tree", cat = "nature", layer = "object", ids = {2709}, block = true,
			source = {type = "default"}},
		{key = "shadow_plant", name = "Shadow Plant", cat = "nature", layer = "object", ids = {2769}, block = true,
			source = {type = "default"}},
		{key = "mourning_mushroom", name = "Mourning Mushroom", cat = "nature", layer = "object", ids = {10813},
			block = true, source = {type = "faction", faction = "circle", rank = "trusted"}},
		{key = "cauldron_plant", name = "Witchroot", cat = "nature", layer = "object", ids = {4149}, block = true,
			max = 2, source = {type = "faction", faction = "circle", rank = "revered"}},
		-- ---------------------------------------------------------------- bones
		{key = "bone_pile", name = "Pile of Bones", cat = "macabre", layer = "object", ids = {3125},
			source = {type = "default"}},
		{key = "skulls", name = "Scattered Skulls", cat = "macabre", layer = "object", ids = {5018},
			source = {type = "default"}},
		{key = "burning_skull", name = "Burning Skull", cat = "macabre", layer = "object", ids = {5020},
			source = {type = "stat", stat = "invasion_defended", min = 1, group = "event", label = "Defend a town from an invasion"}},
		{key = "beast_skull", name = "Great Beast Skull", cat = "macabre", layer = "object", ids = {6970}, max = 1,
			source = {type = "stat", stat = "goblin_kills", min = 10, group = "event", label = "Slay 10 Treasure Goblins"}},
		{key = "skull_pillar", name = "Skull Pillar", cat = "macabre", layer = "object", ids = {7058}, block = true,
			max = 2, source = {type = "achievement", id = "rift_t5"}},
		-- ---------------------------------------------------------------- banners
		{key = "crimson_banner", name = "Crimson Banner", cat = "banner", layer = "object", ids = {10954, 10955},
			block = true, source = {type = "default"}},
		{key = "wyrm_banner", name = "Wyrm Banner", cat = "banner", layer = "object", ids = {10952, 10953}, block = true,
			source = {type = "store", price = 150}},
		{key = "clan_banner", name = "Clan Banner", cat = "banner", layer = "object", ids = {6793, 6794}, block = true,
			source = {type = "faction", faction = "compact", rank = "honored"}},
		{key = "blighted_banner", name = "Blighted Banner", cat = "banner", layer = "object", ids = {11289, 11290},
			block = true, source = {type = "stat", stat = "invasion_defended", min = 5, group = "event",
				label = "Defend 5 invasions"}},
		{key = "wayfarer_banner", name = "Wayfarer's Banner", cat = "banner", layer = "object", ids = {9442}, block = true,
			max = 1, source = {type = "journey", chapter = 1}},
		{key = "pilgrim_shrine", name = "Pilgrim's Shrine", cat = "statue", layer = "object", ids = {1354}, block = true,
			max = 1, source = {type = "journey", chapter = 3}},
		-- ---------------------------------------------------------------- wall
		{key = "crimson_tapestry", name = "Crimson Tapestry", cat = "wall", layer = "wall", wall = {n = 1867, w = 1868},
			source = {type = "default"}},
		{key = "violet_tapestry", name = "Violet Tapestry", cat = "wall", layer = "wall", wall = {n = 1855, w = 1856},
			source = {type = "faction", faction = "choir", rank = "trusted"}},
		{key = "azure_tapestry", name = "Azure Tapestry", cat = "wall", layer = "wall", wall = {n = 1870, w = 1871},
			source = {type = "store", price = 100}},
		-- ---------------------------------------------------------------- rugs
		{key = "crimson_rug", name = "Crimson Rug", cat = "rug", layer = "floor", ids = {1798}, max = 20,
			source = {type = "default"}},
		{key = "woven_rug", name = "Woven Rug", cat = "rug", layer = "floor", ids = {1804}, max = 20,
			source = {type = "store", price = 80}},
		-- ---------------------------------------------------------------- trophies (kills the owner made)
		{key = "trophy_ulthar", name = "Gravewarden's Watchdog", cat = "trophy", layer = "object", ids = {1450},
			block = true, max = 1, trophy = {stat = "raid_ulthar", boss = "Gravewarden Ulthar"},
			source = {type = "stat", stat = "raid_ulthar", min = 1, group = "trophy"}},
		{key = "trophy_morwen", name = "Ash-Sister's Effigy", cat = "trophy", layer = "object", ids = {3739, 3740, 3741, 3742},
			block = true, max = 1, trophy = {stat = "raid_morwen", boss = "Morwen the Ash-Sister"},
			source = {type = "stat", stat = "raid_morwen", min = 1, group = "trophy"}},
		{key = "trophy_colossus", name = "Marrow Heap", cat = "trophy", layer = "object", ids = {11253}, block = true,
			max = 1, trophy = {stat = "raid_colossus", boss = "the Marrow Colossus"},
			source = {type = "stat", stat = "raid_colossus", min = 1, group = "trophy"}},
		{key = "trophy_hexmaw", name = "Hexmaw Totem", cat = "trophy", layer = "object", ids = {3802}, block = true,
			max = 1, trophy = {stat = "raid_hexmaw", boss = "Vhoss the Hexmaw"},
			source = {type = "stat", stat = "raid_hexmaw", min = 1, group = "trophy"}},
		{key = "trophy_sovereign", name = "Sovereign's Monument", cat = "trophy", layer = "object", ids = {1445},
			block = true, max = 1, trophy = {stat = "raid_sovereign", boss = "Varkhul the Ashen Sovereign"},
			source = {type = "stat", stat = "raid_sovereign", min = 1, group = "trophy"}},
		{key = "trophy_bloodmoon", name = "Bloodmoon Crystal", cat = "trophy", layer = "object", ids = {8633}, block = true,
			max = 1, trophy = {stat = "ascended_bloodmoon", boss = "Ascended Sangrith"},
			source = {type = "stat", stat = "ascended_bloodmoon", min = 1, group = "trophy"}},
		{key = "trophy_hollow", name = "Hollow Shard", cat = "trophy", layer = "object", ids = {11826}, block = true,
			max = 1, trophy = {stat = "ascended_hollow", boss = "Ascended Morvane"},
			source = {type = "stat", stat = "ascended_hollow", min = 1, group = "trophy"}},
		{key = "trophy_storm", name = "Stormglass Column", cat = "trophy", layer = "object", ids = {9784}, block = true,
			max = 1, trophy = {stat = "ascended_storm", boss = "Ascended Thalcyra"},
			source = {type = "stat", stat = "ascended_storm", min = 1, group = "trophy"}},
		{key = "trophy_cinderheart", name = "Cinderheart Pyre", cat = "trophy", layer = "object", ids = {1484}, block = true,
			max = 1, trophy = {stat = "cinder_kills", boss = "Ysgrath the Cinderheart"},
			source = {type = "stat", stat = "cinder_kills", min = 1, group = "trophy"}},
		{key = "trophy_descent", name = "Throne of the Descent", cat = "trophy", layer = "object", ids = {10816},
			block = true, max = 1, source = {type = "descent", clear = true}},
		{key = "trophy_kaelgor", name = "Kaelgor's Horns", cat = "trophy", layer = "wall", wall = {n = 1882, w = 1883},
			max = 1, trophy = {stat = "wb_kaelgor", boss = "Kaelgor the Infernal Warlord"},
			source = {type = "stat", stat = "wb_kaelgor", min = 1, group = "trophy"}},
		{key = "trophy_skaldra", name = "Skaldra's Skull", cat = "trophy", layer = "wall", wall = {n = 1894, w = 1895},
			max = 1, trophy = {stat = "wb_skaldra", boss = "Skaldra the Rime Queen"},
			source = {type = "stat", stat = "wb_skaldra", min = 1, group = "trophy"}},
		{key = "trophy_rotmother", name = "Rotmother's Maw", cat = "trophy", layer = "wall", wall = {n = 1888, w = 1889},
			max = 1, trophy = {stat = "wb_rotmother", boss = "The Rotmother"},
			source = {type = "stat", stat = "wb_rotmother", min = 1, group = "trophy"}},
		{key = "trophy_nyxareth", name = "Nyxareth's Mane", cat = "trophy", layer = "wall", wall = {n = 1896, w = 1897},
			max = 1, trophy = {stat = "wb_nyxareth", boss = "Nyxareth the Void Archon"},
			source = {type = "stat", stat = "wb_nyxareth", min = 1, group = "trophy"}},
		{key = "trophy_vharok", name = "Vharok's Horns", cat = "trophy", layer = "wall", wall = {n = 1898, w = 1899},
			max = 1, trophy = {stat = "wb_vharok", boss = "Vharok the Blood Colossus"},
			source = {type = "stat", stat = "wb_vharok", min = 1, group = "trophy"}}
	}
}
