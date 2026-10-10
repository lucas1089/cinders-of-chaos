-- Rift Atlas settings (atlas.lua, atlas_core.lua). Loaded with
--     ChaosAtlasConfig = dofile("data/scripts/chaos/atlas_config.lua")
-- Every number of the Rift Atlas lives here: the completion grid and its points, the node graph (positions, links,
-- costs, effects), the caps of the summed effects, the keystone limit and the respec prices.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Overview: server/README.md "Rift Atlas".
--
-- Node ids are stored in the database (chaos_rift_atlas.nodes): never renumber a node. A removed id simply drops out
-- of an allocation at the next load (the point comes back for free, atlas_core.lua A.sanitize).

-- the four theme branches share one shape. Local coordinates: u = distance from the centre along the branch's axis,
-- v = sideways. dir turns them into map coordinates (x right, y down): north (0, -1), east (1, 0), south (0, 1),
-- west (-1, 0). Every branch node has the id base + id below; a link is a local id, or minus a core node's id.
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
			links[#links + 1] = l < 0 and -l or base + l -- negative: a core node
		end
		local stats = {}
		for _, s in ipairs(n.stats or {}) do
			local copy = {}
			for k, val in pairs(s) do
				copy[k] = val
			end
			if copy.theme == true then
				copy.theme = theme -- "this branch's theme"
			end
			stats[#stats + 1] = copy
		end
		out[#out + 1] = {id = base + n.id, kind = n.kind or "small", name = n.name, x = x, y = y, links = links,
			stats = stats, glyph = n.glyph, branch = theme, text = n.text, keystone = n.keystone}
	end
	return out
end

local T_ABYSS, T_HALL, T_CRYPT, T_SANCTUM = "Abyssal Rift", "Obsidian Hall", "Ashen Crypt", "Forsaken Sanctum"

local cfg = {
	-- the opcode (chaos_constants.lua ChaosOpcodes.riftAtlas) and the table (Chaos.tables.riftAtlas, sql/chaos_rift_atlas.sql)
	opcode = 210,
	table = "chaos_rift_atlas",
	requestMs = 400, -- rate limit of the window's requests (ratelimit.lua)

	-- ------------------------------------------------------------------ the completion grid
	-- Points come only from FIRST completions, so the grid is finite and visible:
	--   theme x tier  sealing a rift of that theme and tier (every finisher)               4 x 15 cells, `cell` each
	--   flawless      sealing a rift of that tier (any theme) without a death               15 cells, `flawless` each
	--   swift         sealing a rift of that tier within swiftShare of the base time limit 15 cells, `swift` each
	--   omen          killing that Omen guardian                                            3 cells, `omen` each
	-- The themes and the omen kinds are those of rift_config.lua (themes, omen.kinds), in that order.
	-- Total: 60 + 15 + 15 + 3 x 2 = 96 points.
	points = {cell = 1, flawless = 1, swift = 1, omen = 2},
	swiftShare = 0.5, -- of rift_config.lua timeLimit (600 s: sealed in 5:00 or less; the run's own limit does not matter)
	tiers = 15, -- columns of the grid (rift_config.lua maxTier)

	-- ------------------------------------------------------------------ the tree
	costs = {start = 0, small = 1, notable = 2, keystone = 3}, -- points per node of each kind
	keystoneMax = 1, -- keystones held at once (each is a trade-off; they do not stack)
	startId = 1,

	-- respec: refunding one node costs either gold (carried first, then the bank) or orbs; allocating is free.
	-- A full reset costs the per-node price x the nodes held x resetShare. A sink, sized against the rift chest:
	-- 250k gold is about a tier-5 chest (10000 x 5^2), one Orb of Upheaval is the chest's own orb.
	respec = {gold = 250000, orbItem = 29856, orbCount = 1, orbName = "Orb of Upheaval", resetShare = 0.8},

	-- the summed effects of every allocated node (all themes and the run's theme together) are capped here, so a full
	-- atlas stays inside the rift economy (server/README.md "Rift Atlas", the totals). Keystones are applied on top.
	caps = {density = 25, elite = 40, time = 25, modReward = 20, goldMult = 25, keyChance = 15, keyUpgrade = 25,
		fragments = 25, chaos = 2, divine = 1.5, rolls = 1.5, goblin = 40, coffer = 40, themeWeight = 100, lives = 2},

	-- how a stat reads in a tooltip (value first; fractions keep two decimals). A stat with `theme` adds " in <theme>",
	-- one with `minTier` adds " (tier N+)".
	statText = {
		density = "+%s%% monster packs",
		elite = "+%s%% magic, rare and legendary monsters",
		time = "+%s%% rift time",
		modReward = "+%s%% modifier reward bonuses",
		goldMult = "+%s%% chest gold",
		keyChance = "+%s%% chance of the next key",
		keyUpgrade = "+%s%% chance the next key is a tier higher",
		fragments = "+%s%% Omen Fragments",
		chaos = "+%s Orbs of Upheaval per chest",
		divine = "+%s Orbs of Fate per chest",
		rolls = "+%s item rolls per chest",
		goblin = "+%s%% chance of the Treasure Goblin",
		coffer = "+%s%% chance of a Sealed Coffer",
		themeWeight = "+%s%% chance a rift opens as this theme",
		lives = "+%s shared lives",
		betterMods = "Keys from sealed rifts roll more modifiers"
	},

	-- the four branches: key, theme (rift_config.lua themes[].name), direction, colour of the client's art
	branches = {
		{key = "abyss", name = "Abyssal Rift", theme = T_ABYSS, dir = "north", color = "#9a6ae8"},
		{key = "hall", name = "Obsidian Hall", theme = T_HALL, dir = "east", color = "#e8803a"},
		{key = "crypt", name = "Ashen Crypt", theme = T_CRYPT, dir = "south", color = "#c8b890"},
		{key = "sanctum", name = "Forsaken Sanctum", theme = T_SANCTUM, dir = "west", color = "#7fc86a"}
	},

	-- keystones (atlas_core.lua A.resolve): the run takes them from the player who used the key
	--   oneLife       the run has exactly one shared life
	--   rewardMult    every finisher's chest x (1 + value / 100): gold, orbs, item rolls
	--   guardianMult  guardian health and damage x value (as Dread Guardian)
	--   orbsMult      Orbs of Upheaval and Fate of the chest x value
	--   keyChanceMult the next-key chance x value
	--   keyAscend     every next key that drops is one tier higher (up to the top tier)
	--   timeMult      the time limit x value
	--   density       (as a stat, but outside the cap)
	keystones = {
		lone_ember = {oneLife = true, rewardMult = 60},
		obsidian_crown = {guardianMult = 2, orbsMult = 2},
		ashen_ascent = {keyChanceMult = 0.5, keyAscend = true},
		fleeting_sanctum = {timeMult = 0.65, density = 40, rewardMult = 30}
	}
}

-- ------------------------------------------------------------------ the core (ids 1-17)
-- the start, four spokes of three small nodes toward the branches, and four notables between the spokes
cfg.nodes = {
	{id = 1, kind = "start", name = "Heart of the Atlas", x = 0, y = 0, links = {}, stats = {}, glyph = "start",
		text = "Where every rift begins. Seal rifts to earn points."},
	-- north spoke (toward the Abyssal Rift)
	{id = 2, name = "Widening Tear", x = 0, y = -90, links = {1}, stats = {{stat = "density", value = 3}}, glyph = "density"},
	{id = 3, name = "Widening Tear", x = 0, y = -170, links = {2}, stats = {{stat = "density", value = 3}}, glyph = "density"},
	{id = 4, name = "Charted Strain", x = 0, y = -250, links = {3}, stats = {{stat = "modReward", value = 2}}, glyph = "reward"},
	-- east spoke (toward the Obsidian Hall)
	{id = 5, name = "Charted Strain", x = 90, y = 0, links = {1, 2}, stats = {{stat = "modReward", value = 2}}, glyph = "reward"},
	{id = 6, name = "Gilded Seal", x = 170, y = 0, links = {5}, stats = {{stat = "goldMult", value = 4}}, glyph = "gold"},
	{id = 7, name = "Charted Strain", x = 250, y = 0, links = {6}, stats = {{stat = "modReward", value = 2}}, glyph = "reward"},
	-- south spoke (toward the Ashen Crypt)
	{id = 8, name = "Keyfinder", x = 0, y = 90, links = {1, 5}, stats = {{stat = "keyChance", value = 2}}, glyph = "key"},
	{id = 9, name = "Keyfinder", x = 0, y = 170, links = {8}, stats = {{stat = "keyChance", value = 2}}, glyph = "key"},
	{id = 10, name = "Rising Key", x = 0, y = 250, links = {9}, stats = {{stat = "keyUpgrade", value = 3}}, glyph = "upgrade"},
	-- west spoke (toward the Forsaken Sanctum)
	{id = 11, name = "Lingering Veil", x = -90, y = 0, links = {1, 8, 2}, stats = {{stat = "time", value = 3}}, glyph = "time"},
	{id = 12, name = "Lingering Veil", x = -170, y = 0, links = {11}, stats = {{stat = "time", value = 3}}, glyph = "time"},
	{id = 13, name = "Omen Sense", x = -250, y = 0, links = {12}, stats = {{stat = "fragments", value = 5}}, glyph = "fragment"},
	-- notables between the spokes
	{id = 14, kind = "notable", name = "Second Wind", x = 125, y = -125, links = {3, 6}, glyph = "life",
		stats = {{stat = "lives", value = 1, minTier = 8}}},
	{id = 15, kind = "notable", name = "Keywright", x = 125, y = 125, links = {6, 9}, glyph = "key",
		stats = {{stat = "keyChance", value = 4}, {stat = "keyUpgrade", value = 5}}},
	{id = 16, kind = "notable", name = "Unbroken Line", x = -125, y = 125, links = {9, 12}, glyph = "life",
		stats = {{stat = "lives", value = 1, minTier = 12}, {stat = "time", value = 4}}},
	{id = 17, kind = "notable", name = "Cartographer's Eye", x = -125, y = -125, links = {12, 3}, glyph = "reward",
		stats = {{stat = "modReward", value = 4}, {stat = "density", value = 4}}}
}

-- ------------------------------------------------------------------ the branches (16 nodes each)
-- shape (u, v): gate 1 and the attunement 2 on the axis, a left arm 3-6, a right arm 7-10, the trunk 11-13, the join
-- 14 (linked from both arms and the trunk), 15 and the keystone 16 at the far end
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

-- Abyssal Rift (north): packs and elites
add(branch(100, T_ABYSS, "north", shape({
	gate = 4,
	n1 = "Abyssal Gate", s1 = {{stat = "density", value = 4, theme = true}}, g1 = "density",
	n2 = "Abyssal Attunement", s2 = {{stat = "themeWeight", value = 60, theme = true}},
	n3 = "Gazing Deep", s3 = {{stat = "elite", value = 8, theme = true}}, g3 = "elite",
	n5 = "Teeming Abyss", s5 = {{stat = "density", value = 15, theme = true}}, g5 = "density",
	n6 = "Charted Strain", s6 = {{stat = "modReward", value = 2}}, g6 = "reward",
	n7 = "Omen Sense", s7 = {{stat = "fragments", value = 5}}, g7 = "fragment",
	n9 = "Eye of the Abyss", s9 = {{stat = "elite", value = 15, theme = true}, {stat = "rolls", value = 0.5, theme = true}}, g9 = "elite",
	n10 = "Widening Tear", s10 = {{stat = "density", value = 3}}, g10 = "density",
	n11 = "Abyssal Pull", s11 = {{stat = "density", value = 3, theme = true}}, g11 = "density",
	n12 = "Lingering Dark", s12 = {{stat = "time", value = 4, theme = true}}, g12 = "time",
	n13 = "Endless Tide", s13 = {{stat = "density", value = 8}}, g13 = "density",
	n14 = "Keyfinder", s14 = {{stat = "keyChance", value = 2}}, g14 = "key",
	n15 = "Charted Strain", s15 = {{stat = "modReward", value = 2}}, g15 = "reward",
	n16 = "Lone Ember", g16 = "ks_ember", ks = "lone_ember",
	t16 = "Your rifts have one shared life. Every finisher's chest +60% (gold, orbs, item rolls)."
})))

-- Obsidian Hall (east): gold and orbs
add(branch(200, T_HALL, "east", shape({
	gate = 7,
	n1 = "Obsidian Gate", s1 = {{stat = "goldMult", value = 5, theme = true}}, g1 = "gold",
	n2 = "Obsidian Attunement", s2 = {{stat = "themeWeight", value = 60, theme = true}},
	n3 = "Molten Vein", s3 = {{stat = "chaos", value = 0.25, theme = true}}, g3 = "orb",
	n5 = "Guardian's Hoard", s5 = {{stat = "chaos", value = 1, theme = true}, {stat = "divine", value = 1, theme = true}}, g5 = "orb",
	n6 = "Charted Strain", s6 = {{stat = "modReward", value = 2}}, g6 = "reward",
	n7 = "Gilded Seal", s7 = {{stat = "goldMult", value = 4}}, g7 = "gold",
	n9 = "Molten Coffers", s9 = {{stat = "goldMult", value = 10}, {stat = "rolls", value = 0.5}}, g9 = "gold",
	n10 = "Spoils of the Hall", s10 = {{stat = "rolls", value = 0.25}}, g10 = "rolls",
	n11 = "Glimmering Orb", s11 = {{stat = "chaos", value = 0.25}}, g11 = "orb",
	n12 = "Charted Strain", s12 = {{stat = "modReward", value = 2}}, g12 = "reward",
	n13 = "Forged in Obsidian", s13 = {{stat = "modReward", value = 6, theme = true}, {stat = "divine", value = 0.5}}, g13 = "reward",
	n14 = "Gilded Seal", s14 = {{stat = "goldMult", value = 4}}, g14 = "gold",
	n15 = "Spoils of the Hall", s15 = {{stat = "rolls", value = 0.25}}, g15 = "rolls",
	n16 = "Obsidian Crown", g16 = "ks_crown", ks = "obsidian_crown",
	t16 = "Guardians of your rifts have +100% health and damage. Orbs of Upheaval and Fate in every finisher's chest x2."
})))

-- Ashen Crypt (south): keys
add(branch(300, T_CRYPT, "south", shape({
	gate = 10,
	n1 = "Ashen Gate", s1 = {{stat = "keyChance", value = 3, theme = true}}, g1 = "key",
	n2 = "Ashen Attunement", s2 = {{stat = "themeWeight", value = 60, theme = true}},
	n3 = "Smouldering Key", s3 = {{stat = "keyUpgrade", value = 4, theme = true}}, g3 = "upgrade",
	n5 = "Rekindled Key", s5 = {{stat = "keyUpgrade", value = 15, theme = true}}, g5 = "upgrade",
	n6 = "Keyfinder", s6 = {{stat = "keyChance", value = 2}}, g6 = "key",
	n7 = "Lingering Veil", s7 = {{stat = "time", value = 3}}, g7 = "time",
	n9 = "Crypt Warden's Mark", s9 = {{stat = "lives", value = 1, theme = true}, {stat = "time", value = 8, theme = true}}, g9 = "life",
	n10 = "Keyfinder", s10 = {{stat = "keyChance", value = 2}}, g10 = "key",
	n11 = "Keyfinder", s11 = {{stat = "keyChance", value = 2}}, g11 = "key",
	n12 = "Rising Key", s12 = {{stat = "keyUpgrade", value = 3}}, g12 = "upgrade",
	n13 = "Ember Ward", s13 = {{stat = "betterMods", value = 1}}, g13 = "key",
	n14 = "Omen Sense", s14 = {{stat = "fragments", value = 5}}, g14 = "fragment",
	n15 = "Rising Key", s15 = {{stat = "keyUpgrade", value = 3}}, g15 = "upgrade",
	n16 = "Ashen Ascent", g16 = "ks_ascent", ks = "ashen_ascent",
	t16 = "The next-key chance of your rifts is halved, but every key that drops is one tier higher."
})))

-- Forsaken Sanctum (west): time, the Treasure Goblin and the Sealed Coffer
add(branch(400, T_SANCTUM, "west", shape({
	gate = 13,
	n1 = "Sanctum Gate", s1 = {{stat = "time", value = 5, theme = true}}, g1 = "time",
	n2 = "Sanctum Attunement", s2 = {{stat = "themeWeight", value = 60, theme = true}},
	n3 = "Glint of Gold", s3 = {{stat = "goblin", value = 5, theme = true}}, g3 = "goblin",
	n5 = "Gilded Pilgrims", s5 = {{stat = "goblin", value = 20, theme = true}}, g5 = "goblin",
	n6 = "Lingering Veil", s6 = {{stat = "time", value = 3}}, g6 = "time",
	n7 = "Hidden Reliquary", s7 = {{stat = "coffer", value = 5, theme = true}}, g7 = "coffer",
	n9 = "Reliquary", s9 = {{stat = "coffer", value = 20, theme = true}}, g9 = "coffer",
	n10 = "Omen Sense", s10 = {{stat = "fragments", value = 5}}, g10 = "fragment",
	n11 = "Lingering Veil", s11 = {{stat = "time", value = 3}}, g11 = "time",
	n12 = "Widening Tear", s12 = {{stat = "density", value = 3}}, g12 = "density",
	n13 = "Sanctified Hours", s13 = {{stat = "time", value = 6}, {stat = "modReward", value = 3}}, g13 = "time",
	n14 = "Glint of Gold", s14 = {{stat = "goblin", value = 3}}, g14 = "goblin",
	n15 = "Hidden Reliquary", s15 = {{stat = "coffer", value = 3}}, g15 = "coffer",
	n16 = "Fleeting Sanctum", g16 = "ks_hourglass", ks = "fleeting_sanctum",
	t16 = "Your rifts close 35% sooner, but hold +40% monster packs and every finisher's chest is +30%."
})))

return cfg
