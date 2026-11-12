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

-- O517: reachFrom. A tile that fits is also refused when no walk from the origin reaches it (the cursed chest horde
-- stood on a rock ringed by walls: the tile rules alone passed it)
fill("sand", 100, 100, 130, 130)
-- an island: 3x3 good tiles at 110-112 inside a wall ring at 109-113, the origin outside at 105,111
fill("wall", 109, 109, 113, 113)
fill("sand", 110, 110, 112, 112)
local origin = at(105, 111)
eq(S.ok(at(111, 111)), true, "island tile: fits by the tile rules alone")
eq(S.ok(at(111, 111), {reachFrom = origin}), false, "island tile: refused with reachFrom")
eq(select(2, S.ok(at(111, 111), {reachFrom = origin})), "unreachable", "island tile: the reason")
eq(S.ok(at(107, 111), {reachFrom = origin}), true, "an open tile beside the origin is reachable")
eq(S.ok(at(111, 111), {reachFrom = at(110, 110)}), true, "the same tile from inside the island")
-- the origin need not fit itself: a blocked origin (the chest) still seeds the walk
map["105:111"] = "wall"
eq(S.ok(at(107, 111), {reachFrom = origin}), true, "a blocked origin still seeds the walk")
map["105:111"] = "sand"
-- another floor is never reachable
eq(S.ok({x = 107, y = 111, z = 6}, {reachFrom = origin}), false, "another floor: unreachable")
-- find: a random pick never lands on the island, and the centre of an island is refused
for _ = 1, 300 do
	local p = S.find(at(108, 111), {radius = 4, tries = 20, rand = rng, reachFrom = origin, maxPath = 12})
	if p then eq(p.x >= 110 and p.x <= 112 and p.y >= 110 and p.y <= 112, false, "find: never an island tile") end
end
eq(S.find(at(111, 111), {radius = 0, reachFrom = origin}), nil, "find: an island centre is refused")
-- a wall with one gap: the walk goes through it
map["109:111"] = "sand"
eq(S.ok(at(111, 111), {reachFrom = origin}), true, "a gap in the wall: reachable")
fill("wall", 109, 109, 113, 113)
fill("sand", 110, 110, 112, 112)
-- a ring corridor, one tile wide, around 120,120 (a loop of 32 tiles inside walls); cut on the left of the start, the
-- far tile 2 tiles away is reached only round the ring
fill("wall", 114, 114, 126, 126)
for x = 116, 124 do for y = 116, 124 do
	if x == 116 or x == 124 or y == 116 or y == 124 then map[x .. ":" .. y] = "sand" end
end end
map["116:120"] = "wall" -- the loop is cut on the left: the far point is reached only the long way round
local start, far = at(116, 119), at(116, 121)
eq(S.ok(far, {reachFrom = start, maxPath = 40, box = 40}), true, "ring corridor: the long way round is a walk")
eq(S.ok(far, {reachFrom = start, maxPath = 10, box = 40}), false, "ring corridor: too long for maxPath 10")
-- the shortest way counts: round the ring, 30 tiles, the corners cut diagonally
local m1 = S.reachMap(start, {maxPath = 40, box = 40})
eq(m1[S.key(far)], 26, "ring corridor: 26 steps the long way round (corners cut)")
map["116:120"] = "sand"
local m2 = S.reachMap(start, {maxPath = 40, box = 40})
eq(m2[S.key(far)], 2, "ring corridor: 2 steps once the cut is closed")
-- a diagonal step is a step
fill("sand", 100, 100, 104, 104)
local m3 = S.reachMap(at(100, 100), {maxPath = 4})
eq(m3["104:104"], 4, "8 directions: 4 diagonal steps")
-- the bound: maxPath and box cap the tiles looked at, in an open field
local looked = 0
local function countWalk() looked = looked + 1; return true end
local m4, n4 = S.reachMap(at(115, 105), {maxPath = 3, box = 3, walk = countWalk})
eq(n4, 49, "open field: (2 * 3 + 1)^2 tiles at most")
eq(looked <= 49 * 8, true, "walk queries bounded by tiles x 8 directions")
local _, n5 = S.reachMap(at(115, 105), {maxPath = 10, box = 2, walk = countWalk})
eq(n5, 25, "the box caps it before maxPath does")
local _, n6 = S.reachMap(at(115, 105), {maxPath = 1, box = 9, walk = countWalk})
eq(n6, 9, "maxPath 1: the origin and its 8 neighbours")
-- the injected walk query decides, not the tile rules
local _, n7 = S.reachMap(at(115, 105), {maxPath = 3, walk = function(p) return p.x == 115 end})
eq(n7, 7, "injected walk: only the column x = 115, 3 up and 3 down")
-- the map is cached in opts, so a search over a square walks once
local cacheOpts = {reachFrom = origin}
S.ok(at(107, 111), cacheOpts)
local cached = cacheOpts.reach
eq(cached ~= nil, true, "opts.reach holds the map")
S.ok(at(106, 111), cacheOpts)
eq(cacheOpts.reach == cached, true, "and is not rebuilt")
-- protection zone tiles stop the walk unless allowed, like the tile rules
fill("sand", 100, 80, 110, 80)
map["105:80"] = "pz"
eq(S.ok(at(108, 80), {reachFrom = at(102, 80), box = 8}), false, "a protection zone tile in a 1 tile corridor stops the walk")
eq(S.ok(at(108, 80), {reachFrom = at(102, 80), box = 8, protection = true}), true, "and does not when protection is allowed")
eq(S.ok(at(108, 80), {reachFrom = at(102, 80), box = 3, protection = true}), false, "a box of 3 tiles is too small to reach 108 from 102")

print(string.format("spawn_tile_test: %d checks, %d failures", checks, fails))
if fails > 0 then os.exit(1) end
