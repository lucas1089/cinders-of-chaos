-- Run from the server/ folder: luajit tests/trainer_meter_test.lua (and lua5.3; CI runs both)
-- Trainers as DPS meters (O573; trainer_meter_core.lua, trainer_meter_config.lua, trainer_meter.lua; client
-- game_trainerdps; server/README.md "Trainers as DPS meters (O573)"). Part 1, the pure logic: which monsters are trainers,
-- the target profile, the rolling window, the average, the end of a session, the rows (cap, top N and "Others"), the
-- elements, the registry (a new session for another trainer or after the end, reset). Part 2, trainer_meter.lua on a
-- mocked engine: the combat log's hook, packets only when a session begins, ends or is reset and once a second while it
-- runs (never per hit), players on different trainers and on the same one, the party list, `watch` / `open` / `reset`,
-- the trainer that disappears, logout, the profile hooks of the monster defence. Part 3, the opcode (147: free, unique,
-- named by the client module). All data is synthetic.
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	checks = checks + 1
	if not v then
		error(m or "expected true", 2)
	end
end
local function near(a, b, tol, m)
	checks = checks + 1
	if math.abs(a - b) > tol then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- part 1: the core
dofile("data/scripts/chaos/trainer_meter_core.lua")
local M = ChaosTrainerMeterCore
local cfgFile = dofile("data/scripts/chaos/trainer_meter_config.lua")
local cfg = M.configure(cfgFile)

-- the config
eq(cfg.windowMs, 5000, "window 5 s")
eq(cfg.endAfterMs, 10000, "session ends after 10 s")
eq(cfg.maxRowsSent, 10, "top 10")
eq(cfg.profile.class, "normal", "default profile: normal")
eq(cfg.profile.level, "player", "default profile: the player's level")
ok(cfg.sendMs == 1000, "a summary every second")

-- who is a trainer
for _, n in ipairs({"Training Dummy", "Chaos Dummy", "Salamander Trainer", "Training Monk", "dummy 2"}) do
	ok(M.isTrainerName(cfg, n), n .. " is a trainer")
end
for _, n in ipairs({"Dragon", "Brainstealer", "Demon", "", "Rat"}) do
	ok(not M.isTrainerName(cfg, n), n .. " is not")
end
ok(not M.isTrainerName(cfg, nil) and not M.isTrainerName(cfg, 5), "no name, no trainer")
do
	local c = M.configure({words = {"train"}, names = {"Wooden Post"}, exclude = {"Trainee Rat"}})
	ok(M.isTrainerName(c, "wooden post"), "a listed name (any case)")
	ok(not M.isTrainerName(c, "Trainee Rat"), "excluded")
	ok(M.isTrainerName(c, "Salamander Trainer"), "a word")
	ok(not M.isTrainerName(c, "Dummy"), "only the listed words")
end

-- the target profile
do
	local p = M.profileFor(cfg, "Training Dummy")
	eq(p.class, "normal", "profile class")
	eq(p.level, nil, "profile level: the player's")
	eq(M.levelFor(cfg, p, 150), 150, "the player's level")
	eq(M.levelFor(cfg, p, 0), 1, "level 0 reads as 1")
	eq(M.levelFor(cfg, p, 99999), 2500, "capped")
	local c = M.configure({profile = {enabled = true, class = "elite", level = 300},
		byName = {["boss trainer"] = {class = "boss"}, ["fixed dummy"] = {level = 99999}}})
	p = M.profileFor(c, "Training Dummy")
	eq(p.class, "elite", "configured class")
	eq(p.level, 300, "configured level")
	eq(M.levelFor(c, p, 5), 300, "a fixed level ignores the player's")
	p = M.profileFor(c, "Boss Trainer")
	eq(p.class, "boss", "per name class")
	eq(p.level, 300, "a missing field keeps the default")
	eq(M.profileFor(c, "Fixed Dummy").level, 2500, "a fixed level is capped")
	eq(M.profileFor(M.configure({profile = {enabled = false}}), "Training Dummy"), nil, "off: nil")
	eq(M.profileFor(M.configure({profile = {class = "weird"}}), "x").class, "normal", "an unknown class is normal")
	eq(M.profileFor(M.configure({profile = {level = "player"}}), "x").level, nil, "player = nil")
end

-- the window, the average, the end
local T0 = 100000 -- a multiple of the bucket size
local A = {k = "s:Witchfire Bolt", t = "s", n = "Witchfire Bolt", i = "wif"}
local B = {k = "w:Sword attacks", t = "w", n = "Sword attacks", i = "sword"}
do
	local s = M.newSession(1, 7, "Training Dummy")
	ok(not M.active(s), "empty: not active")
	eq(M.currentDps(cfg, s, T0), 0, "empty: no DPS")
	eq(M.averageDps(cfg, s, T0), 0, "empty: no average")
	eq(M.duration(cfg, s, T0), 0, "empty: no time")
	ok(not M.record(cfg, s, T0, 0, A, "fire"), "a hit of 0 is nothing")
	ok(not M.record(cfg, s, T0, -5, A, "fire"), "a negative hit is nothing")
	eq(s.hits, 0, "nothing counted")
	ok(M.record(cfg, s, T0, 500, A, "fire", false), "the first hit")
	ok(M.active(s), "active")
	eq(M.currentDps(cfg, s, T0), 500, "one lone hit is over the minimum span (1 s), not infinite")
	M.record(cfg, s, T0 + 1000, 200, B, "physical", true)
	M.record(cfg, s, T0 + 2000, 300, A, "fire", false)
	eq(s.total, 1000, "total")
	eq(s.hits, 3, "hits")
	eq(s.crits, 1, "crits")
	eq(s.max, 500, "biggest hit")
	eq(s.maxName, "Witchfire Bolt", "biggest hit source")
	near(M.currentDps(cfg, s, T0 + 2000), 500, 1e-9, "DPS now: all inside the window, over the 2 s so far")
	near(M.averageDps(cfg, s, T0 + 2000), 500, 1e-9, "average since the start")
	eq(M.duration(cfg, s, T0 + 2000), 2000, "time")
	-- the window slides: at +7 s only the hit of +2 s is inside the last 5 s (the older buckets left)
	near(M.currentDps(cfg, s, T0 + 7000), 300 * 1000 / 5000, 1e-9, "DPS now slides")
	near(M.averageDps(cfg, s, T0 + 7000), 1000 * 1000 / 7000, 1e-9, "the average keeps counting the time")
	-- past the window: nothing in it
	eq(M.currentDps(cfg, s, T0 + 9000), 0, "DPS now: nothing inside the window")
	-- the end
	ok(not M.tick(cfg, s, T0 + 2000 + 9999), "not ended after 9.999 s")
	ok(M.tick(cfg, s, T0 + 2000 + 10000), "ended after 10 s")
	ok(s.ended and not M.active(s), "ended, not active")
	ok(not M.tick(cfg, s, T0 + 30000), "ends once")
	eq(M.duration(cfg, s, T0 + 30000), 2000, "the time stops at the last hit")
	near(M.averageDps(cfg, s, T0 + 30000), 500, 1e-9, "the final average")
	eq(M.currentDps(cfg, s, T0 + 12000), 0, "no DPS now once ended")
end

-- the average is never over less than the minimum span
do
	local s = M.newSession(1, 7, "x")
	M.record(cfg, s, T0, 900, A, "fire")
	near(M.averageDps(cfg, s, T0 + 100), 900, 1e-9, "100 ms in: over 1 s")
end

-- rows: sorted, capped, top N and the rest
do
	local c = M.configure({maxRows = 2, maxRowsSent = 3})
	local s = M.newSession(1, 7, "Training Dummy")
	for i = 1, 7 do
		M.record(c, s, T0 + i, i * 10, {k = "s:S" .. i, t = "s", n = "S" .. i, i = ""}, "fire")
	end
	-- the first two sources have rows, the other five share "Other"
	eq(s.nrows, 3, "2 rows and Other")
	eq(s.rows["o:Other"].total, 30 + 40 + 50 + 60 + 70, "the rest under Other")
	local v = M.view(c, s, T0 + 1000)
	eq(#v.rows, 3, "top 3 of 3")
	eq(v.rows[1].n, "Other", "sorted by total")
	eq(v.rows[1].v, 250, "Other total")
	eq(v.rows[2].n, "S2", "then the bigger source")
	eq(v.rows[3].n, "S1", "then the smaller")
	-- more rows than sent: the rest is "Others"
	local c2 = M.configure({maxRowsSent = 2})
	local s2 = M.newSession(1, 7, "x")
	for i = 1, 5 do
		M.record(c2, s2, T0 + i, i * 100, {k = "s:S" .. i, t = "s", n = "S" .. i, i = ""}, "fire", i == 1)
	end
	local v2 = M.view(c2, s2, T0 + 1000)
	eq(#v2.rows, 3, "2 rows and the Others row")
	eq(v2.rows[1].n, "S5", "biggest first")
	eq(v2.rows[2].n, "S4", "second")
	eq(v2.rows[3].n, "Others", "the rest")
	eq(v2.rows[3].v, 100 + 200 + 300, "Others total")
	eq(v2.rows[3].h, 3, "Others hits")
	eq(v2.rows[3].m, 300, "Others biggest")
	eq(v2.rows[3].c, 1, "Others crits (the first source had the crit)")
	local sum = 0
	for _, r in ipairs(v2.rows) do
		sum = sum + r.v
	end
	eq(sum, s2.total, "the rows add up to the total")
end

-- elements and the view
do
	local s = M.newSession(5, 9, "Chaos Dummy")
	M.record(cfg, s, T0, 300, A, "fire", false)
	M.record(cfg, s, T0 + 500, 100, B, "physical", false)
	M.record(cfg, s, T0 + 1000, 150, A, "fire", true)
	M.record(cfg, s, T0 + 1500, 20, B, nil, false)
	local v = M.view(cfg, s, T0 + 2000, {class = "elite", level = nil})
	eq(v.tn, "Chaos Dummy", "name")
	eq(v.tid, 9, "trainer id")
	eq(v.sid, 5, "session id")
	eq(v.act, 1, "active")
	eq(v["end"], 0, "not ended")
	eq(v.empty, 0, "not empty")
	eq(v.tot, 570, "total")
	eq(v.hits, 4, "hits")
	eq(v.crits, 1, "crits")
	eq(v.max, 300, "biggest")
	eq(v.mxn, "Witchfire Bolt", "biggest source")
	eq(v.dur, 2000, "time")
	eq(v.cur, 285, "DPS now")
	eq(v.avg, 285, "average")
	eq(v.w, 5, "window seconds")
	eq(v.e, 10, "end seconds")
	eq(#v.el, 2, "two elements (a hit with none is in no element)")
	eq(v.el[1][1], "fire", "fire first")
	eq(v.el[1][2], 450, "fire total")
	eq(v.el[2][1], "physical", "physical")
	eq(v.prof.c, "elite", "profile class")
	eq(v.prof.l, 0, "profile level 0 = the player's")
	eq(v.rows[1].n, "Witchfire Bolt", "first row")
	eq(v.rows[1].v, 450, "first row total")
	eq(v.rows[1].h, 2, "first row hits")
	eq(v.rows[1].c, 1, "first row crits")
	eq(v.rows[1].m, 300, "first row biggest")
	eq(v.rows[1].t, "s", "first row kind")
	eq(v.rows[1].i, "wif", "first row icon")
	-- an empty session
	local e = M.view(cfg, M.newSession(6, 9, "Chaos Dummy"), T0)
	eq(e.empty, 1, "empty")
	eq(e.act, 0, "not active")
	eq(e.tot, 0, "nothing")
	eq(#e.rows, 0, "no rows")
	ok(e.prof == nil, "no profile asked: none")
	-- an ended one
	M.tick(cfg, s, T0 + 1500 + 10000)
	local f = M.view(cfg, s, T0 + 99999)
	eq(f["end"], 1, "ended")
	eq(f.act, 0, "no longer active")
	eq(f.cur, 0, "no DPS now")
	eq(f.dur, 1500, "the time stopped at the last hit")
	eq(f.avg, 380, "final average 570 / 1.5 s")
end

-- the registry
do
	local reg = M.newRegistry()
	local s1, fresh = M.hit(cfg, reg, 1, 10, "Training Dummy", T0, 100, A, "fire", false)
	ok(fresh, "the first hit begins a session")
	local s1b, fresh2 = M.hit(cfg, reg, 1, 10, "Training Dummy", T0 + 500, 50, B, "physical", false)
	ok(not fresh2 and s1b == s1, "the second hit is in the same one")
	eq(s1.total, 150, "both counted")
	-- another player, the same trainer: its own numbers
	local s2, fresh3 = M.hit(cfg, reg, 2, 10, "Training Dummy", T0 + 600, 1000, A, "fire", false)
	ok(fresh3 and s2 ~= s1, "another player has its own session")
	eq(s1.total, 150, "the first player's numbers are untouched")
	eq(s2.total, 1000, "the second player's own")
	-- another trainer: a new session, the old one is replaced
	local s3, fresh4 = M.hit(cfg, reg, 1, 11, "Chaos Dummy", T0 + 700, 10, A, "fire", false)
	ok(fresh4 and s3.tid == 11 and reg.sess[1] == s3, "another trainer starts another session")
	-- the end, also before its tick ran
	local s4, fresh5 = M.hit(cfg, reg, 1, 11, "Chaos Dummy", T0 + 700 + 10000, 10, A, "fire", false)
	ok(fresh5 and s4 ~= s3, "a hit after the end delay is a new session")
	ok(s3.ended, "the old one ended")
	-- ended by its tick, then a hit
	M.tick(cfg, s4, T0 + 700 + 10000 + 10000)
	local s5, fresh6 = M.hit(cfg, reg, 1, 11, "Chaos Dummy", T0 + 30000, 10, A, "fire", false)
	ok(fresh6 and s5 ~= s4, "a hit after an ended session is a new one")
	-- reset
	local sig = M.signature(s5)
	local r = M.reset(reg, 1)
	ok(r ~= s5 and reg.sess[1] == r, "reset: a new session")
	eq(r.tid, 11, "reset: the same trainer")
	eq(r.name, "Chaos Dummy", "reset: the same name")
	ok(not M.active(r) and r.start == nil, "reset: nothing counted yet")
	ok(M.signature(r) ~= sig, "reset: another signature")
	local r2, fresh7 = M.hit(cfg, reg, 1, 11, "Chaos Dummy", T0 + 31000, 70, A, "fire", false)
	ok(r2 == r and not fresh7, "the first hit after a reset fills the empty session")
	eq(r.total, 70, "after the reset only the new hits")
	eq(M.reset(reg, 99), nil, "no session, nothing to reset")
	-- a tick of an empty session does not end it
	local e = M.newSession(9, 3, "x")
	ok(not M.tick(cfg, e, T0 + 99999999), "an empty session never ends")
end

-- ---------------------------------------------------------------- part 2: the engine file on a mocked engine
local clock = T0
os.mtime = function() return clock end
COMBAT_PHYSICALDAMAGE, COMBAT_FIREDAMAGE = 1, 8

local events, globals = {}, {}
function CreatureEvent(name)
	local o = {name = name}
	function o:type() end
	function o:register() events[name] = o end
	return o
end
function GlobalEvent(name)
	local o = {name = name}
	function o:interval(ms) self.ms = ms end
	function o:register() globals[name] = o end
	return o
end

local byId = {}
local C = {}
C.__index = C
local nextId = 0
local function creature(o)
	nextId = nextId + 1
	o.id = o.id or nextId
	o.events = {}
	o.packets = {}
	byId[o.id] = setmetatable(o, C)
	return o
end
function C:getId() return self.id end
function C:getName() return self.name end
function C:isPlayer() return self.kind == "player" end
function C:isMonster() return self.kind == "monster" end
function C:getLevel() return self.level or 1 end
function C:getParty() return self.party end
function C:registerEvent(name) self.events[name] = true return true end
function C:sendExtendedOpcode(op, buffer) self.packets[#self.packets + 1] = {op = op, data = buffer} return true end
function Player(id) local c = byId[id] return c and c.kind == "player" and not c.offline and c or nil end
function Creature(id) local c = byId[id] return c and not c.removed and c or nil end

local decodeBox, encoded = {}, {}
json = {
	encode = function(t) encoded[#encoded + 1] = t; return "#" .. #encoded end,
	decode = function(s) return decodeBox[s] end,
}
local function packetsOf(p)
	local out = {}
	for _, pk in ipairs(p.packets) do
		out[#out + 1] = encoded[tonumber(pk.data:sub(2))]
	end
	return out
end
local function lastState(p)
	local list = packetsOf(p)
	return list[#list] and list[#list].data
end

dofile("data/scripts/chaos/chaos_constants.lua")
ChaosCombatLog = nil -- the global of the real combat log; the hooks are set on a table the file makes
dofile("data/scripts/chaos/trainer_meter.lua")
local T = ChaosTrainerMeter
local CL = ChaosCombatLog
ok(type(CL.trainerHook) == "function" and type(CL.isTrainer) == "function", "the combat log's hooks are set")
eq(globals.ChaosTrainerMeterThink.ms, 1000, "the clock runs every second")
ok(events.ChaosTrainerMeterExtended ~= nil and events.ChaosTrainerMeterLogin ~= nil, "events registered")

local hero = creature({kind = "player", name = "Hero", level = 300})
local mage = creature({kind = "player", name = "Mage", level = 80})
local dummy = creature({kind = "monster", name = "Training Dummy"})
local dummy2 = creature({kind = "monster", name = "Chaos Dummy"})
local dragon = creature({kind = "monster", name = "Dragon"})
for _, p in ipairs({hero, mage}) do
	events.ChaosTrainerMeterLogin.onLogin(p)
	ok(p.events.ChaosTrainerMeterExtended and p.events.ChaosTrainerMeterLogout, "login registers the events")
end
ok(CL.isTrainer(dummy) and CL.isTrainer(dummy2), "trainers")
ok(not CL.isTrainer(dragon) and not CL.isTrainer(hero), "a dragon and a player are not")

local function hit(p, tr, amount, src, el, crit)
	CL.trainerHook(p, tr, src or A, amount, el or "fire", crit or false, clock)
end
local function opcode(p, action, data)
	local id = "m" .. #encoded .. action
	decodeBox[id] = {action = action, data = data}
	events.ChaosTrainerMeterExtended.onExtendedOpcode(p, 147, id)
end
local function think()
	globals.ChaosTrainerMeterThink.onThink(1000)
end

-- nobody watches: hits and ticks send nothing
hit(hero, dummy, 300)
think()
eq(#hero.packets, 0, "a client that never sent watch gets nothing")
eq(T.reg.sess[hero.id].total, 300, "but the session counts")

-- another opcode, a bad payload: nothing
events.ChaosTrainerMeterExtended.onExtendedOpcode(hero, 200, "x")
events.ChaosTrainerMeterExtended.onExtendedOpcode(hero, 147, "garbage")
eq(#hero.packets, 0, "foreign opcode and garbage ignored")

-- watch: the running session is sent at once
opcode(hero, "watch", {on = true})
eq(#hero.packets, 1, "watch with a session: its state")
local st = lastState(hero)
eq(st.tot, 300, "state: total")
eq(st.act, 1, "state: active")
eq(st.tn, "Training Dummy", "state: trainer")
eq(st.prof.c, "normal", "state: the default profile")
eq(st.prof.l, 0, "state: the player's level")

-- no packet per hit
local before = #hero.packets
for i = 1, 20 do
	clock = clock + 50
	hit(hero, dummy, 10, B, "physical")
end
eq(#hero.packets, before, "20 hits, no packet")
-- the clock: one a second while active
think()
eq(#hero.packets, before + 1, "a tick: one packet")
think()
eq(#hero.packets, before + 2, "another tick: another one")
st = lastState(hero)
eq(st.tot, 500, "state: all hits counted")
eq(st.hits, 21, "state: hits")
eq(st.rows[1].n, "Witchfire Bolt", "state: rows")
eq(st.rows[2].n, "Sword attacks", "state: second row")
eq(st.el[1][1], "fire", "state: elements")
-- the other player: nothing sent (not watching), numbers of its own
hit(mage, dummy, 40)
think()
eq(#mage.packets, 0, "the mage does not watch")
eq(T.reg.sess[mage.id].total, 40, "the mage's own total")
eq(T.reg.sess[hero.id].total, 500, "the hero's is untouched by the mage's hits on the same trainer")
opcode(mage, "watch", {on = true})
eq(lastState(mage).tot, 40, "the mage sees its own numbers")
eq(lastState(mage).tn, "Training Dummy", "on the same trainer")
ok(lastState(mage).party == nil, "no party, no party list")

-- the party: both on the same trainer
local party = {getMembers = function() return {mage} end, getLeader = function() return hero end}
hero.party, mage.party = party, party
clock = clock + 1000
think()
st = lastState(hero)
ok(st.party ~= nil and #st.party == 2, "the party list has both")
eq(st.party[1].n, "Hero", "sorted by total")
eq(st.party[1].me, 1, "the viewer is marked")
eq(st.party[2].n, "Mage", "the other member")
eq(st.party[2].tot, 40, "the member's total")
ok(st.party[2].me == nil, "not marked")
local ms = lastState(mage)
eq(ms.party[2].n, "Mage", "the mage sees the same list")
eq(ms.party[2].me, 1, "marked for the mage")
-- a member on another trainer is not in the list
hit(mage, dummy2, 10)
clock = clock + 1000
think()
ok(lastState(hero).party == nil, "a member on another trainer is not listed")
eq(lastState(mage).tn, "Chaos Dummy", "the mage's session moved to the other trainer")
eq(lastState(mage).tot, 10, "and started over")
eq(lastState(mage).sid ~= nil, true, "session id")
hero.party, mage.party = nil, nil

-- a session begins: the panel hears at once (watching)
local n = #mage.packets
clock = clock + 20000 -- the mage's session ended
think()
eq(lastState(mage)["end"], 1, "ended: the last state says so")
local n2 = #mage.packets
eq(n2, n + 1, "the end is sent once")
think()
think()
eq(#mage.packets, n2, "nothing more after the end")
hit(mage, dummy2, 25)
eq(#mage.packets, n2 + 1, "a new session is sent when it begins")
eq(lastState(mage).tot, 25, "the new session starts at the first hit")
eq(lastState(mage).act, 1, "active")

-- the hero's session also ended with the long gap; its result stays, a reset empties it
think()
st = lastState(hero)
eq(st["end"], 1, "the hero's session ended")
eq(st.tot, 500, "its result stays")
local h = #hero.packets
opcode(hero, "reset")
eq(#hero.packets, h + 1, "reset: a state")
st = lastState(hero)
eq(st.empty, 1, "reset: empty")
eq(st.tot, 0, "reset: nothing")
eq(st.tn, "Training Dummy", "reset: the same trainer")
think()
eq(#hero.packets, h + 1, "an empty session is not re-sent")
hit(hero, dummy, 60)
think()
st = lastState(hero)
eq(st.tot, 60, "after the reset only the new hits")
eq(st.act, 1, "active again")

-- open: the last result, or none
local lonely = creature({kind = "player", name = "Lonely"})
events.ChaosTrainerMeterLogin.onLogin(lonely)
opcode(lonely, "open")
eq(lastState(lonely).none, 1, "open without a session: none")
opcode(lonely, "reset")
eq(#lonely.packets, 1, "reset without a session sends nothing")
opcode(lonely, "watch", {on = false})
hit(lonely, dummy, 5)
think()
eq(#lonely.packets, 1, "watch off: nothing more")

-- the trainer disappears: the session ends
hit(hero, dummy2, 5)
local hp = #hero.packets
dummy2.removed = true
think()
eq(lastState(hero)["end"], 1, "the trainer is gone: ended")
think()
eq(#hero.packets, hp + 1, "and sent once")

-- logout clears
events.ChaosTrainerMeterLogout.onLogout(hero)
ok(T.reg.sess[hero.id] == nil and T.watch[hero.id] == nil, "logout: session and watch dropped")
mage.offline = true
think()
ok(T.reg.sess[mage.id] == nil, "a player that is gone: its session is dropped")

-- the profile hooks of the monster defence
do
	local MD = ChaosMonsterDefence
	local p = MD.trainerProfile(dummy)
	ok(p ~= nil and p.class == "normal" and p.level == nil, "a trainer has the default profile")
	eq(MD.trainerProfile(dragon), nil, "a dragon has none")
	eq(MD.trainerLevel(p, hero), 300, "the level of the player that hits")
	eq(MD.trainerLevel(p, {getLevel = function() error("x") end}), 1, "a player without a level reads as 1")
	eq(MD.trainerLevel({class = "boss", level = 700}, hero), 700, "a fixed level")
end

-- the config switch
do
	local before = T.cfg.enabled
	T.cfg.enabled = false
	ok(not CL.isTrainer(creature({kind = "monster", name = "Another Dummy"})), "off: no trainer")
	T.cfg.enabled = before
end

-- ---------------------------------------------------------------- part 3: the opcode
eq(ChaosOpcodes.trainerMeter, 147, "opcode 147")
do
	local seen = {}
	for name, v in pairs(ChaosOpcodes) do
		ok(seen[v] == nil, "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
		seen[v] = name
	end
	for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 125, 126, 127, 144, 145, 146, 140, 210,
		212, 213, 230, 246}) do
		ok(ChaosOpcodes.trainerMeter ~= v, "not an opcode of the reference server or client: " .. v)
	end
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a")
		f:close()
		return s
	end
	local others = 0
	local p = io.popen('ls data/scripts/chaos/*.lua ../client/overlay/modules/*/*.lua 2>/dev/null')
	for file in p:lines() do
		if not file:find("trainer_meter", 1, true) and not file:find("trainerdps", 1, true)
			and not file:find("chaos_constants", 1, true) then
			local s = readFile(file) or ""
			if s:find("[Oo][Pp][Cc][Oo][Dd][Ee][%w_]*%s*=%s*147%f[%D]") or s:find("xtended[%w]*Opcode%(%s*147%f[%D]") then
				others = others + 1
				io.write("opcode 147 in " .. file .. "\n")
			end
		end
	end
	p:close()
	eq(others, 0, "no other script or module on 147")
	local client = readFile("../client/overlay/modules/game_trainerdps/trainerdps.lua") or ""
	ok(client:find("local OPCODE = 147", 1, true) ~= nil, "the client listens on 147")
end

print("trainer_meter_test: OK (" .. checks .. " checks)")
