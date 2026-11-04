-- luajit mobilebag_test.lua && lua5.3 mobilebag_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'mobilebag_logic.lua')
local L = MobileBagLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(L.cell(180, 3), 56, 'phone side panel: 3 columns, capped')
eq(L.cell(160, 3), 51, 'narrower panel: 3 columns of 51')
eq(L.cell(150, 3), 48, 'just 3 columns of the minimum')
eq(L.cell(100, 3), 48, '2 columns, the minimum')
eq(L.cell(0, 3), L.FALLBACK, 'no width yet')
eq(L.cell(nil, nil), L.FALLBACK, 'bad input')
eq(L.cell(1000, 3) <= L.MAX, true, 'never above the maximum')
for w = 48, 400 do
  local c = L.cell(w, 3)
  if c < L.MIN or c > L.MAX then eq(c, 'in range', 'cell at width ' .. w) end
  local cols = math.floor((w + 3) / (c + 3))
  if c < L.MAX and cols < 1 then eq(cols, '>= 1', 'columns at width ' .. w) end
end
eq(L.maxHeight(52, 3, 4), 220, 'max height: lines x (cell + spacing)')
eq(L.maxHeight(52, 3, 0), 55, 'at least one line')

if fails == 0 then print('mobilebag_test: ok') else os.exit(1) end
