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
ChaosSpellScalingConfig = {
	mlShare = {
		per = 300,
		normalise = true,
		ref = {{1, 0}, {100, 10}, {300, 25}, {600, 32}, {1000, 40}},
	},
}
return ChaosSpellScalingConfig
