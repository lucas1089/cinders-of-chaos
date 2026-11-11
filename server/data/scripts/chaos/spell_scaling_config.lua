-- spell_scaling_config.lua: the magic level share of weapon spells (O468, owner 2026-11-10: "How are the players' spells
-- scaling? It needs to be by skill, magic level and character level."; the orchestrator's rule, answered "go ahead like
-- that"). Pure data. Rules: spell_scaling_core.lua (tested by server/tests/spell_scaling_test.lua); the guard that keeps
-- it true: server/tests/spell_inputs_test.lua. Documented in server/README.md "Spell scaling (O468)".
--
-- A spell of a weapon line (Warrior, Ranger, Thief, Monk lines, the weapon spells of any class) reads the character
-- level, its weapon skill and now a magic level share: its base damage is multiplied by (1 + ML / per). A caster's
-- magic level IS its skill, so a caster spell gets nothing extra.
--
-- `normalise`: the measured tables (class_dps_measured.csv, the balance models) were taken with the typical character
-- of server/tools/rotation_sim.py ANCHORS, whose weapon class magic level is 'ml_other'. With normalise on the factor is
-- divided by (1 + refML(level) / per), refML the typical magic level at that level (linear between the anchors below,
-- copied from ANCHORS 'ml_other': tests/spell_scaling_test.lua reads the two and fails when they drift). So a typical
-- character deals what it dealt before, and every magic level above or below typical moves a weapon spell by about
-- 1 / per = 0.33%.
--
-- O472 (2026-11-10, owner: "You can do everything"; the damage design, section B5): the weapon values grow with the level.
-- `weaponGrowth` is the factor W(level) on the weapon term of a hit: {level, W} rows, straight in the logarithm of the level
-- between the rows, 1.00 up to level 100, flat above 2000. A weapon's attack grows by a = 1 + (W - 1) / skillShare (skill x
-- attack is about 85% of a weapon hit); server/tools/weapon_growth.py holds the same table (tests/weapon_growth_test.lua and
-- tools/weapon_growth_test.py hold the two equal).
-- A caster's spell does not read a wand, so the same growth reaches it as one factor on the caster's spells:
--   1 + (W(level) - 1) x min(caster.cap, wand / caster.wandMean(level))
-- `wand` is the mean damage of the wand or rod in the hands (0 without one: factor 1), `wandMean` the mean wand of the
-- level (the gear sets' wand curve, tools/install_gear_sets.py WEAPON_CURVES 'wand': a wand of the right band gives exactly W,
-- a better one up to `cap` times the growth).
ChaosSpellScalingConfig = {
	mlShare = {
		per = 300,
		normalise = true,
		ref = {{1, 0}, {100, 10}, {300, 25}, {600, 32}, {1000, 40}},
	},
	skillShare = 0.85,
	weaponGrowth = {{100, 1.00}, {200, 1.14}, {300, 1.26}, {500, 1.42}, {700, 1.55}, {850, 1.85}, {1000, 2.20}, {1500, 2.35},
		{2000, 2.60}},
	caster = {
		cap = 1.2,
		-- the Necromancer line's minion hits (necro_lib.lua minionFactor) take the caster factor too: they read the level and the magic
		-- level like the owner's spells and have no weapon term; false leaves them as they were
		minions = true,
		-- the Beastmaster's wolves, companion bite and pet aura (classes.lua biteValuesFor / autoBiteValuesFor, pets.lua) take the same
		-- growth keyed on the attack of the owner's bow or weapon against `bowMean` (the bow curve of install_gear_sets.py): a bow of the
		-- band gives W, none gives 1; false leaves them as they were
		wolves = true,
		bowMean = {{8, 31}, {50, 38}, {100, 68}, {200, 83}, {300, 94}, {400, 103}, {500, 111}, {700, 125}, {850, 155}, {1000, 191},
			{1500, 212}, {2000, 245}},
		wandMean = {{8, 16}, {50, 40}, {100, 62}, {200, 99}, {300, 119}, {400, 138}, {500, 151}, {700, 178}, {850, 226},
			{1000, 285}, {1500, 331}, {2000, 398}},
	},
}
return ChaosSpellScalingConfig
