-- Run from the server/ folder: luajit tests/progression_test.lua (no engine needed; CI runs luajit and lua5.3)
-- O135: the leveling journey stays smooth. Unit tests of tools/progression_model.lua and the check itself:
-- the experience stage table of tools/late_game.py, the minutes per level from 8 to 2200, the hunts of the pool and
-- of the teleport hall in reach of every level. Also pins the old table's cliff, so the check is known to bite.
ChaosProgressionLib = true
local M = dofile("tools/progression_model.lua")
local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function ok(c, m)
	n = n + 1
	if not c then error(m or "failed", 2) end
end

-- the engine's experience formula (Player::getExpForLevel differences)
eq(M.expToNext(1), 100, "1 -> 2"); eq(M.expToNext(8), 2200, "8 -> 9"); eq(M.expToNext(100), 485200, "100 -> 101")

-- stage parsing and lookup
local text = [[
SMOOTH_STAGES = [(1, 10, 30), (11, 20, 40)]
LATE_STAGES = [(21, 30, 38), (31, OPEN_END, 36)]
]]
local st = M.stagesFromText(text)
eq(#st, 4, "four rows"); eq(st[4][2], 999999, "OPEN_END"); eq(M.stage(st, 5), 30); eq(M.stage(st, 20), 40)
eq(M.stage(st, 31), 36); eq(M.stage(st, 5000), 36, "beyond the table: the last row")

-- runs and the hall window
local r = M.runs(1, 10, function(L) return L == 2 or L == 3 or L == 10 end)
eq(#r, 2); eq(r[1][1], 2); eq(r[1][2], 3); eq(r[2][1], 10); eq(r[2][2], 10)
local bands = {{0, 0, "a", 100}, {0, 0, "b", 130}, {0, 0, "c", 70}, {0, 0, "d", 131}}
eq(M.hallCount(bands, 100, {lo = 0.7, hi = 1.3}), 3, "70, 100 and 130 are in reach of 100, 131 is not")

-- the repository's data: smooth
local env = M.load()
local problems = M.problems(env)
eq(#problems, 0, table.concat(problems, "; "))
-- the stage table as the files have it
eq(env.stages[1][1], 1); eq(env.stages[#env.stages][2], 999999, "the last stage has an explicit maxlevel")
ok(#env.stages > 40, "the smooth table has a row per multiplier step")

-- the table before O135 must fail: x10 up to level 20, x50 from 21 (a 5x cliff), 3 a step every 50 levels from 301
local old = {{1, 20, 10}, {21, 50, 50}, {51, 100, 45}, {101, 150, 43}, {151, 200, 41}, {201, 300, 39}, {301, 350, 36},
	{351, 400, 33}, {401, 450, 30}, {451, 500, 27}, {501, 550, 24}, {551, 600, 21}, {601, 650, 18}, {651, 700, 15},
	{701, 750, 15}, {751, 800, 15}, {801, 850, 14}, {851, 900, 14}, {901, 950, 13}, {951, 999999, 13}}
local saved = env.stages
env.stages = old
local oldProblems = M.problems(env)
env.stages = saved
ok(#oldProblems >= 5, "the old table is not smooth: " .. #oldProblems)
local cliffStage, cliffTime = false, false
for _, p in ipairs(oldProblems) do
	if p:find("x50 from level 21", 1, true) then cliffStage = true end
	if p:find("time per level: levels 18", 1, true) or p:find("time per level: levels 28", 1, true) then cliffTime = true end
end
ok(cliffStage, "the check names the x50 step at level 21")
ok(cliffTime, "the check names the time per level cliff")

-- O139: the narrow hall window (0.8-1.1 L) bites in the listed ranges: without the hunts for 200 and 450 it fails
local savedBands = env.bands
local without = {}
for _, b in ipairs(savedBands) do
	if not (b[4] > 150 and b[4] < 240 and b[3]:find("^[a-z_]+$")) and not (b[4] >= 395 and b[4] <= 480 and b[3]:find("^[a-z_]+$")) then
		without[#without + 1] = b
	end
end
env.bands = without
local thin = M.problems(env)
env.bands = savedBands
local thinHall = false
for _, p in ipairs(thin) do
	if p:find("0.8x-1.1x", 1, true) then thinHall = true end
end
ok(thinHall, "no hunts for the levels 200 and 450: the narrow window names the gap")
ok(env.cfg.hall.tight and #env.cfg.hall.tight.ranges == 6, "six ranges with the narrow window")

-- the journey: a level never takes much longer or shorter than the ones around it, and the hours add up
local curve = select(2, M.problems(env))
local h = M.hours(curve, 8, 1000)
ok(h > 100 and h < 180, "levels 8 to 1000 take " .. h .. " hours (the leveling model: about 130 for the median class)")
ok(M.hours(curve, 8, 20) < 0.5, "the first 12 levels are minutes, not half an hour")
for L = 8, 2200 do ok(curve[L].min > 0 and curve[L].min < 120, "level " .. L .. " takes " .. curve[L].min .. " minutes") end

-- the spell unlock table reads the files
local lv = M.unlockLevels()
ok(lv.Warrior and lv.Mystic and lv.Monk, "unlock levels of the base classes")
local gap = M.longestSpellGap({1, 8, 25, 40, 200}, 300)
eq(gap[1], 160); eq(gap[2], 40); eq(gap[3], 200)

print("progression: " .. n .. " checks passed")
