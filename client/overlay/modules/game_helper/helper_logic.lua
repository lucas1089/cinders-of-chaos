-- ChaosHelperLogic: the helper's decisions as pure functions (no engine calls; tests: helper_logic_test.lua).
--   * spell areas: rotateArea, findCaster, countHits, bestDirection (the shooter counts what a wave or beam would hit)
--   * target modes A..H: pickByMode (the candidates are already reachable and checked by ChaosAutoTargetEngine)
--   * the healing row, the training row and Auto Haste: pickHeal, trainingDue, hasteDue
-- Positions are { x, y, z }. Directions are the engine's numbers (North 0, East 1, South 2, West 3, then the diagonals).
ChaosHelperLogic = ChaosHelperLogic or {}
local L = ChaosHelperLogic

L.DIR = { North = 0, East = 1, South = 2, West = 3, NorthEast = 4, SouthEast = 5, SouthWest = 6, NorthWest = 7 }
L.HASTE_GAP_MS = 2500        -- a haste cast waits at least this long after the last one (the buff shows a moment late)
L.REACH_X, L.REACH_Y = 7, 5  -- the shooter and Auto Target look this far (half width, half height) around the player

-- ---------------------------------------------------------------- areas
-- Area cells: 1 = hit, 2 or 3 = the caster's own cell (3: the spell also hits there), 0 = empty. Rows go north to south.
function L.rotateArea(area, direction)
  if type(area) ~= 'table' or #area == 0 or type(area[1]) ~= 'table' then return area end
  local D = L.DIR
  local rows, cols = #area, #area[1]
  local out = {}
  if direction == D.South then
    for y = 1, rows do
      out[y] = {}
      for x = 1, cols do out[y][x] = area[rows - y + 1][cols - x + 1] end
    end
  elseif direction == D.East then
    for x = 1, cols do
      out[x] = {}
      for y = 1, rows do out[x][y] = area[rows - y + 1][x] end
    end
  elseif direction == D.West then
    for x = 1, cols do
      out[x] = {}
      for y = 1, rows do out[x][y] = area[y][cols - x + 1] end
    end
  else
    return area
  end
  return out
end

function L.findCaster(area)
  for y, row in ipairs(area or {}) do
    for x, v in ipairs(row) do
      if v == 3 or v == 2 then return x, y end
    end
  end
  return nil, nil
end

local function diagonal(direction)
  local D = L.DIR
  if direction == D.NorthEast or direction == D.SouthEast then return D.East end
  if direction == D.SouthWest or direction == D.NorthWest then return D.West end
  return direction
end

-- How many of the creatures the area hits when cast from `from` facing `direction`.
-- creatures: { { id, position } }; opts.ranged: the caster's own cell counts; opts.sight(from, to) -> true when clear.
function L.countHits(from, direction, area, creatures, opts)
  opts = opts or {}
  local rotated = L.rotateArea(area, diagonal(direction))
  local cx, cy = L.findCaster(rotated)
  if not cx then return 0 end
  local seen, n = {}, 0
  for yy, row in ipairs(rotated) do
    for xx, v in ipairs(row) do
      if v == 1 or (opts.ranged and (v == 2 or v == 3)) then
        local px, py = from.x + (xx - cx), from.y + (yy - cy)
        for _, c in ipairs(creatures or {}) do
          local p = c.position
          if p and p.x == px and p.y == py and p.z == from.z and not seen[c.id or (px .. ',' .. py)] then
            local near = math.abs(from.x - p.x) <= 1 and math.abs(from.y - p.y) <= 1
            if near or not opts.sight or opts.sight(from, p) then
              seen[c.id or (px .. ',' .. py)] = true
              n = n + 1
              break
            end
          end
        end
      end
    end
  end
  return n
end

-- The facing that hits most. Returns direction, hits (hits 0: no facing hits anything).
function L.bestDirection(from, area, creatures, opts)
  local D = L.DIR
  local best, bestN = nil, 0
  for _, d in ipairs({ D.North, D.East, D.South, D.West }) do
    local n = L.countHits(from, d, area, creatures, opts)
    if n > bestN then best, bestN = d, n end
  end
  return best, bestN
end

-- ---------------------------------------------------------------- creatures near the player
function L.inReach(from, pos)
  if not from or not pos or from.z ~= pos.z then return false end
  return math.abs(from.x - pos.x) <= L.REACH_X and math.abs(from.y - pos.y) <= L.REACH_Y
end

function L.distance(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- ---------------------------------------------------------------- target modes
L.MODES = { closest = 1, farthest = 2, lowest = 3, highest = 4, hits = 5, closestLowest = 6, closestHighest = 7,
  farthestLowest = 8 }

-- candidates: { { id, position, health (percent), hits (optional) } }. Returns the chosen candidate or nil.
-- A tie goes to the nearer one, then to the lower id, so the choice does not flicker between two equal monsters.
function L.pickByMode(candidates, from, mode)
  local list = {}
  for _, c in ipairs(candidates or {}) do
    if c.position then
      list[#list + 1] = { c = c, d = L.distance(from, c.position), h = tonumber(c.health) or 100, n = tonumber(c.hits) or 0,
        id = tonumber(c.id) or 0 }
    end
  end
  if #list == 0 then return nil end
  mode = tonumber(mode) or L.MODES.closestLowest
  local M = L.MODES
  -- the keys, in order; a smaller value wins
  local function keys(e)
    if mode == M.closest then return { e.d, e.id } end
    if mode == M.farthest then return { -e.d, e.id } end
    if mode == M.lowest then return { e.h, e.d, e.id } end
    if mode == M.highest then return { -e.h, e.d, e.id } end
    if mode == M.hits then return { -e.n, e.d, e.h, e.id } end
    if mode == M.closestHighest then return { e.d, -e.h, e.id } end
    if mode == M.farthestLowest then return { -e.d, e.h, e.id } end
    return { e.d, e.h, e.id }
  end
  local best, bestKeys
  for _, e in ipairs(list) do
    local k = keys(e)
    local better = false
    if not best then
      better = true
    else
      for i = 1, #k do
        if k[i] ~= bestKeys[i] then
          better = k[i] < bestKeys[i]
          break
        end
      end
    end
    if better then best, bestKeys = e, k end
  end
  return best.c
end

-- ---------------------------------------------------------------- the rows
-- The healing spell to cast now, or nil. rows: { { id, percent } }; ctx = { healthPct, ready(id) -> true when it can go out
-- (castable, off cooldown, enough mana) }. The lowest threshold goes first: the strongest heal for the lowest health.
function L.pickHeal(rows, ctx)
  local list = {}
  for i, r in ipairs(rows or {}) do
    local id = tonumber(r.id) or 0
    if id > 0 and (tonumber(ctx.healthPct) or 100) <= (tonumber(r.percent) or 0) and (not ctx.ready or ctx.ready(id)) then
      list[#list + 1] = { id = id, percent = tonumber(r.percent) or 0, i = i }
    end
  end
  table.sort(list, function(a, b)
    if a.percent ~= b.percent then return a.percent < b.percent end
    return a.i < b.i
  end)
  return list[1] and list[1].id or nil
end

-- the mana training row: cast while the mana is at or above the percent
function L.trainingDue(row, manaPct)
  if type(row) ~= 'table' or row.enabled ~= true or (tonumber(row.id) or 0) <= 0 then return false end
  return (tonumber(manaPct) or 0) >= (tonumber(row.percent) or 100)
end

-- Auto Haste: st = { hasted, now, last (ms of the last cast, or nil), inProtectionZone }
function L.hasteDue(row, st)
  if type(row) ~= 'table' or row.enabled ~= true or (tonumber(row.id) or 0) <= 0 then return false end
  if st.hasted then return false end
  if st.inProtectionZone and row.safecast ~= true then return false end
  if st.last and (st.now or 0) - st.last < L.HASTE_GAP_MS then return false end
  return true
end

-- a slot of the shooter is due: the mana is at or above its percent and its creature count is met. (forceCast does not
-- change this: it only aims a wave or beam at the target, not at the side with most monsters.)
function L.slotDue(slot, manaPct, hits)
  if type(slot) ~= 'table' or (tonumber(slot.id) or 0) <= 0 then return false end
  if (tonumber(manaPct) or 0) < (tonumber(slot.percent) or 0) then return false end
  return (tonumber(hits) or 0) >= (tonumber(slot.creatures) or 1)
end

-- the facing from `from` toward `to` for an aimed wave: the longer axis (nil on the same tile or another floor)
function L.facingToward(from, to)
  if not from or not to or from.z ~= to.z then return nil end
  local dx, dy = to.x - from.x, to.y - from.y
  if dx == 0 and dy == 0 then return nil end
  if math.abs(dx) > math.abs(dy) then return dx > 0 and L.DIR.East or L.DIR.West end
  return dy > 0 and L.DIR.South or L.DIR.North
end

-- the slots in the order they are tried (priority, then position)
function L.slotOrder(slots)
  local list = {}
  for i, s in ipairs(slots or {}) do
    if type(s) == 'table' and (tonumber(s.id) or 0) > 0 then list[#list + 1] = { s = s, i = i } end
  end
  table.sort(list, function(a, b)
    local pa, pb = tonumber(a.s.priority) or a.i, tonumber(b.s.priority) or b.i
    if pa ~= pb then return pa < pb end
    return a.i < b.i
  end)
  local out = {}
  for _, e in ipairs(list) do out[#out + 1] = e.s end
  return out
end

return ChaosHelperLogic
