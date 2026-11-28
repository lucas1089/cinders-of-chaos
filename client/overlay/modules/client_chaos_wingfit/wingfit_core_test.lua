-- luajit wingfit_core_test.lua && lua5.3 wingfit_core_test.lua (CI runs it from the repo root)
-- Wings centred on the body: the generated tables (wing_centres.lua, gen_wing_centres.py on the live pair) and their
-- hand-over to the engine. The owner's screenshot look (Warrior class 2073; Frost Crystal Wings 2414 is pack art now, O747) gets the shift
-- that puts the wings' pair centre on its torso.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'wing_centres.lua')
dofile(dir .. 'head_centres.lua')
dofile(dir .. 'wear_pieces.lua')
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
-- 73 wings looks carry purchased pack art (O747): base patch 0209 places them by their anchor tile, no row here
ok(nw == 48, 'wings: ' .. nw)
-- the wings of the store and the exclusives are all in
for _, id in ipairs({ 937, 1186, 1486, 2140, 2187, 2225, 2231, 2233 }) do
  ok(D.wings[id] ~= nil, 'wings ' .. id .. ' has a row')
end
for _, id in ipairs({ 2385, 2402, 2414, 2422, 2441, 2476 }) do
  ok(D.wings[id] == nil, 'pack art wings ' .. id .. ' has no row')
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
  function(l, d, px) counted.w = counted.w + 1; if l == 2231 and d == 2 then gotw = px end end)
ok(a == nb and b == nw and counted.b == nb * 4 and counted.w == nw * 4, 'apply counts ' .. tostring(a) .. ' ' .. tostring(b))
ok(gotb == D.bodies[2073][3] and gotw == D.wings[2231][3], 'apply hands the south values')
ok(select(1, C.apply(nil, error, error)) == 0, 'no table: nothing')
-- bad rows are left out
local junk = { bodies = { [5] = { 1, 2, 3 }, [6] = { 1, 2, 3, 4 }, ['x'] = { 1, 2, 3, 4 }, [0] = { 1, 2, 3, 4 } },
  wings = { [7] = { 1, 2, 3, 'a' } } }
local n1, n2 = C.apply(junk, function() end, function() end)
ok(n1 == 1 and n2 == 0, 'only the whole rows count: ' .. n1 .. ' ' .. n2)

-- the shift: wings' pair centre onto the torso, the lift taken out
local body, wings = D.bodies[2073][3], D.wings[2231][3]
ok(C.shiftOf(D, 2073, 2231, 2, 6) == body - wings - 6, 'Warrior with Gloomgild Wings: ' .. C.shiftOf(D, 2073, 2231, 2, 6))
ok(C.shiftOf(D, 2073, 2231, 2, 0) == body - wings, 'without the lift feature')
ok(C.shiftOf(D, 2073, 9999, 2, 6) == 0 and C.shiftOf(D, 9999, 2231, 2, 6) == 0 and C.shiftOf(D, 2073, 2414, 2, 6) == 0, 'a look without a row: no shift')
ok(C.shiftOf(nil, 2073, 2231, 2, 6) == 0, 'no data')
ok(C.shiftOf({ bodies = { [1] = { 0, 0, 100, 0 } }, wings = { [2] = { 0, 0, -100, 0 } } }, 1, 2, 2, 6) == 0, 'over the limit')
-- after the shift the pair centre is on the torso for every look and wings pair (the engine's landing rule)
local worst = 0
for look, brow in pairs(D.bodies) do
  for _, wid in ipairs({ 937, 1486, 2231, 2233 }) do
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

-- head accessories on the head (base patch 0200): head_centres.lua and its hand-over
local H = ChaosHeadCentres
ok(type(H) == 'table' and type(H.dat) == 'string' and #H.dat == 32 and H.dat == D.dat, 'head table: same pair as the wing table')
ok(H.first == 2477 and H.last == 2568, 'head piece range')
ok(type(H.ref) == 'table' and #H.ref == 8, 'reference look 128 has a head per direction')
local nh = 0
for id, row in pairs(H.bodies) do
  nh = nh + 1
  -- 170: Malgrath (3530, 7x7 tiles, O637) has its head 158 px above the foot tile
  ok(type(id) == 'number' and #row == 8 and math.abs(row[5]) <= 170 and math.abs(row[6]) <= 170, 'head row ' .. tostring(id))
end
ok(nh == nb, 'a head row for every body row: ' .. nh .. ' ' .. nb)
for _, id in ipairs({ 2060, 2061, 2073, 2074, 2161, 2183, 2173, 2163, 2045, 2049, 2080, 2169, 2171, 2179 }) do
  ok(H.bodies[id] ~= nil, 'class look ' .. id .. ' has a head row')
end
-- the hand-over: reference, range, every row, four directions
local calls = { ref = 0, pieces = 0, body = 0 }
local gotRef, gotPieces, gotBody
local n = C.applyHeads(H, function(d, x, y) calls.ref = calls.ref + 1; if d == 2 then gotRef = { x, y } end end,
  function(f, l) calls.pieces = calls.pieces + 1; gotPieces = { f, l } end,
  function(l, d, x, y) calls.body = calls.body + 1; if l == 2073 and d == 2 then gotBody = { x, y } end end)
ok(n == nh and calls.ref == 4 and calls.pieces == 1 and calls.body == nh * 4, 'applyHeads counts ' .. n)
ok(gotRef[1] == H.ref[5] and gotRef[2] == H.ref[6] and gotPieces[1] == 2477 and gotPieces[2] == 2568, 'applyHeads hands the reference and range')
ok(gotBody[1] == H.bodies[2073][5] and gotBody[2] == H.bodies[2073][6], 'applyHeads hands the south head')
ok(C.applyHeads(nil, error, error, error) == 0, 'no head table: nothing')
ok(C.applyHeads({ first = 1, last = 2, ref = { 1, 2, 3 }, bodies = {} }, error, error, error) == 0, 'a short reference: nothing')
ok(C.applyHeads({ first = 5, last = 2, ref = { 1, 2, 3, 4, 5, 6, 7, 8 }, bodies = {} }, error, error, error) == 0, 'a bad range: nothing')
local junkH = { first = 10, last = 20, ref = { 0, 0, 0, 0, 0, 0, 0, 0 }, bodies = { [5] = { 1, 2, 3 }, [6] = { 1, 2, 3, 4, 5, 6, 7, 8 }, x = { 1, 2, 3, 4, 5, 6, 7, 8 } } }
ok(C.applyHeads(junkH, function() end, function() end, function() end) == 1, 'only whole rows count')
-- the shift: head(body) - head(128), per direction, inside the piece range only
local s2 = C.headShiftOf(H, 2073, 2486, 2)
ok(s2[1] == H.bodies[2073][5] - H.ref[5] and s2[2] == H.bodies[2073][6] - H.ref[6], 'Warrior with Bull Horns: ' .. s2[1] .. ',' .. s2[2])
local s0 = C.headShiftOf(H, 2073, 2486, 0)
ok(s0[1] == H.bodies[2073][1] - H.ref[1] and s0[2] == H.bodies[2073][2] - H.ref[2], 'north')
local sr = C.headShiftOf(H, 128, 2486, 2)
ok(sr[1] == 0 and sr[2] == 0, 'look 128 needs no shift')
ok(C.headShiftOf(H, 2073, 2414, 2)[1] == 0 and C.headShiftOf(H, 2073, 2569, 2)[2] == 0 and C.headShiftOf(H, 2073, 0, 2)[1] == 0, 'outside the piece range: none')
ok(C.headShiftOf(H, 99999, 2486, 2)[1] == 0 and C.headShiftOf(nil, 2073, 2486, 2)[1] == 0, 'no row, no table: none')
ok(C.headShiftOf({ first = 1, last = 9, ref = { 0, 0, 0, 0, 0, 0, 0, 0 }, bodies = { [3] = { 0, 0, 0, 0, 99, 0, 0, 0 } } }, 3, 5, 2)[1] == 0, 'over the limit')
-- the class looks stand left of and above look 128 on average (the owner's picture): the median shift is negative
local xs, ys = {}, {}
for _, id in ipairs({ 2045, 2046, 2049, 2050, 2055, 2056, 2060, 2061, 2062, 2063, 2071, 2072, 2073, 2074, 2075, 2076, 2080, 2081 }) do
  local sh = C.headShiftOf(H, id, 2486, 2)
  xs[#xs + 1], ys[#ys + 1] = sh[1], sh[2]
end
table.sort(xs); table.sort(ys)
ok(xs[math.floor(#xs / 2)] <= 0 and ys[math.floor(#ys / 2)] < 0, 'the median class head is left of and above look 128: ' .. xs[math.floor(#xs / 2)] .. ',' .. ys[math.floor(#ys / 2)])

-- code-drawn wings (O583): the anchors file and its hand-over
dofile(dir .. 'wing_anchors.lua')
local A = ChaosWingAnchors
ok(type(A) == 'table' and #A.wings == 127 and A.anchor[1] == -16 and A.anchor[2] == 0, 'the anchors file: 121 old wings and the 6 of O581 phase 2, one anchor')
local seenW, lastW, sortedW = {}, 0, true
for _, id in ipairs(A.wings) do
  if seenW[id] or id <= lastW then sortedW = false end
  seenW[id], lastW = true, id
end
ok(sortedW, 'the wings ids are sorted and unique')
local gotW, gotB = {}, {}
local nw, nr = C.applyAnchors(A, function(l, x, y) gotW[#gotW + 1] = { l, x, y } end, function(l, d, x, y) gotB[#gotB + 1] = { l, d, x, y } end)
ok(nw == 127 and #gotW == 127 and nr == #A.bodies and #gotB == nr, 'applyAnchors counts ' .. nw .. ' ' .. nr)
ok(gotW[1][1] == A.wings[1] and gotW[1][2] == -16 and gotW[1][3] == 0, 'applyAnchors hands the anchor')
ok(C.applyAnchors(nil, error, error) == 0 and C.applyAnchors({ wings = { 5 } }, error, error) == 0, 'no table, no anchor: nothing')
local junkA = { anchor = { -16.7, 0 }, wings = { 9, 'x', 0, 2.5, 4 }, bodies = { { 7, 2, -30, -4 }, { 7, 4, 0, 0 }, { 7, 1 }, 'x' } }
gotW, gotB = {}, {}
nw, nr = C.applyAnchors(junkA, function(l, x, y) gotW[#gotW + 1] = { l, x, y } end, function(l, d, x, y) gotB[#gotB + 1] = { l, d, x, y } end)
ok(nw == 2 and gotW[1][1] == 4 and gotW[2][1] == 9 and gotW[1][2] == -17, 'only whole ids, sorted, whole pixels')
ok(nr == 1 and gotB[1][1] == 7 and gotB[1][2] == 2 and gotB[1][3] == -30 and gotB[1][4] == -4, 'only whole hand rows')

-- purchased pieces of pair 83 (O747, base patch 0209): every generated row goes in, every lift has whole pairs
local P = ChaosWearPieces
ok(type(P) == 'table' and P.pair == 83 and P.frameMs == 83, 'wear_pieces pair 83')
local pieces, lifts = {}, {}
local np, nl = C.applyPieces(P, function(look, ax, ay) pieces[#pieces + 1] = { look, ax, ay } end,
  function(look, text) lifts[#lifts + 1] = { look, text } end)
ok(np == #P.pieces and np == 218, 'all 218 pieces: ' .. np)
local nlifts = 0
for _ in pairs(P.lifts) do nlifts = nlifts + 1 end
ok(nl == nlifts and nl == 74, 'a lift per wings look: ' .. nl)
ok(#P.heads == 66 and #P.capes == 78, 'heads and capes')
local seen = {}
for _, row in ipairs(P.pieces) do
  ok(not seen[row[1]], 'look once ' .. row[1]); seen[row[1]] = true
end
for _, h in ipairs(P.heads) do ok(seen[h.look] and h.look >= P.first, 'head look ' .. h.key) end
for _, c in ipairs(P.capes) do ok(seen[c.look] and c.look >= P.first, 'cape look ' .. c.key) end
np, nl = C.applyPieces({ pieces = { { 5, 1, 2 }, { 0, 1, 1 }, { 6, 9, 0 }, 'x' },
  lifts = { [5] = '1 -2', [6] = '1', [7] = '0 0.5', [8] = '0 99' } },
  function() end, function(look) ok(look == 5, 'only the good lift ' .. look) end)
ok(np == 1 and nl == 1, 'bad rows skipped')
ok(C.applyPieces(nil) == 0, 'no table')
-- O762: the Float option off: every piece, no lift (the body stays on the ground, the wings are still placed)
local offPieces, offLifts = 0, 0
np, nl = C.applyPieces(P, function() offPieces = offPieces + 1 end, function() offLifts = offLifts + 1 end, false)
ok(np == 218 and offPieces == 218, 'float off: every piece still goes in')
ok(nl == 0 and offLifts == 0, 'float off: no lift')
np, nl = C.applyPieces(P, function() end, function() end, true)
ok(nl == 74, 'float on: the lifts')
ok(C.levitationOn(nil) and C.levitationOn(true) and C.levitationOn('true'), 'float is on by default')
ok(not C.levitationOn(false) and not C.levitationOn('false'), 'float off when saved off')

-- O779 (base patch 0217): the north view of every pack wing moves up onto the south one's height (pack_wear_shift.csv,
-- pair 90: 8 to 13 px up, 2 to 5 px right); O784 (base patch 0218): the east view 5 to 10 px up and the west view 1 to 6 px
-- up, never across; south never moves, a bad row is skipped, the Float option leaves them
local nWings = 0
for _ in pairs(P.lifts) do nWings = nWings + 1 end
ok(type(P.shifts) == 'table' and #P.shifts >= 2 * nWings and #P.shifts <= 3 * nWings,
  'a north, an east and a west move per pack wing (a row of no move left out): ' .. tostring(P.shifts and #P.shifts))
local wingLooks = {}
for look in pairs(P.lifts) do wingLooks[look] = true end
local turned = {}
local ns = C.applyShifts(P, function(look, d, dx, dy) turned[#turned + 1] = { look, d, dx, dy } end)
ok(ns == #P.shifts and #turned == #P.shifts, 'every row handed in: ' .. ns)
local pearl, perDir = {}, { [0] = 0, 0, 0, 0 }
for _, t in ipairs(turned) do
  ok(wingLooks[t[1]], 'a moved look is a pack wing ' .. t[1])
  perDir[t[2]] = perDir[t[2]] + 1
  if t[2] == 0 then
    ok(t[4] <= -8 and t[4] >= -13 and t[3] >= 2 and t[3] <= 5, 'north up 8-13 px, right 2-5 px: ' .. t[1] .. ' ' .. t[3] .. ' ' .. t[4])
  elseif t[2] == 1 then
    ok(t[3] == 0 and t[4] <= -5 and t[4] >= -10, 'east up 5-10 px, not across: ' .. t[1] .. ' ' .. t[3] .. ' ' .. t[4])
  else
    ok(t[2] == 3 and t[3] == 0 and t[4] <= -1 and t[4] >= -6, 'west up 1-6 px, not across: ' .. t[1] .. ' ' .. t[2] .. ' ' .. t[4])
  end
  if t[1] == 2442 then pearl[t[2]] = t end
end
ok(perDir[0] == nWings and perDir[1] == nWings and perDir[2] == 0, 'every wing north and east, none south')
ok(pearl[0] and pearl[0][3] == 2 and pearl[0][4] == -9, 'Pearl Scallop Wings 2442: 2 right, 9 up facing north (it hung 9.2 px low)')
ok(pearl[1] and pearl[1][4] < 0 and pearl[3] and pearl[3][4] < 0, 'Pearl Scallop Wings 2442: up facing east and west')

-- O784 (base patch 0218): the rows grouped by look as "nx ny ex ey sx sy wx wy", one call per pack wing
local texts = {}
local nl2 = C.applyShiftTexts(P, function(look, text) texts[#texts + 1] = { look, text } end)
ok(nl2 == nWings and #texts == nWings, 'one text per pack wing: ' .. nl2)
for _, t in ipairs(texts) do
  local v = {}
  for n in t[2]:gmatch('%-?%d+') do v[#v + 1] = tonumber(n) end
  ok(#v == 8 and v[5] == 0 and v[6] == 0 and v[3] == 0 and v[7] == 0, 'eight numbers, south still, no side move across: ' .. t[2])
  if t[1] == 2442 then
    ok(v[1] == pearl[0][3] and v[2] == pearl[0][4] and v[4] == pearl[1][4] and v[8] == pearl[3][4], 'Pearl text = its rows ' .. t[2])
  end
end
-- a later row wins, a direction without a row is 0 0, bad rows skipped, looks in first-row order
local got = {}
C.applyShiftTexts({ shifts = { { 9, 0, 1, -9 }, { 4, 3, 0, -2 }, { 9, 1, 0, -5 }, { 9, 1, 0, -6 }, { 9, 4, 0, 1 }, { 0, 1, 0, 1 }, 'x' } },
  function(look, text) got[#got + 1] = look .. ':' .. text end)
ok(#got == 2 and got[1] == '9:1 -9 0 -6 0 0 0 0' and got[2] == '4:0 0 0 0 0 0 0 -2', 'grouped texts: ' .. table.concat(got, ' | '))
ok(C.applyShiftTexts(nil, error) == 0 and C.applyShiftTexts({ pieces = {} }, error) == 0, 'no shifts: no text')
-- an old table of O779 (north rows only) still loads, both ways
local old = { shifts = { { 2442, 0, 2, -9 }, { 2390, 0, 3, -12 } } }
local oldRows, oldTexts = {}, {}
ok(C.applyShifts(old, function(l, d, x, y) oldRows[#oldRows + 1] = { l, d, x, y } end) == 2 and oldRows[2][4] == -12, 'O779 rows load')
ok(C.applyShiftTexts(old, function(l, t) oldTexts[l] = t end) == 2 and oldTexts[2442] == '2 -9 0 0 0 0 0 0', 'O779 rows as texts')
local good = 0
ns = C.applyShifts({ shifts = { { 5, 0, 1, -9 }, { 0, 0, 1, 1 }, { 6, 4, 0, 1 }, { 7, 0, 0.5, 1 }, { 8, 0, 0, -25 }, { 9, 2 }, 'x' } },
  function(look) good = good + 1; ok(look == 5, 'only the good row ' .. look) end)
ok(ns == 1 and good == 1, 'bad shift rows skipped')
ok(C.applyShifts(nil, error) == 0 and C.applyShifts({ pieces = {} }, error) == 0, 'no shifts: nothing')

-- O785 (base patch 0219): the head pieces and capes moved onto the body's head or back (pack_wear_layer_shift.csv, pair 90,
-- against the median class body): wearShifts, the same rows, other looks than the wings; a head moves both ways in every
-- direction, a cape both ways facing north and only in height facing east or west; south never moves
local headLooks, capeLooks = {}, {}
for _, h in ipairs(P.heads) do headLooks[h.look] = true end
for _, c in ipairs(P.capes) do capeLooks[c.look] = true end
ok(type(P.wearShifts) == 'table' and #P.wearShifts > 0 and #P.wearShifts <= 3 * (#P.heads + #P.capes),
  'up to a north, an east and a west move per head piece and cape: ' .. tostring(P.wearShifts and #P.wearShifts))
local worn = {}
local nw = C.applyShifts(P, function(look, d, dx, dy) worn[#worn + 1] = { look, d, dx, dy } end, 'wearShifts')
ok(nw == #P.wearShifts and #worn == nw, 'every wear row handed in: ' .. nw)
local horns, train = {}, {}
for _, t in ipairs(worn) do
  ok((headLooks[t[1]] or capeLooks[t[1]]) and not wingLooks[t[1]], 'a moved look is a head piece or a cape ' .. t[1])
  ok(t[2] ~= 2, 'south never moves: ' .. t[1])
  if capeLooks[t[1]] and t[2] ~= 0 then ok(t[3] == 0, 'a cape facing east or west moves in height only: ' .. t[1]) end
  if t[1] == 3590 then horns[t[2]] = t end
  if t[1] == 3697 then train[t[2]] = t end
end
ok(horns[0] and horns[0][3] == 1 and horns[0][4] == -3, 'Antelope Horns 3590 facing north: 1 right, 3 up (it sat 2.8 px low)')
ok(train[0] and train[0][4] == -20 and train[1] and train[1][4] == -9, 'Mermaid Scale Train 3697: 20 up facing north, 9 facing east')
local wtexts = {}
local nwl = C.applyShiftTexts(P, function(look, text) wtexts[look] = text end, 'wearShifts')
ok(nwl == #P.heads + #P.capes, 'one text per head piece and cape (every one sat more than 1 px off): ' .. nwl)
ok(wtexts[3590] == '1 -3 3 -5 0 0 0 -2', 'Antelope Horns text: ' .. tostring(wtexts[3590]))
-- the wings rows are not touched by the field, and an old table without wearShifts hands in nothing
ok(C.applyShifts(P, function() end) == #P.shifts, 'the default field is still the wings shifts')
ok(C.applyShiftTexts({ shifts = { { 2442, 0, 2, -9 } } }, error, 'wearShifts') == 0, 'a table without wearShifts: nothing')

if fails > 0 then os.exit(1) end
print('wingfit_core_test: all checks passed')
