-- luajit hud_test.lua && lua5.3 hud_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'hudmath.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
eq(HudMath.fillWidth(50, 100, 166), 83, 'half')
eq(HudMath.fillWidth(100, 100, 166), 166, 'full')
eq(HudMath.fillWidth(150, 100, 166), 166, 'over max')
eq(HudMath.fillWidth(0, 100, 166), 0, 'empty')
eq(HudMath.fillWidth(1, 100000, 166), 1, 'tiny but alive')
eq(HudMath.fillWidth(10, 0, 166), 0, 'no max')
eq(HudMath.fillWidth(-5, 100, 166), 0, 'negative')
eq(HudMath.fillWidth(nil, nil, 166), 0, 'nil')
eq(HudMath.pair(5, 10), '5 / 10', 'pair plain')
if fails > 0 then os.exit(1) end
print('hud tests OK')
