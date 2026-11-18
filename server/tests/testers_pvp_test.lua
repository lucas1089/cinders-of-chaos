-- Run from the server/ folder: luajit tests/testers_pvp_test.lua (no engine; CI runs it with luajit and lua5.3)
-- PvP among the tester bots (O652, server/README.md "The rest of the closed audit (O589)" step 10): the targeting rule of testers_core.lua
-- (K.pvpRefusal) and of testers.lua (the guard, X.pvpFoe, X.pvpProbe), and the Marches' own foe rule and probe (pvpzone.lua Z.foe, Z.probe) on a
-- mocked engine. The arena, battleground and season parts are in arena_flow_test.lua and battleground_flow_test.lua.
local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		io.stderr:write("FAIL " .. label .. "\n")
	end
end
local function eq(a, b, label)
	check(a == b, tostring(label or "") .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z][A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
RETURNVALUE_NOERROR, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER = 0, 41

local events, callbacks = {}, {}
local function newEvent(name)
	local e = setmetatable({name = name}, {__index = function() return function() end end})
	function e:type() end
	function e:register() events[name] = e end
	function e:interval() end
	return e
end
CreatureEvent, GlobalEvent, TalkAction, MoveEvent = newEvent, newEvent, newEvent, newEvent
EventCallback = {}
function EventCallback:register()
	for name, fn in pairs(self) do
		if type(fn) == "function" and name ~= "register" then
			callbacks[name] = fn
		end
	end
end
function addEvent() end
local realPrint = print
print = function() end
db = {query = function() return true end, storeQuery = function() return false end, escapeString = function(s) return "'" .. tostring(s) .. "'" end}
local spectators = {}
Game = {getPlayers = function() return {} end, getStorageValue = function() return -1 end,
	getSpectators = function() return spectators end, broadcastMessage = function() return true end}
Position = function(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end} end
ChaosTitles = {register = function() end}

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/testers_core.lua")
local K = ChaosTestersCore

-- ------------------------------------------------------------------ the rule (testers_core.lua)
eq(K.pvpRefusal(true, false, true, "arena", "arena"), "mixed", "a tester against a player: mixed, in a place, switch on")
eq(K.pvpRefusal(false, true, true, "arena", "arena"), "mixed", "a player against a tester: mixed")
eq(K.pvpRefusal(true, true, false, "arena", "arena"), "closed-off", "two testers, the switch off")
eq(K.pvpRefusal(true, true, nil, "arena", "arena"), "closed-off", "an unknown switch is off")
eq(K.pvpRefusal(true, true, true, nil, nil), "no-place", "two testers on the street")
eq(K.pvpRefusal(true, true, true, "arena", nil), "no-place", "one of them outside a place")
eq(K.pvpRefusal(true, true, true, "arena", "siege"), "no-place", "two different places")
eq(K.pvpRefusal(true, true, true, "arena", "arena"), nil, "two testers in one arena, switch on: allowed")
eq(K.pvpRefusal(true, true, true, "pvp zone", "pvp zone"), nil, "two testers in the Marches")
eq(K.pvpRefusal(false, false, false, nil, nil), nil, "two players: not the testers' business")
check(K.CLOSED_TEXT["no-place"] ~= nil, "the refusal has a text")

-- ------------------------------------------------------------------ testers.lua
local reader, now = "on", 1000
K.reader, K.clock = function() return reader end, function() return now end
local function bump() now = now + 100; K.resetClosedCache() end
K.resetClosedCache()

local players = {}
local function player(id, name, tester, pos)
	local p = {id = id, name = name, pos = pos or {x = 100, y = 100, z = 7}, storage = {}, party = nil}
	if tester then p.storage[Chaos.storage.tester] = 1 end
	function p:isPlayer() return true end
	function p:getMaster() return nil end
	function p:getId() return self.id end
	function p:getGuid() return self.id + 1000 end
	function p:getName() return self.name end
	function p:getParty() return self.party end
	function p:getPosition() return Position(self.pos.x, self.pos.y, self.pos.z) end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:getLevel() return 700 end
	p.health = 800
	function p:getHealth() return self.health end
	function p:getMaxHealth() return 1000 end
	function p:getGroup() return {getId = function() return 1 end} end
	function p:getAccountType() return 1 end
	function p:sendCancelMessage() end
	players[id] = p
	return p
end
Player = function(id) return players[id] end
dofile("data/scripts/chaos/testers.lua")
local X = ChaosTesters
local a, b, c = player(1, "Tester Aaa", true), player(2, "Tester Bbb", true, {x = 103, y = 100, z = 7}), player(3, "Tester Ccc", true, {x = 140, y = 100, z = 7})
local ana = player(4, "Ana", false, {x = 101, y = 100, z = 7})
local combat = callbacks.onTargetCombat

-- the guard counts what it cancels
local place = "arena"
ChaosBlessings = {pvpPlace = function() return place end}
eq(combat(a, ana), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "a tester never hits a player, in a PvP place either")
eq(combat(a, ana), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "again")
eq(X.pvpStats[a:getId()].player, 2, "the cancelled hits on a player are counted")
eq(combat(ana, a), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "a player never hits a tester")
reader = nil
bump()
eq(combat(a, b), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "two testers, the switch off")
eq(X.pvpStats[a:getId()].off, 1, "counted as a hit the switch cancelled")
reader = "on"
bump()
place = nil
eq(combat(a, b), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "two testers, switch on, no PvP place")
eq(X.pvpStats[a:getId()].outside, 1, "counted as a hit outside a place")
place = "arena"
eq(combat(a, b), RETURNVALUE_NOERROR, "two testers in a PvP place, switch on")
eq(combat(a, a), RETURNVALUE_NOERROR, "a tester and itself: the engine's rules")

-- X.pvpFoe: the same rule plus the place's own foe rule
local foes = {}
ChaosArena = {foe = function(x, y) return foes.arena == true end}
ChaosBattleground = {foe = function() return foes.bg == true end}
ChaosPvpZone = {foe = function() return foes.zone == true end}
ChaosSiege = {targetCombat = function() return foes.siege and RETURNVALUE_NOERROR or RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER end}
local ok, why = X.pvpFoe(a, ana)
check(not ok and why == "not two testers", "no foe among a player")
ok, why = X.pvpFoe(a, a)
check(not ok, "none against itself")
reader = nil
bump()
ok, why = X.pvpFoe(a, b)
check(not ok and why == "closed-off", "no foe with the switch off")
reader = "on"
bump()
place = nil
ok, why = X.pvpFoe(a, b)
check(not ok and why == "no-place", "no foe outside a place")
place = "arena"
foes.arena = false
ok = X.pvpFoe(a, b)
check(not ok, "a team mate (the arena's own rule says no) is no foe")
foes.arena = true
ok, why = X.pvpFoe(a, b)
check(ok and why == "arena", "the other team of the arena is a foe")
place = "battleground"
foes.bg = true
ok, why = X.pvpFoe(a, b)
check(ok and why == "battleground", "the battleground's foe")
place = "pvp zone"
foes.zone = true
check(X.pvpFoe(a, b), "the Marches' foe")
foes.zone = false
check(not X.pvpFoe(a, b), "the Marches: protected or in one party: no")
place = "siege"
foes.siege = true
check(X.pvpFoe(a, b), "the siege arena's foe")
foes.siege = false
check(not X.pvpFoe(a, b), "the siege: a guild mate is no foe")

-- the probe: the foe in sight, the guide, the counters
place = "arena"
foes.arena = true
spectators = {a, b, c, ana}
ChaosArena.probe = function() return {inMatch = true, foes = {{x = 140, y = 100, z = 7, name = "Tester Ccc"}}} end
ChaosPvpSeason = {listedTesters = function() return 0 end}
local pr = X.pvpProbe(a)
check(pr.closed and pr.place == "arena" and pr.seasonListed == 0, "probe: the switch, the place, no tester in the season rows")
check(pr.foe and pr.foe.name == "Tester Bbb" and pr.foe.seen and pr.foe.dist == 3 and pr.foe.hp == 80, "probe: the nearest foe in sight is a tester (a player is never one), with its health")
check(pr.guide.mode == "fight" and pr.guide.area == "foe", "probe: in reach: fight")
eq(pr.cancelledPlayer, 2, "probe: the hits on a player that were cancelled")
spectators = {a, c, ana}
pr = X.pvpProbe(a)
check(pr.foe and pr.foe.name == "Tester Ccc" and pr.foe.seen and pr.foe.dist == 40, "probe: a tester far away is seen")
spectators = {a, ana}
pr = X.pvpProbe(a)
check(pr.foe and pr.foe.name == "Tester Ccc" and not pr.foe.seen and pr.guide.mode == "walk", "probe: out of sight, the system's list gives the foe: walk")
place = nil
pr = X.pvpProbe(a)
check(pr.foe == nil and pr.guide.mode == "wait", "probe: outside a PvP place the bot has no foe at all")
place = "battleground"
ChaosArena.probe = nil
ChaosBattleground.probe = function() return {inMatch = true, phase = "fight", team = 1, foes = {}, braziers = {{x = 110, y = 100, z = 7, owner = 1}, {x = 120, y = 100, z = 7, owner = 0}}} end
pr = X.pvpProbe(a)
spectators = {a}
pr = X.pvpProbe(a)
check(pr.guide.mode == "walk" and pr.guide.area == "brazier" and pr.guide.goal.x == 120, "probe: no foe in a fight: the nearest brazier the team does not hold")

-- ------------------------------------------------------------------ the Marches: Z.foe and Z.probe
dofile("data/scripts/chaos/pvpzone.lua")
local Z = ChaosPvpZone
check(Z.foe and Z.probe, "pvpzone.lua has the foe rule and the probe")
local z1, z2, z3, z4 = player(11, "Tester Zaa", true), player(12, "Tester Zbb", true), player(13, "Tester Zcc", true), player(14, "Ana Z", false)
check(not Z.foe(z1, z2), "outside the Marches: no foe")
Z.state[z1:getId()], Z.state[z2:getId()], Z.state[z3:getId()] = {slot = 4}, {slot = 4}, {slot = 5}
Z.state[z4:getId()] = {slot = 0}
check(Z.foe(z1, z2) and Z.foe(z2, z1), "two in one instance, nobody protected: foes")
check(not Z.foe(z1, z3), "another instance: no")
check(not Z.foe(z1, z1), "not itself")
Z.state[z2:getId()].moveAt = 5
check(not Z.foe(z1, z2), "one on its way out (exit circle) is no foe")
Z.state[z2:getId()].moveAt = nil
local party = {}
z1.party, z2.party = party, party
check(not Z.foe(z1, z2), "one party: no")
z1.party, z2.party = nil, nil
local zp = Z.probe(z1)
check(zp.inside and zp.slot == 4 and zp.testers == 1 and zp.others == 0 and #zp.foes == 1 and zp.foes[1].hp == 80,"probe: the instance holds only testers, one foe")
check(not Z.probe(z4).inside or Z.probe(z4).slot == 0, "probe: a player's own")

print = realPrint
print(string.format("testers_pvp_test: %d checks, %d failed", count, failures))
if failures > 0 then os.exit(1) end
