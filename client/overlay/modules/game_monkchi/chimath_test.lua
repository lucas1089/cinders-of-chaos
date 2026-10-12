-- luajit chimath_test.lua && lua5.3 chimath_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'chimath.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local s = ChiMath.parse('chi:3:5:12')
eq(s.chi, 3, 'chi'); eq(s.max, 5, 'max'); eq(s.decay, 12, 'decay')
eq(ChiMath.parse('chi:9:5:12').chi, 5, 'clamped to max')
eq(ChiMath.parse('chi:0:0:0').max, 0, 'hide message')
eq(ChiMath.parse('{"action":"x"}'), nil, 'not a chi message')
eq(ChiMath.parse(nil), nil, 'nil')
eq(ChiMath.shown(s, 100, 105), 3, 'fresh')
eq(ChiMath.shown(s, 100, 112), 0, 'faded with the server')
eq(ChiMath.shown(nil, 0, 0), 0, 'no state')
eq(ChiMath.pip(1, 3, 5), 'full', 'pip 1'); eq(ChiMath.pip(3, 3, 5), 'full', 'pip 3')
eq(ChiMath.pip(4, 3, 5), 'empty', 'pip 4'); eq(ChiMath.pip(6, 3, 5), 'hidden', 'pip beyond max')
eq(ChiMath.fadeIn(s, 100, 104), 8, 'fades in 8 s'); eq(ChiMath.fadeIn(ChiMath.parse('chi:0:5:12'), 0, 0), nil, 'empty')
eq(ChiMath.isMonk(17) and ChiMath.isMonk(18) and ChiMath.isMonk(19), true, 'monk line')
eq(ChiMath.isMonk(11), false, 'thief'); eq(ChiMath.isMonk(nil), false, 'nil')
if fails > 0 then os.exit(1) end
print('chi HUD tests OK')
