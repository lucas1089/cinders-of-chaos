-- spell_factor_config.lua: the class factor on spell damage (owner 2026-10-20, after the cooldown ladder: "apply your
-- retune proposals"; server/data/spells/README.md "Class spell factor"). Pure data. Rules: spell_factor_core.lua (tested
-- by server/tests/spell_factor_test.lua); applied in passivetree_effects.lua (the ChaosPassiveDealt event) to the damage a
-- player deals with origin ORIGIN_SPELL; server/tools/rotation_sim.py reads this table too, so its numbers match.
--
-- The cooldown ladder (2026-10-20) cut the long cooldowns of the big area spells; the classes built on them gained most
-- (rotation_sim.py: the Templar line +41 to +76% at levels 300-1000, the Elementalist, Illusionist and Necromancer line
-- +21 to +59%, the Shadowfist +44% at 1000) and the Beastmaster lost 22% at 300. One factor per class keeps the ladder's
-- order (it ranks a class's spells by damage per cast). A class not listed keeps 1.
--
-- Retuned 2026-10-23 with the attack kit (every class has 10 attack spells: server/data/spells/README.md "Attack spell
-- parity"). The 37 new spells move every class's cooldown ladder (a class with more spells has more rungs, so its old
-- spells wait longer), and the kit adds damage of its own. The factors below put the best-set score of each class back
-- to its value before the kit at levels 300, 600 and 1000 (within 4% except where the README table says otherwise). The
-- Warrior, Juggernaut, Berserker, Iron Sage and Beastmaster came out within 3% of 1, so they are not listed (the Beastmaster
-- was 1.25: its ladder gained a rung that its minion-less spells now fill). The Thief line is not listed either: its
-- blade and shuriken strikes are weapon hits, which the factor never touches (the kit's strengths are set per spell).

ChaosSpellFactorConfig = {
	-- server vocation id -> factor on the damage of the class's spells (docs/CLASSES.md vocation ids)
	byVocation = {
		[7] = 1.19,   -- Deadeye
		[3] = 1.06,   -- Ranger
		[17] = 0.87,  -- Monk
		[21] = 0.82,  -- Lich
		[24] = 0.75,  -- Inquisitor
		[18] = 0.74,  -- Shadowfist
		[10] = 0.73,  -- Illusionist
		[5] = 0.7,    -- Elementalist
		[23] = 0.6,   -- Templar
		[20] = 0.59,  -- Necromancer
		[22] = 0.59,  -- Bone Lord
		[25] = 0.57,  -- Sentinel
	},
}

return ChaosSpellFactorConfig
