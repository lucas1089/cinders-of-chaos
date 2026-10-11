-- Run from the server/ folder: luajit tests/arena_flow_test.lua (mocked engine; CI runs it with LuaJIT and Lua 5.3)
-- The runtime of the arena (arena.lua): 2v2 queue as parties, match start, countdown block, team damage block, the
-- death catch and the gallery, the team win and the ratings, the release; a 1v1 left by a disconnect; a timeout.
local n = 0
setmetatable(_G, {__index = function(t, k)
  if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local unpack = table.unpack or unpack

local fails, count = 0, 0
local function check(cond, name)
  count = count + 1
  if not cond then fails = fails + 1; print("FAIL: " .. name) end
end
local function eq(a, b, name) check(a == b, name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

-- ---------------------------------------------------------------- engine mock
local events, globals, talks = {}, {}, {}
function CreatureEvent(name) local o = {name = name}; function o:type() end; function o:register() events[name] = o end; return o end
function GlobalEvent(name) local o = {}; function o:interval() end; function o:register() globals[name] = o end; return o end
function TalkAction(w) local o = {}; function o:separator() end; function o:register() talks[w] = o end; return o end
local callbacks = {}
EventCallback = setmetatable({register = function() end}, {__newindex = function(_, k, v) callbacks[k] = v end})

local queue, clock = {}, 0
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, args = {...}, due = clock + delay}; return #queue end
local realTime = os.time
local base = realTime({year = 2026, month = 10, day = 8, hour = 10, min = 0, sec = 0})
os.time = function(t) if t then return realTime(t) end return base + math.floor(clock / 1000) end
-- runs the due events and the arena tick (every second, like the engine)
local function advance(ms)
  local limit = clock + ms
  local nextTick = (math.floor(clock / 1000) + 1) * 1000
  while true do
    local best
    for i, e in ipairs(queue) do if e.due <= limit and (not best or e.due < queue[best].due) then best = i end end
    local due = best and queue[best].due or math.huge
    if nextTick <= limit and nextTick <= due then
      clock = nextTick; nextTick = nextTick + 1000
      globals.ChaosArenaTick.onThink(1000)
    elseif best then
      local e = table.remove(queue, best); clock = e.due; e.fn(unpack(e.args))
    else
      break
    end
  end
  clock = limit
end

json = {encode = function(t) return t end, decode = function() return nil end}

local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
Position = function(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end} end

local tiles = {}
local function newTile(pos)
  local t = {pos = pos, items = {}, pz = false}
  function t:hasFlag(f) return f == TILESTATE_PROTECTIONZONE and self.pz end
  function t:getGround() return self.items[1] end
  function t:getItemById(id) for _, it in ipairs(self.items) do if it.id == id then return it end end end
  function t:getItems() local l = {}; for i = 2, #self.items do l[#l + 1] = self.items[i] end; return l end
  function t:getCreatures() return {} end
  tiles[key(pos)] = t
  return t
end
function Tile(pos) return tiles[key(pos)] end
local storages = {}
Game = {
  createTile = function(pos) return tiles[key(pos)] or newTile(pos) end,
  createItem = function(id, c, pos)
    local t = tiles[key(pos)]
    local it = {id = id}
    function it:getId() return self.id end
    function it:remove() for i, x in ipairs(t.items) do if x == self then table.remove(t.items, i) break end end end
    t.items[#t.items + 1] = it
    return it
  end,
  getStorageValue = function(k) return storages[k] or -1 end,
  setStorageValue = function(k, v) storages[k] = v end,
}
function ItemType(id) return {getName = function() return "item " .. id end} end

local queries = {}
db = {query = function(q) queries[#queries + 1] = q; return true end, escapeString = function(s) return "'" .. s .. "'" end,
  lastInsertId = function() return 77 end, storeQuery = function() return nil end}
result = {}

local players, byName = {}, {}
local nextId = 1000
local function newPlayer(name, level, ip, maxHealth)
  nextId = nextId + 1
  local p = {id = nextId, guid = nextId - 1000, name = name, level = level, ip = ip, pos = {x = 100 + nextId % 10, y = 100, z = 7},
    health = maxHealth, maxHealth = maxHealth, mana = 100, maxMana = 100, events = {}, st = {}, msgs = {}, sends = {},
    skull = 0, infight = false, secure = false, items = {}}
  newTile(p.pos).pz = true
  function p:getId() return self.id end
  function p:getGuid() return self.guid end
  function p:getName() return self.name end
  function p:getLevel() return self.level end
  function p:getIp() return self.ip end
  function p:getGroup() return {getId = function() return 1 end, getAccess = function() return false end} end
  function p:getParty() return self.party end
  function p:getPosition() local q = Position(self.pos.x, self.pos.y, self.pos.z); return q end
  function p:teleportTo(pos) self.pos = {x = pos.x, y = pos.y, z = pos.z} end
  function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
  function p:sendCancelMessage(text) self.msgs[#self.msgs + 1] = text end
  function p:getHealth() return self.health end
  function p:getMaxHealth() return self.maxHealth end
  function p:setHealth(h) self.health = math.min(h, self.maxHealth) end
  function p:addHealth(a, b) if type(a) == "number" then self.health = math.min(self.maxHealth, self.health + a) end end
  function p:getMana() return self.mana end
  function p:getMaxMana() return self.maxMana end
  function p:addMana(m) self.mana = math.min(self.maxMana, self.mana + m) end
  function p:registerEvent(e) self.events[e] = true end
  function p:unregisterEvent(e) self.events[e] = nil end
  function p:removeCondition(t) if t == CONDITION_INFIGHT then self.infight = false; self.skull = 0 end end
  function p:hasCondition(t) return t == CONDITION_INFIGHT and self.infight end
  function p:isPzLocked() return false end
  function p:getSkull() return self.skull end
  function p:setSkull(s) self.skull = s end
  function p:setTarget() end
  function p:hasSecureMode() return self.secure end
  function p:getStorageValue(k) return self.st[k] or -1 end
  function p:setStorageValue(k, v) self.st[k] = v end
  function p:getTown() return {getTemplePosition = function() return Position(1, 1, 7) end} end
  function p:isPlayer() return true end
  function p:getPlayer() return self end
  function p:getMaster() return nil end
  function p:getInbox() return nil end
  function p:getItemCount(id) return self.items[id] or 0 end
  function p:addItem(id, c) self.items[id] = (self.items[id] or 0) + c end
  function p:sendExtendedOpcode(op, payload) self.sends[#self.sends + 1] = payload end
  players[p.id] = p
  byName[name] = p
  return p
end
function Player(x) if type(x) == "string" then return byName[x] end return players[x] end
function Game.getPlayers() local l = {}; for _, p in pairs(players) do l[#l + 1] = p end; return l end
local function party(a, b)
  local pt = {getLeader = function() return a end, getMembers = function() return {b} end}
  a.party, b.party = pt, pt
end
local function lastSend(p, action)
  for i = #p.sends, 1, -1 do if p.sends[i].action == action then return p.sends[i].data end end
end

-- ---------------------------------------------------------------- load
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/arena_core.lua")
dofile("data/scripts/chaos/arena.lua")
local S, A, cfg = ChaosArena, ChaosArenaCore, Chaos.arenaConfig
local records = {}
ChaosLeaderboard = {record = function(board, who, value, mode) records[#records + 1] = {board, who.name, value, mode} end}
local health, prepare = events.ChaosArenaHealth, events.ChaosArenaPrepareDeath
local function hit(target, attacker, dmg)
  local p, _, s = health.onHealthChange(target, attacker, dmg, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
  target.health = target.health - p - s
  return p + s
end

-- ---------------------------------------------------------------- 2v2
local a1, a2 = newPlayer("Ash", 950, 11, 1000), newPlayer("Bram", 1000, 12, 1000)
local b1, b2 = newPlayer("Cyra", 900, 13, 2000), newPlayer("Dorn", 980, 14, 2000)
local homeA1 = {x = a1.pos.x, y = a1.pos.y}

check(not S.join(a1, "2v2"), "2v2 without a party is refused")
party(a1, a2)
party(b1, b2)
a2.infight = true
check(not S.join(a1, "2v2"), "2v2 refused while the partner is in combat")
a2.infight = false
tiles[key(b2.pos)].pz = false
check(not S.join(b1, "2v2"), "2v2 refused while the partner is outside a protection zone")
tiles[key(b2.pos)].pz = true
check(S.join(a1, "2v2"), "party A queues")
check(S.join(b1, "2v2"), "party B queues")
check(S.isQueued(a2) and S.isQueued(b2), "the partners are queued too")
check(not S.join(a2, "1v1"), "a queued player cannot queue twice")

advance(2000)
local m = S.matchOf[a1:getId()]
check(m ~= nil, "match started")
eq(m and m.mode, "2v2", "2v2 match")
eq(#S.queue, 0, "queue empty")
check(S.matchOf[b2:getId()] == m, "all four in the match")
local L = A.layout(cfg, m.slot)
check(A.inArena(L, a1.pos) and A.inArena(L, b2.pos), "teleported into the arena")
check(a1.pos.x < L.center.x and b1.pos.x > L.center.x, "teams on opposite sides")
check(a1.events.ChaosArenaHealth and b2.events.ChaosArenaPrepareDeath, "combat events registered")
check(lastSend(a1, "start") and lastSend(a1, "start").team == 1, "client told: start, team 1")
check(lastSend(b1, "hud") ~= nil, "HUD sent")

-- countdown: nothing lands, the target callback refuses with a message
eq(hit(b1, a1, 300), 0, "no damage in the countdown")
eq(callbacks.onTargetCombat(a1, b1), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "no attack in the countdown")
advance(10000)
eq(m.phase, "fight", "fight after the countdown")
eq(callbacks.onTargetCombat(a1, b1), RETURNVALUE_NOERROR, "attack allowed in the fight")
eq(callbacks.onTargetCombat(a1, a2), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "no attack on a team mate")
eq(hit(a2, a1, 300), 0, "no team damage")
eq(hit(b1, a1, 300), 300, "opponent damage lands")
local outsider = newPlayer("Eve", 990, 15, 1000)
eq(callbacks.onTargetCombat(outsider, b1), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "no attack from outside the match")
eq(hit(b1, outsider, 300), 0, "no damage from outside the match")

-- the death catch: B1 keeps 1 health and goes to the gallery
local dealt = hit(b1, a1, 99999)
eq(b1.health, 1, "lethal hit leaves 1 health")
eq(dealt, 1699, "the hit is cut to health - 1")
check(m.players[b1:getId()].defeated, "B1 defeated")
advance(100)
check(b1.pos.y > L.arena.y2 and A.inSlot(L, b1.pos), "B1 moved to the gallery")
eq(hit(b1, a2, 50), 0, "the defeated cannot be hit")
eq(hit(a1, b1, 50), 0, "the defeated cannot hit")
eq(prepare.onPrepareDeath(b2, a1), false, "prepare-death safety net cancels the death")
check(m.players[b2:getId()].defeated, "the safety net defeats B2")
advance(1000)
eq(m.phase, "done", "both of team B down: decided")
eq(m.winner, 1, "team A wins")
local ra, rb = S.ratingOf(a1:getGuid(), "2v2"), S.ratingOf(b1:getGuid(), "2v2")
eq(ra.rating, 1020, "A rating +20")
eq(rb.rating, 980, "B rating -20")
eq(S.ratingOf(a2:getGuid(), "2v2").wins, 1, "A2 win counted")
eq(lastSend(a2, "end").delta, 20, "client told the change")
eq(lastSend(b2, "end").result, "loss", "loser told")
eq(a1.items[29857], 1, "first win of the day: Orb of Fate")
eq(a1.items[29856], 3, "win + first win Orbs of Upheaval")
eq(b1.items[29856], nil, "no reward for a loss")
local boards = 0
for _, r in ipairs(records) do if r[1] == "arena2v2" and r[4] == "max" then boards = boards + 1 end end
eq(boards, 4, "leaderboard recorded for all four")
advance(cfg.endDelaySeconds * 1000)
eq(S.matchOf[a1:getId()], nil, "released")
eq(a1.pos.x, homeA1.x, "back where the match started")
eq(b1.health, b1.maxHealth, "healed after the match")
check(not b1.events.ChaosArenaHealth, "events off after the match")
eq(S.matches[m.slot], nil, "slot free")

-- ---------------------------------------------------------------- 1v1: a disconnect is a loss
a1.party, a2.party, b1.party, b2.party = nil, nil, nil, nil
check(S.join(a1, "1v1"), "1v1 queue A1")
check(S.join(b2, "1v1"), "1v1 queue B2")
advance(2000)
local m2 = S.matchOf[a1:getId()]
check(m2 and m2.mode == "1v1", "1v1 started")
advance(10000)
b2.ip = 0 -- connection lost
advance(cfg.disconnectSeconds * 1000 + 1000)
eq(m2.phase, "done", "the disconnect ends the match")
eq(m2.winner, 1, "the one who stayed wins")
eq(S.ratingOf(b2:getGuid(), "1v1").losses, 1, "the leaver gets a loss")
check(b2.pos.x == 100 + b2.id % 10, "the leaver is sent back at once")
advance(cfg.endDelaySeconds * 1000)
b2.ip = 14

-- ---------------------------------------------------------------- 1v1: timeout, the health share decides
cfg.fightSeconds = 30
check(S.join(a2, "1v1"), "1v1 queue A2")
check(S.join(b1, "1v1"), "1v1 queue B1")
advance(2000)
local m3 = S.matchOf[a2:getId()]
check(m3 ~= nil, "third match")
check(m3.slot ~= nil, "slot taken")
advance(10000)
hit(a2, b1, 400) -- A2 at 60%
hit(b1, a2, 1000) -- B1 at 50%
advance(31000)
eq(m3.phase, "done", "time ran out")
eq(m3.winner, 1, "60% beats 50%")
advance(cfg.endDelaySeconds * 1000)

-- ---------------------------------------------------------------- parallel slots
for _, p in ipairs({a1, b2, a2, b1}) do check(S.join(p, "1v1"), "queue for parallel " .. p.name) end
advance(2000)
local ma, mb = S.matchOf[a1:getId()], S.matchOf[b1:getId()]
check(ma and mb and ma ~= mb, "two matches at once")
check(ma and mb and ma.slot ~= mb.slot, "in different slots")
local La, Lb = A.layout(cfg, ma.slot), A.layout(cfg, mb.slot)
check(A.inArena(La, a1.pos) and A.inArena(Lb, b1.pos) and not A.inSlot(La, b1.pos), "each pair in its own instance")
eq(S.stopAll(), 2, "staff stop ends both, not rated")
advance(cfg.endDelaySeconds * 1000)
eq(next(S.matches), nil, "all slots free")

-- ---------------------------------------------------------------- multi-client refusal
local c1, c2 = newPlayer("Fen", 900, 99, 1000), newPlayer("Gil", 900, 99, 1000)
check(not S.join(c1, "1v1"), "multi-client refused")
check(c1.msgs[#c1.msgs]:find("connection") ~= nil, "multi-client message")
storages[Chaos.multiClient.offStorage] = 1
check(S.join(c1, "1v1"), "allowed with the multi-client blocks off")
S.leaveQueue(c1, true)

-- ---------------------------------------------------------------- a shutdown / a closed server: no rating change
storages[Chaos.multiClient.offStorage] = nil
local function ratingSnapshot(list)
  local out = {}
  for _, p in ipairs(list) do local r = S.ratingOf(p:getGuid(), "1v1"); out[#out + 1] = r.rating .. "/" .. r.wins .. "/" .. r.losses .. "/" .. r.draws end
  return table.concat(out, " ")
end
check(S.join(a1, "1v1"), "shutdown: queue A1"); check(S.join(b2, "1v1"), "shutdown: queue B2")
advance(2000)
local ms = S.matchOf[a1:getId()]
check(ms ~= nil, "shutdown: match started")
advance(10000)
local before = ratingSnapshot({a1, b2})
globals.ChaosArenaShutdown.onShutdown()
eq(ms.phase, "done", "onShutdown stops the match")
events.ChaosArenaLogout.onLogout(a1); events.ChaosArenaLogout.onLogout(b2) -- the kicks
eq(ratingSnapshot({a1, b2}), before, "onShutdown: no rating change")
check(a1.pos.x == 100 + a1.id % 10 and b2.pos.x == 100 + b2.id % 10, "onShutdown: both sent back")
advance(cfg.endDelaySeconds * 1000)
-- a closed server (no onShutdown): the first kick stops the match unrated
check(S.join(a1, "1v1"), "closed: queue A1"); check(S.join(b2, "1v1"), "closed: queue B2")
advance(2000)
local mc = S.matchOf[a1:getId()]
check(mc ~= nil, "closed: match started")
advance(10000)
before = ratingSnapshot({a1, b2})
Game.getGameState = function() return GAME_STATE_CLOSED end
events.ChaosArenaLogout.onLogout(b2)
eq(mc.phase, "done", "closed: the kick stops the match")
eq(ratingSnapshot({a1, b2}), before, "closed: no loss for the kicked player, no win for the other")
events.ChaosArenaLogout.onLogout(a1)
Game.getGameState = nil
advance(cfg.endDelaySeconds * 1000)

-- ---------------------------------------------------------------- 3v3 (a party of three) and the season hook
local seasonCalls = {}
ChaosPvpSeason = {recordArena = function(mode, sides, winner)
  seasonCalls[#seasonCalls + 1] = {mode = mode, n1 = #sides[1], n2 = #sides[2], winner = winner}
  local out = {}
  for side = 1, 2 do for _, e in ipairs(sides[side]) do out[e.guid] = {before = 1500, after = side == winner and 1520 or 1480, delta = side == winner and 20 or -20} end end
  return out
end}
local function party3(a, b, c)
  local pt = {getLeader = function() return a end, getMembers = function() return {b, c} end}
  a.party, b.party, c.party = pt, pt, pt
end
local t1 = {newPlayer("Hal", 900, 21, 1000), newPlayer("Ivo", 920, 22, 1000), newPlayer("Jun", 940, 23, 1000)}
local t2 = {newPlayer("Kai", 910, 24, 1000), newPlayer("Lux", 930, 25, 1000), newPlayer("Mae", 950, 26, 1000)}
party(t1[1], t1[2])
check(not S.join(t1[1], "3v3"), "3v3 refused for a party of two")
check(t1[1].msgs[#t1[1].msgs]:find("exactly 3") ~= nil, "3v3 party size message")
party3(t1[1], t1[2], t1[3])
party3(t2[1], t2[2], t2[3])
check(S.join(t1[1], "3v3"), "3v3 party A queues")
check(S.join(t2[1], "3v3"), "3v3 party B queues")
advance(2000)
local m6 = S.matchOf[t1[3]:getId()]
check(m6 ~= nil and m6.mode == "3v3", "3v3 started")
local L6 = A.layout(cfg, m6.slot)
local spots = {}
for _, p in ipairs({t1[1], t1[2], t1[3], t2[1], t2[2], t2[3]}) do
  check(A.inArena(L6, p.pos), "3v3 fighter inside " .. p.name)
  spots[p.pos.x .. "," .. p.pos.y] = true
end
local nspots = 0
for _ in pairs(spots) do nspots = nspots + 1 end
eq(nspots, 6, "six different spawn tiles")
advance(10000)
for _, p in ipairs(t2) do hit(p, t1[1], 99999) end
advance(1000)
eq(m6.phase, "done", "3v3: all three of B down")
eq(m6.winner, 1, "3v3: A wins")
eq(#seasonCalls, 1, "the season rating is recorded once")
eq(seasonCalls[1].mode, "3v3", "for the 3v3 bracket")
eq(seasonCalls[1].n1 + seasonCalls[1].n2, 6, "with all six")
eq(lastSend(t1[2], "end").season.after, 1520, "the season change goes to the client")
local b3 = 0
for _, r in ipairs(records) do if r[1] == "arena3v3" then b3 = b3 + 1 end end
eq(b3, 6, "the 3v3 board recorded for all six")
advance(cfg.endDelaySeconds * 1000)
ChaosPvpSeason = nil

print(string.format("arena_flow_test: %d checks, %d failed", count, fails))
if fails > 0 then os.exit(1) end
