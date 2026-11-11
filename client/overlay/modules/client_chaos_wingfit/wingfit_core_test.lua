-- luajit wingfit_core_test.lua && lua5.3 wingfit_core_test.lua (CI runs it from the repo root)
-- Wings centred on the body: the generated tables (wing_centres.lua, gen_wing_centres.py on the live pair) and their
-- hand-over to the engine. The owner's screenshot look (Warrior class 2073 with Frost Crystal Wings 2414) gets the shift
-- that puts the wings' pair centre on its torso.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'wing_centres.lua')
dofile(dir .. 'wingfit_core.lua')
local C = WingFitCore
local D = ChaosWingCentres
local fails = 0
local function ok(cond, what)
  if not cond then print('FAIL ' .. what); fails = fails + 1 end
end

-- the data
ok(type(D) == 'table' and type(D.dat) == 'string' and #D.dat == 32, 'dat md5 in the table')
local nb, nw = 0, 0
for id, row in pairs(D.bodies) do
  nb = nb + 1
  ok(type(id) == 'number' and #row == 4 and math.abs(row[3]) <= 120, 'body row ' .. tostring(id))
end
for id, row in pairs(D.wings) do
  nw = nw + 1
  ok(type(id) == 'number' and #row == 4 and math.abs(row[3]) <= 60, 'wings row ' .. tostring(id))
end
ok(nb >= 1000, 'bodies: ' .. nb)
ok(nw == 121, 'wings: ' .. nw)
-- the wings of the store and the exclusives are all in
for _, id in ipairs({ 937, 1186, 1486, 2140, 2187, 2225, 2233, 2385, 2414, 2441, 2476 }) do
  ok(D.wings[id] ~= nil, 'wings ' .. id .. ' has a row')
end
-- every class look has a body row
for _, id in ipairs({ 2060, 2061, 2073, 2074, 2161, 2183, 2173, 2163, 2045, 2049, 2080, 2169, 2171, 2179, 2181 }) do
  ok(D.bodies[id] ~= nil, 'class look ' .. id .. ' has a row')
end

-- the entries of a table and the hand-over
local list = C.entries(D.bodies)
ok(#list == nb * 4, 'four directions per body: ' .. #list)
ok(list[1][1] <= list[#list][1] and list[1][2] == 0, 'sorted, north first')
local counted = { b = 0, w = 0 }
local gotb, gotw
local a, b = C.apply(D, function(l, d, px) counted.b = counted.b + 1; if l == 2073 and d == 2 then gotb = px end end,
  function(l, d, px) counted.w = counted.w + 1; if l == 2414 and d == 2 then gotw = px end end)
ok(a == nb and b == nw and counted.b == nb * 4 and counted.w == nw * 4, 'apply counts ' .. tostring(a) .. ' ' .. tostring(b))
ok(gotb == D.bodies[2073][3] and gotw == D.wings[2414][3], 'apply hands the south values')
ok(select(1, C.apply(nil, error, error)) == 0, 'no table: nothing')
-- bad rows are left out
local junk = { bodies = { [5] = { 1, 2, 3 }, [6] = { 1, 2, 3, 4 }, ['x'] = { 1, 2, 3, 4 }, [0] = { 1, 2, 3, 4 } },
  wings = { [7] = { 1, 2, 3, 'a' } } }
local n1, n2 = C.apply(junk, function() end, function() end)
ok(n1 == 1 and n2 == 0, 'only the whole rows count: ' .. n1 .. ' ' .. n2)

-- the shift: wings' pair centre onto the torso, the lift taken out
local body, wings = D.bodies[2073][3], D.wings[2414][3]
ok(C.shiftOf(D, 2073, 2414, 2, 6) == body - wings - 6, 'Warrior with Frost Crystal Wings: ' .. C.shiftOf(D, 2073, 2414, 2, 6))
ok(C.shiftOf(D, 2073, 2414, 2, 0) == body - wings, 'without the lift feature')
ok(C.shiftOf(D, 2073, 9999, 2, 6) == 0 and C.shiftOf(D, 9999, 2414, 2, 6) == 0, 'a look without a row: no shift')
ok(C.shiftOf(nil, 2073, 2414, 2, 6) == 0, 'no data')
ok(C.shiftOf({ bodies = { [1] = { 0, 0, 100, 0 } }, wings = { [2] = { 0, 0, -100, 0 } } }, 1, 2, 2, 6) == 0, 'over the limit')
-- after the shift the pair centre is on the torso for every look and wings pair (the engine's landing rule)
local worst = 0
for look, brow in pairs(D.bodies) do
  for _, wid in ipairs({ 937, 2231, 2414, 2441 }) do
    for d = 0, 3 do
      local s = C.shiftOf(D, look, wid, d, 6)
      if s ~= 0 then
        local torso = -6 + brow[d + 1]
        local pair = s + D.wings[wid][d + 1]
        worst = math.max(worst, math.abs(torso - pair))
      end
    end
  end
end
ok(worst == 0, 'landing: torso and pair centre agree, worst ' .. worst)
-- the two outliers of the first measure (a thin streak beside the wing) are not off: 2441 south is near its mean
ok(math.abs(D.wings[2441][3] - D.wings[2414][3]) <= 8, '2441 is no outlier: ' .. D.wings[2441][3])

if fails > 0 then os.exit(1) end
print('wingfit_core_test: all checks passed')
