-- pvp_balance_config.lua (O444, 2026-11-09): the model parameters and the limits of the PvP model, tools/pvp_model.py --check (CI).
-- Plain table, numbers only, loaded with dofile or read by the tool with regular expressions (keep `name = number` on one line and an
-- exception row as `["Class"] = {metric = number}`). Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls.
-- server/README.md "PvP model (O444)" has the method, the table and the findings.
--
-- COMPUTED, NOT MEASURED. Nobody ran a PvP DPS test. The model puts class_dps_model.py's damage (measured on dummies, then moved by
-- the changes since), survival_model.py's layers (health pool, armour, absorbs, dodge, toughness, potions and self heal) and the PvP
-- rules of the configs (the engine's half damage, healing_rules_core.lua healingTaken, the arena's fightSeconds) into a duel of two
-- classes at one level. It screens for a one shot, an unkillable class and a class that wins nearly every duel. It does not forecast a
-- ladder: no movement, line of sight, stun, snare or crowd control, no mana spent on spells, no parties.
--
-- The limits below are what a sane game passes. Where today's game does not, a row in `exceptions` names the class (and the level
-- with "Class@100") and carries a `-- O444:` note with the gap; an exception holds today's value, so it catches a class getting worse
-- and is deleted when the class is fixed.
return {
	-- O473 (2026-11-10): the damage a player (or a summon or companion of a player) deals to ANOTHER player is multiplied by this factor
	-- of the ATTACKER's level, geometric between two rows ({level, factor}; pvp_scale_core.lua, applied once in passivetree_effects.lua
	-- ChaosPassiveDealt). The one additive damage pool and the weapon, gear and tier changes of the same round raise typical damage; a
	-- duel keeps today's length. The design's first fit: it is re-fitted when every package of the round is in. Monsters, heals and hits
	-- on monsters are never scaled. tools/pvp_model.py reads this table.
	damageScale = {{100, 1.00}, {200, 0.94}, {300, 0.89}, {500, 0.79}, {700, 0.76}, {1000, 0.48}, {1500, 0.52}, {2000, 0.46}},

	-- the levels of the table and of the check (class_dps_model.py measures 100, 500 and 1000; survival_model.py has builds for them)
	levels = {100, 500, 1000},

	-- the burst window: the first seconds of a fight (the target needs about this long to react)
	burstSeconds = 3,
	-- a duel where the kill times are within this share of each other, or the health shares left after fightSeconds within this
	-- many points, is a draw (hit variance, who opens)
	drawBand = 0.10,
	-- the attacks of a class are this share physical (armour, physical absorb, dodge), the rest elemental (elemental absorb). One
	-- number for every class: rotation_model.csv has no damage type
	physicalShare = 0.5,

	-- LIMITS, at every level of `levels`, for every class
	-- the damage a class deals in burstSeconds, after the PvP rules and the median class's layers, as a share of the median class's
	-- health pool: a class that reaches 1.0 kills the median class before it can react. At most
	burstMax = 0.90,
	-- seconds to kill the median class with no healing, at least (nobody kills a player of its own level in under this)
	killMin = 4,
	-- ... and at most (a class that needs longer without healing is not a threat)
	killMax = 15,
	-- seconds to die to the median class with no healing, at least (a glass cannon the median class kills faster than this is no class)
	dieMin = 4,
	-- healing per second a class has in PvP (potions and self heal, x healingTaken) over the damage per second the median class
	-- deals to it, at most. 1.0 would be "the median class can always kill it". O444: TEMPORARY. Today EVERY class out-heals the
	-- median class at every level (1.07 to 7.80: Inquisitor at 1000 the least, Iron Sage at 100 the most), so with its potions
	-- (one Everfull potion a second, survival_balance_config.lua) no class can be killed by damage alone and every duel with
	-- healing is a draw. The owner decides (README "PvP model (O444)"); the value pins the worst class of today
	sustainMax = 8.5,
	-- no class wins or loses more than this share of its 20 duels (damage race, no healing). A draw is neither
	duelShareMax = 0.90,

	-- the classes that are outside a limit today, each with its value of today as the limit (so a worse state fails)
	exceptions = {
		-- O444: burst. The Deadeye's best set opens with its long cooldown hits inside 3 s (2.4 and 2.55 times its average damage
		-- per second): it deals 0.93 of the median class's pool at 500 and 1.00 at 1000, a one shot in the opening window
		["Deadeye@500"] = {burst = 0.93},
		["Deadeye@1000"] = {burst = 1.01},
		-- O444: burst at level 100, the sets have 4 or 5 spells and the pools are small: 0.98 and 0.96.
		-- O442: the Recommended builds reach a keystone in their first 23 to 30 points and hold fewer health nodes there, so the
		-- median pool at level 100 fell from 1924 to 1842 (-4%; levels 500 and 1000 moved under 2%). The same bursts read 1.011
		-- (Illusionist), 0.994 (Necromancer) and 0.924 (Beastmaster, was 0.89) against the smaller pool; the pins round up
		["Illusionist@100"] = {burst = 1.02},
		["Beastmaster@100"] = {burst = 0.93},
		-- O455: the Deadeye traded Skewering Line for Seeker Mine, so its level 100 set has 4 spells instead of 5, like the
		-- Beastmaster's. The first 3 s hold the same two casts as before. The set's average fell about 14% in rotation_sim.py,
		-- while the damage per second read here is still the measured one of the old kit. The share rises from 0.83 to 0.97
		-- with no more damage in the opening. Measure the Deadeye again, then drop this row
		["Deadeye@100"] = {burst = 0.98},

		-- O444: duels, damage race. Wins: the Necromancer line is the highest damage class of its level with a mana shield pool two
		-- to four times the others' (Ward of the Mind: health plus mana, survival_model.py; the model does not spend that mana on
		-- spells). The Bone Lord wins all 20 at 500 and 1000, the Necromancer 20 and 19 at 100 and 500. The Necromancer at 100 also
		-- has the burst of 0.96 named above
		["Necromancer@100"] = {burst = 1.00, wins = 20},
		["Necromancer@500"] = {wins = 19},
		["Bone Lord@500"] = {wins = 20},
		["Bone Lord@1000"] = {wins = 20},
		-- O444: duels, damage race. Losses: the two support classes in heavy or medium armour with no absorb lane (the weak spots
		-- survival_model.py names too): the Inquisitor loses all 20 at 1000 and 19 at 500, the Iron Sage 19 at 500 and 1000
		["Inquisitor@500"] = {losses = 19},
		["Inquisitor@1000"] = {losses = 20},
		["Iron Sage@500"] = {losses = 19},
		["Iron Sage@1000"] = {losses = 19}
	}
}
