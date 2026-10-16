-- Run from the server/ folder: luajit tests/monster_levels_test.lua (or lua5.3; CI runs both)
-- Monster levels in the name: monster_levels_core.lua, monster_levels.lua against a mocked engine (a stock monster
-- gets ChaosLoot.monsterLevel as its display level, a level-scaled one keeps its own, a player's summon gets none,
-- an engine without patch 0040 is left alone) and the engine patch 0040 itself.
local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

-- ================================================================== the core
dofile("data/scripts/chaos/monster_levels_core.lua")
local K = ChaosMonsterLevelsCore
eq(K.displayLevel(0, 257.4), 257, "a stock monster shows its estimate")
eq(K.displayLevel(0, 0.2), 1, "at least level 1")
eq(K.displayLevel(777, 250), nil, "a level-scaled monster shows its own level (the engine's)")
eq(K.displayLevel(0, 250, true), nil, "a player's summon shows none")
eq(K.displayLevel(0, nil), nil, "no estimate: none")
eq(K.displayLevel(0, 0 / 0), nil, "NaN: none")

-- ================================================================== the engine file
Chaos = {}
local registered
EventCallback = setmetatable({}, {__newindex = function(t, k, v)
	rawset(t, k, v)
	registered = v
end})
function EventCallback.register() end
ChaosLoot = {monsterLevel = function(m)
	return m.pool -- the bounty pool's hunting level of its type
end}
local Mon = {}
Mon.__index = Mon
function Mon:getMonsterLevel() return self.own or 0 end
function Mon:getMaster() return self.master end
function Mon:isPlayer() return self.player == true end
function Mon:setDisplayLevel(v) self.shown = v end
local function mon(o) return setmetatable(o, Mon) end
dofile("data/scripts/chaos/monster_levels.lua")
check(type(registered) == "function", "onSpawn registered")
local hellflayer = mon({pool = 257})
registered(hellflayer, {x = 1, y = 1, z = 7}, false, false)
eq(hellflayer.shown, 257, "Hellflayer [257]: a stock monster gets a level in its name")
local stag = mon({own = 777, pool = 790})
registered(stag, {x = 1, y = 1, z = 7}, false, false)
eq(stag.shown, nil, "Black Stag keeps the engine's own [777]")
local pet = mon({pool = 40, master = mon({player = true})})
registered(pet, {x = 1, y = 1, z = 7}, false, false)
eq(pet.shown, nil, "a player's summon gets no level")
local minion = mon({pool = 300, master = mon({})})
registered(minion, {x = 1, y = 1, z = 7}, false, false)
eq(minion.shown, 300, "a monster's summon shows its level like any monster")
local old = setmetatable({pool = 257}, {__index = function(t, k)
	if k == "setDisplayLevel" then
		return nil -- an engine without patch 0040
	end
	return Mon[k]
end})
eq(ChaosMonsterLevels.apply(old), nil, "without patch 0040 nothing is set")
ChaosLoot = nil
ChaosItemMods = {estimateMonsterLevel = function(exp, hp) return 1.6 * math.sqrt(exp) end}
local bare = mon({})
function bare:getType() return {getExperience = function() return 2500 end, getMaxHealth = function() return 3000 end} end
eq(ChaosMonsterLevels.apply(bare), 80, "loot.lua not loaded: the experience estimate")

-- ================================================================== the engine patch 0040
local f = io.open("src-patches/0040-monster-display-level.patch", "r")
check(f ~= nil, "patch 0040 exists")
local patch = f and f:read("*a") or ""
if f then
	f:close()
end
check(patch:find('registerMethod("Monster", "setDisplayLevel"', 1, true) ~= nil, "0040 registers setDisplayLevel")
check(patch:find("getDisplayLevel() > 0", 1, true) ~= nil, "0040: the creature packet uses the display level")
check(patch:find("\n%+[^\n]*[Bb]onus") == nil and patch:find("\n%+[^\n]*skull =") == nil,
	"0040 adds no level bonus and no skull")

print(string.format("monster_levels_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
