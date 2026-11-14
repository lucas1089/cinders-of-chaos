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

return M
