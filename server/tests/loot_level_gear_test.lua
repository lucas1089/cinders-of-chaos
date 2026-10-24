-- Run from the server/ folder: luajit tests/loot_level_gear_test.lua (and lua5.3; CI runs both)
-- Level gear of the Chaos loot layer (loot.lua L.levelGear, step 1d; data/lib/chaos_gear_sets.lua M.rollLevelGear;
-- server/README.md "Gear beyond level 1000"). Beta 2026-10-24: "the monsters of the highest teleport hall spots (level 2000)
-- drop the same equipment as level 800". A monster type has one loot table whatever level it is spawned at, so the
-- kill's own hunting level now picks a piece of an equipment set near it.

local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

Chaos = {}
MAX_LOOTCHANCE = 100000
EventCallback = setmetatable({register = function() end}, {__newindex = rawset})
function ItemType(id)
	return {isStackable = function() return false end, getName = function() return "item " .. id end}
end
dofile("data/scripts/chaos/loot.lua")
local L = ChaosLoot
ChaosGearSets = dofile("data/lib/chaos_gear_sets.lua")
local G = ChaosGearSets

local function monster(boss)
	return {getType = function() return {isBoss = function() return boss end} end}
end
local function owner(class)
	return {getVocation = function() return {getName = function() return class end} end}
end

-- a roll that always hits picks a piece of the window of the level the kill is hunted at
L.setRandom(function(a, b)
	return a
end)
for _, level in ipairs({800, 1000, 1300, 1700, 2000}) do
	local piece = L.levelGear(monster(false), owner("Warrior"), "normal", {huntLevel = level, itemFind = 1, pace = 1})
	ok(piece ~= nil, "level " .. level .. ": a hit drops a piece")
	if piece then
		ok(piece.level <= level + G.config.open.above and piece.level >= level - G.config.open.below,
			"level " .. level .. ": " .. piece.name .. " (" .. piece.level .. ") is near it")
	end
end
local lo = L.levelGear(monster(false), owner("Warrior"), "normal", {huntLevel = 800, itemFind = 1, pace = 1})
local hi = L.levelGear(monster(false), owner("Warrior"), "normal", {huntLevel = 2000, itemFind = 1, pace = 1})
ok(lo and hi and lo.id ~= hi.id and hi.level >= lo.level + 900, "800 and 2000 drop other pieces")
ok(L.levelGear(monster(false), owner("Warrior"), "normal", {huntLevel = 699, itemFind = 1, pace = 1}) == nil,
	"below level 700: nothing")
ok(L.levelGear(monster(false), owner("Warrior"), "normal", {huntLevel = 0, itemFind = 1, pace = 1}) == nil,
	"no level: nothing")

-- a miss: the roll is above the chance
L.setRandom(function(a, b)
	return b
end)
ok(L.levelGear(monster(false), owner("Warrior"), "normal", {huntLevel = 2000, itemFind = 1, pace = 1}) == nil, "a miss drops nothing")

-- a boss rolls the boss chance: a draw between the normal and the boss chance hits only for the boss
local draw = math.floor((G.levelChance("normal") + G.levelChance("boss")) / 2)
L.setRandom(function(a, b)
	if b == 100000 then
		return draw
	end
	return a
end)
ok(L.levelGear(monster(false), owner("Warrior"), "normal", {huntLevel = 2000, itemFind = 1, pace = 1}) == nil,
	"a normal monster misses that draw")
ok(L.levelGear(monster(true), owner("Warrior"), "normal", {huntLevel = 2000, itemFind = 1, pace = 1}) ~= nil,
	"a boss hits it")

-- the pack factor and item find scale the chance
local base = G.levelChance("normal")
L.setRandom(function(a, b)
	if b == 100000 then
		return math.floor(base * 0.6)
	end
	return a
end)
ok(L.levelGear(monster(false), owner("Warrior"), "normal", {huntLevel = 2000, itemFind = 1, pace = 0.5}) == nil,
	"a pack factor of 0.5 halves the chance")
ok(L.levelGear(monster(false), owner("Warrior"), "normal", {huntLevel = 2000, itemFind = 2, pace = 0.5}) ~= nil,
	"item find x2 gives it back")

-- no sets, no switch: nothing, never an error
local real = ChaosGearSets
ChaosGearSets = nil
ok(L.levelGear(monster(false), owner("Warrior"), "normal", {huntLevel = 2000, itemFind = 1, pace = 1}) == nil, "no gear sets lib")
ChaosGearSets = real
G.PAIR28 = false
L.setRandom(function(a) return a end)
ok(L.levelGear(monster(false), owner("Warrior"), "normal", {huntLevel = 2000, itemFind = 1, pace = 1}) == nil, "switch off: nothing")
G.PAIR28 = true

if fails > 0 then
	error(fails .. " of " .. checks .. " checks failed")
end
print("loot_level_gear_test: " .. checks .. " checks ok")
