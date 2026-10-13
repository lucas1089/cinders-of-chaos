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
			obstacles = {share = 0.02, items = "trees:swamp,dead"}},
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
	abyss = {kind = "cave", theme = "rift_abyss", z = 11, light = "dark",
		desc = "eldritch waste or cave of rift floor"},
	sanctum = {kind = "cave", theme = "rift_sanctum", z = 9, light = "dim",
		desc = "blighted cave with mud and cracks (dark set: wet and mossy rock, moss, glowcaps)"},
	forest = {kind = "waste", theme = "cinderfall", z = 7, light = "normal", needs = "pack items (install step packitems)",
		desc = "forest glade: dense grass with lush and meadow grass and loam, trees, stones, cliffs",
		override = {floor = "pk_dense_grass", rock = "mountain",
			patches = {{family = "pk_lush_grass", share = 0.10, radius = {2, 4}}, {family = "pk_meadow_grass", share = 0.07,
				radius = {2, 4}}, {family = "pk_loam", share = 0.04, radius = {2, 3}}},
			pools = {}, obstacles = {share = 0.05, items = "trees:broadleaf,conifer,fruit"},
			lights = {per100 = 0.3, spacing = 10, items = "theme:cinderfall:lights"}}},
	ice = {kind = "waste", theme = "cinderfall", z = 7, light = "normal", needs = "pack items (install step packitems)",
		desc = "snow field: fresh snow with grey rock patches, frost trees and stones, cliffs",
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
	kind = def.kind, theme = b.theme}))
io.write(table.concat(out, "\n"), "\n")
