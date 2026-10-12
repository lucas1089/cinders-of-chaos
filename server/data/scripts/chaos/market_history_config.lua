-- Market price history (market_history.lua, market_history_core.lua, client game_market). Every number of it.
-- Returned as a table, loaded as Chaos.marketHistoryConfig (and by server/tests/market_history_test.lua). Data only.
-- See server/README.md "Market", Price history.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	-- DB tables (server/sql/chaos_market_history.sql; market_history.lua also creates them at startup when missing)
	tables = {
		sales = "chaos_market_history", -- one row per completed sale (a bought offer or a buy order fill), per unit price
		daily = "chaos_market_history_daily" -- one row per key and day once the day is older than rawDays
	},

	bandSize = 10, -- item level band of a key: iLvl 60-69 is one key (items without an item level: band 0)
	statsDays = 7, -- the window of the median, range, volume and of "typical"
	chartDays = 30, -- days of the daily median chart
	rawDays = 7, -- full days kept as single sales; older days are aggregated to one daily row per key
	keepDays = 90, -- daily rows older than this are dropped
	minSamples = 5, -- sales needed before a "typical price" is shown (7 days, else the chart window)
	trimPct = 10, -- the range (lo-hi) and the trimmed mean drop this % of the sales at each end

	-- the Browse list marks an offer whose price per unit is at most low x / at least high x the typical price
	marks = {low = 0.6, high = 1.6},
	-- the Sell form warns when the asking price per unit is at most low x / at least high x the typical price
	warn = {low = 0.5, high = 2.0},

	compactSeconds = 3600, -- the compaction job (globalevent): aggregate finished days, drop old ones
	compactGroups = 300, -- key-days aggregated per run at most (the rest waits for the next run)
	dropBatch = 5000, -- rows deleted per statement when dropping old daily rows
	cacheSeconds = 300, -- the stats of a key are kept this long in memory (a new sale of the key clears them)
	rawLimit = 5000, -- raw sales read for one key at most (the newest)
	rateMs = 250, -- ms between two price requests of one character
	backfillVersion = 1 -- server_config chaos_market_history: the sold offers of the last keepDays imported once
}
