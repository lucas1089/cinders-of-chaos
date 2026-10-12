-- Run from the server/ folder: luajit tests/antibot_test.lua (or lua5.3; CI runs both)
-- Anti-bot and player reports: the core helpers, each signal, the score bound for a single signal, the presence check
-- (pictures, groups, answer, retry, timeout, rate limits, deferral), synthetic human and bot traces (separation and
-- false positives), reports_core.lua (validation, limits, public chat lines, webhook), the opcode, and antibot.lua +
-- reports.lua against a mocked engine (login, heals, tick, check, answer, failure action, report row, staff list).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
local cfg = dofile("data/scripts/chaos/antibot_config.lua")
dofile("data/scripts/chaos/antibot_core.lua")
dofile("data/scripts/chaos/reports_core.lua")
local K, R = ChaosAntibotCore, ChaosReportsCore

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

-- ---------------------------------------------------------------- opcode and storages
eq(ChaosOpcodes.antibot, 211, "opcode 211")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	check(not seen[v], "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202}) do
	check(seen[v] == nil or v == 89, "no Chaos opcode on base opcode " .. v)
end
eq(Chaos.storage.antibot, 7100890, "storage base")
for k, v in pairs(Chaos.storage) do
	if k ~= "antibot" and type(v) == "number" then
		check(v < 7100890 or v > 7100899, "storage " .. k .. " outside the anti-bot range")
	end
end
check(cfg.check.timeLimitSeconds >= 60 and cfg.check.timeLimitSeconds <= 90, "time limit 60 - 90 s")
eq(cfg.log.holdLeaderboards, false, "leaderboard holds off by default")
eq(cfg.reports.discordWebhook, "", "no webhook in the repository")

-- ---------------------------------------------------------------- helpers
local r = K.ring(3)
for i = 1, 5 do K.push(r, i) end
eq(table.concat(K.values(r), ","), "3,4,5", "ring keeps the newest")
eq(K.last(r), 5, "ring last")
eq(K.ramp(0.15, 0.15, 0.05), 0, "ramp from")
eq(K.ramp(0.05, 0.15, 0.05), 1, "ramp to")
near(K.ramp(0.10, 0.15, 0.05), 0.5, 1e-9, "ramp middle")
near(K.cv({10, 10, 10}), 0, 1e-9, "cv flat")
near(K.cv({5, 15}), 0.5, 1e-9, "cv")

-- ---------------------------------------------------------------- a small deterministic PRNG (same in Lua 5.3 and LuaJIT)
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
	return rnd
end

-- ---------------------------------------------------------------- signals on small traces
do
	local st = K.newState(cfg, 0)
	for i = 1, 30 do K.onAction(st, cfg, i * 1500, i) end
	local s, info = K.timingSignal(st, cfg)
	eq(s, 1, "fixed 1.5 s rhythm scores 1")
	eq(info.n, 29, "29 intervals")
	st = K.newState(cfg, 0)
	for i = 1, 30 do K.onAction(st, cfg, i * 2000 + (i % 3) * 15, i) end
	eq(select(2, K.timingSignal(st, cfg)).n, 0, "cooldown-bound intervals (held hotkey) left out")
	st = K.newState(cfg, 0)
	K.onAction(st, cfg, 1000, 1)
	eq(K.onAction(st, cfg, 1030, 1), false, "a second event within dedupeMs is the same action")
end
do
	local st = K.newState(cfg, 0)
	local t = 0
	for i = 1, 12 do
		t = t + 5000
		K.onDamage(st, cfg, t)
		eq(K.onSelfHeal(st, cfg, t + 60 + (i % 3) * 5, 1), 60 + (i % 3) * 5, "isolated heal latency " .. i)
	end
	near(K.reactionSignal(st, cfg), 1, 1e-9, "instant tight reactions score 1")
	K.onDamage(st, cfg, t + 1000)
	eq(K.onSelfHeal(st, cfg, t + 1100, 1), nil, "a heal 1 s after the last heal is part of a train, not a reaction")
	st = K.newState(cfg, 0)
	K.onSelfHeal(st, cfg, 10000, 1)
	eq(st.reacts.n, 0, "a heal without a hit is no reaction")
end
do
	-- a 10-cell loop walked 6 times: loop; walking between two cells: no loop
	local st = K.newState(cfg, 0)
	for lap = 1, 6 do
		for c = 0, 9 do K.onPosition(st, cfg, 1000 + c * 8, 1000, 7, lap * 100 + c) end
	end
	local s, info = K.loopSignal(st, cfg, 1000)
	eq(s, 1, "repeated loop scores 1")
	eq(info.period, 10, "loop period 10")
	st = K.newState(cfg, 0)
	for i = 1, 80 do K.onPosition(st, cfg, 1000 + (i % 2) * 8, 1000, 7, i) end
	eq(K.loopSignal(st, cfg, 1000), 0, "two cells back and forth is no loop")
	eq(K.onPosition(st, cfg, 1000 + 8 * (80 % 2), 1000, 7, 81), false, "same cell: nothing stored")
end
do
	local st = K.newState(cfg, 0)
	-- active every 5 minutes for 15 hours: streak 15 h
	for m = 0, 15 * 60, 5 do K.markActive(st, cfg, m * 60) end
	local s, info = K.nonstopSignal(st, cfg, 15 * 3600)
	eq(s, 1, "15 h without a break scores 1")
	near(info.streak, 15, 0.01, "streak hours")
	K.markActive(st, cfg, 15 * 3600 + 21 * 60)
	near(select(2, K.nonstopSignal(st, cfg, 15 * 3600 + 21 * 60)).streak, 0, 0.01, "a 21 min break starts a new streak")
end

-- ---------------------------------------------------------------- the score: one signal alone stays under the thresholds
do
	local maxSingle = 0
	for _, name in ipairs(K.SIGNALS) do
		local sig = {}
		sig[name] = 1
		local add = K.combine(sig, cfg)
		maxSingle = math.max(maxSingle, K.steadyScore(cfg, add))
	end
	check(maxSingle < cfg.check.at, string.format("one maxed signal steady score %.1f < check %d", maxSingle, cfg.check.at))
	local add, elevated = K.combine({timing = 1, reaction = 1}, cfg)
	eq(elevated, 2, "two elevated")
	check(K.steadyScore(cfg, add) > cfg.log.at, "two maxed signals pass the log threshold")
	-- decay: an hour without an add halves the score
	local st = K.newState(cfg, 0)
	st.score = 100
	st.lastEval = 0
	K.evaluate(st, cfg, 3600)
	near(st.score, 50, 0.01, "half-life one hour")
end

-- ---------------------------------------------------------------- decisions
do
	local st = K.newState(cfg, 0)
	local now = 100000
	st.score = cfg.check.at + 1
	local a, logIt = K.decide(st, cfg, now, {pvp = true}, 20261010)
	eq(a, "defer", "PvP defers the check")
	eq(logIt, false, "under the log threshold")
	eq(K.decide(st, cfg, now + 60, {boss = true}, 20261010), "defer", "boss fight defers")
	eq(K.decide(st, cfg, now + 120, {}, 20261010), "check", "out of combat: check")
	local rnd7 = prng(7)
	K.newChallenge(st, cfg, function(k) return rnd7.int(1, k) end, now + 120)
	eq(K.decide(st, cfg, now + 180, {}, 20261010), nil, "no second check while one runs")
	K.finish(st, cfg, "pass", now + 200)
	near(st.score, (cfg.check.at + 1) * cfg.check.successFactor, 1e-6, "pass lowers the score")
	st.score = 200
	eq(K.decide(st, cfg, now + 300, {}, 20261010), nil, "grace time and gap after a check")
	eq(K.decide(st, cfg, now + cfg.check.graceHours * 3600 + 400, {}, 20261010), "check", "after the grace time")
	st.check.active = nil
	st.check.lastAt = 0
	st.check.graceUntil = 0
	st.check.dayCount = cfg.check.maxPerDay
	st.check.day = 20261011
	eq(K.decide(st, cfg, now + 90000, {}, 20261011), nil, "daily limit")
	eq(K.decide(st, cfg, now + 90000, {}, 20261012), "check", "a new day")
	-- deferred too long: dropped
	st = K.newState(cfg, 0)
	st.score = 100
	eq(K.decide(st, cfg, 100000, {pvp = true}, 1), "defer", "defer starts")
	eq(K.decide(st, cfg, 100000 + cfg.check.deferMaxMinutes * 60 + 1, {pvp = true}, 1), nil, "deferred too long: dropped")
	eq(st.check.lastAt, 100000 + cfg.check.deferMaxMinutes * 60 + 1, "dropped check counts for the gap")
	-- log
	st = K.newState(cfg, 0)
	st.score = cfg.log.at
	check(select(2, K.decide(st, cfg, 5000, {}, 1)), "log at the threshold")
	K.markLogged(st, 5000)
	check(not select(2, K.decide(st, cfg, 6000, {}, 1)), "log cooldown")
	st.score = cfg.log.at * 2
	check(select(2, K.decide(st, cfg, 6060, {}, 1)), "a doubled score logs again")
end

-- ---------------------------------------------------------------- the presence check
do
	local rnd = prng(42)
	local rng = function(k) return rnd.int(1, k) end
	local groupOf = {}
	for _, e in ipairs(cfg.check.pool) do groupOf[e.id] = e.group end
	for i = 1, 200 do
		local st = K.newState(cfg, 0)
		local c = K.newChallenge(st, cfg, rng, 1000)
		eq(#c.options, cfg.check.choices, "four pictures " .. i)
		local ids, groups, keys, found = {}, {}, {}, false
		for _, o in ipairs(c.options) do
			check(not ids[o.id], "distinct pictures " .. i)
			ids[o.id] = true
			if groupOf[o.id] then
				check(not groups[groupOf[o.id]], "never two of one group " .. i)
				groups[groupOf[o.id]] = true
			end
			check(not keys[o.key] and #o.key == 6, "distinct keys " .. i)
			keys[o.key] = true
			if o.key == c.answer then
				found = true
				eq(o.word, c.word, "the answer shows the word " .. i)
			end
		end
		check(found, "the answer is one of the pictures " .. i)
	end
	local st = K.newState(cfg, 0)
	local c = K.newChallenge(st, cfg, rng, 1000)
	local p = K.payload(c, cfg, 1010, function(id) return id + 100000 end)
	eq(p.s, cfg.check.timeLimitSeconds - 10, "seconds left")
	eq(p.r, 1, "one retry left")
	eq(#p.o, 4, "payload options")
	for _, o in ipairs(p.o) do
		check(o.c > 100000 and o.word == nil and o.id == nil, "payload sends client ids only, no words, no server ids")
	end
	check(p.answer == nil and p.k == nil, "payload has no answer")
	eq(K.answer(st, cfg, "nope", c.answer, 1010), "stale", "wrong token")
	local wrong = c.options[1].key == c.answer and c.options[2].key or c.options[1].key
	eq(K.answer(st, cfg, c.token, wrong, 1010), "retry", "first wrong click: retry")
	local c2 = K.newChallenge(st, cfg, rng, 1020, 2)
	check(c2.token ~= c.token, "the retry is a new picture")
	eq(c2.deadline, math.max(c.deadline, 1020 + cfg.check.retrySeconds), "retry deadline")
	eq(K.payload(c2, cfg, 1020).r, 0, "no retry left")
	check(not K.canRetry(st, cfg, c2.token), "no second retry")
	local wrong2 = c2.options[1].key == c2.answer and c2.options[2].key or c2.options[1].key
	eq(K.answer(st, cfg, c2.token, wrong2, 1030), "fail", "second wrong click fails")
	eq(K.answer(st, cfg, c2.token, c2.answer, c2.deadline + 1), "fail", "too late")
	eq(K.answer(st, cfg, c2.token, c2.answer, 1030), "pass", "right picture")
	check(K.timedOut(st, c2.deadline + 1), "timed out")
	eq(st.check.dayCount, 1, "the retry is the same check")
	st.score = 70
	K.finish(st, cfg, "fail", 1100)
	eq(st.score, 70 + cfg.check.failPenalty, "fail adds the penalty")
	eq(st.check.active, nil, "check closed")
end

-- ---------------------------------------------------------------- synthetic traces
-- A character over hours: position samples every 2 s, deliberate actions, hits taken and own heals, loot moves, an
-- evaluation every 60 s. Returns the highest score, when it first reached the check and the log thresholds, and the
-- last signals.
local function simulate(kind, seed, hours)
	local rnd = prng(seed)
	local st = K.newState(cfg, 0)
	local ev = {}
	local function add(t, k, a, b)
		ev[#ev + 1] = {t = math.floor(t), k = k, a = a, b = b}
	end
	local totalMs = hours * 3600000
	local bot = kind == "bot" or kind == "carefulbot" or kind == "lootbot"
	-- online periods: humans play sessions with breaks; bots almost never stop
	local periods = {}
	if bot then
		periods[1] = {0, totalMs}
	elseif kind == "grinder" then
		local t = 0
		while t < totalMs do
			local len = rnd.normal(2 * 3600000, 600000)
			periods[#periods + 1] = {t, math.min(totalMs, t + len)}
			t = t + len + rnd.normal(30 * 60000, 5 * 60000)
		end
	else
		local len = rnd.normal(3.5 * 3600000, 3600000)
		periods[1] = {0, math.min(totalMs, math.max(3600000, len))}
	end
	-- the hunting ground: a ring of rooms 24 tiles apart (two floors of the same cave for humans to switch)
	local rooms = {}
	for i = 0, 15 do
		local a = i / 16 * 2 * math.pi
		rooms[#rooms + 1] = {x = 1000 + math.floor(math.cos(a) * 60), y = 1000 + math.floor(math.sin(a) * 60)}
	end
	local ping = bot and rnd.normal(50, 10) or (kind == "fasthuman" and 15 or rnd.normal(70, 25))
	local tryhard = kind == "spammer" or kind == "grinder" or kind == "routehuman"
	local route = kind == "routehuman" -- always the same circle, forward, no detours: a loop, but a human's hands
	local lastHeal = -1e9
	-- one fight from tA to tB: hits taken, heals, attack spells; then the loot of the kills
	local function fight(tA, tB)
		local nextHit = tA + rnd.exp(1500)
		local nextAttack = tA + rnd.int(200, 1500)
		while nextHit < tB or nextAttack < tB do
			if nextHit <= nextAttack then
				add(nextHit, "hit")
				local heal
				if bot then
					if rnd.u() < 0.5 then heal = nextHit + ping + rnd.int(5, 25) end
				elseif kind == "spammer" then
					-- holds the heal hotkey while hit: a heal every cooldown
					if nextHit - lastHeal > 1100 then heal = nextHit + ping + rnd.normal(420, 130) end
				elseif kind == "fasthuman" then
					if rnd.u() < 0.4 then heal = nextHit + ping + 170 + rnd.exp(70) end
				else
					if rnd.u() < 0.35 then heal = nextHit + ping + math.max(150, rnd.normal(380, 120)) + rnd.exp(80) end
				end
				if heal and heal - lastHeal > 1000 then
					add(heal, "heal")
					lastHeal = heal
					if kind == "spammer" then
						for k = 1, rnd.int(1, 4) do
							add(heal + k * (1000 + rnd.int(0, 40)), "heal")
							lastHeal = heal + k * 1040
						end
					end
				end
				nextHit = nextHit + rnd.exp(1500)
			else
				add(nextAttack, "act")
				if kind == "bot" or kind == "lootbot" then
					nextAttack = nextAttack + 1500 + rnd.int(-15, 15)
				elseif kind == "carefulbot" then
					nextAttack = nextAttack + 1500 + rnd.int(-450, 450)
				elseif tryhard and rnd.u() < 0.3 then
					nextAttack = nextAttack + 2000 + rnd.int(0, 40) -- held key on the cooldown
				else
					nextAttack = nextAttack + math.max(350, rnd.normal(1900, 650))
				end
			end
		end
		local lt = tB + (bot and 300 or rnd.int(500, 3000))
		if bot or rnd.u() < 0.6 then
			for i = 1, rnd.int(1, 4) do
				add(lt, "loot")
				if kind == "bot" or kind == "lootbot" then
					lt = lt + 300 + rnd.int(-12, 12)
				elseif kind == "carefulbot" then
					lt = lt + 300 + rnd.int(-150, 150)
				else
					lt = lt + math.max(150, rnd.normal(750, 300))
				end
			end
		end
		return lt
	end
	for _, per in ipairs(periods) do
		local t, t1 = per[1], per[2]
		local room, dir = rnd.int(1, #rooms), 1
		local x, y = rooms[room].x, rooms[room].y
		local target = room % #rooms + 1
		local detour = {x = 0, y = 0}
		while t < t1 do
			-- walk to the next room (a stray monster sometimes hits on the way)
			local goal = rooms[target]
			local gx, gy = goal.x + detour.x, goal.y + detour.y
			local dx, dy = gx - x, gy - y
			local dist = math.sqrt(dx * dx + dy * dy)
			local step = bot and 8 or rnd.normal(7.5, 1.5)
			if dist > step then
				x, y = x + dx / dist * step, y + dy / dist * step
				add(t, "pos", math.floor(x + 0.5), math.floor(y + 0.5))
				if rnd.u() < 0.03 then add(t + rnd.int(0, 1999), "hit") end
				t = t + cfg.sampleMs
			else
				x, y = gx, gy
				add(t, "pos", math.floor(x + 0.5), math.floor(y + 0.5))
				t = t + cfg.sampleMs
				-- the room: a fight half of the time (chasing and dodging around; bots follow their target too)
				if rnd.u() < 0.5 then
					local fightEnd = math.min(t1, t + rnd.int(10, 40) * 1000)
					local lootEnd = fight(t, fightEnd)
					while t < math.max(fightEnd, lootEnd) and t < t1 do
						x, y = x + rnd.int(-2, 2), y + rnd.int(-2, 2)
						add(t, "pos", math.floor(x + 0.5), math.floor(y + 0.5))
						t = t + cfg.sampleMs
					end
					t = t + (bot and rnd.int(0, 2) * 1000 or rnd.int(0, 10) * 1000)
				end
				-- next room: bots follow the ring; humans mostly go on, sometimes turn back or skip a room
				if bot or route then
					target = target % #rooms + 1
				else
					if rnd.u() < (tryhard and 0.08 or 0.2) then dir = -dir end
					local skip = rnd.u() < 0.15 and 2 or 1
					target = ((target - 1 + dir * skip) % #rooms) + 1
					detour = {x = rnd.int(-10, 10), y = rnd.int(-10, 10)}
				end
			end
		end
	end
	for t = 0, totalMs, cfg.evalSeconds * 1000 do
		add(t + 1, "eval")
	end
	table.sort(ev, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.k < b.k end)
	local maxScore, checkAt, logAt = 0, nil, nil
	for _, e in ipairs(ev) do
		local s = math.floor(e.t / 1000)
		if e.k == "pos" then
			K.onPosition(st, cfg, e.a, e.b, 7, s, e.t)
		elseif e.k == "act" then
			K.onAction(st, cfg, e.t, s, "attack")
		elseif e.k == "hit" then
			K.onDamage(st, cfg, e.t)
		elseif e.k == "heal" then
			K.onSelfHeal(st, cfg, e.t, s)
		elseif e.k == "loot" then
			K.onLootMove(st, cfg, e.t, s)
		elseif e.k == "eval" then
			K.evaluate(st, cfg, s)
			if st.score > maxScore then maxScore = st.score end
			if not checkAt and st.score >= cfg.check.at then checkAt = s end
			if not logAt and st.score >= cfg.log.at then logAt = s end
		end
	end
	return {max = maxScore, checkAt = checkAt, logAt = logAt, signals = st.signals, info = st.info, st = st}
end

local function fmtSignals(s)
	local parts = {}
	for _, name in ipairs(K.SIGNALS) do parts[#parts + 1] = string.format("%s %.2f", name, s[name] or 0) end
	return table.concat(parts, " ")
end

local verbose = arg and arg[1] == "-v"
local results = {}
local function run(kind, seeds, hours)
	local flagged, maxOfMax, sumMax, minutes = 0, 0, 0, {}
	local worst
	for seed = 1, seeds do
		local res = simulate(kind, seed * 7919 + #kind, hours)
		if res.checkAt then
			flagged = flagged + 1
			minutes[#minutes + 1] = res.checkAt / 60
		end
		if res.max >= maxOfMax then maxOfMax, worst = res.max, res end
		sumMax = sumMax + res.max
	end
	table.sort(minutes)
	local r = {kind = kind, seeds = seeds, hours = hours, flagged = flagged, maxScore = maxOfMax, meanMax = sumMax / seeds,
		medianMinutes = minutes[math.max(1, math.floor(#minutes / 2 + 0.5))], worst = worst}
	results[#results + 1] = r
	if verbose then
		print(string.format("%-10s %3d x %2dh  reached check %3d/%d  max score %6.1f  mean max %6.1f  median minutes to check %s",
			kind, seeds, hours, flagged, seeds, maxOfMax, r.meanMax, tostring(r.medianMinutes and math.floor(r.medianMinutes))))
		print("           worst signals: " .. fmtSignals(worst.signals) .. "  | " .. K.summary(worst.st))
	end
	return r
end

local human = run("human", 24, 6)
local spammer = run("spammer", 16, 6)
local fast = run("fasthuman", 16, 6)
local routeHuman = run("routehuman", 12, 6)
local grinder = run("grinder", 8, 14)
local bot = run("bot", 12, 6)
local lootbot = run("lootbot", 6, 6)
local careful = run("carefulbot", 6, 16)

eq(human.flagged, 0, "normal humans never reach the presence check")
eq(spammer.flagged, 0, "heal-spamming tryhards never reach the presence check")
eq(fast.flagged, 0, "fast-reflex humans on a 15 ms ping never reach the presence check")
eq(grinder.flagged, 0, "14 h grinders with breaks never reach the presence check")
eq(routeHuman.flagged, 0, "humans walking one fixed circle (a loop alone) never reach the presence check")
check(routeHuman.worst.signals.loop >= 0.5, "the fixed circle does show as a loop")
check(human.maxScore < cfg.check.at and spammer.maxScore < cfg.check.at and fast.maxScore < cfg.check.at and
	grinder.maxScore < cfg.check.at, "every human stays under the check threshold")
eq(bot.flagged, bot.seeds, "every plain bot reaches the presence check")
check(bot.medianMinutes and bot.medianMinutes <= 45, "plain bots are checked within 45 minutes (median " ..
	tostring(bot.medianMinutes) .. ")")
eq(lootbot.flagged, lootbot.seeds, "every loot-timing bot reaches the presence check")
check(careful.flagged >= math.floor(careful.seeds * 0.8), "most bots with jittered timing are caught within 16 h by " ..
	"reactions, loops and nonstop play (" .. careful.flagged .. "/" .. careful.seeds .. ")")
check(bot.worst.max >= cfg.log.at, "plain bots reach the staff log threshold")

-- ---------------------------------------------------------------- reports_core.lua
local rcfg = cfg.reports
do
	local me = {guid = 1, name = "Arwen", level = 50, account = 10}
	local ok, err = R.validate(rcfg, {name = "Bad Guy", reason = "botting", note = "  walks\nthe same\tpath  "}, me)
	eq(ok and ok.note, "walks the same path", "note cleaned")
	eq(ok and ok.reason, "botting", "reason kept")
	eq(select(2, R.validate(rcfg, {name = "arwen", reason = "scam"}, me)), "self", "no self report")
	eq(select(2, R.validate(rcfg, {name = "B", reason = "scam"}, me)), "name", "short name")
	eq(select(2, R.validate(rcfg, {name = "Bad'; DROP", reason = "scam"}, me)), "name", "name charset")
	eq(select(2, R.validate(rcfg, {name = "Bad Guy", reason = "spam"}, me)), "reason", "unknown reason")
	eq(select(2, R.validate(rcfg, {name = "Bad Guy", reason = "other", note = ""}, me)), "note", "other needs a note")
	eq(select(2, R.validate(rcfg, {name = "Bad Guy", reason = "scam"}, {name = "Low", level = 2})), "level", "minimum level")
	eq(#R.validate(rcfg, {name = "Bad Guy", reason = "other", note = string.rep("x", 400)}, me).note, rcfg.noteMax, "note cut")
	eq(R.clean("caf\195\169 \1ok", 50), "caf ok", "non-ASCII and controls dropped")
	local st = R.newState()
	local now = 1000000
	check(R.allow(st, rcfg, me, 2, now), "first report allowed")
	R.record(st, rcfg, me, 2, now)
	eq(select(2, R.allow(st, rcfg, me, 3, now + 10)), "cooldown", "cooldown")
	eq(select(2, R.allow(st, rcfg, me, 2, now + 100)), "same", "same target within a day")
	check(R.allow(st, rcfg, {account = 10, guid = 99}, 3, now + 100), "another character of the account, other target")
	for i = 1, rcfg.perDay - 1 do R.record(st, rcfg, me, 100 + i, now + 100 * i) end
	eq(select(2, R.allow(st, rcfg, {account = 10, guid = 98}, 500, now + 10000)), "day", "per-account daily limit")
	check(R.allow(st, rcfg, me, 500, now + 86400 * 2), "a new day")
	-- public chat lines
	for i = 1, 15 do R.chatPush(st, rcfg, 7, "World Chat", "line " .. i, now + i) end
	local lines = R.chatLines(st, 7, function(t) return "T" end)
	eq(#lines, rcfg.chatLines, "last N lines kept")
	eq(lines[#lines], "[T] World Chat: line 15", "line format")
	R.chatGone(st, 7, now)
	R.chatSweep(st, rcfg, now + 60)
	eq(#R.chatLines(st, 7), rcfg.chatLines, "kept a while after logout")
	R.chatSweep(st, rcfg, now + rcfg.chatKeepMinutes * 60)
	eq(#R.chatLines(st, 7), 0, "gone after chatKeepMinutes")
	-- webhook
	check(R.validWebhook("https://discord.com/api/webhooks/123/abc_DEF-9"), "webhook URL")
	check(not R.validWebhook("https://discord.com/api/webhooks/123/abc;rm -rf"), "no shell characters")
	check(not R.validWebhook("http://discord.com/api/webhooks/1/a"), "https only")
	check(not R.validWebhook("https://example.com/api/webhooks/1/a"), "discord only")
	check(not R.validWebhook(""), "empty = off")
	local body = R.discordPayload({id = 5, reason = "botting", reporter_name = "A", target_name = "B", chat = "secret", note = "n"})
	check(body.content:find("#5", 1, true) and not body.content:find("secret", 1, true), "webhook body without chat")
	check(R.listLine({id = 3, status = "open", created_at = 0, reporter_name = "A", target_name = "B", reason = "scam",
		suspicion = 12}):find("#3 open", 1, true), "list line")
end

-- ---------------------------------------------------------------- antibot.lua + reports.lua against a mocked engine
do
	local queries, async = {}, {}
	local lastId = 0
	db = {
		query = function(q) queries[#queries + 1] = q; if q:find("^INSERT INTO `chaos_reports`") then lastId = lastId + 1 end; return true end,
		asyncQuery = function(q) async[#async + 1] = q; return true end,
		storeQuery = function() return false end,
		escapeString = function(s) return "'" .. tostring(s):gsub("'", "\\'") .. "'" end,
		lastInsertId = function() return lastId end
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
	EventCallback = setmetatable({}, {__newindex = function(t, k, v) callbacks[k] = v end,
		__index = function(t, k) if k == "register" then return function() end end end})
	addEvent = function(fn, ms, ...) fn(...) end
	function ItemType(id) return {getClientId = function() return id + 1000 end, isCorpse = function() return true end} end
	function MonsterType() return nil end
	local sent = {}
	local oldSend = Chaos.send
	Chaos.send = function(player, opcode, action, data)
		sent[#sent + 1] = {to = player.name, op = opcode, action = action, data = data}
		return true
	end
	local players, byName = {}, {}
	local P = {}
	P.__index = P
	local function mk(guid, name, group, level)
		local p = setmetatable({guid = guid, id = 9000 + guid, name = name, group = group or 1, level = level or 100,
			pos = {x = 100, y = 100, z = 7}, storage = {}, msgs = {}, events = {}, account = 500 + guid}, P)
		players[p.id], byName[name:lower()] = p, p
		return p
	end
	function P:getId() return self.id end
	function P:getGuid() return self.guid end
	function P:getName() return self.name end
	function P:getLevel() return self.level end
	function P:getAccountId() return self.account end
	function P:getGroup() local g = self.group return {getId = function() return g end, getAccess = function() return g >= 4 end} end
	function P:getPosition() local p = self.pos return {x = p.x, y = p.y, z = p.z, sendMagicEffect = function() end} end
	function P:getStorageValue(k) return self.storage[k] or -1 end
	function P:setStorageValue(k, v) self.storage[k] = v end
	function P:registerEvent(e) self.events[e] = true end
	function P:sendTextMessage(kind, text) self.msgs[#self.msgs + 1] = text end
	function P:getTarget() return nil end
	function P:isPlayer() return true end
	function P:isMonster() return false end
	function P:getMaster() return nil end
	function P:isPzLocked() return false end
	function P:popupFYI(text) self.msgs[#self.msgs + 1] = text end
	function P:getTown()
		return {getTemplePosition = function() return {x = 50, y = 50, z = 7, sendMagicEffect = function() end} end}
	end
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
	os.mtime = function() return os.time() * 1000 end
	ChaosAntibot, ChaosReports, ChaosAdminPending = nil, nil, nil
	Chaos.antibotConfig = nil
	dofile("data/scripts/chaos/antibot.lua")
	dofile("data/scripts/chaos/reports.lua")
	local AB, RP = ChaosAntibot, ChaosReports
	check(callbacks.onTargetCombat and callbacks.onItemMoved and callbacks.onReportRuleViolation, "callbacks registered")
	check(talks["/reports"] and not talks["!report"], "staff talkaction only (players use the menu)")
	check(ChaosAdminPending["security.reports_list"] and ChaosAdminPending["security.reports_close"] and
		ChaosAdminPending["security.antibot_score"], "admin panel actions")

	local alice = mk(1, "Alice")
	local bob = mk(2, "Bob")
	local gm = mk(3, "Gamemaster", 6)
	events.ChaosAntibotLogin.onLogin(alice)
	events.ChaosAntibotLogin.onLogin(bob)
	events.ChaosAntibotLogin.onLogin(gm)
	check(alice.events.ChaosAntibotHealth and alice.events.ChaosAntibotExtended, "events registered at login")
	check(not gm.events.ChaosAntibotHealth and AB.states[3] == nil, "staff are not sampled")
	-- heals and hits through the healthchange event
	local h = events.ChaosAntibotHealth.onHealthChange
	local a1, a2, a3, a4 = h(alice, nil, 50, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
	eq(a1, 50, "damage passed through unchanged")
	eq(a2, COMBAT_PHYSICALDAMAGE, "type passed through")
	h(alice, alice, 100, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL)
	check(AB.states[1].kinds.heal ~= nil, "own heal is an action")
	eq(AB.states[1].reacts.n, 1, "and a reaction after the hit")
	h(alice, bob, 30, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
	check(AB.states[1].lastPvp ~= nil, "a hit from a player marks PvP")
	-- spell casts with the engine's cooldowns (patch 0008): a cast the moment it is ready gives no interval
	local E = ChaosSpellEvents
	local clock = 1000000
	os.mtime = function() return clock end
	local function cast(at)
		clock = at
		eq(E.onSpellCooldown(alice, "Strike", 77, 1, true, "spell", 2000), 2000, "cooldown passed through")
		E.onSpellCooldown(alice, "Strike", 77, 1, true, "group", 2000)
		E.onSpellCast(alice, "Strike", 77, 1, true, 20, 0)
	end
	cast(1000000)
	cast(1002050) -- held hotkey: 50 ms after ready
	eq(AB.states[1].kinds.s77.gaps.n, 0, "cast on the cooldown: no interval")
	cast(1005000) -- 950 ms after ready: a choice, an interval
	eq(AB.states[1].kinds.s77.gaps.n, 1, "cast later than ready: an interval")
	eq(K.last(AB.states[1].kinds.s77.gaps), 2950, "the interval")
	os.mtime = function() return os.time() * 1000 end
	-- loot moved by hand out of a corpse
	local corpse = {isItem = function() return true end, isContainer = function() return true end, getId = function() return 3058 end}
	callbacks.onItemMoved(alice, {}, 1, {x = 100, y = 100, z = 7}, {x = CONTAINER_POSITION, y = 64, z = 0}, corpse, alice)
	check(AB.states[1].lastLoot ~= nil, "loot move recorded")
	-- a forced check: the modal goes out with client ids
	sent = {}
	AB.states[1].lastPvp = nil
	local ok = AB.forceCheck(alice)
	check(ok, "staff check sent")
	local msg = sent[#sent]
	eq(msg and msg.action, "check", "check payload")
	eq(msg and msg.op, 211, "on opcode 211")
	check(msg and msg.data.o[1].c > 1000, "client ids")
	eq(select(2, AB.forceCheck(gm)), "Staff characters are not checked.", "no check for staff")
	-- right answer
	local c = AB.states[1].check.active
	events.ChaosAntibotExtended.onExtendedOpcode(alice, 211, "x")
	Chaos.decode = function(b) return b end
	ChaosRateLimit = nil
	events.ChaosAntibotExtended.onExtendedOpcode(alice, 211, {action = "answer", data = {t = c.token, k = c.answer}})
	eq(sent[#sent].action, "checkResult", "result sent")
	eq(sent[#sent].data.ok, true, "passed")
	eq(AB.states[1].check.active, nil, "check closed")
	check(async[#async]:find("check_pass", 1, true), "pass logged")
	check(alice.storage[7100890] and alice.storage[7100890] > 0, "last check stored")
	-- unanswered: temple + log
	AB.states[2].lastPvp = nil
	AB.forceCheck(bob)
	bob.pos = {x = 300, y = 300, z = 7}
	local deadline = AB.states[2].check.active.deadline
	local realTime = os.time
	os.time = function() return deadline + 5 end
	AB.tick()
	os.time = realTime
	eq(bob.pos.x, 50, "failed check: temple")
	check(async[#async]:find("check_fail", 1, true) and async[#async]:find("no answer", 1, true), "failure logged")
	check(gm.msgs[#gm.msgs]:find("[Anti-bot] check_fail: Bob", 1, true), "online staff told")
	-- logout during a check: no failure, owed for the next login
	AB.states[1].check.graceUntil = 0
	AB.forceCheck(alice)
	events.ChaosAntibotLogout.onLogout(alice)
	eq(AB.states[1].check.active, nil, "logout closes the check")
	eq(AB.states[1].check.owed, true, "owed for the next login")
	events.ChaosAntibotLogin.onLogin(alice)

	-- reports: chat lines, submit, limits, staff
	RP.onChannelSpeak(bob, "World Chat", TALKTYPE_CHANNEL_Y, "selling stuff")
	sent = {}
	events.ChaosAntibotExtended.onExtendedOpcode(alice, 211, {action = "reportOpen", data = {name = "Bob"}})
	eq(sent[#sent].action, "reportOpen", "dialog opened")
	eq(sent[#sent].data.reasons[1].k, "botting", "reasons sent")
	events.ChaosAntibotExtended.onExtendedOpcode(alice, 211, {action = "report",
		data = {name = "bob", reason = "botting", note = "same path for hours"}})
	eq(sent[#sent].action, "reportResult", "report answered")
	eq(sent[#sent].data.ok, true, "report stored: " .. tostring(sent[#sent].data.text))
	local ins = queries[#queries]
	check(ins:find("INSERT INTO `chaos_reports`", 1, true), "report row")
	check(ins:find("'Bob'", 1, true) and ins:find("'botting'", 1, true), "canonical target name and reason")
	check(ins:find("World Chat: selling stuff", 1, true), "public chat lines stored")
	events.ChaosAntibotExtended.onExtendedOpcode(alice, 211, {action = "report", data = {name = "Bob", reason = "scam"}})
	eq(sent[#sent].data.ok, false, "second report refused")
	eq(sent[#sent].data.text, R.errors.cooldown, "cooldown text")
	events.ChaosAntibotExtended.onExtendedOpcode(bob, 211, {action = "report", data = {name = "Gamemaster", reason = "scam"}})
	eq(sent[#sent].data.text, R.errors.staff, "staff cannot be reported")
	events.ChaosAntibotExtended.onExtendedOpcode(bob, 211, {action = "report", data = {name = "Nobody", reason = "scam"}})
	eq(sent[#sent].data.text, R.errors.unknown, "unknown target")
	-- the staff command
	eq(talks["/reports"].onSay(alice, "/reports", "list"), true, "/reports is plain chat for players")
	local realSelect = Chaos.select
	Chaos.select = function(q) if q:find("chaos_reports", 1, true) then return {{id = 1, status = "open"}} end return {} end
	talks["/reports"].onSay(gm, "/reports", "close 1, checked, no bot")
	Chaos.select = realSelect
	check(queries[#queries]:find("SET `status` = 'closed'", 1, true) and queries[#queries]:find("'checked, no bot'", 1, true),
		"staff close with a note")
	-- leaderboard holds: off by default, then on
	eq(AB.heldClause("p."), "", "no SQL while holds are off")
	local list = {{guid = 1, rank = 1}, {guid = 2, rank = 2}}
	eq(AB.filterRanked(list), list, "ranked list untouched while off")
	Chaos.antibotConfig.log.holdLeaderboards = true
	AB.held = {accounts = {[501] = true}, guids = {[1] = true}, count = 1}
	local f = AB.filterRanked(list)
	eq(#f, 1, "held character left out")
	eq(f[1].guid, 2, "the other stays")
	eq(f[1].rank, 1, "ranks renumbered")
	check(AB.heldClause("p."):find("p.`account_id` NOT IN", 1, true), "ladder SQL clause")
	Chaos.antibotConfig.log.holdLeaderboards = false
	Chaos.send = oldSend
end

print(string.format("antibot_test: %d checks, %d failed", count, failures))
if failures > 0 then
	os.exit(1)
end
