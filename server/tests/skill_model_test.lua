-- Run from the server/ folder: luajit tests/skill_model_test.lua (and lua5.3; CI runs both)
-- tools/skill_model.lua (O150): the engine formulas, the hunting / exercise / offline tries, the value of a dummy hour and the
-- exercise weapon price bound.
local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function near(a, b, tol, label)
	check(math.abs(a - b) <= tol * math.max(1, math.abs(b)), label .. " (" .. tostring(a) .. " vs " .. tostring(b) .. ")")
end

ChaosSkillModelLib = true
local M = dofile("tools/skill_model.lua")
local env = M.load()
local war, mys, nin = env.vocs[4], env.vocs[1], env.vocs[12]

check(#M.problems(env) == 0, "the real model has no problems")
check(#env.order == 21, "21 vocations")
check(war.skill.melee == 1.1 and war.attackMs == 2000 and nin.attackMs == 1300 and mys.manaMult == 1.1, "vocation attributes read from the XML")

-- engine formulas: skillBase x mult^(level - 10); 1600 x mult^level
near(M.need(env, war, "melee", 10), 50, 1e-9, "10 -> 11 is 50 tries")
near(M.need(env, war, "melee", 100), 50 * 1.1 ^ 90, 1e-9, "Warrior 100 -> 101")
near(M.need(env, war, "distance", 100), 30 * 1.4 ^ 90, 1e-9, "Warrior distance uses its own multiplier")
near(M.need(env, mys, "magic", 0), 1600, 1e-9, "magic level 0 -> 1 is 1600 mana")
near(M.need(env, mys, "magic", 100), 1600 * 1.1 ^ 100, 1e-9, "magic level 100 -> 101")

-- stage multipliers
check(M.stageMult(env.cfg.stages.skill, 1) == 20 and M.stageMult(env.cfg.stages.skill, 100) == 11 and M.stageMult(env.cfg.stages.skill, 101) == 9, "skill stages")
check(M.stageMult(env.cfg.stages.skill, 149) == 7 and M.stageMult(env.cfg.stages.skill, 150) == 4 and M.stageMult(env.cfg.stages.skill, 400) == 4, "skill stages, last row open")
check(M.stageMult(env.cfg.stages.magic, 100) == 8 and M.stageMult(env.cfg.stages.magic, 130) == 5, "magic stages")

-- hunting: swings an hour x attackShare x rateSkill x stage
near(M.hunting(env, war, "melee", 100), 1800 * 0.7 * 3 * 11, 1e-9, "Warrior hunting tries at 100")
near(M.hunting(env, nin, "melee", 100), 3600000 / 1300 * 0.7 * 3 * 11, 1e-9, "a faster attack speed trains faster")
near(M.hunting(env, mys, "magic", 100), 8000 * 60 * 0.5 * 2 * 8, 1e-9, "Mystic mana spent at 100")
check(M.hunting(env, war, "magic", 100) == nil, "no magic hunting figure for a class without a rotation figure")

-- exercise: 4800 charges an hour, E.step tries, then the stage
near(M.exercise(env, "melee", "melee", 100), 4800 * 21 * 11, 1e-9, "melee dummy tries at 100 (7 x rate 3, stage 11)")
near(M.exercise(env, "melee", "melee", 130), 4800 * 14 * 7, 1e-9, "melee dummy tries at 130 (7 x rate 2, stage 7)")
near(M.exercise(env, "rod", "magic", 100), 4800 * 1500 * 8, 1e-9, "rod dummy mana at 100 (500 x rate 3, stage 8)")
check(M.exercise(env, "melee", "melee", 100, 0, true) > M.exercise(env, "melee", "melee", 100), "a house dummy gives more")
near(M.ratio(env, war, "melee", 100), 4800 * 21 * 11 / (1800 * 0.7 * 3 * 11), 1e-9, "a dummy hour in hunting hours")
check(M.ratio(env, mys, "magic", 130) > 5 and M.ratio(env, war, "melee", 130) > 10, "a dummy hour is worth many hunting hours")

-- offline: no uptime share; casters get almost nothing
near(M.offline(env, war, "melee", 100), 3600 / 2 / 2 * 3 * 11, 1e-9, "offline melee tries")
near(M.offline(env, env.vocs[3], "distance", 100), 3600 / 2 / 4 * 3 * 11, 1e-9, "offline distance is a quarter")
check(M.offline(env, mys, "magic", 100) < M.hunting(env, mys, "magic", 100) / 20, "offline magic training is a small fraction of hunting")

-- hours
local h = M.hours(env, war, "melee", 100, 101, function(L) return M.hunting(env, war, "melee", L) end)
near(h, M.need(env, war, "melee", 100) / M.hunting(env, war, "melee", 100), 1e-9, "hours of one level")
check(M.hours(env, war, "melee", 10, 11, function() return 0 end) == math.huge, "no tries, no end")

-- the exercise weapon price bound
local offers = {
	{kind = "item", name = "Exercise Melee Weapon (500)", cost = 25},
	{kind = "item", name = "Lasting Exercise Melee Weapon (14400)", cost = 450},
	{kind = "item", name = "Exercise Rod (500)", cost = 25},
	{kind = "item", name = "Exercise Shield (500)", cost = 25}
}
local function problems() return M.exerciseProblems(env, offers, 8.33, 50) end
check(#problems() == 0, "the real prices pass")
offers[2].cost = 60
check(#problems() > 0, "a lasting weapon at 60 coins is far too cheap")
offers[2].cost = 450
offers[1].cost = 1500
check(#problems() > 0, "a 500 charge weapon at 1500 coins is far too dear")
offers[1].cost = 40
local p = problems()
local found = false
for _, t in ipairs(p) do if t:find("cheaper per charge", 1, true) then found = true end end
check(found, "a tier discount over 40% is caught")

if failures > 0 then
	print(string.format("skill_model_test: %d of %d checks FAILED", failures, checks))
	os.exit(1)
end
print(string.format("skill_model_test: %d checks OK", checks))
