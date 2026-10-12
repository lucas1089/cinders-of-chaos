-- luajit shieldmath_test.lua && lua5.3 shieldmath_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'shieldmath.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local s = ShieldMath.parse('es:350:500')
eq(s.current, 350, 'current'); eq(s.max, 500, 'max')
eq(ShieldMath.parse('es:900:500').current, 500, 'clamped to max')
eq(ShieldMath.parse('es:0:0').max, 0, 'hide message')
eq(ShieldMath.parse('es:-3:10').current, 0, 'never below 0')
eq(ShieldMath.parse('chi:3:5:12'), nil, 'another opcode text')
eq(ShieldMath.parse('{"action":"x"}'), nil, 'json')
eq(ShieldMath.parse(nil), nil, 'nil')
eq(ShieldMath.fillWidth(250, 500, 166), 83, 'half')
eq(ShieldMath.fillWidth(500, 500, 166), 166, 'full')
eq(ShieldMath.fillWidth(1, 100000, 166), 1, 'tiny but there')
eq(ShieldMath.fillWidth(0, 500, 166), 0, 'empty')
eq(ShieldMath.fillWidth(10, 0, 166), 0, 'no max')
eq(ShieldMath.ease(0, 100, 0, 400), 0, 'ease start')
eq(ShieldMath.ease(0, 100, 200, 400), 50, 'ease half')
eq(ShieldMath.ease(0, 100, 500, 400), 100, 'ease done')
eq(ShieldMath.ease(80, 20, 100, 0), 20, 'no easing')
eq(ShieldMath.pair(5, 10), '5 / 10', 'pair plain')
if fails > 0 then os.exit(1) end
print('energy shield bar tests OK')
