-- Our area generator and area plans inside the map editor (docs/MAP_GUIDE.md "Generator in the map editor", O381).
-- The editor runs Lua 5.1 scripts (Tools > Lua Scripts, "Custom Lua script") and gives them one API table, dme:
--   dme.setGround(pos, serverId), dme.addItem(pos, serverId, count), dme.clearTile(pos), dme.getTile(pos), dme.log(text)
-- pos = {x, y, z}. Ids are server ids (items.otb). Relative paths (dofile, io.open) start at the script's folder.
-- The editor moves the result: the smallest x / y and the largest z of the written tiles land on the window's
-- Destination X / Y / floor. Limits of one run: 100,000 tiles, 500,000 items, 1,024 items on a tile, 120 seconds.
-- It cannot write creatures, spawns, action ids, teleport targets or tile flags (protection zone): the log and a
-- text file list those.
--
-- The script pack (mapeditor\cinders\ in the Windows package) mirrors the server folder, so the same paths work
-- here and in server/ (tests/editor_scripts_test.lua):
--   generate_area.lua, paint_plan.lua      the entry scripts (parameters at the top)
--   tools/editor_scripts/cinders_editor.lua this file
--   tools/areaplan_build.lua               the planner's biomes (library use: AREAPLAN_LIB)
--   data/...                               areagen_core / areagen_config and the tables areaplan_build.lua reads
--   monsters.lua, plans/                   made by tools/gen_editor_scripts.py (monster levels, compiled plans)
-- Lua 5.1 / LuaJIT / Lua 5.3: no goto, no integer division, no bit operators.

local M = {}

M.LIMIT_TILES = 100000
M.LIMIT_ITEMS = 500000
M.LIMIT_STACK = 1024
M.LOG_LINES = 400 -- the editor keeps about 32 KiB of log

local floor = math.floor

local logged = 0
local function say(text)
	logged = logged + 1
	if logged > M.LOG_LINES then
		return
	end
	if logged == M.LOG_LINES then
		text = "(more lines left out: the editor keeps about 32 KiB of log)"
	end
	if dme and dme.log then
		dme.log(text)
	else
		print(text)
	end
end
M.say = say

local function fail(text)
	error(text, 0)
end

local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

-- ChaosThemeArt.PAIR24 (data/lib/chaos_theme_art.lua): the pair 24 grounds only while it is on (area_plan_core.py)
function M.pair24Switch()
	local s = readFile("data/lib/chaos_theme_art.lua")
	if not s then
		return false
	end
	return ("\n" .. s .. "\n"):find("\nM%.PAIR24%s*=%s*true[^%w_]") ~= nil
end

-- the planner's tables (tools/areaplan_build.lua in library mode)
function M.loadPlanner(pair24, dark)
	AREAPLAN_LIB = {pair24 = pair24, dark = dark}
	local ok, lib = pcall(dofile, "tools/areaplan_build.lua")
	AREAPLAN_LIB = nil
	if not ok then
		fail("cannot load the area generator: " .. tostring(lib))
	end
	return lib
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

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	return keys
end

-- ------------------------------------------------------------------ writing tiles
-- tiles = {{x, y, z, ground, items = {id, ...}}, ...}: checks the limits first, then writes every tile
function M.write(tiles)
	local items = 0
	for _, t in ipairs(tiles) do
		local n = #t.items
		if n + 1 > M.LIMIT_STACK then
			fail(string.format("the tile %d, %d, %d holds %d items (the editor takes %d)", t.x, t.y, t.z, n + 1, M.LIMIT_STACK))
		end
		items = items + n + (t.ground and 1 or 0)
	end
	if #tiles > M.LIMIT_TILES then
		fail(string.format("%d tiles: the editor writes at most %d in one run", #tiles, M.LIMIT_TILES))
	end
	if items > M.LIMIT_ITEMS then
		fail(string.format("%d items: the editor writes at most %d in one run", items, M.LIMIT_ITEMS))
	end
	for _, t in ipairs(tiles) do
		local pos = {x = t.x, y = t.y, z = t.z}
		if t.ground then
			dme.setGround(pos, t.ground)
		else
			dme.clearTile(pos)
		end
		for _, id in ipairs(t.items) do
			dme.addItem(pos, id, 1)
		end
	end
	return #tiles, items
end

-- the corner the editor moves to its Destination: smallest x / y, largest z
function M.corner(tiles)
	local x, y, z = 65535, 65535, 0
	for _, t in ipairs(tiles) do
		if t.x < x then
			x = t.x
		end
		if t.y < y then
			y = t.y
		end
		if t.z > z then
			z = t.z
		end
	end
	return x, y, z
end

local function rel(cx, cy, cz, p)
	return string.format("+%d, +%d, floor %+d", p.x - cx, p.y - cy, p.z - cz)
end

-- ------------------------------------------------------------------ monsters of a level band
-- rows {name, level, boss}: up to 5 monsters nearest the middle of the band (within 25% of it), the boss nearest
-- the top; the same rows always give the same pick
function M.pickMonsters(rows, lo, hi)
	local mid = (lo + hi) / 2
	local slack = math.max(25, floor((hi - lo) / 2 + hi * 0.25))
	local mons, bosses = {}, {}
	for _, r in ipairs(rows) do
		local lv = tonumber(r.level or r[2])
		local name = r.name or r[1]
		local boss = r.boss
		if boss == nil then
			boss = r[3]
		end
		if lv and name then
			if boss then
				if lv >= lo - slack and lv <= hi + slack then
					bosses[#bosses + 1] = {name = name, d = math.abs(lv - hi)}
				end
			elseif lv >= lo - slack and lv <= hi + slack then
				mons[#mons + 1] = {name = name, d = math.abs(lv - mid)}
			end
		end
	end
	local function order(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.name < b.name
	end
	table.sort(mons, order)
	table.sort(bosses, order)
	local weights = {3, 3, 2, 2, 1}
	local out = {}
	for k = 1, math.min(5, #mons) do
		out[k] = {mons[k].name, weights[k]}
	end
	return out, bosses[1] and bosses[1].name or nil
end

-- ------------------------------------------------------------------ a new area
-- P: biome, width, height, floors, seed, level = {lo, hi}, decoration, light, boss, origin = {x, y, z}, dark, name,
--    monsters (names or {name, weight}; nil: picked from monsters.lua by level), monsterTable (rows, for tests),
--    spawnFile (path of the spawn list; false: none)
function M.generate(P)
	logged = 0
	local pair24 = P.pair24
	if pair24 == nil then
		pair24 = M.pair24Switch()
	end
	local L = M.loadPlanner(pair24, P.dark)
	local A, cfg = L.A, L.cfg
	local biome = P.biome or "cave"
	local b = L.biomes[biome]
	if not b then
		fail("unknown biome " .. tostring(biome) .. "; the biomes: " .. table.concat(sortedKeys(L.biomes), ", "))
	end
	local w, h, n = floor(tonumber(P.width) or 0), floor(tonumber(P.height) or 0), floor(tonumber(P.floors) or 1)
	if w < 32 or h < 32 or w > 400 or h > 400 then
		fail(string.format("width and height must be 32-400 (got %d x %d)", w, h))
	end
	if n < 1 or n > 4 then
		fail("floors must be 1-4")
	end
	if w * h * n > M.LIMIT_TILES then
		fail(string.format("%d x %d x %d floors = %d tiles: the editor writes at most %d in one run. Make it smaller or"
			.. " generate the floors one by one (floors = 1, then another seed or origin z).", w, h, n, w * h * n, M.LIMIT_TILES))
	end
	local seed = floor(tonumber(P.seed or DME_SEED) or 1)
	local lv = P.level or {100, 200}
	local lo, hi = floor(tonumber(lv[1]) or 1), floor(tonumber(lv[2] or lv[1]) or 1)
	if hi < lo then
		lo, hi = hi, lo
	end
	local o = P.origin or {}
	local origin = {x = floor(tonumber(o.x) or 1000), y = floor(tonumber(o.y) or 1000), z = floor(tonumber(o.z) or b.z)}
	if origin.z < 0 or origin.z + n - 1 > 15 or origin.x + w > 65535 or origin.y + h > 65535 then
		fail("the area does not fit the map at that origin")
	end

	-- the layout and spawn rules of the first configured area of the same kind (areagen_config.lua areas)
	local base
	for _, a in ipairs(cfg.areas) do
		if a.kind == b.kind and not base then
			base = a
		end
	end
	local layout = copy(base and base.layout or {})
	if b.kind == "dungeon" then
		local area = w * h
		local rlo = math.max(3, floor(area / 650))
		layout.rooms = {rlo, math.max(rlo + 1, floor(area / 550))}
		layout.room = math.min(w, h) >= 100 and {7, 12} or {6, 8}
		layout.bossRoom = P.boss ~= false and 9 or nil
	end

	local rows = P.monsters
	local bossName = P.bossMonster
	if not rows then
		local tbl = P.monsterTable
		if not tbl then
			local ok, t = pcall(dofile, "monsters.lua")
			tbl = ok and t or nil
		end
		if not tbl then
			fail("no monster table (monsters.lua, made by gen_editor_scripts.py): give monsters = {...} instead")
		end
		local picked, boss = M.pickMonsters(tbl, lo, hi)
		rows = picked
		bossName = bossName or boss
	end
	local mons = {}
	for _, r in ipairs(rows) do
		if type(r) == "table" then
			mons[#mons + 1] = {r[1], r[2] or 1}
		else
			mons[#mons + 1] = {r, 1}
		end
	end
	local sp = copy(base and base.spawns or {density = 4.5, minDistance = 6, safeRadius = 10, spawntime = 75})
	sp.level = {lo, hi}
	sp.monsters = mons
	sp.band = nil
	if #mons == 0 then
		sp.density = 0
	end

	local def = {id = "editor", name = P.name or ("Generated " .. biome), origin = origin, size = {w, h}, floors = n,
		seed = seed, layout = layout, arrival = {8, 8}, exit = {0, -1}, spawns = sp,
		linksPerFloor = n > 1 and (b.kind == "dungeon" and 1 or 2) or nil}
	if P.boss ~= false and bossName then
		def.boss = {monster = bossName, name = bossName, level = hi}
		if b.kind ~= "dungeon" then
			def.boss.radius = 6
		end
	end
	local theme = L.planTheme(biome, L.decoration[P.decoration or "normal"] or 1, L.light[P.light or b.light] or 1)
	def.kind = b.kind
	def.theme = "plan_editor"
	cfg.themes[def.theme] = theme

	local m = A.generate(cfg, def, L.opts)
	local tiles = {}
	for _, t in ipairs(m.tiles) do
		tiles[#tiles + 1] = {x = t.x, y = t.y, z = t.z, ground = t.ground, items = t.items}
	end
	local nt, ni = M.write(tiles)
	local cx, cy, cz = M.corner(tiles)

	say(string.format("%s: biome %s (%s), %d x %d, %d floor(s), seed %d, monsters of level %d-%d", def.name, biome,
		b.kind, w, h, n, seed, lo, hi))
	say(string.format("%d tiles, %d items, checksum %d", nt, ni, A.checksum(m)))
	say("Positions below: from the Destination X / Y; floor 0 = the Destination floor (the deepest floor of the area).")
	for _, f in ipairs(m.floors) do
		say(string.format("floor %+d: %d walkable tiles, %d monsters", f.z - cz, f.walkable or 0, f.monsters or 0))
	end
	for _, p in ipairs(A.validate(cfg, m, L.opts)) do
		say("check: " .. p)
	end
	if m.arrival then
		say("arrival (the entry point): " .. rel(cx, cy, cz, m.arrival))
	end
	if m.exit then
		say("exit portal (set its teleport target by hand): " .. rel(cx, cy, cz, m.exit))
	end
	for _, l in ipairs(m.links or {}) do
		say("hole " .. rel(cx, cy, cz, l.hole) .. " -> ladder " .. rel(cx, cy, cz, l.ladder))
	end
	-- spawns: the editor cannot place creatures; the list goes to the log and to a file next to the script
	local lines = {}
	for _, s in ipairs(m.spawns or {}) do
		lines[#lines + 1] = string.format("%s x%d (level %d, respawn %d s) at %s", s.monster, s.count or 1, s.level or hi,
			s.spawntime or 0, rel(cx, cy, cz, s))
	end
	if m.boss then
		lines[#lines + 1] = string.format("BOSS %s (level %d) at %s", m.boss.monster, m.boss.level or hi, rel(cx, cy, cz, m.boss))
	end
	say(string.format("%d spawn points (the editor cannot place creatures: add them with the creature palette):", #lines))
	for k = 1, math.min(#lines, 40) do
		say("  " .. lines[k])
	end
	local file = P.spawnFile
	if file == nil then
		file = "generated_spawns.txt"
	end
	if file then
		local f = io.open(file, "w")
		if f then
			f:write(def.name, ", seed ", seed, "\n")
			f:write("Positions from the Destination X / Y; floor 0 = the Destination floor.\n")
			f:write(table.concat(lines, "\n"), "\n")
			f:close()
			if #lines > 40 then
				say(string.format("  ... and %d more: all of them in %s next to this script", #lines - 40, file))
			end
		end
	end
	return {tiles = nt, items = ni, checksum = A.checksum(m), model = m, def = def, allowed = A.allowedIds(cfg, def, L.opts)}
end

-- ------------------------------------------------------------------ a compiled plan
-- the data file of one plan (gen_editor_scripts.py): {id, name, biome, origin, size, floors, level, tiles = "rows",
-- frame = "rows", notes = "text"}; a row: x y z ground item item ...
local function rowsOf(text, out, onlyZ)
	for line in (text or ""):gmatch("[^\n]+") do
		local v = {}
		for num in line:gmatch("%d+") do
			v[#v + 1] = tonumber(num)
		end
		if #v >= 4 and (not onlyZ or v[3] == onlyZ) then
			local items = {}
			for k = 5, #v do
				items[#items + 1] = v[k]
			end
			out[#out + 1] = {x = v[1], y = v[2], z = v[3], ground = v[4] > 0 and v[4] or nil, items = items}
		end
	end
	return out
end
M.rowsOf = rowsOf

local function plansList(dir)
	local ok, index = pcall(dofile, dir .. "index.lua")
	if not ok or type(index) ~= "table" then
		return "(no plans/index.lua)"
	end
	local names = {}
	for _, e in ipairs(index) do
		names[#names + 1] = e.id
	end
	return table.concat(names, ", ")
end

-- P: plan (id), floor (a z; nil: every floor), frame (true: the view frame of bare rock around it), plansDir,
--    limitTiles (tests)
function M.paint(P)
	logged = 0
	local dir = P.plansDir or "plans/"
	if not P.plan or P.plan == "" then
		fail("set plan = \"<id>\" at the top of the script; the plans: " .. plansList(dir))
	end
	local ok, data = pcall(dofile, dir .. P.plan .. ".lua")
	if not ok or type(data) ~= "table" then
		fail("no compiled plan " .. tostring(P.plan) .. "; the plans: " .. plansList(dir))
	end
	-- tiles per floor first: a plan too big for one run is painted floor by floor
	local all = rowsOf(data.tiles, {})
	if P.frame ~= false then
		rowsOf(data.frame, all)
	end
	local perZ, zs = {}, {}
	for _, t in ipairs(all) do
		if not perZ[t.z] then
			perZ[t.z] = 0
			zs[#zs + 1] = t.z
		end
		perZ[t.z] = perZ[t.z] + 1
	end
	table.sort(zs)
	local tiles = all
	if P.floor then
		tiles = {}
		for _, t in ipairs(all) do
			if t.z == P.floor then
				tiles[#tiles + 1] = t
			end
		end
		if #tiles == 0 then
			local list = {}
			for _, z in ipairs(zs) do
				list[#list + 1] = tostring(z)
			end
			fail(string.format("%s has no tiles on floor %d; its floors: %s", data.id, P.floor, table.concat(list, ", ")))
		end
	end
	local limit = P.limitTiles or M.LIMIT_TILES
	if #tiles > limit then
		local list = {}
		for _, z in ipairs(zs) do
			list[#list + 1] = string.format("z %d: %d tiles", z, perZ[z])
		end
		local hint = P.floor and "set frame = false" or "set floor = <z> and paint one floor per run"
		fail(string.format("%s has %d tiles (%s), the editor writes at most %d in one run: %s", data.id, #tiles,
			table.concat(list, ", "), limit, hint))
	end
	local nt, ni = M.write(tiles)
	local cx, cy, cz = M.corner(tiles)
	say(string.format("%s (%s): %d tiles, %d items%s%s", data.name or data.id, data.id, nt, ni,
		P.floor and (" on floor " .. P.floor) or "", P.frame ~= false and ", with the view frame" or ""))
	if data.origin then
		say(string.format("At its place on the server map: Destination X %d, Y %d, floor %d.", cx, cy, cz))
	end
	say("Not written (the editor's scripts cannot): spawns, NPCs, action ids of chests and portals, teleport targets,"
		.. " protection zones. The list: plans\\" .. data.id .. "-notes.txt")
	local k = 0
	for line in (data.notes or ""):gmatch("[^\n]+") do
		k = k + 1
		if k > 30 then
			say("  ... (the rest in the notes file)")
			break
		end
		say("  " .. line)
	end
	return {tiles = nt, items = ni, corner = {cx, cy, cz}, floors = zs}
end

return M
