-- luajit rotation_test.lua && lua5.3 rotation_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'rotation.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
eq(RotationView.left(3 * 86400 + 4 * 3600 + 59), '3d 04h', 'days')
eq(RotationView.left(5 * 3600 + 7 * 60), '5h 07m', 'hours')
eq(RotationView.left(12 * 60 + 30), '12m', 'minutes')
eq(RotationView.left(20), '1m', 'under a minute')
eq(RotationView.left(-5), '0m', 'over')
eq(RotationView.left('x'), '0m', 'bad input')
eq(RotationView.label('This week', 1000 + 86400, 1000), 'This week (1d 00h)', 'label')
eq(RotationView.label('Outfits', nil, 1000), 'Outfits', 'no countdown')
if fails > 0 then error(fails .. ' failure(s)') end
print('rotation_test: all passed')
