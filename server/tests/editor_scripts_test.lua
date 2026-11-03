-- Run from the server/ folder: luajit tests/editor_scripts_test.lua (CI: LuaJIT, Lua 5.3 and Lua 5.1, the map editor's
-- Lua). The map editor's script pack (tools/editor_scripts/, O381; docs/MAP_GUIDE.md "Generator in the map editor"):
-- the entry scripts run against a stand-in of the editor's Lua runner (tools/editor_scripts/dme_mock.lua: relative
-- paths from the script's folder, the dme table, the run limits). generate_area.lua: tiles written for several biomes,
-- every id in the area's allowed set, inside the area's box, the same seed the same map, another seed another map,
-- the refusals (size over 100,000 tiles, unknown biome); the level band's monster pick. paint_plan.lua on a small
-- plan file: tiles and frame, one floor, the floor split over the tile limit, a missing plan.
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

local mock = dofile("tools/editor_scripts/dme_mock.lua")
local GEN = "tools/editor_scripts/generate_area.lua"
local PAINT = "tools/editor_scripts/paint_plan.lua"

local function gen(params, seed)
	params.spawnFile = false
	params.monsters = params.monsters or {{"Rat", 3}, {"Cave Rat", 2}}
	params.bossMonster = params.bossMonster or "Rat"
	return mock.run(GEN, {seed = seed or 7, params = params})
end

-- a text over the whole buffer (same buffer = same text)
local function signature(tiles)
	local keys = {}
	for k in pairs(tiles) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		local t = tiles[k]
		local s = {k, t.ground and t.ground.id or 0}
		for _, it in ipairs(t.items) do
			s[#s + 1] = it.id
		end
		parts[#parts + 1] = table.concat(s, " ")
	end
	return table.concat(parts, "\n")
end

-- ====================================================================== generate_area.lua
for _, case in ipairs({
	{biome = "cave", width = 48, height = 40, floors = 2},
	{biome = "crypt", width = 60, height = 50, floors = 1},
	{biome = "vault", width = 50, height = 44, floors = 1},
	{biome = "waste", width = 48, height = 40, floors = 1},
	{biome = "marsh", width = 48, height = 40, floors = 1},
	{biome = "lava", width = 48, height = 40, floors = 1},
	{biome = "forest", width = 40, height = 36, floors = 1},
	{biome = "ice", width = 40, height = 36, floors = 1, decoration = "dense", light = "dark"},
	{biome = "catacomb", width = 48, height = 40, floors = 2, boss = false},
}) do
	local tag = case.biome
	local res = gen(case)
	ok(res.ok, tag .. ": runs (" .. tostring(res.error) .. ")")
	if res.ok then
		local v = res.value
		ok(res.count > case.width * case.height * case.floors / 5, tag .. ": a real area (" .. res.count .. " tiles)")
		eq(res.count, v.tiles, tag .. ": every model tile written once")
		eq(#v.model.tiles, v.tiles, tag .. ": the model's tiles")
		local o = v.def.origin
		local bad, outside, noGround = 0, 0, 0
		for _, t in pairs(res.tiles) do
			if t.x < o.x or t.y < o.y or t.x >= o.x + case.width or t.y >= o.y + case.height or t.z < o.z
				or t.z > o.z + case.floors - 1 then
				outside = outside + 1
			end
			if not t.ground then
				noGround = noGround + 1
			elseif not v.allowed[t.ground.id] then
				bad = bad + 1
			end
			for _, it in ipairs(t.items) do
				if not v.allowed[it.id] then
					bad = bad + 1
				end
			end
		end
		eq(bad, 0, tag .. ": ids outside the area's allowed set")
		eq(outside, 0, tag .. ": tiles outside the area's box")
		eq(noGround, 0, tag .. ": tiles without ground")
		ok(#res.log >= 5 and res.log[1]:find(case.biome, 1, true) ~= nil, tag .. ": the log names the biome")
		-- the same seed: the same buffer; another seed: another one
		local again = gen(case)
		eq(signature(again.tiles), signature(res.tiles), tag .. ": the same seed gives the same tiles")
		local other = gen(case, 8)
		ok(other.ok and signature(other.tiles) ~= signature(res.tiles), tag .. ": another seed gives other tiles")
	end
end

-- the seed parameter wins over the editor window's seed
do
	local a = gen({biome = "cave", width = 40, height = 40, seed = 99}, 1)
	local b = gen({biome = "cave", width = 40, height = 40, seed = 99}, 2)
	ok(a.ok and b.ok and signature(a.tiles) == signature(b.tiles), "seed = 99 ignores the window's seed")
	eq(a.value and a.value.def.seed, 99, "the area's seed")
end

-- refusals: clear messages, nothing written
do
	local r = gen({biome = "cave", width = 400, height = 300, floors = 1})
	ok(not r.ok and r.error:find("100000", 1, true) ~= nil and r.count == 0, "400 x 300 is refused before writing: "
		.. tostring(r.error))
	r = gen({biome = "cave", width = 200, height = 200, floors = 3})
	ok(not r.ok and r.error:find("floors one by one", 1, true) ~= nil, "120,000 tiles over 3 floors is refused")
	r = gen({biome = "moon", width = 40, height = 40})
	ok(not r.ok and r.error:find("unknown biome moon", 1, true) ~= nil and r.error:find("crypt", 1, true) ~= nil,
		"an unknown biome names the biomes")
	r = gen({biome = "cave", width = 20, height = 40})
	ok(not r.ok and r.error:find("32-400", 1, true) ~= nil, "a too small area is refused")
end

-- the level band's monsters (monsters.lua rows {name, level, boss})
do
	local E = dofile("tools/editor_scripts/cinders_editor.lua")
	local rows = {{"Ash Rat", 120, false}, {"Bone Hound", 160, false}, {"Far Wyrm", 900, false}, {"Grave King", 210, true},
		{"Old King", 2000, true}, {"Cinder Bat", 150, false}}
	local mons, boss = E.pickMonsters(rows, 100, 200)
	eq(#mons, 3, "three monsters near 100-200")
	eq(mons[1][1], "Cinder Bat", "the nearest to the middle first")
	eq(mons[1][2], 3, "with the highest weight")
	eq(boss, "Grave King", "the boss of the band")
	local again = E.pickMonsters(rows, 100, 200)
	eq(again[2][1], mons[2][1], "the same pick again")
	local none = E.pickMonsters(rows, 5000, 5100)
	eq(#none, 0, "no monster far above every level")
	-- a run with a monster table instead of names
	local r = mock.run(GEN, {seed = 3, params = {biome = "cave", width = 40, height = 40, spawnFile = false,
		monsterTable = rows, level = {100, 200}}})
	ok(r.ok, "a run with the monster table: " .. tostring(r.error))
	local seen = {}
	for _, s in ipairs(r.value and r.value.model.spawns or {}) do
		seen[s.monster] = true
	end
	ok(seen["Cinder Bat"] or seen["Bone Hound"] or seen["Ash Rat"], "the spawns use the band's monsters")
	ok(not seen["Far Wyrm"], "no monster outside the band")
end

-- ====================================================================== paint_plan.lua
local base = os.tmpname()
local dir = base .. "_"
local function writeFile(path, text)
	local f = assert(io.open(path, "w"))
	f:write(text)
	f:close()
end
writeFile(dir .. "fixture.lua", [=[
return {
	id = "fixture", name = "Fixture Hollow", biome = "cave", level = {10, 20},
	origin = {x = 500, y = 600, z = 8}, floors = {8, 9},
	tiles = [[
500 600 8 101 1484
501 600 8 101
502 600 8 101 2229 2230
500 601 9 351
501 601 9 351 1386
]],
	frame = [[
499 600 8 101
503 600 8 101
]],
	notes = [[
Monsters (1):
  Rat 501 600 8
]],
}
]=])
writeFile(dir .. "index.lua", 'return {{id = "fixture", name = "Fixture Hollow", tiles = 5, frame = 2, floors = {8, 9}}}\n')

do
	local r = mock.run(PAINT, {params = {plan = "fixture", plansDir = dir}})
	ok(r.ok, "paint: runs (" .. tostring(r.error) .. ")")
	eq(r.count, 7, "paint: tiles and frame")
	eq(r.items, 7 + 4, "paint: grounds and items")
	local t = r.tiles["502:600:8"]
	ok(t and t.ground.id == 101 and #t.items == 2 and t.items[2].id == 2230, "paint: the stack in order")
	eq(r.value and r.value.corner[1], 499, "paint: the corner x (frame included)")
	eq(r.value and r.value.corner[3], 9, "paint: the corner floor is the deepest")
	local said = table.concat(r.log, "\n")
	ok(said:find("Destination X 499, Y 600, floor 9", 1, true) ~= nil, "paint: the log names its own place")
	ok(said:find("Rat 501 600 8", 1, true) ~= nil, "paint: the notes in the log")

	r = mock.run(PAINT, {params = {plan = "fixture", plansDir = dir, frame = false}})
	eq(r.count, 5, "paint: without the frame")
	r = mock.run(PAINT, {params = {plan = "fixture", plansDir = dir, floor = 9}})
	eq(r.count, 2, "paint: one floor")
	-- over the limit: refused with the floors, one floor at a time goes through
	r = mock.run(PAINT, {params = {plan = "fixture", plansDir = dir, limitTiles = 5}})
	ok(not r.ok and r.error:find("set floor", 1, true) ~= nil and r.error:find("z 8: 5 tiles", 1, true) ~= nil
		and r.count == 0, "paint: a plan over the limit names its floors: " .. tostring(r.error))
	r = mock.run(PAINT, {params = {plan = "fixture", plansDir = dir, limitTiles = 5, floor = 8}})
	ok(r.ok and r.count == 5, "paint: one floor under the limit")
	r = mock.run(PAINT, {params = {plan = "fixture", plansDir = dir, floor = 3}})
	ok(not r.ok and r.error:find("its floors: 8, 9", 1, true) ~= nil, "paint: a floor the plan does not have")
	r = mock.run(PAINT, {params = {plan = "missing", plansDir = dir}})
	ok(not r.ok and r.error:find("the plans: fixture", 1, true) ~= nil, "paint: a missing plan lists the plans")
	r = mock.run(PAINT, {params = {plan = false, plansDir = dir}})
	ok(not r.ok and r.error:find("set plan", 1, true) ~= nil, "paint: no plan named")
end
os.remove(dir .. "fixture.lua")
os.remove(dir .. "index.lua")
os.remove(base)

print(string.format("editor_scripts: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
