-- Run from the server/ folder: luajit tests/loot_tower_test.lua && lua5.3 tests/loot_tower_test.lua
-- O328: an Infinity Tower monster loots at the level of its floor. loot.lua ChaosLoot.monsterLevel takes at least
-- ChaosTowerRun.lootLevelOf, and L.corpseFactors / the pace multiplier of a kill read ChaosTowerRun.lootFactorsOf when the
-- monster has no pace factors of its own. The tower side: tests/infinitytower_run_test.lua, infinitytower_balance_test.lua.
EventCallback = setmetatable({register = function() end}, {__newindex = rawset})
Chaos = {}
MAX_LOOTCHANCE = 100000
function ItemType(id)
	return {isStackable = function() return false end, getName = function() return "item " .. id end}
end
dofile("data/scripts/chaos/loot.lua")
dofile("data/scripts/chaos/pace_core.lua")
ChaosPaceConfig = dofile("data/scripts/chaos/pace_config.lua")

local checks, failed = 0, 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		failed = failed + 1
		print("FAIL " .. m .. ": " .. tostring(a) .. " ~= " .. tostring(b))
	end
end

local function monster(name)
	return {getName = function() return name end, getMonsterLevel = function() return 0 end, getId = function() return 1 end}
end

local troll = monster("Troll")
eq(ChaosLoot.monsterLevel(troll), 7, "a troll outside the tower is level 7")

ChaosTowerRun = {lootLevelOf = function() return 1200 end}
eq(ChaosLoot.monsterLevel(troll), 1200, "a tower troll loots at its floor's level")
ChaosTowerRun = {lootLevelOf = function() return 3 end}
eq(ChaosLoot.monsterLevel(troll), 7, "never below the species' own level")
ChaosTowerRun = {lootLevelOf = function() return nil end}
eq(ChaosLoot.monsterLevel(troll), 7, "a monster that is not in the tower keeps its level")
ChaosTowerRun = {lootLevelOf = function() error("broken") end}
eq(ChaosLoot.monsterLevel(troll), 7, "a failing tower hook leaves the level alone")

-- corpse factors: none for an ordinary unpaced monster, the tower's for a tower monster
ChaosTowerRun = nil
eq(ChaosLoot.corpseFactors(troll, 1), nil, "an unpaced monster has no corpse factors")
ChaosTowerRun = {lootFactorsOf = function() return {loot = 0.3, coins = 0.5, notable = 0.4, junkKeep = 1.2} end}
local f = ChaosLoot.corpseFactors(troll, 1)
eq(f and f.loot, 0.3, "a tower monster is thinned by its floor's loot factor")
eq(f and f.coins, 0.5, "and its coins factor")
eq(f and f.notable, 0.4, "and its notable share")
ChaosTowerRun = {lootFactorsOf = function() return {loot = 1, coins = 1, notable = 1} end}
eq(ChaosLoot.corpseFactors(troll, 1), nil, "factors of 1 leave the corpse whole")
ChaosTowerRun = {lootFactorsOf = function() error("broken") end}
eq(ChaosLoot.corpseFactors(troll, 1), nil, "a failing tower hook leaves the corpse alone")

print(string.format("loot_tower_test: %d checks, %d failed", checks, failed))
if failed > 0 then
	os.exit(1)
end
