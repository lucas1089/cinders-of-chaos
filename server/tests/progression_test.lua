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

-- O375: 5 hall hunts in reach of every level, 2 in the narrow window at 8-100 and 5 at 1300-2200; without the nine
-- new plans the check names both ends
eq(env.cfg.hall.minHunts, 5, "five hall hunts in reach (0.7-1.3 L) of every level")
local O375 = {thistlewood_hollow = true, copperdelve_mine = true, ashgrave_barrow = true, murkreed_fen = true,
	chitinmaw_warren = true, scalewatch_bastion = true, anvilmourn_wastes = true, oathgrave_ossuary = true, pyrecrown_caldera = true}
local before, found = {}, 0
for _, b in ipairs(savedBands) do
	if O375[b[3]] then found = found + 1 else before[#before + 1] = b end
end
eq(found, 9, "the nine O375 plans are hall hunts")
for L = 8, 100 do ok(M.hallCount(env.bands, L, env.cfg.hall) >= 5, "level " .. L .. ": 5 hall hunts in reach") end
for L = 1300, 2200 do ok(M.hallCount(env.bands, L, env.cfg.hall.tight) >= 5, "level " .. L .. ": 5 hall hunts within 0.8-1.1 L") end
env.bands = before
local thinner = M.problems(env)
env.bands = savedBands
local low, late = false, false
for _, p in ipairs(thinner) do
	if p:find("hall: levels 8-", 1, true) and p:find("fewer than 5", 1, true) then low = true end
	if p:find("fewer than 5 hall hunts within 0.8x-1.1x", 1, true) and p:find("levels 2", 1, true) then late = true end
end
ok(low, "without the O375 hunts levels from 8 have fewer than 5 hall hunts in reach: " .. table.concat(thinner, "; "))
ok(late, "without the O375 hunts levels 2000-2200 have fewer than 5 within 0.8-1.1 L")

-- O375: the planned monsters the generated pool does not list yet join the model's pool
local pool = {hunt = {{name = "Known", level = 10, exp = 1, health = 1}}, bosses = {{name = "Big Boss", level = 50}}}
local plans = {a = '{"spawns": [{"zone": "z", "monster": "New One", "count": 4}, {"path": ["x", "y"], "monster": "Known", "count": 9}]}',
	b = '{"spawns": [{"zone": "q", "monster": "New One", "count": 2}, {"zone": "q", "monster": "Too Few", "count": 5},\n' ..
		'{"zone": "q", "monster": "Big Boss", "count": 8}, {"zone": "q", "monster": "Boss Flag", "count": 8}]}'}
local xml = {
	'<monster name="New One" experience="500" speed="1">\n\t<health now="900" max="900"/>\n\t<level min="1540" max="1561"/>',
	'<monster name="Too Few" experience="5"><health now="9" max="9"/><level min="10" max="20"/>',
	'<monster name="Boss Flag" experience="5"><health now="9" max="9"/><level min="10" max="20"/><flag isboss="1"/>',
	'<!-- <monster name="Commented" --><monster name="Known" experience="1"><health now="1" max="1"/><level min="1" max="2"/>'}
local add = M.plannedMonsters(pool, plans, xml)
eq(#add, 1, "one planned monster joins: 6 spawns over two plans, not in the pool, not a boss")
eq(add[1].name, "New One"); eq(add[1].level, 1550, "the middle of its level range"); eq(add[1].spawns, 6)
eq(add[1].exp, 500); eq(add[1].health, 900)
ok(#env.planned >= 1, "the repository's plans hold monsters the pool misses: " .. #env.planned)
for _, e in ipairs(env.planned) do ok(e.spawns >= 6 and e.level > 0, e.name .. ": spawns and level") end
local poolOnly = M.load({poolOnly = true})
eq(#env.hunts, #poolOnly.hunts + #env.planned, "the model's hunts are the pool's and the planned ones")

-- the journey: a level never takes much longer or shorter than the ones around it, and the hours add up
local curve = select(2, M.problems(env))
local h = M.hours(curve, 8, 1000)
ok(h > 100 and h < 180, "levels 8 to 1000 take " .. h .. " hours (the leveling model: about 130 for the median class)")
ok(M.hours(curve, 8, 20) < 0.5, "the first 12 levels are minutes, not half an hour")
for L = 8, 2200 do ok(curve[L].min > 0 and curve[L].min < 120, "level " .. L .. " takes " .. curve[L].min .. " minutes") end

-- O370: the newcomer bonus (catchup_config.lua newcomer) is in the model: level 8 is faster with it, level 600 the same
ok(env.newcomer ~= nil, "the model counts the newcomer bonus")
local plain = M.load({noNewcomer = true})
local _, plainCurve = M.problems(plain)
ok(curve[8].min < plainCurve[8].min * 0.75, "level 8: the newcomer bonus speeds it up")
ok(math.abs(curve[600].min - plainCurve[600].min) < 1e-9, "level 600: no newcomer bonus")

-- the spell unlock table reads the files
local lv = M.unlockLevels()
ok(lv.Warrior and lv.Mystic and lv.Monk, "unlock levels of the base classes")
local gap = M.longestSpellGap({1, 8, 25, 40, 200}, 300)
eq(gap[1], 160); eq(gap[2], 40); eq(gap[3], 200)

print("progression: " .. n .. " checks passed")
