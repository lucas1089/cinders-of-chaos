-- boss_balance_config.lua: the class identity bands (owner 2026-10-28), enforced by tools/boss_model.py --check (boss damage) and
-- tools/pack_model.py --check (pack farming, area lead). Plain table, loaded with dofile or read by the tools. Lua 5.3 and
-- LuaJIT compatible. No engine calls. server/data/spells/README.md "Boss damage per class" and docs/CLASSES.md "Class identity
-- (2026-10-28)" have the method and the final table.
--
-- O430 (2026-11-06, owner: "balance the classes that are far from the median DPS"): THE ROWS BELOW WERE RE-FITTED. The identity
-- pass of 2026-10-28 (the bands in the list that follows) rested on the C4 measurement of 2026-10-11; the DPS test of
-- 2026-11-06 (server/data/spells/class_dps_measured.csv, 21 classes at levels 100 / 500 / 1000) put classes at +188% (Deadeye)
-- and -77% (Sentinel) of the level median, and class_tree.lua classDamage, the spell factor's extra target factor and the
-- Beastmaster's bite were retuned to bring every class within +-25% of the median on 1 target and on 5 targets
-- (tools/class_dps_model.py --check holds that). The ratios of boss_model.py / pack_model.py start from the C4 numbers and move
-- with the class factors, so after a change of x2.5 (Sentinel) they no longer read as "damage against the Deadeye in a hunt";
-- the rows now pin the state after O430 (the model's own value of each class at each level, plus or minus 2%), so a later change
-- of a class factor shows up here, and `lead` is -1: no class has to lead (the single target and the pack leader rules of the
-- identity pass are replaced by the median band of class_dps_model.py). The text that follows is the identity pass as it was.
--
-- Every class has a strength and a weakness:
--   * pure area (Elementalist, Berserker, Bone Lord, Beastmaster): the best pack farmers, 1.00-1.10 of the reference; mid
--     single target (0.64-0.80 of the Deadeye)
--   * area caster base (Mystic): the Elementalist's base class keeps its area, 0.95-1.05; the weakest single target of the
--     damage classes
--   * mixed (Warrior, Ranger, Necromancer, Monk, Inquisitor): 0.88-0.95 (the Necromancer to 0.96) of the reference; single
--     target 0.62-0.90 (the Ranger and the Inquisitor lean to single target)
--   * burst (Deadeye, Ninja, Shadowfist, Lich, Thief, Samurai): 0.80-0.86 of the reference on packs (the Ninja to 0.88: its
--     area spells); single target 0.75-1.0 (the Samurai 0.68-0.80: a duelist who also tanks)
--   * tanks (Juggernaut, Sentinel, Templar): pull packs safely, 0.88-0.95; single target 0.55-0.70
--   * healers (Illusionist, Iron Sage): 0.85-0.93; single target 0.55-0.68 (the Illusionist, the best healer, the lowest)
-- Deadeye the best single target and Elementalist the best area class, each at least `lead` ahead of the next class.
--
-- The boss ratio is a class's damage per second on one boss against the Deadeye's at the same level (computed, not measured in
-- game). The pack ratio is a class's kills per hour in packs against the median class before the pass (pack_model.py
-- `reference`: the C4 numbers, kit changes and cleave of 2026-10-15), so a band does not move when the classes around the median
-- do. Rows are "Class" = {low, high}; the ratio must stay inside at every level of `levels`, widened at the levels that are not
-- measured: 800 lies between the measured 300 and 1000 (the damage is a straight line between them, the pace health is not) and
-- 1200 is extrapolated (a late set and 2.41 damage a level).
return {
	levels = {300, 800, 1000, 1200},

	-- how far outside a row a level may be: [level] = {below, above}
	bossWindows = {[800] = {0.03, 0.00}},
	packWindows = {[800] = {0.00, 0.06}, [1200] = {0.03, 0.00}},

	-- ENFORCED: boss damage against the Deadeye's
	limits = {
		["Warrior"] = {0.50, 0.92},
		["Juggernaut"] = {0.58, 1.05},
		["Berserker"] = {0.36, 1.05},
		["Ranger"] = {0.64, 0.88},
		["Deadeye"] = {0.98, 1.02},
		["Beastmaster"] = {0.45, 0.96},
		["Mystic"] = {0.93, 1.46},
		["Elementalist"] = {0.96, 1.31},
		["Illusionist"] = {0.75, 1.12},
		["Thief"] = {0.73, 2.23},
		["Ninja"] = {1.07, 2.16},
		["Samurai"] = {1.06, 3.21},
		["Necromancer"] = {0.74, 1.05},
		["Lich"] = {1.02, 1.57},
		["Bone Lord"] = {0.91, 1.37},
		["Monk"] = {0.72, 1.26},
		["Shadowfist"] = {1.00, 1.95},
		["Iron Sage"] = {0.77, 1.60},
		["Templar"] = {0.93, 1.88},
		["Inquisitor"] = {1.35, 2.34},
		["Sentinel"] = {1.69, 2.61},
	},

	-- ENFORCED: kills per hour in packs against the reference
	packLimits = {
		["Warrior"] = {0.67, 0.88},
		["Juggernaut"] = {0.84, 0.96},
		["Berserker"] = {0.65, 0.99},
		["Ranger"] = {0.73, 0.81},
		["Deadeye"] = {0.66, 0.76},
		["Beastmaster"] = {0.67, 0.94},
		["Mystic"] = {1.06, 1.24},
		["Elementalist"] = {1.06, 1.20},
		["Illusionist"] = {0.90, 0.96},
		["Thief"] = {0.71, 1.00},
		["Ninja"] = {0.88, 1.02},
		["Samurai"] = {0.89, 1.09},
		["Necromancer"] = {0.78, 0.92},
		["Lich"] = {0.80, 0.89},
		["Bone Lord"] = {0.97, 1.05},
		["Monk"] = {0.83, 0.96},
		["Shadowfist"] = {0.81, 0.92},
		["Iron Sage"] = {0.88, 1.04},
		["Templar"] = {0.99, 1.10},
		["Inquisitor"] = {1.01, 1.12},
		["Sentinel"] = {1.13, 1.37},
	},

	-- the leaders: every other class is at most 1 / (1 + lead) of the Deadeye's boss damage, and of the Elementalist's damage on a
	-- pack of 5 (with the pack cleave), at every level of `levels`
	-- O430: -1 = no leader rule (the identity pass had 0.08); the median band of class_dps_model.py replaces it
	lead = -1,
}
