-- spell_factor_config.lua: the class factor on spell damage (owner 2026-10-20, after the cooldown ladder: "apply your
-- retune proposals"; server/data/spells/README.md "Class spell factor"). Pure data. Rules: spell_factor_core.lua (tested
-- by server/tests/spell_factor_test.lua); applied in passivetree_effects.lua (the ChaosPassiveDealt event) to the damage a
-- player deals with origin ORIGIN_SPELL; server/tools/rotation_sim.py reads this table too, so its numbers match.
--
-- The cooldown ladder (2026-10-20) cut the long cooldowns of the big area spells; the classes built on them gained most
-- (rotation_sim.py: the Templar line +41 to +76% at levels 300-1000, the Elementalist, Illusionist and Necromancer line
-- +21 to +59%, the Shadowfist +44% at 1000) and the Beastmaster lost 22% at 300. One factor per class keeps the ladder's
-- order (it ranks a class's spells by damage per cast). A class not listed keeps 1.

ChaosSpellFactorConfig = {
	-- server vocation id -> factor on the damage of the class's spells (docs/CLASSES.md vocation ids)
	byVocation = {
		[23] = 0.6,   -- Templar
		[25] = 0.6,   -- Sentinel
		[24] = 0.7,   -- Inquisitor
		[5] = 0.7,    -- Elementalist
		[10] = 0.7,   -- Illusionist
		[21] = 0.7,   -- Lich
		[22] = 0.7,   -- Bone Lord
		[18] = 0.7,   -- Shadowfist
		[20] = 0.8,   -- Necromancer
		[15] = 1.25,  -- Beastmaster
	},
}

return ChaosSpellFactorConfig
