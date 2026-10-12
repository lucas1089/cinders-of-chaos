-- Anti-bot behaviour detection and the presence check: pure logic (no engine API). antibot.lua feeds it from the engine,
-- tests/antibot_test.lua runs it on synthetic human and bot traces. Numbers: antibot_config.lua.
--
-- Per character a small state of bounded ring buffers (memory: about 300 numbers per online character):
--   actions   per kind of deliberate action (one spell, own heals): the last time and the intervals (ms); a cast the
--             moment its cooldown ended (a held hotkey) gives no interval
--   reacts    latencies (ms) of isolated own heals after a hit taken
--   loot      gaps (ms) between two items taken out of a corpse in one burst
--   cells     the coarse position cells the character walked through (changes only)
--   activity  start and last moment of the current streak, active minutes per hour of the last 24 hours
-- Signals (0 human-like .. 1 bot-like):
--   timing    robust spread (1.4826 x MAD / median) of the intervals of the most regular kind of action
--   reaction  share of instant reactions times how tight they are
--   loop      the best repeating period of the cell changes (+-1 step), covering several cells, several times
--   loot      coefficient of variation of the looting gaps
--   nonstop   hours of one streak without a break, active hours in the last 24
-- Score: decays with a half-life; each evaluation adds sum(weight x signal), cut to singleFactor when fewer than
-- minElevated signals are elevated, so one odd habit alone never reaches a threshold.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosAntibotCore = ChaosAntibotCore or {}
local K = ChaosAntibotCore

K.SIGNALS = {"timing", "reaction", "loop", "loot", "nonstop"}

-- ---------------------------------------------------------------- helpers
local function clamp01(x)
	if x ~= x then
		return 0
	end
	return x < 0 and 0 or (x > 1 and 1 or x)
end

-- 0 at `from`, 1 at `to` (either direction), clamped
function K.ramp(x, from, to)
	if from == to then
		return x >= to and 1 or 0
	end
	return clamp01((x - from) / (to - from))
end

-- bounded ring buffer: push is O(1), values() returns oldest..newest
function K.ring(size)
	return {size = size, n = 0, head = 0, v = {}}
end

function K.push(r, x)
	r.head = r.head % r.size + 1
	r.v[r.head] = x
	if r.n < r.size then
		r.n = r.n + 1
	end
end

function K.values(r)
	local out = {}
	local start = r.head - r.n
	for i = 1, r.n do
		local idx = (start + i - 1) % r.size + 1
		out[i] = r.v[idx]
	end
	return out
end

function K.last(r)
	return r.n > 0 and r.v[r.head] or nil
end

function K.meanSd(list)
	local n = #list
	if n == 0 then
		return 0, 0
	end
	local sum = 0
	for i = 1, n do
		sum = sum + list[i]
	end
	local mean = sum / n
	local sq = 0
	for i = 1, n do
		local d = list[i] - mean
		sq = sq + d * d
	end
	return mean, math.sqrt(sq / n)
end

function K.cv(list)
	local mean, sd = K.meanSd(list)
	if mean <= 0 then
		return 0
	end
	return sd / mean
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
K.median = median

-- the spread of a normal distribution's CV, but blind to a few outliers (the gap after a fight)
function K.robustCv(list)
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

-- ---------------------------------------------------------------- state
function K.newState(cfg, nowS)
	return {
		kinds = {}, nKinds = 0, -- action kind -> {last = ms, gaps = ring}
		reacts = K.ring(cfg.reaction.ring),
		loot = K.ring(cfg.loot.ring),
		cells = K.ring(cfg.loop.ring),
		lastAction = nil, lastHeal = nil, lastDamage = nil, lastLoot = nil, lastCell = nil,
		streakStart = nil, lastActive = nil, lastMinute = nil,
		hours = {}, hourStamp = {}, -- [0..23] active minutes, the absolute hour they belong to
		score = 0, lastEval = nowS, signals = {}, loopCache = 0, loopAt = nil,
		lastPvp = nil, lastBoss = nil,
		check = {lastAt = 0, day = 0, dayCount = 0, graceUntil = 0, pendingSince = nil, active = nil},
		lastLogAt = nil, lastLogScore = 0
	}
end

-- ---------------------------------------------------------------- activity (nonstop)
function K.markActive(st, cfg, nowS)
	local breakSec = cfg.nonstop.breakMinutes * 60
	if not st.lastActive or nowS - st.lastActive > breakSec then
		st.streakStart = nowS
	end
	st.lastActive = nowS
	local minute = math.floor(nowS / 60)
	if minute ~= st.lastMinute then
		st.lastMinute = minute
		local hourAbs = math.floor(minute / 60)
		local slot = hourAbs % 24
		if st.hourStamp[slot] ~= hourAbs then
			st.hourStamp[slot] = hourAbs
			st.hours[slot] = 0
		end
		st.hours[slot] = st.hours[slot] + 1
	end
end

-- a logout ends nothing by itself: a relog within breakMinutes keeps the streak (antibot.lua keeps the state)
function K.activeHours24(st, nowS)
	local hourNow = math.floor(nowS / 3600)
	local minutes = 0
	for slot = 0, 23 do
		local stamp = st.hourStamp[slot]
		if stamp and hourNow - stamp < 24 and hourNow - stamp >= 0 then
			minutes = minutes + (st.hours[slot] or 0)
		end
	end
	return minutes / 60
end

-- ---------------------------------------------------------------- events
-- whether an interval is a held hotkey on a group cooldown (when the engine did not say: own heals)
function K.cooldownBound(cfg, d)
	local c = cfg.timing
	local k = math.floor(d / c.cooldownMs + 0.5)
	return k >= 1 and math.abs(d - k * c.cooldownMs) <= c.cooldownSlackMs
end

-- a deliberate action of `kind` (a spell id, "heal"). bound = true: cast the moment it was ready again (the engine's
-- cooldowns, antibot.lua), false: not; nil: unknown, the group cooldown rule decides.
function K.onAction(st, cfg, ms, nowS, kind, bound)
	local c = cfg.timing
	if st.lastAction and ms - st.lastAction < c.dedupeMs and (kind or "any") == st.lastKind then
		return false
	end
	st.lastAction, st.lastKind = ms, kind or "any"
	K.markActive(st, cfg, nowS or math.floor(ms / 1000))
	kind = kind or "any"
	local k = st.kinds[kind]
	if not k then
		if st.nKinds >= c.maxKinds then
			-- forget the kind used longest ago (bounded memory)
			local oldKey, oldAt
			for key, v in pairs(st.kinds) do
				if not oldAt or v.last < oldAt then
					oldKey, oldAt = key, v.last
				end
			end
			st.kinds[oldKey] = nil
			st.nKinds = st.nKinds - 1
		end
		k = {last = ms, gaps = K.ring(c.ring)}
		st.kinds[kind] = k
		st.nKinds = st.nKinds + 1
		return true
	end
	local d = ms - k.last
	k.last = ms
	if bound == nil then
		bound = K.cooldownBound(cfg, d)
	end
	if not bound and d >= c.minIntervalMs and d <= c.maxIntervalMs then
		K.push(k.gaps, d)
	end
	return true
end

function K.onDamage(st, cfg, ms)
	st.lastDamage = ms
end

-- an own heal: an action, and a reaction sample when it is isolated and follows a hit
function K.onSelfHeal(st, cfg, ms, nowS)
	local c = cfg.reaction
	local isolated = not st.lastHeal or ms - st.lastHeal >= c.isolateMs
	st.lastHeal = ms
	K.onAction(st, cfg, ms, nowS, "heal")
	if isolated and st.lastDamage and ms >= st.lastDamage and ms - st.lastDamage <= c.windowMs then
		K.push(st.reacts, ms - st.lastDamage)
		return ms - st.lastDamage
	end
	return nil
end

function K.onLootMove(st, cfg, ms, nowS)
	local c = cfg.loot
	if st.lastLoot then
		local gap = ms - st.lastLoot
		if gap >= c.minIntervalMs and gap <= c.burstMs then
			K.push(st.loot, gap)
		end
	end
	st.lastLoot = ms
	K.markActive(st, cfg, nowS or math.floor(ms / 1000))
end

function K.cellOf(cfg, x, y, z)
	local s = cfg.loop.cellSize
	return math.floor(x / s) .. ":" .. math.floor(y / s) .. ":" .. z
end

-- a position sample; returns true when a cell change was stored. While fighting (a hit taken or an action within
-- loop.fightMs) the cell is not stored: chasing and dodging differ every time, the walked route does not.
function K.onPosition(st, cfg, x, y, z, nowS, ms)
	local cell = K.cellOf(cfg, x, y, z)
	if cell == st.lastCell then
		return false
	end
	local first = st.lastCell == nil
	if not first then
		K.markActive(st, cfg, nowS)
	end
	local f = cfg.loop.fightMs
	if ms and f and ((st.lastDamage and ms - st.lastDamage < f) or (st.lastAction and ms - st.lastAction < f)) then
		return false
	end
	st.lastCell = cell
	K.push(st.cells, cell)
	return true
end

-- ---------------------------------------------------------------- signals
-- the most regular kind of action with enough intervals
function K.timingSignal(st, cfg)
	local c = cfg.timing
	local bestCv, info, most = nil, nil, 0
	for kind, k in pairs(st.kinds) do
		local gaps = K.values(k.gaps)
		if #gaps > most then
			most = #gaps
		end
		if #gaps >= c.minSamples then
			local cv = K.robustCv(gaps)
			if not bestCv or cv < bestCv then
				bestCv, info = cv, {n = #gaps, cv = cv, kind = kind}
			end
		end
	end
	if not bestCv then
		return 0, {n = most}
	end
	return K.ramp(bestCv, c.cvHuman, c.cvBot), info
end

function K.reactionSignal(st, cfg)
	local c = cfg.reaction
	local list = K.values(st.reacts)
	if #list < c.minSamples then
		return 0, {n = #list}
	end
	local fast = 0
	for _, v in ipairs(list) do
		if v < c.fastMs then
			fast = fast + 1
		end
	end
	local share = fast / #list
	local _, sd = K.meanSd(list)
	local s = K.ramp(share, c.fastShareFrom, c.fastShareTo) * K.ramp(sd, c.spreadHumanMs, c.spreadBotMs)
	return s, {n = #list, fast = share, sd = sd}
end

local function distinctIn(cells, from, to)
	local seen, n = {}, 0
	for i = from, to do
		local c = cells[i]
		if c and not seen[c] then
			seen[c] = true
			n = n + 1
		end
	end
	return n
end

-- The loop: for every step between two cells (a pair of cell changes) the distance back to its last occurrence.
-- Walking one route again and again gives the lap (or two, three laps when a step was missed once) almost every time,
-- also when a cell is skipped or added now and then (that touches only the steps around it); wandering, turning back
-- and detours spread the distances.
-- match = repeated steps at about 1, 2 or 3 laps of the most common lap / repeated steps; nothing when fewer than
-- minRepeatShare of all steps repeat. Laps under minPeriod (walking between two or three cells) do not count.
function K.loopMatch(cells, cfg)
	local c = cfg.loop
	local n = #cells
	local lastAt, counts, withLag = {}, {}, 0
	local maxLag = c.maxPeriod * 3
	for i = 2, n do
		local key = cells[i - 1] .. "|" .. cells[i]
		local j = lastAt[key]
		if j then
			local lag = i - j
			if lag >= c.minPeriod and lag <= maxLag then
				counts[lag] = (counts[lag] or 0) + 1
				withLag = withLag + 1
			end
		end
		lastAt[key] = i
	end
	if n < 2 or withLag < (n - 1) * c.minRepeatShare then
		return 0, nil
	end
	local best, bestP = 0, nil
	for p = c.minPeriod, c.maxPeriod do
		if counts[p] and n >= p * c.minRepeats then
			local tol = math.max(2, math.floor(p * 0.08))
			local sum = 0
			for k = 1, 3 do
				for q = k * p - k * tol, k * p + k * tol do
					sum = sum + (counts[q] or 0)
				end
			end
			if sum > best then
				best, bestP = sum, p
			end
		end
	end
	if not bestP or distinctIn(cells, n - bestP + 1, n) < c.minDistinct then
		return 0, bestP
	end
	return math.min(1, best / withLag), bestP
end

function K.loopSignal(st, cfg, nowS)
	local c = cfg.loop
	if st.loopAt and nowS and nowS - st.loopAt < c.everySeconds then
		return st.loopCache, st.loopInfo or {}
	end
	local cells = K.values(st.cells)
	local s, info = 0, {n = #cells}
	if #cells >= c.minTransitions then
		local m, p = K.loopMatch(cells, cfg)
		info.match, info.period = m, p
		s = K.ramp(m, c.matchFrom, c.matchTo)
	end
	st.loopAt, st.loopCache, st.loopInfo = nowS, s, info
	return s, info
end

function K.lootSignal(st, cfg)
	local c = cfg.loot
	local list = K.values(st.loot)
	if #list < c.minSamples then
		return 0, {n = #list}
	end
	local cv = K.cv(list)
	return K.ramp(cv, c.cvHuman, c.cvBot), {n = #list, cv = cv}
end

function K.nonstopSignal(st, cfg, nowS)
	local c = cfg.nonstop
	if not st.lastActive or nowS - st.lastActive > c.breakMinutes * 60 then
		return 0, {streak = 0, day = K.activeHours24(st, nowS)}
	end
	local streak = (st.lastActive - (st.streakStart or st.lastActive)) / 3600
	local day = K.activeHours24(st, nowS)
	local s = math.max(K.ramp(streak, c.streakFromHours, c.streakToHours), K.ramp(day, c.dayFromHours, c.dayToHours))
	return s, {streak = streak, day = day}
end

-- ---------------------------------------------------------------- score
function K.signals(st, cfg, nowS)
	local out, info = {}, {}
	out.timing, info.timing = K.timingSignal(st, cfg)
	out.reaction, info.reaction = K.reactionSignal(st, cfg)
	out.loop, info.loop = K.loopSignal(st, cfg, nowS)
	out.loot, info.loot = K.lootSignal(st, cfg)
	out.nonstop, info.nonstop = K.nonstopSignal(st, cfg, nowS)
	return out, info
end

-- the add of one evaluation from the signals
function K.combine(signals, cfg)
	local add, elevated = 0, 0
	for _, name in ipairs(K.SIGNALS) do
		local s = signals[name] or 0
		add = add + (cfg.weights[name] or 0) * s
		if s >= cfg.elevatedAt then
			elevated = elevated + 1
		end
	end
	if elevated < cfg.minElevated then
		add = add * cfg.singleFactor
	end
	return add, elevated
end

-- recompute signals, decay and add; returns the score, the signals and their details
function K.evaluate(st, cfg, nowS)
	local signals, info = K.signals(st, cfg, nowS)
	local add, elevated = K.combine(signals, cfg)
	local dt = math.max(0, nowS - (st.lastEval or nowS))
	local step = cfg.evalSeconds
	st.score = st.score * (0.5 ^ (dt / (cfg.halfLifeMinutes * 60)))
	-- an evaluation that came late (server lag, a relog) adds at most two steps' worth
	st.score = math.min(cfg.maxScore, st.score + add * math.min(2, dt > 0 and dt / step or 1))
	st.lastEval = nowS
	st.signals, st.info, st.elevated = signals, info, elevated
	return st.score, signals, info, elevated
end

-- the steady score a constant add reaches (used by the docs and the tests)
function K.steadyScore(cfg, add)
	local decay = 0.5 ^ (cfg.evalSeconds / (cfg.halfLifeMinutes * 60))
	return add / (1 - decay)
end

-- ---------------------------------------------------------------- decisions
-- ctx = {pvp = bool, boss = bool, busy = bool}. Returns "check", "defer" or nil, and whether to write a log entry.
function K.decide(st, cfg, nowS, ctx, dayKey)
	ctx = ctx or {}
	local ch, cc = st.check, cfg.check
	local action
	if cc.enabled and not ch.active and st.score >= cc.at then
		if ch.day ~= dayKey then
			ch.day, ch.dayCount = dayKey, 0
		end
		local allowed = nowS - (ch.lastAt or 0) >= cc.minGapHours * 3600 and ch.dayCount < cc.maxPerDay and
			nowS >= (ch.graceUntil or 0)
		if allowed then
			if ctx.pvp or ctx.boss or ctx.busy then
				if not ch.pendingSince then
					ch.pendingSince = nowS
				end
				if nowS - ch.pendingSince > cc.deferMaxMinutes * 60 then
					ch.pendingSince = nil
					ch.lastAt = nowS -- dropped: the gap applies as if it had run, the score asks again later
				else
					action = "defer"
				end
			else
				action = "check"
				ch.pendingSince = nil
			end
		end
	end
	local log = false
	local lc = cfg.log
	if st.score >= lc.at then
		if not st.lastLogAt or nowS - st.lastLogAt >= lc.cooldownHours * 3600 or st.score >= 2 * (st.lastLogScore or 0) then
			log = true
		end
	end
	return action, log
end

function K.markLogged(st, nowS)
	st.lastLogAt, st.lastLogScore = nowS, st.score
end

-- ---------------------------------------------------------------- the presence check
local ALNUM = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"

-- rng(n) -> integer 1..n
function K.token(rng, len)
	local out = {}
	for i = 1, len do
		local k = rng(#ALNUM)
		out[i] = ALNUM:sub(k, k)
	end
	return table.concat(out)
end

-- pick `choices` pool entries, no two of one group; shuffled
function K.pick(pool, choices, rng)
	local idx = {}
	for i = 1, #pool do
		idx[i] = i
	end
	for i = #idx, 2, -1 do
		local j = rng(i)
		idx[i], idx[j] = idx[j], idx[i]
	end
	local out, groups = {}, {}
	for _, i in ipairs(idx) do
		local e = pool[i]
		if not e.group or not groups[e.group] then
			out[#out + 1] = e
			if e.group then
				groups[e.group] = true
			end
			if #out == choices then
				break
			end
		end
	end
	return out
end

-- a new challenge on st.check.active; attempt 1 is the first picture, 2 the retry
function K.newChallenge(st, cfg, rng, nowS, attempt)
	local cc = cfg.check
	local picked = K.pick(cc.pool, cc.choices, rng)
	local options, keys = {}, {}
	for i, e in ipairs(picked) do
		local key
		repeat
			key = K.token(rng, 6)
		until not keys[key]
		keys[key] = true
		options[i] = {key = key, id = e.id, word = e.word}
	end
	local target = options[rng(#options)]
	local prev = st.check.active
	local deadline = nowS + cc.timeLimitSeconds
	if prev and attempt and attempt > 1 then
		deadline = math.max(prev.deadline, nowS + cc.retrySeconds)
	end
	local c = {token = K.token(rng, 10), word = target.word, answer = target.key, options = options,
		attempt = attempt or 1, started = prev and prev.started or nowS, deadline = deadline}
	st.check.active = c
	if not prev then
		st.check.lastAt = nowS
		st.check.dayCount = (st.check.dayCount or 0) + 1
		st.check.pendingSince = nil
	end
	return c
end

-- what the client gets: no answer, no words of the options (the client has no item names); clientIdOf(serverId)
function K.payload(c, cfg, nowS, clientIdOf)
	local o = {}
	for i, opt in ipairs(c.options) do
		o[i] = {k = opt.key, c = clientIdOf and clientIdOf(opt.id) or opt.id}
	end
	return {t = c.token, w = c.word, o = o, s = math.max(0, c.deadline - nowS), a = c.attempt,
		r = math.max(0, cfg.check.retries + 1 - c.attempt)}
end

-- returns "pass", "retry" (a new picture follows), "fail", or "stale" (no such check)
function K.answer(st, cfg, token, key, nowS)
	local c = st.check.active
	if not c or c.token ~= token then
		return "stale"
	end
	if nowS > c.deadline then
		return "fail"
	end
	if key == c.answer then
		return "pass"
	end
	if c.attempt <= cfg.check.retries then
		return "retry"
	end
	return "fail"
end

-- "Another picture": the retry without a wrong click; nil when used up
function K.canRetry(st, cfg, token)
	local c = st.check.active
	return c ~= nil and c.token == token and c.attempt <= cfg.check.retries
end

function K.timedOut(st, nowS)
	local c = st.check.active
	return c ~= nil and nowS > c.deadline
end

-- close the check: "pass" lowers the score and starts the grace time, "fail" raises it
function K.finish(st, cfg, result, nowS)
	local cc = cfg.check
	st.check.active = nil
	st.check.pendingSince = nil
	if result == "pass" then
		st.score = st.score * cc.successFactor
		st.check.graceUntil = nowS + cc.graceHours * 3600
	elseif result == "fail" then
		st.score = math.min(cfg.maxScore, st.score + cc.failPenalty)
	end
	return st.score
end

-- one line for the staff log: score and the signals with their numbers
function K.summary(st)
	local parts = {string.format("score %.0f", st.score or 0)}
	local s, info = st.signals or {}, st.info or {}
	for _, name in ipairs(K.SIGNALS) do
		local i = info[name] or {}
		local extra = ""
		if name == "timing" or name == "loot" then
			extra = i.cv and string.format(" cv %.3f n %d", i.cv, i.n or 0) or string.format(" n %d", i.n or 0)
		elseif name == "reaction" then
			extra = i.sd and string.format(" fast %.2f sd %.0f n %d", i.fast or 0, i.sd, i.n or 0) or
				string.format(" n %d", i.n or 0)
		elseif name == "loop" then
			extra = i.match and string.format(" match %.2f period %s", i.match, tostring(i.period)) or
				string.format(" n %d", i.n or 0)
		elseif name == "nonstop" then
			extra = string.format(" streak %.1fh day %.1fh", i.streak or 0, i.day or 0)
		end
		parts[#parts + 1] = string.format("%s %.2f%s", name, s[name] or 0, extra)
	end
	return table.concat(parts, "; ")
end

return K
