-- Numbers of the passive tree pick statistics (treestats.lua, treestats_core.lua; server/README.md "Passive tree pick
-- statistics"). Staff only: /treestats.
ChaosTreeStatsConfig = {
	-- level bands: {from, to} (to nil = and above); a character counts in the band of its level and in "all"
	bands = {{1, 99}, {100, 299}, {300, 499}, {500, 999}, {1000, nil}},
	-- characters of these groups and above are left out (staff test characters would skew the picks)
	staffGroup = 4,
	-- a line and band with fewer characters than this is not written to the CSV (one or two characters' trees would be
	-- readable from the counts); the in-game command still shows it, marked
	minCharacters = 3,
	-- /treestats lists this many of the most taken nodes unless a number is given (at most maxTop)
	top = 10,
	maxTop = 40,
	-- never-taken nodes listed by id in the command (the CSV has all of them)
	neverListed = 40,
	-- the CSV export: in the server's data folder (the working directory of the engine is the server folder)
	csvPath = "data/chaos_tree_picks_%s.csv", -- %s = YYYYMMDD-HHMM of the export
	-- one query over every saved tree: at most one /treestats a few seconds per staff member
	rateMs = 5000,
}

return ChaosTreeStatsConfig
