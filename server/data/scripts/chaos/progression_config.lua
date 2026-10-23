-- Progression smoothness (O135): the limits of tools/progression_model.lua --check (CI) and the model's inputs.
-- Plain table, loaded with dofile. Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls. server/README.md
-- "Progression smoothness (O135)".
--
-- The model (computed, not measured): minutes per level at level L = the experience to the next level (the engine's
-- formula) / (the median experience per hour of the hunts at the level x the multikill chain bonus x the experience
-- stage of the level). A hunt of the pool (bounty_pool.lua, 709 monsters with 6+ spawns) pays its pace-curve experience
-- per kill (pace_config.lua) at the pack model's kills per hour (spawn_tuning.json paceKillsPerHour).
return {
	-- the chain bonus of a median pack (pace_config.lua: the xp curves are divided by it)
	multikill = 1.3,

	-- the hunts a character of level L farms: pool hunts whose hunting level is within [lo L, hi L]; the window grows
	-- by 0.05 each side until minHunts are inside
	window = {lo = 0.8, hi = 1.1, minHunts = 5},

	-- teleport hall: a hall hunt (tools/hall_hunts.csv, tools/areaplan/plans) is within reach of level L when its level is
	-- within [lo L, hi L]; every level from `fromLevel` needs minHunts of them ("next hunt far above" = nothing in range)
	hall = {lo = 0.7, hi = 1.3, minHunts = 3},

	limits = {
		fromLevel = 8, -- characters start at level 8 (start_stats.lua)
		toLevel = 2200, -- the last band of the weapons (weapon_coverage_config.lua)
		-- the experience stage table (tools/late_game.py): the next row is at most this x (or 1/this x) the one before
		stageStep = 1.08,
		-- the mean minutes per level of consecutive blocks of `short` levels change by a ratio inside shortRatio, blocks
		-- of `long` levels inside longRatio (before O135: 0.37 to 1.26 over 10 levels, the cliff at level 21)
		short = 10, shortRatio = {0.75, 1.25},
		long = 25, longRatio = {0.88, 1.35},
		-- hunts of the pool inside the window, every level (the window widens first)
		minPoolHunts = 4
	}
}
