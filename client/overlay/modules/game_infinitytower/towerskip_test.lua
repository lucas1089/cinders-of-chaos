-- luajit towerskip_test.lua && lua5.3 towerskip_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'towerskip.lua')
local M = TowerSkip
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(M.view(nil).visible, false, 'no state: hidden')
-- Leave: inside a run only, one press a second
eq(M.canLeave(nil, 5000, nil), false, 'leave: no state')
eq(M.canLeave({ inRun = false }, 5000, nil), false, 'leave: not in a run')
eq(M.canLeave({ inRun = true, canSkip = false }, 5000, nil), true, 'leave: in a run, even during a fight')
eq(M.canLeave({ inRun = true }, 5000, 4500), false, 'leave: a second press too soon')
eq(M.canLeave({ inRun = true }, 5000, 4000), true, 'leave: after a second')
eq(M.view({ inRun = false, canSkip = true }).visible, false, 'not in a run: hidden even if the flag is set')
eq(M.view({ inRun = false, canSkip = true }).enabled, false, 'not in a run: disabled')
local v = M.view({ inRun = true, canSkip = true })
eq(v.visible and v.enabled, true, 'in a run, allowed: enabled')
eq(M.view({ inRun = true, canSkip = false }).visible, true, 'in a run, not allowed: shown')
eq(M.view({ inRun = true, canSkip = false }).enabled, false, 'in a run, not allowed: disabled')
eq(M.view({ inRun = true, canSkip = false }).tip, 'Available when the floor is cleared.', 'floor alive tip')
eq(M.view({ inRun = true, canSkip = false, nextBoss = true }).tip, 'A boss floor is next: it starts by itself.', 'boss tip')
eq(M.view({ inRun = true, canSkip = false, isLeader = false }).tip, 'Only the run leader can call the next floor.', 'member tip')
eq(M.canPress({ inRun = true, canSkip = true }, 5000, nil), true, 'first press')
eq(M.canPress({ inRun = true, canSkip = true }, 5500, 5000), false, 'too soon')
eq(M.canPress({ inRun = true, canSkip = true }, 6000, 5000), true, 'old enough')
eq(M.canPress({ inRun = true, canSkip = false }, 9000, nil), false, 'server flag off')

-- auto skip
local ok = { inRun = true, canSkip = true }
eq(M.shouldAutoSkip(ok, false, nil, 9000), false, 'auto off')
eq(M.shouldAutoSkip(ok, true, nil, 9000), true, 'auto on, allowed')
eq(M.shouldAutoSkip(ok, true, 8000, 9000), false, 'auto debounce: under 2 s')
eq(M.shouldAutoSkip(ok, true, 7000, 9000), true, 'auto: 2 s passed')
eq(M.shouldAutoSkip({ inRun = false, canSkip = true }, true, nil, 9000), false, 'auto: not in a run')
eq(M.shouldAutoSkip({ inRun = true, canSkip = false }, true, nil, 9000), false, 'auto: canSkip false')
eq(M.shouldAutoSkip({ inRun = true, canSkip = false, nextBoss = true }, true, nil, 9000), false, 'auto: boss pause')
eq(M.shouldAutoSkip(nil, true, nil, 9000), false, 'auto: no state')

-- the panel
eq(M.panel(nil, 0), nil, 'panel: no state')
eq(M.panel({ inRun = false }, 0), nil, 'panel: not in a run')
local p = M.panel({ inRun = true, floor = 0, waiting = true, nextIn = 5, cleared = 0 }, 0)
eq(p.floor.key, 'Get ready', 'panel: before floor 1')
eq(p.timer.secs, 5, 'panel: start countdown')
p = M.panel({ inRun = true, floor = 7, cleared = 6, remaining = 3, total = 8, floorLeft = 300 }, 2500)
eq(p.floor.n, 7, 'panel: floor'); eq(p.floor.key, 'Floor %d', 'panel: normal key')
eq(p.cleared.n, 6, 'panel: cleared')
eq(p.monsters.left, 3, 'panel: left'); eq(p.monsters.total, 8, 'panel: total')
eq(p.timer.secs, 298, 'panel: floor time runs down on the client clock')
eq(p.timer.key, 'Floor time left: %s', 'panel: floor timer key')
p = M.panel({ inRun = true, floor = 10, boss = true, remaining = 1, total = 5 }, 0)
eq(p.floor.key, 'Floor %d (boss)', 'panel: boss key'); eq(p.timer, nil, 'panel: no floor timer without the field')
p = M.panel({ inRun = true, floor = 3, waiting = true, nextIn = 6, remaining = 0, total = 4 }, 4100)
eq(p.monsters, nil, 'panel: no monsters while waiting'); eq(p.timer.secs, 2, 'panel: countdown rounds up')
eq(M.panel({ inRun = true, floor = 3, waiting = true, nextIn = 6 }, 99000).timer.secs, 0, 'panel: never negative')
eq(M.clock(125), '2:05', 'clock'); eq(M.clock(-4), '0:00', 'clock floor')
eq(M.clock(3599), '59:59', 'clock: just under an hour'); eq(M.clock(3600), '1:00:00', 'clock: an hour'); eq(M.clock(3725), '1:02:05', 'clock: over an hour')

-- O484: the run's own clock, a second line under the floor's
p = M.panel({ inRun = true, floor = 7, cleared = 6, remaining = 3, total = 8, floorLeft = 200, runLeft = 3600 }, 0)
eq(p.runTimer.key, 'Run time left: %s', 'run line: key'); eq(p.runTimer.secs, 3600, 'run line: seconds')
eq(p.runTimer.low, false, 'run line: normal colour at the start'); eq(p.timer.secs, 200, 'run line: the floor line stays')
p = M.panel({ inRun = true, floor = 7, remaining = 3, total = 8, floorLeft = 200, runLeft = 3600 }, 2500)
eq(p.runTimer.secs, 3598, 'run line: counts down on the client clock between two states')
p = M.panel({ inRun = true, floor = 7, remaining = 3, total = 8, floorLeft = 200, runLeft = 301 }, 0)
eq(p.runTimer.low, false, 'run line: 301 s is not low')
p = M.panel({ inRun = true, floor = 7, remaining = 3, total = 8, floorLeft = 200, runLeft = 301 }, 1000)
eq(p.runTimer.secs, 300, 'run line: 300 s'); eq(p.runTimer.low, true, 'run line: warning colour at 300 s')
p = M.panel({ inRun = true, floor = 7, remaining = 3, total = 8, floorLeft = 200, runLeft = 301 }, 1001)
eq(p.runTimer.secs, 300, 'run line: still 300 s one ms later (rounds up)')
p = M.panel({ inRun = true, floor = 7, remaining = 3, total = 8, floorLeft = 200, runLeft = 10 }, 99000)
eq(p.runTimer.secs, 0, 'run line: never negative'); eq(p.runTimer.low, true, 'run line: low at zero')
eq(M.RUN_LOW_SECS, 300, 'run line: threshold'); eq(M.RUN_LOW_COLOR, '#ff4030', 'run line: warning colour')
eq(M.RUN_COLOR, '#f0e4c8', 'run line: normal colour')
-- also in the pause between floors and before floor 1, where the floor line is absent
p = M.panel({ inRun = true, floor = 3, waiting = true, nextIn = 6, remaining = 0, total = 4, runLeft = 1234 }, 2000)
eq(p.runTimer.secs, 1232, 'run line: shown in the pause'); eq(p.timer.key, 'Next floor in %ds', 'run line: the pause keeps its own line')
p = M.panel({ inRun = true, floor = 0, waiting = true, nextIn = 5, runLeft = 3600 }, 0)
eq(p.runTimer.secs, 3600, 'run line: shown before floor 1')
-- no run limit: no line
p = M.panel({ inRun = true, floor = 7, remaining = 3, total = 8, floorLeft = 200 }, 0)
eq(p.runTimer, nil, 'run line: absent without a limit')
p = M.panel({ inRun = true, floor = 3, waiting = true, nextIn = 6 }, 0)
eq(p.runTimer, nil, 'run line: absent in the pause without a limit')

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks failed'); os.exit(1) end
print('towerskip: ' .. checks .. ' checks passed')
