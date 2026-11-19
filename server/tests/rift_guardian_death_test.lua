-- Run from the server/ folder: luajit tests/rift_guardian_death_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The death of a rift monster reaches the run (O674; live run O671: a guardian was gone with no death event and the run was never sealed).
-- The mocked engine here is as strict as the real one about what a death event needs: a monster's death handler runs only when the handler was
-- registered on the monster BY A NAME A CREATUREEVENT WAS REGISTERED UNDER (Creature::registerCreatureEvent ignores any other name). So: every event
-- name rift.lua registers on a spawned pack monster and on a spawned guardian is a registered CreatureEvent, the death one is on both, the
-- registered handler reaches riftDeath (the run's bookkeeping, the guardian's kill), and a guardian that leaves with no death event is counted by
-- the tick's sweep (RF._sweepGone).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z][A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then fails = fails + 1; print("FAIL " .. what) end
end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

-- ------------------------------------------------------------------ engine mocks
local events = {} -- CreatureEvent name -> the event (what the engine's g_creatureEvents holds)
local function eventMock(kind)
	return function(name)
		local e = setmetatable({name = name, kind = kind}, {__index = function() return function() end end})
		e.register = function() events[name or (kind .. "#" .. tostring(e))] = e end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction, Action, MoveEvent = eventMock("creature"), eventMock("global"), eventMock("talk"),
	eventMock("action"), eventMock("move")
EventCallback = setmetatable({}, {__index = function() return function() end end})
GAME_STATE_NORMAL = 1
db = {query = function() return true end, storeQuery = function() return false end, escapeString = function(s) return "'" .. s .. "'" end}
result = {free = function() end}
local function pos(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end} end
Position = pos
ItemType = function(id) return {getId = function() return id end, getName = function() return "item" .. id end} end
Player = function() return nil end
json = {encode = function() return "{}" end, decode = function() return {} end}
Tile = function() return nil end
addEvent = function() return 0 end

-- a monster as the engine keeps it: the events it was given
local monsters, nextId = {}, 5000
local function newMonster(name, at)
	nextId = nextId + 1
	local m = {id = nextId, name = name, at = at, hp = 1000, max = 1000, registered = {}, look = 1}
	function m:getId() return self.id end
	function m:getName() return self.name end
	function m:getPosition() return self.at end
	function m:getHealth() return self.hp end
	function m:getMaxHealth() return self.max end
	function m:setMaxHealth(v) self.max = v end
	function m:setHealth(v) self.hp = v end
	function m:changeSpeed() end
	function m:setOutfit() end
	function m:getOutfit() return {lookType = self.look} end
	function m:setDropLoot() end
	function m:isMonster() return true end
	-- Creature::registerCreatureEvent: false for a name no CreatureEvent was registered under (the engine ignores it)
	function m:registerEvent(ev)
		if not events[ev] then
			return false
		end
		self.registered[#self.registered + 1] = ev
		return true
	end
	function m:hasEvent(ev)
		for _, e in ipairs(self.registered) do
			if e == ev then
				return true
			end
		end
		return false
	end
	monsters[m.id] = m
	return m
end
Game = {
	getGameState = function() return 1 end,
	createItem = function() return {setActionId = function() end, remove = function() end} end,
	getPlayers = function() return {} end,
	getSpectators = function() return {} end,
	getExperienceStage = function() return 1 end,
	createMonster = function(name, at) return newMonster(name, at) end,
}
Monster = function(id) return monsters[id] end

dofile("data/scripts/chaos/rift.lua")
local RF, R = ChaosRift, ChaosRiftCore
local cfg = ChaosRiftConfig
local death = events.ChaosRiftMonsterDeath
ok(death ~= nil and type(death.onDeath) == "function", "ChaosRiftMonsterDeath is a registered CreatureEvent with an onDeath handler")
ok(events.ChaosRiftMonsterHealth ~= nil, "ChaosRiftMonsterHealth is registered")

-- a run with room for a pack monster and a guardian
local c = R.slotCenter(cfg, 4)
local function newRun(id)
	local fx = R.effects(cfg, {}, 15)
	local run = R.newRun(cfg, os.time(), 10, 8, fx)
	run.fx = fx
	run.id, run.slot, run.key, run.size, run.lives = id, 4, {tier = 10, mods = {}}, 1, 3
	run.L = {start = {x = c.x, y = c.y, z = c.z}, bossSpawn = {x = c.x + 5, y = c.y, z = c.z}, kind = "rooms", floors = {1}}
	run.plan = run.plan or {}
	run.plan.boss = "Crypt Dreadknight"
	run.players, run.state, run.boss, run.killed, run.total, run.bossAt = {}, "running", "waiting", 0, 10, 8
	run.aliveIds, run.bossIds = {}, {}
	RF.runs[4] = run
	return run
end
local run = newRun(1)

local pack = RF._spawnOne(run, "Crypt Bonehulk", pos(c.x + 1, c.y, c.z), nil, false)
local guardian = RF._spawnOne(run, "Crypt Dreadknight", pos(c.x + 5, c.y, c.z), nil, true)
ok(pack ~= nil and guardian ~= nil, "a pack monster and a guardian are spawned")
run.bossIds[guardian:getId()] = true
for _, m in ipairs({pack, guardian}) do
	ok(m:hasEvent("ChaosRiftMonsterDeath"), m:getName() .. ": the death event is registered on the monster")
	ok(m:hasEvent("ChaosRiftMonsterHealth"), m:getName() .. ": the health event is registered on the monster")
	eq(#m.registered, 2, m:getName() .. ": every name rift.lua registers on it is a CreatureEvent of the engine (none ignored)")
	eq(RF.monsterRun[m:getId()], run, m:getName() .. ": the run knows the monster")
end

-- the pack monster
local pid = pack:getId()
monsters[pid] = nil
death.onDeath(pack, nil, nil, nil)
ok(run.aliveIds[pid] == nil and RF.monsterRun[pid] == nil, "a pack monster's death leaves the run's list the same way")

-- the guardian's death reaches the run through the registered handler
local bossKills = {}
local realKilled = R.onBossKilled
R.onBossKilled = function(r) bossKills[#bossKills + 1] = r return "wait" end
local gid = guardian:getId()
monsters[gid] = nil -- the engine removes the creature after its death event
death.onDeath(guardian, nil, nil, nil)
eq(#bossKills, 1, "the handler reached the run: the guardian's kill is counted")
ok(run.bossIds[gid] == nil, "the guardian is off the run's list")
ok(RF.monsterRun[gid] == nil, "and off the run's monsters")
ok(RF.bossDead[gid] == true, "marked as a guardian's death for the loot event")
death.onDeath(guardian, nil, nil, nil)
eq(#bossKills, 1, "a second event for the same death counts nothing (once per monster)")
-- a guardian that leaves with no death event: the tick's sweep counts it, once, only when it is really gone
local run2 = newRun(2)
local g2 = RF._spawnOne(run2, "Crypt Dreadknight", pos(c.x + 5, c.y, c.z), nil, true)
run2.bossIds[g2:getId()] = true
eq(RF._sweepGone(run2), false, "a guardian that stands there is not swept")
eq(#bossKills, 1, "and not counted")
monsters[g2:getId()] = nil -- gone, no death event ran
eq(RF._sweepGone(run2), true, "a guardian gone with no death event is swept")
eq(#bossKills, 2, "counted as killed")
ok(run2.bossIds[g2:getId()] == nil and RF.monsterRun[g2:getId()] == nil, "off the run's lists")
eq(RF._sweepGone(run2), false, "nothing more to sweep afterwards")
-- a pack monster gone with no event (a husk nobody of the run killed) still counts as before
local run3 = newRun(3)
local p3 = RF._spawnOne(run3, "Crypt Bonehulk", pos(c.x + 1, c.y, c.z), nil, false)
monsters[p3:getId()] = nil
eq(RF._sweepGone(run3), true, "a pack monster gone is swept as before")
ok(run3.aliveIds[p3:getId()] == nil, "off the alive list")
-- the tick calls the sweep
local f = io.open("data/scripts/chaos/rift.lua")
local src = f:read("*a")
f:close()
ok(src:find("RF._sweepGone(run)", 1, true) ~= nil, "the tick runs the sweep")

R.onBossKilled = realKilled
print(string.format("rift_guardian_death_test: %d checks, %d failures", checks, fails))
if fails > 0 then os.exit(1) end
