-- Run from the server/ folder: luajit tests/levelwings_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the level-up wings (data/scripts/chaos/levelwings_core.lua, levelwings.lua): the payload (a gain only, the
-- levels gained), the throttles (per character, per viewer, server-wide; windows roll over; the cooldown is spent only
-- when a play goes out), pruning, and the glue against a mocked engine: the events, every spectator gets one JSON
-- message on opcode 191, several levels play once, a level lost plays nothing, a repeated set_level is throttled.
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/levelwings_core.lua")
local L = ChaosLevelWings
local cfg = dofile("data/scripts/chaos/levelwings_config.lua")

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

-- ------------------------------------------------------------------ opcode
eq(ChaosOpcodes.levelWings, 191, "opcode")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	ok(seen[v] == nil, "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	ok(ChaosOpcodes.levelWings ~= v, "not a base opcode " .. v)
end

-- ------------------------------------------------------------------ config
ok(cfg.enabled, "on by default")
ok(cfg.playerCooldownMs >= 2000, "cooldown longer than the animation (about 1.8 s)")
ok(cfg.viewerMax >= 1 and cfg.globalMax >= cfg.viewerMax, "budgets")

-- ------------------------------------------------------------------ payload
local p = L.payload(0x10000001, 41, 42)
eq(p.id, 0x10000001, "id"); eq(p.lv, 42, "new level"); eq(p.n, 1, "one level")
eq(L.payload(5, 41, 47).n, 6, "several levels: one payload")
eq(L.payload(5, 42, 41), nil, "a level lost: nothing")
eq(L.payload(5, 42, 42), nil, "no change: nothing")
eq(L.payload(nil, 1, 2), nil, "no id")
eq(L.payload(0, 1, 2), nil, "id 0")
eq(L.payload("7", "1", "3").lv, 3, "numbers as text")
-- the JSON stays tiny (well under the 8192 byte limit of one message)
local keys = 0
for _ in pairs(p) do keys = keys + 1 end
eq(keys, 3, "three fields")

-- ------------------------------------------------------------------ per character cooldown
local st = L.newState()
local t = 1000000
local got, why = L.decide(st, cfg, 5, 10, 11, t)
ok(got ~= nil, "first play goes out")
got, why = L.decide(st, cfg, 5, 11, 12, t + 1000)
eq(got, nil, "again within the cooldown"); eq(why, "cooldown", "reason")
got = L.decide(st, cfg, 6, 11, 12, t + 1000)
ok(got ~= nil, "another character is not held back")
got = L.decide(st, cfg, 5, 12, 13, t + cfg.playerCooldownMs - 1)
eq(got, nil, "1 ms before the cooldown ends")
got = L.decide(st, cfg, 5, 12, 13, t + cfg.playerCooldownMs)
ok(got ~= nil, "after the cooldown")
-- a dropped gain does not restart the cooldown
st = L.newState()
L.decide(st, cfg, 5, 10, 11, t)
L.decide(st, cfg, 5, 11, 12, t + 3000)
ok(L.decide(st, cfg, 5, 12, 13, t + cfg.playerCooldownMs) ~= nil, "cooldown counts from the last play, not the last try")
-- a lost level never plays and never spends the cooldown
st = L.newState()
got, why = L.decide(st, cfg, 5, 12, 11, t)
eq(got, nil, "loss"); eq(why, "no gain", "loss reason")
ok(L.decide(st, cfg, 5, 11, 12, t + 1) ~= nil, "loss did not spend the cooldown")
-- switched off
local off = {}
for k, v in pairs(cfg) do off[k] = v end
off.enabled = false
got, why = L.decide(L.newState(), off, 5, 1, 2, t)
eq(got, nil, "off"); eq(why, "disabled", "off reason")
-- a clock that went back does not lock a character out
st = L.newState()
L.decide(st, cfg, 5, 1, 2, t)
ok(L.decide(st, cfg, 5, 2, 3, t - 10) ~= nil, "clock went back")

-- ------------------------------------------------------------------ server-wide budget (staff levelling everyone)
st = L.newState()
local small = {}
for k, v in pairs(cfg) do small[k] = v end
small.globalMax, small.globalWindowMs = 3, 1000
local played = 0
for pid = 1, 10 do
	if L.decide(st, small, pid, 1, 50, t) then
		played = played + 1
	end
end
eq(played, 3, "only globalMax per window")
got, why = L.decide(st, small, 11, 1, 50, t + 999)
eq(why, "busy", "still the same window")
ok(L.decide(st, small, 11, 1, 50, t + 1000) ~= nil, "next window")
-- a character dropped as busy keeps no cooldown
ok(L.decide(st, small, 4, 1, 50, t + 1000) ~= nil, "busy did not spend the character's cooldown")

-- ------------------------------------------------------------------ per viewer budget
st = L.newState()
local small2 = {}
for k, v in pairs(cfg) do small2[k] = v end
small2.viewerMax, small2.viewerWindowMs = 2, 1000
local r = L.recipients(st, small2, {100, 101, 100}, t)
eq(#r, 2, "a viewer listed twice gets one"); eq(r[1], 100, "order kept"); eq(r[2], 101, "second viewer")
r = L.recipients(st, small2, {100, 101, 102}, t + 10)
eq(#r, 3, "second play: all within 2")
r = L.recipients(st, small2, {100, 101, 102}, t + 20)
eq(#r, 1, "third play: only the viewer with room"); eq(r[1], 102, "the new viewer")
r = L.recipients(st, small2, {100}, t + 1000)
eq(#r, 1, "window rolled over")
eq(#L.recipients(st, small2, {}, t), 0, "nobody")
eq(#L.recipients(st, small2, nil, t), 0, "nil list")

-- ------------------------------------------------------------------ forget and prune
st = L.newState()
L.decide(st, cfg, 5, 1, 2, t)
L.recipients(st, cfg, {5, 6}, t)
L.forget(st, 5)
eq(st.last[5], nil, "forget: cooldown"); eq(st.viewers[5], nil, "forget: viewer")
ok(st.viewers[6] ~= nil, "others kept")
eq(L.prune(st, cfg, t + 1), 0, "nothing old yet")
eq(L.prune(st, cfg, t + 2), 0, "pruned a moment ago: skipped")
eq(L.prune(st, cfg, t + cfg.pruneAfterMs + 1), 1, "old viewer dropped")
eq(st.viewers[6], nil, "gone")

-- ------------------------------------------------------------------ glue (levelwings.lua) against a mocked engine
SKILL_LEVEL, SKILL_SWORD = 8, 2
local clock = 5000000
os.mtime = function() return clock end
local events = {}
function CreatureEvent(name)
	local o = {}
	function o:register() events[name] = o end
	return o
end
json = {encode = function(v)
	return string.format('{"action":"%s","data":{"id":%d,"lv":%d,"n":%d}}', v.action, v.data.id, v.data.lv, v.data.n)
end}
local sent = {}
local function newPlayer(id, x)
	local pl = {id = id, x = x, registered = {}}
	function pl:getId() return self.id end
	function pl:getPosition() return {x = self.x, y = 100, z = 7} end
	function pl:registerEvent(name) self.registered[#self.registered + 1] = name end
	function pl:sendExtendedOpcode(op, buffer)
		sent[#sent + 1] = {to = self.id, op = op, buffer = buffer}
		return true
	end
	return pl
end
local hero, friend, stranger = newPlayer(0x10000001, 100), newPlayer(0x10000002, 103), newPlayer(0x10000003, 104)
local spectatorArgs
Game = {getSpectators = function(pos, multifloor, onlyPlayers)
	spectatorArgs = {pos = pos, multifloor = multifloor, onlyPlayers = onlyPlayers}
	return {hero, friend, stranger}
end}
local printed = {}
local realPrint = print
print = function(s) printed[#printed + 1] = s end
ChaosLevelWings.state = nil
dofile("data/scripts/chaos/levelwings.lua")
print = realPrint
eq(#printed, 0, "loads quietly")
ok(events.ChaosLevelWingsLogin and events.ChaosLevelWingsAdvance and events.ChaosLevelWingsLogout, "three events")
events.ChaosLevelWingsLogin.onLogin(hero)
eq(table.concat(hero.registered, ","), "ChaosLevelWingsAdvance,ChaosLevelWingsLogout", "login registers")

local adv = events.ChaosLevelWingsAdvance.onAdvance
eq(adv(hero, SKILL_LEVEL, 41, 44), true, "returns true")
eq(#sent, 3, "every spectator, the hero too")
eq(spectatorArgs.onlyPlayers, true, "players only"); eq(spectatorArgs.multifloor, false, "this floor")
eq(spectatorArgs.pos.x, 100, "around the hero")
for _, m in ipairs(sent) do
	eq(m.op, 191, "opcode")
	eq(m.buffer, '{"action":"play","data":{"id":268435457,"lv":44,"n":3}}', "payload")
end
-- several levels were one call: one message each, already checked; a second call right away is the cooldown
sent = {}
clock = clock + 500
adv(hero, SKILL_LEVEL, 44, 45)
eq(#sent, 0, "set_level again within the cooldown: nothing")
-- other skills and a lost level do nothing
clock = clock + 10000
adv(hero, SKILL_SWORD, 10, 11)
adv(hero, SKILL_LEVEL, 45, 44)
eq(#sent, 0, "sword skill and a lost level: nothing")
-- after the cooldown it plays again
adv(hero, SKILL_LEVEL, 44, 45)
eq(#sent, 3, "after the cooldown")
-- an engine error is caught and logged, the event still returns true
Game.getSpectators = function() error("boom") end
clock = clock + 10000
printed = {}
print = function(s) printed[#printed + 1] = s end
local okRet = adv(friend, SKILL_LEVEL, 1, 2)
print = realPrint
eq(okRet, true, "error: still true")
ok(printed[1] and printed[1]:find("boom", 1, true) ~= nil, "error logged")
-- logout forgets the character
events.ChaosLevelWingsLogout.onLogout(hero)
eq(ChaosLevelWings.state.last[hero.id], nil, "logout forgets")

if fails > 0 then
	print(string.format("levelwings: %d of %d checks failed", fails, checks))
	os.exit(1)
end
print(string.format("levelwings: all %d checks passed", checks))
