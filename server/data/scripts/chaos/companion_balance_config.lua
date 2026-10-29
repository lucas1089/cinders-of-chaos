-- companion_balance_config.lua (O306): the inputs and the limits of the Beastmaster companion model,
-- tools/companion_model.py --check (CI). Plain table, loaded with dofile. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
-- No engine calls. The companion's own numbers are Chaos.classes.companion (chaos_constants.lua); server/README.md
-- "Beastmaster companion (O306)" has the method and the before / after table.
--
-- The model (computed, not measured in game): what the companion's own bites are worth next to the rest of the
-- Beastmaster's damage, and how long it lives when monsters of its owner's hunting level go for it. Monster damage is
-- the Necromancer minion model's (necro_balance_config.lua monsterDps: a target with the armour of a summon), times
-- `burst` below.
return {
	-- the levels of the report
	levels = {50, 100, 200, 400, 700, 1000},
	-- the levels the limits are checked at (tester report 2026-10-29: a level 400 Beastmaster)
	checkLevels = {100, 400, 1000},

	-- what the numbers were before O306 (Chaos.classes.companion then), for the before / after table
	legacy = {autoLevel = 0.12, autoSkill = 0.6, healthBase = 500, healthPerLevel = 15, taken = 1.0,
		-- class_tree.lua classDamage.beastmaster then
		classDamage = {{250, 1.0}, {300, 1.14}, {800, 0.97}, {1000, 0.95}},
		-- pace_config.lua cleave.byVocation[15].high then
		cleaveHigh = 1},

	-- monsters of the hunting level going for one companion at once (the tester: "I tank most, 2 go for him")
	attackers = 2,
	-- the monsters' real hits come in bursts (waves, beams, a pack's first volley) above their average per second:
	-- the tester's companion fell to 3 hits where the average dps said 10. Monster damage x burst in the alive time.
	burst = 1.5,
	-- the share of the time a companion stands next to the target and bites (it walks with the owner, chases, waits for a bite; fitted so the old bites read the 4% the tester saw)
	contact = 0.6,
	-- a pack fight: the share of the clear time an average pack monster is alive and hitting (minion model: 0.55); the
	-- monsters going for the companions are huntAttackers in all, split between them; a dead companion is called again
	-- with Wild Bond between packs (full health at the start of a pack)
	alive = 0.55,
	huntAttackers = 2,

	limits = {
		-- seconds a companion lives under `attackers` monsters of the hunting level (with burst), at the check levels
		aliveSecondsMin = 15,
		-- hits of a monster (every 2 s, burst included) one companion takes at least
		hitsMin = 8,
		-- the companion's share of the Beastmaster's damage in a hunt (bites alive and in contact / all damage)
		share = {0.20, 0.30},
		-- the Beastmaster's total damage after the change against before it (the class damage factor of class_tree.lua
		-- and the cleave's high end in pace_config.lua take the bites' gain back, so the class stays in its bands)
		-- against before, on a pack of 5 (with the cleave): at most this far; on 1 target: between these (the bites add to
		-- 1 target; the boss band of boss_balance_config.lua is checked by boss_model.py)
		drift5 = 0.06, drift1 = {0.0, 0.16},
		-- share of the pack fight the companion is alive
		uptimeMin = 0.85,
	},
}
