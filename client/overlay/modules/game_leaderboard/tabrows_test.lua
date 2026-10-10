-- luajit tabrows_test.lua && lua5.3 tabrows_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'tabrows.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- every tab keeps its label width, the order is kept and every row fits
local function check(widths, avail, gap, what)
  local rows = TabRows.layout(widths, avail, gap)
  local n = 0
  for r, row in ipairs(rows) do
    local used = gap * (#row - 1)
    for _, t in ipairs(row) do
      n = n + 1
      eq(t.index, n, what .. ' order')
      if t.width < math.min(avail, widths[t.index]) then eq(t.width, widths[t.index], what .. ' tab too narrow') end
      used = used + t.width
    end
    if used > avail then eq(used, avail, what .. ' row ' .. r .. ' overflows') end
  end
  eq(n, #widths, what .. ' count')
  return rows
end

-- 11 boards in the 590 px row (the server's weekly boards and the ladder), labels 50..100 px
local boards = { 82, 86, 78, 100, 52, 98, 80, 74, 74, 70, 92 }
local rows = check(boards, 590, 4, 'boards')
eq(#rows, 2, 'boards fit two rows')
eq(math.abs(#rows[1] - #rows[2]) <= 1, true, 'boards balanced')
local used = 4 * (#rows[1] - 1)
for _, t in ipairs(rows[1]) do used = used + t.width end
eq(used, 590, 'a row fills the width')

-- the 7 class groups fit one row
eq(#check({ 70, 66, 64, 58, 98, 54, 72 }, 590, 3, 'groups'), 1, 'groups one row')

-- a wider font (the Chaos fonts) only adds rows, never cuts a label
eq(#check({ 120, 126, 118, 150, 80, 148, 120, 112, 110, 104, 138 }, 590, 4, 'wide'), 3, 'wide font three rows')

-- maxWidth caps the growth of a short row, not a label
rows = TabRows.layout({ 60, 60 }, 590, 4, 124)
eq(rows[1][1].width, 124, 'max width')
rows = TabRows.layout({ 200 }, 590, 4, 124)
eq(rows[1][1].width, 200, 'max width never cuts')

-- a label wider than the row gets the whole row
rows = TabRows.layout({ 50, 900, 50 }, 300, 4)
eq(#rows, 3, 'too wide alone')
eq(rows[2][1].width, 300, 'too wide gets the row')

eq(#TabRows.layout({}, 590, 4), 0, 'no tabs')
eq(#TabRows.layout(nil, 590, 4), 0, 'nil tabs')

eq(TabRows.valueText(305, 'time'), '5:05', 'time format')
eq(TabRows.valueText(59, 'time'), '0:59', 'under a minute')
eq(TabRows.valueText(305, nil), nil, 'no format: the caller formats')

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('tabrows: all tests passed')
