-- Run from the server/ folder: luajit tests/templar_aura_sync_test.lua (mock engine API; CI runs it with luajit and lua5.3)
-- Covers what the clients are told about the Templar line's aura (O315): the opcode (118: free, one of a kind), the pure rules in
-- templar_aura_core.lua (lineOf, syncEntries: who sees which Templar, radius with the passive tree's bonus, the party flag;
-- syncKey / syncDecide: send only on change, tell a viewer that the last Templar is gone; syncPrune; syncDue: at most one
-- check per second) and the glue in templar_combat.lua against a mocked engine: the 4 s holy_spiral effect is gone, a message
-- goes out on login / entering view / a party change / a Templar leaving, never twice for the same state.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})

local fails, checks = 0, 0
local function ok(cond, what) checks = checks + 1; if not cond then fails = fails + 1; print("FAIL " .. what) end end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

-- ------------------------------------------------------------------ the opcode
dofile("data/scripts/chaos/chaos_constants.lua")
eq(ChaosOpcodes.templarAura, 118, "opcode 118")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	ok(seen[v] == nil, "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, -- the reference server
		126, 127, -- its NPC scripts' currency opcodes
		140, 144, 145, 146, 210, 212, 213, 230, 246}) do -- the reference client's own ExtendedIds
	ok(ChaosOpcodes.templarAura ~= v, "not an opcode of the reference server or client: " .. v)
end
local function readFile(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end
-- no other server script and no other client module names 118 as an opcode
local others = 0
for _, cmd in ipairs({"ls data/scripts/chaos/*.lua", "ls ../client/overlay/modules/*/*.lua"}) do
	local ph = io.popen(cmd .. " 2>/dev/null")
	for file in ph:lines() do
		local s = readFile(file)
		local own = file:find("templar_", 1, true) or file:find("game_chestaura", 1, true) or file:find("chaos_constants", 1, true)
		if s and not own and not file:find("_test.lua", 1, true)
				and (s:find("[Oo]pcode[%w_]*%s*=%s*118%f[%D]") or s:find("xtended[%w]*Opcode%(%s*118%f[%D]")) then
			others = others + 1
			print("opcode 118 in " .. file)
		end
	end
	ph:close()
end
eq(others, 0, "no other script or module on 118")

-- ------------------------------------------------------------------ the pure rules
dofile("data/scripts/chaos/templar_aura_core.lua")
local T = ChaosTemplar
local TEMPLAR, INQ, SENT = 23, 24, 25
local function pos(x, y, z) return {x = x, y = y, z = z or 7} end

eq(T.lineOf(TEMPLAR), 1, "line Templar"); eq(T.lineOf(INQ), 2, "line Inquisitor"); eq(T.lineOf(SENT), 3, "line Sentinel")
eq(T.lineOf(4), nil, "no line for other vocations")
eq(T.cfg.aura.fxMs, nil, "the periodic effect (fxMs) is gone")
eq(T.cfg.aura.sync.viewRange, 16, "view range"); ok(T.cfg.aura.sync.minGapMs <= T.cfg.aura.thinkMs, "the gap is not longer than a think")

local templars = {
	{id = 1, voc = TEMPLAR, pos = pos(100, 100), party = "A"},
	{id = 2, voc = INQ, pos = pos(110, 100), party = "A"},
	{id = 3, voc = SENT, pos = pos(100, 110), party = nil},
	{id = 4, voc = SENT, pos = pos(100, 100), party = "B", dead = true},
	{id = 5, voc = 4, pos = pos(100, 100), party = "A"}, -- not a Templar-line vocation: no entry
}
local viewers = {
	{id = 1, pos = pos(100, 100), party = "A"}, {id = 2, pos = pos(110, 100), party = "A"}, {id = 3, pos = pos(100, 110)},
	{id = 6, pos = pos(116, 100), party = "A"}, -- 16 east of 1: in view
	{id = 7, pos = pos(117, 100), party = "A"}, -- 17 east of 1, 7 east of 2: sees only the Inquisitor
	{id = 8, pos = pos(100, 100, 6), party = "A"}, -- another floor
	{id = 9, pos = pos(103, 103), party = "B"}, -- another party, near
	{id = 10, pos = pos(300, 300), party = "A"}, -- far away
}
local out = T.syncEntries(templars, viewers)
local function find(list, id) for _, e in ipairs(list or {}) do if e.i == id then return e end end end
eq(#out[1], 3, "viewer 1 sees itself, the Inquisitor 10 east and the Sentinel 10 south"); eq(out[1][1].i, 1, "sorted by id"); eq(out[1][2].i, 2, "sorted by id")
eq(find(out[1], 1).p, 1, "a Templar in a party sees its frame"); eq(find(out[1], 1).l, 1, "line 1")
eq(find(out[1], 1).r, 4, "Templar radius 4"); eq(find(out[1], 2).r, 3, "Inquisitor radius 3"); eq(find(out[1], 2).l, 2, "line 2")
eq(find(out[1], 2).p, 1, "a party member of the Inquisitor sees its frame")
eq(#out[3], 3, "viewer 3 (no party) sees itself and both others, 10 away")
eq(find(out[3], 3).p, 0, "a Templar without a party: no frame, not even for itself"); eq(find(out[3], 3).l, 3, "line 3")
eq(find(out[3], 3).r, 5, "Sentinel radius 5")
eq(find(out[3], 1).p, 0, "not in the Templar's party: no frame")
ok(find(out[6], 1) ~= nil and find(out[6], 1).p == 1, "16 sqm is in view")
ok(find(out[7], 1) == nil and find(out[7], 2) ~= nil, "17 sqm is out of view; the Inquisitor 7 away is in")
eq(find(out[8], 1), nil, "another floor: not seen")
eq(find(out[9], 1).p, 0, "another party near the Templar: the sigil, no frame")
eq(out[10], nil, "a viewer far from every Templar has no entry")
eq(find(out[1], 4), nil, "a dead Templar has no aura"); eq(find(out[1], 5), nil, "another vocation has none")

-- the passive tree's radius bonus (Bastion) and the Sentinel
local big = T.syncEntries({{id = 1, voc = SENT, pos = pos(0, 0), party = "A", bonus = {radius = 2, reduction = 0.01, bastion = true}}},
	{{id = 1, pos = pos(0, 0), party = "A"}})
eq(big[1][1].r, 7, "5 + 2 from Bastion")
eq(T.syncEntries({}, viewers)[1], nil, "no Templar: nobody has an entry")

-- keys and the send-on-change rule
eq(T.syncKey(nil), "", "empty key"); eq(T.syncKey({}), "", "empty key")
eq(T.syncKey(out[1]), "1:1:4:1;2:2:3:1;3:3:5:0", "key")
local sent = {}
local a = T.syncDecide(sent, 1, out[1])
ok(a == out[1], "first sight: sent")
eq(T.syncDecide(sent, 1, out[1]), nil, "the same list again: nothing")
local changed = {{i = 1, l = 1, r = 4, p = 0}, out[1][2], out[1][3]}
ok(T.syncDecide(sent, 1, changed) == changed, "the party flag changed: sent")
local empty = T.syncDecide(sent, 1, nil)
ok(type(empty) == "table" and #empty == 0, "gone: the empty list is sent once")
eq(sent[1], nil, "and forgotten")
eq(T.syncDecide(sent, 1, nil), nil, "then nothing again")
eq(T.syncDecide(sent, 77, {}), nil, "a viewer that never saw one gets no empty message")
sent = {[1] = "a", [2] = "b", [3] = "c"}
T.syncPrune(sent, {[2] = true})
ok(sent[1] == nil and sent[2] == "b" and sent[3] == nil, "prune keeps the ones online")
T.syncForget(sent, 2); eq(sent[2], nil, "forget")
T.syncSent = {}; T.syncLastMs = nil
ok(T.syncDue(1000), "first check"); ok(not T.syncDue(1500), "not twice in half a second"); ok(T.syncDue(1950), "after the gap (900)")
ok(not T.syncDue(2000), "gap counts from the last check")
T.syncSent[5] = "x"; T.clear(5); eq(T.syncSent[5], nil, "clear (logout) forgets the viewer's list")

-- ------------------------------------------------------------------ the glue (mocks)
local events = {}
local function obj(name)
	local o = {}
	function o:register() if name then events[name] = o end end
	function o:interval() end
	return o
end
function CreatureEvent(name) return obj(name) end
function GlobalEvent(name) return obj(name) end
local pendingCb
EventCallback = setmetatable({}, {
	__index = function(_, k) if k == "register" then return function() end end end,
	__newindex = function() end
})
function addEvent() end
ChaosSpell = {canAttack = function() return true end}
local effects = {}
local msgs = {}
local players, byId = {}, {}
local P_mt = {}
P_mt.__index = P_mt
local store = {}
function P_mt:getId() return self.id end
function P_mt:getPosition() return self.pos end
function P_mt:getParty() return self.party and {getLeader = function() return {getId = function() return self.party end} end} or nil end
function P_mt:getHealth() return self.health end
function P_mt:getMaxHealth() return 1000 end
function P_mt:getVocation() local v = self.voc; return {getId = function() return v end} end
function P_mt:getStorageValue(k) return (store[self.id] or {})[k] or -1 end
function P_mt:setStorageValue(k, v) store[self.id] = store[self.id] or {}; store[self.id][k] = v end
function P_mt:addCondition() end
function P_mt:registerEvent() end
function P_mt:getCondition() return nil end
function P_mt:sendExtendedOpcode(op, buffer)
	msgs[#msgs + 1] = {to = self.id, op = op, buffer = buffer}
	return true
end
local function player(id, voc, x, y, party)
	local p = setmetatable({id = id, voc = voc, pos = setmetatable({x = x, y = y, z = 7}, {__index = {
		sendMagicEffect = function(_, e) effects[#effects + 1] = e end}}), party = party, health = 1000}, P_mt)
	byId[id] = p
	players[#players + 1] = p
	return p
end
Game = {getPlayers = function() return players end}
function Player(id) return byId[id] end
function Condition() return {setParameter = function() end} end
function Position(p) return p end
-- a minimal json for the fallback sender: the glue prefers Chaos.send, which we mock to keep the table
Chaos = Chaos or {}
local sentTables = {}
Chaos.send = function(p, op, action, data)
	sentTables[#sentTables + 1] = {to = p.id, op = op, action = action, data = data}
	return true
end
local clock = 100000
dofile("data/scripts/chaos/templar_combat.lua")
T.now = function() return clock end
T.syncSent = {}; T.syncLastMs = nil
local tick = events.ChaosTemplarAura.onThink
local function step(ms)
	clock = clock + (ms or 1000)
	sentTables = {}
	effects = {}
	tick(1000)
end

local tp = player(11, TEMPLAR, 100, 100, 11)
local mate = player(12, 4, 103, 100, 11)
local stranger = player(13, 4, 104, 100, nil)
local far = player(14, 4, 500, 500, nil)
step()
eq(#effects, 0, "no map effect from the aura any more (the 4 s holy_spiral is gone)")
local by = {}
for _, m in ipairs(sentTables) do by[m.to] = m end
ok(by[11] ~= nil and by[12] ~= nil and by[13] ~= nil, "the Templar, its mate and a bystander near it are told")
eq(by[14], nil, "a player far from every Templar is told nothing")
eq(by[11].op, ChaosOpcodes.templarAura, "on the templarAura opcode"); eq(by[11].action, "sync", "action sync")
eq(by[11].data.t[1].i, 11, "creature id"); eq(by[11].data.t[1].l, 1, "line"); eq(by[11].data.t[1].r, 4, "radius")
eq(by[11].data.t[1].p, 1, "the Templar is in a party (of its leader's id): it sees its own frame")
eq(by[12].data.t[1].p, 1, "a party member sees the frame"); eq(by[13].data.t[1].p, 0, "a bystander sees the sigil only")
eq(#by[11].data.t, 1, "one Templar in view")

-- nothing changed: nothing is sent
step()
eq(#sentTables, 0, "the same state a second later: no message")
step(); eq(#sentTables, 0, "and a third time")

-- never faster than the gap: a change within half a second waits for the next check
mate.party = nil
step(400)
eq(#sentTables, 0, "a check 400 ms after the last one does not run")
step(600)
eq(#sentTables, 1, "the party change is sent at the next check")
eq(sentTables[1].to, 12, "only to the player whose view changed"); eq(sentTables[1].data.t[1].p, 0, "no frame once it left the party")

-- the Templar leaves its party: its own frame goes
tp.party = nil
step()
local got = {}
for _, m in ipairs(sentTables) do got[m.to] = m end
ok(got[11] ~= nil and got[11].data.t[1].p == 0, "the Templar without a party: no frame")
eq(got[13], nil, "the bystander's view did not change"); eq(got[12], nil, "nor the one who already left")

-- a player far away walks into view
far.pos.x, far.pos.y = 110, 100
step()
eq(#sentTables, 1, "one message"); eq(sentTables[1].to, 14, "to the player who came near"); eq(sentTables[1].data.t[1].i, 11, "about the Templar")
far.pos.x, far.pos.y = 500, 500
step()
eq(#sentTables, 1, "and when it leaves, one empty list"); eq(#sentTables[1].data.t, 0, "empty")
step(); eq(#sentTables, 0, "then silence")

-- a Passive Tree radius bonus changes the radius sent (Bastion: radius +, class_tree.lua)
local CT = ChaosClassTree
if CT and CT.write and CT.fx and CT.fx.ksBastion then
	CT.write(tp, {ksBastion = 1})
	step()
	local r = nil
	for _, m in ipairs(sentTables) do if m.to == 11 then r = m.data.t[1].r end end
	eq(r, 4 + (CT.fx.ksBastion.radius or 0), "Bastion widens the range that is drawn")
	CT.write(tp, {})
	step()
end

-- the Templar dies: everyone who saw it is told it is gone
tp.health = 0
step()
local gone = {}
for _, m in ipairs(sentTables) do gone[m.to] = #m.data.t end
eq(gone[11], 0, "the dead Templar's own list is empty"); eq(gone[12], 0, "so is its mate's"); eq(gone[13], 0, "and the bystander's")
tp.health = 1000
step()
eq(#sentTables, 3, "alive again: all three are told")

-- logout: forgotten; the next login is told at the next check
byId[12] = nil
for i = #players, 1, -1 do if players[i].id == 12 then table.remove(players, i) end end
events.ChaosTemplarLogout.onLogout(mate)
eq(T.syncSent[12], nil, "logout forgets the player's list")
step()
eq(#sentTables, 0, "nobody else changed")
byId[12] = mate; players[#players + 1] = mate
step()
eq(#sentTables, 1, "the player who logs in again is told at the next check"); eq(sentTables[1].to, 12, "it is the one")

-- no Templar online at all: nothing but the empty lists
tp.voc = 4
step()
for _, m in ipairs(sentTables) do eq(#m.data.t, 0, "only empty lists once the last Templar is gone") end
step(); eq(#sentTables, 0, "and then nothing")

if fails > 0 then
	print(string.format("templar_aura_sync_test: %d of %d checks failed", fails, checks))
	os.exit(1)
end
print(string.format("templar_aura_sync_test: all %d checks passed", checks))
