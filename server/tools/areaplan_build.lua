-- The area planner's bridge to the area generator (server/tools/area_planner.py; docs/MAP_GUIDE.md "Area planner").
-- Run from the server/ folder with LuaJIT or Lua 5.3:
--     luajit tools/areaplan_build.lua catalogue [pair24] [dark]   the biomes, materials and items a plan may use (JSON)
--     luajit tools/areaplan_build.lua build JOB.lua [pair24] [dark] the tile model of one compiled plan (lines below)
--
-- A plan never holds an item id. Every id comes from our own tables, read here:
--   data/scripts/chaos/areagen_config.lua   families, border pieces, walls, themes, hole / ladder / portal
--   data/lib/chaos_dark_tiles.lua           the dark tile set (names -> ids; with "dark")
--   data/lib/chaos_theme_items.lua          the swamp, acid, lava and water grounds of pair 24 (with "pair24")
--   data/items/art_items.csv                the pack grounds, their border pieces and the trees (forest, ice)
--   data/scripts/chaos/rift_config.lua      the chest (chest.itemId)
-- A biome is one of our areagen themes, sometimes with other families of those tables (BIOMES below).
--
-- build prints the lines of tools/areagen_dump.lua (A, F, T, L, R, Q, X, C) and one last line
--   J {json}   allowed ids, the family of every ground id, the border rules and piece sets, the chest id
-- The job file is written by area_planner.py: return {def = {...}, biome = name, decor = mult, light = mult}.
dofile("data/scripts/chaos/areagen_core.lua")
dofile("data/lib/chaos_dark_tiles.lua")
local A = ChaosAreaGenCore
local cfg = dofile("data/scripts/chaos/areagen_config.lua")
local riftCfg = dofile("data/scripts/chaos/rift_config.lua")
local floor = math.floor

local mode = arg[1]
local flags = {}
for k = 2, #arg do
	flags[arg[k]] = true
end
local dark = flags.dark or false
local pair24 = flags.pair24 or false
local opts = {dark = dark, darkIds = ChaosDarkTiles.ids}

-- ------------------------------------------------------------------ our other tables
local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

-- data/items/art_items.csv: key -> {id, kind, piece, family}
local function csvFields(line)
	local out, cur, q, k = {}, {}, false, 1
	while k <= #line do
		local c = line:sub(k, k)
		if q then
			if c == '"' and line:sub(k + 1, k + 1) == '"' then
				cur[#cur + 1] = '"'
				k = k + 1
			elseif c == '"' then
				q = false
			else
				cur[#cur + 1] = c
			end
		elseif c == '"' then
			q = true
		elseif c == "," then
			out[#out + 1] = table.concat(cur)
			cur = {}
		else
			cur[#cur + 1] = c
		end
		k = k + 1
	end
	out[#out + 1] = table.concat(cur)
	return out
end

local pack = {}
do
	local text = readFile("data/items/art_items.csv") or ""
	local head
	for line in text:gmatch("[^\r\n]+") do
		local f = csvFields(line)
		if not head then
			head = {}
			for k, v in ipairs(f) do
				head[v] = k
			end
		else
			local extra = f[head.extra] or ""
			pack[f[head.key]] = {id = tonumber(f[head.server_id]), kind = f[head.kind], piece = extra:match("piece=([%w_]+)"),
				family = extra:match("family=([%w_]+)")}
		end
	end
end

local themeItems = {}
do
	local ok, t = pcall(dofile, "data/lib/chaos_theme_items.lua")
	themeItems = ok and t or {}
end

-- ------------------------------------------------------------------ extra families (ids from the tables above)
-- the 12 pieces of a border set in the generator's names from a table of our naming
local function piecesFrom(get)
	return {n = get("n"), e = get("e"), s = get("s"), w = get("w"),
		cnw = get("outer_nw"), cne = get("outer_ne"), csw = get("outer_sw"), cse = get("outer_se"),
		dnw = get("inner_nw"), dne = get("inner_ne"), dsw = get("inner_sw"), dse = get("inner_se")}
end

-- pair 24 grounds: swamp (walkable), acid, lava, water (blocking)
local P24 = {swamp = {z = 3100, walk = true}, acid = {z = 3200, walk = false}, lava = {z = 3300, walk = false},
	water = {z = 3400, walk = false}}
local function addPair24()
	for name, d in pairs(P24) do
		local g = themeItems.grounds and themeItems.grounds[name]
		if g and g.ground then
			local fam = "p24_" .. name
			cfg.families[fam] = {z = d.z, grounds = {{g.ground, 1}}, walk = d.walk}
			cfg.pieces[fam] = piecesFrom(function(p) return g[p] end)
			cfg.borders[fam] = {["*"] = fam}
		end
	end
end

-- pack grounds (key ground_<name>, pieces border_<name>_<n|nw|in_nw ...>)
local PACK = {loam = 3500, dense_grass = 3600, fresh_snow = 3600, dry_grass = 3620, meadow_grass = 3650,
	lush_grass = 3700}
local packPiece = {outer_nw = "nw", outer_ne = "ne", outer_sw = "sw", outer_se = "se", inner_nw = "in_nw",
	inner_ne = "in_ne", inner_sw = "in_sw", inner_se = "in_se"}
local function addPack()
	for name, z in pairs(PACK) do
		local g = pack["ground_" .. name]
		if g and g.id then
			local fam = "pk_" .. name
			cfg.families[fam] = {z = z, grounds = {{g.id, 1}}}
			cfg.pieces[fam] = piecesFrom(function(p)
				local e = pack["border_" .. name .. "_" .. (packPiece[p] or p)]
				return e and e.id
			end)
			cfg.borders[fam] = {["*"] = fam}
		end
	end
end
addPack()

-- stock grounds of the 10.98 pair with their border pieces (the planner's own catalogue; pieces named like the
-- generator's sets, checked on renders of each piece: n = the higher ground lies north, c.. = that corner only,
-- d.. = two sides and the corner). Snow over ice and rock, ice over rock, grass over dirt (docs/MAP_GUIDE.md rule 2).
local function set12(first)
	return {n = first, e = first + 1, s = first + 2, w = first + 3, cnw = first + 4, cne = first + 5, csw = first + 6,
		cse = first + 7, dnw = first + 8, dne = first + 9, dsw = first + 10, dse = first + 11}
end
local function addStock()
	local snow = {{670, 8}}
	for _, id in ipairs({6580, 6587, 6588, 6589, 6590, 6591, 6592, 6593, 6594, 6595, 6597, 6602, 6603, 6604, 6605, 6606,
		6607, 6608}) do
		snow[#snow + 1] = {id, 2}
	end
	for _, id in ipairs({6581, 6583, 6584, 6596, 6598, 6599, 6600, 6601}) do
		snow[#snow + 1] = {id, 1}
	end
	cfg.families.st_snow = {z = 3650, grounds = snow}
	cfg.families.st_ice = {z = 3550, grounds = {{671, 4}, {6683, 1}, {6684, 1}, {6685, 1}, {6686, 1}}}
	-- the light grass family (106 is a darker grass that does not blend with it)
	local grass = {{4526, 6}}
	for id = 4527, 4541 do
		grass[#grass + 1] = {id, 1}
	end
	cfg.families.st_grass = {z = 3600, grounds = grass}
	cfg.families.st_dirt = {z = 3450, grounds = {{103, 1}}}
	cfg.pieces.st_snow = set12(4737)
	cfg.pieces.st_ice = set12(6695)
	cfg.pieces.st_grass = set12(4542)
	cfg.borders.st_snow = {["*"] = "st_snow"}
	cfg.borders.st_ice = {["*"] = "st_ice"}
	cfg.borders.st_grass = {["*"] = "st_grass"}
	-- the towns' own tiles (the Halls of Services, server/README.md "Main city"): Cinderhold's temple floor (white
	-- marble) and its grey stone walls; pieces as the live map uses them (pole = the north-west corner, corner = the
	-- south-east one, see areagen_core.lua A.wallPiece)
	cfg.families.st_white_marble = {z = 1, grounds = {{406, 1}}, indoor = true}
	cfg.walls.st_stone = {horizontal = {{1050, 1}}, vertical = {{1049, 1}}, corner = {{1053, 1}}, pole = {{1051, 1}}}
end
addStock()

-- the harvest kit of pair 33 (data/lib/chaos_pack33_kit.lua, server/tools/install_pack33_items.py): five farmland
-- grounds and two crypt grounds of 9 variants, their border sets (the kit's N, E, S, W sides, its NE.. corner nubs as
-- c.. and its IN_NE.. pieces as d..: two sides and the corner) and the crypt brick walls. Used by the biomes harvest
-- and harvest_crypt (the Haunted Harvest, server/README.md "Haunted Harvest"); the ids exist in the game only while
-- ChaosHarvestArt.PAIR33 is on, so install_content_areas.py places those plans only then.
local kit = {}
do
	local ok, t = pcall(dofile, "data/lib/chaos_pack33_kit.lua")
	kit = ok and type(t) == "table" and t.items or {}
end
local function kitId(key)
	local e = kit[key]
	return e and e.id
end
local KIT_GROUNDS = {k_grass = {"autumn_grass", 3700}, k_grave = {"grave_grass", 3750}, k_soil = {"tilled_soil", 3420},
	k_stubble = {"corn_stubble", 3440}, k_mud = {"mud_road", 3400}, k_flag = {"crypt_flagstones", 1500},
	k_bone = {"bone_dust", 1550}}
local KIT_SETS = {k_grass_mud = "autumn_grass_on_mud_road", k_grass_soil = "autumn_grass_on_tilled_soil",
	k_grave_mud = "grave_grass_on_mud_road", k_bone_flag = "bone_dust_on_crypt_flagstones"}
local kitPiece = {outer_nw = "nw", outer_ne = "ne", outer_sw = "sw", outer_se = "se", inner_nw = "in_nw",
	inner_ne = "in_ne", inner_sw = "in_sw", inner_se = "in_se"}
local function addKit()
	for fam, d in pairs(KIT_GROUNDS) do
		local rows = {}
		for n = 1, 9 do
			local id = kitId(d[1] .. "_" .. n)
			if id then
				rows[#rows + 1] = {id, n == 1 and 6 or 1}
			end
		end
		if #rows > 0 then
			cfg.families[fam] = {z = d[2], grounds = rows, indoor = (fam == "k_flag" or fam == "k_bone") or nil}
		end
	end
	for set, prefix in pairs(KIT_SETS) do
		cfg.pieces[set] = piecesFrom(function(p)
			return kitId(prefix .. "_" .. (kitPiece[p] or p))
		end)
	end
	cfg.borders.k_grass = {k_mud = "k_grass_mud", ["*"] = "k_grass_soil"}
	cfg.borders.k_grave = {["*"] = "k_grave_mud"}
	cfg.borders.k_bone = {["*"] = "k_bone_flag"}
	local function w(h, broken)
		return {{kitId(h), 6}, {kitId(broken), 1}}
	end
	cfg.walls.k_brick = {horizontal = w("crypt_brick_h", "crypt_brick_broken_h"),
		vertical = w("crypt_brick_v", "crypt_brick_broken_v"), corner = {{kitId("crypt_brick_corner"), 1}},
		pole = {{kitId("crypt_brick_post"), 1}}}
end
if kitId("autumn_grass_1") then
	addKit()
end
-- "kit:a,b:3,c" stands for kit keys with weights (default 1)
local function kitRows(spec)
	local out = {}
	for part in spec:gmatch("[^,]+") do
		local key, wt = part:match("^([%w_]+):?(%d*)$")
		local id = kitId(key)
		assert(id, "unknown kit key " .. tostring(key))
		out[#out + 1] = {id, tonumber(wt) or 1}
	end
	return out
end

local function ids(list)
	local rows = {}
	for _, id in ipairs(list) do
		rows[#rows + 1] = {id, 1}
	end
	return rows
end

if pair24 then
	addPair24()
end

local function trees(families)
	local rows, want = {}, {}
	for _, f in ipairs(families) do
		want[f] = true
	end
	local keys = {}
	for key, e in pairs(pack) do
		if e.kind == "tree" and want[e.family] and e.id then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		rows[#rows + 1] = {pack[key].id, 1}
	end
	return rows
end

local function copy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = copy(x)
	end
	return out
end

local function rowsOf(theme, key)
	local t = cfg.themes[theme]
	return copy(t[key] and t[key].items or t[key] or {})
end

-- ------------------------------------------------------------------ biomes
-- kind: the generator's layout kind (cave and waste: rock around the floor; dungeon: walls). theme: the areagen theme
-- it starts from. override: keys replaced in that theme (and dropped from its dark part). pair24: keys replaced when
-- the pair 24 switch is on (fallback otherwise). needs: what must be installed for the ids to exist.
local BIOMES = {
	cave = {kind = "cave", theme = "emberdeep", z = 9, light = "dim",
		desc = "earth cave: dirt walls, mud and lava-crack patches, small lava pools, glowing mushrooms"},
	lava = {kind = "cave", theme = "cinderfall", z = 10, light = "normal",
		desc = "lava cave: grey rock floor and basalt, lava cracks, lava pools, mountain walls",
		override = {pools = {{family = "lava", share = 0.05, radius = {2, 4}}}},
		pair24 = {pools = {{family = "lava", share = 0.04, radius = {2, 4}}, {family = "p24_lava", share = 0.015,
			radius = {2, 3}}}}},
	waste = {kind = "waste", theme = "cinderfall", z = 7, light = "normal",
		desc = "open waste under the sky: rock floor, basalt fields, lava cracks and pools, cliffs, dead trees"},
	swamp = {kind = "cave", theme = "emberdeep", z = 8, light = "dim",
		desc = "sunken swamp: cave floor with wide mud (pair 24: swamp ground, water and acid pools), swamp trees",
		override = {patches = {{family = "mud", share = 0.16, radius = {2, 4}}}, pools = {},
			obstacles = {share = 0.02, items = "trees:swamp,dead"},
			lights = {per100 = 2, spacing = 6, items = "ids:17750,17751,17749"}},
		pair24 = {patches = {{family = "p24_swamp", share = 0.14, radius = {2, 4}}, {family = "mud", share = 0.05,
			radius = {2, 3}}}, pools = {{family = "p24_water", share = 0.03, radius = {2, 3}},
			{family = "p24_acid", share = 0.008, radius = {1, 2}}}}},
	crypt = {kind = "dungeon", theme = "ossuary", z = 9, light = "dim",
		desc = "crypt: rooms of slate, marble and flagstone in old stone walls, rubble, bones, coffins and shelves"},
	vault = {kind = "dungeon", theme = "vault", z = 9, light = "normal",
		desc = "vault: dark stone halls with flagstone, slate and tile rooms and a marble boss room"},
	catacomb = {kind = "dungeon", theme = "rift_crypt", z = 10, light = "dim",
		desc = "catacombs: crypt sand corridors, slate and flagstone rooms, ruin walls"},
	hall = {kind = "dungeon", theme = "rift_hall", z = 9, light = "normal",
		desc = "black marble halls in dark stone walls"},
	-- the Halls of Services (server/README.md "Main city"): a town building, not a dungeon: no clutter, no pillars
	townhall = {kind = "dungeon", theme = "rift_hall", z = 7, light = "bright",
		desc = "town hall: white marble floor in grey stone walls, as the temples of the towns; no clutter",
		override = {floor = "st_white_marble", wall = "st_stone", roomFloors = {"st_white_marble"},
			bossFloor = "st_white_marble", mixedFloors = {"st_white_marble"}, patches = {}, pools = {},
			decor = {share = 0, scatter = {}, clusters = {}}, obstacles = {share = 0, items = {}},
			props = {per100 = 0, spacing = 3, items = {}}, lights = {per100 = 0, spacing = 6, items = "ids:1484"}}},
	abyss = {kind = "cave", theme = "rift_abyss", z = 11, light = "dark",
		desc = "eldritch waste or cave of rift floor"},
	sanctum = {kind = "cave", theme = "rift_sanctum", z = 9, light = "dim",
		desc = "blighted cave with mud and cracks (dark set: wet and mossy rock, moss, glowcaps)"},
	-- forest and ice of stock grounds (no install step needed); the pack versions need the packitems step
	forest = {kind = "waste", theme = "cinderfall", z = 7, light = "normal",
		desc = "forest glade: grass (16 stock ids) with dirt patches, trees, bushes and tufts, cliffs",
		override = {floor = "st_grass", rock = "mountain",
			patches = {{family = "st_dirt", share = 0.05, radius = {2, 3}}},
			pools = {}, obstacles = {share = 0.05, items = "ids:2700,2701,2702,2703,2704,2706,2707,2708,2711,2712,2722,2767,2785"},
			decor = {share = 0.12, scatter = "ids:6216,6217,6218,6219,10738,10739,3610,3611,3613,6226,6227",
				clusters = {{per1000 = 6, size = {3, 5}, radius = 2, items = "ids:6216,6217,6218,6219,6228"}}},
			lights = {per100 = 0.2, spacing = 12, items = "theme:cinderfall:lights"}}},
	ice = {kind = "waste", theme = "cinderfall", z = 7, light = "normal",
		desc = "snow field: 27 stock snow grounds with ice sheets and grey rock, snowy trees and stones, cliffs",
		override = {floor = "st_snow", rock = "mountain",
			patches = {{family = "st_ice", share = 0.09, radius = {2, 4}}, {family = "rockfloor", share = 0.03,
				radius = {1, 3}}},
			pools = {}, obstacles = {share = 0.025, items = "ids:2697,7020,7021,7022,2698,6999,7000,7002,6707,6708"},
			decor = {share = 0.07, scatter = "ids:6715,6716,6717,6718,7001,7003",
				clusters = {{per1000 = 4, size = {2, 4}, radius = 1, items = "ids:6715,6716,6717"}}},
			lights = {per100 = 0.3, spacing = 10, items = "theme:cinderfall:lights"}}},
	forest_pack = {kind = "waste", theme = "cinderfall", z = 7, light = "normal", needs = "pack items (install step packitems)",
		desc = "forest glade of the pack grounds: dense grass with lush and meadow grass and loam, pack trees, stones, cliffs",
		override = {floor = "pk_dense_grass", rock = "mountain",
			patches = {{family = "pk_lush_grass", share = 0.10, radius = {2, 4}}, {family = "pk_meadow_grass", share = 0.07,
				radius = {2, 4}}, {family = "pk_loam", share = 0.04, radius = {2, 3}}},
			pools = {}, obstacles = {share = 0.05, items = "trees:broadleaf,conifer,fruit"},
			lights = {per100 = 0.3, spacing = 10, items = "theme:cinderfall:lights"}}},
	-- the Haunted Harvest (pair 33 kit, server/README.md "Haunted Harvest"): a cursed farmland at night and its crypts
	harvest = {kind = "waste", theme = "cinderfall", z = 7, light = "dim",
		needs = "the pair 33 kit (install step pack33items; ChaosHarvestArt.PAIR33)",
		desc = "haunted farmland at night: autumn grass, tilled fields, corn stubble, mud roads and grave grass, corn, pumpkins, dead trees, scarecrows, tombstones, jack-o'-lanterns",
		override = {floor = "k_grass", rock = "mountain",
			patches = {{family = "k_soil", share = 0.10, radius = {3, 6}}, {family = "k_stubble", share = 0.07,
				radius = {3, 5}}, {family = "k_mud", share = 0.04, radius = {2, 3}}, {family = "k_grave", share = 0.04,
				radius = {2, 4}}},
			pools = {},
			obstacles = {share = 0.025, items = "kit:corn_tall:4,corn_clump:3,corn_single:2,corn_broken:2,dead_tree_small:2,birch_bare:2,hay_bale:2,hay_bale_stack:1,scarecrow:1,pumpkin_big:2,pumpkin_rotten:2,pumpkin_stack:1,tombstone_round:1,tombstone_cross:1,tombstone_cracked:1,wheelbarrow:1,apple_barrel:1,signpost_crooked:1"},
			decor = {share = 0.13, scatter = "kit:leaves_orange:4,leaves_red:4,straw_scatter:3,puddle_moon:1,bones_small:1,fog_patch_1:2,fog_patch_2:2,vine_decal_1:1,vine_decal_2:1,pumpkin_small:2",
				clusters = {{per1000 = 6, size = {3, 5}, radius = 2, items = "kit:leaves_orange:2,leaves_red:2,straw_scatter:2,pumpkin_small:1"},
					{per1000 = 3, size = {2, 4}, radius = 2, items = "kit:fog_patch_1:1,fog_patch_2:1,bones_small:1"}}},
			lights = {per100 = 1.4, spacing = 7, items = "kit:jack_lantern_grin:2,jack_lantern_scary:2,jack_lantern_cute:1,lantern_post:2"}}},
	harvest_crypt = {kind = "dungeon", theme = "rift_crypt", z = 8, light = "dark",
		needs = "the pair 33 kit (install step pack33items; ChaosHarvestArt.PAIR33)",
		desc = "the harvest catacombs: crypt flagstone halls with bone dust in crypt brick walls, urns, bones, skull niches",
		override = {floor = "k_flag", wall = "k_brick", roomFloors = {"k_flag", "k_flag", "k_bone"}, bossFloor = "k_bone",
			mixedFloors = {"k_flag", "k_bone"},
			patches = {{family = "k_bone", share = 0.06, radius = {2, 3}}}, pools = {},
			decor = {share = 0.12, scatter = "kit:bone_fragments:3,skull_rubble:2,puddle_crypt:1,candle_drips:2,rat_droppings:2,bones_small:2,cobweb_sheet:1",
				clusters = {{per1000 = 6, size = {3, 5}, radius = 1, items = "kit:bone_fragments:2,skull_rubble:2,bones_small:1"}}},
			obstacles = {share = 0.008, items = "kit:urn_large:2,urn_cluster:2,skull_pile:1,rat_skeleton_a:1,rat_skeleton_b:1"},
			lights = {per100 = 3.5, spacing = 5, items = "kit:skull_candle_niche:2,black_candles:2"},
			props = {per100 = 2, spacing = 3, items = "kit:urn_large:2,urn_cluster:2,skull_pile:1,hanging_chains:1,rat_skeleton_a:1"}}},
	ice_pack = {kind = "waste", theme = "cinderfall", z = 7, light = "normal", needs = "pack items (install step packitems)",
		desc = "snow field of the pack grounds: fresh snow with grey rock patches, frost trees and stones, cliffs",
		override = {floor = "pk_fresh_snow", rock = "mountain",
			patches = {{family = "rockfloor", share = 0.06, radius = {2, 4}}}, pools = {},
			obstacles = {share = 0.02, items = "trees:frost"},
			lights = {per100 = 0.3, spacing = 10, items = "theme:cinderfall:lights"}}}
}

local LIGHT = {dark = 0.5, dim = 0.75, normal = 1.0, bright = 1.5}
local DECOR = {sparse = 0.6, normal = 1.0, dense = 1.4}

-- "trees:a,b" and "theme:name:key" stand for rows of our tables
local function rows(v)
	if type(v) ~= "string" then
		return v
	end
	local fams = v:match("^trees:(.+)$")
	if fams then
		local list = {}
		for f in fams:gmatch("[^,]+") do
			list[#list + 1] = f
		end
		return trees(list)
	end
	local list = v:match("^ids:([%d,]+)$")
	if list then
		local out = {}
		for id in list:gmatch("%d+") do
			out[#out + 1] = tonumber(id)
		end
		return ids(out)
	end
	local spec = v:match("^kit:(.+)$")
	if spec then
		return kitRows(spec)
	end
	local th, key = v:match("^theme:([%w_]+):([%w_]+)$")
	if th then
		return rowsOf(th, key)
	end
	error("unknown rows " .. v)
end

local function resolveOverride(o)
	local out = {}
	for k, v in pairs(o or {}) do
		v = copy(v)
		if type(v) == "table" and v.items then
			v.items = rows(v.items)
		end
		if type(v) == "table" and v.scatter then
			v.scatter = rows(v.scatter)
			for _, cl in ipairs(v.clusters or {}) do
				cl.items = rows(cl.items)
			end
		end
		out[k] = v
	end
	return out
end

-- the theme of one plan: the biome's theme, its overrides, the decoration and light multipliers
local function planTheme(biome, decorMult, lightMult)
	local b = BIOMES[biome]
	assert(b, "unknown biome " .. tostring(biome))
	local t = copy(cfg.themes[b.theme])
	local over = resolveOverride(b.override)
	if pair24 and b.pair24 then
		for k, v in pairs(resolveOverride(b.pair24)) do
			over[k] = v
		end
	end
	for k, v in pairs(over) do
		t[k] = v
		if t.dark then
			t.dark[k] = nil
		end
		for _, part in pairs(t.byKind or {}) do
			part[k] = nil
		end
		for _, part in pairs(t.dark and t.dark.byKind or {}) do
			part[k] = nil
		end
	end
	local function scale(part)
		if part.decor then
			part.decor.share = (part.decor.share or 0) * decorMult
			for _, cl in ipairs(part.decor.clusters or {}) do
				cl.per1000 = cl.per1000 * decorMult
			end
		end
		if part.obstacles then
			part.obstacles.share = (part.obstacles.share or 0) * decorMult
		end
		if part.props then
			part.props.per100 = part.props.per100 * decorMult
		end
		if part.lights then
			part.lights.per100 = part.lights.per100 * lightMult
		end
	end
	scale(t)
	if t.dark then
		scale(t.dark)
		for _, part in pairs(t.dark.byKind or {}) do
			scale(part)
		end
	end
	for _, part in pairs(t.byKind or {}) do
		scale(part)
	end
	return t, b
end

-- ------------------------------------------------------------------ JSON
local function json(v)
	local tv = type(v)
	if tv == "nil" then
		return "null"
	elseif tv == "boolean" then
		return v and "true" or "false"
	elseif tv == "number" then
		if v == floor(v) then
			return string.format("%d", v)
		end
		return string.format("%.6g", v)
	elseif tv == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c)
			if c == '"' then
				return '\\"'
			elseif c == "\\" then
				return "\\\\"
			end
			return string.format("\\u%04x", c:byte())
		end) .. '"'
	end
	local n = #v
	local isList = n > 0 or next(v) == nil
	if isList then
		for k in pairs(v) do
			if type(k) ~= "number" then
				isList = false
			end
		end
	end
	local parts = {}
	if isList then
		for k = 1, n do
			parts[k] = json(v[k])
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	local keys = {}
	for k in pairs(v) do
		keys[#keys + 1] = tostring(k)
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local x = v[k]
		if x == nil then
			x = v[tonumber(k)]
		end
		parts[#parts + 1] = json(k) .. ":" .. json(x)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function idOf(v)
	if type(v) == "number" then
		return v
	end
	return dark and ChaosDarkTiles.ids[v] or nil
end

-- the families, border rules and piece ids a theme can use (for the planner's border and id checks)
local function materials(theme)
	local fams = {theme.floor, theme.rock, theme.bossFloor}
	for _, f in ipairs(theme.roomFloors or {}) do
		fams[#fams + 1] = f
	end
	for _, p in ipairs(theme.patches or {}) do
		fams[#fams + 1] = p.family
	end
	for _, p in ipairs(theme.pools or {}) do
		fams[#fams + 1] = p.family
	end
	local famOut, seen = {}, {}
	for _, f in pairs(fams) do
		if f and not seen[f] and cfg.families[f] then
			seen[f] = true
			local d = cfg.families[f]
			local ids = {}
			for _, row in ipairs(d.grounds) do
				ids[#ids + 1] = idOf(row[1])
			end
			famOut[f] = {z = d.z, walk = d.walk ~= false, grounds = ids}
		end
	end
	local borders, sets = {}, {}
	for over in pairs(famOut) do
		for under, set in pairs(cfg.borders[over] or {}) do
			if under == "*" or famOut[under] then
				borders[#borders + 1] = {over = over, under = under, set = set}
				if not sets[set] then
					local ids = {}
					for _, v in pairs(cfg.pieces[set]) do
						ids[#ids + 1] = idOf(v)
					end
					table.sort(ids)
					sets[set] = ids
				end
			end
		end
	end
	table.sort(borders, function(a, b)
		return a.over .. ":" .. a.under < b.over .. ":" .. b.under
	end)
	return famOut, borders, sets
end

-- ------------------------------------------------------------------ catalogue
if mode == "catalogue" then
	local biomes = {}
	for name, b in pairs(BIOMES) do
		local t = planTheme(name, 1, 1)
		local fams = materials(t)
		local list = {}
		for f in pairs(fams) do
			list[#list + 1] = f
		end
		table.sort(list)
		biomes[name] = {kind = b.kind, theme = b.theme, z = b.z, light = b.light, desc = b.desc, needs = b.needs,
			families = list, pair24 = b.pair24 ~= nil}
	end
	print(json({biomes = biomes, light = LIGHT, decoration = DECOR, pair24 = pair24, dark = dark,
		items = {hole = cfg.items.hole, ladder = cfg.items.ladder, portal = cfg.items.portal, chest = riftCfg.chest.itemId},
		exitAction = cfg.aid.exit}))
	return
end

-- ------------------------------------------------------------------ build
assert(mode == "build" and flags, "usage: areaplan_build.lua catalogue|build JOB.lua [pair24] [dark]")
local job = dofile(arg[2])
local def = job.def
local biomeDef = BIOMES[job.biome]
assert(biomeDef, "unknown biome " .. tostring(job.biome))
local theme, b = planTheme(job.biome, DECOR[job.decoration or "normal"] or 1, LIGHT[job.light or biomeDef.light] or 1)
def.kind = b.kind
def.theme = "plan_" .. def.id
cfg.themes[def.theme] = theme

local m = A.generate(cfg, def, opts)
local out = {}
local function put(s)
	out[#out + 1] = s
	if #out >= 2000 then
		io.write(table.concat(out, "\n"), "\n")
		out = {}
	end
end
put(string.format("A %s %s %d %d %d %d %d %d %s", def.id, def.kind, def.origin.x, def.origin.y, def.origin.z, m.w, m.h,
	def.floors or 1, def.name))
for _, f in ipairs(m.floors) do
	put(string.format("F %d %d %d %d", f.z, f.walkable, f.hunt, f.monsters))
end
for _, t in ipairs(m.tiles) do
	local wk = m.walk[t.z] and m.walk[t.z][t.y * 65536 + t.x] and 1 or 0
	put(string.format("T %d %d %d %d %d", t.x, t.y, t.z, wk, t.ground) .. (#t.items > 0 and (" " .. table.concat(t.items, " ")) or ""))
end
for _, l in ipairs(m.links) do
	put(string.format("L %d %d %d %d %d %d %d %d %d", l.hole.x, l.hole.y, l.hole.z, l.ladder.x, l.ladder.y, l.ladder.z,
		l.up.x, l.up.y, l.up.z))
end
put(string.format("R %d %d %d %d %d %d", m.arrival.x, m.arrival.y, m.arrival.z, m.exit.x, m.exit.y, m.exit.z))
for _, q in ipairs(m.rooms or {}) do
	put(string.format("Q %d %d %d %d %d", q.x1, q.y1, q.x2, q.y2, q.z))
end
for _, p in ipairs(A.validate(cfg, m, opts)) do
	put("X " .. p)
end
put("C " .. A.checksum(m))
local allowed = {}
for id in pairs(A.allowedIds(cfg, def, opts)) do
	allowed[#allowed + 1] = id
end
table.sort(allowed)
local fams, borders, sets = materials(theme)
put("J " .. json({allowed = allowed, families = fams, borders = borders, sets = sets, chest = riftCfg.chest.itemId,
	portal = cfg.items.portal, hole = cfg.items.hole, ladder = cfg.items.ladder, exitAction = cfg.aid.exit,
	kind = def.kind, theme = b.theme, walls = theme.wall and cfg.walls[theme.wall] and (function()
		local w = {}
		for kind, rws in pairs(cfg.walls[theme.wall]) do
			w[kind] = {}
			for _, row in ipairs(rws) do
				w[kind][#w[kind] + 1] = row[1]
			end
		end
		return w
	end)() or nil}))
io.write(table.concat(out, "\n"), "\n")
