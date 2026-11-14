-- Pure helpers of the hunt teleport markers (O568; no client API), tested by huntportmath_test.lua.
-- The server (poi.lua action huntports of extended opcode 153) sends one row per hunt of the teleport hall:
-- {i = id, n = name, l = {lo, hi}, t = the hall teleport, f = the tile in front of it, a = the hunt's arrival,
-- b = the way out of the hunt (not for every base hunt)}, every place as {x, y, z}. The client keeps three facts apart
-- from that list, all computed here from the character's own steps (no server message for them):
--   last  the hunt whose hall teleport the character last used or last came out of: its hall teleport is the one to go
--         back to, drawn highlighted and pulsing
--   used  the hunts the character has entered: their way out is on the map (a hunt not entered stays unmarked, like a
--         hunting area not yet found)
--   here  the hunt the character stands in now (by its arrival, kept while the character is within HERE_RANGE of it):
--         its way out is highlighted and pulsing
-- A step of more than JUMP tiles is a teleport. From a tile next to a hall teleport it is a use of that teleport; to a
-- tile in front of a hall teleport (a hunt's exit portal sends the character there, ChaosHuntTeleports.backFor) it is a
-- coming out of that teleport's hunt.
local function tr(s, ...) local g = (rawget(_G, 'tr') or (rawget(_G, 'ChaosLocale') or {}).tr) if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
HuntPortMath = {}
local M = HuntPortMath

M.ICONS = '/images/chaos/mapmarkers/'
M.MAX = 300             -- hunts the client keeps (the hall has about 150)
M.JUMP = 3              -- a step of more than this many tiles (either axis) is a teleport
M.HERE_RANGE = 150      -- tiles between the character and the arrival of the hunt it stands in
M.HALL_RANGE = 45       -- tiles from a hall teleport: the character is in the hall, in no hunt
M.MIN_SCALE = 2         -- pixels per tile of the map below which the hall's many teleports are left out (the marked ones stay)
M.SIZE, M.SIZE_HL = 14, 18   -- the art (client/tools/gen_mapmarker_art.py) and the highlighted size on screen
M.MAX_USED = 200        -- hunts of a character kept
M.MAX_CHARS = 20        -- characters kept in the settings
M.PULSE_MS = 1400       -- one pulse of a highlighted marker
M.PULSE_TICK_MS = 120   -- how often the pulse is drawn while a highlighted marker is on the map

-- the image of each kind of marker (client/tools/gen_mapmarker_art.py)
M.IMAGE = {
  ['in'] = 'huntport', in_last = 'huntport_last', out = 'huntexit', out_here = 'huntexit_here',
}

local function whole(v)
  local n = tonumber(v)
  if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
  return math.floor(n)
end

local function pos(p)
  if type(p) ~= 'table' then return nil end
  local x, y, z = whole(p.x), whole(p.y), whole(p.z)
  if x and y and z and z >= 0 and z <= 15 then return { x = x, y = y, z = z } end
  return nil
end

-- a server message {ports = [...]} -> a clean list: broken rows and rows without an id or a hall teleport dropped,
-- positions whole, at most M.MAX rows, a repeated id keeps its first row
function M.parse(data)
  local out, seen = {}, {}
  local list = type(data) == 'table' and type(data.ports) == 'table' and data.ports or {}
  for _, e in ipairs(list) do
    if #out >= M.MAX then break end
    if type(e) == 'table' and type(e.i) == 'string' and e.i ~= '' and not seen[e.i] then
      local t = pos(e.t)
      local l = type(e.l) == 'table' and e.l or {}
      if t then
        seen[e.i] = true
        out[#out + 1] = { i = e.i, n = type(e.n) == 'string' and e.n ~= '' and e.n or e.i, lo = whole(l[1]) or 0,
          hi = whole(l[2]) or 0, t = t, f = pos(e.f), a = pos(e.a), b = pos(e.b) }
      end
    end
  end
  return out
end

-- {id -> port}
function M.index(ports)
  local by = {}
  for _, p in ipairs(ports or {}) do by[p.i] = p end
  return by
end

-- the larger of the tile distances on the two axes; nil on another floor when `sameFloor`
local function dist(a, b, sameFloor)
  if not a or not b then return nil end
  if sameFloor and a.z ~= b.z then return nil end
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end
M.dist = dist

-- the port whose `field` place is nearest to `at` on the same floor within `range` tiles (the first of equals)
local function nearestOn(ports, field, at, range)
  local best, bestD
  for _, p in ipairs(ports or {}) do
    local d = dist(p[field], at, true)
    if d and d <= range and (not bestD or d < bestD) then best, bestD = p, d end
  end
  return best
end

-- the hunt the character stands in at `at`: nil in the hall (a hall teleport within HALL_RANGE on the same floor);
-- else `keep` (an id) while the character is within HERE_RANGE of its arrival, else the hunt whose arrival is nearest
-- within HERE_RANGE (one floor up or down counts, the nearest first)
function M.hereFor(ports, at, keep)
  if not at then return nil end
  if nearestOn(ports, 't', at, M.HALL_RANGE) then return nil end
  local by = M.index(ports)
  local k = keep and by[keep]
  if k and k.a then
    local d = dist(k.a, at)
    if d and d <= M.HERE_RANGE and math.abs(k.a.z - at.z) <= 2 then return k.i end
  end
  local best, bestD
  for _, p in ipairs(ports or {}) do
    local d = p.a and dist(p.a, at)
    if d and d <= M.HERE_RANGE and math.abs(p.a.z - at.z) <= 1 then
      d = d + math.abs(p.a.z - at.z) * 0.5   -- the same floor first
      if not bestD or d < bestD then best, bestD = p, d end
    end
  end
  return best and best.i or nil
end

-- ---------------------------------------------------------------- the character's own state
function M.newState()
  return { last = nil, here = nil, used = {} }
end

-- a character's step from `prev` to `cur` (positions or nil) changes the state; true when it changed. See the head.
function M.track(state, ports, prev, cur)
  local before_last, before_here = state.last, state.here
  local usedBefore = 0
  for _ in pairs(state.used) do usedBefore = usedBefore + 1 end
  if cur and prev and dist(prev, cur) > M.JUMP then
    local entered = nearestOn(ports, 't', prev, 1)
    local left = (not entered) and nearestOn(ports, 'f', cur, 1) or nil
    if entered then
      state.last, state.here = entered.i, entered.i
      state.used[entered.i] = true
    elseif left then
      state.last, state.here = left.i, nil
      state.used[left.i] = true
    else
      state.here = M.hereFor(ports, cur, state.here)
    end
  else
    state.here = M.hereFor(ports, cur, state.here)
  end
  local usedAfter = 0
  for _ in pairs(state.used) do usedAfter = usedAfter + 1 end
  return state.last ~= before_last or state.here ~= before_here or usedAfter ~= usedBefore
end

-- ---------------------------------------------------------------- saving (g_settings node 'huntPorts')
-- {chars = {[name] = {last = id, used = {id, ...}}}} -> a state for the character `name`
function M.load(node, name)
  local state = M.newState()
  local chars = type(node) == 'table' and type(node.chars) == 'table' and node.chars or {}
  local c = type(name) == 'string' and chars[name]
  if type(c) ~= 'table' then return state end
  if type(c.last) == 'string' and c.last ~= '' then state.last = c.last end
  local n = 0
  for _, id in ipairs(type(c.used) == 'table' and c.used or {}) do
    if type(id) == 'string' and id ~= '' and n < M.MAX_USED then
      state.used[id] = true
      n = n + 1
    end
  end
  return state
end

-- the node with the character's state written in (the other characters kept, the oldest dropped over MAX_CHARS)
function M.save(node, name, state)
  node = type(node) == 'table' and node or {}
  local chars = type(node.chars) == 'table' and node.chars or {}
  local order = type(node.order) == 'table' and node.order or {}
  if type(name) ~= 'string' or name == '' then return { chars = chars, order = order } end
  local used = {}
  for id in pairs(state.used or {}) do used[#used + 1] = id end
  table.sort(used)
  while #used > M.MAX_USED do table.remove(used) end
  chars[name] = { last = state.last, used = used }
  local kept = {}
  for _, n in ipairs(order) do if n ~= name and chars[n] then kept[#kept + 1] = n end end
  kept[#kept + 1] = name
  while #kept > M.MAX_CHARS do chars[table.remove(kept, 1)] = nil end
  return { chars = chars, order = kept }
end

-- ---------------------------------------------------------------- what is drawn
-- the hover text of a marker
function M.text(kind, port, highlighted)
  local name = tr('%s (levels %d-%d)', tostring(port.n), port.lo, port.hi)
  if kind == 'in' then
    local s = tr('Hunt teleport: %s', name)
    if highlighted then s = tr('%s, last used: your way back', s) end
    return s
  end
  if highlighted then return tr('Way out of %s: you are in this hunt', tostring(port.n)) end
  return tr('Way out of %s (to the teleport room)', tostring(port.n))
end

-- the markers on the floor `bounds.z` inside the tile bounds {x1, y1, x2, y2, z} for a map of `scale` pixels a tile:
-- {kind = 'in' | 'out', id, x, y, z, highlighted, image, text}, the highlighted ones first, then by id; at most
-- `limit`. The hall teleports (kind in) are all marked; below MIN_SCALE only the one to go back to. A way out (kind
-- out) is marked for a hunt of `state.used` and for the hunt the character stands in.
function M.markers(ports, state, bounds, scale, limit)
  local out = {}
  local function inside(p)
    return p and p.z == bounds.z and p.x >= bounds.x1 and p.x <= bounds.x2 and p.y >= bounds.y1 and p.y <= bounds.y2
  end
  local close = (tonumber(scale) or 1) >= M.MIN_SCALE
  for _, p in ipairs(ports or {}) do
    local last = state.last == p.i
    if inside(p.t) and (close or last) then
      out[#out + 1] = { kind = 'in', id = p.i, x = p.t.x, y = p.t.y, z = p.t.z, highlighted = last,
        image = M.IMAGE[last and 'in_last' or 'in'], text = M.text('in', p, last) }
    end
    local here = state.here == p.i
    if inside(p.b) and (here or state.used[p.i]) then
      out[#out + 1] = { kind = 'out', id = p.i, x = p.b.x, y = p.b.y, z = p.b.z, highlighted = here,
        image = M.IMAGE[here and 'out_here' or 'out'], text = M.text('out', p, here) }
    end
  end
  table.sort(out, function(a, b)
    if a.highlighted ~= b.highlighted then return a.highlighted end
    if a.id ~= b.id then return a.id < b.id end
    return a.kind < b.kind
  end)
  if limit and #out > limit then
    for i = #out, limit + 1, -1 do out[i] = nil end
  end
  return out
end

-- the opacity of a highlighted marker at `ms` (0.55 .. 1, one pulse every PULSE_MS)
function M.pulse(ms)
  local phase = ((tonumber(ms) or 0) % M.PULSE_MS) / M.PULSE_MS
  return 0.55 + 0.45 * (0.5 + 0.5 * math.cos(phase * 2 * math.pi))
end

-- the on-screen size of a marker
function M.size(highlighted)
  return highlighted and M.SIZE_HL or M.SIZE
end
