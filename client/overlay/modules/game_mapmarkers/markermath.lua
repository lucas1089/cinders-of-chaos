-- Pure helpers of the map markers (no client API), tested by markermath_test.lua.
MapMarkerMath = {}
local M = MapMarkerMath

M.OPCODE = 153
M.ICONS = '/images/chaos/mapmarkers/'
M.ANIM_MS = 800        -- a party marker glides to its new place in this time (the server sends every second)
M.JUMP_TILES = 40      -- a bigger step (a teleport) is a jump, not a glide
M.EDGE_MARGIN = 7      -- pixels between a clamped marker and the minimap's edge

-- the categories of points of interest (one check box each) and the kinds in them
M.CATEGORIES = { 'town', 'npc', 'shop', 'craft', 'guild', 'portal', 'dungeon', 'boss', 'hunt' }
M.CATEGORY_LABEL = {
  town = 'Temples, depots and banks', npc = 'Chaos NPCs (services)', shop = 'Shops, travel and blessings',
  craft = 'Crafting tables', guild = 'Guild hall', portal = 'Entrances and portals', dungeon = 'Dungeons',
  boss = 'Boss places', hunt = 'Hunting areas',
}
M.KIND_CATEGORY = {
  temple = 'town', depot = 'town', bank = 'town', npc = 'npc', shop = 'shop', travel = 'shop', bless = 'shop',
  craft = 'craft', guild = 'guild', portal = 'portal', dungeon = 'dungeon', boss = 'boss', hunt = 'hunt',
}
-- party colours, by slot (a member keeps its colour while it stays in the party)
M.COLORS = { '#ff9d2e', '#5fd0ff', '#8ee05a', '#e070ff', '#ffd84a', '#ff6464', '#5fffc8', '#c8a0ff',
             '#ffffff', '#ff9ad0' }

M.DEFAULTS = { party = true, poi = true }

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function flag(v, default)
  if v == nil then return default end
  return v == true or v == 'true'
end

-- settings from storage (any shape) -> a complete, valid table
function M.sanitize(t)
  t = type(t) == 'table' and t or {}
  local s = { party = flag(t.party, M.DEFAULTS.party), poi = flag(t.poi, M.DEFAULTS.poi), cats = {} }
  local cats = type(t.cats) == 'table' and t.cats or {}
  for _, c in ipairs(M.CATEGORIES) do
    s.cats[c] = flag(cats[c], true)
  end
  return s
end

-- ---------------------------------------------------------------- party
-- colour slots: slots = {id -> index} (kept between updates). Members that left free their slot; a new member takes
-- the lowest free one. Returns slots (changed in place).
function M.assignColors(slots, ids)
  local present, used = {}, {}
  for _, id in ipairs(ids) do present[id] = true end
  for id, i in pairs(slots) do
    if present[id] then used[i] = true else slots[id] = nil end
  end
  for _, id in ipairs(ids) do
    if not slots[id] then
      local i = 1
      while used[i] do i = i + 1 end
      slots[id] = i
      used[i] = true
    end
  end
  return slots
end

function M.color(slot)
  return M.COLORS[((tonumber(slot) or 1) - 1) % #M.COLORS + 1]
end

-- 'up' when the member is above the shown floor (a lower z), 'down' when below, nil on the same floor
function M.floorArrow(memberZ, viewZ)
  if memberZ < viewZ then return 'up' end
  if memberZ > viewZ then return 'down' end
  return nil
end

local DIRS = { 'e', 'se', 's', 'sw', 'w', 'nw', 'n', 'ne' }
local atan2 = math.atan2 or math.atan

-- one of 8 directions of a screen vector (y grows downward)
function M.dir8(dx, dy)
  if dx == 0 and dy == 0 then return nil end
  local a = atan2(dy, dx)
  local i = math.floor((a + math.pi / 8) / (math.pi / 4)) % 8
  return DIRS[i + 1]
end

local COMPASS = { n = 'north', ne = 'north-east', e = 'east', se = 'south-east', s = 'south', sw = 'south-west',
                  w = 'west', nw = 'north-west' }

-- A point (px, py) in a rect {x, y, width, height}: inside -> true, px, py. Outside (closer than margin to the edge
-- counts as outside) -> false, the point on the inset rect toward it from the rect's centre, and the direction.
function M.edge(px, py, rect, margin)
  margin = margin or M.EDGE_MARGIN
  local x1, y1 = rect.x + margin, rect.y + margin
  local x2, y2 = rect.x + rect.width - margin, rect.y + rect.height - margin
  if px >= x1 and px <= x2 and py >= y1 and py <= y2 then
    return true, px, py
  end
  local cx, cy = rect.x + rect.width / 2, rect.y + rect.height / 2
  local dx, dy = px - cx, py - cy
  local hw, hh = math.max(0, rect.width / 2 - margin), math.max(0, rect.height / 2 - margin)
  local t = 1
  if dx ~= 0 then t = math.min(t, hw / math.abs(dx)) end
  if dy ~= 0 then t = math.min(t, hh / math.abs(dy)) end
  local x, y = cx + dx * t, cy + dy * t
  return false, math.floor(clamp(x, x1, x2) + 0.5), math.floor(clamp(y, y1, y2) + 0.5), M.dir8(dx, dy)
end

-- the part of the minimap an edge arrow may use: the map's own controls (zoom, floor, compass: narrow widgets over its
-- right side) are cut off on the right. obstacles = rects of those widgets.
function M.clampRect(rect, obstacles, maxWidth)
  maxWidth = maxWidth or 80
  local right = rect.x + rect.width
  local mid = rect.x + rect.width / 2
  for _, o in ipairs(obstacles or {}) do
    local overlaps = o.x < rect.x + rect.width and o.x + o.width > rect.x and o.y < rect.y + rect.height and o.y + o.height > rect.y
    if overlaps and o.width <= maxWidth and o.x >= mid and o.x < right then
      right = o.x
    end
  end
  return { x = rect.x, y = rect.y, width = right - rect.x, height = rect.height }
end

-- the glide: a member's shown tile position at time `now` (from -> to over ANIM_MS); jumps when far or on a floor change
function M.glide(anim, now)
  if not anim.from or anim.jump then return anim.to.x, anim.to.y, true end
  local t = (now - anim.t0) / M.ANIM_MS
  if t >= 1 then return anim.to.x, anim.to.y, true end
  if t < 0 then t = 0 end
  return anim.from.x + (anim.to.x - anim.from.x) * t, anim.from.y + (anim.to.y - anim.from.y) * t, false
end

-- a new target for a member's marker: the glide starts from where it is shown now
function M.retarget(anim, x, y, z, now)
  local nx, ny = x, y
  if anim and anim.to then
    local sx, sy = M.glide(anim, now)
    local far = math.max(math.abs(x - sx), math.abs(y - sy)) > M.JUMP_TILES
    if anim.to.z ~= z or far then
      return { to = { x = nx, y = ny, z = z }, jump = true, t0 = now }
    end
    return { from = { x = sx, y = sy }, to = { x = nx, y = ny, z = z }, t0 = now }
  end
  return { to = { x = nx, y = ny, z = z }, jump = true, t0 = now }
end

-- the hover text of a member: name, health, floor and where (from the viewer's position)
function M.memberText(e, me)
  local parts = { tostring(e.n or '?') }
  if tonumber(e.p) then parts[#parts + 1] = string.format('%d%% health', e.p) end
  if me then
    local dz = (e.z or 0) - (me.z or 0)
    if dz < 0 then
      parts[#parts + 1] = (dz == -1) and '1 floor up' or string.format('%d floors up', -dz)
    elseif dz > 0 then
      parts[#parts + 1] = (dz == 1) and '1 floor down' or string.format('%d floors down', dz)
    end
    local dx, dy = (e.x or 0) - (me.x or 0), (e.y or 0) - (me.y or 0)
    local d = math.max(math.abs(dx), math.abs(dy))
    if d > 0 then
      parts[#parts + 1] = string.format('%d %s %s', d, d == 1 and 'square' or 'squares', COMPASS[M.dir8(dx, dy)])
    end
  end
  return table.concat(parts, ', ')
end

-- the party list without the viewer and without broken entries
function M.others(list, selfId)
  local out = {}
  for _, e in ipairs(type(list) == 'table' and list or {}) do
    if type(e) == 'table' and e.i ~= selfId and tonumber(e.x) and tonumber(e.y) and tonumber(e.z) then
      out[#out + 1] = e
    end
  end
  return out
end

-- ---------------------------------------------------------------- points of interest
-- clean marks by floor: {[z] = {mark, ...}}; unknown kinds are left out
function M.byFloor(marks)
  local out = {}
  for _, m in ipairs(type(marks) == 'table' and marks or {}) do
    if type(m) == 'table' and M.KIND_CATEGORY[m.k] and tonumber(m.x) and tonumber(m.y) and tonumber(m.z) then
      local z = math.floor(m.z)
      out[z] = out[z] or {}
      table.insert(out[z], m)
    end
  end
  return out
end

-- adds new marks (a reveal) to a list, one per kind and tile; returns how many were new
function M.addMarks(list, new)
  local seen = {}
  for _, m in ipairs(list) do seen[m.k .. ':' .. m.x .. ':' .. m.y .. ':' .. m.z] = true end
  local n = 0
  for _, m in ipairs(type(new) == 'table' and new or {}) do
    if type(m) == 'table' and m.k and m.x and m.y and m.z then
      local key = m.k .. ':' .. m.x .. ':' .. m.y .. ':' .. m.z
      if not seen[key] then
        seen[key] = true
        list[#list + 1] = m
        n = n + 1
      end
    end
  end
  return n
end

-- the tile bounds the minimap shows: camera, widget size in pixels, scale (pixels per tile), margin in tiles
function M.viewBounds(cam, width, height, scale, margin)
  scale = (tonumber(scale) or 1) > 0 and scale or 1
  margin = margin or 1
  local hw, hh = width / 2 / scale + margin, height / 2 / scale + margin
  return { x1 = cam.x - hw, y1 = cam.y - hh, x2 = cam.x + hw, y2 = cam.y + hh, z = cam.z }
end

-- the marks to draw on the shown floor: category switched on, inside the bounds; at most `limit` (nearest the centre
-- first when there are more)
function M.visiblePoi(floors, bounds, cats, limit)
  local out = {}
  for _, m in ipairs(floors[bounds.z] or {}) do
    local cat = M.KIND_CATEGORY[m.k]
    if cat and cats[cat] and m.x >= bounds.x1 and m.x <= bounds.x2 and m.y >= bounds.y1 and m.y <= bounds.y2 then
      out[#out + 1] = m
    end
  end
  if limit and #out > limit then
    local cx, cy = (bounds.x1 + bounds.x2) / 2, (bounds.y1 + bounds.y2) / 2
    table.sort(out, function(a, b)
      local da = math.max(math.abs(a.x - cx), math.abs(a.y - cy))
      local db = math.max(math.abs(b.x - cx), math.abs(b.y - cy))
      if da ~= db then return da < db end
      return a.k .. a.x .. a.y < b.k .. b.x .. b.y
    end)
    for i = #out, limit + 1, -1 do out[i] = nil end
  end
  return out
end

-- which of the shown markers is under the mouse: list of {rect = {x, y, width, height}, text}; the last drawn wins
function M.hit(list, mx, my)
  for i = #list, 1, -1 do
    local r = list[i].rect
    if r and mx >= r.x and mx < r.x + r.width and my >= r.y and my < r.y + r.height then
      return list[i]
    end
  end
  return nil
end
