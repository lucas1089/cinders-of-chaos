-- manashield_config.lua: the numbers and switches of the mana shield (server/README.md "Magic Shield"). Pure data.
-- Rules: manashield_core.lua (tested by server/tests/manashield_test.lua), engine glue: manashield.lua.
--
-- The classic Magic Shield is back (owner 2026-10-21: "quero aquele antigo, que o usuário toma dano primeiro da mana e
-- depois da hp. somente pra mages e rangers"; the Necromancer counts as a mage): Ward of the Mind (spell 44, the stock "utamo vita", our words "tor ael")
-- is the stock CONDITION_MANASHIELD of the base server, 200 s: every hit goes to the mana first and only what the mana
-- cannot take goes to the health. No pool, no cap. The engine does it (game.cpp combatChangeHealth); no Chaos patch
-- changes it. Who may learn and cast it: server/tools/patch_spell_cap.py CAP and add_vocations.py LINE_STOCK_SPELLS.

ChaosManaShieldConfig = {
	-- the classes of Ward of the Mind (docs/CLASSES.md vocation ids): the Mystic line (Mystic 1, Elementalist 5,
	-- Illusionist 10), the Necromancer line (Necromancer 20, Lich 21, Bone Lord 22; the owner counts it as a mage) and
	-- the Ranger line (Ranger 3, Deadeye 7, Beastmaster 15). tests/manashield_test.lua checks that the server tools and
	-- the client spell data name the same classes.
	vocations = {1, 5, 10, 20, 21, 22, 3, 7, 15},

	-- parity: the Chaos systems that make a monster hit a player harder (monster tiers, boss mechanics, the raid, the
	-- pocket boss, the invasion, the Vocation Trials, Rampage, Shadow Twin) scale the part the mana shield takes too.
	-- Without it a mana shield skipped every one of them (they are onHealthChange events, which the engine runs only on
	-- what the mana could not take). false: the mana part sees only the events that have their own mana path.
	parity = true,

	-- a mark (the mana event scaled this hit, the health events of the same hit must not scale the rest again) lives at
	-- most this long: the engine runs both in one call, so it only bounds a mark no health event consumed
	markMs = 10,
}

return ChaosManaShieldConfig
