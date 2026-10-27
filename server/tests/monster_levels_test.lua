-- Run from the server/ folder: luajit tests/monster_levels_test.lua (or lua5.3; CI runs both)
-- Monster levels in the name: monster_levels_core.lua, monster_levels.lua against a mocked engine (a stock monster
-- gets ChaosLoot.monsterLevel as its display level, a level-scaled one keeps its own, a player's summon gets none,
-- an engine without patch 0040 is left alone), the level a rift / invasion / generated area scaled a monster to
-- (Chaos.spawnLevel through Chaos.createMonsterNamed, over its own level) and the engine patches 0040 and 0044.
local failures, count = 0, 0
local MULT = dofile("data/scripts/chaos/pace_config.lua").baseLevelMult -- owner 2026-10-27: pool level x this is shown
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

-- O177: an estimate is shown at most at the top hunting level (a world boss species estimated at 10182); a level a
-- system passes itself (the Infinity Tower's floors) is not clamped
eq(K.displayLevel(0, 10182), 2200, "a huge estimate is clamped to the top hunting level")
eq(K.displayLevel(0, 2200), 2200, "the top level itself is kept")
eq(K.displayLevel(0, 2201), 2200, "one above is clamped")
eq(K.displayLevel(0, 1e9), 2200, "a huge number is clamped")
eq(K.displayLevel(0, 10182, false, 3500), 3500, "a system's own level (tower floor) is not clamped")
do
	local prog = dofile("data/scripts/chaos/progression_config.lua")
	local lim = prog.limits or (prog.progression and prog.progression.limits)
	eq(K.maxEstimate, lim and lim.toLevel, "the clamp is the top level of progression_config.lua")
end

eq(K.huntingLevel(20, 2), 40, "pool level x baseLevelMult")
eq(K.huntingLevel(0, 2), nil, "no pool level: none")
eq(K.huntingLevel(20, nil), 20, "no multiplier: unchanged")

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
eq(hellflayer.shown, 257 * MULT, "Hellflayer: a stock monster shows its hunting level (pool x baseLevelMult)")
-- O177: a world boss species whose estimate is 10182 shows the top hunting level at most (display only)
local kaelgor = mon({pool = 10182})
registered(kaelgor, {x = 1, y = 1, z = 7}, false, false)
eq(kaelgor.shown, 2200, "Kaelgor's estimate 10182 is shown as 2200")
-- Beta 2026-10-27: a monster that is not in the bounty pool, inside a high-level hunt, is shown at the lower end of the
-- hunt (not "level 2"); a listed one keeps its own level; the summon of a monster is shown at least at its master's
do
	local K2 = ChaosMonsterLevelsCore
	local idx = K2.indexHunts({{k = "hunt", x = 1000, y = 1000, z = 7, n = "Hunting: Bone Slicer, Bone Warrior (level 240-320)"},
		{k = "temple", x = 1, y = 1, z = 7, n = "Temple"}})
	eq(K2.areaFloor(idx, 1030, 990, 7), 240, "inside the hunt (60 squares)")
	eq(K2.areaFloor(idx, 1100, 1000, 7), nil, "outside it")
	eq(K2.areaFloor(idx, 1000, 1000, 8), nil, "another floor")
	eq(K2.areaFloor(nil, 1, 1, 7), nil, "no index")
	eq(K2.raise(4, 240), 240, "raised to the floor")
	eq(K2.raise(500, 240), 500, "never lowered")
	eq(K2.raise(4, nil), 4, "no floor")
	eq(K2.bandOf("Hunting: Rat (level 1-20)"), 1, "band of a mark")
	ML = ChaosMonsterLevels
	ML.hunts() -- the real file: loads or stays off
	local savedLoot = ChaosLoot
	ChaosLoot = {monsterLevel = function(m) return m.pool end,
		poolLevelOf = function(m) return m.listed and m.pool or nil end}
	local function put(m, x, y, z)
		m.getPosition = function() return {x = x, y = y, z = z} end
		return m
	end
	-- inject the index through the engine file's own loader: a data file on disk
	local tmp = os.tmpname()
	local f = io.open(tmp, "w")
	f:write('return {marks = {{k = "hunt", x = 1000, y = 1000, z = 7, n = "Hunting: Bone Slicer, Bone Warrior (level 240-320)"}}}')
	f:close()
	ChaosPoiConfig = {dataFile = tmp}
	-- reload the engine file so its cached index is read from the new file
	dofile("data/scripts/chaos/monster_levels.lua")
	local sheep = put(mon({pool = 1}), 1010, 1005, 7)
	registered(sheep, {x = 1010, y = 1005, z = 7}, false, false)
	eq(sheep.shown, 240, "an unlisted monster in a level 240 hunt is shown at the hunt's lower end")
	local listedMon = put(mon({pool = 40, listed = true}), 1010, 1005, 7)
	registered(listedMon, {x = 1010, y = 1005, z = 7}, false, false)
	eq(listedMon.shown, 40 * MULT, "a listed monster keeps its own hunting level")
	local badger = put(mon({pool = 4, listed = true}), 1010, 1005, 7)
	registered(badger, {x = 1010, y = 1005, z = 7}, false, false)
	eq(badger.shown, 240, "a listed monster far below the hunt (under a tenth of its lower end) is raised to it")
	local badger = put(mon({pool = 4, listed = true}), 1010, 1005, 7)
	registered(badger, {x = 1010, y = 1005, z = 7}, false, false)
	eq(badger.shown, 240, "a listed monster far below the hunt (under a tenth of its lower end) is raised to it")
	local far = put(mon({pool = 1}), 5000, 5000, 7)
	registered(far, {x = 5000, y = 5000, z = 7}, false, false)
	eq(far.shown, 1 * MULT, "an unlisted monster far from any hunt: its estimate")
	local boss = mon({own = 300, isMonsterMaster = true})
	boss.isMonster = function() return true end
	boss.getMonsterLevel = function() return 300 end
	local minion2 = put(mon({pool = 6, listed = true, master = boss}), 5000, 5000, 7)
	registered(minion2, {x = 5000, y = 5000, z = 7}, false, false)
	eq(minion2.shown, 300, "the summon of a level 300 monster is shown at 300")
	os.remove(tmp)
	ChaosPoiConfig = nil
	ChaosLoot = savedLoot
end
-- a system's own level (Chaos.spawnLevel: a pocket boss, a tower floor) is shown as given, over the estimate
Chaos.spawnLevel = 300
local pocketBoss = mon({pool = 10182})
registered(pocketBoss, {x = 1, y = 1, z = 7}, false, false)
eq(pocketBoss.shown, 300, "a pocket boss shows the level it was spawned with")
Chaos.spawnLevel = 3500
local floorBoss = mon({pool = 10182})
registered(floorBoss, {x = 1, y = 1, z = 7}, false, false)
eq(floorBoss.shown, 3500, "a tower floor level above 2200 is kept")
Chaos.spawnLevel = nil
-- a generated area's point and a waystone tier are hunting levels already: not multiplied
Mon.getId = function(self) return self.id end
ChaosAreaGen = {pointOf = {[4242] = {level = 333}}}
local pointMon = mon({id = 4242, pool = 20})
registered(pointMon, {x = 1, y = 1, z = 7}, false, false)
eq(pointMon.shown, 333, "a generated area monster shows its point's level, not x baseLevelMult")
ChaosAreaGen = nil
ChaosWaystoneTiers = {levelOf = function(m) return m.tierLevel end}
local wayMon = mon({id = 1, pool = 20, tierLevel = 150})
registered(wayMon, {x = 1, y = 1, z = 7}, false, false)
eq(wayMon.shown, 150, "a waystone monster shows its run's level, not x baseLevelMult")
-- the monster bar chip (monster_tiers.lua) reads ML.estimate when the nameplate level is not set: it must be the level
-- the name would show, on the hunting scale, for a pool monster and a waystone monster alike
eq((ChaosMonsterLevels.estimate(wayMon)), 150, "bar chip estimate: a waystone monster, not doubled")
ChaosWaystoneTiers = nil
eq((ChaosMonsterLevels.estimate(mon({id = 2, pool = 52}))), 52 * MULT, "bar chip estimate: a pool monster is on the hunting scale (Lv 104 vs [540])")
local stag = mon({own = 777, pool = 790})
registered(stag, {x = 1, y = 1, z = 7}, false, false)
eq(stag.shown, nil, "Black Stag keeps the engine's own [777]")
local pet = mon({pool = 40, master = mon({player = true})})
registered(pet, {x = 1, y = 1, z = 7}, false, false)
eq(pet.shown, nil, "a player's summon gets no level")
local minion = mon({pool = 300, master = mon({})})
registered(minion, {x = 1, y = 1, z = 7}, false, false)
eq(minion.shown, 300 * MULT, "a monster's summon shows its level like any monster")
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
eq(ChaosMonsterLevels.apply(bare), 80 * MULT, "loot.lua not loaded: the experience estimate")

-- the scaled level of a rift / invasion / generated area monster: Chaos.spawnLevel, used once in onSpawn
ChaosLoot = {monsterLevel = function(m) return m.pool end}
Chaos.spawnLevel = 150
local riftStag = mon({own = 777, pool = 790})
registered(riftStag, {x = 1, y = 1, z = 7}, false, true)
eq(riftStag.shown, 150, "a level-scaled type in a tier 1 rift shows [150], not its own [777]")
eq(Chaos.spawnLevel, nil, "the scaled level is used once")
local next1 = mon({pool = 257})
registered(next1, {x = 1, y = 1, z = 7}, false, false)
eq(next1.shown, 257 * MULT, "the next monster: its own estimate again")
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
eq(placedLevel, 257 * MULT, "no level: the estimate as at any spawn")
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
-- O177: the scripted boss spawns pass the level of their fight
check(src("data/scripts/chaos/pocketboss.lua"):find("pcall(create, run.boss.monster, P(run.L.bossSpawn), false, true, nil, level)", 1,
	true) ~= nil, "pocketboss.lua spawns the boss with its level")
check(src("data/scripts/chaos/worldboss.lua"):find("Chaos.createMonsterNamed(b.name, P(L.bossSpawn), false, true, nil, C().minLevel)", 1,
	true) ~= nil, "worldboss.lua spawns the boss with the entry level")
check(src("data/scripts/chaos/raid.lua"):find('kind == "boss" and C().minLevel', 1, true) ~= nil, "raid.lua: the boss's level")
check(src("data/scripts/chaos/guildboss.lua"):find("false, true, nil, cfg.minLevel)", 1, true) ~= nil, "guildboss.lua: the boss's level")
check(src("data/scripts/chaos/uber.lua"):find("false, true, nil, def.minLevel)", 1, true) ~= nil, "uber.lua: the boss's level")
check(src("data/scripts/chaos/trials.lua"):find("false, true, nil, scale.level)", 1, true) ~= nil, "trials.lua: the warden's level")
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
