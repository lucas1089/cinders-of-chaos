-- luajit screenfit_test.lua && lua5.3 screenfit_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'screenfit_logic.lua')
local L = ScreenFitLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- overflow
eq(L.overflows(600, 540), true, 'helper on a 540 phone')
eq(L.overflows(540, 540), false, 'exact fit')
eq(L.overflows(300, 540), false, 'small window')
eq(L.overflows(600, 0), false, 'parent not laid out yet')
eq(L.overflows(nil, 540), false, 'no size')

-- a window that fits: the old bind (inside the parent)
eq(L.clamp(100, 300, 0, 540), 100, 'inside stays')
eq(L.clamp(-20, 300, 0, 540), 0, 'pushed down to the top')
eq(L.clamp(400, 300, 0, 540), 240, 'pushed up to the bottom')
eq(L.clamp(30, 300, 20, 540), 30, 'parent offset kept')
eq(L.clamp(10, 300, 20, 540), 20, 'parent offset bind')

-- a window taller than the parent: it covers the parent, never leaves an empty strip
eq(L.clamp(0, 800, 0, 540), 0, 'title at the top')
eq(L.clamp(-260, 800, 0, 540), -260, 'scrolled to the bottom edge')
eq(L.clamp(-300, 800, 0, 540), -260, 'not past the bottom')
eq(L.clamp(50, 800, 0, 540), 0, 'not below the top')
eq(L.clamp(-100, 800, 0, 540), -100, 'middle')
eq(L.clamp(-300, 800, 20, 540), -240, 'parent offset: bottom edge at 560')

-- opening
eq(L.openStart(-30, 600, 0, 540), 0, 'tall window opens with its title in view')
eq(L.openStart(120, 300, 0, 540), 120, 'small window keeps its place')
eq(L.openStart(-30, 600, 15, 540), 15, 'parent offset')

-- the wheel
eq(L.wheel(0, 800, 0, 540, false), -L.WHEEL_STEP, 'wheel down shows the part below')
eq(L.wheel(-L.WHEEL_STEP, 800, 0, 540, true), 0, 'wheel up back to the top')
eq(L.wheel(0, 800, 0, 540, true), 0, 'wheel up at the top stays')
eq(L.wheel(-250, 800, 0, 540, false), -260, 'wheel down stops at the bottom')
eq(L.wheel(100, 300, 0, 540, false), 100, 'a window that fits does not move')
eq(L.WHEEL_STEP > 0 and L.WHEEL_STEP <= 120, true, 'wheel step sane')

print(string.format('screenfit_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
