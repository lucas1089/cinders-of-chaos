-- luajit tests/intros_test.lua && lua5.3 tests/intros_test.lua (run from server/)
-- The quiet first login and the introductions after it (O761): intros_core.lua rules, the real intros_config.lua against the main
-- quest, then intros.lua on a mocked engine: a first login wants the Daily Reward window only, the quest's first look waits for the
-- login windows, the introductions come later in their order, one per gap, once each; a character from before O761, staff and
-- testers see no change.
local fails, count = 0, 0
local function eq(a, b, what)
	count = count + 1
	if a ~= b then
		error((what or "eq") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function check(c, what)
	count = count + 1
	if not c then
		error(what or "check", 2)
	end
end

-- ---------------------------------------------------------------- the core
dofile("data/scripts/chaos/intros_core.lua")
local M = ChaosIntrosCore
local cfg = M.cfg()
check(type(cfg) == "table", "the config loads")
dofile("data/scripts/chaos/mainquest_core.lua")
local Q = ChaosMainQuestCore
local q = Q.cfg()
local qk = {}
for _, st in ipairs(q.steps) do qk[st.key] = true end
local problems = M.validate(cfg, qk)
eq(#problems, 0, "the config is valid: " .. table.concat(problems, "; "))
eq(q.steps[1].key, "helper", "the quest starts with the Helper")
check(cfg.storage.base == 7103160 and cfg.storage.last == 7103169, "the storage block")

-- every introduction has a step of the quest and a level; the steps come in quest order (the schedule is the order they come)
local lastAfter = 0
for i, it in ipairs(cfg.intros) do
	local at = Q.indexOf(q, it.after)
	check(at and at > lastAfter, "intro " .. it.key .. ": its step comes after the one before")
	lastAfter = at
	check(at > 1, "intro " .. it.key .. ": never before the Helper step is done")
	if it.text then check(it.text.en ~= "" and it.text.pt ~= "", "intro " .. it.key .. " text en / pt") end
end

-- bits
eq(M.has(-1, 1), false); eq(M.set(-1, 1), 1); eq(M.set(1, 3), 5); eq(M.set(5, 3), 5, "set twice"); eq(M.has(5, 3), true); eq(M.has(5, 2), false)

-- first state
eq(M.firstState(cfg, 0, false, false), cfg.states.quiet, "a first login is quiet")
eq(M.firstState(cfg, os.time(), false, false), cfg.states.open, "a character that logged in before is open (no change)")
eq(M.firstState(cfg, 0, true, false), cfg.states.open, "staff: open")
eq(M.firstState(cfg, 0, false, true), cfg.states.open, "a tester: open (the bots' checks see everything)")

-- the login windows of a first login
eq(M.loginWindowWanted(cfg, "daily", true), true, "a first login: the Daily Reward")
eq(M.loginWindowWanted(cfg, "patchnotes", true), false, "a first login: no patch notes")
eq(M.loginWindowWanted(cfg, "patchnotes", false), true, "later logins: every window as before")

-- allowed
local Q_ = cfg.states.quiet
eq(M.allowed(cfg, cfg.states.open, -1, "tips"), true, "open: everything")
eq(M.allowed(cfg, Q_, -1, "tips"), false, "quiet: the tips wait")
eq(M.allowed(cfg, Q_, M.set(0, M.index(cfg, "tips")), "tips"), true, "quiet: given")
eq(M.allowed(cfg, Q_, -1, "no-such"), true, "an unknown key is never held back")

-- the order: what is due along the quest
local function ctxAt(stepKey, level, active)
	return {level = level or 8, questActive = active ~= false, questStep = Q.indexOf(q, stepKey), indexOf = function(k) return Q.indexOf(q, k) end}
end
eq(#M.due(cfg, Q_, -1, ctxAt("helper")), 0, "on the Helper step: nothing")
eq(#M.due(cfg, Q_, -1, ctxAt("warden")), 0, "on the Ysolde step: nothing")
local after = Q.indexOf(q, "warden") + 1
local d = M.due(cfg, Q_, -1, {level = 8, questActive = true, questStep = after, indexOf = function(k) return Q.indexOf(q, k) end})
eq(#d, 1); eq(cfg.intros[d[1]].key, "outfit", "Ysolde met: the outfit first")
local shown = M.set(-1, d[1])
eq(#M.due(cfg, Q_, shown, {level = 8, questActive = true, questStep = after, indexOf = ctxAt("x").indexOf}), 0, "once each")
-- every introduction in the order of the table as the quest moves on
local order, mask = {}, -1
for i = 1, #q.steps do
	local due = M.due(cfg, Q_, mask, {level = 8, questActive = true, questStep = i, indexOf = ctxAt("x").indexOf})
	for _, j in ipairs(due) do
		order[#order + 1] = cfg.intros[j].key
		mask = M.set(mask, j)
	end
end
eq(table.concat(order, ","), "outfit,tips,unlocks,goals", "the schedule along the quest")
-- by level, whichever is first
local lv = M.due(cfg, Q_, -1, ctxAt("helper", 12))
eq(#lv, #cfg.intros, "level 12 on the first step: all due (one per gap at run)")
eq(lv[1], 1, "in their order")
eq(#M.due(cfg, Q_, -1, ctxAt("helper", 10)), 2, "level 10: outfit and tips")
-- the quest not running: at once
eq(#M.due(cfg, Q_, -1, {level = 8, questActive = false}), #cfg.intros, "a skipped quest: due at once")
eq(#M.due(cfg, cfg.states.open, -1, ctxAt("helper", 50)), 0, "open: none (nothing was held)")

-- validate catches mistakes
local bad = {storage = {base = 7100000, state = 0, shown = 1}, intros = {{key = "a", system = "zz", level = 0, after = "nope", text = {en = "x"}}}}
local bp = M.validate(bad, qk)
check(#bp >= 5, "validate: storage, system, level, step, text: " .. #bp)

-- ---------------------------------------------------------------- the engine file on a mocked engine
local timers, sentOps, msgs = {}, {}, {}
function addEvent(fn, ms, ...) timers[#timers + 1] = {fn = fn, ms = ms, args = {...}} end
local function runTimers()
	local list = timers
	timers = {}
	local unpackArgs = unpack or table.unpack
	for _, t in ipairs(list) do t.fn(unpackArgs(t.args)) end
	return #list
end
local events = {}
function CreatureEvent(name)
	local o = {}
	function o:type(t) self.t = t end
	function o:register() events[name] = o end
	return o
end
SKILL_LEVEL = 8
MESSAGE_EVENT_ADVANCE = 19
local testers = {}
Chaos = {isTester = function(p) return testers[p:getId()] == true end}
ChaosOpcodes = {notifications = 200}
json = {encode = function(t) return t end}
local players = {}
function Player(id) return players[id] end
local calls = {}
ChaosFirstHour = {run = function(p) calls[#calls + 1] = "firsthour" end}
ChaosUnlocks = {run = function(p) calls[#calls + 1] = "unlocks" end}
ChaosGoals = {sendTracker = function(p) calls[#calls + 1] = "goals" end}

local function newPlayer(id, level, lastLogin, group)
	local p = {id = id, level = level, store = {}, last = lastLogin or 0, group = group or 1, outfitWindows = 0, said = {}, ops = {}}
	function p:getId() return self.id end
	function p:getLevel() return self.level end
	function p:getStorageValue(k) return self.store[k] or -1 end
	function p:setStorageValue(k, v) self.store[k] = v end
	function p:getLastLoginSaved() return self.last end
	function p:getGroup() local s = self; return {getId = function() return s.group end} end
	function p:sendTextMessage(_, t) self.said[#self.said + 1] = t end
	function p:sendExtendedOpcode(op, d) self.ops[#self.ops + 1] = {op = op, d = d} end
	function p:sendOutfitWindow() self.outfitWindows = self.outfitWindows + 1; calls[#calls + 1] = "outfit" end
	function p:registerEvent() end
	players[id] = p
	return p
end

dofile("data/scripts/chaos/intros.lua")
local I = ChaosIntros
check(events.ChaosIntrosLogin and events.ChaosIntrosAdvance, "events")
local function skey(n) return cfg.storage.base + cfg.storage[n] end
local function qset(p, stepKey, state)
	p.store[q.storage.base + q.storage.state] = state or q.states.active
	p.store[q.storage.base + q.storage.step] = Q.indexOf(q, stepKey)
end

-- a brand-new character: the first login
local p = newPlayer(1, 8, 0)
events.ChaosIntrosLogin.onLogin(p)
eq(#timers, 0, "a first login schedules no introduction")
eq(I.state(p), cfg.states.quiet, "quiet"); eq(p.store[skey("state")], cfg.states.quiet, "stored")
eq(I.firstSession(p), true, "the first session")
eq(I.loginWindowWanted(p, "daily"), true, "the Daily Reward window")
eq(I.loginWindowWanted(p, "patchnotes"), false, "no patch notes window")
for _, k in ipairs({"tips", "unlocks", "goals", "outfit"}) do eq(I.allowed(p, k), false, k .. " waits") end

-- the quest's first look waits for the login windows (the Daily Reward open)
ChaosLoginWindows = {state = {[1] = {current = "daily"}}, starting = {}}
local looked = 0
I.afterLoginWindows(p, function() looked = looked + 1 end)
eq(looked, 0, "the Daily Reward is open: the quest waits")
runTimers(); runTimers()
eq(looked, 0, "still open")
check(timers[1] and timers[1].ms == cfg.wait.pollMs, "polls")
ChaosLoginWindows.state[1] = nil
runTimers()
eq(looked, 1, "the Daily Reward closed: the quest starts")
eq(#timers, 0, "no more polling")
-- the wait has an end
ChaosLoginWindows.state[1] = {current = "daily"}
local late = 0
I.afterLoginWindows(p, function() late = late + 1 end)
for _ = 1, cfg.wait.maxWaitMs / cfg.wait.pollMs + 1 do runTimers() end
eq(late, 1, "after maxWaitMs the quest starts anyway")
ChaosLoginWindows.state[1] = nil
runTimers()

-- no introduction while on the Helper and Ysolde steps
qset(p, "helper")
eq(I.run(p), false, "the Helper step: nothing"); eq(#calls, 0)
qset(p, "warden")
I.onQuestStep(p, "helper")
runTimers()
eq(#calls, 0, "Ysolde's step: nothing")
-- Ysolde met: the outfit window, once, with its line
p.store[q.storage.base + q.storage.step] = Q.indexOf(q, "warden") + 1
I.onQuestStep(p, "warden")
eq(timers[1].ms, 3000, "after the step's own lines")
runTimers()
eq(table.concat(calls, ","), "outfit", "the outfit window"); eq(p.outfitWindows, 1)
check(p.said[#p.said]:find("Customise Character", 1, true), "its line")
eq(I.allowed(p, "outfit"), true)
-- a level up inside the gap brings nothing beside it
p.level = 12
events.ChaosIntrosAdvance.onAdvance(p, SKILL_LEVEL, 11, 12)
eq(#calls, 1, "inside the gap: nothing more")
-- the gap ends: the next, one at a time
eq(timers[1].ms, cfg.pace.gapMs, "the gap")
runTimers()
eq(table.concat(calls, ","), "outfit,firsthour", "then the tips")
runTimers()
eq(table.concat(calls, ","), "outfit,firsthour,unlocks", "then the menu callouts")
runTimers()
eq(table.concat(calls, ","), "outfit,firsthour,unlocks,goals", "then Next Goals")
check(p.said[#p.said]:find("Next Goals", 1, true), "its line")
runTimers(); runTimers()
eq(#calls, 4, "once each: nothing more")
eq(p.outfitWindows, 1, "the outfit window once")
for _, k in ipairs({"tips", "unlocks", "goals", "outfit"}) do eq(I.allowed(p, k), true, k .. " given") end

-- the next login of a quiet character: every login window, the introductions due after them
local r = newPlayer(2, 8, 0)
events.ChaosIntrosLogin.onLogin(r)
eq(I.state(r), cfg.states.quiet)
r.last = os.time()
eq(I.firstSession(r), false, "a later login")
eq(I.loginWindowWanted(r, "patchnotes"), true, "its windows as before")
qset(r, "helper", q.states.skipped)
calls = {}
events.ChaosIntrosLogin.onLogin(r)
eq(timers[1].ms, 4000, "after the login")
runTimers()
eq(timers[1].ms, cfg.loginDelayMs, "after the login windows")
runTimers()
eq(table.concat(calls, ","), "outfit", "a skipped quest: the introductions come, one at a time")
runTimers()
eq(table.concat(calls, ","), "outfit,firsthour")
timers = {}

-- a character from before O761: open, nothing held, nothing given
calls = {}
local old = newPlayer(3, 40, os.time())
events.ChaosIntrosLogin.onLogin(old)
eq(I.state(old), cfg.states.open, "open")
eq(#timers, 0, "no introduction run")
for _, k in ipairs({"tips", "unlocks", "goals"}) do eq(I.allowed(old, k), true, k .. " as before") end
eq(I.firstSession(old), false); eq(I.loginWindowWanted(old, "patchnotes"), true)
eq(I.run(old), false); eq(#calls, 0, "nothing given to an open character")
-- staff and testers on a first login: open
local staff = newPlayer(4, 8, 0, 5)
eq(I.state(staff), cfg.states.open, "staff: open")
local bot = newPlayer(5, 8, 0)
testers[5] = true
eq(I.state(bot), cfg.states.open, "a tester: open")
-- a tester never waits for the login windows
ChaosLoginWindows.state[5] = {current = "daily"}
local bl = 0
I.afterLoginWindows(bot, function() bl = bl + 1 end)
eq(bl, 1, "a tester: at once")

-- the systems ask before they show: the hooks are in place
local function src(f) return io.open("data/scripts/chaos/" .. f):read("*a") end
check(src("firsthour.lua"):find('ChaosIntros.allowed(player, "tips")', 1, true), "firsthour.lua asks")
check(src("unlocks.lua"):find('ChaosIntros.allowed(player, "unlocks")', 1, true), "unlocks.lua asks")
check(src("goals.lua"):find('ChaosIntros.allowed(player, "goals")', 1, true), "goals.lua asks")
check(src("daily.lua"):find("I.loginWindowWanted(p, e.key)", 1, true), "daily.lua filters the login windows")
check(src("newplayer.lua"):find("ChaosIntros.firstSession(player)", 1, true), "newplayer.lua keeps the welcome toast and the Helper back")
check(src("mainquest.lua"):find("I.afterLoginWindows(p, look)", 1, true), "mainquest.lua starts after the login windows")
check(src("mainquest.lua"):find("ChaosIntros.onQuestStep", 1, true), "mainquest.lua reports the steps")

print(string.format("intros_test: %d checks ok", count))
