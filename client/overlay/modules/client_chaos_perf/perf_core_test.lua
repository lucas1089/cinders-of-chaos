-- luajit perf_core_test.lua && lua5.3 perf_core_test.lua (CI runs every client/overlay/modules/*/*_test.lua from the
-- repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'perf_core.lua')
local C = ChaosPerfCore
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function near(a, b, what) eq(math.abs(a - b) < 1e-6, true, what .. ' (' .. tostring(a) .. ' vs ' .. tostring(b) .. ')') end

-- stats
local s = C.stats({ 60, 58, 30, 61, 59, 'x', 62, 60, 60, 57, 20 })
eq(s.n, 10, 'non-numbers are dropped')
eq(s.min, 20, 'min')
eq(s.max, 62, 'max')
near(s.avg, 52.7, 'avg')
eq(s.median, 59, 'median: nearest rank')
eq(s.p5, 20, 'p5 of 10 values is the lowest')
eq(s.p95, 62, 'p95 of 10 values is the highest')
eq(C.stats({}).avg, 0, 'empty list')
eq(C.stats(nil).n, 0, 'nil list')
local hundred = {}
for i = 1, 100 do hundred[i] = 101 - i end
local h = C.stats(hundred)
eq(h.p5, 5, 'p5 of 1..100')
eq(h.p95, 95, 'p95 of 1..100')
eq(h.median, 50, 'median of 1..100')
eq(C.percentile({}, 50), 0, 'percentile of nothing')
eq(C.stats({ 0 / 0, 1 }).n, 1, 'NaN dropped')

local list = {}
for i = 1, 15 do C.pushLast(list, i, 10) end
eq(#list, 10, 'pushLast keeps 10')
eq(list[1], 6, 'oldest dropped first')

-- probe
local p = C.newProbe()
C.probeTick(p, 1000)
eq(C.probeTake(p), 0, 'one tick: no gap')
C.probeTick(p, 1010); C.probeTick(p, 1021); C.probeTick(p, 1250); C.probeTick(p, 1262)
eq(C.probeTake(p), 229, 'worst gap')
eq(C.probeTake(p), 0, 'take starts over')
C.probeTick(p, 1272)
eq(C.probeTake(p), 10, 'gap after the take still counts from the last tick')
C.probeReset(p)
C.probeTick(p, 9000)
eq(C.probeTake(p), 0, 'a reset does not count the pause')

local o = C.overlay({ { fps = 50, gap = 20, gfx = 55, cpu = 200 }, { fps = 40, gap = 120, gfx = 45, cpu = 100 } })
eq(o.fps, 40, 'overlay: the last FPS')
near(o.fpsAvg, 45, 'overlay: avg FPS')
eq(o.fpsMin, 40, 'overlay: min FPS')
near(o.frameAvgMs, 1000 / 45, 'overlay: frame time from FPS')
eq(o.frameWorstMs, 120, 'overlay: worst gap')
eq(o.gfx, 50, 'overlay: graphics FPS')
eq(o.cpu, 150, 'overlay: processing FPS')
local o2 = C.overlay({ { fps = 30, gap = 5 } })
eq(o2.gfx, nil, 'overlay: no graphics FPS when the engine has none')
eq(C.overlay({}).frameAvgMs, 0, 'overlay: nothing yet')

-- attribution
eq(C.moduleOfSource('@/modules/game_dpsmeter/dpsmeter.lua'), 'game_dpsmeter', 'module from a source')
eq(C.moduleOfSource('@modules/game_hunt/hunt.lua'), 'game_hunt', 'module without a leading slash')
eq(C.moduleOfSource('@C:\\client\\modules\\game_bank\\bank.lua'), 'game_bank', 'Windows separators')
eq(C.moduleOfSource('@/mods/my_mod/x.lua'), 'my_mod', 'a mod')
eq(C.moduleOfSource('=[C]'), nil, 'C function')
eq(C.moduleOfSource(nil), nil, 'no source')
local stack = {
  [3] = { source = '@/modules/corelib/util.lua' },
  [4] = { source = '@/modules/gamelib/protocolgame.lua' },
  [5] = { source = '@/modules/game_rift/rift.lua' },
}
local function getinfo(l) return stack[l] end
eq(C.callerModule(getinfo, 3), 'game_rift', 'helpers are skipped')
eq(C.callerModule(function() return nil end, 3), '?', 'no frame')
eq(C.callerModule(function() error('boom') end, 3), '?', 'getinfo error')
eq(C.callerModule(function() return { source = '@/modules/corelib/x.lua' } end, 3), '?', 'only helpers')

-- timer
local now = 0
local timer = C.newTimer(function() return now end, function(e) return 'tb: ' .. tostring(e) end)
local calls = 0
local fn = C.wrap(timer, function(a, b) calls = calls + 1; now = now + 500; return a + b, 'x' end, 'game_a', 'cycleEvent')
local r1, r2 = fn(1, 2)
eq(r1, 3, 'off: result passes')
eq(r2, 'x', 'off: second result passes')
eq(timer.profile.calls, 0, 'off: nothing timed')
C.startTimer(timer)
r1, r2 = fn(2, 3)
eq(r1, 5, 'on: result passes')
eq(r2, 'x', 'on: second result passes')
eq(timer.profile.mods.game_a.us, 500, 'on: time added')
eq(timer.profile.mods.game_a.calls, 1, 'on: one call')
-- nil holes in the arguments and the results
local holes = C.wrap(timer, function(a, b, c) return a, b, c end, 'game_h', 'addEvent')
local h1, h2, h3 = holes(nil, 2, nil)
eq(h1, nil, 'nil argument 1'); eq(h2, 2, 'argument 2'); eq(h3, nil, 'nil argument 3')
-- nested: the inner callback is not timed twice
local inner = C.wrap(timer, function() now = now + 100 end, 'game_inner', 'scheduleEvent')
local outer = C.wrap(timer, function() now = now + 200; inner() end, 'game_outer', 'scheduleEvent')
outer()
eq(timer.profile.mods.game_outer.us, 300, 'nested: outer has the inner time')
eq(timer.profile.mods.game_inner, nil, 'nested: inner not counted again')
-- errors go on, the depth is reset
local bad = C.wrap(timer, function() error('broken', 0) end, 'game_bad', 'cycleEvent')
local ok, err = pcall(bad)
eq(ok, false, 'error passes')
eq(err, 'tb: broken', 'error keeps the traceback text')
eq(timer.depth, 0, 'depth back to 0 after an error')
eq(timer.profile.mods.game_bad, nil, 'a failed call is not timed')
fn(1, 1)
eq(timer.profile.mods.game_a.calls, 2, 'timing goes on after an error')
eq(C.wrap(timer, 5, 'x', 'y'), 5, 'not a function: unchanged')
C.addCost(timer.profile, 'game_a', 'opcode', 2000)
C.addCost(timer.profile, 'game_z', 'opcode', -5)
local top = C.topModules(timer.profile, 2)
eq(#top, 2, 'top is capped')
eq(top[1].name, 'game_a', 'costliest first')
eq(top[1].kind, 'opcode', 'mostly: the kind with the most time')
eq(top[1].worstUs, 2000, 'worst single call')
eq(top[2].name, 'game_outer', 'second')
eq(timer.profile.mods.game_z.us, 0, 'negative time counts as 0')
C.stopTimer(timer)
local before = timer.profile.calls
fn(1, 1)
eq(timer.profile.calls, before, 'stopped: nothing timed')
C.startTimer(timer)
eq(timer.profile.calls, 0, 'start: a new profile')

-- recording
local rec = C.newRecording(10000, 3)
eq(C.addSample(rec, { t = 11000, fps = 60, gfx = 61, cpu = 300, gap = 18, luaKb = 20000, creatures = 4,
  windows = { 'b', 'a', 'a' } }), false, 'sample 1')
eq(C.addSample(rec, { t = 12000, fps = 30, gap = 140, luaKb = 20500, creatures = 10, windows = { 'a' } }), false, 'sample 2')
eq(C.addSample(rec, { t = 13000, fps = 45, gap = 30, luaKb = 21000, windows = {} }), true, 'sample 3 ends the record')
eq(rec.windows.a, 2, 'a window seen twice counts its seconds once per sample')
eq(rec.windows.b, 1, 'b once')
eq(rec.samples[1].windows[1], 'a', 'window ids sorted')
local prof = C.newProfile()
C.addCost(prof, 'game_hunt', 'cycleEvent', 30000)
C.addCost(prof, 'game_rift', 'opcode', 6000)
local sum = C.summarize(rec, prof, false)
eq(sum.seconds, 3, 'summary seconds')
eq(sum.fps.min, 30, 'summary FPS min')
near(sum.fps.avg, 45, 'summary FPS avg')
eq(sum.gap.max, 140, 'summary worst gap')
eq(sum.gfx.n, 1, 'graphics FPS only where known')
eq(sum.creatures.max, 10, 'creatures max')
near(sum.luaGrowthKbPerMin, 30000, 'Lua growth per minute: 1000 KB in 2 s')
eq(sum.windows[1].id, 'a', 'most visible window first')
eq(sum.top[1].name, 'game_hunt', 'summary top module')
near(sum.top[1].msPerS, 10, 'ms per second')
near(sum.top[1].share, 1, 'share of the wall time in percent')
near(sum.luaTotalMs, 36, 'Lua total ms')
eq(sum.verdict, 'ok', 'avg 45: ok on a PC')
eq(C.summarize(rec, prof, true).verdict, 'good', 'avg 45, p5 30: good on a phone')

eq(C.verdict(60, 50, false), 'good', 'PC 60 avg, p5 50')
eq(C.verdict(58, 31, false), 'good', 'PC 58 is within 5 %')
eq(C.verdict(60, 12, false), 'low', 'PC with deep drops')
eq(C.verdict(25, 20, false), 'low', 'PC 25 avg')
eq(C.verdict(31, 22, true), 'good', 'phone 31')
eq(C.verdict(22, 12, true), 'ok', 'phone 22')
eq(C.verdict(15, 10, true), 'low', 'phone 15')

local csv = C.csv(rec)
local lines = {}
for line in csv:gmatch('[^\n]+') do lines[#lines + 1] = line end
eq(#lines, 4, 'csv: header and 3 rows')
eq(lines[1], 'second,fps,graphics_fps,processing_fps,frame_ms,worst_gap_ms,lua_kb,creatures,windows', 'csv header')
eq(lines[2], '1,60,61,300,16.7,18,20000,4,a b', 'csv row 1')
eq(lines[4], '3,45,,,22.2,30,21000,,', 'csv row without engine values')
local zero = C.newRecording(0, 1)
C.addSample(zero, { t = 1, fps = 0, gap = 0, luaKb = 1, windows = { 'x,"y"' } })
eq(C.csv(zero):match('\n(.*)\n$'), '1,0,,,,0,1,,"x,""y"""', 'csv: quoted cell, no frame time at 0 FPS')

local text = C.report(sum, { stamp = '20261103-120000', version = '1.0', os = 'windows', screen = '1920x1080',
  clock = 'g_clock.realMicros', profiled = 'record', modules = 120, chaosModules = 90, stats = { 'main 1 ms' } })
eq(text:find('verdict: ok', 1, true) ~= nil, true, 'report: verdict')
eq(text:find('FPS: avg 45.0  min 30  p5 30', 1, true) ~= nil, true, 'report: FPS line')
eq(text:find(' 1. game_hunt', 1, true) ~= nil, true, 'report: top module')
eq(text:find('only callbacks registered during the record', 1, true) ~= nil, true, 'report: record-only note')
eq(text:find('modules loaded: 120 (90 Chaos)', 1, true) ~= nil, true, 'report: modules')
eq(text:find('main 1 ms', 1, true) ~= nil, true, 'report: engine timings')
eq(text:find('\226\128\148', 1, true), nil, 'report: no em-dash')
local off = C.report(sum, { profiled = 'off' })
eq(off:find('not measured (timing not available)', 1, true) ~= nil, true, 'report: timing off')
local none = C.report(C.summarize(C.newRecording(0, 1), C.newProfile(), false), { profiled = 'start' })
eq(none:find('no timed callback ran', 1, true) ~= nil, true, 'report: nothing timed')
eq(none:find('  none', 1, true) ~= nil, true, 'report: no windows')

-- float values (collectgarbage('count'), fractional FPS) print in a Lua 5.3 %d
local fl = C.newRecording(0, 2)
C.addSample(fl, { t = 1000, fps = 59.5, gfx = 60.25, cpu = 100.5, gap = 17.5, luaKb = 20000.75, creatures = 2.5, windows = {} })
C.addSample(fl, { t = 2000, fps = 58.5, gap = 16.25, luaKb = 20100.25, windows = {} })
local okf, ftext = pcall(C.report, C.summarize(fl, C.newProfile(), false), { profiled = 'start' })
eq(okf, true, 'report with float values: ' .. tostring(ftext):sub(1, 80))

eq(C.stamp({ year = 2026, month = 11, day = 3, hour = 9, min = 5, sec = 7 }), '20261103-090507', 'stamp')
eq(C.stamp(nil), '00000000-000000', 'stamp without a date')
local a, b = C.fileNames('X')
eq(a, '/chaos-perf-X.csv', 'csv name: chaos- is kept by the clean-up')
eq(b, '/chaos-perf-X.txt', 'txt name')

if fails > 0 then
  print(('perf_core_test: %d of %d checks failed'):format(fails, checks))
  os.exit(1)
end
print(('perf_core_test: %d checks passed'):format(checks))
