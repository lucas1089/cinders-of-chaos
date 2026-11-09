-- boss_balance_config.lua: the class bands of the boss and pack models, enforced by tools/boss_model.py --check (damage on one
-- boss) and tools/pack_model.py --check (kills per hour in packs). Plain table, loaded with dofile or read by the tools. Lua 5.3
-- and LuaJIT compatible. No engine calls. server/data/spells/README.md "Boss damage per class" has the method.
--
-- O444 (2026-11-09): ONE TRUTH. The two models and tools/tower_model.py read a class's damage from tools/class_dps_model.py (the
-- measured DPS table of 2026-11-06 moved by the class factors, the extra target factor and O429), not from a table of their own.
-- The bands below were rewritten in terms of the LEVEL MEDIAN (the median of the 21 classes at the level), the way
-- class_dps_model.py holds the classes. Before O444:
--   * the identity pass of 2026-10-28 (boss damage against the Deadeye, kills per hour against "the median class before the pass",
--     the Deadeye 8% ahead on one target, the Elementalist 8% ahead on a pack) rested on the C4 measurement of 2026-10-11;
--   * O430 (2026-11-06) re-fitted every row to the model's own value of the day, plus or minus 2%, and set `lead` to -1 (no leader
--     rule). Those rows pinned a state that class_dps_model.py contradicts: the Sentinel at 1.80 of the Deadeye on a boss against
--     -14% of the median on one target, the Deadeye at +7% against +21%.
-- The ratio of a class is now its damage on one boss (boss) or its kills per hour in packs (pack, with the pace cleave of
-- pace_config.lua) over the median class's at the same level. The band is the one of class_dps_model.py, +-25%: the damage table
-- is measured at 100, 500 and 1000, so the levels in between and above are a line through it and a class that is inside the band at
-- the measured levels is inside it at 300, 800 and 1200 (the largest boss ratio today is 1.21, the smallest pack ratio 0.82). A
-- class that needs its own row goes in `limits` / `packLimits` (a row replaces the band for that class); both are empty.
--
-- Rows are "Class" = {low, high}; the ratio must stay inside at every level of `levels`, widened by the level's window.
return {
	-- 100 is left out: its band is +-30% (class_dps_model.py) and the packs there are 5 monsters; 500 is measured
	levels = {300, 500, 800, 1000, 1200},

	-- how far outside a row a level may be: [level] = {below, above}. None today: every class is inside the band at every level
	bossWindows = {},
	packWindows = {},

	-- ENFORCED: the band of every class not listed in `limits` / `packLimits`, against the level median
	bossBand = {0.75, 1.25}, -- damage on one boss
	packBand = {0.75, 1.25}, -- kills per hour in packs

	-- ENFORCED: a class's own boss row (none)
	limits = {
	},

	-- ENFORCED: a class's own pack row (none)
	packLimits = {
	},
}
