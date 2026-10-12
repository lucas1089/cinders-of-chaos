-- Run from the server/ folder: luajit tests/market_history_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- The market price history (data/scripts/chaos/market_history_core.lua, numbers in market_history_config.lua): keys and
-- item level bands, unit prices, medians, trims, weighted medians, the daily aggregation, the stats of a key (last sale,
-- 7-day median and range, volume, typical price with its minimum sample and the 30-day fallback, the daily series, an
-- outlier that does not move the typical price), the marks, the retention cutoffs and the compaction groups. Then the
-- engine file compiles, and its CREATE TABLE statements equal sql/chaos_market_history.sql.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/market_history_core.lua")
local H = ChaosMarketHistoryCore
local cfg = dofile("data/scripts/chaos/market_history_config.lua")
local DAY = 86400

-- ====================================================================== config
ok(cfg.tables.sales:match("^chaos_market_") and cfg.tables.daily:match("^chaos_market_"), "table names")
ok(cfg.bandSize >= 2, "band size >= 2 (the backfill's SQL band equals H.band then)")
ok(cfg.rawDays >= cfg.statsDays, "the 7-day window reads raw sales only")
ok(cfg.keepDays >= cfg.chartDays, "the chart window is kept")
ok(cfg.minSamples >= 2, "a minimum sample")
ok(cfg.marks.low < 1 and cfg.marks.high > 1 and cfg.warn.low <= cfg.marks.low and cfg.warn.high >= cfg.marks.high, "marks / warn")

-- ====================================================================== keys
eq(H.band(0, 10), 0, "no ilvl")
eq(H.band(-3, 10), 0, "negative ilvl")
eq(H.band(9, 10), 0, "ilvl 9 -> band 0")
eq(H.band(10, 10), 10, "ilvl 10")
eq(H.band(67, 10), 60, "ilvl 67")
eq(H.band(67.9, 10), 60, "fraction")
eq(H.band("85", 25), 75, "string, band 25")
eq(H.band(67, 1), 67, "band 1 = exact")
eq(H.bandText(60, 10), "iLvl 60-69", "band text")
eq(H.bandText(0, 10), "", "no band text")
eq(H.key(0, "gold", 2400, 3, 60), "0|gold|2400|3|60", "key")
eq(H.key(7, "coins", 2400, 3, 60), "7|coins|2400|3|60", "season key")
eq(H.key(7, "anything", 2400, 3, 60), "7|gold|2400|3|60", "unknown currency = gold")
ok(H.key(0, "gold", 2400, 3, 60) ~= H.key(5, "gold", 2400, 3, 60), "realms never share a key")
eq(H.unitPrice(1000, 20), 50, "unit price")
eq(H.unitPrice(1001, 20), 50, "unit price rounds down")
eq(H.unitPrice(500, 0), 500, "count 0 = 1")
eq(H.day(DAY * 3 + 5), 3, "day")

-- ====================================================================== medians and trims
eq(H.median({}), nil, "empty median")
eq(H.median({7}), 7, "one")
eq(H.median({5, 1, 3}), 3, "odd")
eq(H.median({4, 1, 3, 2}), 2, "even rounds down (2.5)")
eq(H.median({10, 20}), 15, "even")
eq(H.median({1, "x", 3, 2}), 2, "non-numbers skipped")
local sorted = H.sorted({9, 1, 5, 3, 7, 2, 8, 4, 6, 10})
eq(#H.trim(sorted, 10), 8, "10% of 10 = one each end")
eq(H.trim(sorted, 10)[1], 2, "trim low")
eq(H.trim(sorted, 10)[8], 9, "trim high")
eq(#H.trim(sorted, 0), 10, "no trim")
eq(#H.trim({1, 2, 3}, 10), 3, "too few to trim")
eq(#H.trim({1, 2}, 50), 2, "50% of 2 would drop everything: nothing dropped")
eq(#H.trim({1}, 50), 1, "one stays")
eq(H.trimmedMean({1, 2, 3, 4, 5, 6, 7, 8, 9, 1000}, 10), 6, "trimmed mean drops the outlier (2..9 -> 5.5 -> 6)")
eq(H.trimmedMean({}, 10), nil, "empty trimmed mean")
eq(H.weightedMedian({{p = 100, w = 1}, {p = 200, w = 1}, {p = 300, w = 1}}), 200, "weighted = plain when w = 1")
eq(H.weightedMedian({{p = 100, w = 5}, {p = 900, w = 1}}), 100, "weight wins")
eq(H.weightedMedian({{p = 100, w = 1}, {p = 300, w = 1}}), 200, "even total: middle")
eq(H.weightedMedian({{p = 300, w = 2}, {p = 100, w = 2}}), 200, "unsorted, even")
eq(H.weightedMedian({{p = 100, w = 0}}), nil, "no weight")
-- the weighted median equals the median of the expanded list
do
	local seed = 12345
	local function rnd(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % n
	end
	for run = 1, 200 do
		local pairs_, flat = {}, {}
		for _ = 1, 1 + rnd(6) do
			local p, w = 1 + rnd(1000), 1 + rnd(5)
			pairs_[#pairs_ + 1] = {p = p, w = w}
			for _ = 1, w do
				flat[#flat + 1] = p
			end
		end
		eq(H.weightedMedian(pairs_), H.median(flat), "weighted median run " .. run)
	end
end

-- ====================================================================== a day
local agg = H.aggregateDay({{p = 100, q = 1}, {p = 120, q = 3}, {p = 90, q = 1}, {p = 5000, q = 1}}, 25)
eq(agg.sales, 4, "sales")
eq(agg.units, 6, "units")
eq(agg.median, 110, "median (100 + 120) / 2")
eq(agg.low, 90, "low")
eq(agg.high, 5000, "high")
eq(agg.mean, 110, "trimmed mean (25% each end: 100, 120)")
eq(H.aggregateDay({}), nil, "no sales, no row")

-- ====================================================================== the stats of a key
local now = 20000 * DAY + 15 * 3600 -- 15:00 of day 20000
local function sale(daysAgo, p, q, hoursAgo)
	return {at = now - daysAgo * DAY - (hoursAgo or 0) * 3600, p = p, q = q or 1}
end
-- empty
local s = H.stats({}, {}, now, cfg)
eq(s.n7, 0, "empty n7")
eq(s.typical, nil, "empty: no typical")
eq(#s.points, 0, "empty: no points")
eq(s.need, cfg.minSamples, "need")
eq(s.days, cfg.chartDays, "days")
-- too few sales for a typical price
s = H.stats({sale(0, 1000), sale(1, 1100), sale(2, 900)}, {}, now, cfg)
eq(s.n7, 3, "three sales")
eq(s.median7, 1000, "median of three")
eq(s.typical, nil, "under the minimum sample: no typical")
eq(s.last, 1000, "last sale")
eq(s.lastAt, now, "last sale time")
eq(s.min7, 900, "min")
eq(s.max7, 1100, "max")
-- enough sales; an outlier (a fat finger at 1,000,000 and a dump at 1) does not move the typical price
local list = {sale(0, 1000, 1, 1), sale(0, 1050, 2, 3), sale(1, 950), sale(2, 1000), sale(3, 1020), sale(4, 980), sale(5, 1000000), sale(6, 1),
	sale(9, 800), sale(20, 700)}
s = H.stats(list, {}, now, cfg)
eq(s.n7, 8, "8 sales in 7 days (days 9 and 20 are older)")
eq(s.units7, 9, "units in 7 days")
eq(s.median7, 1000, "median ignores the outliers")
eq(s.typical, 1000, "typical = 7-day median")
eq(s.basis, "7d", "basis 7d")
eq(s.min7, 1, "raw min keeps the dump")
eq(s.max7, 1000000, "raw max keeps the fat finger")
eq(s.lo, 1, "10% of 8 trims nothing (floor 0.8)")
eq(s.last, 1000, "the newest sale")
eq(s.n30, 10, "30-day sales")
-- the series: one point per day with sales, oldest first, h = days ago, the day's median and sales
eq(#s.points, 9, "points: days 0-6, 9, 20")
eq(s.points[1].h, 20, "oldest first")
eq(s.points[1].p, 700, "a day's median")
eq(s.points[#s.points].h, 0, "today last")
eq(s.points[#s.points].p, 1025, "today: median of 1000 and 1050")
eq(s.points[#s.points].v, 2, "today: 2 sales")
-- a larger sample trims the range
local big = {}
for i = 1, 20 do
	big[#big + 1] = sale(i % 7, 1000 + i)
end
big[#big + 1] = sale(1, 5)
big[#big + 1] = sale(2, 999999)
s = H.stats(big, {}, now, cfg)
eq(s.n7, 22, "22 sales")
eq(s.lo, 1002, "10% of 22 = 2 trimmed at each end (5 and 1001 low)")
eq(s.hi, 1019, "and 999999 and 1020 high")
ok(s.mean >= 1002 and s.mean <= 1019, "trimmed mean inside the range")
eq(s.typical, 1010, "typical (median of 22: 1010 and 1011, rounded down)")
-- the chart window: older than chartDays and future sales are left out
s = H.stats({sale(cfg.chartDays, 500), sale(cfg.chartDays - 1, 600), {at = now + 3600, p = 9, q = 1}}, {}, now, cfg)
eq(#s.points, 1, "only the day inside the window")
eq(s.points[1].h, cfg.chartDays - 1, "the oldest day shown")
eq(s.last, 600, "a future row is ignored")
-- compacted days: they fill the older part of the chart and the 30-day fallback of typical
local today = H.day(now)
local daily = {{day = today - 10, sales = 3, units = 3, median = 2000, low = 1900, high = 2100},
	{day = today - 15, sales = 2, units = 4, median = 2200, low = 2100, high = 2300},
	{day = today - 40, sales = 50, units = 50, median = 1, low = 1, high = 1}, -- outside the window
	{day = today - 2, sales = 9, units = 9, median = 7, low = 7, high = 7}} -- a day that still has raw rows: the raw ones count
s = H.stats({sale(2, 2050)}, daily, now, cfg)
eq(s.n7, 1, "one raw sale in 7 days")
eq(#s.points, 3, "days 15, 10, 2")
eq(s.points[1].h, 15, "daily rows in the series")
eq(s.points[3].p, 2050, "the raw day wins over a daily row of the same day")
eq(s.n30, 6, "30-day sales: 2 + 3 + 1")
eq(s.typical, 2025, "30-day fallback: weighted median of the daily medians (2000 x3, 2050 x1, 2200 x2)")
eq(s.basis, "30d", "basis 30d")
-- the fallback also needs the minimum sample
s = H.stats({}, {{day = today - 10, sales = 2, units = 2, median = 2000, low = 2000, high = 2000}}, now, cfg)
eq(s.typical, nil, "two sales in 30 days: no typical")
eq(#s.points, 1, "but the chart has the day")

-- ====================================================================== marks
eq(H.mark(500, 1000, cfg.marks), "low", "half price is low")
eq(H.mark(600, 1000, {low = 0.6, high = 1.6}), "low", "exactly the low limit")
eq(H.mark(800, 1000, cfg.marks), nil, "800 is normal")
eq(H.mark(1600, 1000, {low = 0.6, high = 1.6}), "high", "exactly the high limit")
eq(H.mark(5000, 1000, cfg.marks), "high", "five times is high")
eq(H.mark(5000, nil, cfg.marks), nil, "no typical, no mark")
eq(H.mark(5000, 0, cfg.marks), nil, "typical 0, no mark")
local _, r = H.mark(1500, 1000, cfg.marks)
eq(r, 1.5, "ratio")

-- ====================================================================== retention
local c = H.cutoffs(now, cfg)
eq(c.today, today, "today")
eq(c.rawBefore, today - cfg.rawDays, "raw kept rawDays full days")
eq(c.dailyBefore, today - cfg.keepDays, "daily kept keepDays")
-- the 7-day window starts inside a raw day: every sale the stats need is still raw
ok(H.day(now - cfg.statsDays * DAY) >= c.rawBefore, "the stats window never reads compacted days")
local rows = {
	{id = 1, realm = 0, item = 2400, rarity = 3, band = 60, cur = "gold", at = (today - 10) * DAY + 100, p = 100, q = 1},
	{id = 2, realm = 0, item = 2400, rarity = 3, band = 60, cur = "gold", at = (today - 10) * DAY + 200, p = 300, q = 2},
	{id = 3, realm = 0, item = 2400, rarity = 3, band = 60, cur = "gold", at = (today - 9) * DAY + 200, p = 50, q = 1},
	{id = 4, realm = 5, item = 2400, rarity = 3, band = 60, cur = "gold", at = (today - 10) * DAY + 300, p = 9, q = 1}, -- a season
	{id = 5, realm = 0, item = 2400, rarity = 3, band = 60, cur = "coins", at = (today - 10) * DAY + 300, p = 4, q = 1},
	{id = 6, realm = 0, item = 2400, rarity = 3, band = 60, cur = "gold", at = (today - 1) * DAY, p = 7, q = 1} -- still raw
}
local groups = H.compactGroups(rows, c.rawBefore, cfg.trimPct)
eq(#groups, 4, "4 key-days: standard gold x2 days, coins, season")
local byKey = {}
for _, g in ipairs(groups) do
	byKey[H.key(g.realm, g.cur, g.item, g.rarity, g.band) .. "@" .. (today - g.day)] = g
end
local g = byKey["0|gold|2400|3|60@10"]
ok(g ~= nil, "standard gold day 10")
eq(g and g.agg.sales, 2, "two sales")
eq(g and g.agg.units, 3, "three units")
eq(g and g.agg.median, 200, "median")
eq(g and #g.ids, 2, "both ids to delete")
ok(byKey["5|gold|2400|3|60@10"] and byKey["5|gold|2400|3|60@10"].agg.median == 9, "the season day apart")
ok(byKey["0|coins|2400|3|60@10"] and byKey["0|coins|2400|3|60@10"].agg.median == 4, "coins apart")
ok(byKey["0|gold|2400|3|60@9"] ~= nil, "day 9 apart")
for _, x in ipairs(groups) do
	for _, id in ipairs(x.ids) do
		ok(id ~= 6, "a raw day is not compacted")
	end
end
-- compaction keeps what the stats show: the series of raw rows equals the series of their daily rows
do
	local raw = {}
	for i = 1, 60 do
		raw[#raw + 1] = {id = i, realm = 0, item = 1, rarity = 0, band = 0, cur = "gold", at = (today - 8 - (i % 12)) * DAY + i * 60, p = 100 + (i * 37) % 50,
			q = 1 + i % 3}
	end
	local before = H.stats(raw, {}, now, cfg)
	local dailyRows = {}
	for _, x in ipairs(H.compactGroups(raw, c.rawBefore, cfg.trimPct)) do
		dailyRows[#dailyRows + 1] = {day = x.day, sales = x.agg.sales, units = x.agg.units, median = x.agg.median, low = x.agg.low, high = x.agg.high}
	end
	local after = H.stats({}, dailyRows, now, cfg)
	eq(#after.points, #before.points, "same days after compaction")
	for i = 1, #before.points do
		eq(after.points[i].p, before.points[i].p, "same median day " .. i)
		eq(after.points[i].v, before.points[i].v, "same sales day " .. i)
	end
	eq(after.n30, before.n30, "same 30-day sales")
end

-- ====================================================================== the engine file
local function compiles(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	local fn, err = (loadstring or load)(text, "@" .. path)
	return fn ~= nil, err, text
end
local okC, err, engine = compiles("data/scripts/chaos/market_history.lua")
ok(okC, "market_history.lua compiles: " .. tostring(err))
-- its schema equals the SQL file (whitespace aside)
local function norm(s)
	return (s:gsub("%s+", " "):gsub(" %)", ")"):gsub("%( ", "("))
end
local f = assert(io.open("sql/chaos_market_history.sql", "r"))
local sqlText = f:read("*a"):gsub("%-%-[^\n]*", "")
f:close()
local fromSql, fromLua = {}, {}
for stmt in sqlText:gmatch("(CREATE TABLE.-);") do
	fromSql[#fromSql + 1] = norm(stmt)
end
for stmt in engine:gmatch("%[%[(CREATE TABLE.-)%]%]") do
	fromLua[#fromLua + 1] = norm(stmt)
end
eq(#fromSql, 2, "two tables in the SQL file")
eq(#fromLua, 2, "two tables in the engine file")
for i = 1, math.max(#fromSql, #fromLua) do
	eq(fromLua[i], fromSql[i], "schema " .. i)
end
-- the hooks in market.lua
local okM, errM, market = compiles("data/scripts/chaos/market.lua")
ok(okM, "market.lua compiles: " .. tostring(errM))
ok(market:find("ChaosMarketHistory.record, id, realm", 1, true) ~= nil, "buy records the sale")
ok(market:find("ChaosMarketHistory.record, f.id", 1, true) ~= nil, "a buy order fill records the sale")
ok(market:find("ChaosMarketHistory.markRows", 1, true) ~= nil, "browse marks the rows")
ok(market:find("ChaosMarketHistory.actions[a]", 1, true) ~= nil, "the prices action")

print(string.format("market_history_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
