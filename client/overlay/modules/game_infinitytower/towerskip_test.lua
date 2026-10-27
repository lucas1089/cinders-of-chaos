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

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks failed'); os.exit(1) end
print('towerskip: ' .. checks .. ' checks passed')
