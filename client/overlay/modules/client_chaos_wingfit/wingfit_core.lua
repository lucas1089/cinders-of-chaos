-- Wings centred on the body (client/MANIFEST.md "Wings centred on the body"): the pure part. wing_centres.lua
-- (generated from the pair by client/tools/sprites/gen_wing_centres.py) lists, per look and direction (north, east,
-- south, west), the x of a body's torso and of a wings' pair centre, sprite pixels at 1x from the creature's place;
-- the engine (base patch 0193, chaoswingfit.h) shifts the wings by bodyCentre - wingsCentre - lift.
WingFitCore = {}
local M = WingFitCore

M.LIFT = 6        -- GameWingOffset: the body is drawn this many px up and left of the wings
M.MAX_SHIFT = 64  -- the engine ignores a larger shift
M.MAX_HEAD_SHIFT = 32 -- the engine ignores a larger head shift (chaosheadfit.h)
M.SOUTH = 2       -- direction index: 0 north, 1 east, 2 south, 3 west

local function validRow(row)
  if type(row) ~= 'table' then return false end
  for d = 1, 4 do
    if type(row[d]) ~= 'number' then return false end
  end
  return true
end

-- the valid {id, direction (0-3), px} triples of one table (bodies or wings), sorted
function M.entries(map)
  local out = {}
  if type(map) ~= 'table' then return out end
  for id, row in pairs(map) do
    if type(id) == 'number' and id >= 1 and id == math.floor(id) and validRow(row) then
      for d = 1, 4 do out[#out + 1] = { id, d - 1, math.floor(row[d]) } end
    end
  end
  table.sort(out, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] < b[2] end)
  return out
end

-- hand every row to setBody(look, dir, px) and setWings(look, dir, px); returns the number of bodies and wings
function M.apply(data, setBody, setWings)
  if type(data) ~= 'table' then return 0, 0 end
  local b, w = M.entries(data.bodies), M.entries(data.wings)
  for _, e in ipairs(b) do setBody(e[1], e[2], e[3]) end
  for _, e in ipairs(w) do setWings(e[1], e[2], e[3]) end
  return #b / 4, #w / 4
end

-- Head accessories on the head (O561, base patch 0200): head_centres.lua (ChaosHeadCentres) lists per body look the x and y
-- of its head (north, east, south, west), and the same for the reference look (ref); the engine moves a head piece (an aura
-- look from first to last) by head(body) - ref.
local function validHeadRow(row)
  if type(row) ~= 'table' then return false end
  for i = 1, 8 do
    if type(row[i]) ~= 'number' then return false end
  end
  return true
end

-- hand the reference, the piece range and every body row to the engine: setRef(dir, x, y), setPieces(first, last),
-- setBody(look, dir, x, y); returns the number of bodies handed over (0 when the data has no valid reference or range)
function M.applyHeads(data, setRef, setPieces, setBody)
  if type(data) ~= 'table' or not validHeadRow(data.ref) then return 0 end
  if type(data.first) ~= 'number' or type(data.last) ~= 'number' or data.last < data.first then return 0 end
  setPieces(data.first, data.last)
  for d = 0, 3 do setRef(d, math.floor(data.ref[d * 2 + 1]), math.floor(data.ref[d * 2 + 2])) end
  local ids = {}
  for id, row in pairs(data.bodies or {}) do
    if type(id) == 'number' and id >= 1 and id == math.floor(id) and validHeadRow(row) then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local row = data.bodies[id]
    for d = 0, 3 do setBody(id, d, math.floor(row[d * 2 + 1]), math.floor(row[d * 2 + 2])) end
  end
  return #ids
end

-- the {x, y} shift the engine adds to the head piece `aura` worn with body look `look` facing dir; {0, 0} without the
-- rows or outside the piece range. The same maths as chaosheadfit.h shift.
function M.headShiftOf(data, look, aura, dir)
  if type(data) ~= 'table' or not validHeadRow(data.ref) or type(data.first) ~= 'number' then return { 0, 0 } end
  aura = tonumber(aura)
  if not aura or aura < data.first or aura > data.last then return { 0, 0 } end
  dir = dir or M.SOUTH
  local row = type(data.bodies) == 'table' and data.bodies[tonumber(look)]
  if not validHeadRow(row) then return { 0, 0 } end
  local sx = math.floor(row[dir * 2 + 1]) - math.floor(data.ref[dir * 2 + 1])
  local sy = math.floor(row[dir * 2 + 2]) - math.floor(data.ref[dir * 2 + 2])
  if sx < -M.MAX_HEAD_SHIFT or sx > M.MAX_HEAD_SHIFT or sy < -M.MAX_HEAD_SHIFT or sy > M.MAX_HEAD_SHIFT then return { 0, 0 } end
  return { sx, sy }
end

local function centre(map, id, dir)
  local row = type(map) == 'table' and map[id]
  if not validRow(row) then return nil end
  return row[dir + 1]
end

-- the x shift the engine adds to the wings of `wings` worn with body look `look` facing dir (0 without both rows);
-- the same maths as chaoswingfit.h shiftX. lift: 6 with the client feature GameWingOffset, else 0.
function M.shiftOf(data, look, wings, dir, lift)
  if type(data) ~= 'table' then return 0 end
  local b, w = centre(data.bodies, tonumber(look), dir or M.SOUTH), centre(data.wings, tonumber(wings), dir or M.SOUTH)
  if not b or not w then return 0 end
  local s = math.floor(b) - math.floor(w) - (tonumber(lift) or 0)
  if s < -M.MAX_SHIFT or s > M.MAX_SHIFT then return 0 end
  return s
end

-- Code-drawn wings (O583, base patch 0204): wing_anchors.lua (ChaosWingAnchors) lists the wings looks that are drawn by
-- code, the one point of their picture that belongs on the torso, and hand rows {look, direction, x, y} for a body the
-- engine measures wrong. setWings(look, x, y), setBody(look, dir, x, y); returns the number of wings and of hand rows.
function M.applyAnchors(data, setWings, setBody)
  if type(data) ~= 'table' or type(data.anchor) ~= 'table' or type(data.wings) ~= 'table' then return 0, 0 end
  local ax, ay = data.anchor[1], data.anchor[2]
  if type(ax) ~= 'number' or type(ay) ~= 'number' then return 0, 0 end
  local ids = {}
  for _, id in ipairs(data.wings) do
    if type(id) == 'number' and id >= 1 and id == math.floor(id) then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do setWings(id, math.floor(ax), math.floor(ay)) end
  local rows = 0
  if type(data.bodies) == 'table' then
    for _, row in ipairs(data.bodies) do
      if type(row) == 'table' and type(row[1]) == 'number' and row[1] >= 1 and type(row[2]) == 'number' and row[2] >= 0
        and row[2] <= 3 and type(row[3]) == 'number' and type(row[4]) == 'number' then
        setBody(math.floor(row[1]), math.floor(row[2]), math.floor(row[3]), math.floor(row[4]))
        rows = rows + 1
      end
    end
  end
  return #ids, rows
end

-- Purchased pieces of pair 83 (O747, base patch 0209): wear_pieces.lua (ChaosWearPieces) lists per look the anchor tile
-- {look, ax, ay} and per wings look the lift of the body per frame ("dx dy dx dy ..."). setPiece(look, ax, ay),
-- setLift(look, text); returns the number of pieces and of lifts handed in. A bad row is skipped.
local function validLift(text)
  if type(text) ~= 'string' or #text == 0 or #text > 4096 then return false end
  local n = 0
  for v in text:gmatch('%S+') do
    local x = tonumber(v)
    if not x or x ~= math.floor(x) or x < -64 or x > 64 then return false end
    n = n + 1
  end
  return n >= 2 and n % 2 == 0
end

-- levitate = false (O762, the option "Float" of the Customise Character window): the pieces go in, the lifts do not, so the
-- engine draws the body on the ground under its pack wings (chaospiece.h: a wings look without a lift row lifts nothing)
function M.applyPieces(data, setPiece, setLift, levitate)
  if type(data) ~= 'table' or type(data.pieces) ~= 'table' then return 0, 0 end
  local np = 0
  for _, row in ipairs(data.pieces) do
    if type(row) == 'table' and type(row[1]) == 'number' and row[1] >= 1 and row[1] == math.floor(row[1])
      and type(row[2]) == 'number' and row[2] >= 0 and row[2] <= 7 and type(row[3]) == 'number' and row[3] >= 0
      and row[3] <= 7 then
      setPiece(row[1], math.floor(row[2]), math.floor(row[3]))
      np = np + 1
    end
  end
  local nl = 0
  if type(data.lifts) == 'table' and levitate ~= false then
    local ids = {}
    for look, text in pairs(data.lifts) do
      if type(look) == 'number' and look >= 1 and validLift(text) then ids[#ids + 1] = look end
    end
    table.sort(ids)
    for _, look in ipairs(ids) do setLift(look, data.lifts[look]); nl = nl + 1 end
  end
  return np, nl
end

-- O779 (base patch 0217): wear_pieces.lua `shifts` {look, dir, dx, dy} moves a pack wing's picture facing a direction
-- (dir 0 north .. 3 west, px at 1x, at most 24): the pack draws from above, so its north view hung 8-13 px low, and (O784)
-- its east and west views 1-10 px low. setShift(look, dir, dx, dy) for each good row, in table order; returns how many. The
-- Float option does not touch them. A table of O779 (north rows only) loads the same way. O785 (base patch 0219): `field`
-- names another list of the same rows, wearShifts (the head pieces and capes, moved onto the body's head or back); default
-- shifts.
M.MAX_SHIFT = 24
local function goodShift(row)
  local ok = type(row) == 'table'
  for i = 1, 4 do
    ok = ok and type(row[i]) == 'number' and row[i] == math.floor(row[i])
  end
  return ok and row[1] >= 1 and row[2] >= 0 and row[2] <= 3 and math.abs(row[3]) <= M.MAX_SHIFT
    and math.abs(row[4]) <= M.MAX_SHIFT
end

function M.applyShifts(data, setShift, field)
  field = field or 'shifts'
  if type(data) ~= 'table' or type(data[field]) ~= 'table' then return 0 end
  local n = 0
  for _, row in ipairs(data[field]) do
    if goodShift(row) then
      setShift(row[1], row[2], row[3], row[4])
      n = n + 1
    end
  end
  return n
end

-- O784 (base patch 0218): the same good rows grouped by look, for setOutfitPackShifts(look, text): text "nx ny ex ey sx sy
-- wx wy", a direction without a row 0 0, a later row of a look and direction wins (as with setShift). Looks in the order of
-- their first row; returns how many looks. `field` as for applyShifts.
function M.applyShiftTexts(data, setShifts, field)
  field = field or 'shifts'
  if type(data) ~= 'table' or type(data[field]) ~= 'table' then return 0 end
  local order, moves = {}, {}
  for _, row in ipairs(data[field]) do
    if goodShift(row) then
      local m = moves[row[1]]
      if not m then
        m = { 0, 0, 0, 0, 0, 0, 0, 0 }
        moves[row[1]] = m
        order[#order + 1] = row[1]
      end
      m[row[2] * 2 + 1], m[row[2] * 2 + 2] = row[3], row[4]
    end
  end
  for _, look in ipairs(order) do
    setShifts(look, table.concat(moves[look], ' '))
  end
  return #order
end

-- the levitation setting of this client (g_settings value): on unless it was switched off
M.LEVITATION_KEY = 'chaosWingLevitation'
function M.levitationOn(value)
  return not (value == false or value == 'false' or value == 0 or value == '0')
end

return M
