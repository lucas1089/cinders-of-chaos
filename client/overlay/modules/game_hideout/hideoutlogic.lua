-- Hideouts: the rules without client API (tested by hideoutlogic_test.lua with luajit and lua5.3).
-- The catalogue filters and texts of the window, rotation, grid <-> world positions and the placement check of the
-- ghost preview. The check mirrors the server's (server/data/scripts/chaos/hideout_core.lua K.placeProblem): one
-- object per tile, a rug under it, wall decorations on the north / west wall, the fixture tiles free, the limits and a
-- path from the arrival tile to every fixture. The server decides; this only colours the preview.

HideoutLogic = {}
local HL = HideoutLogic

HL.SOURCES = {
  { key = 'all', name = 'Any source' },
  { key = 'default', name = 'Every character' },
  { key = 'achievement', name = 'Achievements' },
  { key = 'faction', name = 'Factions' },
  { key = 'trophy', name = 'Trophies' },
  { key = 'descent', name = 'Ember Descent' },
  { key = 'event', name = 'Events' },
  { key = 'journey', name = 'Season journey' },
  { key = 'store', name = 'Store' },
}

local function key(x, y) return x .. ',' .. y end
HL.key = key

-- ---------------------------------------------------------------- the catalogue
-- f = {cat = key | 'all', source = key | 'all', ownedOnly = bool, search = text}. Unlocked first, then by name.
function HL.filter(rows, f)
  f = f or {}
  local search = type(f.search) == 'string' and f.search:lower():gsub('^%s+', ''):gsub('%s+$', '') or ''
  local out = {}
  for _, r in ipairs(rows or {}) do
    local okCat = not f.cat or f.cat == 'all' or r.cat == f.cat
    local okSrc = not f.source or f.source == 'all' or r.source == f.source
    local okOwn = not f.ownedOnly or r.owned
    local okText = search == '' or tostring(r.name):lower():find(search, 1, true) ~= nil
    if okCat and okSrc and okOwn and okText then out[#out + 1] = r end
  end
  table.sort(out, function(a, b)
    if (a.owned and true or false) ~= (b.owned and true or false) then return a.owned == true end
    return tostring(a.name) < tostring(b.name)
  end)
  return out
end

-- the line under a row's name
function HL.subText(r)
  if not r.owned then
    return 'Locked - ' .. tostring(r.how or '')
  end
  return string.format('%d / %d placed', r.placed or 0, r.max or 0)
end

-- may the player start placing this row? -> true | false, reason
function HL.canPlace(r, hideout, inside)
  if not r then return false, 'Pick a decoration.' end
  if not inside or not inside.isOwner then return false, 'Enter your hideout to decorate it.' end
  if not r.owned then return false, 'Locked: ' .. tostring(r.how or '') end
  if (r.placed or 0) >= (r.max or 0) then return false, string.format('At most %d of it.', r.max or 0) end
  if hideout and (hideout.count or 0) >= (hideout.max or 0) then
    return false, string.format('Your hideout holds at most %d decorations.', hideout.max or 0)
  end
  return true
end

function HL.rotCount(r)
  if not r or r.layer == 'wall' then return 1 end
  return math.max(1, #(r.rots or {}))
end

function HL.nextRot(r, rot, step)
  local n = HL.rotCount(r)
  rot = (tonumber(rot) or 1) + (step or 1)
  if rot > n then rot = 1 end
  if rot < 1 then rot = n end
  return rot
end

-- parts {{dx, dy, clientId}} of a row at a rotation; wall rows take the west id on the west wall
function HL.parts(r, rot, side)
  if not r then return {} end
  if r.layer == 'wall' then
    if side == 'w' and r.wallW then return r.wallW end
    return (r.rots or {})[1] or {}
  end
  return (r.rots or {})[rot or 1] or (r.rots or {})[1] or {}
end

-- ---------------------------------------------------------------- positions
-- origin = the room's top-left wall corner (server inside.origin); nil when pos is not in the room (walls included)
function HL.toGrid(origin, layout, pos)
  if not origin or not pos or pos.z ~= origin.z then return nil end
  local gx, gy = pos.x - origin.x, pos.y - origin.y
  if gx < 0 or gy < 0 or gx > layout.w + 1 or gy > layout.h + 1 then return nil end
  return gx, gy
end

function HL.toWorld(origin, gx, gy)
  return { x = origin.x + gx, y = origin.y + gy, z = origin.z }
end

function HL.wallSide(layout, gx, gy)
  if gy == 0 and gx >= 1 and gx <= layout.w then return 'n' end
  if gx == 0 and gy >= 1 and gy <= layout.h then return 'w' end
  return nil
end

-- ---------------------------------------------------------------- the placement check
local function rowsByKey(catalogue)
  local by = {}
  for _, r in ipairs(catalogue or {}) do by[r.key] = r end
  return by
end

-- occupancy of the placed list (ignoreId: the decoration being moved)
function HL.occupancy(state, ignoreId)
  local by = rowsByKey(state.catalogue)
  local occ = { object = {}, floor = {}, wall = {}, solid = {} }
  local total = 0
  for _, p in ipairs(state.placed or {}) do
    if p.id ~= ignoreId then
      local r = by[p.key]
      if r then
        total = total + 1
        local side = r.layer == 'wall' and HL.wallSide(state.layout, p.x, p.y) or nil
        for _, part in ipairs(HL.parts(r, p.r, side)) do
          local k = key(p.x + part[1], p.y + part[2])
          occ[r.layer][k] = p.id or true
          if r.block and r.layer == 'object' then occ.solid[k] = true end
        end
      end
    end
  end
  return occ, total
end

local SOLID_FIXTURES = { depot = true, stash = true }
local function fixtureSolid(name)
  return SOLID_FIXTURES[name] or name:match('^dummy') ~= nil or name:match('^light') ~= nil
end

-- every fixture except the lights keeps a walkable neighbour reachable from the arrival tile (8 directions)
function HL.reachOk(layout, solid)
  local blocked, reserved = {}, {}
  for k in pairs(solid) do blocked[k] = true end
  for _, t in ipairs(layout.reserved or {}) do
    reserved[key(t[1], t[2])] = t[3]
    if fixtureSolid(t[3]) then blocked[key(t[1], t[2])] = true end
  end
  local a = layout.arrival
  local seen, queue, head = { [key(a[1], a[2])] = true }, { { a[1], a[2] } }, 1
  while queue[head] do
    local x, y = queue[head][1], queue[head][2]
    head = head + 1
    for dy = -1, 1 do
      for dx = -1, 1 do
        local nx, ny = x + dx, y + dy
        local k = key(nx, ny)
        if (dx ~= 0 or dy ~= 0) and nx >= 1 and ny >= 1 and nx <= layout.w and ny <= layout.h and not seen[k] and not blocked[k] then
          seen[k] = true
          queue[#queue + 1] = { nx, ny }
        end
      end
    end
  end
  for _, t in ipairs(layout.reserved or {}) do
    local name = t[3]
    if name ~= 'arrival' and not name:match('^light') then
      local reached = false
      if not fixtureSolid(name) then
        reached = seen[key(t[1], t[2])] == true
      else
        for dy = -1, 1 do
          for dx = -1, 1 do
            if seen[key(t[1] + dx, t[2] + dy)] then reached = true end
          end
        end
      end
      if not reached then return false, name end
    end
  end
  return true
end

-- can row r go to (gx, gy) at rotation rot? state = {layout, catalogue, placed, hideout}. -> true | false, reason
function HL.check(state, r, gx, gy, rot, ignoreId)
  if not r then return false, 'Pick a decoration.' end
  local L = state.layout
  local occ, total = HL.occupancy(state, ignoreId)
  local hideout = state.hideout or {}
  if total >= (hideout.max or 0) then return false, 'The hideout is full.' end
  local same = 0
  for _, p in ipairs(state.placed or {}) do
    if p.key == r.key and p.id ~= ignoreId then same = same + 1 end
  end
  if same >= (r.max or 0) then return false, 'At most ' .. tostring(r.max) .. '.' end
  if r.layer == 'wall' then
    if not HL.wallSide(L, gx, gy) then return false, 'Hang it on the north or the west wall.' end
    if occ.wall[key(gx, gy)] then return false, 'Something already hangs there.' end
    return true
  end
  local reserved = {}
  for _, t in ipairs(L.reserved or {}) do reserved[key(t[1], t[2])] = t[3] end
  local newSolid = {}
  for _, part in ipairs(HL.parts(r, rot)) do
    local x, y = gx + part[1], gy + part[2]
    local k = key(x, y)
    if x < 1 or y < 1 or x > L.w or y > L.h then return false, 'Place it on the floor.' end
    if reserved[k] then return false, 'That tile is kept free.' end
    if occ[r.layer][k] then return false, r.layer == 'floor' and 'There is a rug there.' or 'Something stands there.' end
    if r.layer == 'object' and r.block then newSolid[k] = true end
  end
  if next(newSolid) then
    for k in pairs(occ.solid) do newSolid[k] = true end
    local okReach, what = HL.reachOk(L, newSolid)
    if not okReach then return false, 'That would wall off the ' .. (what:match('^dummy') and 'dummies' or what) .. '.' end
  end
  return true
end

-- ---------------------------------------------------------------- the other tabs
function HL.permName(perms, id)
  for _, p in ipairs(perms or {}) do
    if p.id == id then return p.name end
  end
  return '?'
end

HL.WHY = { friend = 'VIP', party = 'Party', guild = 'Guild' }

-- one line of the visit list
function HL.visitLine(v)
  local parts = { v.name }
  if v.theme then parts[#parts + 1] = v.theme end
  if v.why then parts[#parts + 1] = HL.WHY[v.why] or v.why end
  if v.likes then parts[#parts + 1] = v.likes .. ' likes' end
  if v.visits then parts[#parts + 1] = v.visits .. ' visits' end
  if v.at then parts[#parts + 1] = v.at end
  return table.concat(parts, '  -  ')
end

-- the counter of the Decorate tab
function HL.countText(hideout)
  if not hideout then return '' end
  return string.format('%s - %d / %d decorations', hideout.themeName or '', hideout.count or 0, hideout.max or 0)
end

return HL
