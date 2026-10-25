-- luajit hudbars_test.lua && lua5.3 hudbars_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'hudmath.lua')
dofile(dir .. 'hudbars_logic.lua')
local B = HudBars
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the same constants as chaosbars.h
eq(B.EASE_MS, 150, 'ease 150 ms'); eq(B.HOLD_MS, 250, 'hold 250 ms'); eq(B.SLIDE_MS, 300, 'slide 300 ms')

-- first value: at once, no chip
local t = B.new()
B.observe(t, 80, 1000)
eq(B.shown(t, 1000), 80, 'first value'); eq(B.chipAt(t, 1000), 80, 'no chip'); eq(B.settled(t, 1000), true, 'settled')

-- a hit 80 -> 50
B.observe(t, 50, 2000)
eq(B.shown(t, 2000), 80, 'starts where it stood'); eq(B.chipAt(t, 2000), 80, 'chip starts at the old level')
local prev = 80
for ms = 0, B.EASE_MS do
  local s = B.shown(t, 2000 + ms)
  eq(s <= prev and s >= 50, true, 'bar down at ' .. ms)
  prev = s
end
eq(B.shown(t, 2000 + B.EASE_MS), 50, 'exact at the end of the ease')
eq(B.shown(t, 2000 + 75) < 65, true, 'ease-out')
for ms = 0, B.HOLD_MS, 10 do eq(B.chipAt(t, 2000 + ms), 80, 'chip holds at ' .. ms) end
prev = 80
for ms = B.HOLD_MS, B.HOLD_MS + B.SLIDE_MS do
  local c = B.chipAt(t, 2000 + ms)
  eq(c <= prev and c >= 50, true, 'chip slides at ' .. ms)
  eq(c >= B.shown(t, 2000 + ms), true, 'chip not below the bar at ' .. ms)
  prev = c
end
eq(B.chipAt(t, 2000 + 550), 50, 'chip gone at 550 ms'); eq(B.settled(t, 2000 + 550), true, 'settled after')
eq(B.settled(t, 2000 + 100), false, 'moving'); eq(B.settled(t, 2000 + 540), false, 'chip still sliding')

-- second hit while the chip holds: continues from the chip on screen
local h = B.new()
B.observe(h, 100, 0); B.observe(h, 70, 10); B.observe(h, 40, 210)
eq(B.chipAt(h, 210), 100, 'second hit keeps the chip level'); eq(B.shown(h, 210), 70, 'bar had arrived')
eq(B.chipAt(h, 210 + B.HOLD_MS), 100, 'hold restarted'); eq(B.chipAt(h, 210 + B.HOLD_MS + B.SLIDE_MS), 40, 'gone after the slide')

-- heal: ease up, no chip; an open chip is dropped
local g = B.new()
B.observe(g, 30, 0); B.observe(g, 90, 5)
for ms = 5, 5 + B.EASE_MS do
  eq(B.chipAt(g, ms), B.shown(g, ms), 'no chip while healing at ' .. ms)
  eq(B.shown(g, ms) >= 30 and B.shown(g, ms) <= 90, true, 'heal in range')
end
eq(B.shown(g, 5 + B.EASE_MS), 90, 'heal exact')
B.observe(g, 50, 400); B.observe(g, 95, 430)
for ms = 430, 1200, 9 do eq(B.chipAt(g, ms), B.shown(g, ms), 'heal drops the chip at ' .. ms) end

-- reset and stale
local r = B.new()
B.observe(r, 100, 0); B.reset(r); B.observe(r, 15, 50)
eq(B.shown(r, 50), 15, 'reset takes the value'); eq(B.settled(r, 50), true, 'no slide after reset')
local s = B.new()
B.observe(s, 100, 0)
B.observe(s, 20, 100000)
eq(B.shown(s, 100000), 100, 'no stale limit by default: it eases even after a long pause')
local st = B.new()
B.observe(st, 100, 0, 1000); B.observe(st, 20, 5000, 1000)
eq(B.shown(st, 5000), 20, 'a stale limit takes the value at once')
local back = B.new()
B.observe(back, 100, 5000); B.observe(back, 40, 5010); B.observe(back, 40, 100)
eq(B.shown(back, 100), 40, 'clock back takes the value')

-- percent
eq(B.percent(50, 100), 50, 'percent half'); eq(B.percent(0, 100), 0, 'empty'); eq(B.percent(5, 0), 0, 'no max')
eq(B.percent(150, 100), 100, 'over max'); eq(B.percent(nil, nil), 0, 'nil')

-- widths: at rest they are exactly the plate's old widths, for many values and maxima
for _, max in ipairs({ 1, 7, 100, 150, 1234, 20000 }) do
  for v = 0, max, math.max(1, math.floor(max / 37)) do
    local tr = B.new()
    B.observe(tr, B.percent(v, max), 0)
    local fill, chip, rest = B.widths(tr, v, max, 166, 5, HudMath.fillWidth)
    eq(rest, true, 'at rest')
    eq(fill, HudMath.fillWidth(v, max, 166), 'rest width ' .. v .. '/' .. max)
    eq(chip, fill, 'no chip pixels at rest')
  end
end
-- widths while moving: fill follows the bar, chip is never narrower, both within the bar
do
  local tr = B.new()
  B.observe(tr, 100, 0); B.observe(tr, 40, 10)
  local lastFill = 166
  for ms = 10, 10 + 600, 5 do
    local fill, chip, rest = B.widths(tr, 40, 100, 166, ms, HudMath.fillWidth)
    eq(chip >= fill and chip <= 166 and fill >= 0, true, 'widths in range at ' .. ms)
    eq(fill <= lastFill, true, 'fill never grows while it falls at ' .. ms)
    lastFill = fill
    if ms >= 10 + 550 then eq(rest, true, 'settled at the end') end
  end
  eq(lastFill, HudMath.fillWidth(40, 100, 166), 'ends at the plain width')
end

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks failed'); os.exit(1) end
print('hudbars tests OK (' .. checks .. ' checks)')
