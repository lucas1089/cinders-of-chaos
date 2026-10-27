-- Run from the server/ folder: lua5.3 tests/infinitytower_run_test.lua (mock engine API; CI runs it)
local n = 0
setmetatable(_G, {__index = function(t, k)
  if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
Chaos = {storage = {}, tables = {}, passive = {}, tower = {}}
ChaosOpcodes = {}

local registry = {}
function CreatureEvent(name) local o = {}; function o:register() registry[name] = o end; return o end

-- event queue: addEvent(fn, delay, ...) runs when flush() is called
local queue, clock = {}, 0
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, args = {...}, due = clock + delay}; return #queue end
-- advance the virtual clock by `ms` and run every event that became due, in time order
local function advance(ms)
  local limit = clock + ms
  while true do
    local best
    for i, e in ipairs(queue) do if e.due <= limit and (not best or e.due < queue[best].due) then best = i end end
    if not best then break end
    local e = table.remove(queue, best); clock = e.due; e.fn((table.unpack or unpack)(e.args))
  end
  clock = limit
end

Position = function(x, y, z) return {x = x, y = y, z = z, getDistance = function(self, o) return math.max(math.abs(self.x - o.x), math.abs(self.y - o.y)) end, sendMagicEffect = function() end} end

local tiles, monsters, nextId = {}, {}, 100
local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
local function mkTile(p)
  local t = {pos = p, items = {}, creatures = {}}
  function t:getGround() return self.ground end
  function t:addItem(id) if not self.ground then self.ground = id end; self.items[#self.items + 1] = {id = id, remove = function() end}; return true end
  function t:getItemById(id) for _, i in ipairs(self.items) do if i.id == id then return i end end end
  function t:getCreatures() return self.creatures end
  function t:getItems() return {} end
  return t
end
Game = {}
function Game.createTile(p) local k = key(p); tiles[k] = tiles[k] or mkTile(p); return tiles[k] end
function Tile(p) return tiles[key(p)] end
function Game.createItem(id, count, p) local t = tiles[key(p)]; if t then t:addItem(id) end; return true end
local created = {}
function Game.createMonster(name, pos)
  nextId = nextId + 1
  local m = {spawnLevel = Chaos.spawnLevel, id = nextId, name = name, events = {}, removed = false, hp = 1000, maxHp = 1000}
  function m:getId() return self.id end
  function m:getMaxHealth() return self.maxHp end
  function m:setMaxHealth(v) self.maxHp = v end
  function m:setHealth(v) self.hp = v end
  function m:isMonster() return true end
  function m:registerEvent(e) self.events[e] = true end
  function m:remove() self.removed = true end
  monsters[m.id] = m; created[#created + 1] = m
  local tile = tiles[key(pos)]; if tile then tile.creatures[#tile.creatures + 1] = m end
  return m
end
function MonsterType(name) return name ~= "ghost-of-nothing" end
-- the stock tier multiplies the health by its hp (monster_tiers.lua ChaosTiers)
ChaosTiers = {magic = {hp = 2.0}, rare = {hp = 3.5}, legendary = {hp = 6.0}}
ChaosApplyTier = function(m, tier) m.tier = tier; m.maxHp = math.floor(m.maxHp * ChaosTiers[tier].hp); m.hp = m.maxHp; return true end

local recorded = {}
ChaosTower = {canEnter = function() return true end, recordRun = function(p, floors, secs) recorded[#recorded + 1] = {name = p.name, floors = floors} end}

local function mkPlayer(id, name, level)
  local p = {id = id, name = name, level = level or 200, pos = Position(10, 10, 7), events = {}, msgs = {}, money = 0}
  function p:getId() return self.id end
  function p:getGuid() return self.id end
  function p:getName() return self.name end
  function p:getLevel() return self.level end
  function p:getParty() return nil end
  function p:getPosition() return self.pos end
  function p:teleportTo(pos) self.pos = pos end
  function p:registerEvent(e) self.events[e] = true end
  function p:unregisterEvent(e) self.events[e] = nil end
  function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
  function p:sendCancelMessage(t) self.cancel = t end
  function p:getCondition() return nil end
  function p:addMoney(m) self.money = self.money + m end
  p.bank = 0
  function p:getBankBalance() return self.bank end
  function p:setBankBalance(v) self.bank = v end
  p.items, p.storage = {}, {}
  function p:getStorageValue(k) return self.storage[k] or -1 end
  function p:setStorageValue(k, v) self.storage[k] = v end
  -- this engine's addHealth: (damage type, amount); a one-argument call does nothing
  p.hp = 50
  function p:addHealth(t, v) if type(t) == "string" then self.hp = math.min(100, self.hp + v) end end
  function p:addMana() end
  function p:getMaxHealth() return 100 end function p:getHealth() return self.hp end
  function p:getMaxMana() return 100 end function p:getMana() return 50 end
  function p:getTown() return {getTemplePosition = function() return Position(1, 1, 7) end} end
  return p
end
local players = {}
function Player(id) return players[id] end
Chaos.decode = function() end
-- the real Chaos.heal (chaos_constants.lua returns early while Chaos exists, so load it into a fresh table)
do local stub = Chaos; Chaos = nil; dofile("data/scripts/chaos/chaos_constants.lua"); stub.heal = Chaos.heal; Chaos = stub end
Chaos.giveItem = function(p, id, n) p.items[id] = (p.items[id] or 0) + n; return n end
ChaosTower.currentSeason = function() return 7 end
local lootCallbacks = {}
EventCallback = setmetatable({}, {__index = function() return nil end})
function EventCallback:register() lootCallbacks[#lootCallbacks + 1] = self.onDropLoot end
ItemType = function() return {isStackable = function() return true end} end

dofile("data/scripts/chaos/infinitytower_run.lua")
local assertEq = function(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

-- ---- floor planner
local det = function() return 1 end -- rng that always returns 1: legendary tier, first pool entry
local p1 = ChaosTowerFloorPlan(1, 1, det)
assertEq(p1.boss, false, "floor 1 not boss")
assertEq(#p1.spawns, 4, "floor 1 count")
assertEq(p1.spawns[1].name, "troll", "band 1 pool")
local p10 = ChaosTowerFloorPlan(10, 1, det)
assertEq(p10.boss, true, "floor 10 boss")
assertEq(p10.spawns[1].boss, true, "boss first")
assertEq(p10.spawns[1].name, "the ashen count", "first boss (the order of infinitytower_balance_config.lua)")
assertEq(ChaosTowerFloorPlan(20, 1, det).spawns[1].name, "the grey widow", "second boss")
assertEq(p10.spawns[1].health, ChaosTowerBalance.bossHealth[10], "the boss has the health of its floor")
assertEq(p1.spawns[1].health, math.floor(ChaosTowerBalance.health[1][2] * ChaosTowerBalance.sawtooth[1]), "floor 1 health: the curve x the sawtooth")
assertEq(p1.spawns[1].tier, "magic", "floor 1: a roll of 1 is inside the 5% of magic")
assertEq(ChaosTowerFloorLimit(9), 300, "a floor has floorTimeLimit")
assertEq(ChaosTowerFloorLimit(10), 600, "a boss floor has twice the time")
assertEq(ChaosTowerFloorLimit(90), 600, "the floor 90 boss too")
assertEq(#ChaosTowerFloorPlan(1, 3, det).spawns, 8, "party size adds monsters")
assertEq(#ChaosTowerFloorPlan(301, 1, det).spawns, 9, "count cap (the last point of the count curve)")
assertEq(ChaosTowerFloorPlan(100, 1, det).spawns[2].tier, "legendary", "high floors roll tiers")

-- ---- a run
local a = mkPlayer(1, "Alice"); players[1] = a
assertEq(ChaosTowerRun.start(a), true, "start")
assert(a.events["ChaosTowerPlayerDeath"], "death event registered")
assert(Tile(a.pos) and a.pos.x >= 2000, "teleported into the arena")
assertEq(ChaosTowerRun.start(a), false, "cannot start twice")
advance(6000) -- start delay -> floor 1
assertEq(#created, 4, "floor 1 spawned 4 monsters")
for _, m in ipairs(created) do assert(m.events["ChaosTowerMonsterDeath"], "monster hook") end
local ev = registry["ChaosTowerMonsterDeath"]
for i = 1, 4 do ev.onDeath(created[i]) end
assertEq(a.bank, 50, "floor gold goes to the bank")
assertEq(a.money, 0, "no floor gold in the backpack")
assertEq(a.hp, 75, "half the missing health back after a floor")
-- Chaos.heal: at most the missing health, the stock one-argument signature as the fallback, nothing at full health
local s = {hp = 90}
function s:getHealth() return self.hp end function s:getMaxHealth() return 100 end
function s:addHealth(v) if type(v) == "number" then self.hp = self.hp + v end end
assertEq(Chaos.heal(s, 50.7), 10, "heal clamped to the missing health"); assertEq(s.hp, 100, "stock signature")
assertEq(Chaos.heal(s, 5), 0, "nothing at full health"); assertEq(Chaos.heal(nil, 5), 0, "no creature")
advance(7000) -- next floor delay -> floor 2
assertEq(#created, 4 + 4, "floor 2 spawned")
-- Alice dies on floor 2: run ends with 1 cleared floor
registry["ChaosTowerPlayerDeath"].onDeath(a)
assertEq(recorded[#recorded].floors, 1, "recorded cleared floors")
assertEq(ChaosTowerRun.activeRuns(), 0, "run closed")
assertEq(created[#created].removed, true, "arena monsters removed")

-- ---- leave and level gate
local b = mkPlayer(2, "Bob", 50); players[2] = b
assertEq(ChaosTowerRun.start(b), false, "level gate")
b.level = 150
assertEq(ChaosTowerRun.start(b), true, "start b")
assertEq(ChaosTowerRun.leave(b), true, "leave")
assertEq(b.pos.x, 10, "back at the entry position")
assertEq(recorded[#recorded].floors, 0, "left with no floors")
assertEq(ChaosTowerRun.activeRuns(), 0, "no runs left")

-- ---- time limit
local c = mkPlayer(3, "Cy"); players[3] = c
ChaosTowerRun.start(c)
advance(6000) -- floor 1
local before = #recorded
advance(301000) -- time limit fires
assertEq(ChaosTowerRun.activeRuns(), 0, "time limit ends the run")
assertEq(#recorded, before + 1, "time limit records")

-- ---- logout inside the tower
local d = mkPlayer(4, "Di"); players[4] = d
ChaosTowerRun.start(d)
registry["ChaosTowerLogout"].onLogout(d)
assertEq(ChaosTowerRun.activeRuns(), 0, "logout ends the run")
-- login inside the arena goes to the temple
local e = mkPlayer(5, "Ed"); players[5] = e; e.pos = Position(2000, 2005, 7)
assertEq(registry["ChaosTowerLogin"], nil, "the run file does not reuse infinitytower.lua's login event name")
registry["ChaosTowerRunLogin"].onLogin(e)
assertEq(e.pos.x, 1, "stuck player sent to the temple")
-- the engine keeps only the first creature event of a name: the two tower files must not share one
local names = {}
for _, f in ipairs({"data/scripts/chaos/infinitytower.lua", "data/scripts/chaos/infinitytower_run.lua"}) do
	local h = assert(io.open(f, "r"))
	for name in h:read("*a"):gmatch('CreatureEvent%("([^"]+)"%)') do
		assertEq(names[name], nil, "creature event name used twice: " .. name)
		names[name] = f
	end
	h:close()
end
assertEq(names["ChaosTowerLogin"], "data/scripts/chaos/infinitytower.lua", "ChaosTowerLogin stays infinitytower.lua's")
-- ---- instance limits (instance_limits.lua, server/README.md "Instance limits"): the whole run's time limit with its
-- warnings, the floor warnings, the cap with the waiting line, the staff list and close
do
  local base = 1000000
  os.time = function() return base + math.floor(clock / 1000) end -- luacheck: ignore
  CreatureEvent = function(name) local o = {}; function o:register() registry[name] = o end; function o:type() end; return o end
  Chaos.instanceOrder, Chaos.instances = {}, {}
  Chaos.registerInstance = function(k, d) if not Chaos.instances[k] then Chaos.instanceOrder[#Chaos.instanceOrder + 1] = k end; Chaos.instances[k] = d end
  Chaos.inAnyInstance = function(p) return ChaosTowerRun.isInside(p) and "tower" or nil end
  Chaos.staffCommand = function() return true, true end
  local byId = Player
  Player = function(k) if type(k) == "string" then for _, p in pairs(players) do if p.name == k then return p end end return nil end return byId(k) end
  dofile("data/scripts/chaos/instance_limits.lua")
  dofile("data/scripts/chaos/infinitytower_run.lua") -- again, now with the registry
  local cfg = ChaosTowerRunConfig
  cfg.runTimeLimit = 400
  cfg.limits.maxRuns = 1
  local f = mkPlayer(6, "Fay"); players[6] = f
  assertEq(ChaosTowerRun.start(f), true, "limits: start")
  local g = mkPlayer(7, "Gus"); players[7] = g
  assertEq(ChaosTowerRun.start(g), false, "limits: the cap refuses a second run")
  assert(g.cancel:find("All tower arenas are busy. Try again in ~7 min. You are 1st in line", 1, true), "limits: busy text: " .. g.cancel)
  local function said(p, text) for _, m in ipairs(p.msgs) do if m:find(text, 1, true) then return true end end return false end
  local start = clock
  advance(100000) -- 100 s: 300 s of the run left
  assert(said(f, "Infinity Tower: 5 minutes left"), "limits: run warning at 5 minutes")
  advance(146000) -- 246 s: floor 1 began at 5 s, 59 s of it left
  assert(said(f, "Floor 1: 1 minute left"), "limits: floor warning at 1 minute")
  local floorMonsters = {}
  for _, m in ipairs(created) do if not m.removed and not m.dead then floorMonsters[#floorMonsters + 1] = m end end
  for _, m in ipairs(floorMonsters) do m.dead = true; registry["ChaosTowerMonsterDeath"].onDeath(m) end
  advance(94000) -- 340 s
  assert(said(f, "Infinity Tower: 1 minute left"), "limits: run warning at 1 minute")
  local before = #recorded
  advance(61000) -- 401 s: the run's limit
  assertEq(ChaosTowerRun.activeRuns(), 0, "limits: the run limit ends the run")
  assert(said(f, "Time is up: your tower run ends here."), "limits: told why")
  assertEq(recorded[#recorded].floors, 1, "limits: the cleared floor is recorded")
  assertEq(#recorded, before + 1, "limits: recorded once")
  assertEq(f.pos.x, 10, "limits: back where the run began")
  assert(said(g, "A place in the Infinity Tower is free now"), "limits: the first in line is told")
  -- staff: listed with the time left, closed by slot
  assertEq(ChaosTowerRun.start(g), true, "limits: the one in line starts")
  local list = ChaosInstanceLimits.runs()
  assertEq(#list, 1, "limits: one run listed")
  assertEq(list[1].key, "tower", "limits: by type")
  assertEq(list[1].left, 400, "limits: time left")
  local okc = Chaos.instances.tower.close(list[1].id)
  assertEq(okc, true, "limits: staff close")
  assertEq(ChaosTowerRun.activeRuns(), 0, "limits: closed")
  assert(said(g, "A gamemaster closed the tower run."), "limits: told")
  cfg.runTimeLimit, cfg.limits.maxRuns = 3600, 16
  local _ = start
end

-- ---- O144: floor health, tier health, damage factor, floor rewards, tower drops
do
  local BC = ChaosTowerBalance
  advance(30000) -- the events the blocks above left (a start delay of a closed run) fire with nobody inside
  local first = #created
  local alive = function() local out = {} for i = first + 1, #created do local m = created[i]; if not m.removed and not m.dead then out[#out + 1] = m end end return out end
  local h = mkPlayer(8, "Hal", 300); players[8] = h
  assertEq(ChaosTowerRun.start(h), true, "O144: start")
  local joined = table.concat(h.msgs, "|")
  assert(joined:find("Next reward: floor 5, ", 1, true), "O144: the entry message names the next reward: " .. joined)
  assert(joined:find("first clear this season: 5 Crystal Coin", 1, true), "O144: and its first clear: " .. joined)
  for floor = 1, 5 do
    advance(floor == 1 and 6000 or 7000)
    local list = alive()
    assertEq(#list, ChaosTowerFloorPlan(floor, 1).boss and 0 or #ChaosTowerFloorPlan(floor, 1).spawns, "O144: floor " .. floor .. " monster count")
    if floor == 1 then
      -- the floor's health; a tier x the tower's tierHealth (not the stock x2 / x3.5 / x6)
      for _, m in ipairs(list) do
        local base = math.floor(ChaosTowerBalanceCore.health(BC, 1))
        local expect = m.tier and math.floor(base * BC.tierHealth[m.tier]) or base
        assert(math.abs(m.maxHp - expect) <= 2, "O144: floor 1 health " .. m.maxHp .. " vs " .. expect .. " tier " .. tostring(m.tier))
      end
    end
    for _, m in ipairs(list) do m.dead = true; registry["ChaosTowerMonsterDeath"].onDeath(m) end
  end
  -- floor 5 is a milestone: 1 Crystal Coin every time and 5 more for the first clear this season
  assertEq(h.items[2160], nil, "coins never go to the backpack")
  assertEq(h.bank, 6 * 10000 + 50 * (1 + 2 + 3 + 4 + 5), "O144: floor 5 pays 1 (every time) + 5 (first clear) crystal coins, into the bank with the floor gold")
  assertEq(h.storage[BC.rewards.storage], 7005, "O144: the first clear is kept as season x 1000 + floor")
  local said5 = table.concat(h.msgs, "|")
  assert(said5:find("First clear of floor 5 this season: 5 Crystal Coin.", 1, true), "O144: first clear text")
  assert(said5:find("Floor 5 reward: 1 Crystal Coin.", 1, true), "O144: repeatable text")
  assert(said5:find("Next reward: floor 10, ", 1, true), "O144: the next reward after a milestone floor")
  assert(said5:find("2 Orb of Upheaval", 1, true) or said5:find("Orb of Upheaval", 1, true), "O144: floor 10 pays orbs")
  ChaosTowerRun.leave(h)
  -- the second run: the repeatable reward only
  h.items = {}
  h.bank = 0
  assertEq(ChaosTowerRun.start(h), true, "O144: second run")
  for floor = 1, 5 do
    advance(floor == 1 and 6000 or 7000)
    for _, m in ipairs(alive()) do m.dead = true; registry["ChaosTowerMonsterDeath"].onDeath(m) end
  end
  assertEq(h.bank, 10000 + 50 * (1 + 2 + 3 + 4 + 5), "O144: the second clear pays the repeatable reward only")
  ChaosTowerRun.leave(h)
  -- the damage factor and the drops
  advance(1000)
  local h2 = mkPlayer(9, "Ivy", 300); players[9] = h2
  assertEq(ChaosTowerRun.start(h2), true, "O144: third run")
  advance(6000)
  local mon = alive()[1]
  mon.isMonster = function() return true end
  mon.getMaster = function() return nil end
  assertEq(ChaosTowerRun.damageMultOf(mon), BC.damage[1][2], "O144: floor 1 damage factor")
  assertEq(ChaosTowerRun.damageMultOf({isMonster = function() return false end, getId = function() return 1 end}), 1, "O144: players are never scaled")
  local corpse = {added = {}}
  function corpse:addItem(id, n) self.added[#self.added + 1] = {id, n} end
  math.randomseed(1)
  local old = math.random
  math.random = function(a, b) if b then return a end return 1 end -- every drop rolls in
  lootCallbacks[#lootCallbacks](mon, corpse)
  math.random = old
  assert(#corpse.added >= 2, "O144: tower drops are added to the corpse")
  local sawOrb = false
  for _, a in ipairs(corpse.added) do sawOrb = sawOrb or a[1] == 29856 end
  assert(sawOrb, "O144: an Orb of Upheaval can drop")
  local other = {isMonster = function() return true end, getId = function() return 99999 end, getMaster = function() return nil end}
  local before = #corpse.added
  lootCallbacks[#lootCallbacks](other, corpse)
  assertEq(#corpse.added, before, "O144: other monsters get no tower drops")
  ChaosTowerRun.leave(h2)
  local _ = first
end
-- ---- "Next floor now" (action skip): between floors only, leader, boss floors, rate limit, no stale timer
do
  advance(30000)
  local alive = function(from) local out = {} for i = from + 1, #created do local m = created[i]; if not m.removed and not m.dead then out[#out + 1] = m end end return out end
  local cfg = ChaosTowerRunConfig
  local base = 5000000
  local now = base
  os.time = function() return now end -- luacheck: ignore
  local function said(p, text) for _, m in ipairs(p.msgs) do if m:find(text, 1, true) then return true end end return false end
  local k = mkPlayer(20, "Kay", 300); players[20] = k
  local out = mkPlayer(21, "Out", 300); players[21] = out
  assertEq(ChaosTowerRun.skip(out), false, "skip: refused outside a run")
  assert(out.cancel:find("not inside the tower", 1, true), "skip: told")
  local first = #created
  assertEq(ChaosTowerRun.start(k), true, "skip: start")
  -- the start delay can be skipped
  assertEq(ChaosTowerRun.skip(k), true, "skip: the start delay")
  assertEq(#alive(first), 4, "skip: floor 1 began at once")
  -- while monsters are alive: refused, nothing stacks
  now = now + 10
  assertEq(ChaosTowerRun.skip(k), false, "skip: refused while the floor is alive")
  assertEq(#alive(first), 4, "skip: no second floor on top")
  advance(6000) -- the start timer that was skipped fires: it must do nothing
  assertEq(#alive(first), 4, "skip: the old start timer is dead")
  for _, m in ipairs(alive(first)) do m.dead = true; registry["ChaosTowerMonsterDeath"].onDeath(m) end
  local mark = #created
  -- cleared: skip between floors, then the pause timer of floor 1 must not start floor 3
  now = now + 10
  assertEq(ChaosTowerRun.skip(k), true, "skip: the pause between floors")
  assertEq(#alive(mark), 4, "skip: floor 2 began at once")
  assert(said(k, "Floor 2"), "skip: floor 2 announced")
  advance(7000)
  assertEq(#alive(mark), 4, "skip: the stale pause timer started nothing")
  -- rate limit: a press right after a skip is refused even if the floor is clear
  for _, m in ipairs(alive(mark)) do m.dead = true; registry["ChaosTowerMonsterDeath"].onDeath(m) end
  mark = #created
  now = now + 1
  assertEq(ChaosTowerRun.skip(k), false, "skip: rate limit")
  assert(k.cancel:find("Wait a moment", 1, true), "skip: rate limit text")
  now = now + 5
  -- floor 3 -> the next after floor 9 is a boss floor: refused (floor 10)
  assertEq(ChaosTowerRun.skip(k), true, "skip: floor 3")
  for f = 3, 8 do
    for _, m in ipairs(alive(mark)) do m.dead = true; registry["ChaosTowerMonsterDeath"].onDeath(m) end
    mark = #created
    now = now + 5
    assertEq(ChaosTowerRun.skip(k), true, "skip: floor " .. (f + 1))
  end
  for _, m in ipairs(alive(mark)) do m.dead = true; registry["ChaosTowerMonsterDeath"].onDeath(m) end -- floor 9 cleared
  mark = #created
  now = now + 5
  assertEq(ChaosTowerRun.skip(k), false, "skip: the pause before a boss floor is kept")
  assert(k.cancel:find("boss floor", 1, true), "skip: boss text")
  cfg.skip.intoBoss = true
  assertEq(ChaosTowerRun.skip(k), true, "skip: intoBoss allows it")
  cfg.skip.intoBoss = false
  ChaosTowerRun.leave(k)
  assertEq(ChaosTowerRun.skip(k), false, "skip: refused after leaving")
  -- the records see the run's real clock, and a disabled switch refuses
  cfg.skip.enabled = false
  local k2 = mkPlayer(22, "Kim", 300); players[22] = k2
  ChaosTowerRun.start(k2)
  assertEq(ChaosTowerRun.skip(k2), false, "skip: switched off")
  cfg.skip.enabled = true
  ChaosTowerRun.leave(k2)
  -- a group: the leader presses, a member cannot while the leader is in, anyone once the leader is out
  local l, m1 = mkPlayer(23, "Lea", 300), mkPlayer(24, "Max", 300); players[23] = l; players[24] = m1
  l.getParty = function() return {getLeader = function() return l end, getMembers = function() return {l, m1} end} end
  m1.getParty = l.getParty
  l.pos = Position(10, 10, 7); m1.pos = Position(11, 10, 7)
  assertEq(ChaosTowerRun.start(l), true, "skip: group start")
  now = now + 5
  assertEq(ChaosTowerRun.skip(m1), false, "skip: a member cannot while the leader is in")
  assert(m1.cancel:find("run leader", 1, true), "skip: leader text")
  local gm = #created
  assertEq(ChaosTowerRun.skip(l), true, "skip: the leader")
  for _, m in ipairs(alive(gm)) do m.dead = true; registry["ChaosTowerMonsterDeath"].onDeath(m) end
  registry["ChaosTowerPlayerDeath"].onDeath(l) -- the leader falls
  now = now + 5
  assertEq(ChaosTowerRun.skip(m1), true, "skip: a member once the leader is out")
  ChaosTowerRun.leave(m1)
  assertEq(ChaosTowerRun.activeRuns(), 0, "skip: all closed")
  -- a player that is in a run but not in the arena is refused
  local z = mkPlayer(25, "Zed", 300); players[25] = z
  ChaosTowerRun.start(z)
  z.pos = Position(10, 10, 7)
  assertEq(ChaosTowerRun.skip(z), false, "skip: not in the tower area")
  ChaosTowerRun.leave(z)
  -- the state pushed to the client enables the button
  local sent = {}
  ChaosOpcodes.infinitytower = 214
  json = {encode = function(t) return t end}
  local w = mkPlayer(26, "Wyn", 300); players[26] = w
  w.sendExtendedOpcode = function(self, op, st) sent[#sent + 1] = st end
  ChaosTowerRun.start(w)
  assertEq(sent[#sent].inRun, true, "state: in a run")
  assertEq(sent[#sent].canSkip, true, "state: the start delay can be skipped")
  now = now + 5
  ChaosTowerRun.skip(w)
  assertEq(sent[#sent].canSkip, false, "state: a live floor cannot")
  assertEq(sent[#sent].floor, 1, "panel: floor")
  assertEq(sent[#sent].total, 4, "panel: monsters of the floor")
  assertEq(sent[#sent].remaining, 4, "panel: monsters left")
  assertEq(sent[#sent].floorLeft, 300, "panel: floor time left")
  assertEq(sent[#sent].nextIn, nil, "panel: no next-floor countdown while it is alive")
  local live = {}
  for i = 1, #created do local m = created[i]; if not m.removed and not m.dead then live[#live + 1] = m end end
  live[1].dead = true; registry["ChaosTowerMonsterDeath"].onDeath(live[1])
  assertEq(sent[#sent].remaining, 3, "panel: pushed on a kill")
  for i = 2, #live do live[i].dead = true; registry["ChaosTowerMonsterDeath"].onDeath(live[i]) end
  assertEq(sent[#sent].waiting, true, "panel: waiting after the clear")
  assertEq(sent[#sent].cleared, 1, "panel: cleared floors")
  assertEq(sent[#sent].nextIn, 6, "panel: countdown to the next floor")
  assertEq(sent[#sent].remaining, 0, "panel: nothing left")
  ChaosTowerRun.leave(w)
  assertEq(sent[#sent].inRun, false, "state: left")
  json = nil
end
print("infinity tower run: next floor now passed")
print("infinity tower run: O144 floor health, rewards and drops passed")
print("infinity tower run: all asserts passed")
