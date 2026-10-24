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
-- Warrior, Juggernaut, Berserker, Iron Sage and Beastmaster came out within 3% of 1 on the first pass (O136 gave them a curve).
-- The Thief line was left out then: its blade and shuriken strikes are weapon hits, which the event never touches. C2
-- (2026-10-24) lists it: ChaosSpell.weaponStrike (spells/chaos/_common.lua) multiplies a spell's strike by the same curve
-- (ChaosSpellFactor.forVocation) before it is dealt; auto attacks (ORIGIN_MELEE / ORIGIN_RANGED outside a spell) stay unscaled.

-- Level curve (O136, 2026-10-23; owner: "balanceie o jogo ..."; server/data/spells/README.md "Combat pass (O136)"). One factor
-- per class could not hold the levels 30-200 and 300-1000 together: the parity pass left dips of -16 to -43% at levels 30-100
-- (Necromancer, Bone Lord, Monk, Beastmaster, Templar, Inquisitor, Sentinel) and spikes of +27 to +42% at 200 (Illusionist,
-- Ranger, Deadeye). `byLevel[voc]` is a list of {level, factor} points: the factor is flat below the first point, linear
-- between points and the last point's value above it (spell_factor_core.lua F.forVocation). The points are fitted with
-- server/tools/rotation_sim.py to put each class's best-set score back to its value before the attack kit (commit 5cd77f1f)
-- at the point's level. `byVocation` holds the factor above the last point (level 1000 and up) and is the whole factor of a
-- class without a curve; tests/spell_factor_test.lua checks that the two agree.

ChaosSpellFactorConfig = {
	-- server vocation id -> factor on the damage of the class's spells at the end of its curve (docs/CLASSES.md vocation ids)
	byVocation = {
		[3] = 1.12,   -- Ranger
		[4] = 1.00,   -- Warrior
		[5] = 0.70,   -- Elementalist (no curve)
		[7] = 1.25,   -- Deadeye
		[8] = 1.09,   -- Juggernaut
		[10] = 0.73,   -- Illusionist
		[11] = 0.91,   -- Thief (C2, 2026-10-24: weapon strikes too, ChaosSpell.weaponStrike)
		[12] = 1.09,   -- Ninja
		[13] = 1.05,   -- Samurai
		[14] = 1.08,   -- Berserker
		[15] = 1.17,   -- Beastmaster
		[17] = 0.87,   -- Monk
		[18] = 0.80,   -- Shadowfist
		[19] = 0.99,   -- Iron Sage
		[20] = 0.69,   -- Necromancer
		[21] = 0.92,   -- Lich
		[22] = 0.71,   -- Bone Lord
		[23] = 0.63,   -- Templar
		[24] = 0.77,   -- Inquisitor
		[25] = 0.60,   -- Sentinel
	},
	-- server vocation id -> {level, factor} points (see above)
	byLevel = {
		[3] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 1.00}, {70, 1.00}, {80, 1.00}, {90, 1.00}, {100, 0.98}, {120, 0.98}, {150, 0.98}, {180, 0.89}, {200, 0.89}, {230, 0.85}, {260, 0.85}, {300, 1.13}, {450, 1.13}, {600, 1.12}, {1000, 1.12}},  -- Ranger
		[4] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 1.00}, {70, 1.00}, {80, 1.00}, {90, 1.00}, {100, 1.00}, {120, 1.00}, {150, 0.91}, {180, 0.94}, {200, 0.94}, {230, 0.90}, {260, 0.94}, {300, 1.04}, {450, 1.04}, {600, 1.04}, {1000, 1.00}},  -- Warrior
		[7] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 1.00}, {70, 1.00}, {80, 1.00}, {90, 1.00}, {100, 0.98}, {120, 0.98}, {150, 0.98}, {180, 0.89}, {200, 0.98}, {230, 0.98}, {260, 0.98}, {300, 1.14}, {450, 1.26}, {600, 1.26}, {1000, 1.25}},  -- Deadeye
		[8] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 1.00}, {70, 1.00}, {80, 1.00}, {90, 1.00}, {100, 1.00}, {120, 1.00}, {150, 0.91}, {180, 0.91}, {200, 0.91}, {230, 0.89}, {260, 0.92}, {300, 1.02}, {450, 1.03}, {600, 1.11}, {1000, 1.09}},  -- Juggernaut
		[10] = {{15, 0.70}, {30, 0.70}, {40, 0.70}, {60, 0.70}, {70, 0.70}, {80, 0.70}, {90, 0.70}, {100, 0.70}, {120, 0.70}, {150, 0.63}, {180, 0.52}, {200, 0.51}, {230, 0.64}, {260, 0.63}, {300, 0.74}, {450, 0.74}, {600, 0.74}, {1000, 0.73}},  -- Illusionist
		[11] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 1.02}, {70, 1.02}, {80, 1.06}, {90, 1.06}, {100, 1.07}, {120, 1.08}, {150, 0.95}, {180, 0.93}, {200, 0.93}, {230, 0.89}, {260, 0.89}, {300, 0.89}, {450, 0.90}, {600, 0.90}, {1000, 0.91}},  -- Thief
		[12] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 1.02}, {70, 1.02}, {80, 1.02}, {90, 1.02}, {100, 0.98}, {120, 0.98}, {150, 0.91}, {180, 0.99}, {200, 0.99}, {230, 0.99}, {260, 0.99}, {270, 0.88}, {300, 0.84}, {350, 0.84}, {360, 1.10}, {450, 1.10}, {600, 1.10}, {1000, 1.09}},  -- Ninja
		[13] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 1.02}, {70, 1.02}, {80, 1.02}, {90, 1.02}, {100, 1.04}, {120, 1.12}, {150, 1.06}, {180, 1.00}, {200, 1.12}, {230, 1.06}, {260, 1.06}, {300, 1.06}, {450, 1.06}, {600, 1.06}, {1000, 1.05}},  -- Samurai
		[14] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 1.00}, {70, 1.00}, {80, 1.00}, {90, 1.00}, {100, 1.05}, {120, 1.04}, {150, 0.94}, {180, 0.94}, {200, 0.91}, {230, 0.91}, {260, 1.00}, {300, 1.07}, {450, 1.09}, {600, 1.09}, {1000, 1.08}},  -- Berserker
		[15] = {{15, 1.25}, {30, 1.25}, {40, 1.25}, {60, 1.25}, {70, 1.25}, {80, 1.25}, {90, 1.25}, {100, 1.21}, {120, 1.21}, {150, 1.11}, {180, 0.98}, {200, 0.98}, {230, 0.93}, {260, 0.93}, {300, 0.93}, {450, 1.12}, {600, 1.14}, {1000, 1.17}},  -- Beastmaster
		[17] = {{15, 1.00}, {30, 1.07}, {40, 1.07}, {60, 1.05}, {70, 1.03}, {80, 1.03}, {90, 1.03}, {100, 1.03}, {120, 0.93}, {150, 0.93}, {180, 0.93}, {200, 0.93}, {230, 0.93}, {260, 0.88}, {300, 0.87}, {450, 0.87}, {600, 0.87}, {1000, 0.87}},  -- Monk
		[18] = {{15, 0.70}, {30, 0.75}, {40, 0.75}, {60, 0.73}, {70, 0.72}, {80, 0.72}, {90, 0.72}, {100, 0.75}, {120, 0.67}, {150, 0.65}, {180, 0.65}, {200, 0.65}, {230, 0.65}, {260, 0.65}, {300, 0.65}, {450, 0.78}, {600, 0.78}, {1000, 0.80}},  -- Shadowfist
		[19] = {{15, 1.00}, {30, 1.07}, {40, 1.07}, {60, 1.05}, {70, 1.03}, {80, 1.03}, {90, 1.03}, {100, 1.03}, {120, 1.07}, {150, 0.99}, {180, 0.99}, {200, 0.99}, {230, 0.99}, {260, 0.99}, {300, 0.99}, {450, 0.99}, {600, 0.99}, {1000, 0.99}},  -- Iron Sage
		[20] = {{15, 0.80}, {30, 0.80}, {40, 1.00}, {60, 0.92}, {70, 0.79}, {80, 0.78}, {90, 0.71}, {100, 0.71}, {120, 0.61}, {150, 0.60}, {180, 0.58}, {200, 0.58}, {230, 0.54}, {260, 0.55}, {300, 0.55}, {450, 0.59}, {600, 0.63}, {1000, 0.69}},  -- Necromancer
		[21] = {{15, 0.70}, {30, 0.70}, {40, 1.01}, {60, 1.01}, {70, 0.84}, {80, 0.83}, {90, 0.68}, {100, 0.79}, {120, 0.71}, {150, 0.76}, {180, 0.75}, {200, 0.76}, {230, 0.76}, {260, 0.77}, {300, 0.78}, {450, 0.82}, {600, 0.86}, {1000, 0.92}},  -- Lich
		[22] = {{15, 0.70}, {30, 0.70}, {40, 0.88}, {60, 0.88}, {70, 0.68}, {80, 0.68}, {90, 0.53}, {100, 0.53}, {120, 0.40}, {150, 0.66}, {180, 0.67}, {200, 0.67}, {230, 0.60}, {260, 0.55}, {300, 0.55}, {450, 0.61}, {600, 0.64}, {1000, 0.71}},  -- Bone Lord
		[23] = {{15, 0.60}, {30, 0.60}, {40, 1.01}, {45, 0.99}, {50, 0.97}, {55, 0.96}, {59, 1.00}, {60, 0.80}, {70, 0.79}, {80, 0.71}, {90, 0.71}, {100, 0.64}, {120, 0.60}, {150, 0.60}, {180, 0.56}, {200, 0.56}, {230, 0.56}, {260, 0.57}, {300, 0.57}, {450, 0.59}, {600, 0.61}, {1000, 0.63}},  -- Templar
		[24] = {{15, 0.70}, {30, 0.70}, {40, 1.18}, {60, 1.17}, {70, 1.17}, {80, 0.98}, {90, 0.86}, {100, 0.76}, {120, 0.82}, {150, 0.82}, {180, 0.73}, {200, 0.73}, {230, 0.73}, {260, 0.73}, {300, 0.73}, {450, 0.74}, {600, 0.75}, {1000, 0.77}},  -- Inquisitor
		[25] = {{15, 0.60}, {30, 0.60}, {40, 1.01}, {60, 1.00}, {70, 1.00}, {80, 0.84}, {90, 0.83}, {100, 0.62}, {120, 0.58}, {150, 0.61}, {180, 0.55}, {200, 0.55}, {230, 0.56}, {260, 0.56}, {300, 0.56}, {450, 0.57}, {600, 0.58}, {1000, 0.60}},  -- Sentinel
	},
}

return ChaosSpellFactorConfig
