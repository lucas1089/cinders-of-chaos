-- Run from the server/ folder: luajit tests/battleground_flow_test.lua (mocked engine; CI runs it with LuaJIT and Lua 5.3)
-- The runtime of the battleground (battleground.lua with arena_season.lua): queue refusals, a party and solos forming a
-- 5v5 after the fill time, the runtime map, the preparation (no damage, kept in the base), a capture and the score,
-- the death catch, the graveyard and the respawn wave, the enemy base wards, level normalisation, an AFK deserter,
-- the end (season rating, honor, weekly first win, leaderboard, summary), the release, the vendor, a logout deserter
-- and a staff stop.
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
local base = realTime({year = 2026, month = 10, day = 14, hour = 10, min = 0, sec = 0})
os.time = function(t) if t then return realTime(t) end return base + math.floor(clock / 1000) end
local function advance(ms)
  local limit = clock + ms
  local nextTick = (math.floor(clock / 1000) + 1) * 1000
  while true do
    local best
    for i, e in ipairs(queue) do if e.due <= limit and (not best or e.due < queue[best].due) then best = i end end
    local due = best and queue[best].due or math.huge
    if nextTick <= limit and nextTick <= due then
      clock = nextTick; nextTick = nextTick + 1000
      globals.ChaosBgTick.onThink(1000)
    elseif best then
      local e = table.remove(queue, best); clock = e.due; e.fn(unpack(e.args))
    else
      break
    end
  end
  clock = limit
end

json = {encode = function(t) return t end, decode = function(t) return t end}
local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
Position = function(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end} end

local tiles, created = {}, 0
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
  createTile = function(pos) created = created + 1; return tiles[key(pos)] or newTile(pos) end,
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
  broadcastMessage = function() end
}
function ItemType(id) return {getName = function() return "item " .. id end, getClientId = function() return id end} end

local queries = {}
db = {query = function(q) queries[#queries + 1] = q; return true end, escapeString = function(s) return "'" .. tostring(s) .. "'" end,
  lastInsertId = function() return 77 end, storeQuery = function() return nil end, asyncQuery = function() end}
result = {}

local players, byName = {}, {}
local nextId = 1000
local function newPlayer(name, level, voc, maxHealth)
  nextId = nextId + 1
  local p = {id = nextId, guid = nextId - 1000, name = name, level = level, ip = nextId, voc = voc or 5,
    pos = {x = 100 + nextId % 50, y = 100, z = 7}, health = maxHealth or 3000, maxHealth = maxHealth or 3000, mana = 100,
    maxMana = 100, events = {}, st = {}, msgs = {}, sends = {}, skull = 0, infight = false, secure = false, items = {}}
  newTile(p.pos).pz = true
  function p:getId() return self.id end
  function p:getGuid() return self.guid end
  function p:getName() return self.name end
  function p:getLevel() return self.level end
  function p:getIp() return self.ip end
  function p:getAccountId() return self.guid + 500 end
  function p:getVocation() local v = self.voc; return {getId = function() return v end, getName = function() return "voc" .. v end} end
  function p:getGroup() return {getId = function() return self.staff and 6 or 1 end, getAccess = function() return self.staff or false end} end
  function p:getParty() return self.party end
  function p:getPosition() return Position(self.pos.x, self.pos.y, self.pos.z) end
  function p:teleportTo(pos) self.pos = {x = pos.x, y = pos.y, z = pos.z} end
  function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
  function p:sendCancelMessage(text) self.msgs[#self.msgs + 1] = text end
  function p:getHealth() return self.health end
  function p:getMaxHealth() return self.maxHealth end
  function p:setHealth(h) self.health = math.min(h, self.maxHealth) end
  function p:addHealth(a) if type(a) == "number" then self.health = math.min(self.maxHealth, self.health + a) end end
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
  function p:getMaster() return nil end
  function p:getInbox() return nil end
  function p:getItemCount(id) return self.items[id] or 0 end
  function p:addItem(id, c) self.items[id] = (self.items[id] or 0) + c end
  function p:sendExtendedOpcode() end
  players[p.id] = p
  byName[name] = p
  return p
end
function Player(x) if type(x) == "string" then return byName[x] end return players[x] end
function Game.getPlayers() local l = {}; for _, p in pairs(players) do l[#l + 1] = p end; return l end
local function makeParty(leader, ...)
  local members = {...}
  local pt = {getLeader = function() return leader end, getMembers = function() return members end}
  leader.party = pt
  for _, m in ipairs(members) do m.party = pt end
end
local function lastSend(p, action)
  for i = #p.sends, 1, -1 do if p.sends[i].action == action then return p.sends[i].data end end
end

-- ---------------------------------------------------------------- load
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.sendChunked = function(p, op, payload) p.sends[#p.sends + 1] = payload; return true end
local cosmetics = {}
ChaosCosmetics = {owns = function(acc, k) return cosmetics[acc .. k] == true end,
  grant = function(acc, k) cosmetics[acc .. k] = true; return true end}
local records = {}
ChaosLeaderboard = {record = function(board, who, value, mode) records[#records + 1] = {board, who.name, value, mode} end}
dofile("data/scripts/chaos/arena_season.lua")
dofile("data/scripts/chaos/battleground.lua")
local B, K, cfg, PS = ChaosBattleground, ChaosBattlegroundCore, Chaos.battlegroundConfig, ChaosPvpSeason
eq(ChaosOpcodes.battleground, 200, "opcode registered")
local health, prepare = events.ChaosBgHealth, events.ChaosBgPrepareDeath
local function hit(target, attacker, dmg, typ)
  local p, _, s = health.onHealthChange(target, attacker, dmg, typ or COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
  if (typ or COMBAT_PHYSICALDAMAGE) == COMBAT_HEALING then
    target.health = math.min(target.maxHealth, target.health + p)
  else
    target.health = target.health - p - s
  end
  return p + s
end

-- ---------------------------------------------------------------- the queue
local tank = newPlayer("Aldo", 450, 8) -- Juggernaut: tank
local healer = newPlayer("Bea", 470, 10) -- Illusionist: healer
local dps1 = newPlayer("Cato", 460, 5)
makeParty(tank, healer, dps1)
local low = newPlayer("Low", 80, 5)
check(not B.join(low, "dps"), "below level 100 refused")
check(low.msgs[#low.msgs]:find("level 100") ~= nil, "level message")
check(not B.join(healer, "healer"), "a party member cannot queue the party")
tiles[key(dps1.pos)].pz = false
check(not B.join(tank, "tank"), "a member outside a protection zone stops the party")
tiles[key(dps1.pos)].pz = true
local hi = newPlayer("High", 900, 5)
makeParty(tank, healer, hi)
check(not B.join(tank, "tank"), "a member of another level bracket stops the party")
check(tank.msgs[#tank.msgs]:find("bracket") ~= nil, "bracket message")
makeParty(tank, healer, dps1)
check(B.join(tank, "tank"), "the party of three queues")
check(B.isQueued(healer) and B.isQueued(dps1), "the whole party is queued")
eq(B.queued[healer:getId()].members[2].role, "healer", "the Illusionist queues as its main role, healer")
ChaosArena = {isQueued = function(p) return p.name == "Ari" end, isInside = function() return false end}
local ari = newPlayer("Ari", 450, 5)
check(not B.join(ari, "dps"), "refused while in the arena queue")
ChaosArena = nil
local solos = {}
local roles = {13, 19, 5, 5, 3, 3, 11} -- Samurai (tank), Iron Sage (healer), DPS
for i, v in ipairs(roles) do
  solos[i] = newPlayer("Solo" .. i, i == 7 and 300 or 430 + i * 10, v)
  check(B.join(solos[i], nil), "solo " .. i .. " queues")
end
eq(B.queued[solos[1]:getId()].members[1].role, "tank", "a Samurai's main role: tank")
local st = B.stateOf(solos[3])
check(st.queue and st.queue.players == 10 and st.queue.est >= 1, "state: queued, 10 in the group, an estimate")
eq(st.bracket.key, "b2", "bracket b2")
check(st.season and st.season.brackets.bg and st.season.brackets.bg.placementLeft == 5, "season view: 5 placement matches")
eq(#st.vendor, #cfg.vendor, "the vendor offers")
check(B.isBusy(solos[1]), "busy for the arena")

-- 10 players: 5v5 only after the fill time
advance(10000)
eq(next(B.matches), nil, "no 5v5 before the fill time")
advance((cfg.fillSeconds - 9) * 1000)
local m = B.matchOf[tank:getId()]
check(m ~= nil, "match started")
eq(m and m.size, 5, "5v5")
eq(#B.queue, 0, "queue empty")
check(created > 1000, "the map was built (" .. created .. " tiles)")
local L = K.layout(cfg, m.slot)
eq(m.players[healer:getId()].team, m.players[tank:getId()].team, "the party plays together")
local tanks, heals = {0, 0}, {0, 0}
for _, cid in ipairs(m.order) do
  local e = m.players[cid]
  if e.role == "tank" then tanks[e.team] = tanks[e.team] + 1 end
  if e.role == "healer" then heals[e.team] = heals[e.team] + 1 end
  eq(K.baseOf(L, Player(cid).pos), e.team, "in the own base: " .. e.name)
end
eq(tanks[1], 1, "a tank in team 1"); eq(tanks[2], 1, "a tank in team 2")
eq(heals[1], 1, "a healer in team 1"); eq(heals[2], 1, "a healer in team 2")
check(lastSend(tank, "start") and lastSend(tank, "hud"), "start and HUD sent")
check(tank.events.ChaosBgHealth and tank.st[cfg.storage.inside] == 1, "events on, crash marker set")
local function teamOf(p) return m.players[p:getId()].team end
local mine, theirs = {}, {}
for _, cid in ipairs(m.order) do
  local p = Player(cid)
  if teamOf(p) == teamOf(tank) then mine[#mine + 1] = p else theirs[#theirs + 1] = p end
end
local enemy = theirs[1]

-- preparation: no damage, nobody leaves the base
eq(hit(enemy, tank, 300), 0, "no damage in the preparation")
eq(callbacks.onTargetCombat(tank, enemy), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "no attack in the preparation")
tank.pos = {x = L.center.x, y = L.center.y, z = L.z}
advance(1000)
eq(K.baseOf(L, tank.pos), teamOf(tank), "walked out in the preparation: back in the base")
advance(cfg.prepSeconds * 1000)
eq(m.phase, "fight", "the wells are open")
eq(callbacks.onTargetCombat(tank, enemy), RETURNVALUE_NOERROR, "attack allowed")
eq(callbacks.onTargetCombat(tank, healer), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "no team attack")

-- normalisation: the level 300 solo hits harder, a 470 softer, against the 450 reference
local s7 = solos[7]
local victim = teamOf(s7) == teamOf(tank) and enemy or tank
local before = victim.health
local dealt = hit(victim, s7, 300)
check(dealt > 300, "a level-300 hit is scaled up (" .. dealt .. ")")
victim.health = before
local strong = teamOf(healer) == teamOf(victim) and theirs[2] or healer
if strong.level > victim.level then
  check(hit(victim, strong, 300) < 300 + 1, "a higher level's hit is not scaled up")
  victim.health = victim.maxHealth
end

-- capture: the near well of team 1 (west); one player stands in it 8 s
local t1 = teamOf(tank) == 1 and tank or enemy
local w = L.braziers[1]
for _, p in ipairs({tank, enemy}) do p.pos = {x = L.spawns[teamOf(p)][1].x, y = L.spawns[teamOf(p)][1].y, z = L.z} end
t1.pos = {x = w.x + 1, y = w.y, z = w.z}
advance(8000)
eq(m.braziers[1].owner, 1, "team 1 holds the West Well")
eq(m.players[t1:getId()].captures, 1, "capture credited")
local sc = m.score[1]
advance(4000)
check(m.score[1] >= sc + 2 * cfg.perTick[1] - cfg.perTick[1], "score ticks for a held well (" .. sc .. " -> " .. m.score[1] .. ")")
check(lastSend(t1, "hud").braziers[1].owner == 1, "HUD shows the owner")
check(#lastSend(t1, "board").rows == 10, "scoreboard has every player")

-- the death catch, the graveyard, the wave
local foe = theirs[3]
foe.pos = {x = L.center.x, y = L.center.y + 3, z = L.z}
local score2 = m.score[teamOf(tank)]
local d2 = hit(foe, tank, 999999)
eq(foe.health, 1, "the lethal hit leaves 1 health")
check(m.players[foe:getId()].down, "downed")
eq(m.players[tank:getId()].kills, 1, "kill credited")
eq(m.score[teamOf(tank)], score2 + cfg.killPoints, "kill points to the team")
advance(100)
eq(K.graveOf(L, foe.pos), teamOf(foe), "in the own graveyard")
eq(hit(foe, tank, 100), 0, "the downed cannot be hit")
eq(hit(tank, foe, 100), 0, "the downed cannot hit")
eq(prepare.onPrepareDeath(theirs[4], tank), false, "the safety net cancels a death")
check(m.players[theirs[4]:getId()].down, "and downs the player")
advance(900)
check(not m.players[foe:getId()].down or lastSend(foe, "hud").respawn ~= nil, "the HUD shows the respawn wave")
advance(cfg.waveSeconds * 1000)
check(not m.players[foe:getId()].down, "back with the wave")
eq(K.baseOf(L, foe.pos), teamOf(foe), "at the base")
eq(foe.health, foe.maxHealth, "healed at the wave")

-- the enemy base wards
tank.pos = {x = L.spawns[teamOf(foe)][1].x, y = L.spawns[teamOf(foe)][1].y, z = L.z}
advance(1000)
eq(K.baseOf(L, tank.pos), teamOf(tank), "thrown back from the enemy base")

-- healing between team mates is scaled too and counted
tank.health = 1000
local healed = hit(tank, healer, 500, COMBAT_HEALING)
check(healed > 0 and m.players[healer:getId()].healing > 0, "healing counted")
eq(hit(tank, newPlayer("Outsider", 450, 5), 500, COMBAT_HEALING), 0, "no healing from outside the match")

-- AFK: one of the other team stands still: warned, then removed as a deserter
local idle = theirs[5]
idle.pos = {x = L.spawns[teamOf(idle)][2].x, y = L.spawns[teamOf(idle)][2].y, z = L.z}
for _, p in ipairs(Game.getPlayers()) do if p ~= idle and m.players[p:getId()] then p.pos.x = p.pos.x end end
local keepMoving
keepMoving = function()
  for _, cid in ipairs(m.order) do
    local p = Player(cid)
    if p ~= idle and B.matchOf[cid] == m and not m.players[cid].down then
      local sp = L.spawns[teamOf(p)][math.floor(clock / 1000) % 2 + 1]
      p.pos = {x = sp.x, y = sp.y, z = sp.z}
    end
  end
end
for i = 1, cfg.afkKickSeconds + 2 do keepMoving(); advance(1000) end
check(m.players[idle:getId()].gone, "the idle player was removed")
check(idle.msgs[#idle.msgs - 1]:find("Deserter") ~= nil or idle.msgs[#idle.msgs]:find("Deserter") ~= nil, "deserter message")
check(not B.matchOf[idle:getId()], "out of the match")
eq(idle.st[cfg.storage.inside], 0, "crash marker cleared")
check(not B.join(idle, nil), "the deserter cannot queue")
check(idle.msgs[#idle.msgs]:find("Deserter") ~= nil, "deserter refusal")
check(not m.players[tank:getId()].gone, "the active ones stay")

-- the end: team 1 at 997, still holding the West Well (4 a tick)
m.score[1], m.score[2] = 997, 400
advance(2000)
eq(m.phase, "done", "1000 reached")
eq(m.winner, 1, "team 1 wins")
local w1 = teamOf(tank) == 1 and tank or enemy
local l1 = teamOf(tank) == 1 and enemy or tank
local e1 = lastSend(w1, "end")
eq(e1.result, "win", "winner told")
check(e1.honor >= cfg.honor.win + cfg.honor.weeklyFirstWin, "win honor + the weekly first win (" .. e1.honor .. ")")
check(e1.firstWin, "first win of the week")
check(e1.season and e1.season.after > e1.season.before, "season rating up")
eq(e1.season.placementLeft, 4, "4 placement matches left")
eq(#e1.rows, 10, "the summary has every player")
eq(lastSend(l1, "end").result, "loss", "loser told")
check(lastSend(l1, "end").honor == cfg.honor.loss + math.min(cfg.honor.killCap, cfg.honor.perKill * (m.players[l1:getId()].kills + m.players[l1:getId()].assists)) + math.min(cfg.honor.captureCap, cfg.honor.perCapture * m.players[l1:getId()].captures), "loss honor")
eq(w1.items[29857], 1, "first win of the week: an Orb of Fate")
eq(B.rowOf(idle:getGuid()).losses, 1, "the deserter got a loss")
eq(B.rowOf(idle:getGuid()).honor, 0, "and no honor")
local idleRow = PS.rowOf(idle:getGuid(), "bg")
check(idleRow.matches == 1 and idleRow.rating < cfg.season.start, "the deserter's season rating went down")
local wins = 0
for _, r in ipairs(records) do if r[1] == "battleground" then wins = wins + 1 end end
eq(wins, 5, "the weekly board counts the five winners")
local savedRatings = 0
for _, q in ipairs(queries) do if q:find("chaos_pvp_ratings") and q:find("INSERT") then savedRatings = savedRatings + 1 end end
eq(savedRatings, 10, "ten season rows saved")
advance(cfg.endDelaySeconds * 1000)
eq(B.matchOf[tank:getId()], nil, "released")
eq(tank.pos.x, 100 + tank.id % 50, "back where the match started")
check(not tank.events.ChaosBgHealth, "events off")
eq(tank.st[cfg.storage.inside], 0, "crash marker cleared")
eq(B.matches[m.slot], nil, "slot free")

-- the vendor
local row = B.rowOf(w1:getGuid())
local honor = row.honor
B.buy(w1, "ghp")
eq(w1.items[7591], 50, "50 great health potions")
eq(row.honor, honor - 60, "60 honor paid")
row.honor = 5000
B.buy(w1, "c_kill")
check(cosmetics[w1:getAccountId() .. "kill_honorbrand"], "the kill effect unlocked for the account")
eq(row.honor, 2000, "3000 honor paid")
check(not B.buy(w1, "c_kill"), "not sold twice")
check(not B.buy(w1, "c_chat"), "not enough honor (2500)")
eq(row.honor, 2000, "nothing paid for a refused offer")

-- a logout in a match is a desertion; a staff stop is not rated
for _, p in ipairs(players) do end
local list2 = {}
for i = 1, 10 do list2[i] = newPlayer("Late" .. i, 450, i % 3 == 0 and 8 or 5); check(B.join(list2[i], nil), "late " .. i .. " queues") end
advance((cfg.fillSeconds + cfg.matchmakeSeconds) * 1000)
local m2 = B.matchOf[list2[1]:getId()]
check(m2 ~= nil, "second match")
advance((cfg.prepSeconds + 1) * 1000)
events.ChaosBgLogout.onLogout(list2[2])
check(list2[2].msgs[#list2[2].msgs]:find("Deserter") ~= nil, "a logout in a match: deserter")
local saved = false
for _, q in ipairs(queries) do
  if q:find("chaos_pvp_players") and q:find("%(" .. list2[2]:getGuid() .. ", ") and q:find("'%d+'") then saved = true end
end
check(saved, "the desertion is saved with its log")
check(m2.players[list2[2]:getId()].gone, "gone from the match")
eq(B.stopAll(), 1, "staff stop")
eq(lastSend(list2[1], "end").rated, false, "not rated")
eq(B.rowOf(list2[1]:getGuid()).matches, 0, "no record change")
advance(cfg.endDelaySeconds * 1000)
eq(next(B.matches), nil, "all slots free")

-- a crash during a match: the next login goes back to where it started
local c = newPlayer("Crash", 450, 5)
local home = {x = c.pos.x, y = c.pos.y, z = c.pos.z}
c.st[cfg.storage.inside], c.st[cfg.storage.retX], c.st[cfg.storage.retY], c.st[cfg.storage.retZ] = 1, home.x, home.y, home.z
c.pos = {x = L.center.x, y = L.center.y, z = L.z}
events.ChaosBgLogin.onLogin(c)
eq(c.pos.x, home.x, "crash: back to the start position")
eq(c.st[cfg.storage.inside], 0, "crash marker cleared")

-- ---------------------------------------------------------------- the season glue (arena_season.lua)
local realSelect = Chaos.select
local sid, sStart = PS.current()
-- a character with a 2v2 row of the last season (2300, idle since its middle) and a battleground row of this season
Chaos.select = function(q, cols)
  if q:find("FROM `chaos_pvp_ratings` WHERE `player_id` = 4242") then
    return {{season = sid, bracket = "bg", rating = 1620, rd = 120, matches = 7, wins = 5, losses = 2, draws = 0, peak = 1650, last_match = sStart + 10},
      {season = sid - 1, bracket = "2v2", rating = 2300, rd = 75, matches = 30, wins = 25, losses = 5, draws = 0, peak = 2300,
        last_match = sStart - 28 * 86400}}
  end
  return {}
end
local rows = PS.load(4242, true)
eq(rows.bg.rating, 1620, "this season's row is read as it is")
-- 2300 idle 28 days at the season's end: 2 weeks past the grace = 2240, soft reset: 1500 + 740 / 2 = 1870
eq(rows["2v2"].rating, 1870, "the last season's row: decayed, then softly reset")
eq(rows["2v2"].matches, 0, "placement again")
check(rows["2v2"].rd >= cfg.season.rdReset, "rd back up")
eq(rows["1v1"].rating, cfg.season.start, "a bracket never played starts fresh")
eq(PS.viewOf(4242).bg.tierName, "Kindled", "1620 is Kindled")
-- the season's end: two characters, one placed Infernal (2v2), one not placed; staff skipped
local inserted, granted, tierSet = {}, {}, {}
ChaosCosmetics.grant = function(acc, k) granted[#granted + 1] = acc .. ":" .. k; cosmetics[acc .. k] = true; return true end
ChaosAchievements = {set = function(who, k, v) tierSet[who] = v end}
Chaos.select = function(q)
  if q:find("JOIN `players`") then
    return {{player_id = 7001, bracket = "2v2", rating = 2050, rd = 80, matches = 20, last_match = sStart - 5 * 86400, account_id = 900, group_id = 1},
      {player_id = 7001, bracket = "bg", rating = 1700, rd = 80, matches = 12, last_match = sStart - 86400, account_id = 900, group_id = 1},
      {player_id = 7002, bracket = "1v1", rating = 2400, rd = 80, matches = 3, last_match = sStart - 86400, account_id = 901, group_id = 1},
      {player_id = 7003, bracket = "1v1", rating = 2400, rd = 80, matches = 30, last_match = sStart - 86400, account_id = 902, group_id = 6}}
  end
  return {}
end
local nq = #queries
eq(PS.processSeason(sid - 1), 1, "one character rewarded")
for i = nq + 1, #queries do if queries[i]:find("chaos_pvp_season_rewards") then inserted[#inserted + 1] = queries[i] end end
eq(#inserted, 1, "one reward row")
check(inserted[1]:find("'Infernal %(S" .. (sid - 1) .. "%)'") ~= nil, "the Infernal title of that season")
check(inserted[1]:find("'gold'") ~= nil, "with the gold frame")
eq(#granted, 2, "two cosmetics for Infernal")
eq(granted[1], "900:loot_blazing", "Blazing labels to the account")
eq(tierSet[7001], 5, "achievement stat pvp_season_tier 5")
eq(B.rowOf(7001).honor, cfg.season.tiers[5].honor, "season honor")
Chaos.select = realSelect
ChaosAchievements = nil

-- ---------------------------------------------------------------- instance limits (instance_limits.lua)
-- warnings before the match's end, the found teams are told once when every field is in use, the staff list and close
do
  dofile("data/scripts/chaos/instance_limits.lua")
  local function said(p, text) for _, t in ipairs(p.msgs) do if t:find(text, 1, true) then return true end end return false end
  local slots = cfg.grid.slots
  cfg.grid.slots = 1
  local g1, g2 = {}, {}
  for i = 1, 10 do g1[i] = newPlayer("First" .. i, 450, i % 3 == 0 and 8 or 5); check(B.join(g1[i], nil), "limits: first " .. i .. " queues") end
  advance((cfg.fillSeconds + cfg.matchmakeSeconds) * 1000)
  local mm = B.matchOf[g1[1]:getId()]
  check(mm ~= nil, "limits: a match")
  for i = 1, 10 do g2[i] = newPlayer("Second" .. i, 450, i % 3 == 0 and 8 or 5); check(B.join(g2[i], nil), "limits: second " .. i .. " queues") end
  advance((cfg.fillSeconds + cfg.matchmakeSeconds) * 1000)
  check(B.matchOf[g2[1]:getId()] == nil, "limits: no field for the second match")
  check(said(g2[1], "Battleground: All battlefields are busy. Try again in ~"), "limits: told the wait: " .. table.concat(g2[1].msgs, " | "))
  advance((cfg.prepSeconds + 1) * 1000)
  mm.endAt = os.time() + 61
  advance(1000)
  check(said(g1[1], "Battleground: 1 minute left"), "limits: the 1 minute warning")
  local found
  for _, r in ipairs(ChaosInstanceLimits.runs()) do if r.key == "battleground" then found = r end end
  check(found and found.id == mm.id and found.players == 10, "limits: listed")
  check(Chaos.instances.battleground.close(mm.id) and mm.phase == "done", "limits: a staff close stops the match")
  eq(lastSend(g1[1], "end").rated, false, "limits: not rated")
  advance(cfg.endDelaySeconds * 1000 + (cfg.matchmakeSeconds + 1) * 1000)
  check(B.matchOf[g2[1]:getId()] ~= nil, "limits: the waiting teams start when the field frees up")
  cfg.grid.slots = slots
  B.stopAll()
  advance(cfg.endDelaySeconds * 1000)
end

print(string.format("battleground_flow_test: %d checks, %d failed", count, fails))
if fails > 0 then os.exit(1) end
