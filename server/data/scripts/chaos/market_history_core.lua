-- Market price history: the numbers without engine calls (tested by server/tests/market_history_test.lua with LuaJIT and
-- Lua 5.3). market_history.lua does the database and the protocol; market_history_config.lua has every number.
-- An item key is realm + currency + item type + rarity + item level band: season and standard markets never mix, gold and
-- Chaos Coins never mix. Prices are per unit (a stack of 20 sold for 1000 is one sale at 50).
--   ChaosMarketHistoryCore.band(ilvl, size)                  first level of the item level band (0 = no item level)
--   ChaosMarketHistoryCore.bandText(band, size)              "iLvl 60-69" ("" for band 0)
--   ChaosMarketHistoryCore.key(realm, cur, itemId, rarity, band)  the cache / grouping key
--   ChaosMarketHistoryCore.unitPrice(paid, count)            price per unit, rounded down
--   ChaosMarketHistoryCore.median(values)                    median (the mean of the two middle values, rounded down)
--   ChaosMarketHistoryCore.trim(sorted, pct)                 a sorted list without pct % at each end
--   ChaosMarketHistoryCore.trimmedMean(values, pct)          the mean of the trimmed list
--   ChaosMarketHistoryCore.weightedMedian(pairs)             median of {p, w} pairs (each p counted w times)
--   ChaosMarketHistoryCore.aggregateDay(sales)               one day of sales {p, q} -> the daily row
--   ChaosMarketHistoryCore.stats(sales, daily, now, cfg)     last sale, 7-day median, range, volume, typical, daily series
--   ChaosMarketHistoryCore.mark(unit, typical, limits)       "low" / "high" / nil and the ratio
--   ChaosMarketHistoryCore.cutoffs(now, cfg)                 the days the compaction job aggregates and drops
--   ChaosMarketHistoryCore.compactGroups(rows, beforeDay)    raw sales of finished days grouped per key and day
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosMarketHistoryCore = ChaosMarketHistoryCore or {}
local H = ChaosMarketHistoryCore

local floor = math.floor
local DAY = 86400
H.DAY = DAY

local function int(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return floor(v)
end
H.int = int

function H.day(t)
	return floor((int(t) or 0) / DAY)
end

-- ------------------------------------------------------------------ keys
function H.band(ilvl, size)
	ilvl, size = int(ilvl) or 0, int(size) or 10
	if ilvl <= 0 then
		return 0
	end
	if size <= 1 then
		return ilvl
	end
	return floor(ilvl / size) * size
end

function H.bandText(band, size)
	band, size = int(band) or 0, int(size) or 10
	if band <= 0 then
		return ""
	end
	if size <= 1 then
		return "iLvl " .. band
	end
	return string.format("iLvl %d-%d", band, band + size - 1)
end

function H.key(realm, cur, itemId, rarity, band)
	return string.format("%d|%s|%d|%d|%d", int(realm) or 0, cur == "coins" and "coins" or "gold", int(itemId) or 0, int(rarity) or 0,
		int(band) or 0)
end

function H.unitPrice(paid, count)
	paid, count = int(paid) or 0, int(count) or 1
	if count < 1 then
		count = 1
	end
	return floor(paid / count)
end

-- ------------------------------------------------------------------ robust statistics
local function sortedCopy(values)
	local s = {}
	for _, v in ipairs(values or {}) do
		local n = tonumber(v)
		if n and n == n then
			s[#s + 1] = n
		end
	end
	table.sort(s)
	return s
end
H.sorted = sortedCopy

local function medianSorted(s)
	local n = #s
	if n == 0 then
		return nil
	end
	if n % 2 == 1 then
		return s[(n + 1) / 2]
	end
	return floor((s[n / 2] + s[n / 2 + 1]) / 2)
end

function H.median(values)
	return medianSorted(sortedCopy(values))
end

-- drops floor(n * pct / 100) values at each end; never everything (at least one value stays)
function H.trim(sorted, pct)
	local n = #sorted
	local k = floor(n * (tonumber(pct) or 0) / 100)
	if n - 2 * k < 1 then
		k = floor((n - 1) / 2)
	end
	local out = {}
	for i = k + 1, n - k do
		out[#out + 1] = sorted[i]
	end
	return out
end

function H.trimmedMean(values, pct)
	local t = H.trim(sortedCopy(values), pct)
	if #t == 0 then
		return nil
	end
	local sum = 0
	for _, v in ipairs(t) do
		sum = sum + v
	end
	return floor(sum / #t + 0.5)
end

-- pairs = {{p = value, w = weight}}: the value at the middle of the total weight (the lower one on an exact tie, as
-- the median of the expanded list would round down between two values)
function H.weightedMedian(pairs)
	local list, total = {}, 0
	for _, x in ipairs(pairs or {}) do
		local p, w = tonumber(x.p), int(x.w) or 0
		if p and w > 0 then
			list[#list + 1] = {p = p, w = w}
			total = total + w
		end
	end
	if total == 0 then
		return nil
	end
	table.sort(list, function(a, b) return a.p < b.p end)
	local lowIdx, highIdx = floor((total + 1) / 2), floor(total / 2) + 1
	local seen, low, high = 0, nil, nil
	for _, x in ipairs(list) do
		local from = seen + 1
		seen = seen + x.w
		if not low and lowIdx >= from and lowIdx <= seen then
			low = x.p
		end
		if not high and highIdx >= from and highIdx <= seen then
			high = x.p
		end
	end
	return floor((low + high) / 2)
end

-- one day of one key: sales = {{p = unit price, q = units}} -> {sales, units, median, low, high, mean (trimmed)}
function H.aggregateDay(sales, trimPct)
	local prices, units = {}, 0
	for _, s in ipairs(sales or {}) do
		prices[#prices + 1] = s.p
		units = units + math.max(1, int(s.q) or 1)
	end
	local sorted = sortedCopy(prices)
	if #sorted == 0 then
		return nil
	end
	return {sales = #sorted, units = units, median = medianSorted(sorted), low = sorted[1], high = sorted[#sorted],
		mean = H.trimmedMean(sorted, trimPct or 10)}
end

-- ------------------------------------------------------------------ the stats of one key
-- sales = raw rows {at, p (unit price), q (units)} of the days not compacted yet (any order); daily = compacted rows
-- {day, sales, units, median, low, high}; cfg = market_history_config.lua. Returns
--   {n7, units7, last, lastAt, median7, min7, max7, lo, hi (the 7-day range without the trimmed ends), mean (trimmed
--    mean, 7 days), n30, typical, basis ("7d" | "30d" | nil), need (cfg.minSamples), days (cfg.chartDays),
--    points = {{h = days ago, p = median of that day, v = sales}} oldest first}
-- typical: the 7-day median once there are cfg.minSamples sales in 7 days; else the median of the daily medians of the
-- chart window weighted by their sales once that window has cfg.minSamples; else nil (too few sales to say).
function H.stats(sales, daily, now, cfg)
	cfg = cfg or {}
	now = int(now) or 0
	local statsDays, chartDays = cfg.statsDays or 7, cfg.chartDays or 30
	local need = cfg.minSamples or 5
	local trimPct = cfg.trimPct or 10
	local today = H.day(now)
	local since = now - statsDays * DAY
	local out = {n7 = 0, units7 = 0, n30 = 0, need = need, days = chartDays, points = {}}
	local week, byDay = {}, {}
	for _, s in ipairs(sales or {}) do
		local at, p, q = int(s.at), tonumber(s.p), math.max(1, int(s.q) or 1)
		if at and p and at <= now then
			if not out.lastAt or at > out.lastAt then
				out.lastAt, out.last = at, p
			end
			if at >= since then
				week[#week + 1] = p
				out.units7 = out.units7 + q
			end
			local ago = today - H.day(at)
			if ago >= 0 and ago < chartDays then
				local d = byDay[ago]
				if not d then
					d = {prices = {}, units = 0}
					byDay[ago] = d
				end
				d.prices[#d.prices + 1] = p
				d.units = d.units + q
			end
		end
	end
	local perDay = {}
	for ago, d in pairs(byDay) do
		perDay[ago] = {p = H.median(d.prices), v = #d.prices}
	end
	-- compacted days (a day that still has raw rows keeps those: the job moves a day in one transaction)
	for _, r in ipairs(daily or {}) do
		local ago = today - (int(r.day) or 0)
		if ago >= 0 and ago < chartDays and not perDay[ago] and (int(r.sales) or 0) > 0 then
			perDay[ago] = {p = tonumber(r.median) or 0, v = int(r.sales)}
		end
	end
	local weighted = {}
	for ago = chartDays - 1, 0, -1 do
		local d = perDay[ago]
		if d then
			out.points[#out.points + 1] = {h = ago, p = d.p, v = d.v}
			out.n30 = out.n30 + d.v
			weighted[#weighted + 1] = {p = d.p, w = d.v}
		end
	end
	local sorted = sortedCopy(week)
	out.n7 = #sorted
	if #sorted > 0 then
		out.median7 = medianSorted(sorted)
		out.min7, out.max7 = sorted[1], sorted[#sorted]
		local t = H.trim(sorted, trimPct)
		out.lo, out.hi = t[1], t[#t]
		out.mean = H.trimmedMean(sorted, trimPct)
	end
	if out.n7 >= need then
		out.typical, out.basis = out.median7, "7d"
	elseif out.n30 >= need then
		out.typical, out.basis = H.weightedMedian(weighted), "30d"
	end
	return out
end

-- a price per unit against the typical one: "low" at or under limits.low x typical, "high" at or over limits.high x
-- typical, else nil; the ratio (unit / typical) as the second value
function H.mark(unit, typical, limits)
	unit, typical = tonumber(unit), tonumber(typical)
	if not unit or not typical or typical <= 0 or unit <= 0 then
		return nil, nil
	end
	limits = limits or {}
	local r = unit / typical
	if r <= (limits.low or 0.6) then
		return "low", r
	end
	if r >= (limits.high or 1.6) then
		return "high", r
	end
	return nil, r
end

-- ------------------------------------------------------------------ retention
-- rawBefore: raw sales of days before this one are aggregated to daily rows (rawDays full days stay raw, so the 7-day
-- window always reads raw sales); dailyBefore: daily rows of days before this one are dropped (keepDays)
function H.cutoffs(now, cfg)
	local today = H.day(now)
	return {today = today, rawBefore = today - (cfg.rawDays or 7), dailyBefore = today - (cfg.keepDays or 90)}
end

-- rows = raw sales {id, realm, item, rarity, band, cur, at, p, q}; the ones of days before beforeDay grouped per key and
-- day: {{realm, item, rarity, band, cur, day, agg = aggregateDay, ids = {...}}} in a stable order (key, then day)
function H.compactGroups(rows, beforeDay, trimPct)
	local groups, order = {}, {}
	for _, r in ipairs(rows or {}) do
		local d = H.day(r.at)
		if d < beforeDay then
			local k = H.key(r.realm, r.cur, r.item, r.rarity, r.band) .. "|" .. d
			local g = groups[k]
			if not g then
				g = {realm = int(r.realm) or 0, item = int(r.item) or 0, rarity = int(r.rarity) or 0, band = int(r.band) or 0,
					cur = r.cur == "coins" and "coins" or "gold", day = d, sales = {}, ids = {}, k = k}
				groups[k] = g
				order[#order + 1] = g
			end
			g.sales[#g.sales + 1] = {p = r.p, q = r.q}
			g.ids[#g.ids + 1] = r.id
		end
	end
	table.sort(order, function(a, b) return a.k < b.k end)
	for _, g in ipairs(order) do
		g.agg = H.aggregateDay(g.sales, trimPct)
		g.sales, g.k = nil, nil
	end
	return order
end

return H
