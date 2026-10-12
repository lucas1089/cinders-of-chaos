-- luajit qrcode_test.lua && lua5.3 qrcode_test.lua (from the repo root or this folder)
-- The QR encoder of the donation window. Its output was checked against an independent encoder and decoder
-- (OpenCV 5: the same matrix for 36 of the 40 versions at the same mask, every version decoded); the fingerprints
-- below pin those results.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'qrcode.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local Q = ChaosQR

-- the block table of level M fills every version exactly
for v = 1, 40 do
  local b = Q.BLOCKS[v]
  eq(b[2] * (b[3] + b[1]) + b[4] * (b[5] + b[1]), math.floor(Q.rawModules(v) / 8), 'codewords of version ' .. v)
end
eq(Q.dataCodewords(1), 16, 'v1 data'); eq(Q.dataCodewords(10), 216, 'v10 data'); eq(Q.dataCodewords(40), 2334, 'v40 data')
-- format and version information (tables of the standard)
eq(Q.formatBits(0), 0x5412, 'format M mask 0'); eq(Q.formatBits(7), 0x4AA0, 'format M mask 7')
eq(Q.versionBits(7), 0x07C94, 'version 7'); eq(Q.versionBits(40), 0x28C69, 'version 40')
local al = Q.alignment(32)
eq(table.concat(al, ','), '6,34,60,86,112,138', 'alignment v32'); eq(table.concat(Q.alignment(7), ','), '6,22,38', 'alignment v7')

local function fingerprint(q)
  local h = 0
  for y = 1, q.size do
    for x = 1, q.size do h = (h * 31 + (q.modules[y][x] and 1 or 0) + x) % 2147483647 end
  end
  return h
end
local q = Q.encode('HELLO WORLD')
eq(q.size, 21, 'v1 size'); eq(q.version, 1, 'v1')
-- finder pattern corners
eq(q.modules[1][1], true, 'top left dark'); eq(q.modules[2][2], nil, 'ring light'); eq(q.modules[3][3], true, 'centre dark')
local pix = '00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865406123.455802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D'
q = Q.encode(pix)
eq(q.version, 8, 'a Pix code fits version 8'); eq(q.size, 49, 'v8 size')
eq(Q.encode(string.rep('x', 2334 - 3)).version, 40, 'largest'); eq(Q.encode(string.rep('x', 2334 - 2)), nil, 'too long')
local runs = Q.runs({ size = 4, modules = { { true, true, nil, true }, {}, { nil, true, true, true }, {} } })
eq(#runs, 3, 'runs'); eq(runs[1][3], 2, 'first run'); eq(runs[3][2], 2, 'third run starts at 2'); eq(runs[3][3], 3, 'third run length')
eq(fingerprint(Q.encode('HELLO WORLD')), 1675976102, 'HELLO WORLD matrix'); eq(Q.encode('HELLO WORLD').mask, 4, 'HELLO WORLD mask')
eq(fingerprint(q), 1566823748, 'Pix code matrix'); eq(q.mask, 2, 'Pix code mask')
if fails > 0 then print(fails .. ' failure(s)'); os.exit(1) end
print('qrcode_test: ok')
