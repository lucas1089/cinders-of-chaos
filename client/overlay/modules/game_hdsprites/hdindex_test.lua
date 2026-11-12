-- run from the repo root: luajit client/overlay/modules/game_hdsprites/hdindex_test.lua (and lua5.3)
dofile('client/overlay/modules/game_hdsprites/hdindex.lua')
local I = HdIndex

local function eq(a, b, what)
  if a ~= b then error(what .. ': expected ' .. tostring(b) .. ', got ' .. tostring(a), 2) end
end

-- a good file: comment, CRLF, blank line, two atlases, a 4x tile, the largest id
local good = '# made by gen_hd_overlay.py\nchaos-hd-overlay 1\r\n\natlas 0 hd_2x_0.png\natlas 1 hd_4x_0.png\n'
  .. 'sprite 815931 0 0 0 2 deadbeef\nsprite 815932 0 64 0 2 00000000\nsprite 4294967295 1 128 64 4 0000ABCD\n'
  .. 'slot 1 3019 57 0 0 192 0 2\nslot 1 3019 58 815931 1 0 64 4\n'
local idx, err = I.parse(good)
assert(idx, err)
eq(#idx.atlases, 2, 'atlases')
eq(idx.atlases[2], 'hd_4x_0.png', 'second atlas')
eq(idx.count, 3, 'sprites')
eq(idx.sprites[815931].crc, 0xDEADBEEF, 'crc')
eq(idx.sprites[815932].x, 64, 'x')
eq(idx.sprites[4294967295].scale, 4, 'scale 4')
eq(idx.sprites[4294967295].atlas, 1, 'atlas 1')
eq(idx.sprites[4294967295].crc, 0xABCD, 'upper case hex')
eq(idx.slotCount, 2, 'slots')
eq(idx.slots['1:3019:57'].sprite, 0, 'slot of a place with no sprite')
eq(idx.slots['1:3019:57'].x, 192, 'slot x')
eq(idx.slots['1:3019:58'].sprite, 815931, 'slot sprite')
eq(idx.slots['1:3019:58'].scale, 4, 'slot scale')
assert(idx.slots['1:3019:59'] == nil and idx.slots['2:3019:57'] == nil, 'other places have no slot')
local ids = I.ids(idx)
eq(#ids, 3, 'ids')
eq(ids[1], 815931, 'sorted ids')
eq(ids[3], 4294967295, 'sorted ids, last')

-- an atlas nobody uses is not needed
local one = assert(I.parse('chaos-hd-overlay 1\natlas 0 a.png\natlas 1 b.png\nsprite 5 1 0 0 2 00000000\n'))
local used = I.usedAtlases(one)
eq(#used, 1, 'one atlas used')
eq(used[1], 'b.png', 'the one that is used')

-- a repeated id: the later line wins and counts once
local twice = assert(I.parse('chaos-hd-overlay 1\natlas 0 a.png\nsprite 5 0 0 0 2 00000001\nsprite 5 0 64 0 2 00000002\n'))
eq(twice.count, 1, 'repeated id counts once')
eq(twice.sprites[5].x, 64, 'later line wins')

-- bad files, each refused with a line number
local bad = {
  '',
  '# comment only\n',
  'chaos-hd-overlay 2\n',
  'atlas 0 a.png\n',
  'chaos-hd-overlay 1\natlas 1 a.png\n',
  'chaos-hd-overlay 1\natlas 0 ../a.png\n',
  'chaos-hd-overlay 1\natlas 0 sub/a.png\n',
  'chaos-hd-overlay 1\natlas 0 .hidden.png\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 1 0 0 2 00000000\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nsprite 0 0 0 0 2 00000000\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 0 0 0 0 00000000\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 0 0 0 9 00000000\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 0 0 0 2 0\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 0 0 0 2 0000000g\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nsprite -1 0 0 0 2 00000000\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 0 70000 0 2 00000000\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 0 0 0 2\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 0 0 0 2 00000000 x\n',
  'chaos-hd-overlay 1\nwhat 1\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nslot 1 5 0 0 1 0 0 2\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nslot 4 5 0 0 0 0 0 2\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nslot 1 0 0 0 0 0 0 2\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nslot 1 5 70000 0 0 0 0 2\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nslot 1 5 0 0 0 0 0 0\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nslot 1 5 0 0 0 0 0\n',
  'chaos-hd-overlay 1\natlas 0 a.png\nslot 1 5 0 0 0 0 0 2 1\n',
}
for i, text in ipairs(bad) do
  local r = I.parse(text)
  assert(r == nil, 'bad index ' .. i .. ' was accepted')
end
local _, why = I.parse('chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 0 0 0 2 00000000\nsprite x\n')
assert(why and why:find('^line 4'), 'the error names the line: ' .. tostring(why))

-- the shipped index: parses, every atlas it uses is a file next to it, every tile lies inside the 2048 px atlas
local f = io.open('client/overlay/data/hd/index.txt', 'rb')
assert(f, 'client/overlay/data/hd/index.txt is missing')
local text = f:read('*a')
f:close()
local shipped, e2 = I.parse(text)
assert(shipped, 'shipped index: ' .. tostring(e2))
assert(shipped.count + shipped.slotCount > 0, 'shipped index maps nothing')
for _, name in ipairs(I.usedAtlases(shipped)) do
  local af = io.open('client/overlay/data/hd/' .. name, 'rb')
  assert(af, 'atlas ' .. name .. ' is missing')
  local head = af:read(8)
  af:close()
  assert(head == '\137PNG\r\n\26\n', name .. ' is not a PNG')
end
local function onGrid(what, e)
  local size = I.BASE * e.scale
  assert(e.x + size <= 2048 and e.y + size <= 2048, what .. ' tile leaves the atlas')
  assert(e.x % size == 0 and e.y % size == 0, what .. ' tile is not on the atlas grid')
end
for id, e in pairs(shipped.sprites) do onGrid('sprite ' .. id, e) end
for key, e in pairs(shipped.slots) do onGrid('slot ' .. key, e) end

print('hdindex_test: ok')
