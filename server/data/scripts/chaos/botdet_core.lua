-- Bot detection events and scores: pure logic (no engine API; tests/botdet_test.lua). The engine glue is botdet.lua, the
-- numbers are botdet_config.lua, the design and the policy questions are docs/BOT_DETECTION.md.
--
-- Per character a state holds bounded rings of what was seen (position changes, intervals between the same spell, hit point
-- % at heals, reaction times, activity minutes) and the rows that are not written yet. K.analyze runs the six heuristics
-- over the rings and returns the scores with the numbers behind each one:
--   route        the same circuit of map cells again and again                       weight 30
--   regularity   the same spell at a fixed delay (coefficient of variation)          weight 25
--   reaction     the first attack on a creature right after it came into view        weight 20
--   heal         the heals always at the same hit point %                            weight 15
--   session      hours without a pause, hours with an action in a day                weight 10
--   path         almost every step comes from a long path command: a bonus only
-- A score is 0 (human-like) .. 100 (bot-like); a heuristic without enough samples has no score and its weight is left out
-- (the total is cut when too little weight has data). Nothing here acts on a character. Lua 5.1 / LuaJIT and 5.3 compatible.
ChaosBotdetCore = ChaosBotdetCore or {}
local K = ChaosBotdetCore

local floor, min, max, sqrt, abs = math.floor, math.min, math.max, math.sqrt, math.abs

local function clamp01(v)
	if v < 0 then
		return 0
	end
	if v > 1 then
		return 1
	end
	return v
end

-- 0 at `from`, 1 at `to` (either direction), linear between
local function ramp(v, from, to)
	if from == to then
		return v >= to and 1 or 0
	end
	return clamp01((v - from) / (to - from))
end

local function round(v)
	return floor(v + 0.5)
end

-- ---------------------------------------------------------------- rings
local function ringNew(cap)
	return {cap = cap, n = 0, a = {}, b = {}}
end

local function ringPush(r, v, w)
	r.n = r.n + 1
	local i = (r.n - 1) % r.cap + 1
	r.a[i] = v
	r.b[i] = w
end

-- the kept entries, oldest first (and the parallel second array)
local function ringList(r, from)
	local out, outB = {}, {}
	local first = max(1, r.n - r.cap + 1, from or 1)
	for k = first, r.n do
		local i = (k - 1) % r.cap + 1
		out[#out + 1] = r.a[i]
		outB[#outB + 1] = r.b[i]
	end
	return out, outB
end

local function median(list)
	local n = #list
	if n == 0 then
		return 0
	end
	local c = {}
	for i = 1, n do
		c[i] = list[i]
	end
	table.sort(c)
	if n % 2 == 1 then
		return c[(n + 1) / 2]
	end
	return (c[n / 2] + c[n / 2 + 1]) / 2
end

local function meanStd(list)
	local n = #list
	if n == 0 then
		return 0, 0
	end
	local s = 0
	for i = 1, n do
		s = s + list[i]
	end
	local m = s / n
	local v = 0
	for i = 1, n do
		v = v + (list[i] - m) ^ 2
	end
	return m, sqrt(v / n)
end

K.ringNew, K.ringPush, K.ringList, K.median, K.meanStd, K.ramp = ringNew, ringPush, ringList, median, meanStd, ramp

-- a tile as one number: z, x and y are each below 65536 (z below 16 in this map)
local function posKey(x, y, z)
	return (z * 65536 + x) * 65536 + y
end

local function posParts(key)
	local y = key % 65536
	local r = (key - y) / 65536
	local x = r % 65536
	return x, y, (r - x) / 65536
end
K.posKey, K.posParts = posKey, posParts

-- ---------------------------------------------------------------- the state
function K.newState(cfg, guid, name, now)
	return {
		guid = guid, name = name,
		loginAt = now, idleEnd = now, lastAct = nil,
		pos = ringNew(cfg.rings.pos), posFlushed = 0, lastKey = nil,
		kinds = {}, kindOrder = {},
		heals = ringNew(cfg.rings.heals),
		react = ringNew(cfg.rings.react),
		actMin = {}, -- minute slots: [m % 1440 + 1] = the minute number that had an action
		walk = {k = 0, p = 0, s = 0, fk = 0, fp = 0, fs = 0}, -- totals in the window and the part not written yet
		hours = {}, -- hour index % 4 + 1 = {h = hour index, k, p, s} of the last hours, for the path signal
		lastCastMs = -1e9,
		pend = {spell = {}, heal = {}, react = {}, session = {}},
		tools = {}, extras = {}, integrity = nil -- the client's signals (K.onClient)
	}
end

local function pushPending(st, cfg, kind, text)
	local list = st.pend[kind]
	list[#list + 1] = text
	local cap = cfg.rings.pending
	if #list > cap then
		-- bounded: the oldest half goes (a character that cannot flush must not grow without bound)
		local keep = {}
		for i = floor(cap / 2) + 1, #list do
			keep[#keep + 1] = list[i]
		end
		st.pend[kind] = keep
	end
end

-- any action of the character: ends or extends the stretch without a pause, marks the minute
function K.touch(st, cfg, now)
	local idle = cfg.session.idleSeconds
	if st.lastAct and now - st.lastAct >= idle then
		st.idleEnd = now
		pushPending(st, cfg, "session", string.format("%d,gap,%d", now, now - st.lastAct))
	end
	st.lastAct = now
	local m = floor(now / 60)
	st.actMin[m % 1440 + 1] = m
end

-- one position sample (every second); only a change of tile is kept
function K.onSample(st, cfg, x, y, z, now)
	local key = posKey(x, y, z)
	if key ~= st.lastKey then
		st.lastKey = key
		ringPush(st.pos, key, now)
		K.touch(st, cfg, now)
		return true
	end
	return false
end

-- the engine's counters since the last poll (player:getBotSignals): key steps, path commands and their steps, and the
-- reaction times
function K.onSignals(st, cfg, sig, now)
	if type(sig) ~= "table" then
		return
	end
	local k, p, s = tonumber(sig.keys) or 0, tonumber(sig.paths) or 0, tonumber(sig.pathSteps) or 0
	if k + p + s > 0 then
		local w = st.walk
		w.k, w.p, w.s = w.k + k, w.p + p, w.s + s
		w.fk, w.fp, w.fs = w.fk + k, w.fp + p, w.fs + s
		local h = floor(now / 3600)
		local slot = st.hours[h % 4 + 1]
		if not slot or slot.h ~= h then
			slot = {h = h, k = 0, p = 0, s = 0}
			st.hours[h % 4 + 1] = slot
		end
		slot.k, slot.p, slot.s = slot.k + k, slot.p + p, slot.s + s
		K.touch(st, cfg, now)
	end
	if type(sig.reactions) == "table" then
		for _, r in ipairs(sig.reactions) do
			if type(r) == "table" then
				K.onReact(st, cfg, tonumber(r[1]) or 0, tonumber(r[2]) or -1, now)
			end
		end
	end
end

function K.onReact(st, cfg, creatureId, ms, now)
	if ms >= 0 and ms <= cfg.reaction.maxMs then
		ringPush(st.react, ms, now)
		pushPending(st, cfg, "react", string.format("%d,%d,%d", now, creatureId, floor(ms)))
	end
	K.touch(st, cfg, now)
end

local function kindOf(st, cfg, kind)
	local k = st.kinds[kind]
	if not k then
		if #st.kindOrder >= cfg.rings.kinds then
			local old = table.remove(st.kindOrder, 1)
			st.kinds[old] = nil
		end
		k = {ring = ringNew(cfg.rings.intervals), last = nil}
		st.kinds[kind] = k
		st.kindOrder[#st.kindOrder + 1] = kind
	else
		-- most recently used last
		for i = 1, #st.kindOrder do
			if st.kindOrder[i] == kind then
				table.remove(st.kindOrder, i)
				break
			end
		end
		st.kindOrder[#st.kindOrder + 1] = kind
	end
	return k
end

local function interval(st, cfg, kind, ms, bound)
	local k = kindOf(st, cfg, kind)
	if bound then
		k.last = nil -- a cast the moment the cooldown ended (a held hotkey) says nothing about rhythm
		return
	end
	local r = cfg.regularity
	if k.last then
		local dt = ms - k.last
		if dt >= r.minMs and dt <= r.maxMs then
			ringPush(k.ring, dt)
		end
	end
	k.last = ms
end

-- a spell cast (ChaosSpellEvents "cast"): id, whether it was cast the moment its cooldown ended, hit point and mana %
function K.onCast(st, cfg, nowMs, now, id, bound, hpPct, mpPct)
	st.lastCastMs = nowMs
	interval(st, cfg, "s" .. tostring(id), nowMs, bound)
	pushPending(st, cfg, "spell", string.format("%d,%s,%d,%d,%d", now, tostring(id), round(hpPct or 100), round(mpPct or 100),
		bound and 1 or 0))
	K.touch(st, cfg, now)
end

-- an own heal (healthchange with the character as attacker: spell, rune or potion), hit point % before the heal
function K.onHeal(st, cfg, nowMs, now, hpPct)
	if hpPct < cfg.heal.topUpAt then
		ringPush(st.heals, hpPct, now)
		pushPending(st, cfg, "heal", string.format("%d,%d", now, round(hpPct)))
	end
	-- the heal of a spell (a cast event in the same moment) is the spell's interval, not a potion's
	if nowMs - st.lastCastMs > 80 then
		interval(st, cfg, "p", nowMs, false)
	end
	K.touch(st, cfg, now)
end

function K.onLogin(st, cfg, now)
	pushPending(st, cfg, "session", string.format("%d,login", now))
	st.offlineAt = nil
end

function K.onLogout(st, cfg, now)
	pushPending(st, cfg, "session", string.format("%d,logout", now))
	st.offlineAt = now
end

-- ---------------------------------------------------------------- the heuristics
local function routeScore(st, cfg, now)
	local c = cfg.route
	local keys, times = ringList(st.pos)
	local n = #keys
	if n < 2 or times[n] - times[1] < c.minSpanSeconds then
		return nil
	end
	-- the cells: one entry per change of cell, with the first tile of the visit
	local cells, tiles = {}, {}
	local last = nil
	for i = 1, n do
		local x, y, z = posParts(keys[i])
		local ck = (z * 65536 + floor(x / c.cellSize)) * 65536 + floor(y / c.cellSize)
		if ck ~= last then
			cells[#cells + 1] = ck
			tiles[#tiles + 1] = keys[i]
			last = ck
		end
	end
	local m = #cells
	if m > c.maxCells then
		local from = m - c.maxCells
		local nc, nt = {}, {}
		for i = from + 1, m do
			nc[#nc + 1] = cells[i]
			nt[#nt + 1] = tiles[i]
		end
		cells, tiles, m = nc, nt, c.maxCells
	end
	if m < c.minCells then
		return nil
	end
	-- the best period: the share of cells equal to the cell one period before; the shortest period near the best
	local fracs, best = {}, 0
	local top = min(c.maxPeriod, floor(m / 2))
	for p = c.minPeriod, top do
		local hit = 0
		for i = p + 1, m do
			if cells[i] == cells[i - p] then
				hit = hit + 1
			end
		end
		local f = hit / (m - p)
		fracs[p] = f
		if f > best then
			best = f
		end
	end
	local period = nil
	for p = c.minPeriod, top do
		if fracs[p] and fracs[p] >= best - 0.02 then
			-- the loop must cover several different cells
			local seen, distinct = {}, 0
			for i = 1, p do
				if not seen[cells[i]] then
					seen[cells[i]] = true
					distinct = distinct + 1
				end
			end
			if distinct >= c.minDistinct then
				period = p
				break
			end
		end
	end
	if not period then
		return {score = 0, text = "no loop of at least " .. c.minDistinct .. " different cells", n = m}
	end
	local laps = m / period
	local match = fracs[period]
	-- the mean distance between the tile of a lap and the one of the lap before, over the cells that came back
	local sum, cnt = 0, 0
	for i = period + 1, m do
		if cells[i] == cells[i - period] then
			local x1, y1 = posParts(tiles[i])
			local x2, y2 = posParts(tiles[i - period])
			sum = sum + max(abs(x1 - x2), abs(y1 - y2))
			cnt = cnt + 1
		end
	end
	local dev = cnt > 0 and sum / cnt or 99
	local score = 100 * ramp(laps, c.lapsFrom, c.lapsTo) * ramp(match, c.matchFrom, c.matchTo) * (1 - ramp(dev, c.devFrom, c.devTo))
	if match < c.matchFrom then
		return {score = 0, n = m, text = string.format("no repeated loop: at the best period (%d cells) only %d%% of the cells come back",
			period, round(match * 100))}
	end
	return {
		score = score, n = m,
		text = string.format("loop of %d cells repeated %.1f times, %d%% of the cells come back, mean deviation %.1f sqm",
			period, laps, round(match * 100), dev)
	}
end

local function regularityScore(st, cfg)
	local c = cfg.regularity
	local worst, text, total = nil, nil, 0
	for kind, k in pairs(st.kinds) do
		local list = ringList(k.ring)
		local n = #list
		total = total + n
		if n >= c.minSamples then
			local mean, std = meanStd(list)
			if mean > 0 then
				local cv = std / mean
				local s = 100 * ramp(cv, c.cvHuman, c.cvBot) * min(1, n / c.fullSamples)
				if not worst or s > worst then
					worst = s
					text = string.format("coefficient of variation %.2f in %d intervals (%s)", cv, n, kind)
				end
			end
		end
	end
	if not worst then
		return nil
	end
	return {score = worst, n = total, text = text}
end

local function reactionScore(st, cfg)
	local c = cfg.reaction
	local list = ringList(st.react)
	local n = #list
	if n < c.minSamples then
		return nil
	end
	local med = median(list)
	local s = 100 * ramp(med, c.humanMs, c.botMs) * min(1, n / c.fullSamples)
	return {score = s, n = n, text = string.format("median reaction %d ms in %d creatures", round(med), n)}
end

local function healScore(st, cfg)
	local c = cfg.heal
	local list = ringList(st.heals)
	local n = #list
	if n < c.minSamples then
		return nil
	end
	local mean, std = meanStd(list)
	local s = 100 * ramp(std, c.stdHuman, c.stdBot) * min(1, n / c.fullSamples)
	return {score = s, n = n, text = string.format("heals at %d%% of health, spread %.1f points in %d heals", round(mean), std, n)}
end

-- longest stretch without a pause (hours) and hours with an action in the last 24
function K.sessionNumbers(st, cfg, now)
	local idle = cfg.session.idleSeconds
	local stretchEnd = st.lastAct or now
	if st.lastAct and now - st.lastAct < idle then
		stretchEnd = now
	end
	local stretch = max(0, stretchEnd - st.idleEnd) / 3600
	local mNow = floor(now / 60)
	local active = 0
	for i = 1, 1440 do
		local m = st.actMin[i]
		if m and mNow - m < 1440 and mNow - m >= 0 then
			active = active + 1
		end
	end
	return stretch, active / 60
end

local function sessionScore(st, cfg, now)
	local c = cfg.session
	local stretch, hours = K.sessionNumbers(st, cfg, now)
	-- says nothing before the character has played long enough to have either number mean something
	if stretch < 1 and hours < 2 then
		return nil
	end
	local a = ramp(stretch, c.stretchFromHours, c.stretchToHours)
	local b = ramp(hours, c.dayFromHours, c.dayToHours)
	return {
		score = 100 * max(a, b), n = 1,
		text = string.format("%.1f hours without a 5 minute pause, %.1f hours with an action in the last 24", stretch, hours)
	}
end

local function pathBonus(st, cfg, now)
	local c = cfg.path
	local k, p, s = 0, 0, 0
	local h = floor(now / 3600)
	for i = 1, 4 do
		local slot = st.hours[i]
		if slot and h - slot.h < 4 then
			k, p, s = k + slot.k, p + slot.p, s + slot.s
		end
	end
	local steps = k + s
	if steps < c.minSteps or p == 0 then
		return nil
	end
	local share = s / steps
	local len = s / p
	local score = 100 * ramp(share, c.shareFrom, c.shareTo) * ramp(len, c.lengthFrom, c.lengthTo)
	return {score = score, n = steps,
		text = string.format("%d%% of %d steps from path commands, %.1f steps a command", round(share * 100), steps, len)}
end

-- the policy of the owner's route tool: how a character that runs it is shown (never an action)
-- seen: true when the integrity list or the tool scan named it; pos = {x, y, z} or nil
function K.rumoView(cfg, seen, pos)
	local r = cfg.rumo
	if not seen then
		return nil
	end
	local policy = r.policy or "flag"
	if policy == "allowed" then
		return "allowed", true
	elseif policy == "forbidden" then
		return "forbidden", false
	elseif policy == "areas" then
		for _, a in ipairs(r.areas or {}) do
			if pos and pos[3] == a[5] and pos[1] >= a[1] and pos[1] <= a[3] and pos[2] >= a[2] and pos[2] <= a[4] then
				return "allowed in this area", true
			end
		end
		return "outside the allowed areas", false
	end
	return "flag", false
end

local EXCUSED = {route = true, regularity = true, session = true}

-- the six heuristics over the rings; returns {total, flagged, parts = {name = {score, n, text}}, bonus, coverage, rumo, ...}
function K.analyze(st, cfg, now)
	local parts = {
		route = routeScore(st, cfg, now),
		regularity = regularityScore(st, cfg),
		reaction = reactionScore(st, cfg),
		heal = healScore(st, cfg),
		session = sessionScore(st, cfg, now)
	}
	local path = pathBonus(st, cfg, now)
	local sum, have = 0, 0
	local rumoLabel, excuse = K.rumoView(cfg, st.rumoSeen, st.lastKey and {posParts(st.lastKey)} or nil)
	for name, w in pairs(cfg.weights) do
		local p = parts[name]
		if p and not (excuse and EXCUSED[name]) then
			sum = sum + w * p.score
			have = have + w
		end
	end
	local total = 0
	if have > 0 then
		total = sum / have * min(1, have / cfg.minCoverage)
	end
	local bonus = 0
	if path then
		bonus = cfg.bonusMax * path.score / 100
	end
	total = min(100, total + bonus)
	local res = {
		total = total, bonus = bonus, path = path, parts = parts, coverage = have, rumo = rumoLabel,
		flagged = total > cfg.flagAt and not excuse
	}
	return res
end

-- numbers for the staff: one line per heuristic
function K.lines(res, cfg)
	local out = {string.format("total %d%s (flag above %d), weight with data %d of %d", round(res.total),
		res.flagged and " FLAGGED" or "", cfg.flagAt, res.coverage, 100)}
	local order = {"route", "regularity", "reaction", "heal", "session"}
	for _, name in ipairs(order) do
		local p = res.parts[name]
		if p then
			out[#out + 1] = string.format("%s %d (weight %d): %s", name, round(p.score), cfg.weights[name], p.text)
		else
			out[#out + 1] = string.format("%s: not enough samples", name)
		end
	end
	if res.path then
		out[#out + 1] = string.format("path precision %d, bonus +%.1f: %s", round(res.path.score), res.bonus, res.path.text)
	else
		out[#out + 1] = "path precision: not enough steps"
	end
	if res.rumo then
		out[#out + 1] = "route tool seen, policy: " .. res.rumo
	end
	return out
end

-- the columns of chaos_botdet_scores for a result
function K.scoreRow(res, cfg)
	local function s(name)
		local p = res.parts[name]
		return p and round(p.score) or 0
	end
	local notes = {}
	for _, l in ipairs(K.lines(res, cfg)) do
		notes[#notes + 1] = l
	end
	local text = table.concat(notes, " | ")
	if #text > 1000 then
		text = text:sub(1, 1000)
	end
	return {
		total = round(res.total), route = s("route"), regularity = s("regularity"), reaction = s("reaction"), heal = s("heal"),
		session = s("session"), bonus = round(res.bonus), flagged = res.flagged and 1 or 0, notes = text
	}
end

-- ---------------------------------------------------------------- rows for the database
-- the unwritten events of the state as rows {type = ..., data = table, created_at = n}; clears what it returns
function K.takeRows(st, cfg, now)
	local rows = {}
	-- positions: the entries since the last flush, delta coded ("dt,x,y,z;..." from the first time t)
	local first = max(st.posFlushed + 1, st.pos.n - st.pos.cap + 1)
	if st.pos.n >= first then
		local keys, times = ringList(st.pos, first)
		local parts, prev = {}, times[1]
		for i = 1, #keys do
			local x, y, z = posParts(keys[i])
			parts[#parts + 1] = string.format("%d,%d,%d,%d", times[i] - prev, x, y, z)
			prev = times[i]
		end
		rows[#rows + 1] = {type = "pos", data = {t = times[1], v = table.concat(parts, ";")}, created_at = now}
	end
	st.posFlushed = st.pos.n
	local w = st.walk
	if w.fk + w.fp + w.fs > 0 then
		rows[#rows + 1] = {type = "walk", data = {k = w.fk, p = w.fp, s = w.fs}, created_at = now}
		w.fk, w.fp, w.fs = 0, 0, 0
	end
	for _, kind in ipairs({"spell", "heal", "react", "session"}) do
		local list = st.pend[kind]
		if #list > 0 then
			rows[#rows + 1] = {type = kind, data = {v = table.concat(list, ";")}, created_at = now}
			st.pend[kind] = {}
		end
	end
	return rows
end

-- ---------------------------------------------------------------- the client's signals
-- chunks of module digests: {i = 1.., n = chunks, b = build, m = {{name, digest}, ...}}; official = {name = digest} or nil
-- Returns the number of entries read and, once the last chunk is in, the event to write (or nil).
function K.integrityChunk(st, cfg, msg, official)
	local c = cfg.integrity
	if type(msg) ~= "table" or type(msg.m) ~= "table" then
		return 0, nil
	end
	local i, n = tonumber(msg.i) or 1, tonumber(msg.n) or 1
	if n < 1 or n > c.maxChunks or i < 1 or i > n then
		return 0, nil
	end
	local acc = st.integrity
	if not acc or acc.n ~= n or i == 1 then
		acc = {n = n, got = 0, mods = {}, build = tonumber(msg.b) or 0}
		st.integrity = acc
	end
	local read = 0
	for _, e in ipairs(msg.m) do
		if read >= c.maxEntries then
			break
		end
		if type(e) == "table" and type(e[1]) == "string" and type(e[2]) == "string" and #e[1] <= 64 and #e[2] <= 64 then
			acc.mods[e[1]] = e[2]
			read = read + 1
		end
	end
	acc.got = acc.got + 1
	if acc.got < n then
		return read, nil
	end
	st.integrity = nil
	for _, name in ipairs(cfg.rumo.moduleNames) do
		if acc.mods[name] then
			st.rumoSeen = true
		end
	end
	local extras, changed = {}, {}
	if next(official or {}) == nil then
		return read, nil -- no official list yet: nothing to compare
	end
	for name, digest in pairs(acc.mods) do
		local want = official[name]
		if want == nil then
			extras[#extras + 1] = name
		elseif want ~= digest then
			changed[#changed + 1] = name
		end
	end
	table.sort(extras)
	table.sort(changed)
	if #extras == 0 and #changed == 0 then
		return read, nil
	end
	while #extras > c.maxExtras do
		table.remove(extras)
	end
	while #changed > c.maxExtras do
		table.remove(changed)
	end
	st.extras = extras
	return read, {type = "integrity", data = {b = acc.build, extra = extras, changed = changed}}
end

-- the codes of the tools the client found: only codes the server's own list knows, 3 to 16 letters or digits
function K.toolCodes(st, cfg, msg)
	if type(msg) ~= "table" or type(msg.c) ~= "table" then
		return nil
	end
	local known = {}
	for _, t in ipairs(cfg.tools.list or {}) do
		known[t.code] = true
	end
	local codes = {}
	for _, code in ipairs(msg.c) do
		if type(code) == "string" and code:match("^[%w]+$") and #code >= 3 and #code <= 16 and known[code] and #codes < cfg.tools.maxCodes then
			codes[#codes + 1] = code
			if code == cfg.rumo.toolCode then
				st.rumoSeen = true
			end
		end
	end
	if #codes == 0 then
		return nil
	end
	table.sort(codes)
	st.tools = codes
	return {type = "tool", data = {c = codes}}
end

-- the list the server sends to the client: {{code, hash}, ...}
function K.toolList(cfg)
	local out = {}
	for _, t in ipairs(cfg.tools.list or {}) do
		for _, h in ipairs(t.hashes or {}) do
			if type(h) == "string" and h:match("^%x+$") and #h == 16 then
				out[#out + 1] = {t.code, h}
			end
		end
	end
	return out
end

-- the 10-minute purge: a state that logged out long ago
function K.expired(st, cfg, now)
	return st.offlineAt ~= nil and now - st.offlineAt > cfg.keepOfflineMinutes * 60
end
