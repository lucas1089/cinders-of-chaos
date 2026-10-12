-- Dark tile painter: dresses a runtime-built room with the dark tile set (data/lib/chaos_dark_tiles.lua) the way the
-- real map is dressed: a main ground with its accent variants, patches of a second ground with border pieces on every
-- tile around them, loose decoration scattered over the floor, and solid pieces (rocks, crystals, pools, torches)
-- standing against the walls.
--
-- ChaosDarkPaint.plan(tiles, style, rng, opts) is pure (tested by tests/dark_paint_test.lua):
--   tiles  list of {x, y[, z]} floor positions
--   style  a table like ChaosDarkPaint.STYLES.abyss (or its name)
--   rng    function(a, b) -> integer in [a, b] (math.random)
--   opts   {walls = {["x,y"] = true}, reserved = {{x, y}, ...}, keepFree = 1}
--          walls: blocked tiles next to the floor (solid decoration only stands next to them);
--          reserved: tiles that stay plain (arrival, boss spawn, portals, doors, fixtures); nothing solid is put
--          within keepFree tiles of them
-- returns {["x,y"] = {x, y, ground = name, borders = {name, ...}, decor = name or nil}} (names, not ids)
--
-- ChaosDarkPaint.apply(plan, z) creates the items (server ids from ChaosDarkTiles); old dark borders and dark
-- decoration on those tiles are removed first, so a room can be repainted. Returns the number of items created.
-- ChaosDarkPaint.ready(style) is true when every item the style names is installed.
-- ChaosDarkPaint.isDark(id) is true for any server id of the set (cleaning code keeps those).

if not ChaosDarkTiles then
	dofile("data/lib/chaos_dark_tiles.lua")
end

ChaosDarkPaint = ChaosDarkPaint or {}
local P = ChaosDarkPaint
local D = ChaosDarkTiles

-- grounds that look the same at their edges belong to one family (no border between them)
P.FAMILY = {
	obsidian_floor = "obsidian_floor", magma_floor = "obsidian_floor", cursed_pool = "obsidian_floor",
	ash_soil = "ash_soil", bone_earth = "ash_soil",
	wet_rock = "wet_rock", mossy_rock = "wet_rock",
	dark_moss = "dark_moss",
	ruined_floor = "ruined_floor"
}
-- families with border pieces (drawn over the neighbouring tiles of other families)
P.BORDERED = {obsidian_floor = true, ash_soil = true, wet_rock = true, dark_moss = true}

-- base: weighted walkable grounds of the main family; patches: blobs of a bordered ground of another family;
-- decor: walkable pieces, `decorShare` of the floor tiles; edge: solid pieces next to walls, `edgeShare` of those
-- tiles (a ground name there, like cursed_pool, replaces the ground)
P.STYLES = {
	abyss = {
		base = {{"obsidian_floor", 90}, {"magma_floor", 10}},
		patches = {ground = "ash_soil", count = {2, 4}, radius = {1.5, 3.2}},
		decor = {{"rubble", 4}, {"bone_pile", 2}, {"glowcap_purple", 1}}, decorShare = 0.07,
		edge = {{"blood_crystals", 4}, {"dark_boulder", 3}, {"cursed_pool", 2}, {"standing_torch", 1}}, edgeShare = 0.12
	},
	hall = {
		base = {{"ruined_floor", 100}},
		patches = {ground = "obsidian_floor", count = {2, 4}, radius = {1.5, 3}},
		decor = {{"rubble", 4}, {"bone_pile", 1}}, decorShare = 0.05,
		edge = {{"broken_pillar", 3}, {"standing_torch", 2}, {"dark_boulder", 1}}, edgeShare = 0.1
	},
	crypt = {
		base = {{"ash_soil", 70}, {"bone_earth", 30}},
		patches = {ground = "dark_moss", count = {1, 3}, radius = {1.5, 2.8}},
		decor = {{"bone_pile", 3}, {"rubble", 2}, {"glowcap_teal", 1}}, decorShare = 0.07,
		edge = {{"dead_bush", 3}, {"broken_pillar", 2}, {"dark_boulder", 2}, {"standing_torch", 1}}, edgeShare = 0.12
	},
	sanctum = {
		base = {{"wet_rock", 70}, {"mossy_rock", 30}},
		patches = {ground = "dark_moss", count = {2, 4}, radius = {1.5, 3.2}},
		decor = {{"glowcap_teal", 2}, {"glowcap_purple", 2}, {"rubble", 2}}, decorShare = 0.06,
		edge = {{"dark_boulder", 3}, {"cursed_pool", 2}, {"blood_crystals", 1}, {"standing_torch", 1}}, edgeShare = 0.12
	},
	arena = {
		base = {{"obsidian_floor", 92}, {"magma_floor", 8}},
		patches = {ground = "ash_soil", count = {3, 5}, radius = {1.5, 3}},
		decor = {{"rubble", 3}, {"bone_pile", 2}}, decorShare = 0.04,
		edge = {{"blood_crystals", 2}, {"dark_boulder", 2}, {"standing_torch", 1}}, edgeShare = 0.1
	},
	trial = {
		base = {{"obsidian_floor", 85}, {"magma_floor", 15}},
		patches = {ground = "ash_soil", count = {1, 3}, radius = {1.2, 2.2}},
		decor = {{"rubble", 3}, {"bone_pile", 2}}, decorShare = 0.05
	},
	lobby = {
		base = {{"ruined_floor", 100}},
		patches = {ground = "dark_moss", count = {1, 2}, radius = {1.2, 2}},
		decor = {{"rubble", 2}, {"glowcap_teal", 1}}, decorShare = 0.04,
		edge = {{"standing_torch", 1}, {"broken_pillar", 1}}, edgeShare = 0.08
	}
}

local DIRS4 = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}}

local function key(x, y)
	return x .. "," .. y
end

local function pick(list, rng)
	local total = 0
	for _, e in ipairs(list) do
		total = total + e[2]
	end
	if total <= 0 then
		return nil
	end
	local r = rng(1, total)
	for _, e in ipairs(list) do
		r = r - e[2]
		if r <= 0 then
			return e[1]
		end
	end
	return list[#list][1]
end

local function names(style)
	local out, seen = {}, {}
	local function add(n)
		if n and not seen[n] then
			seen[n] = true
			out[#out + 1] = n
		end
	end
	for _, e in ipairs(style.base or {}) do add(e[1]) end
	for _, e in ipairs(style.decor or {}) do add(e[1]) end
	for _, e in ipairs(style.edge or {}) do add(e[1]) end
	local pg = style.patches and style.patches.ground
	add(pg)
	if pg and P.BORDERED[P.FAMILY[pg]] then
		for _, piece in ipairs(P.PIECES) do
			add(P.FAMILY[pg] .. "_border_" .. piece)
		end
	end
	return out
end

P.PIECES = {"n", "e", "s", "w", "outer_ne", "outer_nw", "outer_se", "outer_sw", "inner_ne", "inner_nw", "inner_se",
	"inner_sw"}

function P.style(s)
	if type(s) == "string" then
		return P.STYLES[s]
	end
	return s
end

function P.ready(style)
	style = P.style(style)
	if not style or not D then
		return false
	end
	for _, n in ipairs(names(style)) do
		if not D.installed(n) then
			return false
		end
	end
	return true
end

-- border pieces for a tile, from which of its 8 neighbours are of the bordered family
function P.pieces(n, e, s, w, ne, nw, se, sw)
	local out = {}
	local used = {}
	local function add(piece, a, b)
		out[#out + 1] = piece
		used[a] = true
		if b then used[b] = true end
	end
	if n and w then
		add("inner_nw", "n", "w")
	elseif n and e then
		add("inner_ne", "n", "e")
	elseif s and w then
		add("inner_sw", "s", "w")
	elseif s and e then
		add("inner_se", "s", "e")
	end
	if s and e and not used.s and not used.e then add("inner_se", "s", "e") end
	if s and w and not used.s and not used.w then add("inner_sw", "s", "w") end
	for _, side in ipairs({{"n", n}, {"e", e}, {"s", s}, {"w", w}}) do
		if side[2] and not used[side[1]] then add(side[1], side[1]) end
	end
	if nw and not n and not w then out[#out + 1] = "outer_nw" end
	if ne and not n and not e then out[#out + 1] = "outer_ne" end
	if sw and not s and not w then out[#out + 1] = "outer_sw" end
	if se and not s and not e then out[#out + 1] = "outer_se" end
	return out
end

function P.plan(tiles, style, rng, opts)
	style = P.style(style)
	rng = rng or math.random
	opts = opts or {}
	local walls = opts.walls or {}
	local keepFree = opts.keepFree or 1
	local plan, list = {}, {}
	for _, t in ipairs(tiles) do
		local k = key(t.x, t.y)
		if not plan[k] then
			plan[k] = {x = t.x, y = t.y, z = t.z, borders = {}}
			list[#list + 1] = plan[k]
		end
	end
	local reserved, nearReserved = {}, {}
	for _, r in ipairs(opts.reserved or {}) do
		reserved[key(r.x, r.y)] = true
		for dx = -keepFree, keepFree do
			for dy = -keepFree, keepFree do
				nearReserved[key(r.x + dx, r.y + dy)] = true
			end
		end
	end
	-- 1. main ground
	for _, t in ipairs(list) do
		t.ground = pick(style.base, rng)
	end
	-- 2. patches of the second ground (not on reserved tiles: they stay the main ground)
	local pt = style.patches
	if pt and pt.ground and #list > 0 then
		local n = rng(pt.count[1], pt.count[2])
		for _ = 1, n do
			local c = list[rng(1, #list)]
			local r = pt.radius[1] + (pt.radius[2] - pt.radius[1]) * rng(0, 100) / 100
			local sx = 0.75 + rng(0, 50) / 100
			local sy = 0.75 + rng(0, 50) / 100
			local ir = math.ceil(r * 1.3)
			for dx = -ir, ir do
				for dy = -ir, ir do
					local t = plan[key(c.x + dx, c.y + dy)]
					local d = (dx * sx) ^ 2 + (dy * sy) ^ 2
					if t and d <= r * r + rng(0, 100) / 100 and not reserved[key(t.x, t.y)] then
						t.ground = pt.ground
					end
				end
			end
		end
	end
	-- 3. borders of the bordered family over every other tile next to it
	local fam = pt and pt.ground and P.FAMILY[pt.ground]
	if fam and P.BORDERED[fam] then
		local function is(x, y)
			local t = plan[key(x, y)]
			return t ~= nil and P.FAMILY[t.ground] == fam
		end
		for _, t in ipairs(list) do
			if P.FAMILY[t.ground] ~= fam then
				local x, y = t.x, t.y
				for _, piece in ipairs(P.pieces(is(x, y - 1), is(x + 1, y), is(x, y + 1), is(x - 1, y),
					is(x + 1, y - 1), is(x - 1, y - 1), is(x + 1, y + 1), is(x - 1, y + 1))) do
					t.borders[#t.borders + 1] = fam .. "_border_" .. piece
				end
			end
		end
	end
	-- 4. solid pieces against the walls: the tile touches a wall on one side and has three floor tiles behind it on
	-- the other, no other solid piece within two tiles, nothing near reserved tiles
	local solid = {}
	local function solidNear(x, y)
		for dx = -2, 2 do
			for dy = -2, 2 do
				if solid[key(x + dx, y + dy)] then
					return true
				end
			end
		end
		return false
	end
	if style.edge and (style.edgeShare or 0) > 0 then
		for _, t in ipairs(list) do
			local k = key(t.x, t.y)
			if not nearReserved[k] and #t.borders == 0 and P.FAMILY[t.ground] ~= fam then
				local ok = false
				for _, d in ipairs(DIRS4) do
					if walls[key(t.x + d[1], t.y + d[2])] and plan[key(t.x - d[1], t.y - d[2])]
						and plan[key(t.x - 2 * d[1], t.y - 2 * d[2])] and plan[key(t.x - 3 * d[1], t.y - 3 * d[2])] then
						ok = true
					end
				end
				if ok and not solidNear(t.x, t.y) and rng(1, 1000) <= style.edgeShare * 1000 then
					local name = pick(style.edge, rng)
					if P.FAMILY[name] then
						t.ground = name
						t.borders = {}
					else
						t.decor = name
					end
					solid[k] = true
				end
			end
		end
	end
	-- 5. loose walkable decoration
	if style.decor and (style.decorShare or 0) > 0 then
		for _, t in ipairs(list) do
			if not t.decor and not solid[key(t.x, t.y)] and not reserved[key(t.x, t.y)]
				and rng(1, 1000) <= style.decorShare * 1000 then
				t.decor = pick(style.decor, rng)
			end
		end
	end
	return plan
end

local darkSet
function P.isDark(id)
	if not darkSet then
		darkSet = {}
		for _, sid in pairs(D.ids) do
			darkSet[sid] = true
		end
	end
	return darkSet[id] == true
end

-- dark border / decoration item ids (not grounds), cleared before a repaint
local clearSet
local function clearable(id)
	if not clearSet then
		clearSet = {}
		for name, sid in pairs(D.ids) do
			if not P.FAMILY[name] then
				clearSet[sid] = true
			end
		end
	end
	return clearSet[id] == true
end

function P.apply(plan, z)
	local made = 0
	for _, t in pairs(plan) do
		local pos = Position(t.x, t.y, t.z or z)
		local tile = Tile(pos)
		if tile then
			for _, item in ipairs(tile:getItems() or {}) do
				if clearable(item:getId()) then
					item:remove()
				end
			end
			local gid = D.id(t.ground)
			local g = tile:getGround()
			if gid then
				if g and type(g) ~= "number" then
					if g:getId() ~= gid then
						g:transform(gid)
					end
				elseif not g then
					Game.createItem(gid, 1, pos)
					made = made + 1
				end
			end
			for _, b in ipairs(t.borders) do
				local id = D.id(b)
				if id and Game.createItem(id, 1, pos) then
					made = made + 1
				end
			end
			local did = t.decor and D.id(t.decor)
			if did and Game.createItem(did, 1, pos) then
				made = made + 1
			end
		end
	end
	return made
end

-- every ground id a style can lay (for "is this tile ours" checks)
function P.groundIds(style)
	style = P.style(style)
	local out = {}
	for _, n in ipairs(names(style)) do
		if P.FAMILY[n] and D.installed(n) then
			out[#out + 1] = D.ids[n]
		end
	end
	return out
end
