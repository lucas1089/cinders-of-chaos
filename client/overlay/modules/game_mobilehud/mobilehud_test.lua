-- luajit mobilehud_test.lua && lua5.3 mobilehud_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'mobilehud_logic.lua')
local L = MobileHudLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(#L.barsToHide(true, false), 3, 'first start on a phone: the three bottom bars')
eq(L.barsToHide(true, false)[1], 'actionBarShowBottom1', 'bar names are the action bar options')
eq(#L.barsToHide(true, true), 0, 'only once')
eq(#L.barsToHide(false, false), 0, 'desktop untouched')
local a = L.barsToHide(true, false); a[1] = 'x'
eq(L.BARS[1], 'actionBarShowBottom1', 'the list is a copy')

if fails == 0 then print('mobilehud_test: ok') else os.exit(1) end
