-- Run from the server/ folder: luajit tests/botreview_test.lua [-v] (or lua5.3; CI runs both)
-- Bot review (botreview_core.lua, botreview.lua): each new signal on small traces, the score rules, the day, the random
-- presence check, the synchrony check, SQL builders, synthetic day traces of humans, helper users and bots (the daily
-- scores must separate them), and botreview.lua with antibot.lua and reports.lua against a mocked engine (wrapped hooks,
-- kill / combat / look / item move / chat, presence check results, day rows, staff marks, website check requests, purge,
-- /botreview, admin panel, never a kick). -v prints the separation table.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
local acfg = dofile("data/scripts/chaos/antibot_config.lua")
local cfg = dofile("data/scripts/chaos/botreview_config.lua")
dofile("data/scripts/chaos/antibot_core.lua")
dofile("data/scripts/chaos/botreview_core.lua")
local K, BR = ChaosAntibotCore, ChaosBotReviewCore

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, eps, label)
	check(math.abs(a - b) <= eps, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local verbose = arg and arg[1] == "-v"

local function prng(seed)
	local s = seed % 2147483647
	if s <= 0 then s = s + 2147483646 end
	local rnd = {}
	function rnd.u() s = (s * 16807) % 2147483647; return s / 2147483647 end
	function rnd.int(a, b) return a + math.floor(rnd.u() * (b - a + 1)) end
	function rnd.normal(mean, sd)
		local u1, u2 = math.max(rnd.u(), 1e-12), rnd.u()
		return mean + sd * math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
	end
	function rnd.exp(mean) return -mean * math.log(math.max(rnd.u(), 1e-12)) end
	function rnd.poisson(mean)
		local L, k, p = math.exp(-mean), 0, 1
		repeat k = k + 1; p = p * rnd.u() until p <= L
		return k - 1
	end
	return rnd
end

-- ---------------------------------------------------------------- config sanity
check(cfg.flagAt > cfg.storeAt and cfg.storeAt > 0, "storeAt < flagAt")
check(cfg.retention.days >= 30 and cfg.retention.escalatedDays >= cfg.retention.days, "retention 30 days, escalated longer")
eq(cfg.tables.daily, "chaos_bot_daily", "daily table name")
eq(cfg.tables.actions, "chaos_bot_actions", "actions table name")
for _, k in ipairs(BR.AUTOMATION) do check(cfg.automation[k], "automation weight " .. k) end
for _, k in ipairs(BR.UNATTENDED) do check(cfg.unattended[k], "unattended weight " .. k) end
eq(acfg.check.failAction, "log", "the presence check never moves or kicks by default")

-- ---------------------------------------------------------------- helpers
near(BR.ramp(0.35, 0.35, 0.12), 0, 1e-9, "ramp from")
near(BR.ramp(0.12, 0.35, 0.12), 1, 1e-9, "ramp to")
near(BR.noisyOr({a = 1, b = 0.5}, {a = 0.5, b = 0.5}, {"a", "b"}), 1 - 0.5 * 0.75, 1e-9, "noisy-or")
near(BR.robustCv({100, 100, 100, 100}), 0, 1e-9, "robust cv flat")
near(BR.jaccard({a = true, b = true}, {b = true, c = true}), 1 / 3, 1e-9, "jaccard")

-- ---------------------------------------------------------------- heal threshold
do
	local st = BR.newState(cfg, 0)
	check(BR.onHeal(st, cfg, 1000, 60) == nil, "a heal without a hit is no sample")
	BR.onHit(st, cfg, 2000, 75)
	check(BR.onHeal(st, cfg, 2100, 97) == nil, "a top-up at 97% is no sample")
	local s = BR.onHeal(st, cfg, 2200, 66)
	check(s and s[1] == 66 and s[2] == 75, "sample [HP now, HP before the hit]")
	BR.onHit(st, cfg, 5000, 80)
	check(BR.onHeal(st, cfg, 6000, 70) == nil, "a hit older than lookbackMs is not used")
	-- a threshold healer at 70%: every interval holds 70
	local th = BR.newState(cfg, 0)
	local rnd = prng(5)
	for i = 1, 30 do
		local before = 70 + rnd.int(1, 9)
		local now = before - rnd.int(5, 12)
		if now > 70 then now = 70 end
		BR.onHit(th, cfg, i * 10000, before)
		BR.onHeal(th, cfg, i * 10000 + 80, now)
	end
	local v, info = BR.healSignal(th, cfg)
	eq(v, 1, "threshold healer: heal signal 1")
	eq(info.pct, 70, "the threshold found")
	-- a human: heals at a fuzzy level after a delay
	local hu = BR.newState(cfg, 0)
	for i = 1, 30 do
		local thr = rnd.normal(55, 13)
		local before = thr + rnd.int(1, 10)
		local now = before - rnd.int(4, 10) - (rnd.u() < 0.3 and rnd.int(4, 10) or 0)
		BR.onHit(hu, cfg, i * 10000, math.floor(before))
		BR.onHeal(hu, cfg, i * 10000 + 450, math.floor(now))
	end
	local hv, hinfo = BR.healSignal(hu, cfg)
	check(hv < 0.3, "human heals: low heal signal (" .. hv .. ", share " .. hinfo.share .. ")")
	local few = BR.newState(cfg, 0)
	BR.onHit(few, cfg, 1, 80); BR.onHeal(few, cfg, 2, 60)
	eq(BR.healSignal(few, cfg), 0, "too few heals say nothing")
end

-- ---------------------------------------------------------------- retarget
do
	local st = BR.newState(cfg, 0)
	eq(BR.onCombat(st, cfg, 100, 5), nil, "combat without a kill: no sample")
	BR.onKill(st, 1000)
	eq(BR.onCombat(st, cfg, 1300, 5), nil, "the same target again: no sample")
	BR.onKill(st, 2000)
	eq(BR.onCombat(st, cfg, 2250, 6), 250, "kill -> new target: latency")
	eq(BR.onCombat(st, cfg, 2300, 7), nil, "one sample per kill")
	BR.onKill(st, 10000)
	eq(BR.onCombat(st, cfg, 20000, 8), nil, "outside the window: no sample")
	local bot, hum = BR.newState(cfg, 0), BR.newState(cfg, 0)
	local rnd = prng(9)
	for i = 1, 32 do
		BR.onKill(bot, i * 10000); BR.onCombat(bot, cfg, i * 10000 + 200 + rnd.int(-10, 10), i)
		BR.onKill(hum, i * 10000); BR.onCombat(hum, cfg, i * 10000 + math.floor(math.max(250, rnd.normal(800, 350))), i)
	end
	eq(BR.retargetSignal(bot, cfg), 1, "fixed retarget: 1")
	check(BR.retargetSignal(hum, cfg) < 0.2, "human retarget: low")
end

-- ---------------------------------------------------------------- silence and activity
do
	local st = BR.newState(cfg, 0)
	for m = 0, 4 * 60 - 1 do
		BR.onAction(st, cfg, m * 60000, m * 60)
	end
	local v, info = BR.silenceSignal(st, cfg, 4 * 3600)
	near(info.hours, 4, 0.05, "four active hours")
	eq(v, 1, "no noise in 4 active hours: 1")
	for i = 1, 30 do BR.noise(st, cfg, "look", 3600 + i * 60) end
	local v2 = BR.silenceSignal(st, cfg, 4 * 3600)
	check(v2 < 0.1, "looks are noise (" .. v2 .. ")")
	local p = BR.newState(cfg, 0)
	BR.onAction(p, cfg, 0, 0)
	BR.onAction(p, cfg, 200000, 200)
	eq(BR.hourSlot(p, 200).idle, 1, "a 200 s pause counts")
	local q = BR.newState(cfg, 0)
	BR.onAction(q, cfg, 0, 0)
	BR.onAction(q, cfg, 2000000, 2000)
	eq(BR.hourSlot(q, 2000).idle, 0, "a 30 min break is no pause (nonstop's break)")
	local short = BR.newState(cfg, 0)
	BR.onAction(short, cfg, 0, 0)
	eq(BR.silenceSignal(short, cfg, 600), 0, "under minActiveHours: nothing")
end

-- ---------------------------------------------------------------- route
do
	local function walk(st, hours, jitter, rnd)
		local t = 0
		for h = 0, hours - 1 do
			for lap = 1, 6 do
				for i = 0, 39 do
					local a = i / 40 * 2 * math.pi
					local x = 1000 + math.floor(math.cos(a) * 60) + (jitter and rnd.int(-jitter, jitter) or 0)
					local y = 1000 + math.floor(math.sin(a) * 60) + (jitter and rnd.int(-jitter, jitter) or 0)
					t = h * 3600 + (lap - 1) * 500 + i * 12
					BR.onPosition(st, cfg, x, y, 7, t, false)
				end
			end
		end
		return t
	end
	local st = BR.newState(cfg, 0)
	local t = walk(st, 8)
	local v, info = BR.routeSignal(st, cfg, t)
	eq(v, 1, "the same circle for 8 hours: route 1")
	check(info.hours >= 6 and info.sim > 0.9, "route hours and similarity")
	local hum = BR.newState(cfg, 0)
	local rnd = prng(3)
	local t2 = 0
	for h = 0, 7 do
		local cx, cy = 1000 + rnd.int(-80, 80), 1000 + rnd.int(-80, 80)
		local x, y = cx, cy
		for i = 1, 300 do
			x, y = x + rnd.int(-3, 3), y + rnd.int(-3, 3)
			t2 = h * 3600 + i * 10
			BR.onPosition(hum, cfg, x, y, 7, t2, false)
		end
	end
	check(BR.routeSignal(hum, cfg, t2) < 0.01, "wandering: no route signal")
	local f = BR.newState(cfg, 0)
	check(not BR.onPosition(f, cfg, 0, 0, 7, 1, true) and not BR.onPosition(f, cfg, 40, 0, 7, 2, true), "fighting: no key")
	eq(f.route[0], nil, "nothing stored while fighting")
end

-- ---------------------------------------------------------------- presence
do
	local st = BR.newState(cfg, 0)
	eq(BR.presenceSignal(st, cfg, 100), 0, "no check: 0")
	BR.onCheck(st, 1000, "fail", true)
	eq(BR.presenceSignal(st, cfg, 2000), cfg.presence.ignoredActive, "missed while acting")
	eq(BR.presenceSignal(st, cfg, 1000 + 25 * 3600), 0, "after the window: 0")
	local idle = BR.newState(cfg, 0)
	BR.onCheck(idle, 1000, "fail", false)
	eq(BR.presenceSignal(idle, cfg, 2000), cfg.presence.ignoredIdle, "missed while idle: weaker")
	local ok = BR.newState(cfg, 0)
	BR.onCheck(ok, 1000, "pass", false)
	local v, info = BR.presenceSignal(ok, cfg, 2000)
	check(v == 0 and info.passedRecently, "passed: 0 and remembered")
	for i = 1, 12 do BR.onCheck(ok, i, "pass", false) end
	eq(#ok.checks, 8, "checks bounded")
end

-- ---------------------------------------------------------------- synchrony
do
	local rnd = prng(11)
	local a, b, h1, h2, i1, i2 = {}, {}, {}, {}, {}, {}
	local t = 0
	for i = 1, 64 do
		t = t + rnd.int(800, 2500)
		a[i] = t
		b[i] = t + rnd.int(5, 60) -- a controller acting for both
	end
	local u, w = 0, 0
	for i = 1, 64 do
		u = u + 1000 + rnd.int(0, 60) -- one person, two clients with the helper: each casts when ready
		w = w + 1000 + rnd.int(0, 60)
		h1[i], h2[i] = u, w + 333
		i1[i] = i * 1500 + rnd.int(0, 1400)
		i2[i] = i * 1700 + rnd.int(0, 1600)
	end
	local s = BR.pairSync(a, b, cfg)
	check(s and s > 0.8, "lockstep pair: high synchrony (" .. tostring(s) .. ")")
	local hs = BR.pairSync(h1, h2, cfg)
	check(hs and hs < 0.25, "one human on two helper clients: low (" .. tostring(hs) .. ")")
	local is = BR.pairSync(i1, i2, cfg)
	check(is and is < 0.25, "two independent players: low (" .. tostring(is) .. ")")
	eq(BR.pairSync({1, 2}, b, cfg), nil, "too few actions: nothing")
	local states = {[1] = BR.newState(cfg, 0), [2] = BR.newState(cfg, 0), [3] = BR.newState(cfg, 0)}
	local pairsN = BR.clusterPass({{kind = "ip", {guid = 1, name = "A", acts = a}, {guid = 2, name = "B", acts = b}},
		{kind = "party", {guid = 3, name = "C", acts = i1}, {guid = 1, name = "A", acts = i2}}}, states, cfg)
	eq(pairsN, 2, "pairs compared")
	eq(states[2].clusterWith, "A", "partner named")
	eq(states[2].clusterKind, "ip", "kind kept")
	eq(BR.clusterSignal(states[2], cfg), 1, "lockstep: cluster 1")
	check(BR.clusterSignal(states[3], cfg) < 0.1, "independent: cluster low")
end

-- ---------------------------------------------------------------- score rules
do
	local z = {timing = 0, reaction = 0, loot = 0, heal = 0, retarget = 0, nonstop = 0, silence = 0, route = 0, loop = 0,
		presence = 0, cluster = 0}
	local function with(t)
		local s = {}
		for k, v in pairs(z) do s[k] = v end
		for k, v in pairs(t) do s[k] = v end
		return s
	end
	local helper = BR.combine(with({timing = 1, reaction = 1, heal = 1, retarget = 1, loot = 1}), cfg)
	eq(helper, 0, "automation alone (the helper) scores 0")
	local oneU = BR.combine(with({nonstop = 1, heal = 1, retarget = 1, reaction = 1}), cfg)
	check(oneU < cfg.flagAt, "one unattended signal even with full automation stays under flagAt (" .. oneU .. ")")
	local silentHuman = BR.combine(with({silence = 1, route = 0.6}), cfg)
	check(silentHuman < cfg.flagAt, "silent human with a route, no automation: under flagAt (" .. silentHuman .. ")")
	local bot = BR.combine(with({nonstop = 1, silence = 1, route = 1, heal = 1, retarget = 1}), cfg)
	check(bot >= 80, "bot: high (" .. bot .. ")")
	local unattendedOnly = BR.combine(with({nonstop = 1, silence = 1, route = 1}), cfg)
	check(unattendedOnly >= cfg.storeAt, "unattended without automation signs is stored for review (" .. unattendedOnly .. ")")
	local missed = BR.combine(with({nonstop = 1, silence = 1, presence = 1}), cfg)
	check(missed >= cfg.flagAt, "unattended and a missed check flags without automation signs (" .. missed .. ")")
	local passed = BR.combine(with({nonstop = 1, silence = 1}), cfg, {presence = {passedRecently = true}})
	local notPassed = BR.combine(with({nonstop = 1, silence = 1}), cfg, {presence = {}})
	check(passed < notPassed, "a passed check lowers the score")
	local ex = BR.explain(with({heal = 1, retarget = 0.9}), {heal = {share = 0.97, n = 40, pct = 70}, retarget = {median = 230, cv = 0.05, n = 30}}, cfg, 0.9, 0.1)
	check(ex[1]:find("heal 1.00: 97% of 40 heals fit one HP threshold (70%)", 1, true), "explanation of heal")
	check(ex[#ex]:find("allowed client helper", 1, true), "helper note when automation comes without unattended signs")
end

-- ---------------------------------------------------------------- the day
do
	local st = BR.newState(cfg, 0)
	st.signals, st.explain = {heal = 1}, {"x"}
	for h = 0, 3 do
		for i = 1, 12 do BR.addPoint(st, cfg, 20261014, h, h == 2 and 90 or 40) end
	end
	near(BR.dayScore(st.day, cfg), 40, 1e-9, "one odd hour does not make the day (second highest)")
	for i = 1, 12 do BR.addPoint(st, cfg, 20261014, 5, 80) end
	near(BR.dayScore(st.day, cfg), 80, 1e-9, "two high hours do")
	eq(BR.timeline(st.day), "0=40,1=40,2=90,3=40,5=80", "timeline")
	local one = BR.newState(cfg, 0)
	for i = 1, 12 do BR.addPoint(one, cfg, 1, 3, 100) end
	near(BR.dayScore(one.day, cfg), 50, 1e-9, "a day with one hour: half")
	for i = 1, 3 do BR.addPoint(one, cfg, 1, 4, 100) end
	near(BR.dayScore(one.day, cfg), 50, 1e-9, "an hour with too few evaluations does not count")
	local fin = BR.addPoint(one, cfg, 2, 0, 10)
	check(fin and fin.key == 1 and one.day.key == 2, "day change returns the finished day")
	-- write rules
	local w = BR.newState(cfg, 0)
	for i = 1, 12 do BR.addPoint(w, cfg, 1, 0, 10) end
	eq((BR.writeDue(w, cfg, 100)), false, "under storeAt: not written")
	for h = 1, 2 do for i = 1, 12 do BR.addPoint(w, cfg, 1, h, 60) end end
	local due, sc, newly = BR.writeDue(w, cfg, 101)
	check(due and newly and sc >= cfg.flagAt, "flagged: written at once, newly flagged")
	eq((BR.writeDue(w, cfg, 101)), false, "then once per hour")
	local due2, _, newly2 = BR.writeDue(w, cfg, 102)
	check(due2 and not newly2, "next hour: written again, not newly flagged")
	local row = BR.rowOf(w, cfg, w.day, 7, 8, "Name", 5000)
	check(row.flagged and row.day == 1 and row.timeline == "0=10,1=60,2=60", "row")
	local q = BR.upsertSql(cfg, row, function(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end)
	check(q:find("INSERT INTO `chaos_bot_daily`", 1, true) and q:find("ON DUPLICATE KEY UPDATE", 1, true), "upsert")
	check(q:find("`status` = IF(`status` = 'none' AND VALUES(`flagged`) = 1, 'new', `status`)", 1, true),
		"a staff status is never overwritten by the server")
	local bad = BR.upsertSql(cfg, {player_id = 1, player_name = "O'Brien", day = 1, score = 1, peak = 1, reasons = "a'b", now = 1},
		function(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end)
	check(bad:find("'O''Brien'", 1, true) and bad:find("'a''b'", 1, true), "strings escaped")
	local purge = BR.purgeSql(cfg, 100 * 86400, function(d) return 20260000 + 100 - d end)
	eq(#purge, 3, "three purge queries")
	check(purge[1]:find("`day` < 20260070", 1, true) and purge[1]:find("<> 'escalated'", 1, true), "30 days, not escalated")
	check(purge[2]:find("`day` < 20260010", 1, true), "escalated: 90 days")
	check(purge[3]:find("`created_at` < " .. (100 - 90) * 86400, 1, true), "actions: 90 days")
end

-- ---------------------------------------------------------------- random presence checks
do
	local st = BR.newState(cfg, 0)
	local ac = acfg.check
	local now = 100000
	eq(BR.randomCheckDue(st, cfg, now, 1, {}, ac, 1, 0), false, "not before afterHours of streak")
	eq(BR.randomCheckDue(st, cfg, now, 3, {active = {}}, ac, 1, 0), false, "not while a check runs")
	eq(BR.randomCheckDue(st, cfg, now, 3, {graceUntil = now + 10}, ac, 1, 0), false, "not in the grace after a pass")
	eq(BR.randomCheckDue(st, cfg, now, 3, {day = 1, dayCount = ac.maxPerDay}, ac, 1, 0), false, "not over the daily limit")
	eq(BR.randomCheckDue(st, cfg, now, 3, {}, ac, 1, 0.99), false, "rare")
	eq(BR.randomCheckDue(st, cfg, now, 3, {}, ac, 1, 0), true, "due")
	eq(BR.randomCheckDue(st, cfg, now + 3600, 3, {}, ac, 1, 0), false, "never two within minGapHours")
	-- the rate: about one per everyActiveHours of active play
	local rnd = prng(77)
	local s2, fired = BR.newState(cfg, 0), 0
	for t = 0, 200 * 3600, cfg.evalSeconds do
		if BR.randomCheckDue(s2, cfg, t, 5, {lastAt = t - 5 * 3600}, ac, -1, rnd.u()) then fired = fired + 1 end
	end
	check(fired >= 5 and fired <= 12, "about one random check per 8 active hours, gap 20 h (" .. fired .. " in 200 h)")
end

-- ---------------------------------------------------------------- synthetic days
-- A character over a day: sessions with breaks, walking a ring of rooms, fights (hits, heals, attack spells, kills and
-- retargets), loot, human noise (chat, looks, turns, item moves, pauses), maybe one presence check. Both cores are fed
-- as the engine would: antibot every 60 s, bot review every 300 s.
local KINDS = {
	human = {sessions = {2, 3.0}, chat = 5, look = 10, turn = 4, inv = 5, pauses = 1.5, heal = "human", cast = "human", retarget = "human", move = "human", loot = 0.3},
	silenthuman = {sessions = {2, 3.5}, chat = 0, look = 3, turn = 2, inv = 2, pauses = 1, heal = "human", cast = "human", retarget = "human", move = "human", loot = 0.3},
	routehuman = {sessions = {2, 3.0}, chat = 2, look = 6, turn = 3, inv = 3, pauses = 1, heal = "human", cast = "human", retarget = "human", move = "ring", loot = 0.3},
	helper = {sessions = {3, 3.0}, chat = 4, look = 8, turn = 3, inv = 4, pauses = 1.5, heal = "helper", cast = "helper", retarget = "helper", move = "human", loot = 0},
	helpergrinder = {sessions = {4, 3.3}, breakMin = 25, chat = 0.3, look = 3, turn = 1.5, inv = 2, pauses = 1, heal = "helper", cast = "helper", retarget = "helper", move = "human", loot = 0},
	quiethelper = {sessions = {4, 3.5}, breakMin = 18, chat = 0, look = 1, turn = 1, inv = 1, pauses = 0.7, heal = "helper", cast = "helper", retarget = "helper", move = "human", loot = 0},
	helperroute = {sessions = {3, 3.5}, chat = 0, look = 2, turn = 1, inv = 2, pauses = 1, heal = "helper", cast = "helper", retarget = "helper", move = "ring", loot = 0},
	helperafk = {sessions = {1, 11}, chat = 0, look = 0, turn = 0, inv = 0, pauses = 0, heal = "helper", cast = "helper", retarget = "helper", move = "stand", loot = 0},
	bot = {sessions = {1, 23.5}, chat = 0, look = 0, turn = 0, inv = 0, pauses = 0, heal = "bot", cast = "bot", retarget = "bot", move = "ring", loot = 1},
	baglessbot = {sessions = {1, 16}, chat = 0, look = 0, turn = 0, inv = 0, pauses = 0, heal = "bot", cast = "helper", retarget = "bot", move = "ring", loot = 0},
	carefulbot = {sessions = {1, 20}, chat = 1, look = 0.5, turn = 0, inv = 0, pauses = 1, heal = "careful", cast = "careful", retarget = "careful", move = "ringjitter", loot = 1}
}
local HUMAN = {quiethelper = true, human = true, silenthuman = true, routehuman = true, helper = true, helpergrinder = true, helperroute = true}

local function simulate(kind, seed)
	local p = KINDS[kind]
	local rnd = prng(seed)
	local ast = K.newState(acfg, 0)
	local st = BR.newState(cfg, 0)
	ast.guid = 1
	st.lastRandomCheck, ast.check.lastAt = -1e9, -1e9 -- the simulated clock starts at 0
	local ping = (kind:find("bot") and rnd.normal(45, 8)) or rnd.normal(70, 20)
	-- sessions spread over the day
	local sessions = {}
	local t = rnd.int(0, 2) * 3600000
	for i = 1, p.sessions[1] do
		local len = math.max(1800000, rnd.normal(p.sessions[2] * 3600000, p.sessions[1] > 1 and 1200000 or 0))
		sessions[#sessions + 1] = {t, math.min(24 * 3600000 - 1, t + len)}
		t = t + len + (p.breakMin and rnd.normal(p.breakMin * 60000, 5 * 60000) or rnd.normal(90 * 60000, 30 * 60000))
		if t >= 24 * 3600000 then break end
	end
	local rooms = {}
	for i = 0, 15 do
		local a = i / 16 * 2 * math.pi
		rooms[#rooms + 1] = {x = 1000 + math.floor(math.cos(a) * 60), y = 1000 + math.floor(math.sin(a) * 60)}
	end
	local hp, tid = 100, 1
	local lastHeal = -1e9
	-- antibot.lua evaluates every 60 s; only its signals are used here, so it runs right before each bot review
	local nextAEval, nextBEval = 299000, 300000
	local checkAt = nil
	local checks = 0
	local maxScore, flaggedAt = 0, nil
	local function evals(now)
		while now >= nextAEval do
			K.evaluate(ast, acfg, math.floor(nextAEval / 1000))
			nextAEval = nextAEval + 300000
		end
		while now >= nextBEval do
			local s = math.floor(nextBEval / 1000)
			local online = false
			for _, ses in ipairs(sessions) do if nextBEval >= ses[1] and nextBEval <= ses[2] then online = true end end
			if online then
				-- the random presence check, as botreview.lua decides it (antibot.lua sends it a moment later)
				if not checkAt and BR.randomCheckDue(st, cfg, s, ast.info and ast.info.nonstop and ast.info.nonstop.streak or 0,
						ast.check, acfg.check, 1, rnd.u()) then
					checkAt = nextBEval + 30000
				end
				local score = BR.evaluate(st, cfg, ast.signals, s, ast.info)
				BR.addPoint(st, cfg, 1, math.floor(s / 3600) % 24, score)
				if score > maxScore then maxScore = score end
			end
			nextBEval = nextBEval + 300000
		end
	end
	local function act(ms, kind2, bound)
		local s = math.floor(ms / 1000)
		K.onAction(ast, acfg, ms, s, kind2, bound)
		BR.onAction(st, cfg, ms, s)
	end
	local function hit(ms)
		local before = hp
		hp = math.max(1, hp - rnd.int(4, 10))
		K.onDamage(ast, acfg, ms)
		BR.onHit(st, cfg, ms, before)
	end
	local function heal(ms)
		local s = math.floor(ms / 1000)
		BR.onHeal(st, cfg, ms, hp, s)
		K.onSelfHeal(ast, acfg, ms, s)
		BR.onAction(st, cfg, ms, s)
		hp = math.min(100, hp + rnd.int(25, 35))
		lastHeal = ms
	end
	-- a heal decision after a hit
	local humanThr = rnd.normal(55, 8)
	local function maybeHeal(ms)
		if ms - lastHeal < 1000 then return end
		if p.heal == "helper" then
			if hp <= 70 then heal(ms + ping + rnd.int(0, 50)) end
		elseif p.heal == "bot" then
			if hp <= 65 then heal(ms + ping + rnd.int(5, 25)) end
		elseif p.heal == "careful" then
			if hp <= rnd.int(48, 72) then heal(ms + ping + rnd.int(60, 400)) end
		else
			if hp <= rnd.normal(humanThr, 12) then heal(ms + ping + math.max(150, rnd.normal(420, 140))) end
		end
	end
	local function retargetDelay()
		if p.retarget == "helper" then return ping + rnd.int(0, 50) + 20
		elseif p.retarget == "bot" then return ping + 150 + rnd.int(-10, 10)
		elseif p.retarget == "careful" then return ping + rnd.int(120, 700) end
		return ping + math.max(200, rnd.normal(750, 320))
	end
	local function castGap()
		if p.cast == "bot" then return 1500 + rnd.int(-15, 15), false
		elseif p.cast == "careful" then return 1500 + rnd.int(-450, 450), false
		elseif p.cast == "helper" then return 1000 + rnd.int(0, 50), true end
		return math.max(350, rnd.normal(1900, 650)), false
	end
	-- one fight: monsters killed one after another
	local function fight(t0, t1)
		local tt = t0
		local nextHit = tt + rnd.exp(1500)
		while tt < t1 do
			local killAt = tt + math.max(2000, rnd.normal(6000, 2000))
			local nextCast = tt + rnd.int(100, 900)
			while nextCast < killAt or nextHit < killAt do
				if nextHit <= nextCast then
					hit(nextHit); maybeHeal(nextHit)
					nextHit = nextHit + rnd.exp(1500)
				else
					local gap, bound = castGap()
					act(nextCast, "attack", bound)
					nextCast = nextCast + gap
				end
			end
			BR.onKill(st, killAt)
			if p.loot > 0 and rnd.u() < p.loot then
				local lt = killAt + (p.loot == 1 and 300 or rnd.int(500, 2500))
				for i = 1, rnd.int(1, 3) do
					K.onLootMove(ast, acfg, lt, math.floor(lt / 1000))
					BR.activity(st, cfg, math.floor(lt / 1000))
					lt = lt + ((p.heal == "bot") and (300 + rnd.int(-12, 12)) or (p.heal == "careful" and 300 + rnd.int(-150, 150)) or math.max(150, rnd.normal(750, 300)))
				end
			end
			tid = tid + 1
			local nt = killAt + retargetDelay()
			BR.onCombat(st, cfg, nt, tid)
			act(nt, "start", false)
			tt = nt
		end
		return tt
	end
	for _, ses in ipairs(sessions) do
		local t0, t1 = ses[1], ses[2]
		local tt = t0
		local room = rnd.int(1, #rooms)
		local x, y = rooms[room].x, rooms[room].y
		local target, dir, detour = room % #rooms + 1, 1, {x = 0, y = 0}
		local hourNoise = -1
		local pending = {} -- noise of this hour, in time order (the engine's clock never goes back)
		local nextPause = tt + rnd.exp(3600000 / math.max(0.01, p.pauses))
		while tt < t1 do
			evals(tt)
			-- the noise of this hour, spread over it
			local hourNow = math.floor(tt / 3600000)
			if hourNow ~= hourNoise then
				hourNoise = hourNow
				for _, k in ipairs({"chat", "look", "turn", "inv"}) do
					for i = 1, rnd.poisson(p[k] or 0) do
						pending[#pending + 1] = {at = tt + rnd.int(0, 3599) * 1000, k = k}
					end
				end
				table.sort(pending, function(x, y) return x.at > y.at end)
			end
			while pending[#pending] and pending[#pending].at <= tt do
				local e = table.remove(pending)
				BR.noise(st, cfg, e.k, math.floor(e.at / 1000))
			end
			if checkAt and tt >= checkAt then
				local s = math.floor(tt / 1000)
				if HUMAN[kind] then
					BR.onCheck(st, s, "pass", false)
					K.finish(ast, acfg, "pass", s)
				else
					BR.onCheck(st, s + 80, "fail", true)
					K.finish(ast, acfg, "fail", s + 80)
				end
				ast.check.lastAt = s
				checks = checks + 1
				checkAt = nil
			end
			if p.pauses > 0 and tt >= nextPause then
				tt = tt + rnd.int(150, 600) * 1000 -- a short pause: nothing at all
				nextPause = tt + rnd.exp(3600000 / p.pauses)
			elseif p.move == "stand" then
				-- the helper left running on one spot: monsters come to it
				K.onPosition(ast, acfg, x, y, 7, math.floor(tt / 1000), tt)
				BR.onPosition(st, cfg, x, y, 7, math.floor(tt / 1000), true)
				if rnd.u() < 0.3 then tt = fight(tt, tt + rnd.int(5, 20) * 1000) end
				tt = tt + 2000
			else
				local goal = rooms[target]
				local gx, gy = goal.x + detour.x, goal.y + detour.y
				local dx, dy = gx - x, gy - y
				local dist = math.sqrt(dx * dx + dy * dy)
				local step = kind:find("bot") and 8 or rnd.normal(7.5, 1.5)
				if dist > step then
					x, y = x + dx / dist * step, y + dy / dist * step
				else
					x, y = gx, gy
				end
				local s = math.floor(tt / 1000)
				local fighting = (ast.lastDamage and tt - ast.lastDamage < acfg.loop.fightMs) or (ast.lastAction and tt - ast.lastAction < acfg.loop.fightMs)
				K.onPosition(ast, acfg, math.floor(x + 0.5), math.floor(y + 0.5), 7, s, tt)
				BR.onPosition(st, cfg, math.floor(x + 0.5), math.floor(y + 0.5), 7, s, fighting and true or false)
				tt = tt + 2000
				if dist <= step then
					if rnd.u() < 0.5 then
						local fe = math.min(t1, tt + rnd.int(10, 40) * 1000)
						tt = math.max(tt, fight(tt, fe)) + 1000
					end
					if p.move == "ring" then
						target = target % #rooms + 1
					elseif p.move == "ringjitter" then
						target = target % #rooms + 1
						detour = {x = rnd.int(-3, 3), y = rnd.int(-3, 3)}
					else
						if rnd.u() < 0.2 then dir = -dir end
						local skip = rnd.u() < 0.15 and 2 or 1
						target = ((target - 1 + dir * skip) % #rooms) + 1
						detour = {x = rnd.int(-10, 10), y = rnd.int(-10, 10)}
					end
				end
			end
		end
	end
	evals(24 * 3600000)
	return {day = BR.dayScore(st.day, cfg), max = maxScore, st = st, checks = checks}
end

local results = {}
local function run(kind, seeds)
	local flagged, stored, maxDay, sum, minDay, worst, best = 0, 0, 0, 0, 1e9, nil, nil
	local checked, checkedFlagged = 0, 0
	for seed = 1, seeds do
		local r = simulate(kind, seed * 7919 + #kind * 31)
		if r.day >= cfg.flagAt then flagged = flagged + 1 end
		if r.checks > 0 then
			checked = checked + 1
			if r.day >= cfg.flagAt then checkedFlagged = checkedFlagged + 1 end
		end
		if r.day >= cfg.storeAt then stored = stored + 1 end
		if r.day >= maxDay then maxDay, worst = r.day, r end
		if r.day <= minDay then minDay, best = r.day, r end
		sum = sum + r.day
	end
	local res = {kind = kind, seeds = seeds, flagged = flagged, stored = stored, maxDay = maxDay, minDay = minDay,
		mean = sum / seeds, worst = worst, best = best, checked = checked, checkedFlagged = checkedFlagged}
	results[#results + 1] = res
	if verbose then
		print(string.format("%-14s %2d days  flagged %2d  stored %2d  day score min %5.1f  mean %5.1f  max %5.1f  random checks in %d days",
			kind, seeds, flagged, stored, minDay, res.mean, maxDay, checked))
		local w = HUMAN[kind] and worst or best
		print("               " .. (HUMAN[kind] and "highest: " or "lowest:  ") .. BR.signalsText(w.st.day and w.st.day.signals))
		for _, e in ipairs(w.st.day and w.st.day.explain or {}) do print("                 - " .. e) end
	end
	return res
end

local human = run("human", 8)
local silent = run("silenthuman", 6)
local routeH = run("routehuman", 6)
local helper = run("helper", 8)
local grinder = run("helpergrinder", 8)
local helperRoute = run("helperroute", 6)
local quiet = run("quiethelper", 8)
local afk = run("helperafk", 6)
local bot = run("bot", 6)
local bagless = run("baglessbot", 4)
local careful = run("carefulbot", 8)

eq(human.flagged, 0, "humans are never flagged")
eq(silent.flagged, 0, "silent humans (no chat) are never flagged")
eq(routeH.flagged, 0, "humans walking one fixed circle are never flagged")
eq(helper.flagged, 0, "helper users are never flagged")
eq(grinder.flagged, 0, "12 h helper grinders with breaks and almost no chat are never flagged")
eq(helperRoute.flagged, 0, "helper users on a fixed circle, no chat, are never flagged")
check(human.maxDay < cfg.storeAt and helper.maxDay < cfg.storeAt, "normal humans and helper users are not even stored")
eq(bot.flagged, bot.seeds, "every plain bot is flagged")
eq(bagless.flagged, bagless.seeds, "every bot using the Loot Bag (no loot moves) is flagged")
check(careful.flagged >= math.floor(careful.seeds * 0.75), "most bots with jittered timing and fake chat are flagged (" ..
	careful.flagged .. "/" .. careful.seeds .. ")")
eq(afk.checkedFlagged, afk.checked, "the helper left running unattended for 11 h is flagged once it missed a random check")
check(afk.minDay >= cfg.storeAt, "and stored for review even without a check")
eq(quiet.flagged, 0, "14 h helper users with short breaks and about 3 clicks an hour are never flagged (a passed check helps)")
local humanMax = math.max(human.maxDay, silent.maxDay, routeH.maxDay, helper.maxDay, grinder.maxDay, helperRoute.maxDay,
	quiet.maxDay)
check(bot.minDay > humanMax + 20, "a clear gap between the highest human day (" .. string.format("%.1f", humanMax) ..
	") and the lowest plain bot day (" .. string.format("%.1f", bot.minDay) .. ")")
if verbose then
	print(string.format("highest human or helper day %.1f, flagAt %d, lowest plain bot day %.1f", humanMax, cfg.flagAt, bot.minDay))
end

-- ---------------------------------------------------------------- botreview.lua with antibot.lua and reports.lua (mocked engine)
do
	local queries, async = {}, {}
	db = {
		query = function(q) queries[#queries + 1] = q; return true end,
		asyncQuery = function(q) async[#async + 1] = q; return true end,
		storeQuery = function() return false end,
		escapeString = function(s) return "'" .. tostring(s):gsub("'", "\\'") .. "'" end,
		lastInsertId = function() return 0 end
	}
	result = {free = function() end}
	json = {encode = function(t) return t end}
	local events, globals, talks, callbacks = {}, {}, {}, {}
	function CreatureEvent(name)
		local e = {name = name, type = function() end, register = function() end}
		events[name] = e
		return e
	end
	function GlobalEvent(name)
		local e = {name = name, interval = function() end, type = function() end, register = function() end}
		globals[name] = e
		return e
	end
	function TalkAction(words)
		local e = {words = words, separator = function() end, register = function() end}
		talks[words] = e
		return e
	end
	local cbList = {}
	EventCallback = setmetatable({}, {__newindex = function(t, k, v)
			callbacks[k] = callbacks[k] or {}
			table.insert(callbacks[k], v)
		end,
		__index = function(t, k) if k == "register" then return function() end end end})
	addEvent = function(fn, ms, ...) fn(...) end
	function ItemType(id) return {getClientId = function() return id + 1000 end, isCorpse = function() return id == 3058 end} end
	function MonsterType() return nil end
	Chaos.send = function() return true end
	local players, byName = {}, {}
	local P = {}
	P.__index = P
	local function mk(guid, name, group, ip)
		local p = setmetatable({guid = guid, id = 9000 + guid, name = name, group = group or 1, pos = {x = 100, y = 100, z = 7},
			storage = {}, msgs = {}, events = {}, account = 500 + guid, hp = 1000, maxhp = 1000, dir = 0, ip = ip or guid}, P)
		players[p.id], byName[name:lower()] = p, p
		return p
	end
	function P:getId() return self.id end
	function P:getGuid() return self.guid end
	function P:getName() return self.name end
	function P:getAccountId() return self.account end
	function P:getIp() return self.ip end
	function P:getParty() return nil end
	function P:getHealth() return self.hp end
	function P:getMaxHealth() return self.maxhp end
	function P:getDirection() return self.dir end
	function P:getGroup() local g = self.group return {getId = function() return g end, getAccess = function() return g >= 4 end} end
	function P:getPosition() local p = self.pos return {x = p.x, y = p.y, z = p.z, sendMagicEffect = function() end} end
	function P:getStorageValue(k) return self.storage[k] or -1 end
	function P:setStorageValue(k, v) self.storage[k] = v end
	function P:registerEvent(e) self.events[e] = true end
	function P:sendTextMessage(kind, text) self.msgs[#self.msgs + 1] = text end
	function P:sendCancelMessage(text) self.msgs[#self.msgs + 1] = text end
	function P:getTarget() return nil end
	function P:isPlayer() return true end
	function P:isMonster() return false end
	function P:getMaster() return nil end
	function P:isPzLocked() return false end
	function P:popupFYI(text) self.msgs[#self.msgs + 1] = text end
	function P:getTown() return {getTemplePosition = function() return {x = 50, y = 50, z = 7, sendMagicEffect = function() end} end} end
	function P:teleportTo(pos) self.pos = {x = pos.x, y = pos.y, z = pos.z} end
	function P:remove() self.removed = true end
	function Player(x)
		if type(x) == "number" then return players[x] end
		return byName[tostring(x):lower()]
	end
	Game = {getPlayers = function()
		local out = {}
		for _, p in pairs(players) do if not p.gone then out[#out + 1] = p end end
		table.sort(out, function(a, b) return a.id < b.id end)
		return out
	end}
	local monster = {isMonster = function() return true end, isPlayer = function() return false end, getMaster = function() return nil end,
		getId = function() return 70001 end, getName = function() return "Rat" end}
	local monster2 = {isMonster = function() return true end, isPlayer = function() return false end, getMaster = function() return nil end,
		getId = function() return 70002 end, getName = function() return "Rat" end}
	local clock = 5000000
	os.mtime = function() return clock end
	local selectRows = {}
	Chaos.select = function(q, cols)
		for pat, rows in pairs(selectRows) do
			if q:find(pat, 1, true) then return rows end
		end
		return {}
	end
	ChaosAntibot, ChaosReports, ChaosBotReview, ChaosAdminPending = nil, nil, nil, nil
	Chaos.antibotConfig, Chaos.botReviewConfig = nil, nil
	dofile("data/scripts/chaos/antibot.lua")
	dofile("data/scripts/chaos/botreview.lua")
	dofile("data/scripts/chaos/reports.lua")
	local AB, BV = ChaosAntibot, ChaosBotReview
	check(talks["/botreview"] ~= nil, "staff talkaction /botreview")
	check(ChaosAdminPending["security.botreview_list"] and ChaosAdminPending["security.botreview_show"] and
		ChaosAdminPending["security.botreview_mark"], "admin panel actions (Accounts & Security, group 5)")
	check(callbacks.onTargetCombat and callbacks.onLook and #callbacks.onItemMoved >= 2, "callbacks registered")
	globals.ChaosBotReviewStartup.onStartup()
	check(queries[#queries - 1]:find("CREATE TABLE IF NOT EXISTS `chaos_bot_daily`", 1, true) and
		queries[#queries]:find("CREATE TABLE IF NOT EXISTS `chaos_bot_actions`", 1, true), "tables created at startup")

	local alice = mk(1, "Alice", 1, 77)
	local bob = mk(2, "Bob", 1, 77)
	local gm = mk(3, "Gamemaster", 4)
	local admin = mk(4, "Admin", 5)
	for _, p in ipairs({alice, bob, gm, admin}) do
		events.ChaosAntibotLogin.onLogin(p)
		events.ChaosBotReviewLogin.onLogin(p)
	end
	check(BV.states[1] and BV.states[2] and not BV.states[3], "players get a state, staff never")
	check(alice.events.ChaosBotReviewKill and alice.events.ChaosBotReviewLogout, "kill and logout events registered")
	-- heals and hits through antibot.lua's healthchange: HP % reaches the threshold signal
	local h = events.ChaosAntibotHealth.onHealthChange
	alice.hp = 760
	h(alice, monster, 80, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
	alice.hp = 680
	clock = clock + 120
	h(alice, alice, 300, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL)
	local hs = BR.values(BV.states[1].heals)
	check(#hs == 1 and hs[1][1] == 68 and hs[1][2] == 76, "heal sample from the wrapped antibot hooks")
	check(BV.states[1].acts.n >= 1, "the heal is an action for the synchrony ring")
	-- kill and retarget
	clock = clock + 1000
	events.ChaosBotReviewKill.onKill(alice, monster)
	clock = clock + 230
	for _, cb in ipairs(callbacks.onTargetCombat) do eq(cb(alice, monster2), RETURNVALUE_NOERROR, "combat callback passes") end
	eq(BR.values(BV.states[1].retarget)[1], 230, "retarget latency")
	-- looks, item moves, chat
	for _, cb in ipairs(callbacks.onLook) do eq(cb(alice, monster, {}, 1, "You see a rat."), "You see a rat.", "look text unchanged") end
	local slot = BR.hourSlot(BV.states[1], os.time())
	eq(slot.look, 1, "a look is noise")
	local corpse = {isItem = function() return true end, isContainer = function() return true end, getId = function() return 3058 end}
	local bag = {isItem = function() return true end, isContainer = function() return true end, getId = function() return 1988 end,
		getAttribute = function() return 0 end}
	for _, cb in ipairs(callbacks.onItemMoved) do
		cb(alice, {}, 1, {x = CONTAINER_POSITION}, {x = CONTAINER_POSITION, y = 64, z = 0}, corpse, alice)
		cb(alice, {}, 1, {x = CONTAINER_POSITION}, {x = CONTAINER_POSITION, y = 65, z = 0}, bag, alice)
	end
	eq(slot.inv, 1, "an item move is noise, looting is not")
	ChaosReports.onChannelSpeak(alice, "World Chat", TALKTYPE_CHANNEL_Y, "hello")
	eq(slot.chat, 1, "a public line is counted")
	-- turns on the spot from antibot.lua's position samples
	clock = clock + 10000
	AB.tick(); AB.tick(); alice.dir = 2; AB.tick()
	eq(slot.turn, 1, "a turn on the spot is noise")
	-- a presence check missed while acting: the signal, a log entry, never a move or a kick
	AB.states[2].lastPvp = nil
	AB.forceCheck(bob)
	local c = AB.states[2].check.active
	local realTime = os.time
	local t0 = realTime()
	os.time = function() return t0 + 30 end
	BR.onAction(BV.states[2], cfg, clock, t0 + 30)
	os.time = function() return c.deadline + 5 end
	bob.pos = {x = 300, y = 300, z = 7}
	AB.tick()
	os.time = realTime
	eq(BV.states[2].checks[1].result, "fail", "check result recorded")
	eq(BV.states[2].checks[1].acted, true, "kept acting during the check")
	check(bob.pos.x == 300 and not bob.removed, "never moved, never kicked")
	eq(BR.presenceSignal(BV.states[2], cfg, c.deadline + 10), 1, "presence signal")
	-- evaluation, the day row, staff told once
	local st2 = BV.states[2]
	st2.nextEval = 0
	st2.signals = nil
	local abst = AB.states[2]
	abst.signals = {timing = 1, reaction = 1, loot = 0, loop = 1, nonstop = 1}
	abst.info = {nonstop = {streak = 1, day = 1}, loop = {match = 0.95, period = 20}}
	async = {}
	local nowS = os.time()
	local hourStart = nowS - nowS % 3600
	for back = 1, 2 do
		for i = 1, 12 do BR.addPoint(st2, cfg, Chaos.dayKey(nowS), (os.date("*t", nowS).hour + 24 - back) % 24, 90) end
	end
	BV.evaluate(bob, st2, nowS)
	check(st2.score >= cfg.flagAt, "bot-like signals: high score (" .. st2.score .. ")")
	local wrote
	for _, q in ipairs(async) do if q:find("INSERT INTO `chaos_bot_daily`", 1, true) then wrote = q end end
	check(wrote and wrote:find("'Bob'", 1, true) and wrote:find("presence=1.00", 1, true), "day row written with the signals")
	check(gm.msgs[#gm.msgs]:find("[Bot review] Bob is on the review list", 1, true), "online staff told")
	local told = #gm.msgs
	BV.evaluate(bob, st2, nowS + 300)
	eq(#gm.msgs, told, "told once per day")
	check(not bob.removed and bob.pos.x == 300, "flagging does nothing to the player")
	-- staff marks: a GM may review, only an administrator may change an escalated case
	selectRows["SELECT `id`, `status`, `player_name`, `day` FROM `chaos_bot_daily` WHERE `player_id` = 2"] = {{id = 5, status = "new", player_name = "Bob", day = 20261014}}
	queries = {}
	local ok, text = BV.mark("Gamemaster", 4, 2, nil, "escalate", "watch\nthis")
	check(ok and text:find("escalated", 1, true), "GM escalates")
	check(queries[1]:find("`status` = 'escalated'", 1, true) and queries[1]:find("'watch this'", 1, true), "status and note saved")
	check(async[#async]:find("INSERT INTO `chaos_bot_actions`", 1, true) and async[#async]:find("'escalate'", 1, true), "action logged")
	selectRows["SELECT `id`, `status`, `player_name`, `day` FROM `chaos_bot_daily` WHERE `player_id` = 2"] = {{id = 5, status = "escalated", player_name = "Bob", day = 20261014}}
	ok, text = BV.mark("Gamemaster", 4, 2, nil, "false_positive", "")
	check(not ok and text:find("administrator", 1, true), "GM cannot change an escalated case")
	ok = BV.mark("Admin", 5, 2, nil, "reviewed", "talked, banned per ladder")
	check(ok, "administrator can")
	eq((BV.mark("Admin", 5, 2, nil, "ban", "")), false, "no other actions (nothing here bans)")
	-- /botreview
	talks["/botreview"].onSay(alice, "/botreview", "")
	check(alice.msgs[#alice.msgs] ~= "Nothing to review in the last 7 days.", "players get nothing")
	eq(talks["/botreview"].onSay(alice, "/botreview", ""), true, "a player's words are plain chat")
	selectRows["`status` IN ('new', 'escalated')"] = {{player_name = "Bob", day = 20261014, score = 77, status = "new"}}
	talks["/botreview"].onSay(gm, "/botreview", "")
	check(gm.msgs[#gm.msgs]:find("Bob  day 20261014  score 77  new", 1, true), "staff list")
	talks["/botreview"].onSay(gm, "/botreview", "Bob")
	check(gm.msgs[#gm.msgs]:find("Bob now: score", 1, true) and gm.msgs[#gm.msgs]:find("presence 1.00", 1, true), "staff detail with explanations")
	selectRows["SELECT `id`, `status`, `player_name`, `day` FROM `chaos_bot_daily` WHERE `player_id` = 2"] = {{id = 5, status = "new", player_name = "Bob", day = 20261014}}
	talks["/botreview"].onSay(gm, "/botreview", "mark Bob, reviewed, looked fine")
	check(gm.msgs[#gm.msgs]:find("reviewed", 1, true), "mark from the talkaction")
	local okA, _, lines = ChaosAdminPending["security.botreview_show"].handler(admin, {player = "Bob"})
	check(okA and lines[1]:find("Bob now", 1, true), "admin panel detail")
	-- website check requests
	selectRows["`action` = 'check' AND"] = {{id = 9, player_id = 1, created_at = os.time()}, {id = 10, player_id = 55, created_at = os.time() - 90000}}
	async = {}
	BV.pollRequests(os.time())
	eq(AB.states[1].check.owed, true, "requested check owed (antibot.lua sends it outside PvP / bosses / rifts)")
	check(async[1]:find("'sent'", 1, true) and async[2]:find("'expired'", 1, true), "requests marked")
	selectRows["`action` = 'check' AND"] = nil
	-- cluster pass over the shared IP
	local sa, sb = BV.states[1], BV.states[2]
	sa.acts, sb.acts = BR.ring(cfg.cluster.ring), BR.ring(cfg.cluster.ring)
	local tt = 1000
	for i = 1, 40 do tt = tt + 900 + (i * 37) % 700; BR.push(sa.acts, tt); BR.push(sb.acts, tt + 20) end
	eq(BV.clusterPass(Game.getPlayers()), 1, "one pair on the shared IP")
	eq(sa.clusterWith, "Bob", "cluster partner")
	-- purge
	async = {}
	BV.purge(os.time())
	eq(#async, 3, "purge queries")
	-- tick and offline cleanup
	BV.lastPurge, BV.lastPoll, BV.lastCluster = os.time(), os.time(), os.time()
	events.ChaosBotReviewLogout.onLogout(alice)
	check(BV.states[1].offlineAt ~= nil, "kept after logout")
	BV.states[1].offlineAt = os.time() - 3600
	BV.tick()
	eq(BV.states[1], nil, "forgotten after keepOfflineMinutes")
	-- staff never sampled even through the wrapped hooks
	h(gm, monster, 10, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
	eq(BV.states[3], nil, "staff never sampled")
	-- the wrappers are installed once
	local before = ChaosAntibotCore.onAction
	BV.wrap(); BV.wrap()
	eq(ChaosAntibotCore.onAction, before, "wrapping is idempotent")
end

print(string.format("botreview_test: %d checks, %d failed", count, failures))
if failures > 0 then
	os.exit(1)
end
