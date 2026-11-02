-- Run from the server/ folder: lua5.3 tests/infinitytower_exit_test.lua (mock engine API; CI runs it)
-- Leaving an Infinity Tower run (owner bug 2026-11-02: "no way out, not by portal nor by command"):
-- ChaosTowerCore.leaveRule / exitPos / portalSpot, the exit portal of every arena (item, action id, MoveEvent), the
-- Leave request (action "leave"; no typed words: owner rule), the countdown while a floor is fought, and the way out of an arena whose run a
-- script reload lost. server/README.md "Infinity Tower: leaving a run".
local n = 0
setmetatable(_G, {__index = function(t, k)
  if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local assertEq = function(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

-- ---- the pure rule
dofile("data/scripts/chaos/infinitytower_core.lua")
local K = ChaosTowerCore
do
  local x, y = K.portalSpot(25)
  assertEq(x, 13, "portal: the middle column"); assertEq(y, 24, "portal: by the south wall, above the row its 2x2 pieces cover")
  local r, s = K.leaveRule({inRun = false, inArena = false})
  assertEq(r, "outside", "no run, outside: refused")
  r = K.leaveRule({inRun = false, inArena = true})
  assertEq(r, "stray", "no run, in an arena: to the temple")
  r, s = K.leaveRule({inRun = true, fighting = false, now = 100, delay = 5})
  assertEq(r, "now", "between floors: at once"); assertEq(s, 0, "no wait")
  r, s = K.leaveRule({inRun = true, fighting = true, now = 100, delay = 5})
  assertEq(r, "countdown", "a live floor: countdown"); assertEq(s, 5, "the delay")
  r, s = K.leaveRule({inRun = true, fighting = true, pendingAt = 103, now = 100, delay = 5})
  assertEq(r, "pending", "a second request"); assertEq(s, 3, "seconds left")
  r = K.leaveRule({inRun = true, fighting = true, now = 100, delay = 0})
  assertEq(r, "now", "no delay configured: at once")
  r = K.leaveRule({inRun = true, fighting = true, pendingAt = 100, now = 100, delay = 5})
  assertEq(r, "countdown", "an expired countdown does not block a new one")
  local inside = function(p) return p.x >= 2000 end
  local entry, temple = {x = 10, y = 10, z = 7}, {x = 1, y = 1, z = 7}
  assertEq(K.exitPos(entry, temple, inside), entry, "out to the entry")
  assertEq(K.exitPos({x = 2005, y = 2005, z = 7}, temple, inside), temple, "an entry inside an arena: the temple")
  assertEq(K.exitPos(nil, temple, inside), temple, "no entry: the temple")
end

-- ---- the engine file on a mocked engine
Chaos = {storage = {}, tables = {}, passive = {}, tower = {}}
ChaosOpcodes = {}
local registry, moves, talks = {}, {}, {}
function CreatureEvent(name) local o = {}; function o:register() registry[name] = o end; return o end
function MoveEvent()
  local o = {aids = {}}
  function o:type(t) self.kind = t end
  function o:aid(...) for _, a in ipairs({...}) do self.aids[#self.aids + 1] = a end end
  function o:register() for _, a in ipairs(self.aids) do moves[a] = self end end
  return o
end
function TalkAction(words)
  local o = {words = words}
  function o:separator(s) self.sep = s end
  function o:register() talks[self.words] = self end
  return o
end

local queue, clock = {}, 0
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, args = {...}, due = clock + delay}; return #queue end
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
os.time = function() return 1000000 + math.floor(clock / 1000) end -- luacheck: ignore

Position = function(x, y, z) return {x = x, y = y, z = z, getDistance = function(self, o) return math.max(math.abs(self.x - o.x), math.abs(self.y - o.y)) end, sendMagicEffect = function() end} end

local tiles, nextId = {}, 100
local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
local function mkTile(p)
  local t = {pos = p, items = {}, creatures = {}}
  function t:getGround() return self.ground end
  function t:addItem(id)
    if not self.ground then self.ground = id end
    local item = {id = id}
    function item:remove() for i, it in ipairs(t.items) do if it == self then table.remove(t.items, i) break end end end
    function item:setActionId(a) self.aid = a end
    function item:getActionId() return self.aid or 0 end
    self.items[#self.items + 1] = item
    return item
  end
  function t:getItemById(id) for _, i in ipairs(self.items) do if i.id == id then return i end end end
  function t:getCreatures() return self.creatures end
  function t:getItems() local out = {} for i, it in ipairs(self.items) do out[i] = it end return out end
  return t
end
Game = {}
function Game.createTile(p) local k = key(p); tiles[k] = tiles[k] or mkTile(p); return tiles[k] end
function Tile(p) return tiles[key(p)] end
function Game.createItem(id, count, p) local t = tiles[key(p)]; if t then return t:addItem(id) end end
local created = {}
function Game.createMonster(name, pos)
  nextId = nextId + 1
  local m = {id = nextId, name = name, events = {}, removed = false, hp = 1000, maxHp = 1000}
  function m:getId() return self.id end
  function m:setMaxHealth(v) self.maxHp = v end
  function m:setHealth(v) self.hp = v end
  function m:isMonster() return true end
  function m:registerEvent(e) self.events[e] = true end
  function m:remove() self.removed = true end
  created[#created + 1] = m
  local tile = tiles[key(pos)]; if tile then tile.creatures[#tile.creatures + 1] = m end
  return m
end
function MonsterType() return true end

local recorded = {}
ChaosTower = {canEnter = function() return true end, recordRun = function(p, floors) recorded[#recorded + 1] = {name = p.name, floors = floors} end,
  currentSeason = function() return 1 end}

local players = {}
function Player(id) return players[id] end
local function mkPlayer(id, name)
  local p = {id = id, name = name, pos = Position(10, 10, 7), events = {}, msgs = {}}
  function p:getId() return self.id end
  function p:getGuid() return self.id end
  function p:getName() return self.name end
  function p:getLevel() return 300 end
  function p:getParty() return nil end
  function p:isPlayer() return true end
  function p:getPosition() return self.pos end
  function p:teleportTo(pos) self.pos = pos end
  function p:registerEvent(e) self.events[e] = true end
  function p:unregisterEvent(e) self.events[e] = nil end
  function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
  function p:sendCancelMessage(t) self.cancel = t end
  function p:getCondition() return nil end
  function p:getStorageValue() return -1 end
  function p:setStorageValue() end
  function p:getBankBalance() return 0 end
  function p:setBankBalance() end
  function p:addHealth() end
  function p:addMana() end
  function p:getMaxHealth() return 100 end function p:getHealth() return 100 end
  function p:getMaxMana() return 100 end function p:getMana() return 100 end
  function p:getTown() return {getTemplePosition = function() return Position(1, 1, 7) end} end
  players[id] = p
  return p
end
local function said(p, text) for _, m in ipairs(p.msgs) do if m:find(text, 1, true) then return true end end return false end

Chaos.decode = function() end
do local stub = Chaos; Chaos = nil; dofile("data/scripts/chaos/chaos_constants.lua"); stub.heal = Chaos.heal; Chaos = stub end
Chaos.giveItem = function(_, _, c) return c end
EventCallback = setmetatable({}, {__index = function() return nil end})
function EventCallback:register() end
ItemType = function() return {isStackable = function() return true end} end

dofile("data/scripts/chaos/infinitytower_run.lua")
local cfg = ChaosTowerRunConfig
local ex = cfg.exit

assert(moves[ex.actionId] and moves[ex.actionId].kind == "stepin", "the portal's step-in is registered for its action id")
assertEq(next(talks), nil, "no talkaction (owner rule: players type no commands)")

local function portalOf(slot)
  local dx, dy = K.portalSpot(cfg.inner)
  local pos = Position(cfg.arenaBase.x + slot * cfg.slotSpacing + dx, cfg.arenaBase.y + dy, cfg.arenaBase.z)
  return pos, Tile(pos) and Tile(pos):getItemById(ex.portalId)
end
-- the portal's tile is open in every theme and layout variant (no cover piece, light or rubble on it)
do
  local dx, dy = K.portalSpot(cfg.inner)
  for runNo = 1, #cfg.look.themes * cfg.look.variants do
    local look = ChaosTowerRun.look(runNo)
    assertEq((look.blocked or {})[ChaosArenaLook.key(dx, dy)], nil, "portal tile open in look " .. runNo)
  end
end
local function runs() local r = ChaosTowerRun._state(); local c = 0; for _ in pairs(r) do c = c + 1 end; return c end

-- ---- 1. the portal: placed in the arena with its action id; a step between floors leaves at once
local a = mkPlayer(1, "Ann")
assertEq(ChaosTowerRun.start(a), true, "start")
assert(said(a, "exit portal"), "the welcome names the exit portal")
local ppos, portal = portalOf(0)
assert(portal, "the arena has an exit portal")
assertEq(portal:getActionId(), ex.actionId, "the portal carries the action id")
assertEq(ChaosTowerRun.inArena(ppos), true, "the portal is inside the arena")
moves[ex.actionId].onStepIn(a, portal, ppos, ppos) -- during the start delay: no live floor
assertEq(a.pos.x, 10, "back at the entry"); assertEq(a.pos.y, 10, "back at the entry (y)")
assertEq(runs(), 0, "the last one out ends the run")
assert(said(a, "You left the Infinity Tower. You cleared 0 floor(s)."), "told")
assertEq(recorded[#recorded].floors, 0, "the run is recorded")
assertEq(select(2, portalOf(0)), nil, "the arena is cleared, the portal with it")
assertEq(ChaosTowerRun.leave(a), false, "outside now: refused")
assert(a.cancel:find("not inside the tower", 1, true), "refusal text")

-- ---- 2. a live floor: the countdown; the floor's monsters go when the last player is out
local b = mkPlayer(2, "Bo")
assertEq(ChaosTowerRun.start(b), true, "start 2")
assertEq(select(2, portalOf(0)) ~= nil, true, "a new run gets its portal again")
local mark = #created
advance((cfg.startDelay + 1) * 1000) -- floor 1 begins
assert(#created > mark, "floor 1 spawned")
ChaosTowerRun.leave(b) -- the Leave button (action "leave")
assert(said(b, "You leave the tower in 5 seconds."), "countdown told")
assertEq(runs(), 1, "still inside during the countdown")
ChaosTowerRun.leave(b)
assert(b.cancel:find("You leave the tower in", 1, true), "a second request: the countdown runs")
advance(ex.delay * 1000)
assertEq(b.pos.x, 10, "out after the countdown")
assertEq(runs(), 0, "run closed")
for i = mark + 1, #created do assertEq(created[i].removed, true, "the floor's monsters are removed") end
assertEq(recorded[#recorded].floors, 0, "recorded with the floors cleared")

-- ---- 3. death during the countdown cancels it (the engine respawns the player; nothing teleports later)
local c = mkPlayer(3, "Cy")
local d = mkPlayer(4, "Di")
c.getParty = function() return {getLeader = function() return c end, getMembers = function() return {c, d} end} end
d.getParty = c.getParty
d.pos = Position(11, 10, 7)
assertEq(ChaosTowerRun.start(c), true, "group start")
advance((cfg.startDelay + 1) * 1000)
ChaosTowerRun.leave(c)
registry["ChaosTowerPlayerDeath"].onDeath(c)
local deathPos = c.pos
advance(ex.delay * 1000)
assertEq(c.pos, deathPos, "no teleport after death")
assertEq(runs(), 1, "the other member still fights")
-- the member's portal step during the fight: countdown, then out; the run ends
ppos, portal = portalOf(0)
moves[ex.actionId].onStepIn(d, portal, ppos, ppos)
assertEq(runs(), 1, "countdown first")
advance(ex.delay * 1000)
assertEq(d.pos.x, 11, "the member is out")
assertEq(runs(), 0, "run closed")

-- ---- 5. a stray: in an arena without a run (a /reload scripts dropped the run tables): the temple
local f = mkPlayer(6, "Fey")
f.pos = Position(cfg.arenaBase.x + 13, cfg.arenaBase.y + 13, cfg.arenaBase.z)
assertEq(ChaosTowerRun.leave(f), true, "a stray gets out")
assertEq(f.pos.x, 1, "to the temple"); assertEq(f.pos.y, 1, "to the temple (y)")
f.pos = Position(cfg.arenaBase.x + 13, cfg.arenaBase.y + 25, cfg.arenaBase.z)
moves[ex.actionId].onStepIn(f, {}, f.pos, f.pos)
assertEq(f.pos.x, 1, "an old portal works too")

-- ---- 6. the run's end by time: everyone to the entry, never to a spot inside an arena
local g = mkPlayer(7, "Gil")
g.pos = Position(20, 20, 7)
assertEq(ChaosTowerRun.start(g), true, "start 6")
local _, runOf = ChaosTowerRun._state()
local run = runOf[g:getId()]
run.players[g:getId()].entry = Position(cfg.arenaBase.x + 3, cfg.arenaBase.y + 3, cfg.arenaBase.z) -- a broken entry
ChaosTowerRun.leave(g)
assertEq(g.pos.x, 1, "an entry inside an arena: the temple instead")

print("infinitytower_exit_test: ok")
