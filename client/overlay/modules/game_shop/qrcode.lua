-- qrcode.lua: a QR code encoder in plain Lua (ISO/IEC 18004, byte mode, error correction level M, versions 1-40,
-- the mask with the lowest penalty). Used by the donation window to draw the Pix code and the PayPal link; pure
-- logic, tested by qrcode_test.lua. Lua 5.1 / LuaJIT / Lua 5.3, no bit library: the few bit operations are done
-- with arithmetic on small integers.
--
--   ChaosQR.encode(text) -> {size = n, modules = {[y][x] = true for dark}} or nil, reason   (x, y from 1)
--   ChaosQR.runs(qr)     -> {{y, x, len}} the dark runs of each row (one widget per run when drawing)

ChaosQR = {}
local Q = ChaosQR

-- ------------------------------------------------------------------ small bit helpers
local function bxor(a, b)
  local r, p = 0, 1
  while a > 0 or b > 0 do
    local x, y = a % 2, b % 2
    if x ~= y then r = r + p end
    a, b, p = (a - x) / 2, (b - y) / 2, p * 2
  end
  return r
end

local function bit(x, i) -- bit i (0 = lowest) of x
  return math.floor(x / 2 ^ i) % 2 == 1
end

-- ------------------------------------------------------------------ GF(256), polynomial 0x11D
local EXP, LOG = {}, {}
do
  local x = 1
  for i = 0, 254 do
    EXP[i] = x
    LOG[x] = i
    x = x * 2
    if x >= 256 then x = bxor(x, 0x11D) end
  end
  for i = 255, 511 do EXP[i] = EXP[i - 255] end
end

local XOR8 = {}
for a = 0, 255 do
  local row = {}
  for b = 0, 255 do row[b] = bxor(a, b) end
  XOR8[a] = row
end

local function gmul(a, b)
  if a == 0 or b == 0 then return 0 end
  return EXP[LOG[a] + LOG[b]]
end

-- generator polynomial of the given degree, coefficients highest first without the leading 1
local GEN = {}
local function generator(degree)
  if GEN[degree] then return GEN[degree] end
  local poly = {}
  for i = 1, degree - 1 do poly[i] = 0 end
  poly[degree] = 1
  local root = 1
  for _ = 1, degree do
    for j = 1, degree do
      poly[j] = gmul(poly[j], root)
      if j < degree then poly[j] = XOR8[poly[j]][poly[j + 1]] end
    end
    root = gmul(root, 2)
  end
  GEN[degree] = poly
  return poly
end

local function ecc(data, degree)
  local gen = generator(degree)
  local res = {}
  for i = 1, degree do res[i] = 0 end
  for _, b in ipairs(data) do
    local factor = XOR8[b][res[1]]
    table.remove(res, 1)
    res[degree] = 0
    for i = 1, degree do res[i] = XOR8[res[i]][gmul(gen[i], factor)] end
  end
  return res
end

-- ------------------------------------------------------------------ level M: ec codewords per block, blocks and data
-- codewords of group 1, blocks and data codewords of group 2, per version
local BLOCKS = {
  {10, 1, 16, 0, 0}, {16, 1, 28, 0, 0}, {26, 1, 44, 0, 0}, {18, 2, 32, 0, 0}, {24, 2, 43, 0, 0},
  {16, 4, 27, 0, 0}, {18, 4, 31, 0, 0}, {22, 2, 38, 2, 39}, {22, 3, 36, 2, 37}, {26, 4, 43, 1, 44},
  {30, 1, 50, 4, 51}, {22, 6, 36, 2, 37}, {22, 8, 37, 1, 38}, {24, 4, 40, 5, 41}, {24, 5, 41, 5, 42},
  {28, 7, 45, 3, 46}, {28, 10, 46, 1, 47}, {26, 9, 43, 4, 44}, {26, 3, 44, 11, 45}, {26, 3, 41, 13, 42},
  {26, 17, 42, 0, 0}, {28, 17, 46, 0, 0}, {28, 4, 47, 14, 48}, {28, 6, 45, 14, 46}, {28, 8, 47, 13, 48},
  {28, 19, 46, 4, 47}, {28, 22, 45, 3, 46}, {28, 3, 45, 23, 46}, {28, 21, 45, 7, 46}, {28, 19, 47, 10, 48},
  {28, 2, 46, 29, 47}, {28, 10, 46, 23, 47}, {28, 14, 46, 21, 47}, {28, 14, 46, 23, 47}, {28, 12, 47, 26, 48},
  {28, 6, 47, 34, 48}, {28, 29, 46, 14, 47}, {28, 13, 46, 32, 47}, {28, 40, 47, 7, 48}, {28, 18, 47, 31, 48}
}
Q.BLOCKS = BLOCKS

function Q.dataCodewords(v)
  local b = BLOCKS[v]
  return b[2] * b[3] + b[4] * b[5]
end

-- modules left for data and error correction once the function patterns are drawn
function Q.rawModules(v)
  local r = (16 * v + 128) * v + 64
  if v >= 2 then
    local n = math.floor(v / 7) + 2
    r = r - (25 * n - 10) * n + 55
    if v >= 7 then r = r - 36 end
  end
  return r
end

local function alignment(v)
  if v == 1 then return {} end
  local n = math.floor(v / 7) + 2
  local step = (v == 32) and 26 or math.ceil((v * 4 + 4) / (n * 2 - 2)) * 2
  local out = {6}
  local pos = v * 4 + 10
  for i = n, 2, -1 do
    table.insert(out, 2, pos)
    pos = pos - step
  end
  return out
end
Q.alignment = alignment

-- ------------------------------------------------------------------ matrix
local function newGrid(size)
  local m, fn = {}, {}
  for y = 0, size - 1 do
    m[y], fn[y] = {}, {}
    for x = 0, size - 1 do m[y][x], fn[y][x] = false, false end
  end
  return m, fn
end

local function setFn(g, x, y, dark)
  g.m[y][x] = dark
  g.fn[y][x] = true
end

local function finder(g, cx, cy)
  for dy = -4, 4 do
    for dx = -4, 4 do
      local x, y = cx + dx, cy + dy
      if x >= 0 and x < g.size and y >= 0 and y < g.size then
        local d = math.max(math.abs(dx), math.abs(dy))
        setFn(g, x, y, d ~= 2 and d ~= 4)
      end
    end
  end
end

local function formatBits(mask)
  local data = 0 * 8 + mask -- level M = 00
  local rem = data
  for _ = 1, 10 do
    rem = rem * 2
    if rem >= 1024 then rem = bxor(rem, 0x537) end
  end
  return bxor(data * 1024 + rem, 0x5412)
end
Q.formatBits = formatBits

local function drawFormat(g, mask)
  local bits = formatBits(mask)
  local s = g.size
  for i = 0, 5 do setFn(g, 8, i, bit(bits, i)) end
  setFn(g, 8, 7, bit(bits, 6))
  setFn(g, 8, 8, bit(bits, 7))
  setFn(g, 7, 8, bit(bits, 8))
  for i = 9, 14 do setFn(g, 14 - i, 8, bit(bits, i)) end
  for i = 0, 7 do setFn(g, s - 1 - i, 8, bit(bits, i)) end
  for i = 8, 14 do setFn(g, 8, s - 15 + i, bit(bits, i)) end
  setFn(g, 8, s - 8, true)
end

local function versionBits(v)
  local rem = v
  for _ = 1, 12 do
    rem = rem * 2
    if rem >= 4096 then rem = bxor(rem, 0x1F25) end
  end
  return v * 4096 + rem
end
Q.versionBits = versionBits

local function drawFunctions(g, v)
  local s = g.size
  for i = 0, s - 1 do
    setFn(g, 6, i, i % 2 == 0)
    setFn(g, i, 6, i % 2 == 0)
  end
  finder(g, 3, 3)
  finder(g, s - 4, 3)
  finder(g, 3, s - 4)
  local al = alignment(v)
  local n = #al
  for i = 1, n do
    for j = 1, n do
      if not ((i == 1 and j == 1) or (i == 1 and j == n) or (i == n and j == 1)) then
        for dy = -2, 2 do
          for dx = -2, 2 do
            setFn(g, al[i] + dx, al[j] + dy, math.max(math.abs(dx), math.abs(dy)) ~= 1)
          end
        end
      end
    end
  end
  drawFormat(g, 0) -- reserved now, written again with the chosen mask
  if v >= 7 then
    local bits = versionBits(v)
    for i = 0, 17 do
      local a, b = s - 11 + i % 3, math.floor(i / 3)
      setFn(g, a, b, bit(bits, i))
      setFn(g, b, a, bit(bits, i))
    end
  end
end

local function placeData(g, codewords)
  local s = g.size
  local total = #codewords * 8
  local i = 0
  local right = s - 1
  while right >= 1 do
    if right == 6 then right = 5 end
    for vert = 0, s - 1 do
      for j = 0, 1 do
        local x = right - j
        local upward = math.floor((right + 1) / 2) % 2 == 0
        local y = upward and (s - 1 - vert) or vert
        if not g.fn[y][x] and i < total then
          local byte = codewords[math.floor(i / 8) + 1]
          g.m[y][x] = bit(byte, 7 - i % 8)
          i = i + 1
        end
      end
    end
    right = right - 2
  end
end

local MASKS = {
  [0] = function(x, y) return (x + y) % 2 == 0 end,
  function(x, y) return y % 2 == 0 end,
  function(x, y) return x % 3 == 0 end,
  function(x, y) return (x + y) % 3 == 0 end,
  function(x, y) return (math.floor(x / 3) + math.floor(y / 2)) % 2 == 0 end,
  function(x, y) return x * y % 2 + x * y % 3 == 0 end,
  function(x, y) return (x * y % 2 + x * y % 3) % 2 == 0 end,
  function(x, y) return ((x + y) % 2 + x * y % 3) % 2 == 0 end
}

local function applyMask(g, mask)
  local f = MASKS[mask]
  for y = 0, g.size - 1 do
    for x = 0, g.size - 1 do
      if not g.fn[y][x] and f(x, y) then g.m[y][x] = not g.m[y][x] end
    end
  end
end

-- penalty rules 1-4 of the standard
local function penalty(g)
  local s, m = g.size, g.m
  local score, dark = 0, 0
  local function lineScore(get)
    local sc, run, prev = 0, 0, nil
    local bits = {}
    for i = 0, s - 1 do
      local c = get(i)
      bits[i] = c
      if c == prev then
        run = run + 1
        if run == 5 then sc = sc + 3 elseif run > 5 then sc = sc + 1 end
      else
        prev, run = c, 1
      end
    end
    -- finder-like 1011101 with four light modules on either side (light outside the symbol counts)
    local function at(i) if i < 0 or i >= s then return false end return bits[i] end
    for i = 0, s - 7 do
      if at(i) and not at(i + 1) and at(i + 2) and at(i + 3) and at(i + 4) and not at(i + 5) and at(i + 6) then
        local before = not at(i - 1) and not at(i - 2) and not at(i - 3) and not at(i - 4)
        local after = not at(i + 7) and not at(i + 8) and not at(i + 9) and not at(i + 10)
        if before then sc = sc + 40 end
        if after then sc = sc + 40 end
      end
    end
    return sc
  end
  for y = 0, s - 1 do score = score + lineScore(function(i) return m[y][i] end) end
  for x = 0, s - 1 do score = score + lineScore(function(i) return m[i][x] end) end
  for y = 0, s - 2 do
    for x = 0, s - 2 do
      local c = m[y][x]
      if c == m[y][x + 1] and c == m[y + 1][x] and c == m[y + 1][x + 1] then score = score + 3 end
    end
  end
  for y = 0, s - 1 do
    for x = 0, s - 1 do if m[y][x] then dark = dark + 1 end end
  end
  local total = s * s
  local k = math.ceil(math.abs(dark * 20 - total * 10) / total) - 1
  return score + math.max(0, k) * 10
end

-- ------------------------------------------------------------------ encode
function Q.encode(text, forcedMask)
  text = tostring(text or "")
  local n = #text
  local version
  for v = 1, 40 do
    local bits = 4 + (v <= 9 and 8 or 16) + 8 * n
    if bits <= Q.dataCodewords(v) * 8 then version = v; break end
  end
  if not version then return nil, "too long" end
  local cap = Q.dataCodewords(version)
  -- bit stream
  local bits = {}
  local function put(value, len)
    for i = len - 1, 0, -1 do bits[#bits + 1] = bit(value, i) and 1 or 0 end
  end
  put(4, 4)
  put(n, version <= 9 and 8 or 16)
  for i = 1, n do put(text:byte(i), 8) end
  for _ = 1, math.min(4, cap * 8 - #bits) do bits[#bits + 1] = 0 end
  while #bits % 8 ~= 0 do bits[#bits + 1] = 0 end
  local data = {}
  for i = 1, #bits, 8 do
    local b = 0
    for j = 0, 7 do b = b * 2 + bits[i + j] end
    data[#data + 1] = b
  end
  local pad = 0xEC
  while #data < cap do
    data[#data + 1] = pad
    pad = (pad == 0xEC) and 0x11 or 0xEC
  end
  -- blocks, error correction, interleaving
  local b = BLOCKS[version]
  local blocks, ecs, k = {}, {}, 1
  for g = 0, 1 do
    local count, len = b[2 + g * 2], b[3 + g * 2]
    for _ = 1, count do
      local blk = {}
      for i = 1, len do blk[i] = data[k]; k = k + 1 end
      blocks[#blocks + 1] = blk
      ecs[#ecs + 1] = ecc(blk, b[1])
    end
  end
  local out = {}
  local longest = math.max(b[3], b[5])
  for i = 1, longest do
    for _, blk in ipairs(blocks) do
      if blk[i] then out[#out + 1] = blk[i] end
    end
  end
  for i = 1, b[1] do
    for _, e in ipairs(ecs) do out[#out + 1] = e[i] end
  end
  -- matrix
  local size = version * 4 + 17
  local m, fn = newGrid(size)
  local g = {size = size, m = m, fn = fn}
  drawFunctions(g, version)
  placeData(g, out)
  local best, bestScore = forcedMask, nil
  if not best then
    for mask = 0, 7 do
      applyMask(g, mask)
      drawFormat(g, mask)
      local sc = penalty(g)
      if not bestScore or sc < bestScore then best, bestScore = mask, sc end
      applyMask(g, mask) -- undo
    end
  end
  applyMask(g, best)
  drawFormat(g, best)
  local modules = {}
  for y = 0, size - 1 do
    local row = {}
    for x = 0, size - 1 do row[x + 1] = g.m[y][x] or nil end
    modules[y + 1] = row
  end
  return {size = size, version = version, mask = best, modules = modules}
end

function Q.runs(qr)
  local out = {}
  for y = 1, qr.size do
    local row, x = qr.modules[y], 1
    while x <= qr.size do
      if row[x] then
        local start = x
        while x <= qr.size and row[x] do x = x + 1 end
        out[#out + 1] = {y, start, x - start}
      else
        x = x + 1
      end
    end
  end
  return out
end

return Q
