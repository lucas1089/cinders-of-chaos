-- luajit infolift_core_test.lua && lua5.3 infolift_core_test.lua (CI runs it from the repo root)
-- Names over tall looks: the generated table (info_lifts.lua, gen_info_lift.py on the live pair) and its hand-over
-- to the engine. The Necromancer look of the owner's report (2183 / 2184, witch hat) is lifted; the stock citizen
-- (128 / 136) keeps the classic place.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'info_lifts.lua')
dofile(dir .. 'infolift_core.lua')
local C = InfoLiftCore
local D = ChaosInfoLifts
local fails = 0
local function ok(cond, what)
  if not cond then print('FAIL ' .. what); fails = fails + 1 end
end

-- the data
ok(type(D) == 'table' and type(D.dat) == 'string' and #D.dat == 32, 'dat md5 in the table')
local n = 0
for k, v in pairs(D) do
  if k ~= 'dat' then
    n = n + 1
    ok(type(k) == 'number' and k >= 1 and type(v) == 'number' and v >= 3 and v <= C.MAX and v == math.floor(v),
      'entry ' .. tostring(k) .. ' = ' .. tostring(v))
  end
end
ok(n >= 100, 'looks in the table: ' .. n)

-- the report's look and the other tall class looks go up; the stock citizen does not
for _, look in ipairs({ 2183, 2184, 2173, 2174, 2064 }) do
  ok(C.liftOf(D, look) >= 6, 'tall class look ' .. look .. ' lifted: ' .. C.liftOf(D, look))
end
ok(C.liftOf(D, 2183) >= 12, 'the Necromancer in the witch hat clears the hat: ' .. C.liftOf(D, 2183))
for _, look in ipairs({ 128, 136 }) do
  ok(C.liftOf(D, look) == 0, 'stock look ' .. look .. ' keeps its place')
end

-- the core
local list = C.entries({ dat = 'x', [5] = 4, [2] = 200, [3] = 0, [4] = -1, [6] = 'a', [7.5] = 3 })
ok(#list == 2 and list[1][1] == 2 and list[1][2] == C.MAX and list[2][1] == 5 and list[2][2] == 4,
  'entries: valid rows only, sorted, capped')
ok(#C.entries(nil) == 0, 'entries of nothing')
local got = {}
ok(C.apply({ [10] = 7, [11] = 9 }, function(look, lift) got[look] = lift end) == 2, 'apply count')
ok(got[10] == 7 and got[11] == 9, 'apply hands every entry over')
ok(C.liftOf({ [3] = 5 }, 3) == 5 and C.liftOf({ [3] = 5 }, 4) == 0 and C.liftOf(nil, 3) == 0, 'liftOf')
ok(C.apply(D, function() end) == n, 'apply the generated table')

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('infolift_core_test: OK (' .. n .. ' looks)')
