-- Skill training model (O150): the inputs and limits of tools/skill_model.lua (hunting, exercise weapons and offline training
-- tries per hour, skill levels per hour, the value of an exercise weapon hour in hunting hours) and of the exercise weapon
-- bound of tools/store_model.lua --check. Plain table, loaded with dofile; the engine loads it as a script and it only returns a
-- table. Numbers and reasons: docs/PRICES.md "Skill training (O150)". Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- The model is computed from the repository and the engine source, not measured in game. What it follows:
--   * tries needed from skill L to L+1 = skillBase x multiplier^(L - 10)  (Vocation::getReqSkillTries; the multipliers are the
--     <skill id=.../> rows of chaos_vocations*.xml); magic level L to L+1 = 1600 x manamultiplier^L (Vocation::getReqMana)
--   * the stage multiplier of the base server's own script is x5 from level 101 since O154 (skill_stages_config.lua)
--   * hunting: a weapon use is 1 try (Weapon::onUsedWeapon, one per swing or shot at the vocation's attack speed), a spell is
--     its mana cost as mana spent; the engine multiplies by rateSkill / rateMagic (data/events/scripts/player.lua), then the
--     stage multiplier of the base server's own script (data/scripts/customs/skills/skills_stages.lua), which the Chaos
--     install does not touch
--   * exercise weapons: one charge per tickMs, E.step tries (exercise_core.lua) straight to addSkillTries / addManaSpent
--     (no rateSkill: the Lua wrapper switches it off), then the same stage multiplier
--   * offline training: the base script offlinetraining.lua at login, up to 12 hours a session, no cost
return {
	-- config.lua of the base server (docs/LAUNCH.md section 3 leaves them as the download has them)
	rates = {skill = 3, magic = 2},

	-- engine constants (src/vocation.cpp): skills 0 fist, 1 club, 2 sword, 3 axe, 4 distance, 5 shield, 6 fishing
	skillBase = {fist = 50, melee = 50, distance = 30, shield = 100},
	skillId = {fist = 0, melee = 2, distance = 4, shield = 5}, -- melee: sword, club and axe are one skill and one multiplier
	magicBase = 1600,
	minSkill = 10,

	-- the stage multipliers of the base server's skills_stages.lua AS DOWNLOADED: {first level, last level or nil, multiplier},
	-- picked by the trained (not the equipment) level; the last row has no end. Since O154 the install multiplies them from level
	-- 101 up (tools/patch_skill_stages.py, factor in skill_stages_config.lua); tools/skill_model.lua M.load() does the same and
	-- keeps these rows as cfg.stockStages, the result as cfg.stages
	stages = {
		skill = {{1, 60, 20}, {61, 80, 15}, {81, 100, 11}, {101, 110, 9}, {111, 125, 8}, {126, 149, 7}, {150, nil, 4}},
		magic = {{1, 60, 16}, {61, 80, 12}, {81, 100, 8}, {101, 110, 7}, {111, 125, 6}, {126, 149, 5}, {150, nil, 3}}
	},

	-- the main skill of each class line (exercise_config.lua `lines`): the skill the weapon hit, the spells and the passive tree
	-- scale with. The Thief line also has the bow, the Templar line also trains the magic level; the main one is priced.
	main = {warrior = "melee", ranger = "distance", mystic = "magic", thief = "melee", monk = "fist", necromancer = "magic",
		templar = "melee"},

	hunting = {
		-- the share of a hunting hour a swing or a shot lands at the vocation's attack speed. Packs die in about 3 s each
		-- (spawn_tuning.json: 800-1600 kills an hour), so the weapon is busy most of the hour; walking, looting and
		-- resupplying take the rest. Assumption, the biggest one: the ratio exercise / hunting is 1 / this
		attackShare = 0.7,
		-- the mana a magic class spends in the rotation of the sanity measurements (server/data/spells/README.md: Illusionist
		-- 8020, Sorcerer 9410 a minute at level 1000; a Necromancer is taken as the Illusionist)
		manaPerMinute = {mystic = 8000, necromancer = 8000},
		-- the share of a hunting hour the rotation runs at that rate (the rest: pulling, walking, drinking, the pool running dry)
		castShare = 0.5
	},

	-- hours of hunting from level 8 to 1000 (tools/progression_model.lua, docs/PRICES.md "Skill training (O150)"): the main skill
	-- a character has trained by hunting alone when it gets there
	levelingHours = 139,

	offline = {
		poolHours = 12, -- most one login can train (Player::addOfflineTrainingTime), refilled by every hour online or logged out
		-- the base script: melee and fist tries = seconds / attack speed seconds / 2, distance / 4; magic level = seconds x
		-- (mana gain amount of the vocation / (2 x mana gain ticks of the top vocation)); then rateSkill and the stages
		meleeDivisor = 2, distanceDivisor = 4
	},

	-- the skill levels the tables and the bound are read at: a trained main skill. 100 is where hunting needs hours for a level
	-- (below it a level comes in a few hours while leveling), 130 where it needs days
	reference = {skills = {100, 130}, table = {50, 80, 100, 115, 130, 140}},

	-- the exercise weapon bound of tools/store_model.lua --check: coins per hunting hour saved (price of a weapon / (dummy hours
	-- x hunting hours a dummy hour is worth)) at the reference skills, every class line that can use the weapon
	limits = {
		-- the cheapest: not under this fraction of Premium's coins per hour of benefit (Premium is the cheapest time saver)
		minFractionOfPremium = 0.5,
		-- the dearest: not over Double Experience's coins per hour (the dearest time saver)
		maxIsXpPotion = true,
		-- the 14400 tier per charge, at most this percent cheaper than the 500 tier (the only bulk discount over 20% was 37%)
		maxTierDiscountPct = 40
	}
}
