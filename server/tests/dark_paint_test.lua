-- Run from the server/ folder: luajit tests/dark_paint_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The dark tile painter (data/lib/chaos_dark_paint.lua): border pieces per neighbourhood, a planned room (grounds,
-- borders on every tile next to a patch, nothing solid near reserved tiles or away from the walls), the fallback when
-- the set is not installed, and the ids of data/lib/chaos_dark_tiles.lua against data/items/dark_tiles.csv.
dofile("data/lib/chaos_dark_paint.lua")
local P, D = ChaosDarkPaint, ChaosDarkTiles

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

local function rng(seed)
	local s = seed
	return function(a, b)
		s = (s * 16807) % 2147483647
		return a + s % (b - a + 1)
	end
end

local function set(list)
	local out = {}
	for _, v in ipairs(list) do
		out[v] = true
	end
	return out
end

-- ------------------------------------------------------------------ border pieces
do
	local p = set(P.pieces(true, false, false, false))
	ok(p.n and not p.inner_nw, "dark to the north: north edge")
	p = set(P.pieces(true, false, false, true))
	ok(p.inner_nw and not p.n and not p.w, "north and west: inner corner")
	p = set(P.pieces(false, false, false, false, false, true))
	ok(p.outer_nw, "diagonal north-west only: outer corner")
	p = set(P.pieces(true, false, false, false, false, true))
	ok(p.n and not p.outer_nw, "an edge hides the outer corner on its side")
	p = set(P.pieces(true, true, true, true))
	ok(p.inner_nw and p.inner_se, "surrounded: two inner corners")
	p = set(P.pieces(false, false, false, false, true, true, true, true))
	ok(p.outer_ne and p.outer_nw and p.outer_se and p.outer_sw, "four diagonals: four outer corners")
	eq(#P.pieces(false, false, false, false), 0, "no neighbour: no piece")
end

-- ------------------------------------------------------------------ ids and manifest
do
	local f = io.open("data/items/dark_tiles.csv")
	ok(f ~= nil, "manifest present")
	if f then
		local n = 0
		f:read("*l")
		for line in f:lines() do
			local cid, sid, key = line:match("^(%d+),(%d+),([%w_]+),")
			n = n + 1
			eq(D.ids[key], tonumber(sid), "lua id of " .. tostring(key))
			eq(tonumber(sid), tonumber(cid) + 3000, "server id = client id + 3000 for " .. tostring(key))
		end
		f:close()
		local m = 0
		for _ in pairs(D.ids) do
			m = m + 1
		end
		eq(m, n, "every manifest row in chaos_dark_tiles.lua")
	end
	-- every name a style uses exists
	for name, style in pairs(P.STYLES) do
		for _, list in ipairs({style.base, style.decor or {}, style.edge or {}}) do
			for _, e in ipairs(list) do
				ok(D.ids[e[1]] ~= nil, name .. ": " .. e[1] .. " is in the set")
			end
		end
		if style.patches then
			ok(P.BORDERED[P.FAMILY[style.patches.ground]], name .. ": patch ground has borders")
			for _, e in ipairs(style.base) do
				ok(P.FAMILY[e[1]] ~= P.FAMILY[style.patches.ground], name .. ": patch of another family than " .. e[1])
			end
		end
	end
end

-- ------------------------------------------------------------------ not installed: fallback
do
	ItemType = nil -- no engine: nothing is installed
	ok(not P.ready("abyss"), "not ready without the items")
	eq(D.id("obsidian_floor", 407), 407, "fallback id")
	ok(D.list({"obsidian_floor"}, false) == false, "fallback list")
end

-- ------------------------------------------------------------------ a planned room
do
	-- 15 x 15 room inside a wall ring, arrival at the south, boss in the middle
	local tiles, walls = {}, {}
	for x = 0, 16 do
		for y = 0, 16 do
			if x == 0 or y == 0 or x == 16 or y == 16 then
				walls[x .. "," .. y] = true
			else
				tiles[#tiles + 1] = {x = x, y = y, z = 7}
			end
		end
	end
	local reserved = {{x = 8, y = 8}, {x = 8, y = 13}}
	for _, styleName in ipairs({"abyss", "hall", "crypt", "sanctum", "arena", "lobby", "trial"}) do
		local style = P.STYLES[styleName]
		local plan = P.plan(tiles, styleName, rng(7), {walls = walls, reserved = reserved})
		local n, grounds, solids, decor, borders = 0, {}, 0, 0, 0
		local fam = P.FAMILY[style.patches.ground]
		local function at(x, y)
			return plan[x .. "," .. y]
		end
		for k, t in pairs(plan) do
			n = n + 1
			ok(D.ids[t.ground] ~= nil, styleName .. " ground known " .. k)
			grounds[t.ground] = true
			if t.decor then
				decor = decor + 1
			end
			-- every non-family tile next to a family tile has a border, and only those
			local near = false
			for dx = -1, 1 do
				for dy = -1, 1 do
					local o = at(t.x + dx, t.y + dy)
					if (dx ~= 0 or dy ~= 0) and o and P.FAMILY[o.ground] == fam then
						near = true
					end
				end
			end
			if P.FAMILY[t.ground] ~= fam and near then
				ok(#t.borders > 0, styleName .. ": border at " .. k)
			end
			if P.FAMILY[t.ground] == fam or not near then
				eq(#t.borders, 0, styleName .. ": no border at " .. k)
			end
			borders = borders + #t.borders
			for _, b in ipairs(t.borders) do
				ok(D.ids[b] ~= nil, styleName .. ": border piece known " .. b)
			end
			-- solid things only against a wall and never next to reserved tiles
			local solid = (t.decor and not set({"rubble", "bone_pile", "glowcap_purple", "glowcap_teal"})[t.decor])
				or t.ground == "cursed_pool"
			if solid then
				solids = solids + 1
				local wallSide = walls[(t.x - 1) .. "," .. t.y] or walls[(t.x + 1) .. "," .. t.y]
					or walls[t.x .. "," .. (t.y - 1)] or walls[t.x .. "," .. (t.y + 1)]
				ok(wallSide, styleName .. ": solid piece against a wall at " .. k)
				for _, r in ipairs(reserved) do
					ok(math.abs(r.x - t.x) > 1 or math.abs(r.y - t.y) > 1, styleName .. ": solid near reserved " .. k)
				end
			end
		end
		eq(n, 15 * 15, styleName .. ": every tile planned")
		for _, r in ipairs(reserved) do
			local t = at(r.x, r.y)
			ok(t.decor == nil, styleName .. ": no decor on a reserved tile")
		end
		ok(grounds[style.patches.ground], styleName .. ": a patch was laid")
		ok(borders > 0, styleName .. ": borders laid")
		ok(decor > 0, styleName .. ": some decoration")
		-- the same generator gives the same room
		local again = P.plan(tiles, styleName, rng(7), {walls = walls, reserved = reserved})
		local same = true
		for k, t in pairs(plan) do
			local o = again[k]
			if o.ground ~= t.ground or o.decor ~= t.decor or #o.borders ~= #t.borders then
				same = false
			end
		end
		ok(same, styleName .. ": deterministic for one generator")
	end
end

print(string.format("dark_paint_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
print("dark_paint_test: ok")
