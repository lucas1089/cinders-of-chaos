-- Run from the server/ folder: luajit tests/spawn_tile_test.lua (or lua5.3; CI runs both)
-- spawn_tile_core.lua against a mocked map with water: a land monster is never placed on water (beach report: Ogre Rowdy
-- [104] standing in the sea), on a blocked, floor change, teleport or protection zone tile, and the search is bounded.
dofile("data/scripts/chaos/spawn_tile_core.lua")
local S = ChaosSpawnTile

local checks, fails = 0, 0
local function eq(a, b, label)
	checks = checks + 1
	if a ~= b then
		fails = fails + 1
		print("FAIL " .. label .. ": got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

TILESTATE_PROTECTIONZONE, TILESTATE_FLOORCHANGE, TILESTATE_TELEPORT, TILESTATE_TRASHHOLDER, TILESTATE_BLOCKSOLID = 1, 2, 4, 8, 16
CONST_PROP_BLOCKSOLID, CONST_PROP_IMMOVABLEBLOCKSOLID = 1, 2

-- map: kind per "x:y" ("sand", "swim" fluid ground, "trash" trash holder flag, "deep" blocking, "pz", "stairs", "tp", "house",
-- "crowd", "wall"); a missing key is no tile, "void" a tile without ground
local map = {}
local function key(p) return p.x .. ":" .. p.y end
function Tile(p)
	local kind = map[key(p)]
	if not kind then return nil end
	local flags = {pz = TILESTATE_PROTECTIONZONE, stairs = TILESTATE_FLOORCHANGE, tp = TILESTATE_TELEPORT, trash = TILESTATE_TRASHHOLDER,
		deep = TILESTATE_BLOCKSOLID}
	return {
		getGround = function()
			if kind == "void" then return nil end
			return {getType = function() return {getFluidSource = function() return (kind == "swim" or kind == "deep") and 1 or 0 end} end}
		end,
		hasFlag = function(_, f) return flags[kind] == f end,
		hasProperty = function(_, f) return (kind == "deep" or kind == "wall") and f == CONST_PROP_BLOCKSOLID end,
		getHouse = function() return kind == "house" and {} or nil end,
		getCreatureCount = function() return kind == "crowd" and 1 or 0 end,
	}
end
local function fill(kind, x1, y1, x2, y2)
	for x = x1, x2 do for y = y1, y2 do map[x .. ":" .. y] = kind end end
end
local function at(x, y) return {x = x, y = y, z = 7} end

fill("sand", 0, 0, 20, 20)
map["1:1"], map["2:1"], map["3:1"], map["4:1"] = "swim", "trash", "deep", "void"
map["5:1"], map["6:1"], map["7:1"], map["8:1"], map["9:1"], map["10:1"] = "pz", "stairs", "tp", "house", "crowd", "wall"

eq(S.ok(at(0, 0)), true, "sand is fine")
eq(select(2, S.ok(at(1, 1))), "water", "swimmable water (fluid source ground)")
eq(select(2, S.ok(at(2, 1))), "water", "a trash holder ground is water")
eq(S.ok(at(3, 1)), false, "deep water")
eq(select(2, S.ok(at(4, 1))), "no ground", "a tile without ground")
eq(select(2, S.ok(at(99, 99))), "no ground", "no tile")
eq(select(2, S.ok(at(5, 1))), "protection zone", "protection zone")
eq(S.ok(at(5, 1), {protection = true}), true, "protection zone when allowed")
eq(S.ok(at(6, 1)), false, "floor change")
eq(S.ok(at(7, 1)), false, "teleport")
eq(select(2, S.ok(at(8, 1))), "house", "house")
eq(select(2, S.ok(at(9, 1))), "occupied", "occupied")
eq(S.ok(at(9, 1), {occupied = true}), true, "occupied when allowed")
eq(select(2, S.ok(at(10, 1))), "blocked", "blocking item")
eq(S.ok(at(1, 1), {water = true}), true, "a water monster may use water")

-- find: the centre when it fits, else a tile around it; never water
eq(S.find(at(0, 0)).x, 0, "centre fits: the centre")
local sea = {}
fill("swim", 10, 10, 20, 20)
local rngState = 7
local function rng(a, b) rngState = (rngState * 1103515245 + 12345) % 2147483648; return a + rngState % (b - a + 1) end
for _ = 1, 200 do
	local p = S.find(at(10, 10), {radius = 3, rand = rng, tries = 30})
	sea[#sea + 1] = p
	if p then eq(Tile(p) ~= nil and S.ok(p), true, "a found tile is ok") end
end
local land = 0
for _, p in ipairs(sea) do if p then land = land + 1 end end
eq(land > 0, true, "the shore tiles around a beach centre are found")
for _, p in ipairs(sea) do if p then eq(p.x < 10 or p.y < 10, true, "never a sea tile") end end
-- an all-water neighbourhood: nil after a bounded number of tries
fill("swim", 12, 12, 20, 20)
local calls = 0
eq(S.find(at(16, 16), {radius = 2, tries = 12, rand = function(a, b) calls = calls + 1; return a end}), nil, "all water: skip the spawn")
eq(calls, 24, "bounded: 12 tries, two rolls each")
-- minRadius: the centre is not taken
eq(S.find(at(0, 0), {radius = 1, minRadius = 1, rand = function() return 0 end, tries = 5}), nil, "minRadius: a zero offset is never taken")
local ring = S.find(at(0, 0), {radius = 3, minRadius = 2, rand = function(a, b) return b end, tries = 3})
eq(ring.x, 3, "minRadius: a tile at least 2 away")

print(string.format("spawn_tile_test: %d checks, %d failures", checks, fails))
if fails > 0 then os.exit(1) end
