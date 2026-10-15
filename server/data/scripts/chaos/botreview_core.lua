-- Bot review: pure logic (no engine API). botreview.lua feeds it from cheap hooks and from the antibot.lua signals;
-- tests/botreview_test.lua runs it on synthetic traces of humans, helper users and bots. Numbers: botreview_config.lua.
-- Overview: server/README.md "Bot detection".
--
-- Per character a small bounded state (about 250 numbers and up to 400 short strings per hour of route, 24 hours):
--   heals     [HP now, HP before the last hits] of own heals after a hit (the HP threshold signal)
--   retarget  latencies from a kill to the first attack on another monster
--   acts      the last action times (ms) for the synchrony check between characters of one IP or party
--   hours     per hour of the last 24: active minutes, chat lines, looks, turns, item moves, short pauses
--   route     per hour of the last 24: the set of 3-cell keys walked
--   checks    the last presence checks: result, whether the character kept acting
--   day       hourly score sums of the current day, its best evaluation (signals and explanations)
-- New signals: heal, retarget, silence, route, presence, cluster. The antibot.lua signals (timing, reaction, loot, loop,
-- nonstop) come in as numbers. Score: botreview_config.lua header.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosBotReviewCore = ChaosBotReviewCore or {}
local BR = ChaosBotReviewCore

BR.AUTOMATION = {"timing", "reaction", "loot", "heal", "retarget"}
BR.UNATTENDED = {"nonstop", "silence", "route", "loop", "presence", "cluster"}
BR.NOISE = {"chat", "look", "turn", "inv", "idle"}
BR.STATUSES = {new = true, reviewed = true, false_positive = true, escalated = true}
BR.ACTIONS = {reviewed = true, false_positive = true, escalate = true, check = true, note = true}

-- ---------------------------------------------------------------- helpers
local function clamp01(x)
	if x ~= x then
		return 0
	end
	return x < 0 and 0 or (x > 1 and 1 or x)
end

function BR.ramp(x, from, to)
	if from == to then
		return x >= to and 1 or 0
	end
	return clamp01((x - from) / (to - from))
end

function BR.ring(size)
	return {size = size, n = 0, head = 0, v = {}}
end

function BR.push(r, x)
	r.head = r.head % r.size + 1
	r.v[r.head] = x
	if r.n < r.size then
		r.n = r.n + 1
	end
end

function BR.values(r)
	local out = {}
	local start = r.head - r.n
	for i = 1, r.n do
		out[i] = r.v[(start + i - 1) % r.size + 1]
	end
	return out
end

local function median(list)
	local c = {}
	for i = 1, #list do
		c[i] = list[i]
	end
	table.sort(c)
	local n = #c
	if n == 0 then
		return 0
	end
	if n % 2 == 1 then
		return c[(n + 1) / 2]
	end
	return (c[n / 2] + c[n / 2 + 1]) / 2
end
BR.median = median

function BR.robustCv(list)
	local m = median(list)
	if m <= 0 then
		return 0
	end
	local dev = {}
	for i = 1, #list do
		dev[i] = math.abs(list[i] - m)
	end
	return 1.4826 * median(dev) / m
end

-- noisy-or: 1 - prod(1 - w x s)
function BR.noisyOr(signals, weights, names)
	local p = 1
	for _, name in ipairs(names) do
		p = p * (1 - clamp01((weights[name] or 0) * (signals[name] or 0)))
	end
	return 1 - p
end

-- ---------------------------------------------------------------- state
function BR.newState(cfg, nowS)
	return {
		heals = BR.ring(cfg.heal.ring), hits = {}, -- hits: the last few {ms, hpBefore}
		retarget = BR.ring(cfg.retarget.ring), lastKill = nil, lastTarget = nil,
		acts = BR.ring(cfg.cluster.ring),
		hours = {}, -- [slot 0..23] = {stamp = absolute hour, active, chat, look, turn, inv, idle}
		route = {}, -- [slot] = {stamp, keys = {}, n}
		cellA = nil, cellB = nil, lastMinute = nil, lastActive = nil,
		checks = {}, lastRandomCheck = 0,
		cluster = 0, clusterWith = nil, clusterKind = nil,
		day = nil, lastWriteHour = nil, created = nowS
	}
end

local function hourSlot(st, nowS)
	local hourAbs = math.floor(nowS / 3600)
	local slot = hourAbs % 24
	local h = st.hours[slot]
	if not h or h.stamp ~= hourAbs then
		h = {stamp = hourAbs, active = 0, chat = 0, look = 0, turn = 0, inv = 0, idle = 0}
		st.hours[slot] = h
	end
	return h
end
BR.hourSlot = hourSlot

-- any deliberate activity: counts active minutes and pauses of idleSeconds .. 20 minutes
function BR.activity(st, cfg, nowS)
	local gap = st.lastActive and nowS - st.lastActive or 0
	if gap >= cfg.silence.idleSeconds and gap < 1200 then
		local h = hourSlot(st, nowS)
		h.idle = h.idle + 1
	end
	st.lastActive = nowS
	local minute = math.floor(nowS / 60)
	if minute ~= st.lastMinute then
		st.lastMinute = minute
		local h = hourSlot(st, nowS)
		h.active = h.active + 1
	end
end

-- human noise: kind = chat | look | turn | inv
function BR.noise(st, cfg, kind, nowS)
	local h = hourSlot(st, nowS)
	if h[kind] then
		h[kind] = h[kind] + 1
	end
	BR.activity(st, cfg, nowS)
end

-- ---------------------------------------------------------------- events
-- a hit taken; hpBefore = HP % before it
function BR.onHit(st, cfg, ms, hpBefore)
	local hits = st.hits
	hits[#hits + 1] = {ms, hpBefore}
	if #hits > 4 then
		table.remove(hits, 1)
	end
end

-- an own heal at hp % (before the heal); returns the stored {lo, hi} or nil
function BR.onHeal(st, cfg, ms, hp, nowS)
	if nowS then
		BR.activity(st, cfg, nowS)
	end
	local c = cfg.heal
	if hp >= c.maxPct then
		return nil
	end
	local hi
	for i = #st.hits, 1, -1 do
		local h = st.hits[i]
		if ms - h[1] <= c.lookbackMs and ms >= h[1] then
			hi = math.max(hi or 0, h[2])
		elseif ms - h[1] > c.lookbackMs then
			break
		end
	end
	if not hi or hi <= hp then
		return nil
	end
	local s = {math.floor(hp), math.floor(hi)}
	BR.push(st.heals, s)
	return s
end

function BR.onKill(st, ms)
	st.lastKill = ms
end

-- a combat event of the character against target id `tid` (a monster); returns the retarget latency when stored
function BR.onCombat(st, cfg, ms, tid)
	if tid == st.lastTarget then
		return nil
	end
	st.lastTarget = tid
	local k = st.lastKill
	if not k then
		return nil
	end
	st.lastKill = nil
	local d = ms - k
	if d >= cfg.retarget.minMs and d <= cfg.retarget.windowMs then
		BR.push(st.retarget, d)
		return d
	end
	return nil
end

-- a deliberate action (spell, heal, attack start): the synchrony ring and activity
function BR.onAction(st, cfg, ms, nowS)
	BR.push(st.acts, ms)
	BR.activity(st, cfg, nowS or math.floor(ms / 1000))
end

-- a position sample; fighting = true while the antibot loop rule would skip it. Stores a route key on a cell change.
function BR.onPosition(st, cfg, x, y, z, nowS, fighting)
	local s = cfg.route.cellSize
	local cell = math.floor(x / s) .. ":" .. math.floor(y / s) .. ":" .. z
	if cell == st.cellB or cell == st.moveCell then
		return false
	end
	st.moveCell = cell
	BR.activity(st, cfg, nowS)
	if fighting then
		return false
	end
	local a, b = st.cellA, st.cellB
	st.cellA, st.cellB = b, cell
	if not a or not b then
		return false
	end
	local key = a .. ">" .. b .. ">" .. cell
	local hourAbs = math.floor(nowS / 3600)
	local slot = hourAbs % 24
	local r = st.route[slot]
	if not r or r.stamp ~= hourAbs then
		r = {stamp = hourAbs, keys = {}, n = 0}
		st.route[slot] = r
	end
	if not r.keys[key] and r.n < cfg.route.maxPerHour then
		r.keys[key] = true
		r.n = r.n + 1
	end
	return true
end

-- a presence check ended: result "pass" | "fail"; acted = the character acted during the check
function BR.onCheck(st, nowS, result, acted, random)
	local list = st.checks
	list[#list + 1] = {t = nowS, result = result, acted = acted and true or false, random = random and true or false}
	if #list > 8 then
		table.remove(list, 1)
	end
end

-- ---------------------------------------------------------------- signals
function BR.healSignal(st, cfg)
	local c = cfg.heal
	local list = BR.values(st.heals)
	if #list < c.minSamples then
		return 0, {n = #list}
	end
	local diff = {}
	for i = 0, 102 do
		diff[i] = 0
	end
	for _, s in ipairs(list) do
		local lo, hi = math.max(0, math.min(100, s[1])), math.max(0, math.min(100, s[2]))
		diff[lo] = diff[lo] + 1
		diff[hi + 1] = diff[hi + 1] - 1
	end
	local run, best, bestT = 0, 0, 0
	for t = 0, 100 do
		run = run + diff[t]
		if run > best then
			best, bestT = run, t
		end
	end
	local share = best / #list
	return BR.ramp(share, c.shareFrom, c.shareTo), {n = #list, share = share, pct = bestT}
end

function BR.retargetSignal(st, cfg)
	local c = cfg.retarget
	local list = BR.values(st.retarget)
	if #list < c.minSamples then
		return 0, {n = #list}
	end
	local cv = BR.robustCv(list)
	return BR.ramp(cv, c.cvHuman, c.cvBot), {n = #list, cv = cv, median = median(list)}
end

-- active hours and weighted noise of the last 24 hours
function BR.noiseTotals(st, cfg, nowS)
	local hourNow = math.floor(nowS / 3600)
	local active, noise = 0, 0
	local counts = {chat = 0, look = 0, turn = 0, inv = 0, idle = 0}
	for slot = 0, 23 do
		local h = st.hours[slot]
		if h and hourNow - h.stamp >= 0 and hourNow - h.stamp < 24 then
			active = active + h.active
			for _, k in ipairs(BR.NOISE) do
				counts[k] = counts[k] + h[k]
				noise = noise + h[k] * (cfg.silence.weights[k] or 0)
			end
		end
	end
	return active / 60, noise, counts
end

function BR.silenceSignal(st, cfg, nowS)
	local c = cfg.silence
	local hours, noise, counts = BR.noiseTotals(st, cfg, nowS)
	local info = {hours = hours, counts = counts}
	if hours < c.minActiveHours then
		return 0, info
	end
	local rate = noise / hours
	info.rate = rate
	return BR.ramp(rate, c.rateHuman, c.rateBot), info
end

function BR.jaccard(a, b)
	local inter, na, nb = 0, 0, 0
	for k in pairs(a) do
		na = na + 1
		if b[k] then
			inter = inter + 1
		end
	end
	for _ in pairs(b) do
		nb = nb + 1
	end
	local union = na + nb - inter
	return union > 0 and inter / union or 0
end

-- the longest run of consecutive same-route hours in the last 24
function BR.routeSignal(st, cfg, nowS)
	local c = cfg.route
	local hourNow = math.floor(nowS / 3600)
	local best, run, bestSim, prev = 0, 0, 0, nil
	local sims = {}
	for h = hourNow - 23, hourNow do
		local r = st.route[h % 24]
		if r and r.stamp == h and r.n >= c.minPerHour then
			if prev then
				-- a finished hour keeps its similarity with the hour before (only the current hour is computed again)
				local sim
				if r.simWith == prev.stamp and r.simN == r.n and prev.simOwnN == prev.n then
					sim = r.sim
				else
					sim = BR.jaccard(prev.keys, r.keys)
					r.sim, r.simWith, r.simN, prev.simOwnN = sim, prev.stamp, r.n, prev.n
				end
				sims[#sims + 1] = sim
				if sim >= c.simAt then
					run = (run == 0) and 2 or run + 1
					if sim > bestSim then
						bestSim = sim
					end
				else
					run = 0
				end
			end
			prev = r
		else
			prev, run = nil, 0
		end
		if run > best then
			best = run
		end
	end
	return BR.ramp(best, c.fromHours, c.toHours), {hours = best, sim = bestSim, pairs = #sims}
end

function BR.presenceSignal(st, cfg, nowS)
	local c = cfg.presence
	local since = nowS - c.windowHours * 3600
	local s, info, passed = 0, {checks = 0}, false
	for _, ch in ipairs(st.checks) do
		if ch.t >= since then
			info.checks = info.checks + 1
			if ch.result == "pass" then
				passed = true
				info.passed = (info.passed or 0) + 1
			else
				info.failed = (info.failed or 0) + 1
				local v = ch.acted and c.ignoredActive or c.ignoredIdle
				if v > s then
					s = v
					info.acted = ch.acted
				end
			end
		end
	end
	info.passedRecently = passed
	return s, info
end

-- excess synchrony of the actions in `a` with those in `b` (ascending ms lists): nil when too few
function BR.syncExcess(a, b, cfg)
	local c = cfg.cluster
	if #a < c.minActions or #b < c.minActions then
		return nil
	end
	local lo, hi = math.max(a[1], b[1]), math.min(a[#a], b[#b])
	if hi - lo < 1000 then
		return nil
	end
	local w = c.windowMs
	local j, matched, na, nb = 1, 0, 0, 0
	for i = 1, #a do
		local t = a[i]
		if t >= lo and t <= hi then
			na = na + 1
			while j <= #b and b[j] < t - w do
				j = j + 1
			end
			if j <= #b and b[j] <= t + w then
				matched = matched + 1
			end
		end
	end
	for i = 1, #b do
		if b[i] >= lo and b[i] <= hi then
			nb = nb + 1
		end
	end
	if na < c.minActions / 2 or nb < c.minActions / 2 then
		return nil
	end
	local expected = math.min(0.95, 1 - math.exp(-2 * w * nb / (hi - lo)))
	local observed = matched / na
	return math.max(0, (observed - expected) / (1 - expected)), observed, expected
end

-- both directions; nil when either has too few actions
function BR.pairSync(a, b, cfg)
	local x = BR.syncExcess(a, b, cfg)
	local y = BR.syncExcess(b, a, cfg)
	if not x or not y then
		return nil
	end
	return (x + y) / 2
end

-- The cluster pass in slices (botreview.lua runs a few pairs per tick, so no tick stalls the game loop):
-- jobs = BR.clusterJobs(groups, cfg); BR.clusterRun(jobs, i, j, results, cfg) for slices; BR.clusterApply(results, states).
-- groups = list of lists of {guid, name, acts (ascending ms)}, each list with kind = "ip" | "party".
function BR.clusterJobs(groups, cfg)
	local jobs = {}
	for _, g in ipairs(groups) do
		local n = math.min(#g, cfg.cluster.maxGroup)
		for i = 1, n - 1 do
			for j = i + 1, n do
				jobs[#jobs + 1] = {a = g[i], b = g[j], kind = g.kind}
			end
		end
	end
	return jobs
end

-- results: guid -> {sync, with, kind} (the highest per character)
function BR.clusterRun(jobs, from, to, results, cfg)
	for k = from, math.min(to, #jobs) do
		local job = jobs[k]
		local s = BR.pairSync(job.a.acts, job.b.acts, cfg)
		if s then
			for _, pr in ipairs({{job.a, job.b}, {job.b, job.a}}) do
				local r = results[pr[1].guid]
				if not r or s > r.sync then
					results[pr[1].guid] = {sync = s, with = pr[2].name, kind = job.kind}
				end
			end
		end
	end
end

-- every state gets its result, or 0 when it had no partner this pass
function BR.clusterApply(results, states)
	for guid, st in pairs(states) do
		local r = results[guid]
		st.cluster, st.clusterWith, st.clusterKind = r and r.sync or 0, r and r.with or nil, r and r.kind or nil
	end
end

-- the whole pass at once (tests); returns the number of pairs compared
function BR.clusterPass(groups, states, cfg)
	local jobs = BR.clusterJobs(groups, cfg)
	local results = {}
	BR.clusterRun(jobs, 1, #jobs, results, cfg)
	BR.clusterApply(results, states)
	return #jobs
end

function BR.clusterSignal(st, cfg)
	local c = cfg.cluster
	return BR.ramp(st.cluster or 0, c.from, c.to), {sync = st.cluster or 0, with = st.clusterWith, kind = st.clusterKind}
end

-- ---------------------------------------------------------------- score
-- ab = the antibot.lua signals {timing, reaction, loot, loop, nonstop} (0..1), abInfo their details (optional)
function BR.signals(st, cfg, ab, nowS, abInfo)
	local s, info = {}, {}
	ab, abInfo = ab or {}, abInfo or {}
	for _, k in ipairs({"timing", "reaction", "loot", "loop", "nonstop"}) do
		s[k] = clamp01(tonumber(ab[k]) or 0)
		info[k] = abInfo[k] or {}
	end
	s.heal, info.heal = BR.healSignal(st, cfg)
	s.retarget, info.retarget = BR.retargetSignal(st, cfg)
	s.silence, info.silence = BR.silenceSignal(st, cfg, nowS)
	s.route, info.route = BR.routeSignal(st, cfg, nowS)
	s.presence, info.presence = BR.presenceSignal(st, cfg, nowS)
	s.cluster, info.cluster = BR.clusterSignal(st, cfg)
	return s, info
end

-- score 0..100, A, U, elevated unattended count
function BR.combine(s, cfg, info)
	local A = BR.noisyOr(s, cfg.automation, BR.AUTOMATION)
	local U = BR.noisyOr(s, cfg.unattended, BR.UNATTENDED)
	local elevated = 0
	for _, k in ipairs(BR.UNATTENDED) do
		if (s[k] or 0) >= cfg.elevatedAt then
			elevated = elevated + 1
		end
	end
	if elevated < cfg.unattendedMinElevated then
		U = U * cfg.unattendedSingleFactor
	end
	if info and info.presence and info.presence.passedRecently then
		U = U * cfg.presence.passFactor
	end
	local score = 100 * U * (cfg.automationBase + (1 - cfg.automationBase) * A)
	return score, A, U, elevated
end

local function f2(x)
	return string.format("%.2f", x or 0)
end

-- short explanations of the signals at 0.3 or more, strongest first (for staff; no private data)
function BR.explain(s, info, cfg, A, U)
	local items = {}
	local function add(name, text)
		items[#items + 1] = {v = s[name] or 0, text = name .. " " .. f2(s[name]) .. ": " .. text}
	end
	local i = info or {}
	local t = i.timing or {}
	local r = i.reaction or {}
	local l = i.loot or {}
	local lp = i.loop or {}
	local ns = i.nonstop or {}
	local h = i.heal or {}
	local rt = i.retarget or {}
	local si = i.silence or {}
	local ro = i.route or {}
	local pr = i.presence or {}
	local cl = i.cluster or {}
	local texts = {
		timing = function() return string.format("one action at a fixed rhythm (spread %s over %d intervals)", f2(t.cv), t.n or 0) end,
		reaction = function() return string.format("heals right after hits (%d%% instant, spread %d ms)", math.floor((r.fast or 0) * 100), math.floor(r.sd or 0)) end,
		loot = function() return string.format("looting at a fixed pace (spread %s)", f2(l.cv)) end,
		heal = function() return string.format("%d%% of %d heals fit one HP threshold (%d%%)", math.floor((h.share or 0) * 100), h.n or 0, h.pct or 0) end,
		retarget = function() return string.format("next target after a kill in %d ms, spread %s (%d kills)", math.floor(rt.median or 0), f2(rt.cv), rt.n or 0) end,
		nonstop = function() return string.format("%.1f h without a break, %.1f active hours in 24 h", ns.streak or 0, ns.day or 0) end,
		silence = function()
			local c = si.counts or {}
			return string.format("%.1f noise per active hour over %.1f h (chat %d, looks %d, turns %d, item moves %d, pauses %d)",
				si.rate or 0, si.hours or 0, c.chat or 0, c.look or 0, c.turn or 0, c.inv or 0, c.idle or 0)
		end,
		route = function() return string.format("the same route %d hours in a row (similarity up to %s)", ro.hours or 0, f2(ro.sim)) end,
		loop = function() return string.format("a %s-cell loop walked again and again (match %s)", tostring(lp.period or "?"), f2(lp.match)) end,
		presence = function() return pr.acted and "missed a presence check while still acting" or "missed a presence check (idle)" end,
		cluster = function() return string.format("acts in step with %s (same %s), excess %s", tostring(cl.with or "?"), cl.kind == "party" and "party" or "connection", f2(cl.sync)) end
	}
	for _, name in ipairs({"timing", "reaction", "loot", "heal", "retarget", "nonstop", "silence", "route", "loop", "presence", "cluster"}) do
		if (s[name] or 0) >= 0.3 then
			add(name, texts[name]())
		end
	end
	table.sort(items, function(a, b)
		if a.v ~= b.v then
			return a.v > b.v
		end
		return a.text < b.text
	end)
	local out = {}
	for k, it in ipairs(items) do
		out[k] = it.text
	end
	if A and U then
		if A >= 0.5 and U < 0.3 then
			out[#out + 1] = "automation without unattended signs: typical for the allowed client helper"
		end
		if pr.passedRecently then
			out[#out + 1] = "passed a presence check in the last 24 h"
		end
	end
	return out
end

function BR.evaluate(st, cfg, ab, nowS, abInfo)
	local s, info = BR.signals(st, cfg, ab, nowS, abInfo)
	local score, A, U, elevated = BR.combine(s, cfg, info)
	st.signals, st.info, st.score, st.A, st.U = s, info, score, A, U
	st.explain = BR.explain(s, info, cfg, A, U)
	return score, s, info, A, U, elevated
end

-- ---------------------------------------------------------------- the day
-- adds one evaluation; returns the finished previous day when the day changed
function BR.addPoint(st, cfg, dayKey, hour, score)
	local finished
	if st.day and st.day.key ~= dayKey then
		finished = st.day
		st.day = nil
	end
	if not st.day then
		st.day = {key = dayKey, hours = {}, best = 0, signals = nil, explain = nil, written = false, flagged = false}
	end
	local d = st.day
	local h = d.hours[hour]
	if not h then
		h = {sum = 0, n = 0}
		d.hours[hour] = h
	end
	h.sum, h.n = h.sum + score, h.n + 1
	if score >= d.best then
		d.best = score
		d.signals = st.signals
		d.explain = st.explain
	end
	return finished
end

-- the daily score: the second highest hourly mean of the hours with enough evaluations; one such hour: half of it
function BR.dayScore(day, cfg)
	if not day then
		return 0
	end
	local means = {}
	for _, h in pairs(day.hours) do
		if h.n >= cfg.minEvalsPerHour then
			means[#means + 1] = h.sum / h.n
		end
	end
	table.sort(means, function(a, b) return a > b end)
	if #means >= 2 then
		return means[2]
	elseif #means == 1 then
		return means[1] * 0.5
	end
	return 0
end

-- "h=score" for every hour with data, ascending
function BR.timeline(day)
	local hours = {}
	for h in pairs(day and day.hours or {}) do
		hours[#hours + 1] = h
	end
	table.sort(hours)
	local parts = {}
	for _, h in ipairs(hours) do
		local x = day.hours[h]
		parts[#parts + 1] = string.format("%d=%d", h, math.floor(x.sum / x.n + 0.5))
	end
	return table.concat(parts, ",")
end

function BR.signalsText(s)
	local parts = {}
	for _, list in ipairs({BR.AUTOMATION, BR.UNATTENDED}) do
		for _, k in ipairs(list) do
			parts[#parts + 1] = k .. "=" .. f2(s and s[k] or 0)
		end
	end
	return table.concat(parts, ";")
end

-- whether this evaluation should write the day row: once per hour, and at once when it becomes flagged
function BR.writeDue(st, cfg, hourAbs)
	local d = st.day
	if not d then
		return false
	end
	local score = BR.dayScore(d, cfg)
	local flagged = score >= cfg.flagAt
	local newlyFlagged = flagged and not d.flagged
	d.flagged = d.flagged or flagged
	if score < cfg.storeAt and not d.written then
		return false, score, false
	end
	if newlyFlagged or st.lastWriteHour ~= hourAbs then
		st.lastWriteHour = hourAbs
		d.written = true
		return true, score, newlyFlagged
	end
	return false, score, false
end

-- ---------------------------------------------------------------- random presence checks
-- ab = the antibot check state {active, owed, lastAt, dayCount, day, graceUntil}; acfg = antibot_config.lua check;
-- u = a uniform random number in [0, 1)
function BR.randomCheckDue(st, cfg, nowS, streakHours, ab, acfg, dayKey, u)
	local r = cfg.presence.random
	if not r.enabled or not acfg or acfg.enabled == false then
		return false
	end
	ab = ab or {}
	if ab.active or ab.owed or (streakHours or 0) < r.afterHours then
		return false
	end
	if nowS - (st.lastRandomCheck or 0) < r.minGapHours * 3600 then
		return false
	end
	if nowS < (ab.graceUntil or 0) or nowS - (ab.lastAt or 0) < (acfg.minGapHours or 4) * 3600 then
		return false
	end
	if ab.day == dayKey and (ab.dayCount or 0) >= (acfg.maxPerDay or 2) then
		return false
	end
	if u >= cfg.evalSeconds / (r.everyActiveHours * 3600) then
		return false
	end
	st.lastRandomCheck = nowS
	return true
end

-- ---------------------------------------------------------------- SQL (esc = db.escapeString)
function BR.upsertSql(cfg, row, esc)
	return string.format("INSERT INTO `%s` (`player_id`, `account_id`, `player_name`, `day`, `score`, `peak`, `flagged`, " ..
		"`signals`, `reasons`, `timeline`, `status`, `created_at`, `updated_at`) VALUES (%d, %d, %s, %d, %d, %d, %d, %s, %s, " ..
		"%s, %s, %d, %d) ON DUPLICATE KEY UPDATE `status` = IF(`status` = 'none' AND VALUES(`flagged`) = 1, 'new', `status`), " ..
		"`score` = VALUES(`score`), `peak` = GREATEST(`peak`, VALUES(`peak`)), `flagged` = GREATEST(`flagged`, " ..
		"VALUES(`flagged`)), `signals` = VALUES(`signals`), `reasons` = VALUES(`reasons`), `timeline` = VALUES(`timeline`), " ..
		"`updated_at` = VALUES(`updated_at`)",
		cfg.tables.daily, row.player_id, row.account_id or 0, esc(row.player_name or ""), row.day, math.floor(row.score + 0.5),
		math.floor(row.peak + 0.5), row.flagged and 1 or 0, esc(row.signals or ""), esc((row.reasons or ""):sub(1, 1000)),
		esc((row.timeline or ""):sub(1, 255)), esc(row.flagged and "new" or "none"), row.now, row.now)
end

function BR.rowOf(st, cfg, day, guid, account, name, nowS)
	local score = BR.dayScore(day, cfg)
	return {player_id = guid, account_id = account, player_name = name, day = day.key, score = score, peak = day.best or 0,
		flagged = score >= cfg.flagAt, signals = BR.signalsText(day.signals),
		reasons = table.concat(day.explain or {}, " | "), timeline = BR.timeline(day), now = nowS}
end

-- the purge: days are YYYYMMDD; cutoffDay(n) = the day key n days ago
function BR.purgeSql(cfg, nowS, cutoffDay)
	local rt, t = cfg.retention, cfg.tables
	return {
		string.format("DELETE FROM `%s` WHERE `day` < %d AND `status` <> 'escalated'", t.daily, cutoffDay(rt.days)),
		string.format("DELETE FROM `%s` WHERE `day` < %d", t.daily, cutoffDay(rt.escalatedDays)),
		string.format("DELETE FROM `%s` WHERE `created_at` < %d", t.actions, nowS - rt.actionDays * 86400)
	}
end

return BR
