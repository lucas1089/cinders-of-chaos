-- Trainer DPS meter, pure logic (no engine calls): which monsters are trainers, the target profile of a trainer, the
-- session of one player on one trainer (rolling window, average, total, biggest hit, breakdown by source and element)
-- and the compact view sent to the client. Used by trainer_meter.lua; tested by server/tests/trainer_meter_test.lua.
-- Lua 5.1 / LuaJIT and 5.3 compatible.
--
-- A source is the table the combat log attributes a hit to (combatlog_core.lua CL.source): {k = key, t = kind, n = name,
-- i = icon}. A session: {id, tid (trainer creature id), name, start, last (ms of the first and the last hit; nil before
-- the first), total, hits, crits, max, maxName, rows = {[key] = {src, total, hits, crits, max}}, nrows, el = {[element] =
-- amount}, bt / bv / bh / bn (the window's buckets), wsum, ended, ver}.

ChaosTrainerMeterCore = ChaosTrainerMeterCore or {}
local M = ChaosTrainerMeterCore
local floor, max, min = math.floor, math.max, math.min

M.CLASSES = {normal = true, elite = true, boss = true}

local DEFAULTS = {windowMs = 5000, bucketMs = 250, minSpanMs = 1000, endAfterMs = 10000, maxRows = 40, maxRowsSent = 10,
	maxElementsSent = 10, maxPartySent = 8, minLevel = 1, maxLevel = 2500}

-- the config with the defaults under it (a table used for every call, built once by the caller: M.configure(cfg))
function M.configure(cfg)
	local c = {}
	for k, v in pairs(DEFAULTS) do
		c[k] = v
	end
	for k, v in pairs(cfg or {}) do
		c[k] = v
	end
	return c
end

local function round(v)
	return floor((tonumber(v) or 0) + 0.5)
end

-- ---------------------------------------------------------------- who is a trainer
local function inList(list, key)
	for _, n in ipairs(list or {}) do
		if tostring(n):lower() == key then
			return true
		end
	end
	return false
end

function M.isTrainerName(cfg, name)
	if type(name) ~= "string" or name == "" then
		return false
	end
	local key = name:lower()
	if inList(cfg.exclude, key) then
		return false
	end
	if inList(cfg.names, key) then
		return true
	end
	for _, w in ipairs(cfg.words or {}) do
		local word = tostring(w):lower()
		if word ~= "" and key:find(word, 1, true) then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------- the target profile
-- {class = "normal" | "elite" | "boss", level = number | nil (nil: the level of the hitting player)} of a trainer, or nil
-- when the profile is off (the trainer keeps the armour and resistances of its monster file)
function M.profileFor(cfg, name)
	local base = cfg.profile or {}
	if base.enabled == false then
		return nil
	end
	local o = cfg.byName and type(name) == "string" and cfg.byName[name:lower()] or nil
	local class = o and o.class or base.class
	if not M.CLASSES[class] then
		class = "normal"
	end
	local level = base.level
	if o and o.level ~= nil then
		level = o.level
	end
	local n = tonumber(level)
	if n then
		n = floor(max(cfg.minLevel, min(cfg.maxLevel, n)))
	end
	return {class = class, level = n}
end

-- the level the trainer's armour is computed for, when a player hits it
function M.levelFor(cfg, profile, playerLevel)
	local l = profile and profile.level or tonumber(playerLevel) or 1
	return floor(max(cfg.minLevel, min(cfg.maxLevel, l)))
end

-- ---------------------------------------------------------------- a session
function M.newSession(id, tid, name)
	return {id = id or 0, tid = tid, name = tostring(name or ""), total = 0, hits = 0, crits = 0, max = 0, maxName = "",
		rows = {}, nrows = 0, el = {}, bt = {}, bv = {}, bh = 1, bn = 0, wsum = 0, ended = false, ver = 0}
end

function M.active(s)
	return s ~= nil and s.start ~= nil and not s.ended
end

-- buckets older than the window leave it
local function prune(cfg, s, now)
	local limit = now - cfg.windowMs
	local bms = cfg.bucketMs
	while s.bh <= s.bn and (s.bt[s.bh] + 1) * bms <= limit do
		s.wsum = s.wsum - s.bv[s.bh]
		s.bt[s.bh], s.bv[s.bh] = nil, nil
		s.bh = s.bh + 1
	end
	if s.bh > s.bn then
		s.wsum = 0
	end
end

local OTHER = {k = "o:Other", t = "o", n = "Other", i = "other"}

-- one hit of the player on the trainer: amount (> 0), src (the combat log's source), el (element name or nil), crit
function M.record(cfg, s, now, amount, src, el, crit)
	amount = tonumber(amount) or 0
	if amount <= 0 then
		return false
	end
	src = src or OTHER
	if not s.start then
		s.start = now
	end
	s.last = now
	local b = floor(now / cfg.bucketMs)
	if s.bn >= s.bh and s.bt[s.bn] == b then
		s.bv[s.bn] = s.bv[s.bn] + amount
	else
		s.bn = s.bn + 1
		s.bt[s.bn], s.bv[s.bn] = b, amount
	end
	s.wsum = s.wsum + amount
	prune(cfg, s, now)
	s.total = s.total + amount
	s.hits = s.hits + 1
	if crit then
		s.crits = s.crits + 1
	end
	if amount > s.max then
		s.max = amount
		s.maxName = src.n or ""
	end
	local row = s.rows[src.k]
	if not row then
		if s.nrows >= cfg.maxRows then
			src = OTHER
			row = s.rows[src.k]
		end
		if not row then
			row = {src = src, total = 0, hits = 0, crits = 0, max = 0}
			s.rows[src.k] = row
			s.nrows = s.nrows + 1
		end
	end
	row.total = row.total + amount
	row.hits = row.hits + 1
	if crit then
		row.crits = row.crits + 1
	end
	if amount > row.max then
		row.max = amount
	end
	if el then
		s.el[el] = (s.el[el] or 0) + amount
	end
	s.ver = s.ver + 1
	return true
end

-- DPS now: what the last windowMs summed to, per second (never over less than minSpanMs); 0 once the session ended
function M.currentDps(cfg, s, now)
	if not M.active(s) then
		return 0
	end
	prune(cfg, s, now)
	if s.wsum <= 0 then
		return 0
	end
	local span = min(cfg.windowMs, max(cfg.minSpanMs, now - s.start))
	return s.wsum * 1000 / span
end

-- the session's time in ms: from the first hit to now while it runs, to the last hit once it ended
function M.duration(cfg, s, now)
	if not s.start then
		return 0
	end
	if s.ended then
		return max(0, s.last - s.start)
	end
	return max(0, now - s.start)
end

-- the average since the first hit (never over less than minSpanMs)
function M.averageDps(cfg, s, now)
	if not s.start or s.total <= 0 then
		return 0
	end
	return s.total * 1000 / max(cfg.minSpanMs, M.duration(cfg, s, now))
end

-- the session ends endAfterMs after the last hit. True when it ended just now.
function M.tick(cfg, s, now)
	if s.start and not s.ended and now - s.last >= cfg.endAfterMs then
		s.ended = true
		s.ver = s.ver + 1
		return true
	end
	return false
end

-- ---------------------------------------------------------------- the registry (one session per player)
function M.newRegistry()
	return {sess = {}, serial = 0}
end

-- A hit of player pid on the trainer tid (name tname). Returns the session and true when the hit began it. A new session
-- begins when the player has none, hit another trainer, or the last one ended (also when its tick has not run yet).
function M.hit(cfg, reg, pid, tid, tname, now, amount, src, el, crit)
	local s = reg.sess[pid]
	if s then
		M.tick(cfg, s, now)
	end
	local fresh = false
	if not s or s.tid ~= tid or s.ended then
		reg.serial = reg.serial + 1
		s = M.newSession(reg.serial, tid, tname)
		reg.sess[pid] = s
		fresh = true
	end
	M.record(cfg, s, now, amount, src, el, crit)
	return s, fresh
end

-- the Reset button: an empty session on the same trainer (nothing counts until the next hit)
function M.reset(reg, pid)
	local s = reg.sess[pid]
	if not s then
		return nil
	end
	reg.serial = reg.serial + 1
	s = M.newSession(reg.serial, s.tid, s.name)
	reg.sess[pid] = s
	return s
end

-- changes whenever the view changes without time passing (a hit, the end, a reset)
function M.signature(s)
	return s and (s.id .. ":" .. s.ver) or "none"
end

-- ---------------------------------------------------------------- the view
local function byTotal(a, b)
	if a.total ~= b.total then
		return a.total > b.total
	end
	return a.src.k < b.src.k
end

-- the rows sorted, at most `limit`; what is left is one "Others" row. {n, t (kind), i (icon), v, h, c, m}
local function rowsView(cfg, s, limit)
	local list = {}
	for _, r in pairs(s.rows) do
		list[#list + 1] = r
	end
	table.sort(list, byTotal)
	local out, rest = {}, nil
	for i, r in ipairs(list) do
		if i <= limit then
			out[#out + 1] = {n = r.src.n, t = r.src.t, i = r.src.i, v = round(r.total), h = r.hits, c = r.crits, m = round(r.max)}
		else
			rest = rest or {n = "Others", t = "o", i = "other", v = 0, h = 0, c = 0, m = 0}
			rest.v, rest.h, rest.c = rest.v + round(r.total), rest.h + r.hits, rest.c + r.crits
			rest.m = max(rest.m, round(r.max))
		end
	end
	if rest then
		out[#out + 1] = rest
	end
	return out
end

local function elementsView(s, limit)
	local list = {}
	for name, amount in pairs(s.el) do
		list[#list + 1] = {name, amount}
	end
	table.sort(list, function(a, b)
		if a[2] ~= b[2] then
			return a[2] > b[2]
		end
		return a[1] < b[1]
	end)
	local out = {}
	for i = 1, min(limit, #list) do
		out[i] = {list[i][1], round(list[i][2])}
	end
	return out
end

-- One player's numbers for the party list: {cur, tot}
function M.brief(cfg, s, now)
	return {cur = round(M.currentDps(cfg, s, now)), tot = round(s.total)}
end

-- The state sent to the client. act: 1 while the session runs; end: 1 once it ended; empty: 1 before the first hit.
-- cur / avg are per second, dur is ms, w / e the window and the end delay in seconds, prof the target profile
-- ({c = class, l = level the armour was computed for or 0 = the player's}).
function M.view(cfg, s, now, profile)
	local v = {
		tn = s.name, tid = s.tid, sid = s.id,
		act = M.active(s) and 1 or 0, ["end"] = s.ended and 1 or 0, empty = s.start == nil and 1 or 0,
		cur = round(M.currentDps(cfg, s, now)), avg = round(M.averageDps(cfg, s, now)), tot = round(s.total),
		hits = s.hits, crits = s.crits, max = round(s.max), mxn = s.maxName, dur = M.duration(cfg, s, now),
		w = cfg.windowMs / 1000, e = cfg.endAfterMs / 1000,
		rows = rowsView(cfg, s, cfg.maxRowsSent), el = elementsView(s, cfg.maxElementsSent),
	}
	if profile then
		v.prof = {c = profile.class, l = profile.level or 0}
	end
	return v
end

return M
