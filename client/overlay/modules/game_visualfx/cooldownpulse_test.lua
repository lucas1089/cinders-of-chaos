-- luajit cooldownpulse_test.lua && lua5.3 cooldownpulse_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'cooldownpulse_logic.lua')
local L = CooldownPulseLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function near(a, b, what) eq(math.abs(a - b) < 1e-9, true, what .. ' (' .. tostring(a) .. ' ~ ' .. tostring(b) .. ')') end

-- the pulse is about 250-300 ms
eq(L.DURATION >= 250 and L.DURATION <= 300, true, 'duration 250-300 ms')

-- shouldPulse: ran its course, long enough
eq(L.shouldPulse(8000, 8000), true, 'at the end')
eq(L.shouldPulse(8000, 8100), true, 'a little late')
eq(L.shouldPulse(8000, 7900), true, 'a little early is inside the tolerance')
eq(L.shouldPulse(8000, 7850), true, 'exactly at the tolerance')
eq(L.shouldPulse(8000, 7849), false, 'cleared 151 ms early')
eq(L.shouldPulse(8000, 2000), false, 'cleared early (dragged away)')
eq(L.shouldPulse(2999, 2999), false, 'a short cooldown never pulses')
eq(L.shouldPulse(3000, 3000), true, 'the shortest cooldown that pulses')
eq(L.shouldPulse(nil, 5), false, 'no duration')
eq(L.shouldPulse(8000, nil), false, 'no elapsed')
eq(L.shouldPulse('8000', 8000), false, 'junk duration')
eq(L.shouldPulse(0, 0), false, 'no cooldown')

-- opacity: 0 before and after, peak at RISE, monotone fall
eq(L.opacity(-1), 0, 'before')
eq(L.opacity(0), 0, 'start')
near(L.opacity(L.RISE), L.PEAK, 'peak')
near(L.opacity(L.RISE / 2), L.PEAK / 2, 'half way up')
eq(L.opacity(L.DURATION), 0, 'end')
eq(L.opacity(L.DURATION + 100), 0, 'after')
eq(L.opacity(nil), 0, 'junk')
local prev = L.PEAK
for t = L.RISE + 1, L.DURATION - 1 do
  local a = L.opacity(t)
  if a > prev or a < 0 or a > L.PEAK then eq(true, false, 'falls monotone at ' .. t) break end
  prev = a
end
eq(L.opacity(L.DURATION - 1) < 0.001, true, 'ends near 0 (no pop)')

-- tracker
local tr = L.newTracker()
eq(L.active(tr), false, 'idle at start')
eq(L.start(tr, 'a', 1000), true, 'start a')
eq(L.start(tr, 'b', 1100), true, 'start b')
eq(tr.count, 2, 'two alive')
local live, done = L.step(tr, 1040)
near(live.a, L.PEAK, 'a at its peak')
eq(live.b, 0, 'b has not started')
live = L.step(tr, 1120)
eq(live.b > 0 and live.b < L.PEAK, true, 'b rising')
eq(#done, 0, 'none done yet')
live, done = L.step(tr, 1000 + L.DURATION)
eq(live.a, nil, 'a is over')
eq(done[1], 'a', 'a reported done')
eq(live.b ~= nil, true, 'b still runs')
eq(tr.count, 1, 'one alive')
eq(L.start(tr, 'b', 1290), true, 'a key that pulses again restarts')
eq(tr.count, 1, 'a restart is not a second pulse')
live = L.step(tr, 1290 + L.RISE)
near(live.b, L.PEAK, 'restarted: peak again')
L.remove(tr, 'b')
eq(L.active(tr), false, 'removed')
L.remove(tr, 'b')
eq(tr.count, 0, 'removing twice keeps the count')
for i = 1, L.MAX_ALIVE do L.start(tr, i, 0) end
eq(L.start(tr, 'extra', 0), false, 'over the cap is dropped')
eq(L.start(tr, 1, 5), true, 'a live key may restart at the cap')
live, done = L.step(tr, 10000)
eq(#done, L.MAX_ALIVE, 'all finish')
eq(tr.count, 0, 'all gone')

if fails > 0 then print(fails .. ' failed'); os.exit(1) end
print('cooldownpulse_test: ok')
