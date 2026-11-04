-- luajit walkpad_test.lua && lua5.3 walkpad_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'walkpad_logic.lua')
local L = WalkPadLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local x, y

x, y = L.clamp(-5, 9999, 1000, 461, 200, 150)
eq(x, 0, 'clamp left'); eq(y, 311, 'clamp bottom')
x, y = L.clamp(900, -3, 1000, 461, 200, 150)
eq(x, 800, 'clamp right'); eq(y, 0, 'clamp top')
x, y = L.clamp(100, 100, 1000, 461, 200, 150)
eq(x, 100, 'inside x'); eq(y, 100, 'inside y')
x, y = L.clamp(50, 50, 100, 100, 200, 150)
eq(x, 0, 'pad bigger than screen x'); eq(y, 0, 'pad bigger than screen y')
x, y = L.clamp(nil, 'a', 1000, 461, 200, 150)
eq(x, 0, 'bad x'); eq(y, 0, 'bad y')

x, y = L.defaultPos(1000, 461, 200, 150)
eq(x, 8, 'default left'); eq(y, 461 - 150 - 130 - 8, 'default above orb')
eq(y + 150 <= 461 - L.ORB, true, 'default does not touch orb')
x, y = L.defaultPos(1000, 200, 200, 150)
eq(y, 0, 'default on a tiny screen is clamped')

local fx, fy = L.toFraction(400, 155.5, 1000, 461, 200, 150)
eq(fx, 0.5, 'fraction x'); eq(fy, 0.5, 'fraction y')
x, y = L.fromFraction(0.5, 0.5, 1000, 461, 200, 150)
eq(x, 400, 'restore x'); eq(y, 155.5, 'restore y')
x, y = L.fromFraction(1, 1, 500, 300, 200, 150)
eq(x, 300, 'restore after resize x'); eq(y, 150, 'restore after resize y')
x, y = L.fromFraction(nil, nil, 1000, 461, 200, 150)
eq(x, 8, 'nothing saved: default x')
x, y = L.fromFraction(2, 0.5, 1000, 461, 200, 150)
eq(x, 8, 'bad saved: default x')
x, y = L.fromFraction(0 / 0, 0.5, 1000, 461, 200, 150)
eq(x, 8, 'nan saved: default x')
fx, fy = L.toFraction(0, 0, 200, 150, 200, 150)
eq(fx, 0, 'no room x'); eq(fy, 0, 'no room y')

x, y = L.drag(100, 100, 50, -200, 1000, 461, 200, 150)
eq(x, 150, 'drag x'); eq(y, 0, 'drag clamps top')

eq(L.isDoubleTap(nil, 0, 0, 100, 0, 0), false, 'no first tap')
eq(L.isDoubleTap(100, 5, 5, 400, 8, 6), true, 'double tap')
eq(L.isDoubleTap(100, 5, 5, 700, 5, 5), false, 'too slow')
eq(L.isDoubleTap(100, 5, 5, 300, 60, 5), false, 'too far')
eq(L.isTap(3), true, 'tap'); eq(L.isTap(40), false, 'drag is not a tap')

-- walking
eq(L.direction(0.5, 0.5), nil, 'middle is nothing')
eq(L.direction(0.55, 0.45), nil, 'near middle is nothing')
eq(L.direction(0.5, 0.05), 'N', 'north'); eq(L.direction(0.5, 0.95), 'S', 'south')
eq(L.direction(0.05, 0.5), 'W', 'west'); eq(L.direction(0.95, 0.5), 'E', 'east')
eq(L.direction(0.1, 0.1), 'NW', 'north west'); eq(L.direction(0.9, 0.1), 'NE', 'north east')
eq(L.direction(0.1, 0.9), 'SW', 'south west'); eq(L.direction(0.9, 0.9), 'SE', 'south east')
eq(L.direction(-3, 0.5), 'W', 'clamped outside'); eq(L.direction(nil, 'x'), nil, 'bad input is the middle')
local top, left = L.pointer(0.5, 0.5)
eq(top, 0, 'pointer middle top'); eq(left, 0, 'pointer middle left')
top, left = L.pointer(0.5, 0)
eq(math.floor(top + 0.5), -75, 'pointer north top'); eq(math.floor(left + 0.5), 0, 'pointer north left')
eq(L.repeating(1000, 1000 + L.HOLD_MS - 1), false, 'a tap does not repeat')
eq(L.repeating(1000, 1000 + L.HOLD_MS), true, 'a hold repeats')
eq(L.dropQueued(1000, 1100), false, 'a tap keeps its queued step')
eq(L.dropQueued(1000, 2000), true, 'a hold drops the queued step')

if fails == 0 then print('walkpad_test: ok') else os.exit(1) end
