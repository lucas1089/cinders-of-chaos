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
  local m = {id = nextId, name = name, events = {}, removed = false}
  function m:getId() return self.id end
  function m:isMonster() return true end
  function m:registerEvent(e) self.events[e] = true end
  function m:remove() self.removed = true end
  monsters[m.id] = m; created[#created + 1] = m
  local tile = tiles[key(pos)]; if tile then tile.creatures[#tile.creatures + 1] = m end
  return m
end
function MonsterType(name) return name ~= "ghost-of-nothing" end
ChaosApplyTier = function(m, tier) m.tier = tier; return true end

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
assertEq(p10.spawns[1].name, "the old widow", "first boss")
assertEq(ChaosTowerFloorPlan(20, 1, det).spawns[1].name, "the pale count", "second boss")
assertEq(#ChaosTowerFloorPlan(1, 3, det).spawns, 8, "party size adds monsters")
assertEq(#ChaosTowerFloorPlan(301, 1, det).spawns, 16, "count cap")
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
assertEq(a.money, 50, "floor gold")
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
registry["ChaosTowerLogin"].onLogin(e)
assertEq(e.pos.x, 1, "stuck player sent to the temple")
print("infinity tower run: all asserts passed")
