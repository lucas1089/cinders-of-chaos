-- Run from the repo root: luajit client/overlay/modules/game_telegraph/telegraph_test.lua (and lua5.3)
-- Covers the pure rules (telegraph_logic.lua): the message and its limits, the outline of the union of the tiles (a tile, a bar,
-- a block, an L, a ring, two marks that overlap), the marks alive (replace, caps, clear, expiry at the hit), the fill that brightens
-- in the last 0.4 s, the colours, the layout of several marks on one floor, the widget's box and the line's width at any zoom.
local dir = arg[0]:match('^(.*)/[^/]*$') or '.'
dofile(dir .. '/telegraph_logic.lua')
local L = TelegraphLogic

local fails, checks = 0, 0
local function eq(a, b, msg)
  checks = checks + 1
  if a ~= b then
    fails = fails + 1
    print('FAIL ' .. msg .. ': got ' .. tostring(a) .. ', want ' .. tostring(b))
  end
end

-- ---------------------------------------------------------------- the opcode and the hello
eq(L.OPCODE, 125, 'the monster bar opcode (server ChaosOpcodes.monsterbar)')
eq(L.hello().action, 'floorhello', 'hello action'); eq(L.hello().data.v, 1, 'hello version')

-- ---------------------------------------------------------------- the message
local function sq(w, h)
  local t = {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do t[#t + 1] = { x, y } end
  end
  return t
end
local a = L.parse({ id = 'bm:1:1', z = 7, x0 = 100, y0 = 200, t = sq(3, 2), c = 'orange', ms = 2000 }, 5000)
eq(a ~= nil, true, 'a good message parses')
eq(#a.tiles, 6, 'six tiles'); eq(a.tiles[1].x .. ',' .. a.tiles[1].y, '100,200', 'first tile is the origin')
eq(a.tiles[6].x .. ',' .. a.tiles[6].y, '102,201', 'last tile'); eq(a.hitAt, 7000, 'hit time'); eq(a.z, 7, 'floor'); eq(a.color, 'orange', 'colour')
eq(a.set['101,200'], true, 'the set')
eq(L.parse({ id = 'x', z = 7, x0 = 1, y0 = 1, t = { { 0, 0 }, { 0, 0 }, { 1, 0 } }, ms = 1000 }, 0).tiles[2].x, 2, 'a tile twice counts once')
eq(L.parse({ id = 'x', z = 7, x0 = 1, y0 = 1, t = sq(1, 1), ms = 1000, c = 'pink' }, 0).color, 'orange', 'an unknown colour is orange')
eq(L.parse({ id = 'x', z = 7, x0 = 1, y0 = 1, t = sq(1, 1), ms = 10 }, 0).ms, L.MIN_MS, 'a time under the minimum is raised')
eq(L.parse({ id = 'x', z = 7, x0 = 1, y0 = 1, t = sq(1, 1), ms = 10 ^ 9 }, 0).ms, L.MAX_MS, 'a time over the maximum is cut')
local function bad(data, why)
  local r, reason = L.parse(data, 0)
  eq(r, nil, 'refused: ' .. why)
  return reason
end
bad(nil, 'no data'); bad('x', 'a string'); bad({ z = 7, x0 = 1, y0 = 1, t = sq(1, 1), ms = 1000 }, 'no id')
bad({ id = '', z = 7, x0 = 1, y0 = 1, t = sq(1, 1), ms = 1000 }, 'empty id')
bad({ id = string.rep('a', 65), z = 7, x0 = 1, y0 = 1, t = sq(1, 1), ms = 1000 }, 'long id')
bad({ id = 'x', z = 16, x0 = 1, y0 = 1, t = sq(1, 1), ms = 1000 }, 'floor 16'); bad({ id = 'x', z = -1, x0 = 1, y0 = 1, t = sq(1, 1), ms = 1000 }, 'floor -1')
bad({ id = 'x', z = 7, x0 = -1, y0 = 1, t = sq(1, 1), ms = 1000 }, 'negative origin'); bad({ id = 'x', z = 7, x0 = 70000, y0 = 1, t = sq(1, 1), ms = 1000 }, 'origin too far')
bad({ id = 'x', z = 7, x0 = 1, y0 = 1, t = sq(1, 1) }, 'no time'); bad({ id = 'x', z = 7, x0 = 1, y0 = 1, t = sq(1, 1), ms = 'soon' }, 'a time that is no number')
bad({ id = 'x', z = 7, x0 = 1, y0 = 1, ms = 1000 }, 'no tiles'); bad({ id = 'x', z = 7, x0 = 1, y0 = 1, t = {}, ms = 1000 }, 'an empty list')
bad({ id = 'x', z = 7, x0 = 1, y0 = 1, t = { 5 }, ms = 1000 }, 'a tile that is no pair'); bad({ id = 'x', z = 7, x0 = 1, y0 = 1, t = { { 0 } }, ms = 1000 }, 'half a pair')
bad({ id = 'x', z = 7, x0 = 1, y0 = 1, t = { { -1, 0 } }, ms = 1000 }, 'a negative offset'); bad({ id = 'x', z = 7, x0 = 1, y0 = 1, t = { { 256, 0 } }, ms = 1000 }, 'an offset over 255')
bad({ id = 'x', z = 7, x0 = 1, y0 = 1, t = { { 0 / 0, 0 } }, ms = 1000 }, 'nan')
eq(L.parse({ id = 'x', z = 7, x0 = 1, y0 = 1, t = sq(20, 15), ms = 1000 }, 0) ~= nil, true, '300 tiles are the limit')
eq(bad({ id = 'x', z = 7, x0 = 1, y0 = 1, t = sq(20, 16), ms = 1000 }, '320 tiles'), 'too many tiles', 'more than 300 tiles: refused whole, not cut')
eq(L.parseClear({ id = 'bm:1:1' }), 'bm:1:1', 'a clear of one mark'); eq(L.parseClear({}), 'all', 'a clear without id: all'); eq(L.parseClear(nil), 'all', 'no data: all')
eq(L.parseClear({ id = 5 }), nil, 'a clear with a bad id'); eq(L.parseClear('x'), nil, 'junk clear')

-- ---------------------------------------------------------------- the outline of the union
local function setOf(list)
  local s = {}
  for _, t in ipairs(list) do s[L.tileKey(t[1], t[2])] = true end
  return s
end
local one = setOf({ { 5, 5 } })
eq(L.edgeMask(one, 5, 5), 15, 'one tile: four sides')
local bar = setOf({ { 5, 5 }, { 6, 5 }, { 7, 5 } })
eq(L.edgeMask(bar, 5, 5), 1 + 4 + 8, 'a bar: left end'); eq(L.edgeMask(bar, 6, 5), 1 + 4, 'a bar: the middle has no side lines'); eq(L.edgeMask(bar, 7, 5), 1 + 2 + 4, 'a bar: right end')
local block = setOf(sq(3, 3))
eq(L.edgeMask(block, 1, 1), 0, 'a block: the middle tile has no line'); eq(L.edgeMask(block, 0, 0), 1 + 8, 'a block: top left corner')
eq(L.edgeMask(block, 2, 2), 2 + 4, 'a block: bottom right corner'); eq(L.edgeMask(block, 1, 0), 1, 'a block: top edge')
eq(L.edgeMask(block, 2, 1), 2, 'a block: right edge'); eq(L.edgeMask(block, 1, 2), 4, 'a block: bottom edge'); eq(L.edgeMask(block, 0, 1), 8, 'a block: left edge')
local ell = setOf({ { 0, 0 }, { 1, 0 }, { 0, 1 } })
eq(L.edgeMask(ell, 0, 0), 1 + 8, 'an L: the corner'); eq(L.edgeMask(ell, 1, 0), 1 + 2 + 4, 'an L: the arm to the right'); eq(L.edgeMask(ell, 0, 1), 2 + 4 + 8, 'an L: the arm down')
local ringT = {}
for _, t in ipairs(sq(3, 3)) do
  if not (t[1] == 1 and t[2] == 1) then ringT[#ringT + 1] = t end
end
local ring = setOf(ringT)
eq(L.edgeMask(ring, 1, 0), 1 + 4, 'a ring: the top tile has a line on the hole side too'); eq(L.edgeMask(ring, 0, 0), 1 + 4 * 0 + 8 + 2 * 0 + 0, 'a ring: the corner has up and left only')
-- the sides of a mask
local function sides(m)
  local u, r, d, l = L.sides(m)
  return (u and 'U' or '-') .. (r and 'R' or '-') .. (d and 'D' or '-') .. (l and 'L' or '-')
end
eq(sides(0), '----', 'sides 0'); eq(sides(15), 'URDL', 'sides 15'); eq(sides(1), 'U---', 'up'); eq(sides(2), '-R--', 'right'); eq(sides(4), '--D-', 'down'); eq(sides(8), '---L', 'left')
eq(sides(1 + 8), 'U--L', 'up and left'); eq(sides(2 + 4), '-RD-', 'right and down'); eq(sides(nil), '----', 'no mask')
-- every one of the 16 masks round-trips through its sides
for m = 0, 15 do
  local u, r, d, l = L.sides(m)
  eq((u and 1 or 0) + (r and 2 or 0) + (d and 4 or 0) + (l and 8 or 0), m, 'mask ' .. m .. ' round trip')
end

-- ---------------------------------------------------------------- the marks alive
local st = L.newState()
local function mk(id, x0, y0, w, h, ms, now, color, z)
  return L.parse({ id = id, z = z or 7, x0 = x0, y0 = y0, t = sq(w, h), ms = ms, c = color }, now)
end
eq(#L.add(st, mk('a', 10, 10, 3, 3, 2000, 0)), 0, 'add: nothing goes'); eq(L.count(st), 1, 'one mark')
L.add(st, mk('a', 20, 20, 2, 2, 2000, 0)); eq(L.count(st), 1, 'the same id replaces the mark'); eq(st.areas.a.tiles[1].x, 20, 'the new area')
L.add(st, mk('b', 30, 30, 2, 2, 1000, 0)); eq(L.count(st), 2, 'two marks')
eq(#L.step(st, 999), 0, 'before the hit nothing goes'); eq(L.step(st, 1000)[1], 'b', 'at the hit b goes'); eq(L.count(st), 1, 'a is left')
eq(L.clear(st, 'zzz')[1], nil, 'a clear of an unknown id does nothing'); eq(L.clear(st, 'a')[1], 'a', 'clear a'); eq(L.count(st), 0, 'none left')
L.add(st, mk('a', 1, 1, 1, 1, 2000, 0)); L.add(st, mk('b', 3, 3, 1, 1, 2000, 0)); eq(#L.clear(st, 'all'), 2, 'clear all'); eq(L.count(st), 0, 'nothing left')
-- the caps: marks
st = L.newState()
for i = 1, L.MAX_AREAS + 3 do L.add(st, mk('m' .. i, i, 1, 1, 1, 2000, 0)) end
eq(L.count(st), L.MAX_AREAS, 'at most MAX_AREAS marks'); eq(st.areas.m1, nil, 'the oldest went'); eq(st.areas['m' .. (L.MAX_AREAS + 3)] ~= nil, true, 'the newest stays')
-- the caps: tiles of all the marks together
st = L.newState()
for i = 1, 4 do L.add(st, mk('t' .. i, i * 40, 1, 20, 15, 2000, 0)) end -- 4 x 300 = 1200 > 900
eq(L.count(st), 3, 'the oldest mark goes while the tiles of all marks are over MAX_TOTAL'); eq(st.areas.t1, nil, 'the oldest')
-- a lone mark over the total cap stays (it is within MAX_TILES)
eq(L.count(L.newState()), 0, 'empty state')
-- the safety expiry: a mark whose clock was moved far back is dropped too
st = L.newState()
L.add(st, mk('s', 1, 1, 1, 1, 2000, 100000))
eq(L.expired(st.areas.s, 100000), false, 'new'); eq(L.expired(st.areas.s, 102000), true, 'at the hit'); eq(L.expired(st.areas.s, 99999), false, 'a clock a little back')
eq(#L.step(st, 100500), 0, 'alive in between'); eq(#L.step(st, 102000), 1, 'gone at the hit')

-- ---------------------------------------------------------------- the fill
eq(L.fillAlpha(5000, 0), L.FILL_ALPHA, 'flat long before the hit'); eq(L.fillAlpha(5000, 4599), L.FILL_ALPHA, 'still flat 401 ms before')
eq(L.fillAlpha(5000, 4600), L.FILL_ALPHA, 'flat exactly 400 ms before'); eq(L.fillAlpha(5000, 5000), L.FILL_BRIGHT, 'brightest at the hit'); eq(L.fillAlpha(5000, 6000), L.FILL_BRIGHT, 'and after')
local mid = L.fillAlpha(5000, 4800)
eq(math.abs(mid - (L.FILL_ALPHA + L.FILL_BRIGHT) / 2) < 1e-9, true, 'halfway at 200 ms before')
eq(L.fillAlpha(5000, 4700) < L.fillAlpha(5000, 4900), true, 'rising')
eq(L.FILL_ALPHA >= 0.35 and L.FILL_ALPHA <= 0.40, true, 'the flat fill is 35 to 40 percent'); eq(L.FILL_BRIGHT > L.FILL_ALPHA and L.FILL_BRIGHT < 0.7, true, 'a slight brightening')
eq(L.BRIGHT_MS, 400, 'the last 0.4 s')
eq(L.alphaStep(L.FILL_ALPHA), 12, 'the step of the flat fill'); eq(L.alphaStep(L.FILL_BRIGHT), 18, 'the step of the bright fill')
eq(L.alphaStep(L.fillAlpha(5000, 4600)), L.alphaStep(L.fillAlpha(5000, 0)), 'no widget update before the brightening starts')

-- ---------------------------------------------------------------- colours
eq(L.fillColor('orange', 0.38), '#ff7a1e61', 'the orange fill: ff7a1e at 38 percent'); eq(L.lineColor('orange'), '#ff8c28ff', 'the orange line: ff8c28 at full alpha')
eq(L.fillColor(nil, 0.5), '#ff7a1e80', 'no key: orange'); eq(L.fillColor('pink', 0.5), '#ff7a1e80', 'an unknown key: orange'); eq(L.lineColor('pink'), '#ff8c28ff', 'an unknown line key')
eq(#L.fillColor('violet', 1), 9, 'a colour is #rrggbbaa'); eq(L.fillColor('red', 0), '#ff3a2400', 'alpha 0'); eq(L.fillColor('red', 2), '#ff3a24ff', 'alpha over 1 is cut')
for key in pairs(L.COLORS) do
  eq(#L.COLORS[key][1], 6, key .. ' fill is 6 hex'); eq(#L.COLORS[key][2], 6, key .. ' line is 6 hex'); eq(L.colorKey(key), key, key .. ' is a key')
end

-- ---------------------------------------------------------------- the layout of the marks on a floor
st = L.newState()
L.add(st, mk('c1', 10, 10, 3, 3, 3000, 0))
local cells = L.layout(st, 7)
eq(#cells, 9, 'nine cells'); eq(cells[1].x .. ',' .. cells[1].y, '10,10', 'sorted by row then column'); eq(cells[1].mask, 1 + 8, 'the corner')
local function maskAt(list, x, y)
  for _, c in ipairs(list) do
    if c.x == x and c.y == y then return c.mask end
  end
  return nil
end
eq(maskAt(cells, 11, 11), 0, 'the middle has no line'); eq(#L.layout(st, 6), 0, 'a mark of another floor draws nothing')
-- two marks that touch: one outline (no line between them)
L.add(st, mk('c2', 13, 10, 3, 3, 2000, 0))
cells = L.layout(st, 7)
eq(#cells, 18, 'two blocks side by side: 18 cells'); eq(maskAt(cells, 12, 10), 1, 'the seam: only the top line'); eq(maskAt(cells, 13, 10), 1, 'the other side of the seam: only the top line')
eq(maskAt(cells, 12, 11), 0, 'the seam in the middle: no line'); eq(maskAt(cells, 10, 11), 8, 'the outer left edge'); eq(maskAt(cells, 15, 11), 2, 'the outer right edge')
-- an overlap draws the shared tiles once
L.add(st, mk('c3', 12, 10, 2, 3, 1000, 0, 'red'))
cells = L.layout(st, 7)
eq(#cells, 18, 'an overlap adds no tile'); eq(maskAt(cells, 12, 11), 0, 'the overlap is inside the union')
-- the colour and the hit of the mark that hits first
local function cellAt(list, x, y)
  for _, c in ipairs(list) do
    if c.x == x and c.y == y then return c end
  end
end
eq(cellAt(cells, 12, 11).color, 'red', 'the most urgent mark colours the shared tile'); eq(cellAt(cells, 12, 11).hitAt, 1000, 'and times it')
eq(cellAt(cells, 10, 10).color, 'orange', 'a tile of one mark only keeps its colour'); eq(cellAt(cells, 10, 10).hitAt, 3000, 'and its time')
L.clear(st, 'c3'); L.clear(st, 'c2'); L.clear(st, 'c1'); eq(#L.layout(st, 7), 0, 'cleared: nothing is drawn')

-- ---------------------------------------------------------------- the widget and the line
local size, ml, mt = L.box(32)
eq(size, 32, 'one tile'); eq(ml, -16, 'margin: half a sprite back'); eq(mt, -16, 'the same up')
size, ml = L.box(64); eq(size, 64, 'a 64 px sprite'); eq(ml, -32, 'its margin')
size = L.box(nil); eq(size, 32, 'no size: 32')
eq(L.lineWidth(32, 32), 2, 'tiles at their own size: 2 map px = 2 screen px'); eq(L.lineWidth(64, 32), 1, 'double size: 1 map px = 2 screen px')
eq(L.lineWidth(145, 32), 1, 'a big zoom: never under one map pixel'); eq(L.lineWidth(24, 32), 3, 'zoomed out a little: 3 map px'); eq(L.lineWidth(8, 32), 3, 'zoomed out a lot: at most 3')
eq(L.lineWidth(nil, 32), 2, 'no size known: 2'); eq(L.lineWidth(0, 32), 2, 'zero: 2'); eq(L.lineWidth(-5, 32), 2, 'negative: 2')
for _, px in ipairs({ 16, 24, 32, 40, 48, 64, 96, 128 }) do
  local w = L.lineWidth(px, 32)
  eq(w >= 1 and w <= 3, true, 'the line is 1 to 3 map px at ' .. px .. ' px a tile')
  local onScreen = w * px / 32
  eq(onScreen >= 1 and onScreen <= 4.5, true, 'and about 2 screen px (' .. onScreen .. ') at ' .. px .. ' px a tile')
end

if fails > 0 then
  print(string.format('telegraph_test: %d of %d checks failed', fails, checks))
  os.exit(1)
end
print(string.format('telegraph_test: all %d checks passed', checks))
