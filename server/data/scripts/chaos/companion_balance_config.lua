-- companion_balance_config.lua (O306, O332): the inputs and the limits of the Beastmaster companion model,
-- tools/companion_model.py --check (CI). Plain table, loaded with dofile. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
-- No engine calls. The wolves' own numbers are Chaos.classes.companion (chaos_constants.lua); server/README.md
-- "Beastmaster companion (O306)" and "Wolves as the main damage (O332)" have the method and the before / after tables.
--
-- The model (computed, not measured in game): what the wolves (the companion's own bites and the four wolf spells) are
-- worth next to the rest of the Beastmaster's damage, for three builds, and how long a companion lives when monsters of its
-- owner's hunting level go for it. Monster damage is the Necromancer minion model's (necro_balance_config.lua
-- monsterDps: a target with the armour of a summon), times `burst` below.
return {
	-- the levels of the report
	levels = {50, 100, 200, 400, 700, 750, 1000},
	-- the levels the limits are checked at (tester report 2026-10-29: a level 400 Beastmaster; O332: a level 750 one)
	checkLevels = {100, 400, 750, 1000},

	-- what the numbers were before O306 (Chaos.classes.companion then), for the before / after table
	legacy = {autoLevel = 0.12, autoSkill = 0.6, healthBase = 500, healthPerLevel = 15, taken = 1.0,
		-- class_tree.lua classDamage.beastmaster then
		classDamage = {{250, 1.0}, {300, 1.14}, {800, 0.97}, {1000, 0.95}},
		-- pace_config.lua cleave.byVocation[15].high then
		cleaveHigh = 1},

	-- the state before O332 (O306): the class damage factor of class_tree.lua then, and the best 5 spells' damage per
	-- second of the kit then (rotation_sim.py, 1 target and 5 targets; the rows are {level, 1 target, 5 targets}, linear
	-- between them): the spell part of the measured class total (C4) was this much rotation, and the model scales it
	-- by the rotation of today (the method of pack_model.py KIT: the change of the rotation x the class's spell-to-total factor)
	before = {
		-- the companion's own bite then (Chaos.classes.companion autoLevel / autoSkill) and the Beastmaster's pack cleave then
		-- (pace_config.lua cleave.byVocation[15].high; it went from 2 to 0 in O332: the wolves have area spells now)
		autoLevel = 1.1, autoSkill = 2.0, cleaveHigh = 2,
		classDamage = {{50, 0.90}, {100, 0.90}, {200, 0.92}, {300, 1.05}, {400, 0.99}, {550, 0.95}, {700, 0.91}, {800, 0.87}, {1000, 0.85}, {1200, 0.81}},
		sim = {{8, 10.50, 10.50}, {20, 26.21, 62.12}, {50, 51.28, 121.93}, {80, 84.64, 206.25}, {100, 127.31, 414.77},
			{110, 134.36, 439.28}, {140, 169.54, 497.82}, {150, 169.63, 499.32}, {160, 214.02, 504.18}, {200, 226.90, 538.78},
			{220, 246.11, 756.87}, {240, 236.53, 728.35}, {250, 244.43, 753.05}, {300, 295.10, 910.77}, {320, 308.47, 954.45},
			{350, 329.13, 1022.00}, {400, 414.56, 1252.21}, {450, 462.60, 1402.50}, {500, 490.20, 1491.05},
			{550, 518.08, 1580.46}, {600, 546.25, 1670.74}, {650, 570.74, 1750.31}, {700, 595.46, 1830.59},
			{750, 620.41, 1911.57}, {800, 645.58, 1993.25}, {850, 670.97, 2075.65}, {900, 696.59, 2158.76},
			{950, 722.44, 2242.58}, {1000, 748.51, 2327.12}, {1100, 776.25, 2423.33}, {1200, 803.98, 2519.54},
			{1500, 887.19, 2808.19}}},

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

	-- the builds (O332). Every wolf hit (bite or spell) is x the owner's wolf factor, ChaosClasses.wolfFactor: Pack Alpha
	-- (class_tree.lua ksPackAlpha bonus) times the Vocation Trials' minion damage (the Beastmaster's two nodes, trials_nodes.lua:
	-- Alpha Bond +25% and Apex Predator +40% in the dealMinion key, read from the file). plain: neither; tree: Pack Alpha, the
	-- state of the measured class totals and of every other model (pack_model.py, boss_model.py: the class total those bands
	-- check is this one); full: both, the tester's build.
	-- `fullFrom`: the level from which the full build is checked (the Trials open at the first levels but a character has them all
	-- only in the late game).
	fullFrom = 400,

	limits = {
		-- seconds a companion lives under `attackers` monsters of the hunting level (with burst), at the check levels
		aliveSecondsMin = 15,
		-- hits of a monster (every 2 s, burst included) one companion takes at least
		hitsMin = 8,
		-- the wolves' share of the Beastmaster's damage in a hunt (bites alive and in contact + the wolf spells' casts, over
		-- all damage) per build: a plain bow Beastmaster stays a bow class (the arrows are most of it), a fully invested one
		-- is a necromancer with wolves (tester report 2026-10-29: a Ranger's main skill is 60-70% of its damage)
		sharePlain = {0.25, 0.50},
		shareTree = {0.35, 0.60},
		shareFull = {0.55, 0.70},
		-- below `earlyBelow` (before Pack Howl, Rending Pounce and the second companion) the wolves are the bites and Feral Command
		earlyBelow = 220,
		shareEarlyPlain = {0.12, 0.35}, shareEarlyTree = {0.15, 0.45},
		-- the total damage of the plain and the full build against the tree build (1 target): a plain Beastmaster is not much
		-- behind (the bows carry it), a full one is ahead for what it invested, not by far (the Trials give every class its
		-- own boost)
		plainOverTree = {0.75, 1.0}, fullOverTree = {1.0, 1.40},
		-- the tree build's total after the change against the state before O332 (O306: the class total of that tuning), on a
		-- pack of 5 (with the pack cleave of each state) and on 1 target (the pack and boss bands of pack_model.py /
		-- boss_model.py hold the class itself: a pure area class has the lower boss band, and the lead of the Elementalist
		-- on a pack holds it back, so the single target total gives some up for the pack)
		drift5 = 0.08, drift1 = {-0.12, 0.08},
		-- share of the pack fight the companion is alive
		uptimeMin = 0.85,
	},
}
