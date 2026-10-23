-- Waystone Atlas settings (waystone_atlas.lua, waystone_atlas_core.lua). Loaded with
--     ChaosWaystoneAtlasConfig = dofile("data/scripts/chaos/waystone_atlas_config.lua")
-- Every number of the Waystone Atlas: the completion grid and its points, the node graph (the Rift Atlas's shape, its
-- own nodes), the caps of the summed effects, the keystones and the respec prices. Lua 5.1 / LuaJIT and Lua 5.3.
-- Overview: server/README.md "Waystone Atlas".
--
-- Owner 2026-10-23: the waystone maps get their own atlas, as the maps of the well-known action RPG: completing a map at
-- a tier earns a point, the points buy nodes that make your own waystone maps richer. Node ids are stored in the
-- database (chaos_waystone_atlas.nodes): never renumber a node (a removed id drops out at the next load).

-- the four branches share one shape (as atlas_config.lua): u = distance from the centre along the branch's axis,
-- v = sideways; dir turns them into map coordinates. Branch node ids are base + id; a negative link is a core node.
local function branch(base, theme, dir, nodes)
	local out = {}
	for _, n in ipairs(nodes) do
		local u, v = n.at[1], n.at[2]
		local x, y
		if dir == "north" then
			x, y = v, -u
		elseif dir == "east" then
			x, y = u, v
		elseif dir == "south" then
			x, y = -v, u
		else
			x, y = -u, -v
		end
		local links = {}
		for _, l in ipairs(n.links or {}) do
			links[#links + 1] = l < 0 and -l or base + l
		end
		local stats = {}
		for _, s in ipairs(n.stats or {}) do
			local copy = {}
			for k, val in pairs(s) do
				copy[k] = val
			end
			if copy.theme == true then
				copy.theme = theme -- "this branch's maps"
			end
			stats[#stats + 1] = copy
		end
		out[#out + 1] = {id = base + n.id, kind = n.kind or "small", name = n.name, x = x, y = y, links = links,
			stats = stats, glyph = n.glyph, branch = theme, text = n.text, keystone = n.keystone}
	end
	return out
end

local LOW, MID, HIGH, CART = "Low Maps", "Middle Maps", "High Maps", "Cartography"

local cfg = {
	-- the opcode (chaos_constants.lua ChaosOpcodes.waystoneAtlas) and the table (sql/chaos_waystone_atlas.sql)
	opcode = 159,
	table = "chaos_waystone_atlas",
	requestMs = 400,

	-- ------------------------------------------------------------------ the completion grid
	-- First completions only (killing the map's boss during a waystone run; every player inside the map is credited):
	--   map x tier  each of the 12 maps at each tier of its band (4 maps x 5 tiers x 3 bands)   60 cells, `map` each
	--   rare        a map of that tier completed from a Rare waystone (any map)                   15 cells, `rare` each
	-- Total 75 points; the tree costs 108, so it cannot be filled (one keystone at a time).
	points = {map = 1, rare = 1},
	tiers = 15,
	-- the names of the maps (waystone_tiers_config.lua maps, same order: two per base tier)
	mapNames = {"Drowned Grotto", "Ember Cave", "Ashen Plain", "Hollow Cave", "Thornfield", "Gloom Cave", "Mirewood",
		"Underhall", "Sunscar Dunes", "Rimefrost", "Bonecrypt Cave", "Duskmoor"},
	-- the theme of each band (waystone_tiers_config.lua bands, same order): stats of a branch count in its band's maps
	bandThemes = {LOW, MID, HIGH},

	-- ------------------------------------------------------------------ the tree
	costs = {start = 0, small = 1, notable = 2, keystone = 3},
	keystoneMax = 1,
	startId = 1,
	respec = {gold = 250000, orbItem = 29856, orbCount = 1, orbName = "Orb of Upheaval", resetShare = 0.8},

	-- the summed effects of every allocated node, capped (keystones on top). Percent, except bossExtra (percent chance
	-- of one more waystone from the boss).
	caps = {quantity = 20, rarity = 25, experience = 20, waystone = 30, modReward = 25, tierUp = 15, rarer = 35,
		bossExtra = 50},

	statText = {
		quantity = "+%s%% item quantity",
		rarity = "+%s%% item rarity",
		experience = "+%s%% experience",
		waystone = "+%s%% chance of an extra waystone",
		modReward = "+%s%% modifier reward bonuses",
		tierUp = "+%s%% chance a dropped waystone is a tier higher",
		rarer = "+%s%% chance a Normal waystone drop comes Magic or Rare",
		bossExtra = "+%s%% chance the boss drops one more next-tier waystone"
	},

	-- key: the client's art set (the Rift Atlas's icon sheets), theme: the maps the branch's own stats count in
	branches = {
		{key = "abyss", name = LOW, theme = LOW, dir = "north", color = "#7fc86a"},
		{key = "hall", name = MID, theme = MID, dir = "east", color = "#e8b84a"},
		{key = "crypt", name = HIGH, theme = HIGH, dir = "south", color = "#e05a3a"},
		{key = "sanctum", name = CART, theme = CART, dir = "west", color = "#9a6ae8"}
	},

	-- keystones (the map opener's; waystone_atlas_core.lua WC.resolve)
	--   pureQuantity / pureExperience  added in a map opened with a Normal waystone (no modifiers)
	--   modRewardMult                  the modifiers' reward bonuses x this
	--   bossExtraFlat                  the boss drops this many more next-tier waystones
	--   dropLoss                       percent chance a waystone dropped by another monster is lost
	--   tierStep                       every dropped waystone this many tiers higher (XV stays XV)
	--   noBossDrop                     the boss's next-tier waystone is lost
	--   neverNormal                    dropped waystones always come Magic or Rare
	--   quantity                       item quantity (may be negative), outside the cap
	keystones = {
		pure_stone = {pureQuantity = 40, pureExperience = 40, modRewardMult = 0.5},
		hunters_vow = {bossExtraFlat = 2, dropLoss = 50},
		ascendant_path = {tierStep = 1, noBossDrop = true},
		rare_pursuit = {neverNormal = true, quantity = -20}
	}
}

-- ------------------------------------------------------------------ the core (ids 1-17)
cfg.nodes = {
	{id = 1, kind = "start", name = "Cartographer's Table", x = 0, y = 0, links = {}, stats = {}, glyph = "start",
		text = "Where every map begins. Kill a map's boss in a waystone run to earn points."},
	-- north spoke (toward the Low Maps)
	{id = 2, name = "Steady Hand", x = 0, y = -90, links = {1}, stats = {{stat = "quantity", value = 2}}, glyph = "rolls"},
	{id = 3, name = "Steady Hand", x = 0, y = -170, links = {2}, stats = {{stat = "quantity", value = 2}}, glyph = "rolls"},
	{id = 4, name = "Charted Reward", x = 0, y = -250, links = {3}, stats = {{stat = "modReward", value = 3}}, glyph = "reward"},
	-- east spoke (toward the Middle Maps)
	{id = 5, name = "Charted Reward", x = 90, y = 0, links = {1, 2}, stats = {{stat = "modReward", value = 3}}, glyph = "reward"},
	{id = 6, name = "Keen Eye", x = 170, y = 0, links = {5}, stats = {{stat = "rarity", value = 3}}, glyph = "orb"},
	{id = 7, name = "Charted Reward", x = 250, y = 0, links = {6}, stats = {{stat = "modReward", value = 3}}, glyph = "reward"},
	-- south spoke (toward the High Maps)
	{id = 8, name = "Waystone Sense", x = 0, y = 90, links = {1, 5}, stats = {{stat = "waystone", value = 3}}, glyph = "key"},
	{id = 9, name = "Waystone Sense", x = 0, y = 170, links = {8}, stats = {{stat = "waystone", value = 3}}, glyph = "key"},
	{id = 10, name = "Rising Stone", x = 0, y = 250, links = {9}, stats = {{stat = "tierUp", value = 2}}, glyph = "upgrade"},
	-- west spoke (toward Cartography)
	{id = 11, name = "Seasoned Explorer", x = -90, y = 0, links = {1, 8, 2}, stats = {{stat = "experience", value = 2}}, glyph = "elite"},
	{id = 12, name = "Seasoned Explorer", x = -170, y = 0, links = {11}, stats = {{stat = "experience", value = 2}}, glyph = "elite"},
	{id = 13, name = "Polished Stone", x = -250, y = 0, links = {12}, stats = {{stat = "rarer", value = 4}}, glyph = "fragment"},
	-- notables between the spokes
	{id = 14, kind = "notable", name = "Prospector", x = 125, y = -125, links = {3, 6}, glyph = "rolls",
		stats = {{stat = "quantity", value = 5}, {stat = "rarity", value = 5}}},
	{id = 15, kind = "notable", name = "Stonewright", x = 125, y = 125, links = {6, 9}, glyph = "key",
		stats = {{stat = "waystone", value = 6}, {stat = "tierUp", value = 3}}},
	{id = 16, kind = "notable", name = "Veteran's Path", x = -125, y = 125, links = {9, 12}, glyph = "elite",
		stats = {{stat = "experience", value = 5}, {stat = "rarer", value = 5}}},
	{id = 17, kind = "notable", name = "Cartographer's Eye", x = -125, y = -125, links = {12, 3}, glyph = "reward",
		stats = {{stat = "modReward", value = 6}, {stat = "quantity", value = 3}}}
}

local function shape(s)
	return {
		{id = 1, at = {330, 0}, links = {-s.gate}, name = s.n1, stats = s.s1, glyph = s.g1},
		{id = 2, kind = "notable", at = {410, 0}, links = {1}, name = s.n2, stats = s.s2, glyph = "theme"},
		{id = 3, at = {475, -80}, links = {2}, name = s.n3, stats = s.s3, glyph = s.g3},
		{id = 4, at = {545, -140}, links = {3}, name = s.n3, stats = s.s3, glyph = s.g3},
		{id = 5, kind = "notable", at = {620, -180}, links = {4}, name = s.n5, stats = s.s5, glyph = s.g5},
		{id = 6, at = {690, -130}, links = {5}, name = s.n6, stats = s.s6, glyph = s.g6},
		{id = 7, at = {475, 80}, links = {2}, name = s.n7, stats = s.s7, glyph = s.g7},
		{id = 8, at = {545, 140}, links = {7}, name = s.n7, stats = s.s7, glyph = s.g7},
		{id = 9, kind = "notable", at = {620, 180}, links = {8}, name = s.n9, stats = s.s9, glyph = s.g9},
		{id = 10, at = {690, 130}, links = {9}, name = s.n10, stats = s.s10, glyph = s.g10},
		{id = 11, at = {500, 0}, links = {2}, name = s.n11, stats = s.s11, glyph = s.g11},
		{id = 12, at = {590, 0}, links = {11}, name = s.n12, stats = s.s12, glyph = s.g12},
		{id = 13, kind = "notable", at = {680, 0}, links = {12}, name = s.n13, stats = s.s13, glyph = s.g13},
		{id = 14, at = {780, 0}, links = {6, 10, 13}, name = s.n14, stats = s.s14, glyph = s.g14},
		{id = 15, at = {860, 0}, links = {14}, name = s.n15, stats = s.s15, glyph = s.g15},
		{id = 16, kind = "keystone", at = {965, 0}, links = {15}, name = s.n16, stats = {}, glyph = s.g16, keystone = s.ks,
			text = s.t16}
	}
end

local function add(list)
	for _, n in ipairs(list) do
		cfg.nodes[#cfg.nodes + 1] = n
	end
end

-- Low Maps (north): item quantity
add(branch(100, LOW, "north", shape({
	gate = 4,
	n1 = "Lowland Path", s1 = {{stat = "quantity", value = 4, theme = true}}, g1 = "rolls",
	n2 = "Lowland Mastery", s2 = {{stat = "quantity", value = 6, theme = true}, {stat = "experience", value = 6, theme = true}},
	n3 = "Lowland Spoils", s3 = {{stat = "rarity", value = 5, theme = true}}, g3 = "orb",
	n5 = "Bountiful Lowlands", s5 = {{stat = "quantity", value = 12, theme = true}}, g5 = "rolls",
	n6 = "Charted Reward", s6 = {{stat = "modReward", value = 3}}, g6 = "reward",
	n7 = "Waystone Sense", s7 = {{stat = "waystone", value = 3}}, g7 = "key",
	n9 = "Lowland Hoard", s9 = {{stat = "bossExtra", value = 20, theme = true}, {stat = "waystone", value = 5, theme = true}}, g9 = "coffer",
	n10 = "Steady Hand", s10 = {{stat = "quantity", value = 2}}, g10 = "rolls",
	n11 = "Lowland Lore", s11 = {{stat = "experience", value = 4, theme = true}}, g11 = "elite",
	n12 = "Seasoned Explorer", s12 = {{stat = "experience", value = 2}}, g12 = "elite",
	n13 = "Climber's Resolve", s13 = {{stat = "tierUp", value = 8, theme = true}}, g13 = "upgrade",
	n14 = "Keen Eye", s14 = {{stat = "rarity", value = 3}}, g14 = "orb",
	n15 = "Steady Hand", s15 = {{stat = "quantity", value = 2}}, g15 = "rolls",
	n16 = "Pure Stone", g16 = "ks_ember", ks = "pure_stone",
	t16 = "Maps you open with a Normal waystone have +40% item quantity and experience. Modifier reward bonuses are halved."
})))

-- Middle Maps (east): experience
add(branch(200, MID, "east", shape({
	gate = 7,
	n1 = "Midland Path", s1 = {{stat = "experience", value = 4, theme = true}}, g1 = "elite",
	n2 = "Midland Mastery", s2 = {{stat = "experience", value = 6, theme = true}, {stat = "rarity", value = 6, theme = true}},
	n3 = "Midland Lore", s3 = {{stat = "experience", value = 3, theme = true}}, g3 = "elite",
	n5 = "Tempered Hunter", s5 = {{stat = "experience", value = 10, theme = true}}, g5 = "elite",
	n6 = "Charted Reward", s6 = {{stat = "modReward", value = 3}}, g6 = "reward",
	n7 = "Keen Eye", s7 = {{stat = "rarity", value = 3}}, g7 = "orb",
	n9 = "Midland Hoard", s9 = {{stat = "bossExtra", value = 20, theme = true}, {stat = "quantity", value = 5, theme = true}}, g9 = "coffer",
	n10 = "Waystone Sense", s10 = {{stat = "waystone", value = 3}}, g10 = "key",
	n11 = "Midland Spoils", s11 = {{stat = "quantity", value = 4, theme = true}}, g11 = "rolls",
	n12 = "Seasoned Explorer", s12 = {{stat = "experience", value = 2}}, g12 = "elite",
	n13 = "Burdened Map", s13 = {{stat = "modReward", value = 8, theme = true}, {stat = "rarer", value = 5}}, g13 = "reward",
	n14 = "Steady Hand", s14 = {{stat = "quantity", value = 2}}, g14 = "rolls",
	n15 = "Seasoned Explorer", s15 = {{stat = "experience", value = 2}}, g15 = "elite",
	n16 = "Hunter's Vow", g16 = "ks_crown", ks = "hunters_vow",
	t16 = "Bosses of your maps drop two more next-tier waystones, but half the waystones other monsters drop are lost."
})))

-- High Maps (south): rarity and the boss
add(branch(300, HIGH, "south", shape({
	gate = 10,
	n1 = "Highland Path", s1 = {{stat = "rarity", value = 5, theme = true}}, g1 = "orb",
	n2 = "Highland Mastery", s2 = {{stat = "rarity", value = 8, theme = true}, {stat = "quantity", value = 4, theme = true}},
	n3 = "Highland Spoils", s3 = {{stat = "rarity", value = 4, theme = true}}, g3 = "orb",
	n5 = "Summit Hoard", s5 = {{stat = "bossExtra", value = 25, theme = true}}, g5 = "coffer",
	n6 = "Rising Stone", s6 = {{stat = "tierUp", value = 2}}, g6 = "upgrade",
	n7 = "Waystone Sense", s7 = {{stat = "waystone", value = 3}}, g7 = "key",
	n9 = "Peak Lore", s9 = {{stat = "experience", value = 6, theme = true}, {stat = "waystone", value = 6, theme = true}}, g9 = "elite",
	n10 = "Keen Eye", s10 = {{stat = "rarity", value = 3}}, g10 = "orb",
	n11 = "Highland Wealth", s11 = {{stat = "quantity", value = 3, theme = true}}, g11 = "rolls",
	n12 = "Rising Stone", s12 = {{stat = "tierUp", value = 2}}, g12 = "upgrade",
	n13 = "Summit Path", s13 = {{stat = "tierUp", value = 6}}, g13 = "upgrade",
	n14 = "Waystone Sense", s14 = {{stat = "waystone", value = 3}}, g14 = "key",
	n15 = "Keen Eye", s15 = {{stat = "rarity", value = 3}}, g15 = "orb",
	n16 = "Ascendant Path", g16 = "ks_ascent", ks = "ascendant_path",
	t16 = "Every waystone that drops in your maps is one tier higher (Tier XV stays XV), but the boss's next-tier waystone is lost."
})))

-- Cartography (west): the waystones themselves
add(branch(400, CART, "west", shape({
	gate = 13,
	n1 = "Cartographer's Gate", s1 = {{stat = "rarer", value = 4}}, g1 = "fragment",
	n2 = "Cartography", s2 = {{stat = "rarer", value = 8}, {stat = "modReward", value = 5}},
	n3 = "Waystone Sense", s3 = {{stat = "waystone", value = 3}}, g3 = "key",
	n5 = "Stonecutter", s5 = {{stat = "waystone", value = 10}}, g5 = "key",
	n6 = "Polished Stone", s6 = {{stat = "rarer", value = 4}}, g6 = "fragment",
	n7 = "Charted Reward", s7 = {{stat = "modReward", value = 3}}, g7 = "reward",
	n9 = "Map Lore", s9 = {{stat = "modReward", value = 8}, {stat = "experience", value = 3}}, g9 = "reward",
	n10 = "Rising Stone", s10 = {{stat = "tierUp", value = 2}}, g10 = "upgrade",
	n11 = "Polished Stone", s11 = {{stat = "rarer", value = 4}}, g11 = "fragment",
	n12 = "Waystone Sense", s12 = {{stat = "waystone", value = 3}}, g12 = "key",
	n13 = "Gilded Stone", s13 = {{stat = "rarer", value = 10}, {stat = "rarity", value = 3}}, g13 = "fragment",
	n14 = "Steady Hand", s14 = {{stat = "quantity", value = 2}}, g14 = "rolls",
	n15 = "Charted Reward", s15 = {{stat = "modReward", value = 3}}, g15 = "reward",
	n16 = "Rare Pursuit", g16 = "ks_hourglass", ks = "rare_pursuit",
	t16 = "Waystones that drop in your maps are always Magic or Rare, but your maps have 20% less item quantity."
})))

return cfg
