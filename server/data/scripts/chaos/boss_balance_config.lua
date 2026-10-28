-- boss_balance_config.lua: the limits of the boss damage model, tools/boss_model.py --check (CI).
-- Plain table, loaded with dofile or read by the tool. Lua 5.3 and LuaJIT compatible. No engine calls.
-- server/data/spells/README.md "Boss damage per class" has the method.
--
-- The ratio is a class's damage per second on one boss against the Deadeye's at the same level (computed, not
-- measured in game). Rows are "Class" = {low, high}, the ratio must stay inside at every level of `levels`.
return {
	levels = {300, 800, 1000, 1200},

	-- ENFORCED today: the current state with a margin of 0.03 each side. A change of a class's single-target
	-- damage beyond it fails CI, so it is never an accident. Move a row together with the proposal below.
	limits = {
		["Warrior"] = {0.48, 0.71},
		["Juggernaut"] = {0.53, 0.63},
		["Berserker"] = {0.55, 0.77},
		["Ranger"] = {0.77, 0.85},
		["Deadeye"] = {0.97, 1.03},
		["Beastmaster"] = {0.60, 0.77},
		["Mystic"] = {0.50, 0.64},
		["Elementalist"] = {0.62, 0.73},
		["Illusionist"] = {0.41, 0.61},
		["Thief"] = {0.49, 0.69},
		["Ninja"] = {0.76, 0.89},
		["Samurai"] = {0.41, 0.60},
		["Necromancer"] = {0.54, 0.80},
		["Lich"] = {0.85, 0.92},
		["Bone Lord"] = {0.85, 0.94},
		["Monk"] = {0.48, 0.76},
		["Shadowfist"] = {0.78, 0.93},
		["Iron Sage"] = {0.42, 0.66},
		["Templar"] = {0.43, 0.72},
		["Inquisitor"] = {0.75, 0.86},
		["Sentinel"] = {0.40, 0.60},
	},

	-- PROPOSED, not enforced (owner plan 2026-10-28, class identity): Deadeye 1.0; Ninja, Shadowfist and Lich about
	-- 0.9-0.95; burst classes that lose in packs gain here; pure area classes (Elementalist, Berserker, Bone Lord,
	-- Beastmaster) 0.7-0.8 (they win packs); mixed 0.75-0.85; tanks and healers lower. Which classes are burst and
	-- which are mixed is a first guess to be settled with the pack bands. The tool prints which rows break it.
	proposed = {
		["Deadeye"] = {0.98, 1.02},
		["Ninja"] = {0.90, 0.95},
		["Shadowfist"] = {0.90, 0.95},
		["Lich"] = {0.90, 0.95},
		["Ranger"] = {0.85, 0.95},
		["Inquisitor"] = {0.85, 0.95},
		["Thief"] = {0.85, 0.95},
		["Samurai"] = {0.85, 0.95},
		["Illusionist"] = {0.80, 0.90},
		["Mystic"] = {0.75, 0.85},
		["Warrior"] = {0.75, 0.85},
		["Necromancer"] = {0.75, 0.85},
		["Monk"] = {0.75, 0.85},
		["Iron Sage"] = {0.75, 0.85},
		["Elementalist"] = {0.70, 0.80},
		["Berserker"] = {0.70, 0.80},
		["Bone Lord"] = {0.70, 0.80},
		["Beastmaster"] = {0.70, 0.80},
		["Juggernaut"] = {0.60, 0.70},
		["Templar"] = {0.60, 0.70},
		["Sentinel"] = {0.60, 0.70},
	},
}
