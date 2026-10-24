-- Run from the server/ folder: lua5.3 tests/infinitytower_floor_test.lua (mock engine API; CI runs it)
-- O168: what a tower monster really is once the engine has had its say: setHealth clamped to the maximum health like
-- TFS, the species' own health and level, the natural tier roll of monster_tiers.lua, a monster without a target.
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
local SPECIES_HP = 100 -- the stock health of every species of the mock
function Game.createMonster(name, pos)
  nextId = nextId + 1
  local m = {spawnLevel = Chaos.spawnLevel, id = nextId, name = name, events = {}, removed = false, hp = SPECIES_HP, maxHp = SPECIES_HP,
    pos = pos}
  function m:getId() return self.id end
  function m:getMaxHealth() return self.maxHp end
  function m:getHealth() return self.hp end
  -- TFS: creature->healthMax = value; health = min(health, healthMax)
  function m:setMaxHealth(v) self.maxHp = v; self.hp = math.min(self.hp, v) end
  -- TFS: health = min(value, healthMax)
  function m:setHealth(v) self.hp = math.min(v, self.maxHp) end
  function m:isMonster() return true end
  function m:getMaster() return nil end
  function m:getPosition() return self.pos end
  function m:registerEvent(e) self.events[e] = true end
  function m:unregisterEvent(e) self.events[e] = nil end
  function m:getTarget() return self.target end
  function m:selectTarget(p) self.target = p; return true end
  function m:remove() self.removed = true end
  -- onSpawn of monster_tiers.lua: every monster of the mock rolled a natural tier and a boss its modifiers
  m.events["ChaosTierRollLegendary"] = true
  m.events["ChaosTierRollBoss"] = true
  monsters[m.id] = m; created[#created + 1] = m
  local tile = tiles[key(pos)]; if tile then tile.creatures[#tile.creatures + 1] = m end
  return m
end
function Monster(id) return monsters[id] end
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
local BCn = ChaosTowerBalance
local B = ChaosTowerBalanceCore

local function alive()
  local out = {}
  for _, m in ipairs(created) do if not m.removed and not m.dead then out[#out + 1] = m end end
  return out
end
local function killAll()
  for _, m in ipairs(alive()) do m.dead = true; registry["ChaosTowerMonsterDeath"].onDeath(m) end
end

-- ---- health: the engine clamps setHealth, so every tower monster must end with the floor's health
local a = mkPlayer(1, "Alice", 800); players[1] = a
assertEq(ChaosTowerRun.start(a), true, "start")
advance(6000) -- floor 1
local first = alive()
assertEq(#first, 4, "floor 1 monsters")
for _, m in ipairs(first) do
  assert(m.maxHp > SPECIES_HP and m.hp > SPECIES_HP, "floor 1: health above the species' own (" .. m.hp .. "/" .. m.maxHp .. ")")
  assertEq(m.hp, m.maxHp, "full health")
end
-- every later floor is higher up the health curve, boss floors included
for floor = 1, 41 do
  local mons = alive()
  assert(#mons > 0, "floor " .. floor .. " has monsters")
  local plan = ChaosTowerFloorPlan(floor, 1, function() return 1 end)
  for _, m in ipairs(mons) do
    assert(m.hp == m.maxHp, "floor " .. floor .. ": full health")
    assert(m.hp > SPECIES_HP, "floor " .. floor .. ": more than the species' own health")
    assert(not m.events["ChaosTierRollLegendary"] and not m.events["ChaosTierRollBoss"],
      "floor " .. floor .. ": the natural tier roll and the boss modifiers are off")
  end
  if floor % 10 == 0 then
    local boss
    for _, m in ipairs(mons) do if m.maxHp == BCn.bossHealth[floor] then boss = m end end
    assert(boss, "floor " .. floor .. ": a boss with the health of its floor (" .. tostring(BCn.bossHealth[floor]) .. ")")
  else
    local want = B.health(BCn, floor)
    local mx = 0
    for _, m in ipairs(mons) do mx = math.max(mx, m.maxHp) end
    assert(mx >= want, "floor " .. floor .. ": a normal monster has at least the floor's health " .. want .. ", got " .. mx)
  end
  -- level and damage: ChaosTowerRun.levelOf is the level the floor is meant for, the damage factor the floor's
  for _, m in ipairs(mons) do
    assertEq(ChaosTowerRun.levelOf(m), B.level(BCn, floor), "floor " .. floor .. ": level")
  end
  killAll()
  advance(7000)
  a.hp = 100
end
assert(B.level(BCn, 40) > B.level(BCn, 1) * 2, "the level rises with the floor")

-- ---- damage: a floor monster's multiplier is the floor's, and floor 40 is not floor 1
do
  local mons = alive()
  local m = mons[#mons]
  m.getMaster = function() return nil end
  local d = ChaosTowerRun.damageMultOf(m)
  assertEq(d, B.damage(BCn, 42), "floor 42 damage factor")
  assert(ChaosTowerRun.levelOf(m) >= 900, "floor 42 is meant for level 900+, got " .. tostring(ChaosTowerRun.levelOf(m)))
  assertEq(ChaosTowerRun.levelOf({getId = function() return 99999 end}), nil, "other monsters have no tower level")
end

-- ---- engage: a monster without a target gets the nearest living player, also a boss
killAll(); advance(6000)
for _, m in ipairs(alive()) do assert(m.target == nil, "monsters start without a target in the mock") end
advance(1500)
for _, m in ipairs(alive()) do assertEq(m.target, a, "a monster without a target engages the player") end
local mon = alive()[1]
mon.target = nil
advance(2500)
assertEq(mon.target, a, "a lost target is picked again")
ChaosTowerRun.leave(a)
print("infinity tower floor: health, level, damage factor and engage passed")
