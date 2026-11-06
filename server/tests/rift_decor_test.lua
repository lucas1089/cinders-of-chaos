-- Run from the server/ folder: luajit tests/rift_decor_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Decoration of the generated rift maps (O428; owner report 2026-11-06: a brazier on a patch of another floor, a big
-- blue piece beside it cut off by the wall, a strip crossing a wall). The client draws a WxH item up and to the left of
-- its tile and a 2x2 wall piece the same way, so a wall south, east or south-east of a floor tile draws over it.
-- areagen's `decorFit` (areagen_config.lua `fit`, set by rift_layout_core.lua) keeps every piece's footprint on floor
-- the walls do not cover. Checked here on many seeds, every theme and band, stock and dark palettes:
--   - every footprint tile is floor (never a wall, rock or pool tile) and no footprints overlap;
--   - no footprint tile lies under a wall piece, derived again here from the wall ids on the tiles (not from the
--     generator's own sets);
--   - a light or prop stands on one ground: no border piece on its tiles, every floor neighbour of its tiles of the
--     same family (no lone patch tile or patch edge under it);
--   - the sizes: the dark braziers and torches are 1x2, the rock outcrop 2x2; stock lights count 1x2, props 2x2;
--   - the test sees the bug: the same maps without decorFit do put pieces under the walls.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/rift_layout_core.lua")
dofile("data/lib/chaos_dark_tiles.lua")
local RL, A = ChaosRiftLayout, ChaosAreaGenCore
local cfg = dofile("data/scripts/chaos/rift_config.lua")
local ag = dofile("data/scripts/chaos/areagen_config.lua")
local DARK = {dark = true, darkIds = ChaosDarkTiles.ids}
local STOCK = {}
local g = cfg.grid

local function idOf(v)
	if type(v) == "number" then
		return v
	end
	return ChaosDarkTiles.ids[v]
end

-- ground id -> family, border piece ids, wall piece ids (all from the config, both palettes)
local famOf, borderId, wallId = {}, {}, {}
for name, fd in pairs(ag.families) do
	for _, row in ipairs(fd.grounds or {}) do
		famOf[idOf(row[1])] = name
	end
end
for _, set in pairs(ag.pieces or {}) do
	for _, v in pairs(set) do
		if type(v) == "table" then
			for _, row in ipairs(v) do
				borderId[idOf(row[1])] = true
			end
		else
			borderId[idOf(v)] = true
		end
	end
end
for _, set in pairs(ag.walls) do
	for _, rows in pairs(set) do
		for _, row in ipairs(rows) do
			wallId[row[1]] = true
		end
	end
end

-- the footprint data of a model, checked
local function key(x, y)
	return y * 65536 + x
end
local totals = {lights = 0, props = 0, tall = 0, big = 0, decor = 0, obstacles = 0, maps = 0, walls = 0}
local function check(tag, model, expectClean)
	local fit = model.fit
	ok(fit ~= nil and #fit.deco > 0, tag .. ": fit data")
	if not fit then
		return 0
	end
	totals.maps = totals.maps + 1
	-- tiles by position, walls by position (from the wall ids on the tiles)
	local tile, walls = {}, {}
	for _, t in ipairs(model.tiles) do
		tile[t.z .. ":" .. key(t.x, t.y)] = t
		for _, id in ipairs(t.items) do
			if wallId[id] then
				walls[t.z .. ":" .. key(t.x, t.y)] = true
				totals.walls = totals.walls + 1
			end
		end
	end
	-- the cells a 2x2 wall piece draws over: the tile, the one west, north and north-west
	local under = {}
	for k in pairs(walls) do
		local z, p = k:match("^(%d+):(%d+)$")
		p = tonumber(p)
		local x, y = p % 65536, math.floor(p / 65536)
		for a = 0, 1 do
			for b = 0, 1 do
				under[z .. ":" .. key(x - a, y - b)] = true
			end
		end
	end
	local bad, taken = 0, {}
	local function fail(msg)
		bad = bad + 1
		if expectClean then
			ok(false, tag .. ": " .. msg)
		end
	end
	for _, d in ipairs(fit.deco) do
		local lightOrProp = d.kind == "light" or d.kind == "prop"
		totals[d.kind == "light" and "lights" or d.kind == "prop" and "props" or d.kind == "obstacle" and "obstacles" or "decor"] =
			totals[d.kind == "light" and "lights" or d.kind == "prop" and "props" or d.kind == "obstacle" and "obstacles" or "decor"] + 1
		if d.w == 1 and d.h == 2 then
			totals.tall = totals.tall + 1
		elseif d.w >= 2 then
			totals.big = totals.big + 1
		end
		for a = 0, d.w - 1 do
			for b = 0, d.h - 1 do
				local x, y = d.x - a, d.y - b
				local k = d.z .. ":" .. key(x, y)
				if not fit.floor[d.z][key(x, y)] then
					fail(string.format("%s %d at %d,%d: footprint tile %d,%d is not floor", d.kind, d.id, d.x, d.y, x, y))
				end
				if walls[k] then
					fail(string.format("%s %d at %d,%d: footprint over a wall", d.kind, d.id, d.x, d.y))
				end
				if under[k] then
					fail(string.format("%s %d at %d,%d: footprint tile %d,%d under a wall piece", d.kind, d.id, d.x, d.y, x, y))
				end
				if taken[k] then
					fail(string.format("%s %d at %d,%d: footprint overlaps another piece", d.kind, d.id, d.x, d.y))
				end
				taken[k] = true
				if lightOrProp and expectClean then
					-- one ground: no border piece on the tile, every floor neighbour of the same family
					local t = tile[k]
					local fam = t and famOf[t.ground]
					ok(fam ~= nil, tag .. ": the ground of " .. k .. " has a family")
					for _, id in ipairs(t and t.items or {}) do
						ok(not borderId[id], tag .. ": no border piece under a " .. d.kind .. " (" .. tostring(id) .. ")")
					end
					for dx = -1, 1 do
						for dy = -1, 1 do
							local n = tile[d.z .. ":" .. key(x + dx, y + dy)]
							if n and fit.floor[d.z][key(x + dx, y + dy)] and famOf[n.ground] ~= fam then
								ok(false, tag .. ": a " .. d.kind .. " at " .. d.x .. "," .. d.y .. " stands on a patch edge")
							end
						end
					end
				end
			end
		end
	end
	return bad
end

-- ====================================================================== the maps
local expectSize = {}
for name, wh in pairs(ag.fit.sizes) do
	expectSize[idOf(name)] = wh
end
local legacyBad, legacyMaps = 0, 0
local lightsFit, lightsLegacy = 0, 0
for ti, th in ipairs(cfg.themes) do
	for _, band in ipairs({1, 3}) do
		for s = 1, (band == 1 and 7 or 2) do
			for _, d in ipairs({false, true}) do
				local opts = d and DARK or STOCK
				local req = {theme = th.name, band = band, seed = 4100 + ti * 977 + band * 131 + s * 17,
					origin = {x = g.origin.x, y = g.origin.y, z = g.origin.z}}
				local tag = string.format("%s band %d seed %d%s", th.name, band, req.seed, d and " dark" or "")
				local L, model, def = RL.generate(cfg, ag, req, opts)
				eq(#L.problems, 0, tag .. ": valid")
				ok(def.decorFit and def.wallSize == 2, tag .. ": the rift def asks for decorFit and 2x2 walls")
				check(tag, model, true)
				for _, dd in ipairs(model.fit.deco) do
					if dd.kind == "light" then
						lightsFit = lightsFit + 1
					end
					local want = expectSize[dd.id]
					if want then
						eq(dd.w .. "x" .. dd.h, want[1] .. "x" .. want[2], tag .. ": size of " .. dd.id)
					elseif dd.kind == "light" then
						eq(dd.w .. "x" .. dd.h, "1x2", tag .. ": a stock light counts 1x2")
					elseif dd.kind == "prop" then
						eq(dd.w .. "x" .. dd.h, "2x2", tag .. ": a stock prop counts 2x2")
					end
				end
				-- the same plan without the fit: the bug the owner saw (only maps with 2x2 walls can show it)
				if band == 1 and s <= 3 then
					local plain = RL.plan(cfg, req)
					plain.decorFit = nil
					local m2 = A.generate(ag, plain, opts)
					local walls, under = {}, {}
					for _, t in ipairs(m2.tiles) do
						for _, id in ipairs(t.items) do
							if wallId[id] then
								walls[#walls + 1] = t
							end
						end
					end
					for _, w in ipairs(walls) do
						for a = 0, 1 do
							for b = 0, 1 do
								under[w.z .. ":" .. key(w.x - a, w.y - b)] = true
							end
						end
					end
					local lightIds = {}
					for _, id in pairs(ChaosDarkTiles.ids) do
						lightIds[id] = true
					end
					for _, t in ipairs(m2.tiles) do
						local k = t.z .. ":" .. key(t.x, t.y)
						if under[k] and #t.items > 0 and not wallId[t.items[#t.items]] then
							legacyBad = legacyBad + 1
						end
					end
					legacyMaps = legacyMaps + 1
					lightsLegacy = lightsLegacy + m2.stats.lights
				end
			end
		end
	end
end
ok(totals.maps >= 40, "maps checked: " .. totals.maps)
ok(totals.walls > 1000, "the maps have wall pieces to test against: " .. totals.walls)
ok(totals.lights > 200 and totals.props > 20, "lights " .. totals.lights .. " and props " .. totals.props .. " were placed")
ok(totals.tall > 50, "1x2 pieces were placed and fit: " .. totals.tall)
ok(totals.big > 0, "a 2x2 piece was placed and fit: " .. totals.big)
ok(totals.decor > 1000, "scatter decoration was placed: " .. totals.decor)
ok(legacyMaps > 0 and legacyBad > 50, "without decorFit pieces stand under the walls (" .. legacyBad .. " tiles in " .. legacyMaps .. " maps)")
-- the fit costs lights, not all of them
ok(lightsFit >= lightsLegacy * 0.25, "lights kept: " .. lightsFit .. " of " .. lightsLegacy .. " (legacy maps are a subset)")

print(string.format("rift_decor_test: %d checks, %d failed (%d maps, %d lights, %d props, %d tall, %d big)", checks, fails,
	totals.maps, totals.lights, totals.props, totals.tall, totals.big))
if fails > 0 then
	os.exit(1)
end
