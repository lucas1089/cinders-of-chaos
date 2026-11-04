-- luajit touchscroll_test.lua && lua5.3 touchscroll_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'touchscroll_logic.lua')
local L = TouchScrollLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- which gestures scroll
eq(L.decide(2, 20, 50, true, false, false, false), 'v', 'vertical swipe on a list')
eq(L.decide(2, 20, 50, true, false, true, false), 'v', 'quick swipe over an item scrolls')
eq(L.decide(2, 20, L.HOLD_MS, true, false, true, false), nil, 'resting on an item drags it')
eq(L.decide(2, 20, 2000, true, false, false, false), 'v', 'a slow start on a plain row still scrolls')
eq(L.decide(20, 2, 50, true, false, false, false), nil, 'sideways swipe on a vertical list')
eq(L.decide(20, 2, 50, true, true, false, false), 'h', 'sideways swipe on a wide area')
eq(L.decide(2, 20, 50, false, false, false, false), nil, 'nothing to scroll (the map)')
eq(L.decide(2, 20, 50, true, false, false, true), nil, 'a touch on the scroll bar moves the bar')
eq(L.decide(-5, -30, 50, true, false, false, false), 'v', 'upward swipe')

-- value follows the finger and stays in range
eq(L.value(100, -30, 0, 500), 130, 'finger up shows lower rows')
eq(L.value(100, 30, 0, 500), 70, 'finger down shows upper rows')
eq(L.value(10, 30, 0, 500), 0, 'clamped at the top')
eq(L.value(490, -30, 0, 500), 500, 'clamped at the bottom')
eq(L.value(-50, 30, -200, 0), -80, 'inverted range')
eq(L.value(5, 1, 0, 0), 0, 'no range')
eq(L.canScroll(0, 0), false, 'empty range'); eq(L.canScroll(0, 12), true, 'range'); eq(L.canScroll(-40, 0), true, 'inverted')

-- glide speed from the last 100 ms
local s = {}
L.addSample(s, 1000, -10); L.addSample(s, 1020, -10); L.addSample(s, 1040, -10); L.addSample(s, 1060, -10)
local v = L.speed(s, 1060)
eq(v < 0, true, 'speed has the finger sign')
eq(math.floor(-v * 100 + 0.5), 67, 'speed is movement over time (40 px / 60 ms)')
eq(L.speed({ { 1000, 1 }, { 1050, 1 } }, 1050), 0, 'slow lift does not glide')
eq(L.speed({ { 0, -50 } }, 1000), 0, 'old samples do not count')
eq(L.speed({ { 1000, -500 } }, 1000), -L.MAX_SPEED, 'speed is capped')
s = {}
for t = 0, 1000, 10 do L.addSample(s, t, 1) end
eq(#s <= 12, true, 'samples are trimmed to the last stretch')

-- glide slows down and ends
local d, nv = L.glide(2, 16)
eq(d, 32, 'glide moves speed x time')
eq(nv < 2 and nv > 0, true, 'glide slows')
local total, frames = 0, 0
v = 3
while v ~= 0 and frames < 1000 do d, v = L.glide(v, 16); total = total + d; frames = frames + 1 end
eq(frames < 200, true, 'glide ends in a few seconds at most')
eq(total > 100, true, 'a fast lift glides a fair way')
eq(select(2, L.glide(0.01, 16)), 0, 'slow glide stops')

if fails == 0 then print('touchscroll_test: ok') else os.exit(1) end
