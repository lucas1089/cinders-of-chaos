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
  function m:getTarget() return self.target end
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
  p.hp, p.maxhp, p.storage, p.events = 20000, 20000, {}, {}
  function p:getHealth() return self.hp end
  function p:getMaxHealth() return self.maxhp end
  function p:getStorageValue(k) return self.storage[k] or -1 end
  function p:setStorageValue(k, v) self.storage[k] = v end
  function p:registerEvent(e) self.events[e] = true end
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
-- the systems worldboss.lua feeds (guarded there): name plate titles, leaderboards, achievements
local titleSources, lbCalls, achCalls = {}, {}, {}
ChaosTitles = {register = function(name, fn) titleSources[name] = fn end}
ChaosLeaderboard = {
  recordShares = function(list) lbCalls[#lbCalls + 1] = {board = "worldboss", n = #list} end,
  record = function(board, who, value) lbCalls[#lbCalls + 1] = {board = board, name = who.name, value = value} end
}
ChaosAchievements = {progress = function(who, key) achCalls[#achCalls + 1] = who.name .. ":" .. key end}
local toasts = {}
ChaosNotify = {gmBroadcast = function(_, text) toasts[#toasts + 1] = text end}
dofile("data/scripts/chaos/worldboss.lua")
assert(titleSources.worldboss, "role titles registered with ChaosTitles")

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
local podium = {top = 3, placeMinPercent = 0, categories = {
  {key = "damage", name = "Damage", title = "Bossbreaker", rewards = {{{id = 29857, count = 5}}, {{id = 2160, count = 30}}}},
  {key = "healing", name = "Healing", title = "Lifewarden", rewards = {{{id = 2160, count = 7}}}, uniqueChance = {400}},
  {key = "tanking", name = "Tanking", title = "Bulwark", rewards = {{{id = 29857, count = 9}}}}}}
local r = {bankGold = 1000, bankGoldPool = 100000, base = {{id = 29856, count = 3}, {id = 29857, count = 1}},
  pool = {{id = 29856, count = 60}, {id = 29857, count = 25}}, podium = podium,
  gearChance = 1500, gearShareBonus = 3000, gearRarity = {6, 9}, uniqueChance = 50, uniqueShareBonus = 300}
W.placeRoles(shares, podium, 20000000)
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
assertEq(A.titles[1].text, "Bossbreaker", "damage 1st: role title"); assertEq(A.titles[1].place, 1, "title place")
assertEq(#C3.titles, 1, "3rd in damage still gets the title")
assertEq(A.gear, 111, "gear rolled"); assertEq(A.gearRarity, 6, "gear rarity")
assertEq(A.unique, 9001, "unique rolled")
local none = W.computeRewards(shares, r, boss1, {9001}, function(a, b) if b then return a end; if a == 10000 then return 10000 end; return 1 end)
assertEq(none[1].gear, nil, "gear roll failed"); assertEq(none[1].unique, nil, "unique roll failed")
-- chance grows with the share: 1500 + 0.6*3000 = 3300
local g = W.computeRewards({shares[1]}, r, boss1, {}, function(a, b) if b then return a end; if a == 10000 then return 3300 end; return 1 end)
assertEq(g[1].gear, 111, "share bonus on the gear chance")
local g2 = W.computeRewards({shares[3]}, r, boss1, {}, function(a, b) if b then return a end; if a == 10000 then return 3300 end; return 1 end)
assertEq(g2[1].gear, nil, "small share, same roll fails")

-- ---------------------------------------------------------------- roles: credits and caps
local ro = cfg.roles
assertEq(W.tankCredit(5000, 20000, true, ro), 5000, "a survived hit counts")
assertEq(W.tankCredit(12000, 20000, true, ro), ro.tankHitCap, "capped per hit")
assertEq(W.tankCredit(5000, 20000, false, ro), 5000 * ro.offTargetWeight, "splash (attacker not targeting you) counts less")
assertEq(W.tankCredit(5000, 5000, true, ro), 0, "a killing hit counts nothing")
assertEq(W.tankCredit(5000, 0, true, ro), 0, "dead: nothing")
local hc1, he1 = W.healCredit(8000, 6000, 10000, false, ro)
assertEq(hc1, 6000, "healing capped at the missing health"); assertEq(he1, 6000, "effective healing")
assertEq(W.healCredit(8000, 6000, 2500, false, ro), 2500, "capped at the boss damage not healed yet")
assertEq(W.healCredit(8000, 0, 9000, false, ro), 0, "overhealing counts nothing")
assertEq(W.healCredit(3000, 6000, 9000, true, ro), 3000 * ro.selfHealWeight, "self-healing at selfHealWeight")
assertEq(ro.selfHealWeight, 0, "self-healing does not count (documented)")

-- ---------------------------------------------------------------- combined score, eligibility, top 3 per category
assertEq(W.score({damage = 100, healing = 50, tanking = 40}, {healWeight = 1, tankWeight = 0.5}), 170, "combined score")
assertEq(W.score({damage = 100, healing = 50}), 100, "no weights: damage only")
local wts = {healWeight = 1, tankWeight = 0.5}
local st = {
  [11] = {name = "Dps", damage = 900000, healing = 0, tanking = 0, seq = {damage = 5}},
  [12] = {name = "Healer", damage = 1000, healing = 60000, tanking = 0, seq = {damage = 1, healing = 9}},
  [13] = {name = "Tank", damage = 20000, healing = 0, tanking = 80000, seq = {damage = 2, tanking = 7}},
  [14] = {name = "Afk", damage = 0, healing = 0, tanking = 0, seq = {}},
  [15] = {name = "Tank2", damage = 15000, healing = 0, tanking = 80000, seq = {damage = 6, tanking = 3}},
  [16] = {name = "Leech", damage = 20000, healing = 0, tanking = 20000, seq = {damage = 3, tanking = 4}}
}
-- boss 20M, min 0.25% = 50000: Healer 61000, Tank 60000, Tank2 55000 qualify with little or no damage
local sh, tot = W.computeShares(st, 20000000, 0.25, nil, wts)
assertEq(#sh, 4, "Dps, Healer, Tank, Tank2 (Afk and Leech 30000 are under the minimum)")
assertEq(tot, 900000 + 61000 + 60000 + 55000, "total score")
local byName = {}; for _, x in ipairs(sh) do byName[x.name] = x end
assertEq(byName.Healer.scoreRank, 2, "score rank"); assertEq(byName.Healer.share, 61000 / tot, "share by score")
assertEq(byName.Dps.rank, 1, "rank = damage place (achievements: most damage)"); assertEq(byName.Healer.rank, 4, "healer last in damage")
local pod = W.placeRoles(sh, cfg.reward.podium, 20000000) -- placeMin 0.1% = 20000
assertEq(#pod.damage, 2, "damage podium: Tank2's 15000 is under the place minimum, Healer's 1000 too")
assertEq(pod.damage[1].name, "Dps", "damage 1st"); assertEq(pod.damage[2].name, "Tank", "damage 2nd")
assertEq(#pod.healing, 1, "one healer"); assertEq(pod.healing[1].name, "Healer", "healing 1st")
assertEq(pod.tanking[1].name, "Tank2", "tie at 80000: who reached it first places higher")
assertEq(pod.tanking[2].name, "Tank", "tie: 2nd")
assertEq(byName.Tank.places.damage, 2, "one player in two categories"); assertEq(byName.Tank.places.tanking, 2, "and tanking")
assertEq(byName.Dps.places.tanking, nil, "no tanking, no place")
-- ties on equal value and equal seq: the lower guid; only the top 3 place even when the 4th has the same value
local tie = {[21] = {name = "Late", damage = 30000, seq = {damage = 8}}, [22] = {name = "Early", damage = 30000, seq = {damage = 4}},
  [24] = {name = "Later", damage = 30000, seq = {damage = 8}}, [25] = {name = "Fourth", damage = 30000, seq = {damage = 9}}}
local tsh = W.computeShares(tie, 1000000, 0, nil, wts)
local tpod = W.placeRoles(tsh, cfg.reward.podium, 1000000)
assertEq(tpod.damage[1].name, "Early", "tie: first to reach"); assertEq(tpod.damage[2].name, "Late", "tie: lower guid")
assertEq(tpod.damage[3].name, "Later", "3rd"); assertEq(#tpod.damage, 3, "top 3 only")
assertEq(tsh[1].rank ~= nil, true, "damage rank set")

-- ---------------------------------------------------------------- role rewards
local fail = function(a, b) if b then return a end; if a == 10000 then return 10000 end; return 1 end
local rr = W.computeRewards(sh, cfg.reward, boss1, {9001}, fail)
local rb = {}; for _, x in ipairs(rr) do rb[x.name] = x end
local function count(rw, id) for _, it in ipairs(rw.items) do if it.id == id then return it.count end end; return 0 end
local cats = cfg.reward.podium.categories
local tankShare = byName.Tank.share
assertEq(count(rb.Tank, 29857), 1 + math.floor(25 * tankShare) + cats[1].rewards[2][1].count + cats[3].rewards[2][1].count,
  "Tank: base + share + damage 2nd + tanking 2nd Divine Orbs")
assertEq(count(rb.Tank, 2160), cats[1].rewards[2][2].count + cats[3].rewards[2][2].count, "Tank: crystal coins of both places")
assertEq(#rb.Tank.titles, 2, "two role titles"); assertEq(rb.Tank.titles[2].text, "Bulwark", "tank title")
assertEq(rb.Healer.titles[1].text, "Lifewarden", "healer title"); assertEq(count(rb.Healer, 2160), cats[2].rewards[1][2].count, "healer 1st")
assertEq(rb.Healer.bank, cfg.reward.bankGold + math.floor(cfg.reward.bankGoldPool * byName.Healer.share), "healer paid by share")
assertEq(#rb.Dps.titles, 1, "Dps: damage title only"); assertEq(rb.Dps.unique, nil, "no unique on failed rolls")
-- the role unique roll: the participation roll fails, the 1st-place healing roll (uniqueChance[1]) succeeds
local calls = 0
local roleRng = function(a, b) if b then return a end; if a == 10000 then calls = calls + 1; return calls < 3 and 10000 or cats[2].uniqueChance[1] end; return 1 end
local ur = W.computeRewards({byName.Healer}, cfg.reward, boss1, {9001}, roleRng)
assertEq(ur[1].unique, 9001, "unique from the healing podium roll"); assertEq(calls, 3, "gear, participation, role roll")
local noRole = W.computeRewards({byName.Dps}, {base = {}, pool = {}}, boss1, {9001}, fail)
assertEq(#noRole[1].titles, 0, "no podium config: no titles")
assertEq(W.podiumText(pod, cfg.reward.podium), "Top damage: Dps 900k, Tank 20k. Top healing: Healer 60k. Top tanking: Tank2 80k, Tank 80k.", "result text")

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
assertEq(W.state.stats[1].damage, 4000000, "healing is not damage")
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
assertEq(W.state.stats[2].damage, 2000000 + 5950000, "clamped to remaining health")

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
local ranked = W.computeShares(W.state.stats, W.state.maxHealth, 0.25, {[5] = true}, cfg.roles)
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

-- ---------------------------------------------------------------- roles in a fight: Tara tanks, Hela heals, both hit
for k in pairs(lbCalls) do lbCalls[k] = nil end
for k in pairs(achCalls) do achCalls[k] = nil end
local tara, hela, dex = mkPlayer(7, "Tara", 900), mkPlayer(8, "Hela", 800), mkPlayer(10, "Dex", 900)
talks["/worldboss"].onSay(gm, "/worldboss", "start kael")
for _, p in ipairs({tara, hela, dex}) do
  moves[cfg.aid.enter].onStepIn(p, nil, W.state.portals[1], from)
  moves[cfg.aid.arena].onStepIn(p, nil, nil, p.pos)
end
assert(tara.events["ChaosWorldBossRoles"] and tara.events["ChaosWorldBossRoleDeath"], "role events on players entering the arena")
advance(cfg.gatherSeconds * 1000)
local kb = Monster(W.state.bossId)
local rh = registry["ChaosWorldBossRoles"].onHealthChange
local function takes(p, src, amount) rh(p, src, amount, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, 0); p.hp = math.max(0, p.hp - amount) end
local function heals(p, healer, amount) rh(p, healer, amount, COMBAT_HEALING, 0, COMBAT_NONE, 0); p.hp = math.min(p.maxhp, p.hp + amount) end
local S = function(p) return W.state.stats[p.guid] or {damage = 0, healing = 0, tanking = 0, deaths = 0} end
heals(tara, hela, 1000)
assertEq(S(hela).healing, 0, "nothing to heal: no credit")
kb.target = tara
takes(tara, kb, 5000)
assertEq(S(tara).tanking, 0, "no tanking before the player fights (anti-AFK)")
assertEq(W.state.debt[7], 5000, "but the damage is open for healing")
assertEq(callbacks.onTargetCombat(tara, kb), RETURNVALUE_NOERROR, "attacking the boss is allowed")
takes(tara, kb, 6000)                                 -- 15000 -> 9000
assertEq(S(tara).tanking, 6000, "targeted hit")
heals(tara, hela, 30000)                              -- missing 11000, debt 11000
assertEq(S(hela).healing, 11000, "healing capped at the missing health")
assertEq(W.state.debt[7], 0, "debt healed")
takes(tara, kb, 12000)                                -- 20000 -> 8000
assertEq(S(tara).tanking, 6000 + ro.tankHitCap, "capped per hit")
kb.target = dex
takes(tara, kb, 2000)                                 -- splash: 8000 -> 6000
assertEq(S(tara).tanking, 6000 + ro.tankHitCap + 2000 * ro.offTargetWeight, "splash at offTargetWeight")
local add = Game.createMonster("Hellfire Fighter", Position(5016, 5020, 7)); W.state.adds[add.id] = true; add.target = tara
takes(tara, add, 1000)                                -- 6000 -> 5000
local stranger = Game.createMonster("Rat", Position(5016, 5021, 7)); stranger.target = tara
takes(tara, stranger, 1000)                           -- 5000 -> 4000, not a boss source
local tanked = 6000 + ro.tankHitCap + 2000 * ro.offTargetWeight + 1000
assertEq(S(tara).tanking, tanked, "an add counts, other monsters do not")
heals(tara, tara, 3000)                               -- 4000 -> 7000
assertEq(S(tara).healing, 0, "self-healing not counted")
hela:teleportTo(Position(L.lobbyArrival.x, L.lobbyArrival.y, 7))
heals(tara, hela, 2000)                               -- 7000 -> 9000
assertEq(S(hela).healing, 11000, "healing from outside the arena does not count")
moves[cfg.aid.arena].onStepIn(hela, nil, nil, hela.pos)
heals(tara, hela, 50000)                              -- missing 11000, debt 12000 + 2000 + 1000 (rat: none) - 3000 - 2000
assertEq(S(hela).healing, 11000 + 10000, "back in the arena: capped at the boss damage not healed yet")
-- a killing hit counts nothing, death stops further gains, credit stays
tara.hp = 3000
takes(tara, kb, 5000)
assertEq(S(tara).tanking, tanked, "killing hit not counted")
registry["ChaosWorldBossRoleDeath"].onDeath(tara)
assertEq(S(tara).deaths, 1, "death counted"); assertEq(W.state.debt[7], 0, "no healing credit for the old life")
tara.hp = 20000
takes(tara, kb, 3000)
assertEq(S(tara).tanking, tanked, "no gains after dying until the player fights again")
-- damage: Tara and Hela hit the boss a little, Dex a lot
local bh = registry["ChaosWorldBossHealth"].onHealthChange
local function hitBoss(p, amount) bh(kb, p, amount, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, 0); kb.hp = math.max(0, kb.hp - amount) end
hitBoss(tara, 30000); hitBoss(hela, 30000); hitBoss(dex, 17000000)
assertEq(S(tara).damage, 30000, "tank damage")
-- Tara: 30000 + 16000 x 0.5 = 38000 < 45000 (0.25% of 18M); she tanks 20000 more after attacking again (equal
-- damage: Tara hit first and places higher)
tara.hp = 20000; kb.target = tara
for _ = 1, 4 do takes(tara, kb, 5000); tara.hp = 20000 end
tanked = tanked + 20000
assertEq(S(tara).tanking, tanked, "active again after attacking")
for k in pairs(toasts) do toasts[k] = nil end
registry["ChaosWorldBossDeath"].onDeath(kb)
assertEq(#toasts, 3, "one result toast per category")
assertEq(toasts[2], "World boss slain! Top healing: Hela 21k.", "healing toast")
local last = broadcasts[#broadcasts]
assert(last:find("Top damage: Dex 17.0M, Tara 30k, Hela 30k", 1, true), last)
assert(last:find("Top healing: Hela 21k", 1, true), last)
assert(last:find("Top tanking: Tara 36k", 1, true), last)
assert(tara.bank >= cfg.reward.bankGold and hela.bank >= cfg.reward.bankGold, "tank and healer get the base reward")
assert(tara.storage[ro.titleStorage + 2] > os.time(), "Bulwark held for titleDays")
assertEq(tara.storage[ro.titleStorage + 2] - os.time(), ro.titleDays * 86400, "title expiry")
assert(hela.storage[ro.titleStorage + 1] > os.time(), "Lifewarden")
local tt = titleSources.worldboss(tara)
local names = {}; for _, x in ipairs(tt) do names[#names + 1] = x.text end
assertEq(table.concat(names, ","), "Bossbreaker,Bulwark", "Tara's titles: 3rd in damage, 1st in tanking")
assertEq(#titleSources.worldboss(dex), 1, "Dex: damage title")
assert(tara.msgs[#tara.msgs]:find("Bulwark"), "told about the title")
local boards = {}
for _, c in ipairs(lbCalls) do boards[c.board .. ":" .. tostring(c.name)] = c.value or c.n end
assertEq(boards["worldboss:nil"], 3, "World Boss board: every rewarded player")
assertEq(boards["bosshealer:Hela"], 21000, "Boss Healer board"); assertEq(boards["bosstank:Tara"], math.floor(tanked), "Boss Tank board")
assertEq(boards["bosstank:Dex"], nil, "no tanking, no row")
local ach = table.concat(achCalls, " ")
assert(ach:find("Hela:wb_heal_top", 1, true) and ach:find("Tara:wb_tank_top", 1, true) and ach:find("Tara:wb_role_podium", 1, true), ach)
assert(not ach:find("Dex:wb_role_podium", 1, true), "damage podium is not a role podium")
advance(cfg.exitDelaySeconds * 1000 + 10)
assertEq(W.state.phase, "idle", "idle after the role fight")
-- expired titles disappear
tara.storage[ro.titleStorage + 2] = os.time() - 1
assertEq(#titleSources.worldboss(tara), 1, "expired title gone")

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
