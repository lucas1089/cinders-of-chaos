-- Run from the server/ folder: luajit tests/groupqueue_test.lua (CI runs it with luajit and lua5.3)
-- The Group Queue (O407; groupqueue_core.lua, groupqueue_config.lua, groupqueue.lua; server/README.md "Group Queue
-- (O407)"). Part 1: the pure core (the choice from the client, groups, the gate's free / wait / go, ready check answers,
-- time-outs, members leaving, the sync with the modes, the client view). Part 2: groupqueue.lua with the real arena.lua
-- on a mocked engine (a battleground and a dungeon stand-in, a raid stand-in): solo pops leave the other queues, a party
-- is held for its ready check and starts after it, a decline drops only the decliner's party, a time-out, a raid ready
-- check, a queue left in a mode's own window, a logout during a check, and the hooks of the three mode files.

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

dofile("data/scripts/chaos/groupqueue_core.lua")
local K = ChaosGroupQueueCore
local cfg = dofile("data/scripts/chaos/groupqueue_config.lua")

-- ================================================================ part 1: the core
eq(cfg.readyCheckSeconds, 20, "a ready check lasts 20 seconds")

-- the choice
do
	local picks, why = K.parseSelection(cfg, {arena = "1v1", bg = true, dungeon = {id = 3, difficulty = 2}}, 1)
	eq(#picks, 3, "three picks")
	eq(picks[1].key .. picks[2].key .. picks[3].key, "arenabgdungeon", "in queue order")
	eq(picks[1].mode, "1v1", "arena mode")
	eq(picks[3].id * 10 + picks[3].difficulty, 32, "dungeon id and difficulty")
	picks, why = K.parseSelection(cfg, {}, 1)
	eq(picks, nil, "nothing picked")
	eq(why, "Pick at least one queue.", "nothing picked: reason")
	picks, why = K.parseSelection(cfg, {arena = "2v2"}, 1)
	check(picks == nil and why:find("2v2"), "2v2 alone refused")
	check(K.parseSelection(cfg, {arena = "2v2"}, 2) ~= nil, "2v2 as a party of two")
	check(K.parseSelection(cfg, {arena = "3v3"}, 3) ~= nil, "3v3 as a party of three")
	eq((K.parseSelection(cfg, {arena = "5v5"}, 1)), nil, "unknown arena mode")
	eq((K.parseSelection(cfg, {bg = true}, 6)), nil, "a party of six is too large for the battleground")
	eq(K.parseSelection(cfg, {bg = true, role = "healer"}, 5)[1].role, "healer", "a battleground role")
	eq(K.parseSelection(cfg, {bg = true, role = "king"}, 1)[1].role, nil, "an unknown role is dropped")
	eq((K.parseSelection(cfg, {dungeon = {id = 1, difficulty = 7}}, 1)), nil, "difficulty above the maximum")
	eq((K.parseSelection(cfg, {dungeon = {id = "x"}}, 1)), nil, "dungeon id not a number")
	eq((K.parseSelection(cfg, {dungeon = {id = 0 / 0}}, 1)), nil, "dungeon id NaN")
	eq((K.parseSelection(cfg, "arena", 1)), nil, "not a table")
	eq(K.parseSelection(cfg, {bg = "yes"}, 1), nil, "bg must be true")
end

-- groups
local st = K.newState()
local solo = K.add(st, 1, {1}, {{key = "arena", mode = "1v1"}, {key = "bg"}}, 100)
check(solo ~= nil, "solo group")
eq(K.groupOf(st, 1), solo, "group of the player")
eq((K.add(st, 1, {1}, {{key = "bg"}}, 100)), nil, "a player is in one group at a time")
check(K.shares(st, 1, "arena", "bg"), "solo holds arena and bg")
check(not K.shares(st, 1, "arena", "dungeon"), "but no dungeon")
check(not K.shares(st, 2, "arena", "bg"), "someone else holds nothing")
local party = K.add(st, 10, {10, 11}, {{key = "arena", mode = "2v2"}, {key = "dungeon", id = 1, difficulty = 1}}, 100)
eq((K.add(st, 12, {12, 11}, {{key = "bg"}}, 100)), nil, "a member of another group refuses the whole party")
eq(K.groupOf(st, 12), nil, "nothing half added")

-- the gate
eq((K.gate(st, cfg, "arena", {50, 51}, 101)), "free", "no group in the match: free")
local v, list = K.gate(st, cfg, "arena", {1, 50}, 101)
eq(v, "go", "a solo group goes at once")
eq(list[1], solo, "the solo group is named")
local ss = K.newState()
local s1 = K.add(ss, 1, {1}, {{key = "bg"}}, 0)
eq((K.gate(ss, {readyCheckSeconds = 20, confirmSeconds = 60, soloReadyCheck = true}, "bg", {1}, 0)), "wait",
	"soloReadyCheck asks a lone player too")
check(s1.check ~= nil, "check started")

v, list = K.gate(st, cfg, "arena", {10, 11, 60, 61}, 102)
eq(v, "wait", "a party waits for its ready check")
eq(list[1], party, "its check started")
eq(party.check.key, "arena", "check for the arena")
eq(party.check.deadline, 122, "deadline")
v, list = K.gate(st, cfg, "arena", {10, 11, 60, 61}, 104)
eq(v, "wait", "still waiting")
eq(#list, 0, "no second check")
eq((K.gate(st, cfg, "dungeon", {10}, 104)), "wait", "another mode waits for the open check")
eq(K.view(party, 11, 104).check.left, 18, "view: seconds left")

-- answers
eq((K.answer(st, cfg, 99, true, 105)), nil, "not in a group")
eq((K.answer(st, cfg, 1, true, 105)), nil, "no check open")
eq((K.answer(st, cfg, 10, true, 105)), "accepted", "first accept")
eq((K.answer(st, cfg, 10, true, 105)), nil, "answered already")
local vw = K.view(party, 10, 105)
eq(vw.check.accepted .. "/" .. vw.check.total, "1/2", "view: one of two")
check(vw.check.mine, "view: mine")
check(not K.view(party, 11, 105).check.mine, "view: the other has not answered")
local res, g, key = K.answer(st, cfg, 11, true, 106)
eq(res, "ready", "everyone accepted")
eq(key, "arena", "for the arena")
eq(party.check, nil, "check closed")
eq(K.view(party, 10, 106).ready, "arena", "view: ready for the arena")
eq((K.gate(st, cfg, "dungeon", {10, 99}, 107)), "wait", "accepted for the arena: the dungeon waits")
v, list = K.gate(st, cfg, "arena", {10, 11, 70}, 107)
eq(v, "go", "the arena goes")
check(list[1] == party, "the party goes")
-- the confirmation lapses
local p2 = K.add(K.newState(), 1, {1, 2}, {{key = "bg"}}, 0)
p2.confirmed = {key = "bg", untilAt = 60}
local st2 = {groups = {[p2.id] = p2}, of = {[1] = p2.id, [2] = p2.id}, seq = 1}
eq((K.gate(st2, cfg, "bg", {1, 2}, 60)), "go", "within confirmSeconds: no second check")
eq((K.gate(st2, cfg, "bg", {1, 2}, 61)), "wait", "after it: a new check")

-- a decline
local sd = K.newState()
local ga = K.add(sd, 1, {1, 2, 3}, {{key = "bg"}, {key = "arena", mode = "3v3"}}, 0)
local gb = K.add(sd, 4, {4, 5}, {{key = "bg"}}, 0)
eq((K.gate(sd, cfg, "bg", {1, 2, 3, 4, 5, 6}, 0)), "wait", "two parties wait")
check(ga.check and gb.check, "both checks started")
K.answer(sd, cfg, 1, true, 1)
res, g, key = K.answer(sd, cfg, 2, false, 2)
eq(res, "declined", "a decline")
eq(g, ga, "the decliner's group")
eq(key, "bg", "the key of the check")
eq(K.groupOf(sd, 1), nil, "the decliner's group is removed (its members too)")
eq(K.groupOf(sd, 4), gb, "the other party stays")
eq((K.answer(sd, cfg, 3, true, 3)), nil, "no check left for the removed group")
K.answer(sd, cfg, 4, true, 3)
eq((K.answer(sd, cfg, 5, true, 4)), "ready", "the other party is ready")
eq((K.gate(sd, cfg, "bg", {4, 5, 7}, 5)), "go", "it goes with the next match")

-- a time-out
local se = K.newState()
local gt = K.add(se, 1, {1, 2}, {{key = "dungeon", id = 1, difficulty = 1}}, 0)
K.gate(se, cfg, "dungeon", {1, 2}, 0)
K.answer(se, cfg, 1, true, 5)
eq(#K.expire(se, 20), 0, "not yet at the deadline")
eq((K.answer(se, cfg, 2, true, 21)), nil, "too late to answer")
local ex = K.expire(se, 21)
eq(#ex, 1, "expired")
eq(ex[1].group, gt, "that group")
eq(#ex[1].missing, 1, "one missing")
eq(ex[1].missing[1], 2, "the one who did not answer")
eq(K.groupOf(se, 1), nil, "removed")

-- a member leaves
local sm = K.newState()
local gm = K.add(sm, 1, {1, 2, 3}, {{key = "bg"}}, 0)
eq((K.dropMember(sm, cfg, 3, 1)), "left", "a member leaves outside a check")
eq(#gm.members, 2, "two left")
eq(K.groupOf(sm, 3), nil, "the member is free")
K.gate(sm, cfg, "bg", {1, 2}, 2)
eq((K.dropMember(sm, cfg, 2, 3)), "declined", "a member leaving during the check is a decline")
eq(K.groupOf(sm, 1), nil, "the group is gone")
local s1m = K.newState()
K.add(s1m, 1, {1}, {{key = "bg"}}, 0)
K.dropMember(s1m, cfg, 1, 1)
eq(next(s1m.groups), nil, "the last member gone: no group")

-- the sync with the modes
local sy = K.newState()
local gy = K.add(sy, 1, {1}, {{key = "arena", mode = "1v1"}, {key = "bg"}}, 0)
local gz = K.add(sy, 2, {2, 3}, {{key = "raid"}}, 0)
local inQueue = {arena = true, bg = true}
eq(#K.sync(sy, function(_, p) return inQueue[p.key] end), 0, "nothing changed")
inQueue.arena = false
local ch = K.sync(sy, function(_, p) return inQueue[p.key] end)
eq(#ch, 1, "one group changed")
eq(ch[1].dropped[1], "arena", "the arena pick dropped")
check(not ch[1].empty, "the bg pick is left")
eq(#gy.picks, 1, "one pick left")
inQueue.bg = false
ch = K.sync(sy, function(_, p) return inQueue[p.key] end)
check(ch[1].empty, "no pick left")
eq(K.groupOf(sy, 1), nil, "the group is removed")
eq(K.groupOf(sy, 2), gz, "a raid group is never synced away")
-- a check for a dropped pick closes
local sc = K.newState()
local gc = K.add(sc, 1, {1, 2}, {{key = "arena", mode = "2v2"}, {key = "bg"}}, 0)
K.gate(sc, cfg, "arena", {1, 2}, 0)
K.sync(sc, function(_, p) return p.key == "bg" end)
eq(gc.check, nil, "the arena check closed with the arena pick")

-- the view
local vv = K.view(gy, 1, 0)
eq(K.view(nil, 1, 0), nil, "no group: no view")
local vg = K.view(gz, 2, 5)
check(vg.leader, "leader")
check(not K.view(gz, 3, 5).leader, "not leader")
eq(vg.size, 2, "size")
eq(vg.picks[1].key, "raid", "picks")
eq(vg.waited, 5, "waited")
check(vv ~= nil, "a view of a removed group still reads")

-- ================================================================ part 2: the engine with the real arena
local events, globals, talks = {}, {}, {}
function CreatureEvent(name) local o = {name = name}; function o:type() end; function o:register() events[name] = o end; return o end
function GlobalEvent(name) local o = {}; function o:interval() end; function o:register() globals[name] = o end; return o end
function TalkAction(w) local o = {}; function o:separator() end; function o:register() talks[w] = o end; return o end
EventCallback = setmetatable({register = function() end}, {__newindex = function() end})

local queue, clock = {}, 0
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, args = {...}, due = clock + delay}; return #queue end
local realTime = os.time
local base = realTime({year = 2026, month = 11, day = 5, hour = 10, min = 0, sec = 0})
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
			globals.ChaosArenaTick.onThink(1000)
			globals.ChaosGroupQueueThink.onThink(1000)
		elseif best then
			local e = table.remove(queue, best); clock = e.due; e.fn(unpack(e.args))
		else
			break
		end
	end
	clock = limit
end

local inbox = {}
json = {encode = function(t) return t end, decode = function(s) return inbox[s] end}
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
db = {query = function() return true end, escapeString = function(s) return "'" .. s .. "'" end,
	lastInsertId = function() return 77 end, storeQuery = function() return nil end}
result = {}

local players, byName = {}, {}
local nextId = 1000
local function newPlayer(name, level, ip)
	nextId = nextId + 1
	local p = {id = nextId, guid = nextId - 1000, name = name, level = level, ip = ip, pos = {x = 100 + nextId % 20, y = 100, z = 7},
		health = 1000, maxHealth = 1000, mana = 100, maxMana = 100, events = {}, st = {}, msgs = {}, sends = {}, skull = 0,
		infight = false, items = {}}
	newTile(p.pos).pz = true
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return self.name end
	function p:getLevel() return self.level end
	function p:getIp() return self.ip end
	function p:getGroup() return {getId = function() return 1 end, getAccess = function() return false end} end
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
	function p:hasSecureMode() return false end
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:setStorageValue(k, v) self.st[k] = v end
	function p:getTown() return {getTemplePosition = function() return Position(1, 1, 7) end} end
	function p:isPlayer() return true end
	function p:getPlayer() return self end
	function p:getMaster() return nil end
	function p:getInbox() return nil end
	function p:getItemCount(id) return self.items[id] or 0 end
	function p:addItem(id, c) self.items[id] = (self.items[id] or 0) + c end
	function p:sendExtendedOpcode(op, payload) self.sends[#self.sends + 1] = {op = op, msg = payload} end
	players[p.id] = p
	byName[name] = p
	return p
end
function Player(x) if type(x) == "string" then return byName[x] end return players[x] end
function Game.getPlayers() local l = {}; for _, p in pairs(players) do l[#l + 1] = p end; return l end
local function makeParty(leader, ...)
	local rest = {...}
	local pt = {getLeader = function() return leader end, getMembers = function() return rest end}
	leader.party = pt
	for _, m in ipairs(rest) do m.party = pt end
end
local function gqSent(p, action)
	for i = #p.sends, 1, -1 do
		local s = p.sends[i]
		if s.op == 160 and s.msg.action == action then return s.msg.data, i end
	end
end
local function said(p, needle)
	for _, m in ipairs(p.msgs) do if m:find(needle, 1, true) then return true end end
	return false
end

dofile("data/scripts/chaos/chaos_constants.lua")
eq(ChaosOpcodes.groupQueue, 160, "opcode 160")
do -- no other Chaos opcode is 160
	local same = 0
	for _, v in pairs(ChaosOpcodes) do if v == 160 then same = same + 1 end end
	eq(same, 1, "160 is the Group Queue's only")
end
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/arena_core.lua")
dofile("data/scripts/chaos/arena.lua")
local S, acfg = ChaosArena, Chaos.arenaConfig
ChaosLeaderboard = {record = function() end}

-- the battleground and dungeon stand-ins: the same exported calls the Group Queue and arena.lua use
local bgQueued, bgJoins, bgLeaves = {}, 0, 0
ChaosBattleground = {
	isQueued = function(p) return bgQueued[p:getId()] ~= nil end,
	isInside = function() return false end,
	isBusy = function(p) return bgQueued[p:getId()] ~= nil end,
	join = function(p, role)
		local list = {p}
		for _, m in ipairs(p.party and p.party.getMembers() or {}) do list[#list + 1] = m end
		for _, m in ipairs(list) do bgQueued[m:getId()] = role or "dps" end
		bgJoins = bgJoins + 1
		return true
	end,
	leaveQueue = function(p)
		local list = {p}
		for _, m in ipairs(p.party and (p.party.getLeader() ~= p and {p.party.getLeader()} or p.party.getMembers()) or {}) do
			list[#list + 1] = m
		end
		for _, m in ipairs(list) do bgQueued[m:getId()] = nil end
		bgLeaves = bgLeaves + 1
		return true
	end,
}
local dqueued, dfail = {}, {}
ChaosDungeons = {
	queueJoin = function(p, id, diff)
		if dfail[p:getId()] then return false, "You are in cooldown for dungeons." end
		dqueued[p:getId()] = id
		return true
	end,
	queueLeave = function(p) dqueued[p:getId()] = nil; return true end,
	queuedFor = function(p) return dqueued[p:getId()] end,
	titleFor = function(id) return "Crypt " .. id end,
	groupQueueList = function() return {{id = 1, title = "Crypt 1", level = 10, max = 3}} end,
}
local raidOpened = {}
ChaosRaid = {open = function(p) raidOpened[#raidOpened + 1] = p:getName(); return true end}

dofile("data/scripts/chaos/groupqueue.lua")
local G = ChaosGroupQueue
local ext = events.ChaosGroupQueueExtended
local function act(p, action, data)
	inbox.req = {action = action, data = data}
	ext.onExtendedOpcode(p, 160, "req")
end
ChaosRateLimit = nil

-- the hooks are in the three mode files
do
	for _, f in ipairs({"arena.lua", "battleground.lua", "dungeons.lua"}) do
		local fh = io.open("data/scripts/chaos/" .. f, "r")
		local src = fh:read("*a")
		fh:close()
		check(src:find("ChaosGroupQueue.gate(", 1, true) ~= nil, f .. " asks the gate")
	end
	local fh = io.open("data/scripts/chaos/battleground.lua", "r")
	local src = fh:read("*a")
	fh:close()
	check(src:find('GQ.shares(player, "arena", "bg")', 1, true) ~= nil, "battleground.lua lets a shared arena queue through")
end

-- 1) a lone player: arena 1v1 and the battleground side by side; the arena pops, the battleground queue is left
local a = newPlayer("Ash", 300, 11)
local b = newPlayer("Bram", 300, 12)
bgQueued[a:getId()] = "dps"
check(not S.join(a, "1v1"), "without the Group Queue the arena refuses a battleground-queued player")
bgQueued[a:getId()] = nil
act(a, "open")
local stt = gqSent(a, "state")
check(stt and stt.open, "open: the window state")
eq(stt.size, 1, "alone")
eq(#stt.dungeons, 1, "the dungeon list")
act(a, "join", {arena = "1v1", bg = true})
check(S.isQueued(a), "a in the arena queue")
check(bgQueued[a:getId()] ~= nil, "a in the battleground queue")
check(said(a, "Group Queue: you joined Arena 1v1, Battleground."), "joined text")
stt = gqSent(a, "state")
eq(#stt.group.picks, 2, "state: two picks")
eq(stt.group.picks[1].label, "Arena 1v1", "state: labels")
act(b, "join", {arena = "1v1"})
check(S.isQueued(b), "b in the arena queue")
advance(2000)
local m = S.matchOf[a:getId()]
check(m ~= nil and S.matchOf[b:getId()] == m, "the 1v1 started without a ready check")
eq(bgQueued[a:getId()], nil, "a left the battleground queue")
eq(G.state.of[a:getId()], nil, "a is out of the Group Queue")
eq(G.state.of[b:getId()], nil, "b is out of the Group Queue")
check(said(a, "Group Queue: Arena 1v1 found. You left your other queues."), "pop text")
S.stopAll()
advance((acfg.endDelaySeconds + 1) * 1000)

-- 2) a party of two through the Group Queue against a party of two from the Arena window: held for the ready check
local c1, c2 = newPlayer("Cyra", 300, 13), newPlayer("Dorn", 300, 14)
local e1, e2 = newPlayer("Eld", 300, 15), newPlayer("Fen", 300, 16)
makeParty(c1, c2)
makeParty(e1, e2)
act(c2, "join", {arena = "2v2"})
check(not S.isQueued(c2), "a party member cannot queue the party")
act(c1, "join", {arena = "2v2", bg = true, dungeon = {id = 1, difficulty = 2}})
check(S.isQueued(c1) and S.isQueued(c2), "party in the arena queue")
check(bgQueued[c2:getId()] ~= nil, "party in the battleground queue")
eq(dqueued[c1:getId()], 1, "c1 in the dungeon queue")
eq(dqueued[c2:getId()], 1, "c2 in the dungeon queue")
check(S.join(e1, "2v2"), "the other party from the Arena window")
advance(2000)
eq(S.matchOf[c1:getId()], nil, "no match before the ready check")
check(S.isQueued(c1) and S.isQueued(e1), "both parties still queued")
local ck = gqSent(c2, "check")
check(ck ~= nil, "the ready check pops on every member")
eq(ck.key, "arena", "for the arena")
eq(ck.total, 2, "two members")
eq(gqSent(e1, "check"), nil, "no check for the party from the Arena window")
act(c1, "accept")
eq(gqSent(c2, "check").accepted, 1, "one accepted, told to the others")
advance(2000)
eq(S.matchOf[c1:getId()], nil, "still waiting for the second answer")
act(c2, "accept")
eq(G.state.groups[G.state.of[c1:getId()]].confirmed.key, "arena", "ready for the arena")
advance(1000)
m = S.matchOf[c1:getId()]
check(m ~= nil and S.matchOf[e2:getId()] == m, "the 2v2 started after the ready check")
eq(bgQueued[c1:getId()], nil, "the battleground queue left")
eq(dqueued[c1:getId()], nil, "the dungeon queue left (c1)")
eq(dqueued[c2:getId()], nil, "the dungeon queue left (c2)")
check(gqSent(c1, "checkEnd") ~= nil, "the client closes the check")
S.stopAll()
advance((acfg.endDelaySeconds + 1) * 1000)

-- 3) a decline: the decliner's party leaves every queue, the other side stays queued
act(c1, "join", {arena = "2v2", bg = true})
check(S.join(e1, "2v2"), "the other party again")
advance(2000)
check(gqSent(c1, "check") ~= nil, "check")
act(c1, "accept")
act(c2, "decline")
check(not S.isQueued(c1) and not S.isQueued(c2), "the declining party left the arena queue")
eq(bgQueued[c1:getId()], nil, "and the battleground queue")
eq(G.state.of[c1:getId()], nil, "and the Group Queue")
check(said(c1, "Group Queue: Dorn declined the ready check. Your group left every queue."), "decline text")
check(S.isQueued(e1) and S.isQueued(e2), "the other party is still queued")
S.leaveQueue(e1, true)

-- 4) a time-out: nobody answers in 20 seconds
act(c1, "join", {arena = "2v2"})
check(S.join(e1, "2v2"), "the other party once more")
advance(2000)
act(c1, "accept")
advance(21000)
check(not S.isQueued(c1), "no answer: the party left the queue")
eq(G.state.of[c1:getId()], nil, "and the Group Queue")
check(said(c1, "Group Queue: no answer from Dorn. Your group left every queue."), "time-out text")
check(S.isQueued(e1), "the other side stays queued")
S.leaveQueue(e1, true)

-- 5) a queue left in the mode's own window: the Group Queue drops it on its next tick
act(a, "join", {arena = "1v1", bg = true})
S.leaveQueue(a)
advance(1000)
local ga2 = G.state.groups[G.state.of[a:getId()]]
eq(#ga2.picks, 1, "the arena pick dropped")
eq(ga2.picks[1].key, "bg", "the battleground pick stays")
bgQueued[a:getId()] = nil
advance(1000)
eq(G.state.of[a:getId()], nil, "no queue left: out of the Group Queue")
check(said(a, "Group Queue: you are in no queue any more."), "told")

-- 6) a join a mode refuses: the others still join; all refused: nothing
dfail[a:getId()] = true
act(a, "join", {arena = "1v1", dungeon = {id = 1, difficulty = 1}})
check(S.isQueued(a), "the arena took a")
check(said(a, "Group Queue: not joined: Dungeon Crypt 1 (difficulty 1)."), "not joined text")
act(a, "leave")
check(not S.isQueued(a), "leave: out of the arena queue")
eq(G.state.of[a:getId()], nil, "leave: out of the Group Queue")
act(a, "join", {dungeon = {id = 1, difficulty = 1}})
eq(G.state.of[a:getId()], nil, "every queue refused: no group")
dfail[a:getId()] = nil
-- a party dungeon join is all or none
dfail[c2:getId()] = true
act(c1, "join", {dungeon = {id = 1, difficulty = 1}})
eq(dqueued[c1:getId()], nil, "a member refused: the others are taken out again")
dfail[c2:getId()] = nil

-- 7) a logout during the ready check is a decline
act(c1, "join", {arena = "2v2"})
check(S.join(e1, "2v2"), "the other party")
advance(2000)
check(gqSent(c2, "check") ~= nil, "check")
events.ChaosGroupQueueLogout.onLogout(c2)
eq(G.state.of[c1:getId()], nil, "the party is out")
check(not S.isQueued(c1), "and out of the arena queue")
check(said(c1, "Group Queue: Dorn logged out during the ready check. Your group left every queue."), "logout text")
S.leaveQueue(e1, true)

-- 8) the raid ready check: the leader asks, the rest accepts, the raid opens for the leader
act(c1, "raid")
check(gqSent(c2, "check") and gqSent(c2, "check").key == "raid", "the raid check pops")
eq(gqSent(c2, "check").accepted, 1, "the leader counts as ready")
eq(#raidOpened, 0, "not open yet")
act(c2, "accept")
eq(raidOpened[1], "Cyra", "the raid opened for the leader")
eq(G.state.of[c1:getId()], nil, "the raid group is done")
act(a, "raid")
check(said(a, "A ready check needs a party. Alone, open the raid from the Raid window."), "alone: no raid check")
-- a raid decline keeps it closed
act(c1, "raid")
act(c2, "decline")
eq(#raidOpened, 1, "declined: the raid stays closed")

-- 9) disabled: the gate never holds a match
ChaosGroupQueueConfig.enabled = false
check(G.gate("arena", {c1:getId()}), "disabled: free")
act(a, "join", {arena = "1v1"})
check(not S.isQueued(a), "disabled: no join")
ChaosGroupQueueConfig.enabled = true

print(string.format("groupqueue_test: %d checks, %d failed", count, fails))
if fails > 0 then os.exit(1) end
