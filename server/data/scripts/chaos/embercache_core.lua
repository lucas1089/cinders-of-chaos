-- embercache_core.lua: the pure rules of the Ember Cache and the Daily Spark (embercache_config.lua; server/README.md
-- "Ember Cache, Daily Spark and the day book"). No engine calls; embercache.lua is the engine side.
-- Tests: server/tests/embercache_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- A state (one per character, kept in player storages):
--   {week = YYYYMMDD of the week's Monday, weekPoints, tiersGiven, weekSparks,
--    day = YYYYMMDD, dayPoints (counted, with the bonus), dayRaw (before the bonus), spark = 0 | 1,
--    killRest (kills not yet worth a point), caps = {[source] = points today}}

ChaosEmberCacheCore = ChaosEmberCacheCore or {}
local K = ChaosEmberCacheCore

local floor, max, min = math.floor, math.max, math.min

local function num(v, d)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return d or 0
	end
	return v
end

local function dayKeyOf(t)
	return tonumber(os.date("%Y%m%d", t))
end

-- the day of t (YYYYMMDD), turning at `hour`
function K.day(t, hour)
	return dayKeyOf(t - (hour or 6) * 3600)
end

-- the week of t: YYYYMMDD of its Monday (the week starts Monday at `hour`), the bounty board's rule
function K.week(t, hour)
	local d = os.date("*t", t - (hour or 6) * 3600)
	local back = (d.wday + 5) % 7 -- wday 1 = Sunday: Monday -> 0, Sunday -> 6
	return dayKeyOf(os.time({year = d.year, month = d.month, day = d.day - back, hour = 12}))
end

-- unix time a day key starts at `hour` (+ days)
function K.keyStart(key, hour, days)
	key = floor(num(key))
	local y, m, d = floor(key / 10000), floor(key / 100) % 100, key % 100
	return os.time({year = y, month = m, day = d + (days or 0), hour = hour or 6, min = 0, sec = 0})
end

-- seconds until the day / the week turns
function K.dayEndsIn(t, hour)
	return max(0, K.keyStart(K.day(t, hour), hour, 1) - t)
end

function K.weekEndsIn(t, hour)
	return max(0, K.keyStart(K.week(t, hour), hour, 7) - t)
end

function K.new()
	return {week = 0, weekPoints = 0, tiersGiven = 0, weekSparks = 0, day = 0, dayPoints = 0, dayRaw = 0, spark = 0,
		killRest = 0, caps = {}}
end

-- a new day or week empties its counters; returns newDay, newWeek
function K.roll(st, t, cfg)
	local hour = cfg.resetHour or 6
	local day, week = K.day(t, hour), K.week(t, hour)
	local newDay, newWeek = st.day ~= day, st.week ~= week
	if newDay then
		st.day, st.dayPoints, st.dayRaw, st.spark, st.killRest, st.caps = day, 0, 0, 0, 0, {}
	end
	if newWeek then
		st.week, st.weekPoints, st.tiersGiven, st.weekSparks = week, 0, 0, 0
	end
	return newDay, newWeek
end

-- raw points of `units` of a source (kills by `per`, the daily cap). Changes killRest and caps.
function K.addUnits(st, cfg, source, units)
	local s = cfg.sources[source]
	units = floor(num(units))
	if not s or units <= 0 then
		return 0
	end
	local raw
	if s.per then
		local per = max(1, floor(num(s.per, 1)))
		local total = floor(num(st.killRest)) + units
		raw = floor(total / per)
		st.killRest = total % per
	else
		raw = units * floor(num(s.points, 0))
	end
	if s.cap then
		local used = floor(num(st.caps[source]))
		raw = max(0, min(raw, floor(num(s.cap)) - used))
		st.caps[source] = used + raw
	end
	return raw
end

-- counts raw points: the day's first bonusPoints count double; returns {counted, spark = true when the day's Spark
-- was lit now, tiers = {indexes reached now}}
function K.addPoints(st, cfg, raw)
	local out = {counted = 0, spark = false, tiers = {}}
	raw = floor(num(raw))
	if raw <= 0 then
		return out
	end
	local d = cfg.daily or {}
	local bonus = max(0, min(raw, floor(num(d.bonusPoints)) - floor(num(st.dayRaw))))
	local counted = raw + bonus
	st.dayRaw = st.dayRaw + raw
	st.dayPoints = st.dayPoints + counted
	st.weekPoints = st.weekPoints + counted
	out.counted = counted
	if st.spark ~= 1 and num(d.goal) > 0 and st.dayPoints >= num(d.goal) then
		st.spark = 1
		st.weekSparks = st.weekSparks + 1
		out.spark = true
	end
	local tiers = cfg.tiers or {}
	while st.tiersGiven < #tiers and st.weekPoints >= num(tiers[st.tiersGiven + 1].points) do
		st.tiersGiven = st.tiersGiven + 1
		out.tiers[#out.tiers + 1] = st.tiersGiven
	end
	return out
end

-- hunting gold per hour at a level: linear between the points of `income` ({{level, gold}}), flat beyond the ends
function K.income(points, level)
	level = num(level, 1)
	if not points or #points == 0 then
		return 0
	end
	if level <= points[1][1] then
		return points[1][2]
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if level <= b[1] then
			return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
		end
	end
	return points[#points][2]
end

-- the gold of a reward at a level: `hours` of hunting income (cfg.income), or goldPerLevel x level; at most goldMax
function K.gold(reward, level, income)
	local g
	if reward.hours then
		g = floor(num(reward.hours) * K.income(income, level) + 0.5)
	else
		g = floor(num(reward.goldPerLevel) * max(1, floor(num(level, 1))))
	end
	if reward.goldMax then
		g = min(g, floor(num(reward.goldMax)))
	end
	return max(0, g)
end

-- storages <-> state. get(offset) -> value (-1 when unset); set(offset, value)
function K.load(cfg, get)
	local s = cfg.storage
	local function v(off)
		return max(0, floor(num(get(off))))
	end
	local st = {week = v(s.week), weekPoints = v(s.weekPoints), tiersGiven = v(s.tiersGiven), weekSparks = v(s.weekSparks),
		day = v(s.day), dayPoints = v(s.dayPoints), dayRaw = v(s.dayRaw), spark = v(s.spark), killRest = v(s.killRest),
		caps = {}}
	for i, source in ipairs(cfg.capped or {}) do
		st.caps[source] = v(s.capBase + i - 1)
	end
	return st
end

function K.save(cfg, st, set)
	local s = cfg.storage
	set(s.week, st.week)
	set(s.weekPoints, st.weekPoints)
	set(s.tiersGiven, st.tiersGiven)
	set(s.weekSparks, st.weekSparks)
	set(s.day, st.day)
	set(s.dayPoints, st.dayPoints)
	set(s.dayRaw, st.dayRaw)
	set(s.spark, st.spark)
	set(s.killRest, st.killRest)
	for i, source in ipairs(cfg.capped or {}) do
		set(s.capBase + i - 1, st.caps[source] or 0)
	end
end

-- the config checks (startup log and the test): list of problems
function K.validate(cfg)
	local out = {}
	local s = cfg.storage
	local used = {}
	for k, off in pairs(s) do
		if k ~= "base" and k ~= "last" and k ~= "capBase" then
			used[off] = (used[off] or 0) + 1
		end
	end
	for i = 1, #(cfg.capped or {}) do
		used[s.capBase + i - 1] = (used[s.capBase + i - 1] or 0) + 1
	end
	for off, n in pairs(used) do
		if n > 1 then
			out[#out + 1] = "storage offset " .. off .. " used twice"
		end
		if s.base + off > s.last then
			out[#out + 1] = "storage offset " .. off .. " past the block"
		end
	end
	for _, source in ipairs(cfg.capped or {}) do
		if not (cfg.sources[source] and cfg.sources[source].cap) then
			out[#out + 1] = "capped source without a cap: " .. source
		end
	end
	for name, s2 in pairs(cfg.sources) do
		if s2.cap then
			local found = false
			for _, c in ipairs(cfg.capped or {}) do
				found = found or c == name
			end
			if not found then
				out[#out + 1] = "source with a cap not in capped: " .. name
			end
		end
	end
	for _, list in ipairs({cfg.stats or {}, cfg.emits or {}}) do
		for key, m in pairs(list) do
			if not cfg.sources[m[1]] then
				out[#out + 1] = key .. " maps to an unknown source " .. tostring(m[1])
			end
		end
	end
	local last = 0
	for i, tier in ipairs(cfg.tiers or {}) do
		if num(tier.points) <= last then
			out[#out + 1] = "tier " .. i .. " not above the one before"
		end
		last = num(tier.points)
	end
	return out
end

-- the window's view of a state (client game_embercache): numbers only, the client writes the texts
function K.view(st, cfg, t, level, itemInfo)
	local hour = cfg.resetHour or 6
	local d = cfg.daily or {}
	local function items(list)
		local out = {}
		for _, it in ipairs(list or {}) do
			local cid, name = itemInfo(it.id)
			out[#out + 1] = {cid, it.count, name}
		end
		return out
	end
	local tiers = {}
	for i, tier in ipairs(cfg.tiers or {}) do
		tiers[i] = {p = tier.points, g = K.gold(tier, level, cfg.income), it = items(tier.items)}
	end
	local src = {}
	for _, key in ipairs(cfg.order or {}) do
		local s = cfg.sources[key]
		if s then
			src[#src + 1] = {key, s.points or 1, s.per or 1, s.cap or 0, st.caps[key] or 0}
		end
	end
	return {
		week = {pts = st.weekPoints, got = st.tiersGiven, sparks = st.weekSparks, ends = K.weekEndsIn(t, hour), tiers = tiers},
		day = {pts = st.dayPoints, raw = st.dayRaw, bonus = max(0, num(d.bonusPoints) - st.dayRaw), goal = d.goal or 0,
			spark = st.spark, ends = K.dayEndsIn(t, hour), g = K.gold(d.reward or {}, level, cfg.income),
			it = items((d.reward or {}).items)},
		src = src
	}
end

return K
