-- Run from the server/ folder: luajit tests/buffparty_glue_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Loads the two scripts that glue the buff bar (buffbar.lua) and the party frames (partyframes.lua) to the engine against
-- a mocked engine and runs their events: login, the extended opcode (sync / off, open / close, kick / lead / invite), the
-- ticks (full list, diffs, nothing when quiet, one state per tick, heartbeat), what a viewer is and is not told, and the
-- checks of the actions (leader only, same party only).
dofile("data/scripts/chaos/chaos_constants.lua")

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- ------------------------------------------------------------------ the mocked engine
local store, nStore = {}, 0
json = {
	encode = function(t) nStore = nStore + 1 store[nStore] = t return "@@" .. nStore end,
	decode = function(s) return store[tonumber(tostring(s):match("^@@(%d+)$") or 0)] end
}
CONDITION_HASTE, CONDITION_POISON, CONDITION_INFIGHT, CONDITION_ATTRIBUTES = 1, 2, 3, 4
CONDITIONID_DEFAULT, CONDITIONID_COMBAT = -1, 0
MESSAGE_STATUS_SMALL, MESSAGE_STATUS_WARNING = 1, 2
SKULL_WHITE, SKULL_RED, SKULL_BLACK = 3, 4, 5

local events = {}
function GlobalEvent(name)
	local e = {name = name}
	function e:interval(ms) self.ms = ms end
	function e:register() events[name] = self end
	return e
end
function CreatureEvent(name)
	local e = {name = name}
	function e:type(t) self.kind = t end
	function e:register() events[name] = self end
	return e
end

local players, byName, nextId = {}, {}, 100
local parties = {}
local function newPlayer(name, x, y, z, conds)
	nextId = nextId + 1
	local p = {_id = nextId, _name = name, _x = x or 1000, _y = y or 1000, _z = z or 7, _hp = 800, _max = 1000, _mp = 300, _mpMax = 500,
		_conds = conds or {}, _sent = {}, _texts = {}, _events = {}, _store = {}}
	function p:getId() return self._id end
	function p:getName() return self._name end
	function p:getLevel() return 120 end
	function p:getVocation() return {getId = function() return 4 end} end
	function p:getHealth() return self._hp end
	function p:getMaxHealth() return self._max end
	function p:getMana() return self._mp end
	function p:getMaxMana() return self._mpMax end
	function p:getPosition() return {x = self._x, y = self._y, z = self._z} end
	function p:hasCondition(t) return self._conds[t .. ":0:0"] ~= nil end
	function p:getIp() return 1 end
	function p:getOutfit() return {lookType = 128, lookHead = 1, lookBody = 2, lookLegs = 3, lookFeet = 4, lookAddons = 0} end
	function p:getParty() return parties[self._id] end
	function p:registerEvent(n) self._events[n] = true end
	function p:sendExtendedOpcode(op, buf) self._sent[#self._sent + 1] = {op = op, msg = json.decode(buf)} end
	function p:sendTextMessage(t, text) self._texts[#self._texts + 1] = text end
	function p:getCondition(ctype, cid, sub)
		local c = self._conds[ctype .. ":" .. cid .. ":" .. (sub or 0)]
		return c and {getTicks = function() return c end} or nil
	end
	function p:getStorageValue(k) return self._store[k] or -1 end
	function p:getSkull() return 0 end
	function p:getSkullTime() return 0 end
	players[#players + 1] = p
	byName[name:lower()] = p
	return p
end
function Player(x)
	if type(x) == "number" then
		for _, p in ipairs(players) do if p._id == x then return p end end
		return nil
	end
	return byName[tostring(x):lower()]
end
Game = {getPlayers = function() return players end, getStorageValue = function() return -1 end}
function Party(leader)
	local party = {_leader = leader, _members = {}, _invitees = {}, _removed = {}}
	function party:getLeader() return self._leader end
	function party:getMembers() return self._members end
	function party:getInvitees() return self._invitees end
	function party:addInvite(p) self._invitees[#self._invitees + 1] = p return true end
	function party:removeMember(p)
		for i, m in ipairs(self._members) do
			if m == p then table.remove(self._members, i) end
		end
		parties[p._id] = nil
		self._removed[#self._removed + 1] = p
		return true
	end
	function party:setLeader(p)
		for i, m in ipairs(self._members) do
			if m == p then self._members[i] = self._leader end
		end
		self._leader = p
		return true
	end
	parties[leader._id] = party
	return party
end
local function join(party, p)
	party._members[#party._members + 1] = p
	parties[p._id] = party
end

local clock = 5000000
dofile("data/lib/chaos_buffs.lua")
ChaosBuffs.nowMs = function() return clock end
dofile("data/scripts/chaos/ratelimit.lua")
dofile("data/scripts/chaos/buffbar.lua")
dofile("data/scripts/chaos/partyframes.lua")

local function ext(player, opcode, action, data)
	events[opcode == ChaosOpcodes.buffs and "ChaosBuffBarExtended" or "ChaosPartyFramesExtended"].onExtendedOpcode(
		player, opcode, json.encode({action = action, data = data}))
end
local function take(player)
	local list = player._sent
	player._sent = {}
	return list
end

-- ------------------------------------------------------------------ registration
for _, name in ipairs({"ChaosBuffBarThink", "ChaosBuffBarLogin", "ChaosBuffBarLogout", "ChaosBuffBarExtended",
		"ChaosPartyFramesThink", "ChaosPartyFramesLogin", "ChaosPartyFramesLogout", "ChaosPartyFramesExtended"}) do
	ok(events[name] ~= nil, "registered " .. name)
end
-- the buff bar looks at a quarter of the characters per tick (by creature id): four ticks are one full pass
local function buffTick()
	for _ = 1, 4 do
		events.ChaosBuffBarThink.onThink(250)
	end
end
eq(events.ChaosBuffBarThink.ms, ChaosBuffs.cfg.tickMs / 4, "buff tick: a quarter of the players each time"); eq(events.ChaosPartyFramesThink.ms, ChaosPartyFrames.cfg.tickMs, "party tick")
eq(events.ChaosBuffBarExtended.kind, "extendedopcode", "buff opcode event type"); eq(events.ChaosPartyFramesLogin.kind, "login", "login event type")

-- ------------------------------------------------------------------ the buff bar
local A = newPlayer("Aria", 1000, 1000, 7)
events.ChaosBuffBarLogin.onLogin(A)
ok(A._events.ChaosBuffBarExtended and A._events.ChaosBuffBarLogout, "login registers the events")
buffTick()
eq(#take(A), 0, "nothing is sent to a client that did not ask")
-- haste and poison on the character
A._conds["1:0:0"] = 12000
A._conds["2:0:0"] = 8000
ext(A, ChaosOpcodes.buffs, "sync")
local sent = take(A)
eq(#sent, 1, "sync is answered once"); eq(sent[1].op, 234, "on the buffs opcode"); eq(sent[1].msg.action, "full", "with the full list")
local list = sent[1].msg.data.list
eq(#list, 2, "two entries"); eq(list[1].k, "haste", "haste first"); eq(list[1].t, 0, "buff"); eq(list[2].k, "poison", "poison next"); eq(list[2].t, 1, "debuff")
eq(list[1].l, 12000, "ms left"); eq(list[1].n, "Haste", "name"); ok(list[1].d ~= "", "description"); eq(list[1].i, "buff:haste", "icon spec")
-- a second sync straight away is refused by the rate limit
ext(A, ChaosOpcodes.buffs, "sync")
eq(#take(A), 0, "sync is rate limited")
-- quiet: nothing; time passes: still nothing
clock = clock + 1000
A._conds["1:0:0"], A._conds["2:0:0"] = 11000, 7000
buffTick()
eq(#take(A), 0, "a countdown is not sent")
-- a new debuff, a gone buff
A._conds["3:-1:0"] = 59000
A._conds["1:0:0"] = nil
clock = clock + 1000
A._conds["2:0:0"] = 6000
buffTick()
sent = take(A)
eq(#sent, 1, "one diff"); eq(sent[1].msg.action, "diff", "a diff")
local d = sent[1].msg.data
eq(#d.add, 1, "one add"); eq(d.add[1].k, "infight", "in fight added"); eq(d.del[1], "haste", "haste removed"); eq(d.upd, nil, "no update")
-- a recast of the poison moves the end
clock = clock + 1000
A._conds["2:0:0"] = 20000
buffTick()
sent = take(A)
ok(#sent == 1 and sent[1].msg.data.upd and sent[1].msg.data.upd[1].k == "poison" and sent[1].msg.data.upd[1].l == 20000, "recast = update")
-- the periodic full list
clock = clock + ChaosBuffs.cfg.resyncMs
A._conds["2:0:0"], A._conds["3:-1:0"] = 5000, 29000
buffTick()
sent = take(A)
eq(#sent, 1, "resync message"); eq(sent[1].msg.action, "full", "a full list again")
-- the cache serves the party frames without a second look
local before = ChaosBuffs.cache[A._id].at
ChaosBuffs.get(A, clock, 900)
eq(ChaosBuffs.cache[A._id].at, before, "cached list is reused")
-- off stops it, logout clears it
ext(A, ChaosOpcodes.buffs, "off")
A._conds["2:0:0"] = 99000
clock = clock + 2000
buffTick()
eq(#take(A), 0, "nothing after off")
ok(ChaosBuffBar.watch[A._id] == nil, "not watching")
ext(A, ChaosOpcodes.buffs, "bogus")
eq(#take(A), 0, "unknown action ignored")
events.ChaosBuffBarExtended.onExtendedOpcode(A, 999, json.encode({action = "sync"}))
eq(#take(A), 0, "another opcode ignored")
events.ChaosBuffBarExtended.onExtendedOpcode(A, ChaosOpcodes.buffs, "not json")
eq(#take(A), 0, "garbage ignored")
ChaosBuffBar.watch[A._id] = {sent = {}, lastFull = 0}
events.ChaosBuffBarLogout.onLogout(A)
ok(ChaosBuffBar.watch[A._id] == nil and ChaosBuffs.cache[A._id] == nil, "logout forgets the character")

-- ------------------------------------------------------------------ the party frames
local L = newPlayer("Leader", 1000, 1000, 7, {["3:0:0"] = 5000})
local M1 = newPlayer("Boran", 1010, 1000, 7)
local M2 = newPlayer("Cael", 1500, 1000, 7)
local X = newPlayer("Outsider", 1005, 1005, 7)
local party = Party(L)
join(party, M1)
join(party, M2)
for _, p in ipairs({L, M1, M2, X}) do events.ChaosPartyFramesLogin.onLogin(p) end
events.ChaosPartyFramesThink.onThink(500)
eq(#take(M1), 0, "nothing before open")
ext(M1, ChaosOpcodes.partyFrames, "open", {buffs = true})
sent = take(M1)
eq(#sent, 1, "open is answered"); eq(sent[1].op, 235, "on the party opcode"); eq(sent[1].msg.action, "state", "a state")
local st = sent[1].msg.data
eq(st.leader, L._id, "leader id"); eq(#st.members, 3, "three members"); eq(st.members[1].i, L._id, "leader first")
local byId = {}
for _, e in ipairs(st.members) do byId[e.i] = e end
eq(byId[M1._id].h, 800, "own numbers in range"); eq(byId[M1._id].f % 32 >= 16, true, "own flag")
eq(byId[L._id].h, 800, "leader in range: exact"); eq(byId[L._id].d, 10, "distance"); eq(byId[L._id].f % 2, 1, "leader flag"); ok(byId[L._id].f >= 3, "in fight flag too")
eq(byId[M2._id].far, 1, "far member"); eq(byId[M2._id].h, nil, "no exact health for the far one"); eq(byId[M2._id].m, nil, "no mana for the far one")
eq(byId[X._id], nil, "an outsider is never listed")
ok(byId[L._id].b ~= nil and #byId[L._id].b >= 1, "the leader's buffs and debuffs are listed")
eq(byId[L._id].o.t, 128, "outfit")
-- unchanged: nothing, then a change: a state
events.ChaosPartyFramesThink.onThink(500)
eq(#take(M1), 0, "an unchanged state is not repeated")
M2._hp = 790
events.ChaosPartyFramesThink.onThink(500)
eq(#take(M1), 0, "a far member's small change is below the step") -- 79% rounds to the same 80% step
M2._hp = 100
events.ChaosPartyFramesThink.onThink(500)
sent = take(M1)
eq(#sent, 1, "a big change is sent"); eq(sent[1].msg.data.members[3].p, 10, "far health in steps")
-- the outsider and a non-watching member get nothing
eq(#take(X), 0, "outsider gets nothing"); eq(#take(L), 0, "a member that did not open gets nothing")
ext(X, ChaosOpcodes.partyFrames, "open", {})
sent = take(X)
eq(#sent, 1, "an outsider that opens"); eq(#sent[1].msg.data.members, 0, "gets an empty state")
events.ChaosPartyFramesThink.onThink(500)
eq(#take(X), 0, "and only once")
-- the leader opens: sees the others
ext(L, ChaosOpcodes.partyFrames, "open", {buffs = false})
sent = take(L)
eq(#sent[1].msg.data.members, 3, "the leader sees three")
for _, e in ipairs(sent[1].msg.data.members) do eq(e.b, nil, "no buffs when the client did not ask: " .. e.n) end
-- actions: a member cannot kick or lead
clock = clock + 1
local function lastText(p) return p._texts[#p._texts] end
ChaosRateLimit.last = {}
ext(M1, ChaosOpcodes.partyFrames, "kick", {id = M2._id})
ok(lastText(M1) and lastText(M1):find("leader"), "a member cannot kick: " .. tostring(lastText(M1)))
eq(#party._removed, 0, "nobody removed")
ChaosRateLimit.last = {}
ext(M1, ChaosOpcodes.partyFrames, "lead", {id = M2._id})
eq(party:getLeader(), L, "a member cannot pass the leadership")
-- the leader may not kick an outsider or itself
ChaosRateLimit.last = {}
ext(L, ChaosOpcodes.partyFrames, "kick", {id = X._id})
ok(lastText(L):find("not in your party"), "no outsider: " .. tostring(lastText(L)))
ChaosRateLimit.last = {}
ext(L, ChaosOpcodes.partyFrames, "kick", {id = L._id})
eq(#party._removed, 0, "not itself")
-- rate limit of actions
ext(L, ChaosOpcodes.partyFrames, "kick", {id = M2._id})
eq(#party._removed, 0, "an action right after another is dropped")
ChaosRateLimit.last = {}
ext(L, ChaosOpcodes.partyFrames, "kick", {id = M2._id})
eq(#party._removed, 1, "the leader removes a member"); eq(party._removed[1], M2, "the right one")
ok(M2._texts[#M2._texts]:find("removed"), "the member is told")
ChaosRateLimit.last = {}
ext(L, ChaosOpcodes.partyFrames, "lead", {id = M1._id})
eq(party:getLeader(), M1, "the leader passes the leadership")
-- garbage ids
ChaosRateLimit.last = {}
ext(M1, ChaosOpcodes.partyFrames, "kick", {id = "x"}); ext(M1, ChaosOpcodes.partyFrames, "kick", {id = -5}); ext(M1, ChaosOpcodes.partyFrames, "kick", {})
-- invitations: M1 is the leader now
ChaosRateLimit.last = {}
ext(M1, ChaosOpcodes.partyFrames, "invite", {name = "nobody here"})
ok(lastText(M1):find("online"), "unknown name: " .. tostring(lastText(M1)))
ChaosRateLimit.last = {}
ext(M1, ChaosOpcodes.partyFrames, "invite", {name = "Outsider"})
eq(#party._invitees, 1, "the outsider is invited"); eq(party._invitees[1], X, "the right one")
ChaosRateLimit.last = {}
ext(M1, ChaosOpcodes.partyFrames, "invite", {name = "Boran"})
ok(lastText(M1):find("yourself"), "not yourself: " .. tostring(lastText(M1)))
-- someone without a party invites: a party is made
local Y = newPlayer("Yara")
ChaosRateLimit.last = {}
ext(Y, ChaosOpcodes.partyFrames, "invite", {name = "Cael"})
ok(parties[Y._id] ~= nil, "a party is made for the inviter"); eq(parties[Y._id]._invitees[1], M2, "and the player invited")
-- leaving the party: a state with no members, once
join(party, M2)
ext(M2, ChaosOpcodes.partyFrames, "open", {})
eq(#take(M2)[1].msg.data.members, 3, "back in the party: three members")
parties[M2._id] = nil
events.ChaosPartyFramesThink.onThink(500)
sent = take(M2)
eq(#sent, 1, "leaving sends an empty state"); eq(#sent[1].msg.data.members, 0, "empty")
events.ChaosPartyFramesThink.onThink(500)
eq(#take(M2), 0, "and no more")
-- close and logout
ext(M1, ChaosOpcodes.partyFrames, "close")
ok(ChaosPartyFrames.watch[M1._id] == nil, "close stops watching")
ext(L, ChaosOpcodes.partyFrames, "open", {})
events.ChaosPartyFramesLogout.onLogout(L)
ok(ChaosPartyFrames.watch[L._id] == nil, "logout stops watching")

if fails > 0 then
	print(fails .. " of " .. checks .. " checks FAILED")
	os.exit(1)
end
print("buff bar and party frames glue tests OK (" .. checks .. " checks)")
