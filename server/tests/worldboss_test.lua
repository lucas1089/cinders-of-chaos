-- Run from the server/ folder: luajit tests/worldboss_test.lua (mock engine API; CI runs it with LuaJIT and Lua 5.3)
local n = 0
setmetatable(_G, {__index = function(t, k)
  if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local unpack = table.unpack or unpack

-- ---------------------------------------------------------------- engine mock
local registry, moves, talks, globals = {}, {}, {}, {}
function CreatureEvent(name) local o = {}; function o:register() registry[name] = o end; return o end
function MoveEvent() local o = {}; function o:type() end; function o:aid(a) self.aidv = a end; function o:register() moves[self.aidv] = self end; return o end
function TalkAction(w) local o = {}; function o:separator() end; function o:register() talks[w] = self end; return o end
function GlobalEvent(name) local o = {}; function o:interval() end; function o:register() globals[name] = self end; return o end
local callbacks = {}
EventCallback = setmetatable({register = function() end}, {__newindex = function(_, k, v) callbacks[k] = v end})

local queue, clock = {}, 0
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, args = {...}, due = clock + delay}; return #queue end
local realTime = os.time
local base = realTime({year = 2026, month = 10, day = 8, hour = 10, min = 0, sec = 0})
os.time = function(t) if t then return realTime(t) end return base + math.floor(clock / 1000) end
local function advance(ms)
  local limit = clock + ms
  while true do
    local best
    for i, e in ipairs(queue) do if e.due <= limit and (not best or e.due < queue[best].due) then best = i end end
    if not best then break end
    local e = table.remove(queue, best); clock = e.due; e.fn(unpack(e.args))
  end
  clock = limit
end

local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
Position = function(x, y, z)
  return {x = x, y = y, z = z, sendMagicEffect = function() end,
    getDistance = function(self, o) return math.max(math.abs(self.x - o.x), math.abs(self.y - o.y)) end}
end

local tiles = {}
local function mkItem(id, tile)
  local it = {id = id, aid = 0, tile = tile}
  function it:getId() return self.id end
  function it:setActionId(a) self.aid = a end
  function it:getActionId() return self.aid end
  function it:remove()
    if self.tile then for i, x in ipairs(self.tile.items) do if x == self then table.remove(self.tile.items, i) break end end end
    self.removed = true
  end
  return it
end
local function mkTile(p, ground)
  local t = {pos = p, items = {}, creatures = {}}
  if ground then t.ground = mkItem(ground) end
  function t:getGround() return self.ground end
  function t:getItemById(id) for _, i in ipairs(self.items) do if i.id == id then return i end end end
  function t:getItemByType() return nil end
  function t:getItems() local l = {}; for i, x in ipairs(self.items) do l[i] = x end; return l end
  function t:getCreatures() local l = {}; for i, x in ipairs(self.creatures) do l[i] = x end; return l end
  function t:getHouse() return nil end
  function t:hasProperty() return false end
  return t
end
function Tile(p) return tiles[key(p)] end

local GROUNDS = {[407] = true, [413] = true, [100] = true}
local monsters, players, nextId = {}, {}, 1000
local storage = {}
local broadcasts, combats = {}, {}
Game = {}
function Game.createTile(p) local k = key(p); tiles[k] = tiles[k] or mkTile(p); return tiles[k] end
function Game.createItem(id, count, p)
  if not p then return mkItem(id) end
  local t = tiles[key(p)]; if not t then return nil end
  if GROUNDS[id] and not t.ground then t.ground = mkItem(id, nil); return t.ground end
  local it = mkItem(id, t); t.items[#t.items + 1] = it; return it
end
function Game.createItemWithRarity(id, count, rarity) local it = mkItem(id); it.rarity = rarity; return it end
function Game.getStorageValue(k) return storage[k] end
function Game.setStorageValue(k, v) storage[k] = v end
function Game.broadcastMessage(text) broadcasts[#broadcasts + 1] = text end
function Game.getPlayers() local l = {}; for _, p in pairs(players) do if p.online then l[#l + 1] = p end end; return l end
local temples = {Position(100, 100, 7), Position(200, 200, 7), Position(100, 100, 7)} -- town 3 shares town 1's temple
function Game.getTowns()
  local l = {}
  for i, t in ipairs(temples) do l[i] = {getId = function() return i end, getTemplePosition = function() return t end} end
  return l
end
function Game.getSpectators(pos, multi, onlyPlayers, rx)
  local l = {}
  for _, p in pairs(players) do
    if p.online and p.pos.z == pos.z and math.abs(p.pos.x - pos.x) <= rx and math.abs(p.pos.y - pos.y) <= rx then l[#l + 1] = p end
  end
  return l
end

local function moveCreature(c, pos)
  if c.pos then local t = tiles[key(c.pos)]; if t then for i, x in ipairs(t.creatures) do if x == c then table.remove(t.creatures, i) break end end end end
  c.pos = pos
  local t = tiles[key(pos)]; if t then t.creatures[#t.creatures + 1] = c end
end

local MAXHP = {}
function MonsterType(name) if name == "Missing" then return nil end; return {name = name} end
function Game.createMonster(name, pos)
  nextId = nextId + 1
  local m = {id = nextId, name = name, events = {}, hp = MAXHP[name] or 1000, said = {}}
  m.maxhp = m.hp
  function m:getId() return self.id end
  function m:getName() return self.name end
  function m:isMonster() return true end
  function m:isPlayer() return false end
  function m:getMaster() return nil end
  function m:getPlayer() return nil end
  function m:getPosition() return self.pos end
  function m:registerEvent(e) self.events[e] = true end
  function m:remove() self.removed = true; monsters[self.id] = nil; moveCreature(self, Position(0, 0, 0)) end
  function m:getHealth() return self.hp end
  function m:getMaxHealth() return self.maxhp end
  function m:setMaxHealth(v) self.maxhp = v end
  -- this engine's addHealth: (damage type, amount); a one-argument call does nothing
  function m:addHealth(t, v) if type(t) == "string" then self.hp = math.min(self.maxhp, self.hp + v) end end
  function m:say(t) self.said[#self.said + 1] = t end
  monsters[m.id] = m
  moveCreature(m, pos)
  return m
end
function Monster(id) return monsters[id] end
function ItemType(id) return {getName = function() return "item" .. id end} end
function doTargetCombatHealth(src, target, ctype, min, max) combats[#combats + 1] = {target = target, min = min} end

local function mkPlayer(guid, name, level)
  local p = {guid = guid, id = guid + 100, name = name, level = level or 800, online = true, msgs = {}, bank = 0,
    bag = {}, inbox = {}, room = 1000, ip = guid, access = false}
  function p:getId() return self.id end
  function p:getGuid() return self.guid end
  function p:getName() return self.name end
  function p:getLevel() return self.level end
  function p:isPlayer() return true end
  function p:isMonster() return false end
  function p:getPlayer() return self end
  function p:getMaster() return nil end
  function p:getPosition() return self.pos end
  function p:teleportTo(pos) moveCreature(self, Position(pos.x, pos.y, pos.z)) end
  function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
  function p:sendCancelMessage(t) self.cancel = t end
  function p:getTown() return {getTemplePosition = function() return Position(100, 100, 7) end} end
  function p:getBankBalance() return self.bank end
  function p:setBankBalance(v) self.bank = v end
  function p:getItemCount(id) return self.bag[id] or 0 end
  function p:addItem(id, count)
    local add = math.min(count, self.room); self.room = self.room - add
    self.bag[id] = (self.bag[id] or 0) + add
  end
  function p:addItemEx(item) if self.room > 0 then self.room = self.room - 1; self.bag[item.id] = (self.bag[item.id] or 0) + 1; return RETURNVALUE_NOERROR end; return 1 end
  function p:getInbox()
    local me = self
    return {addItem = function(_, id, c) me.inbox[id] = (me.inbox[id] or 0) + c end,
      addItemEx = function(_, item) me.inbox[item.id] = (me.inbox[item.id] or 0) + 1 end}
  end
  function p:getGroup() local me = self; return {getAccess = function() return me.access end} end
  players[guid] = p
  moveCreature(p, Position(150, 150, 7))
  return p
end
function Player(x)
  for _, p in pairs(players) do if p.online and (p.name == x or p.id == x) then return p end end
end

dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.send = function() return true end
local mcSet = {}
Chaos.isMultiClient = function(p) return mcSet[p.guid] == true end
ChaosUniqueItems = {
  {name = "U1", id = 9001, bossOnly = true, monsters = {"Kaelgor the Infernal Warlord", "The Rotmother"}},
  {name = "U2", id = 9002, bossOnly = false, monsters = {"Kaelgor the Infernal Warlord"}},
  {name = "U3", id = 9003, bossOnly = true, monsters = {"Someone Else"}}
}
dofile("data/scripts/chaos/worldboss.lua")

local W = ChaosWorldBoss
local cfg = Chaos.worldBoss
local assertEq = function(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

-- ---------------------------------------------------------------- layout and bounds
local L = W.layout()
assertEq(L.arena.x1, 5000, "arena x1"); assertEq(L.arena.x2, 5032, "arena x2 (31 inner + 2 walls)")
assertEq(L.arena.y2, 5032, "arena y2")
assertEq(L.center.x, 5016, "centre x"); assertEq(L.center.y, 5016, "centre y")
assertEq(L.lobby.x1, 5009, "lobby x1"); assertEq(L.lobby.x2, 5023, "lobby x2")
assertEq(L.lobby.y1, 5040, "lobby y1 (7 empty rows after the arena wall)"); assertEq(L.lobby.y2, 5048, "lobby y2")
assert(L.lobby.y1 - L.arena.y2 - 1 == cfg.arena.lobbyGap, "gap rows")
for _, k in ipairs({"bossSpawn", "arenaEntry", "arenaBack"}) do
  local p = L[k]
  assert(p.x > L.arena.x1 and p.x < L.arena.x2 and p.y > L.arena.y1 and p.y < L.arena.y2, k .. " inside the arena walls")
end
for _, p in ipairs({L.lobbyArrival, L.lobbyToArena, L.lobbyExits[1], L.lobbyExits[2]}) do
  assert(p.x > L.lobby.x1 and p.x < L.lobby.x2 and p.y > L.lobby.y1 and p.y < L.lobby.y2, "lobby point inside the lobby walls")
end
assert(W.inArena({x = 5016, y = 5016, z = 7}), "centre in arena")
assert(not W.inArena({x = 5016, y = 5016, z = 6}), "other floor")
assert(not W.inside({x = 5016, y = 5036, z = 7}), "gap is outside")
assert(W.inLobby({x = 5016, y = 5044, z = 7}), "lobby centre")
assert(not W.inArena({x = 5016, y = 5044, z = 7}), "lobby is not arena")
local foot = W.footprint()
assertEq(#foot, 33 * 33 + 15 * 9, "footprint tiles")
local walls = 0
for _, t in ipairs(foot) do if t.wall then walls = walls + 1 end end
assertEq(walls, 4 * 32 + (2 * 15 + 2 * 7), "wall tiles: arena ring 128 + lobby ring 44")

-- ---------------------------------------------------------------- rotation
assertEq(W.pickBoss(5, "rotation", nil), 1, "rotation starts at 1")
assertEq(W.pickBoss(5, "rotation", 2), 3, "rotation next")
assertEq(W.pickBoss(5, "rotation", 5), 1, "rotation wraps")
assertEq(W.pickBoss(5, "rotation", -1), 1, "unset storage")
for last = 1, 5 do
  for r = 1, 4 do
    local i = W.pickBoss(5, "random", last, function() return r end)
    assert(i ~= last and i >= 1 and i <= 5, "random never repeats")
  end
end
assertEq(W.pickBoss(1, "random", 1), 1, "single boss")

-- ---------------------------------------------------------------- schedule (6 h, offset 3: 03 09 15 21)
local function at(h, mi, d) return realTime({year = 2026, month = 10, day = d or 8, hour = h, min = mi or 0, sec = 0}) end
local c6 = {intervalHours = 6, offsetHours = 3}
assertEq(W.nextStart(at(10, 30), c6), at(15), "next after 10:30")
assertEq(W.nextStart(at(15, 0), c6), at(21), "strictly after now")
assertEq(W.nextStart(at(22, 10), c6), at(3, 0, 9), "next day")
assertEq(W.nextStart(at(0, 5), {intervalHours = 4, offsetHours = 0}), at(4), "every 4 h")

-- ---------------------------------------------------------------- phases
local phases = {{at = 0.7}, {at = 0.4}, {at = 0.15}}
assertEq(#W.duePhases(phases, {}, 0.8), 0, "none above 70%")
assertEq(#W.duePhases(phases, {}, 0.39), 2, "a big hit can pass two thresholds")
assertEq(#W.duePhases(phases, {[1] = true, [2] = true}, 0.39), 0, "each phase once")

-- ---------------------------------------------------------------- damage share
local dmg = {[1] = {damage = 600000, name = "A"}, [2] = {damage = 300000, name = "B"}, [3] = {damage = 100000, name = "C"},
  [4] = {damage = 40000, name = "Leech"}, [5] = {damage = 500000, name = "Alt"}}
-- boss 20M, min 0.25% = 50000: Leech is out, Alt is excluded (multi-client)
local shares, total = W.computeShares(dmg, 20000000, 0.25, {[5] = true})
assertEq(#shares, 3, "eligible players")
assertEq(total, 1000000, "eligible total")
assertEq(shares[1].name, "A", "sorted by damage"); assertEq(shares[1].rank, 1, "rank")
assertEq(shares[1].share, 0.6, "share A"); assertEq(shares[3].share, 0.1, "share C")
local sum = 0; for _, s in ipairs(shares) do sum = sum + s.share end
assert(math.abs(sum - 1) < 1e-9, "shares sum to 1")
assertEq(#W.computeShares({}, 1000, 0.25), 0, "nobody")

-- ---------------------------------------------------------------- rewards
local r = {bankGold = 1000, bankGoldPool = 100000, base = {{id = 29856, count = 3}, {id = 29857, count = 1}},
  pool = {{id = 29856, count = 60}, {id = 29857, count = 25}}, top = {{{id = 29857, count = 5}}, {{id = 2160, count = 30}}},
  gearChance = 1500, gearShareBonus = 3000, gearRarity = {6, 9}, uniqueChance = 50, uniqueShareBonus = 300}
local boss1 = {gear = {111, 222}}
-- rng: 10000-rolls fail unless the threshold allows 1; lists pick their first entry; rarity picks the low end
local rewards = W.computeRewards(shares, r, boss1, {9001}, function(a, b) if b then return a end; return 1 end)
local A, C3 = rewards[1], rewards[3]
assertEq(A.bank, 1000 + 60000, "bank A")
assertEq(A.items[1].id, 29856, "first item"); assertEq(A.items[1].count, 3 + 36, "chaos orbs A: base + 60% of 60")
assertEq(A.items[2].count, 1 + 15 + 5, "divine orbs A: base + 60% of 25 + top 1")
assertEq(rewards[2].items[3].id, 2160, "rank 2 bonus"); assertEq(rewards[2].items[3].count, 30, "rank 2 bonus count")
assertEq(C3.items[1].count, 3 + 6, "chaos orbs C (10%)")
assertEq(#C3.items, 2, "rank 3 has no configured bonus here")
assertEq(A.gear, 111, "gear rolled"); assertEq(A.gearRarity, 6, "gear rarity")
assertEq(A.unique, 9001, "unique rolled")
local none = W.computeRewards(shares, r, boss1, {9001}, function(a, b) if b then return a end; if a == 10000 then return 10000 end; return 1 end)
assertEq(none[1].gear, nil, "gear roll failed"); assertEq(none[1].unique, nil, "unique roll failed")
-- chance grows with the share: 1500 + 0.6*3000 = 3300
local g = W.computeRewards({shares[1]}, r, boss1, {}, function(a, b) if b then return a end; if a == 10000 then return 3300 end; return 1 end)
assertEq(g[1].gear, 111, "share bonus on the gear chance")
local g2 = W.computeRewards({shares[3]}, r, boss1, {}, function(a, b) if b then return a end; if a == 10000 then return 3300 end; return 1 end)
assertEq(g2[1].gear, nil, "small share, same roll fails")

-- unique pool: boss-only entries that list the boss
local pool = W.uniquePool("Kaelgor the Infernal Warlord")
assertEq(#pool, 1, "only boss-only uniques"); assertEq(pool[1], 9001, "the right one")
assertEq(#W.uniquePool("Skaldra the Rime Queen"), 0, "none listed")
assertEq(W.findBoss("rime"), 2, "find by part of the name"); assertEq(W.findBoss("4"), 4, "by number")
assertEq(W.findBoss("random"), nil, "random"); assertEq(W.findBoss("nobody"), false, "unknown")

-- ---------------------------------------------------------------- arena build (empty map)
local ok = W.buildArena()
assert(ok, "built on an empty area")
local t = Tile(Position(5016, 5016, 7))
assertEq(t.ground.id, 407, "arena ground")
assert(Tile(Position(5000, 5000, 7)):getItemById(5648), "wall in the corner")
assertEq(Tile(Position(5016, 5044, 7)).ground.id, 413, "lobby ground")
assertEq(Tile(Position(5016, 5036, 7)), nil, "gap stays empty")
assertEq(Tile(Position(L.arenaBack.x, L.arenaBack.y, 7)):getItemById(1387).aid, cfg.aid.lobby, "arena back portal")
assertEq(Tile(Position(L.lobbyToArena.x, L.lobbyToArena.y, 7)):getItemById(1387).aid, cfg.aid.arena, "lobby to arena portal")
assertEq(Tile(Position(L.lobbyExits[1].x, L.lobbyExits[1].y, 7)):getItemById(1387).aid, cfg.aid.exit, "lobby exit")
assert(W.buildArena(), "rebuilding over our own arena is fine")
local items = #Tile(Position(5000, 5000, 7)).items
W.buildArena()
assertEq(#Tile(Position(5000, 5000, 7)).items, items, "rebuild does not stack walls")

-- a foreign tile in the footprint stops the build (fresh map)
local saved = tiles
tiles = {}
tiles[key(Position(5020, 5045, 7))] = mkTile(Position(5020, 5045, 7), 100)
local ok2, err = W.buildArena()
assertEq(ok2, false, "refuses to build over map content")
assert(err:find("5020,5045,7"), "reason names the tile")
assertEq(Tile(Position(5016, 5016, 7)), nil, "nothing was built")
tiles = saved

-- ---------------------------------------------------------------- the event
-- temples with free spots
for _, tp in ipairs({Position(100, 100, 7), Position(200, 200, 7)}) do
  for dx = -3, 3 do for dy = -3, 3 do Game.createTile(Position(tp.x + dx, tp.y + dy, 7)).ground = mkItem(100) end end
end
MAXHP["Kaelgor the Infernal Warlord"] = 18000000
local a = mkPlayer(1, "Alice", 900)
local b = mkPlayer(2, "Bob", 700)
local cy = mkPlayer(3, "Cyra", 600)
local low = mkPlayer(4, "Lowbie", 100)
local alt = mkPlayer(5, "Alt", 800)
local gm = mkPlayer(9, "Gm", 2); gm.access = true

talks["/worldboss"].onSay(gm, "/worldboss", "start kael")
assertEq(W.state.phase, "gather", "event started")
assertEq(W.state.index, 1, "Kaelgor")
assertEq(storage[cfg.rotationStorage], 1, "rotation stored")
assertEq(#W.state.portals, 2, "one portal per distinct temple")
local portal = Tile(W.state.portals[1]):getItemById(1387)
assertEq(portal.aid, cfg.aid.enter, "town portal action id")
assertEq(W.state.portals[1].x, 102, "first free offset (+2, 0)")
assert(broadcasts[#broadcasts]:find("WORLD BOSS"), "broadcast")
local ok3, err3 = W.start(2)
assertEq(ok3, false, "no second event"); assert(err3:find("already"), "reason")

-- entering
local from = Position(101, 100, 7)
moves[cfg.aid.enter].onStepIn(low, portal, W.state.portals[1], from)
assertEq(low.pos.x, 101, "level gate pushes back")
mcSet[5] = true
for _, p in ipairs({a, b, cy, alt}) do moves[cfg.aid.enter].onStepIn(p, portal, W.state.portals[1], from) end
assert(W.inLobby(a.pos), "Alice in the lobby")
assert(W.state.mc[5], "Alt flagged as multi-client at entry")
-- lobby protection and no PvP
assertEq(callbacks.onTargetCombat(b, a), RETURNVALUE_ACTIONNOTPERMITTEDINPROTECTIONZONE, "lobby is safe")
moves[cfg.aid.arena].onStepIn(a, nil, nil, a.pos)
moves[cfg.aid.arena].onStepIn(b, nil, nil, b.pos)
moves[cfg.aid.arena].onStepIn(cy, nil, nil, cy.pos)
moves[cfg.aid.arena].onStepIn(alt, nil, nil, alt.pos)
assert(W.inArena(a.pos), "Alice in the arena")
assertEq(callbacks.onTargetCombat(b, a), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "no PvP in the arena")
assertEq(callbacks.onTargetCombat(a, Player("Gm")), RETURNVALUE_NOERROR, "outside the arena: untouched")

-- the boss appears after gatherSeconds
advance(cfg.gatherSeconds * 1000)
assertEq(W.state.phase, "fight", "fight")
local boss = Monster(W.state.bossId)
assert(boss and boss.events["ChaosWorldBossHealth"] and boss.events["ChaosWorldBossDeath"], "boss events registered")
assertEq(boss.pos.x, 5016, "boss in the middle")

local hc = registry["ChaosWorldBossHealth"]
local function hit(p, amount)
  hc.onHealthChange(boss, p, amount, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, 0)
  boss.hp = math.max(0, boss.hp - amount)
end
hit(a, 4000000); hit(b, 2000000); hit(alt, 1000000)   -- 18M -> 11M (61%): phase 1 (70%)
advance(200)
local adds = 0; for _ in pairs(W.state.adds) do adds = adds + 1 end
assertEq(adds, 4, "phase 1 adds")
assertEq(monsters[next(W.state.adds)].maxhp, 150000, "adds get the configured health")
assertEq(monsters[next(W.state.adds)].hp, 150000, "adds start at full health")
hc.onHealthChange(boss, a, 500, COMBAT_HEALING, 0, COMBAT_NONE, 0)
assertEq(W.state.damage[1].damage, 4000000, "healing is not damage")
hit(cy, 50000) -- Cyra 50k = 0.28% of 18M: eligible
hit(a, 5000000) -- 6M -> 33%: phase 2 (enrage)
advance(200)
assert(W.state.enraged, "enraged at 40%")
local before = #combats
b:teleportTo(Position(5017, 5017, 7)) -- next to the boss
advance(9000) -- pulse every 8 s, checked every 3 s
assert(#combats > before, "enrage pulse hits players near the boss")
-- overkill is clamped to the remaining health
hit(b, 999999999)
assertEq(W.state.damage[2].damage, 2000000 + 5950000, "clamped to remaining health")

-- Alice logs out before the kill: her reward waits for her
a.online = false
registry["ChaosWorldBossDeath"].onDeath(boss)
assertEq(W.state.phase, "ending", "ending")
assertEq(#W.state.portals, 0, "town portals removed")
assertEq(portal.removed, true, "portal item removed")
for id in pairs(monsters) do assert(not (monsters[id].name == "Hellfire Fighter"), "adds removed") end
assert(b.bank >= cfg.reward.bankGold, "Bob paid into the bank")
assert((b.bag[29856] or 0) >= 3, "Bob got Chaos Orbs")
assert(cy.bank >= cfg.reward.bankGold, "Cyra (small share) still rewarded")
assertEq(alt.bank, 0, "multi-client character gets nothing")
assert(alt.msgs[#alt.msgs]:find("connection"), "and is told why")
assert(W.pending[1] and #W.pending[1] == 1, "offline reward kept")
assert(broadcasts[#broadcasts]:find("slain"), "victory broadcast")

-- ranking: Alice 9M, Bob 7.95M, Cyra 50k; Alt (multi-client) is not ranked
local ranked = W.computeShares(W.state.damage, W.state.maxHealth, 0.25, {[5] = true})
assertEq(ranked[1].name, "Alice", "top damage"); assertEq(#ranked, 3, "three eligible")

-- everyone inside goes home after the delay, arena cleaned
advance(cfg.exitDelaySeconds * 1000 + 10)
assertEq(W.state.phase, "idle", "idle again")
assertEq(b.pos.x, 100, "Bob back at the temple")
assert(not W.inside(cy.pos), "Cyra out")

-- Alice logs in: reward delivered, and she is moved out of the arena
a.online = true
registry["ChaosWorldBossLogin"].onLogin(a)
advance(2100)
assert(a.bank > 0, "pending reward delivered on login")
assertEq(W.pending[1], nil, "pending cleared")
assertEq(a.pos.x, 100, "logged in inside an idle arena -> temple")

-- full backpack: the rest goes to the inbox
local d = mkPlayer(6, "Dora", 900)
d.room = 2
W.deliver(d, {rank = 4, share = 0.1, bank = 10, items = {{id = 29856, count = 250}}, gear = 111, gearRarity = 7})
assertEq(d.bag[29856], 2, "what fits")
assertEq(d.inbox[29856], 248, "rest in the inbox (chunks of 100)")
assertEq(d.inbox[111], 1, "gear to the inbox too")

-- ---------------------------------------------------------------- timeout and stop
talks["/worldboss"].onSay(gm, "/worldboss", "start")
assertEq(W.state.index, 2, "rotation: next boss")
advance(cfg.gatherSeconds * 1000)
local boss2 = Monster(W.state.bossId)
advance(cfg.fightMinutes * 60 * 1000)
assertEq(W.state.phase, "ending", "time ran out")
assertEq(boss2.removed, true, "boss leaves")
assert(broadcasts[#broadcasts]:find("not defeated"), "failure broadcast")
advance(cfg.exitDelaySeconds * 1000 + 10)
assertEq(W.state.phase, "idle", "idle after failure")

talks["/worldboss"].onSay(gm, "/worldboss", "start random")
assert(W.state.index ~= 2, "random never repeats the last boss")
talks["/worldboss"].onSay(gm, "/worldboss", "stop")
assertEq(W.state.phase, "ending", "stopped")
advance(11000)
assertEq(W.state.phase, "idle", "stop closes quickly")
talks["/worldboss"].onSay(b, "/worldboss", "start") -- not staff
assertEq(W.state.phase, "idle", "players cannot start it")

-- ---------------------------------------------------------------- schedule
globals["ChaosWorldBossStartup"].onStartup()
assert(W.nextAt > os.time(), "next start in the future")
clock = (W.nextAt - base - 60) * 1000
globals["ChaosWorldBossSchedule"].onThink()
assert(broadcasts[#broadcasts]:find("1 minute"), "warning before the start")
clock = (W.nextAt - base) * 1000
globals["ChaosWorldBossSchedule"].onThink()
assertEq(W.state.phase, "gather", "scheduled start")

print("worldboss_test: ok")
