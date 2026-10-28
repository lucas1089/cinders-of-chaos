-- Run from the server/ folder: luajit tests/stock_level_range_test.lua (or lua5.3; CI runs both)
-- O163: a type written in Lua with a stock level range (getLevel {minLevel = 1, maxLevel = 10}) next to the stats of a
-- level 150+ monster (Giant Hornet, Reflect Spider, Venom Spider ...). The engine rolled a level of 1-10 for it, and
-- that "level 3" showed in its name ("Giant Hornet [3]") and fed the pace, loot, orb, waystone and goblin layers while
-- the Grimeleech next to it showed [158]. loot.lua L.ownLevel tells such a roll from a real level (the bounty pool level
-- of a not level-scaled type equals the estimate of its experience and health). One mocked-engine case per spawn path:
-- the name at the spawn (monster_levels.lua), the loot / orb / waystone level (loot.lua), the pace layer (pace.lua);
-- tests/areagen_test.lua has the case of the level a generated area scales from.
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

Chaos = {}
MAX_LOOTCHANCE = 100000
local cbList, events = {}, {}
CreatureEvent = function(name)
	local ev = {name = name}
	function ev:register() events[name] = ev end
	return ev
end
EventCallback = setmetatable({}, {
	__newindex = function(t, k, v) rawset(t, "_pending", {k, v}) end,
	__index = function(t, k)
		if k == "register" then
			return function(self, index)
				local pend = rawget(self, "_pending")
				cbList[#cbList + 1] = {kind = pend[1], fn = pend[2], index = index or 0}
				rawset(self, "_pending", nil)
			end
		end
	end
})
function ItemType(id)
	return {isStackable = function() return false end, getName = function() return "item " .. id end}
end
addEvent = function(fn, ms, ...) end
os.mtime = function() return 100000 end
Game = {getSpectators = function() return {} end}
Monster = function() return nil end
ChaosAreaGen = {pointOf = {}}

dofile("data/lib/chaos_item_mods.lua")
dofile("data/scripts/chaos/loot.lua")
local L = ChaosLoot
dofile("data/scripts/chaos/monster_levels.lua")
dofile("data/scripts/chaos/pace.lua")
local PC = ChaosPace
local pool = dofile("data/scripts/chaos/bounty_pool.lua")
local function poolEntry(name)
	for _, list in ipairs({pool.hunt, pool.bosses}) do
		for _, e in ipairs(list) do
			if e.name == name then
				return e
			end
		end
	end
end

local hornetPool = poolEntry("Giant Hornet")
local spiderPool = poolEntry("Reflect Spider")
local leechPool = poolEntry("Grimeleech")
check(hornetPool and spiderPool and leechPool, "the three types of the report are in the bounty pool")
eq(ChaosItemMods.estimateMonsterLevel(hornetPool.exp, hornetPool.health), hornetPool.level, "Giant Hornet: pool level = estimate")

-- a level-scaled type: the pool level is the middle of its range, not the estimate of its stats
local scaled
for _, e in ipairs(pool.hunt) do
	if ChaosItemMods.estimateMonsterLevel(e.exp, e.health) ~= e.level then
		scaled = e
		break
	end
end
check(scaled ~= nil, "the pool has a level-scaled type")

local Mon = {}
Mon.__index = Mon
function Mon:getMonsterLevel() return self.own or 0 end
function Mon:getMaster() return nil end
function Mon:isPlayer() return false end
function Mon:isMonster() return true end
function Mon:setDisplayLevel(v) self.shown = v end
function Mon:getName() return self.name end
function Mon:getId() return self.id end
function Mon:getType()
	return {isBoss = function() return false end, isRewardBoss = function() return false end,
		getExperience = function() return 1 end, getMaxHealth = function() return 1 end}
end
function Mon:getMaxHealth() return 1000 end
function Mon:getHealth() return 1000 end
function Mon:registerEvent() end
local nextId = 1
local function mon(name, own)
	nextId = nextId + 1
	return setmetatable({name = name, own = own, id = nextId}, Mon)
end

-- loot.lua: the level the loot, orb, waystone, damage and goblin layers read
eq(L.ownLevel(mon("Giant Hornet", 3)), 0, "Giant Hornet rolled 3: no real level of its own")
eq(L.ownLevel(mon("Reflect Spider", 9)), 0, "Reflect Spider rolled 9: no real level of its own")
eq(L.ownLevel(mon("Grimeleech", 0)), 0, "no engine level: none")
eq(L.ownLevel(mon(scaled.name, 950)), 950, "a level-scaled type keeps its engine level")
eq(L.baseMonsterLevel(mon("Giant Hornet", 3)), hornetPool.level, "Giant Hornet: item / orb / waystone level = its hunting level, not 3")
eq(L.monsterLevel(mon("Reflect Spider", 9)), spiderPool.level, "Reflect Spider: monster level = hunting level, not 9")
eq(L.monsterLevel(mon("Grimeleech", 0)), leechPool.level, "Grimeleech: unchanged")
eq(L.monsterLevel(mon(scaled.name, 950)), 950, "a level-scaled type: its own level")

-- monster_levels.lua: the name at the spawn
local spawn
for _, c in ipairs(cbList) do
	if c.kind == "onSpawn" and c.index == 50 then
		spawn = c.fn
	end
end
check(spawn ~= nil, "monster_levels.lua registered its onSpawn")
local hornet = mon("Giant Hornet", 3)
spawn(hornet, {x = 1, y = 1, z = 8}, false, false)
eq(hornet.shown, hornetPool.level * (ChaosPaceConfig.baseLevelMult or 1), "Giant Hornet [3] shows its hunting level (pool x baseLevelMult)")
local spider = mon("Reflect Spider", 9)
spawn(spider, {x = 1, y = 1, z = 8}, false, false)
eq(spider.shown, spiderPool.level * (ChaosPaceConfig.baseLevelMult or 1), "Reflect Spider [9] shows its hunting level (pool x baseLevelMult)")
local leech = mon("Grimeleech", 0)
spawn(leech, {x = 1, y = 1, z = 8}, false, false)
eq(leech.shown, leechPool.level * (ChaosPaceConfig.baseLevelMult or 1), "Grimeleech [158]: its hunting level")
local stag = mon(scaled.name, 950)
spawn(stag, {x = 1, y = 1, z = 8}, false, false)
eq(stag.shown, nil, "a level-scaled type keeps the engine's own level in the name")
Chaos.spawnLevel = 480
local riftHornet = mon("Giant Hornet", 3)
spawn(riftHornet, {x = 1, y = 1, z = 8}, false, true)
eq(riftHornet.shown, 480, "a rift / invasion / area spawn: the level its system scaled it to")

-- pace.lua: the curve set and the level of a map spawn
local lv, isScaled = PC.levelOf(mon("Giant Hornet", 3))
eq(lv, hornetPool.level * (ChaosPaceConfig.baseLevelMult or 1), "pace: Giant Hornet is paced at its hunting level, not level 3")
eq(isScaled, false, "pace: on the base curves, like the Grimeleech")
lv, isScaled = PC.levelOf(mon("Grimeleech", 0))
eq(lv, leechPool.level * (ChaosPaceConfig.baseLevelMult or 1), "pace: Grimeleech unchanged")
lv, isScaled = PC.levelOf(mon(scaled.name, 950))
eq(lv, 950, "pace: a level-scaled type at its own level")
eq(isScaled, true, "pace: on the scaled curves")

print(string.format("stock_level_range: %d checks, %d failed", count, failures))
os.exit(failures == 0 and 0 or 1)
