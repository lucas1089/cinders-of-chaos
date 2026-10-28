-- boss_balance_config.lua: the class identity bands (owner 2026-10-28), enforced by tools/boss_model.py --check (boss damage) and
-- tools/pack_model.py --check (pack farming, area lead). Plain table, loaded with dofile or read by the tools. Lua 5.3 and
-- LuaJIT compatible. No engine calls. server/data/spells/README.md "Boss damage per class" and docs/CLASSES.md "Class identity
-- (2026-10-28)" have the method and the final table.
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
		["Warrior"] = {0.62, 0.76},
		["Juggernaut"] = {0.55, 0.70},
		["Berserker"] = {0.66, 0.80},
		["Ranger"] = {0.78, 0.90},
		["Deadeye"] = {0.98, 1.02},
		["Beastmaster"] = {0.70, 0.80},
		["Mystic"] = {0.55, 0.68},
		["Elementalist"] = {0.64, 0.80},
		["Illusionist"] = {0.55, 0.65},
		["Thief"] = {0.75, 0.88},
		["Ninja"] = {0.75, 0.90},
		["Samurai"] = {0.68, 0.80},
		["Necromancer"] = {0.64, 0.78},
		["Lich"] = {0.75, 0.92},
		["Bone Lord"] = {0.70, 0.80},
		["Monk"] = {0.62, 0.76},
		["Shadowfist"] = {0.75, 0.92},
		["Iron Sage"] = {0.58, 0.68},
		["Templar"] = {0.55, 0.70},
		["Inquisitor"] = {0.76, 0.88},
		["Sentinel"] = {0.55, 0.70},
	},

	-- ENFORCED: kills per hour in packs against the reference
	packLimits = {
		["Warrior"] = {0.88, 0.95},
		["Juggernaut"] = {0.88, 0.95},
		["Berserker"] = {1.00, 1.10},
		["Ranger"] = {0.88, 0.95},
		["Deadeye"] = {0.80, 0.86},
		["Beastmaster"] = {1.00, 1.10},
		["Mystic"] = {0.95, 1.05},
		["Elementalist"] = {1.00, 1.10},
		["Illusionist"] = {0.85, 0.93},
		["Thief"] = {0.80, 0.86},
		["Ninja"] = {0.80, 0.88},
		["Samurai"] = {0.80, 0.86},
		["Necromancer"] = {0.88, 0.96},
		["Lich"] = {0.80, 0.86},
		["Bone Lord"] = {1.00, 1.10},
		["Monk"] = {0.88, 0.95},
		["Shadowfist"] = {0.80, 0.86},
		["Iron Sage"] = {0.85, 0.93},
		["Templar"] = {0.88, 0.95},
		["Inquisitor"] = {0.88, 0.95},
		["Sentinel"] = {0.88, 0.95},
	},

	-- the leaders: every other class is at most 1 / (1 + lead) of the Deadeye's boss damage, and of the Elementalist's damage on a
	-- pack of 5 (with the pack cleave), at every level of `levels`
	lead = 0.08,
}
