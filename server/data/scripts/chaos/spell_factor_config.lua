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

-- Shorter cooldowns for the strongest spells (O176, 2026-10-24; owner: "lower the cooldown of the strongest spells, to
-- raise the DPS of every class"; server/data/spells/README.md "Shorter cooldowns for the strongest spells (O176)"). The
-- ladder is now 2, 4, 6, 7 ... 13 s. Every curve below was refit with server/tools/rotation_sim.py: new factor = old factor
-- x the median gain of all classes / the class's own raw gain, at each knot (3% tolerance). Result: every class gains the
-- same, about +1% at level 100 and about +19% from level 300. The Mystic (level 1) and the Elementalist (level 5) got
-- curve knots, and the end values (byVocation, level 1000) follow.

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
		[1] = 1.07,   -- Mystic
		[3] = 1.03,   -- Ranger
		[4] = 1.03,   -- Warrior
		[5] = 0.64,   -- Elementalist
		[7] = 1.01,   -- Deadeye
		[8] = 1.05,   -- Juggernaut
		[10] = 0.74,   -- Illusionist
		[11] = 0.94,   -- Thief (C2, 2026-10-24: weapon strikes too, ChaosSpell.weaponStrike)
		[12] = 1.17,   -- Ninja
		[13] = 1.15,   -- Samurai
		[14] = 1.04,   -- Berserker
		[15] = 1.07,   -- Beastmaster
		[17] = 0.96,   -- Monk
		[18] = 0.79,   -- Shadowfist
		[19] = 1.16,   -- Iron Sage
		[20] = 0.67,   -- Necromancer
		[21] = 0.92,   -- Lich
		[22] = 0.66,   -- Bone Lord
		[23] = 0.64,   -- Templar
		[24] = 0.76,   -- Inquisitor
		[25] = 0.64,   -- Sentinel
	},
	-- server vocation id -> {level, factor} points (see above)
	byLevel = {
		[1] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 1.02}, {70, 1.02}, {80, 1.02}, {90, 1.04}, {100, 1.01}, {120, 1.04}, {140, 1.06}, {150, 1.00}, {180, 1.00}, {200, 1.00}, {230, 1.00}, {260, 1.02}, {290, 1.04}, {300, 1.10}, {450, 1.10}, {600, 1.09}, {1000, 1.07}},  -- Mystic
		[3] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 0.99}, {70, 0.99}, {80, 0.99}, {90, 1.00}, {100, 1.00}, {120, 1.03}, {150, 1.05}, {160, 0.87}, {180, 0.81}, {200, 0.82}, {215, 0.84}, {230, 0.72}, {260, 0.73}, {300, 1.04}, {450, 1.04}, {600, 1.04}, {1000, 1.03}},  -- Ranger
		[4] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 1.02}, {70, 1.02}, {80, 1.02}, {85, 1.02}, {90, 1.09}, {100, 1.06}, {120, 1.09}, {150, 1.00}, {180, 1.01}, {200, 1.03}, {215, 1.05}, {230, 0.94}, {260, 1.01}, {290, 1.10}, {300, 1.01}, {450, 1.01}, {600, 1.02}, {1000, 1.03}},  -- Warrior
		[5] = {{15, 0.70}, {30, 0.70}, {40, 0.71}, {60, 0.71}, {70, 0.71}, {80, 0.71}, {90, 0.72}, {100, 0.70}, {120, 0.72}, {140, 0.73}, {150, 0.69}, {180, 0.70}, {200, 0.71}, {215, 0.74}, {230, 0.70}, {260, 0.71}, {290, 0.72}, {300, 0.67}, {400, 0.67}, {450, 0.64}, {600, 0.65}, {1000, 0.64}},  -- Elementalist
		[7] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 0.99}, {70, 0.99}, {80, 0.99}, {90, 1.00}, {100, 1.00}, {120, 1.03}, {150, 1.05}, {160, 0.87}, {180, 0.81}, {200, 0.87}, {215, 0.91}, {230, 0.89}, {260, 0.91}, {270, 0.94}, {280, 0.86}, {300, 0.96}, {450, 1.01}, {600, 1.02}, {1000, 1.01}},  -- Deadeye
		[8] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 1.02}, {70, 1.02}, {80, 1.02}, {85, 1.02}, {90, 1.09}, {100, 1.06}, {120, 1.09}, {150, 1.00}, {180, 1.01}, {200, 1.03}, {215, 1.06}, {230, 0.91}, {260, 0.95}, {290, 1.04}, {300, 0.99}, {450, 0.97}, {600, 1.06}, {1000, 1.05}},  -- Juggernaut
		[10] = {{15, 0.70}, {30, 0.70}, {40, 0.70}, {60, 0.72}, {70, 0.72}, {80, 0.72}, {90, 0.73}, {100, 0.71}, {105, 0.71}, {110, 0.65}, {120, 0.65}, {150, 0.60}, {180, 0.54}, {200, 0.54}, {215, 0.57}, {230, 0.56}, {245, 0.62}, {260, 0.63}, {280, 0.66}, {300, 0.73}, {450, 0.74}, {600, 0.75}, {1000, 0.74}},  -- Illusionist
		[11] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 1.02}, {70, 1.02}, {80, 1.02}, {90, 1.03}, {100, 1.02}, {120, 1.05}, {150, 0.93}, {180, 0.88}, {200, 0.89}, {230, 0.91}, {260, 0.92}, {300, 0.96}, {450, 0.97}, {600, 0.96}, {1000, 0.94}},  -- Thief
		[12] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 1.02}, {70, 1.02}, {80, 1.02}, {90, 1.04}, {100, 0.95}, {120, 0.98}, {150, 0.91}, {180, 1.02}, {200, 1.03}, {215, 1.07}, {230, 1.05}, {260, 1.07}, {270, 0.90}, {300, 0.90}, {350, 0.90}, {360, 1.18}, {450, 1.18}, {600, 1.19}, {1000, 1.17}},  -- Ninja
		[13] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 1.02}, {70, 1.02}, {80, 1.02}, {90, 1.04}, {100, 1.03}, {120, 1.10}, {150, 1.04}, {180, 1.02}, {190, 1.08}, {200, 1.07}, {230, 1.08}, {260, 1.10}, {300, 1.16}, {450, 1.16}, {600, 1.17}, {1000, 1.15}},  -- Samurai
		[14] = {{15, 1.00}, {30, 1.00}, {40, 1.00}, {60, 1.02}, {70, 1.02}, {80, 1.02}, {85, 1.02}, {90, 1.09}, {100, 1.11}, {120, 1.13}, {150, 1.03}, {180, 1.04}, {190, 0.95}, {200, 0.95}, {215, 0.99}, {230, 0.97}, {245, 1.02}, {260, 0.98}, {300, 1.09}, {360, 1.10}, {380, 1.03}, {450, 1.04}, {600, 1.05}, {1000, 1.04}},  -- Berserker
		[15] = {{15, 1.25}, {30, 1.25}, {40, 1.25}, {60, 1.28}, {70, 1.28}, {80, 1.28}, {90, 1.30}, {100, 1.27}, {120, 1.30}, {150, 1.17}, {160, 0.99}, {180, 0.90}, {200, 0.92}, {215, 0.93}, {230, 0.80}, {260, 0.81}, {300, 0.85}, {380, 0.91}, {400, 1.00}, {450, 1.05}, {600, 1.05}, {1000, 1.07}},  -- Beastmaster
		[17] = {{15, 1.00}, {25, 1.05}, {30, 1.00}, {40, 1.00}, {60, 1.03}, {70, 1.01}, {80, 1.01}, {90, 1.02}, {100, 0.99}, {120, 0.93}, {150, 0.95}, {180, 0.97}, {200, 0.98}, {215, 1.02}, {230, 1.00}, {260, 0.91}, {300, 0.94}, {450, 0.95}, {600, 0.96}, {1000, 0.96}},  -- Monk
		[18] = {{15, 0.70}, {25, 0.73}, {30, 0.70}, {40, 0.70}, {60, 0.71}, {70, 0.70}, {80, 0.70}, {90, 0.71}, {100, 0.75}, {120, 0.70}, {140, 0.70}, {150, 0.63}, {180, 0.64}, {200, 0.65}, {230, 0.66}, {260, 0.62}, {300, 0.65}, {450, 0.78}, {600, 0.78}, {1000, 0.79}},  -- Shadowfist
		[19] = {{15, 1.00}, {25, 1.05}, {30, 1.00}, {40, 1.00}, {60, 1.03}, {70, 1.01}, {80, 1.01}, {90, 1.02}, {100, 0.99}, {120, 1.04}, {150, 1.03}, {180, 1.04}, {200, 1.06}, {215, 1.10}, {230, 1.08}, {260, 1.10}, {300, 1.16}, {450, 1.16}, {600, 1.17}, {1000, 1.16}},  -- Iron Sage
		[20] = {{15, 0.80}, {30, 0.80}, {40, 1.00}, {60, 0.94}, {70, 0.81}, {80, 0.80}, {85, 0.76}, {90, 0.78}, {100, 0.76}, {105, 0.73}, {110, 0.64}, {120, 0.59}, {130, 0.60}, {140, 0.56}, {150, 0.56}, {180, 0.54}, {200, 0.55}, {230, 0.47}, {260, 0.49}, {300, 0.51}, {450, 0.56}, {600, 0.60}, {1000, 0.67}},  -- Necromancer
		[21] = {{15, 0.70}, {30, 0.70}, {40, 1.01}, {60, 1.03}, {70, 0.86}, {80, 0.85}, {90, 0.65}, {100, 0.74}, {105, 0.72}, {110, 0.65}, {120, 0.61}, {130, 0.66}, {140, 0.63}, {150, 0.64}, {180, 0.66}, {200, 0.67}, {215, 0.71}, {230, 0.69}, {260, 0.71}, {300, 0.76}, {450, 0.81}, {600, 0.86}, {1000, 0.92}},  -- Lich
		[22] = {{15, 0.70}, {30, 0.70}, {40, 0.88}, {60, 0.90}, {70, 0.70}, {80, 0.70}, {85, 0.62}, {90, 0.49}, {100, 0.48}, {120, 0.36}, {150, 0.58}, {160, 0.59}, {170, 0.53}, {180, 0.54}, {200, 0.55}, {215, 0.57}, {230, 0.53}, {245, 0.51}, {260, 0.54}, {300, 0.57}, {380, 0.61}, {400, 0.56}, {450, 0.57}, {600, 0.60}, {1000, 0.66}},  -- Bone Lord
		[23] = {{15, 0.60}, {30, 0.60}, {39, 0.97}, {40, 0.87}, {45, 0.86}, {50, 0.84}, {55, 0.83}, {59, 0.87}, {60, 0.72}, {70, 0.71}, {80, 0.66}, {90, 0.67}, {100, 0.59}, {120, 0.59}, {150, 0.60}, {180, 0.57}, {200, 0.56}, {215, 0.59}, {230, 0.56}, {260, 0.58}, {300, 0.61}, {450, 0.62}, {600, 0.63}, {1000, 0.64}},  -- Templar
		[24] = {{15, 0.70}, {30, 0.70}, {39, 1.13}, {40, 1.02}, {60, 1.04}, {70, 1.04}, {80, 0.88}, {90, 0.77}, {100, 0.67}, {120, 0.77}, {150, 0.79}, {180, 0.72}, {190, 0.73}, {200, 0.67}, {215, 0.70}, {230, 0.68}, {260, 0.70}, {300, 0.73}, {450, 0.74}, {600, 0.75}, {1000, 0.76}},  -- Inquisitor
		[25] = {{15, 0.60}, {30, 0.60}, {39, 0.97}, {40, 0.87}, {60, 0.89}, {70, 0.89}, {80, 0.76}, {90, 0.76}, {100, 0.59}, {120, 0.55}, {130, 0.57}, {140, 0.54}, {150, 0.61}, {180, 0.56}, {200, 0.57}, {230, 0.52}, {260, 0.53}, {300, 0.55}, {360, 0.56}, {380, 0.62}, {450, 0.63}, {600, 0.64}, {1000, 0.64}},  -- Sentinel
	},
}

return ChaosSpellFactorConfig
