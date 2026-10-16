-- Run from the server/ folder: luajit tests/monster_levels_test.lua (or lua5.3; CI runs both)
-- Monster levels in the name: monster_levels_core.lua, monster_levels.lua against a mocked engine (a stock monster
-- gets ChaosLoot.monsterLevel as its display level, a level-scaled one keeps its own, a player's summon gets none,
-- an engine without patch 0040 is left alone), the level a rift / invasion / generated area scaled a monster to
-- (Chaos.spawnLevel through Chaos.createMonsterNamed, over its own level) and the engine patches 0040 and 0044.
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
eq(K.displayLevel(0, 257, false, 100), 100, "scaled by its system: the scaled level, not the estimate")
eq(K.displayLevel(777, nil, false, 480.4), 480, "scaled: wins over a level of its own (patch 0044)")
eq(K.displayLevel(0, 40, true, 100), nil, "a player's summon: none even when scaled")
eq(K.displayLevel(0, 257, false, 0), 257, "scaled 0: the estimate")
eq(K.displayLevel(777, nil, false, 0 / 0), nil, "scaled NaN, own level: none set")

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

-- the scaled level of a rift / invasion / generated area monster: Chaos.spawnLevel, used once in onSpawn
ChaosLoot = {monsterLevel = function(m) return m.pool end}
Chaos.spawnLevel = 150
local riftStag = mon({own = 777, pool = 790})
registered(riftStag, {x = 1, y = 1, z = 7}, false, true)
eq(riftStag.shown, 150, "a level-scaled type in a tier 1 rift shows [150], not its own [777]")
eq(Chaos.spawnLevel, nil, "the scaled level is used once")
local next1 = mon({pool = 257})
registered(next1, {x = 1, y = 1, z = 7}, false, false)
eq(next1.shown, 257, "the next monster: its own estimate again")
Chaos.spawnLevel = 300
local riftPet = mon({pool = 40, master = mon({player = true})})
registered(riftPet, {x = 1, y = 1, z = 7}, false, true)
eq(riftPet.shown, nil, "a player's summon ignores a scaled level")
eq(Chaos.spawnLevel, nil, "and clears it")

-- Chaos.createMonsterNamed passes shownLevel to that onSpawn, before the placement, and never leaves it set
do
	local n = 0
	local saved = getmetatable(_G)
	setmetatable(_G, {__index = function(t, k)
		if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
	end})
	loadstring = loadstring or load
	Chaos = nil
	dofile("data/scripts/chaos/chaos_constants.lua")
	setmetatable(_G, saved)
end
local placedLevel, placedName
Game = {createMonster = function(typeName, pos, extended, force)
	if typeName == "Nothing" then
		return nil
	end
	if typeName == "Boom" then
		error("engine error")
	end
	local m = mon({own = typeName == "Black Stag" and 777 or 0, pool = 257})
	Chaos.spawnName = nil -- monster_tiers.lua's rename callback
	registered(m, pos, false, true)
	placedLevel = m.shown -- what the first creature packet carries
	return m
end}
local made = Chaos.createMonsterNamed("Black Stag", {x = 1, y = 1, z = 7}, true, false, "Veil Stag", 480)
eq(placedLevel, 480, "createMonsterNamed: the scaled level is set before the placement")
eq(made.shown, 480, "and stays on the monster")
eq(Chaos.spawnLevel, nil, "no level left over")
Chaos.createMonsterNamed("Hellflayer", {x = 1, y = 1, z = 7}, true, false, "Hellflayer", 220)
eq(placedLevel, 220, "the type's own name with a level: still goes through the level")
Chaos.createMonsterNamed("Hellflayer", {x = 1, y = 1, z = 7}, true, false, nil, nil)
eq(placedLevel, 257, "no level: the estimate as at any spawn")
eq(Chaos.createMonsterNamed("Nothing", {}, true, false, nil, 300), nil, "not placed: nil")
eq(Chaos.spawnLevel, nil, "not placed: no level left over")
check(not pcall(Chaos.createMonsterNamed, "Boom", {}, true, false, nil, 300), "an engine error is passed on")
eq(Chaos.spawnLevel, nil, "engine error: no level left over")

-- the systems' scaled levels
dofile("data/scripts/chaos/rift_core.lua")
local R = ChaosRiftCore
local rcfg = {maxTier = 15, tiers = {{minLevel = 100}, {minLevel = 150}}, beyond = {minLevelStep = 25, health = 0,
	damage = 0, reward = 0}}
for _, t in ipairs(rcfg.tiers) do
	t.pick = {1, 2}
end
eq(R.displayLevel(rcfg, 1, true, false), 100, "rift tier 1 (density): the tier's level")
eq(R.displayLevel(rcfg, 4, true, false), 200, "rift tier 4, beyond the table: + 25 a tier")
eq(R.displayLevel(rcfg, 1, false, false), nil, "rift without density: the type's own health, its own level")
eq(R.displayLevel(rcfg, 1, true, true), nil, "an Omen guardian: its own level")
dofile("data/scripts/chaos/invasion_core.lua")
eq(ChaosInvasionCore.displayLevel(420), 420, "invasion: the area level")
eq(ChaosInvasionCore.displayLevel(nil), nil, "invasion without an area: none")
local function src(path)
	local h = io.open(path, "r")
	local t = h and h:read("*a") or ""
	if h then
		h:close()
	end
	return t
end
check(src("data/scripts/chaos/rift.lua"):find("create(name, P(pos), true, false, shown, level)", 1, true) ~= nil,
	"rift.lua passes the run's level at the spawn")
check(src("data/scripts/chaos/invasion.lua"):find("Chaos.spawnLevel = I.displayLevel(state.area and state.area.level)",
	1, true) ~= nil, "invasion.lua sets the area level around Game.createMonster")
check(src("data/scripts/chaos/areagen.lua"):find("create(point.monster, pos, true, false, point.name, point.level)", 1,
	true) ~= nil, "areagen.lua passes the point's level (generated areas and dungeons)")

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

local f44 = io.open("src-patches/0044-display-level-override.patch", "r")
check(f44 ~= nil, "patch 0044 exists")
local p44 = f44 and f44:read("*a") or ""
if f44 then
	f44:close()
end
check(p44:find("+			return displayLevel > 0 ? displayLevel : level;", 1, true) ~= nil,
	"0044: a set display level wins over the own level")
check(p44:find("-			return level > 0 ? level : displayLevel;", 1, true) ~= nil, "0044 replaces 0040's rule")

print(string.format("monster_levels_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
