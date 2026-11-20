-- Spell upgrades (O686 phase 3): the limits and the inputs of tools/spell_upgrade_model.py. Plain table, read by the model only
-- (the game never loads it). Design: docs/SPELL_UPGRADES.md sections 1.4, 5.1, 5.3, 5.5, 5.6; README "Monster health curve and the
-- models (O686 phase 3)". Everything here is computed, never measured in game. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	-- which parts of the full upgrade the monster health curve (spell_ranks_config.lua `health`) pays for. The committed curve is
	-- the full design (rank, Forms, combos, awakening). A release that ships fewer parts sets the flag false here and rewrites the
	-- curve from `spell_upgrade_model.py --derive`; --check fails while the two disagree.
	parts = {rank = true, forms = true, combos = true, awakening = true},

	-- the typical character (design 1.4 and 5.3)
	-- share of the hunt damage the main rotation spell has (a rotation of five spells; the rest is auto attacks and other spells)
	mainShare = 0.16,
	-- the rank of the rotation's average spell against the main spell's: from `from` at `fromLevel` to `to` at `toLevel` (spells join
	-- later), a straight line, flat outside
	avgRank = {from = 0.88, to = 1.0, fromLevel = 1000, toLevel = 2500},
	-- the cooldown cut of a rank is worth this share of the same cut as extra damage in a rotation held by the 2 s group cooldown
	-- (design 1.5: 10% shorter gives +5.6% damage, 1 / (1 - 0.10) - 1 = 11.1% x 0.5)
	cooldownWorth = 0.5,
	-- Forms (design 5.1): +3% a Form, two Forms, spread over the average rank 0 to 20 (a straight line)
	forms = {total = 0.06},
	-- the Form band (design 2.1, phase 4): the gain of one cast with a Form over the cast without it, on one enemy and on a pack of five,
	-- from the real planner (tools/forms_numbers.lua). A Form is -5% to +8% on one, -5% to +12% on five; the best Form of a spell is at
	-- most +8% in the situation it is for (spell_forms_core.lua `situation`: one, pack, both); a Form under -3% on both counts must name
	-- a utility (`utility` of the core); a Form of a pair is not better than its twin on both counts by `twinGap` unless the twin names a
	-- utility; counted power: the mean gain of all Form I rows and of all Form II rows is +3% each, within `countedTol`
	formBand = {one = {-0.05, 0.08}, five = {-0.05, 0.12}, best = 0.08, utilityBelow = -0.03, twinGap = 0.02, counted = 0.03, countedTol = 0.015},
	-- combos (design 4.1, owner 2026-11-20: 10% to 20% a combo): the typical rotation gains `total`, opening at the average rank
	-- `fromRank` (design 4.2: a class combo opens at rank 5, an element reaction is free) and full at `toRank`. Phase 6: the model COUNTS
	-- the gain from the rows of spell_combos_config.lua (triggerShare 0.40 x the mean bonus of the 13 rows = +6.0%); `total` here is the
	-- number the committed health curve was derived with, and --check fails when the two differ by more than 0.3 points
	combos = {total = 0.064, fromRank = 3, toRank = 10},
	-- awakening (design 3.1): spells awakened on the typical character at a level (a straight line between the points, 0 below the first), +3% damage each
	awakening = {perSpell = 0.03, {1900, 0}, {2100, 1}, {2300, 1.5}, {2500, 2}},
	-- the share of a median class's damage that is spell damage (design 5.3: 0.80). The model measures it per class and level from
	-- class_dps_model.py's measured table (the blend of 1 and 5 targets, a hunt is both); `shareTol` is how far the constant may
	-- be from the blend of the median class
	classShare = 0.80,
	shareTol = 0.08,
	-- H = 1 + classShare x (P - 1), written in steps of this (spell_ranks_config.lua `health` is held to it)
	healthStep = 0.01,

	limits = {
		-- the typical character meets today's kill times: H against the typical class gain, the blend of 1 and 5 targets (a hunt
		-- is both). Design 5.3 target 3%
		killTime = 0.03,
		-- the same for one target alone (a boss, spell share 0.73 of the median class) and for five (a pack, 0.91): one H cannot fit
		-- both, the spread of the spell share is real. The boss is a little slower, the pack a little faster, at the cap
		killTimeOneTarget = 0.04,
		killTimeFiveTargets = 0.05,
		-- the committed `health` curve against the derivation, before the step rounding
		healthTol = 0.0055,
		-- the points of refXpPerHour (spell_ranks_config.lua) against progression_model.lua, share
		refXpTol = 0.01,
		-- the main spell reaches rank 20 inside the owner's window (design 1.4: 1500 to 2000)
		rank20 = {1500, 2000},
		-- a no-upgrades character (design 5.6): experience an hour is 1 / H, in points of percent against the design table; the
		-- hours to a level against the design's, in points of percent
		-- 1.2 until phase 6b; 1.3 since: the combo riders add 0.4 points to the combos, H rises 0.01 at level 2000 (1.31 to 1.32) and the
		-- table's -23% there is -24.2% (the design's table is the first design, before the owner's 10-20% combos and the riders)
		noUpgradesXpTol = 1.3,
		noUpgradesHoursTol = 2.5,
		-- the design's table of 5.6: {level, percent less experience an hour}
		noUpgradesXp = {{100, 2}, {500, 9}, {1000, 17}, {2000, 23}, {2500, 27}},
		-- {level, percent more hours to reach the level}
		noUpgradesHours = {{500, 6}, {1000, 14}, {1500, 18}, {2000, 21}, {2200, 24}},
	},

	-- the models' upgrades mode (--upgrades): how far a model's own limits may be widened where the typical class mix differs from
	-- the median class (a class with a low spell share loses ground, design 5.5). Every widening is a named row with its reason; a
	-- model with no row here passes with its own limits unchanged
	-- the typical character's damage gain by level, {level, gain} (the blend of 1 and 5 targets of the median class's spell share x (P - 1)):
	-- what tools/progression_model.lua --upgrades reads, since Lua cannot run the model. `spell_upgrade_model.py --check` holds it to the
	-- derivation (0.0015), `--derive` prints it
	typical = {{100, 1.014}, {200, 1.026}, {300, 1.058}, {400, 1.081}, {500, 1.104}, {600, 1.130}, {700, 1.168}, {800, 1.187},
		{1000, 1.221}, {1300, 1.253}, {1600, 1.294}, {2000, 1.327}, {2200, 1.357}, {2500, 1.402}},

	-- name = {limit = share}: the limit is multiplied by 1 + share in the upgrades mode only (spell_upgrade_model.py widen(name, limit))
	widen = {
		-- the half rule (design 5.2) raises every class's damage against a player by 0.8% (level 100) to 8% (level 1000) of rank and Forms
		-- and nothing in the defence rises with it, so a burst limit that a class touched today (the exception rows of pvp_balance_config.lua:
		-- Beastmaster, Illusionist, Necromancer at level 100 sit on theirs) is 1.5% looser
		pvpBurst = {burstMax = 0.015},
	},
}
