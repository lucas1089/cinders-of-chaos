-- Pure helpers of the map overlay (no client API), tested by mapmath_test.lua.
MapOverlayMath = {}
local M = MapOverlayMath

M.ACTION = 'ChaosMapOverlay'          -- hotkey set action name (KeyBinds jsonName)
M.DEFAULT_KEY = 'Tab'
M.CHANNEL_ACTION = 'NextChannel'       -- the stock owner of Tab in the default hotkey sets
M.CHANNEL_KEY = 'Ctrl+Tab'             -- where it moves when the overlay takes Tab
M.MIN_ZOOM, M.MAX_ZOOM = 0, 4          -- minimap zoom: 2^zoom pixels per tile (1..16)
M.MODES = { 'center', 'corner' }

-- which settings check box shows a kind of mark
M.CATEGORY = {
  party = 'party',
  temple = 'town', depot = 'town', npc = 'town',
  entry = 'events', guardian = 'events', chest = 'events', coffer = 'events', goblin = 'events',
  worldboss = 'events', invasion = 'events', boss = 'events',
}

M.CENTRE_ACTION = 'ChaosMapOverlayCentre'   -- hotkey set action name of "snap back to the character"
M.CENTRE_KEY = 'Home'
M.CENTRE_KEY_CHAT = 'Ctrl+Home'          -- with chat on the chat input takes a plain Home
M.PAN_LIMIT = 512                      -- furthest the view can be panned from the character, in tiles

M.DEFAULTS = { opacity = 0.6, zoom = 2, mode = 'center', party = true, town = true, events = true, strip = true }

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function M.clampZoom(z)
  z = math.floor(tonumber(z) or M.DEFAULTS.zoom)
  return clamp(z, M.MIN_ZOOM, M.MAX_ZOOM)
end

-- opacity in steps of 0.1 between 0.2 and 1.0
function M.stepOpacity(cur, delta)
  local v = (tonumber(cur) or M.DEFAULTS.opacity) + (tonumber(delta) or 0)
  v = math.floor(v * 10 + 0.5) / 10
  return clamp(v, 0.2, 1.0)
end

function M.percent(opacity)
  return string.format('%d%%', math.floor((tonumber(opacity) or 0) * 100 + 0.5))
end

-- "x4" style label: pixels per tile
function M.zoomLabel(z)
  return string.format('x%d', 2 ^ M.clampZoom(z))
end

-- settings from storage (any shape) -> a complete, valid table
function M.sanitize(t)
  t = type(t) == 'table' and t or {}
  local s = {}
  s.opacity = M.stepOpacity(t.opacity, 0)
  s.zoom = M.clampZoom(t.zoom)
  s.mode = (t.mode == 'corner') and 'corner' or 'center'
  for _, k in ipairs({ 'party', 'town', 'events', 'strip' }) do
    if t[k] == nil then s[k] = M.DEFAULTS[k] else s[k] = (t[k] == true or t[k] == 'true') end
  end
  return s
end

-- ---------------------------------------------------------------- pan and zoom
-- The pan is the offset of the map point shown at the anchor (the character's screen point) from the character,
-- in tiles (x, y). (0, 0) = centred on the character. Screen offsets are in pixels; one tile = 2^zoom pixels.
function M.pixelsPerTile(zoom)
  return 2 ^ M.clampZoom(zoom)
end

function M.clampPan(x, y, limit)
  limit = tonumber(limit) or M.PAN_LIMIT
  return clamp(tonumber(x) or 0, -limit, limit), clamp(tonumber(y) or 0, -limit, limit)
end

function M.isPanned(x, y)
  return math.abs(tonumber(x) or 0) >= 0.05 or math.abs(tonumber(y) or 0) >= 0.05
end

-- dragging the map by (dx, dy) pixels from a pan (startX, startY): the map follows the mouse
function M.dragPan(startX, startY, dx, dy, zoom)
  local ppt = M.pixelsPerTile(zoom)
  return M.clampPan((tonumber(startX) or 0) - (tonumber(dx) or 0) / ppt, (tonumber(startY) or 0) - (tonumber(dy) or 0) / ppt)
end

-- a keyboard step: dirX / dirY in -1..1, about `pixels` screen pixels (at least one tile)
function M.keyPan(x, y, dirX, dirY, zoom, pixels)
  local step = math.max(1, (tonumber(pixels) or 48) / M.pixelsPerTile(zoom))
  return M.clampPan((tonumber(x) or 0) + (tonumber(dirX) or 0) * step, (tonumber(y) or 0) + (tonumber(dirY) or 0) * step)
end

-- zooming from oldZoom to newZoom keeping the map point under the cursor (ox, oy = cursor offset in pixels from the
-- anchor) where it is
function M.zoomToward(x, y, oldZoom, newZoom, ox, oy)
  local a, b = M.pixelsPerTile(oldZoom), M.pixelsPerTile(newZoom)
  return M.clampPan((tonumber(x) or 0) + (tonumber(ox) or 0) / a - (tonumber(ox) or 0) / b,
    (tonumber(y) or 0) + (tonumber(oy) or 0) / a - (tonumber(oy) or 0) / b)
end

-- the pan as a whole-tile camera offset plus the sub-tile rest in pixels (the minimap only moves in whole tiles)
function M.splitPan(x, y, zoom)
  local ppt = M.pixelsPerTile(zoom)
  local cx, cy = math.floor(x + 0.5), math.floor(y + 0.5)
  return cx, cy, math.floor((cx - x) * ppt + 0.5), math.floor((cy - y) * ppt + 0.5)
end

-- where an off-view point (px, py: pixels from the view's top left) is shown on the view's edge:
-- returns nil when inside, else x, y (clamped to the edge with a margin) and a direction arrow "<" ">" "^" "v"
function M.edgeMarker(px, py, w, h, margin)
  margin = margin or 14
  if px >= 0 and py >= 0 and px <= w and py <= h then return nil end
  local x, y = clamp(px, margin, w - margin), clamp(py, margin, h - margin)
  local dx, dy = px - w / 2, py - h / 2
  local arrow
  if math.abs(dx) * h >= math.abs(dy) * w then arrow = dx < 0 and '<' or '>' else arrow = dy < 0 and '^' or 'v' end
  return x, y, arrow
end

-- adds one action with its default key to a hotkey list when the list has no entry for it and the key is free
-- (no steal). Returns true when the list changed.
function M.assignKey(list, action, key)
  if type(list) ~= 'table' then return false end
  for _, e in ipairs(list) do
    if type(e) == 'table' then
      if type(e.actionsetting) == 'table' and e.actionsetting.action == action then return false end
      if e.keysequence == key then return false end
    end
  end
  list[#list + 1] = { actionsetting = { action = action }, keysequence = key }
  return true
end

-- the marks to draw: known kind, the shown floor, category switched on
function M.visibleMarks(marks, z, settings)
  local out = {}
  for _, m in ipairs(type(marks) == 'table' and marks or {}) do
    local cat = type(m) == 'table' and M.CATEGORY[m.k]
    if cat and settings[cat] and tonumber(m.x) and tonumber(m.y) and tonumber(m.z) == z then
      out[#out + 1] = m
    end
  end
  return out
end

-- Gives the overlay its default key in one hotkey list ({ {actionsetting = {action}, keysequence}, ... }) when the
-- list has no entry for it yet. Tab held only by NextChannel: NextChannel moves to Ctrl+Tab (when that is free).
-- Tab held by anything else: the overlay stays unbound (the player picks a key in the hotkey options).
-- Returns true when the list changed.
function M.assignDefaultKey(list)
  if type(list) ~= 'table' then return false end
  local tabOwners, ctrlTabUsed = {}, false
  for _, e in ipairs(list) do
    local action = type(e) == 'table' and type(e.actionsetting) == 'table' and e.actionsetting.action
    if action == M.ACTION then return false end
    if type(e) == 'table' and e.keysequence == M.DEFAULT_KEY then tabOwners[#tabOwners + 1] = e end
    if type(e) == 'table' and e.keysequence == M.CHANNEL_KEY then ctrlTabUsed = true end
  end
  for _, e in ipairs(tabOwners) do
    if e.actionsetting.action ~= M.CHANNEL_ACTION or e.secondary then return false end
  end
  if #tabOwners > 0 then
    if ctrlTabUsed then return false end
    for _, e in ipairs(tabOwners) do e.keysequence = M.CHANNEL_KEY end
  end
  list[#list + 1] = { actionsetting = { action = M.ACTION }, keysequence = M.DEFAULT_KEY }
  return true
end

-- the rift square of a new run is forgotten once (tokens = set of run ids already handled)
function M.shouldClearRift(tokens, area)
  if type(area) ~= 'table' or area.id == nil then return false end
  for _, k in ipairs({ 'x1', 'y1', 'x2', 'y2', 'z' }) do
    if not tonumber(area[k]) then return false end
  end
  if math.abs(area.x2 - area.x1) > 512 or math.abs(area.y2 - area.y1) > 512 then return false end
  return not tokens[tostring(area.id)]
end

-- Where the game view really draws the map, found by probing the screen -> tile function of the map panel
-- (probe(x, y) returns a tile {x, y} or nil outside the drawn map). rect = the panel rect {x, y, width, height};
-- player = the character's tile. Returns {x, y, width, height} of the drawn map, the screen point of the centre of
-- the character's tile (cx, cy) and the tile size in pixels (ts), or nil when the map is not drawn.
local function bisect(lo, hi, ok)
  -- ok(lo) == false, ok(hi) == true; returns the smallest value with ok() true
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if ok(mid) then hi = mid else lo = mid end
  end
  return hi
end

function M.viewGeometry(rect, probe, player)
  if type(rect) ~= 'table' or not player or rect.width < 4 or rect.height < 4 then return nil end
  local cx, cy = rect.x + math.floor(rect.width / 2), rect.y + math.floor(rect.height / 2)
  local c = probe(cx, cy)
  if not c then return nil end
  local x1 = probe(rect.x, cy) and rect.x or bisect(rect.x, cx, function(x) return probe(x, cy) ~= nil end)
  local x2r = rect.x + rect.width - 1
  local x2 = probe(x2r, cy) and x2r or (bisect(cx, x2r, function(x) return probe(x, cy) == nil end) - 1)
  local y1 = probe(cx, rect.y) and rect.y or bisect(rect.y, cy, function(y) return probe(cx, y) ~= nil end)
  local y2r = rect.y + rect.height - 1
  local y2 = probe(cx, y2r) and y2r or (bisect(cy, y2r, function(y) return probe(cx, y) == nil end) - 1)
  -- the first two tile borders right of / below the centre give the tile size
  local function border(from, to, axis, tile)
    local function past(v)
      local p = axis == 'x' and probe(v, cy) or probe(cx, v)
      return p ~= nil and p[axis] > tile
    end
    if not past(to) then return nil end
    return bisect(from, to, past)
  end
  local bx1 = border(cx, x2, 'x', c.x)
  local bx2 = bx1 and border(bx1, x2, 'x', c.x + 1)
  local by1 = border(cy, y2, 'y', c.y)
  local by2 = by1 and border(by1, y2, 'y', c.y + 1)
  if not (bx1 and bx2 and by1 and by2) then return nil end
  local tsx, tsy = bx2 - bx1, by2 - by1
  return {
    x = x1, y = y1, width = x2 - x1 + 1, height = y2 - y1 + 1, ts = (tsx + tsy) / 2,
    cx = math.floor(bx1 + (player.x - c.x - 1) * tsx + tsx / 2),
    cy = math.floor(by1 + (player.y - c.y - 1) * tsy + tsy / 2),
  }
end

-- ---------------------------------------------------------------- mouse
-- The overlay is click-through: the game map under it gets every plain click, drag, hover and wheel turn (walk,
-- attack, use, look). Only modified input belongs to the overlay, and anything over its control strip.
-- Wheel over the game view -> 'opacity' (Ctrl), 'zoom' (Shift, or any wheel over the strip) or nil (pass through).
function M.wheelAction(ctrl, shift, overStrip)
  if ctrl then return 'opacity' end
  if shift or overStrip then return 'zoom' end
  return nil
end

-- a mouse press over the overlay starts a pan only with Shift + the middle button; nothing else is taken
function M.startsPan(isMiddle, shift, overStrip)
  return isMiddle and shift and not overStrip or false
end

-- Where the character is drawn. The game view follows the character: its sprite stays on the centre of the drawn
-- map, and during a step its new tile (geo.cx, geo.cy, already the destination) slides in under it from up to a
-- tile away. Returns the sprite's screen point (sx, sy) and the sprite's offset from its tile in tiles (wx, wy),
-- so the overlay can show the character's exact, in-between position (0 within a pixel). An offset of more than 1.5 tiles means the
-- view does not follow the character (a free camera): then the tile itself is used.
function M.follow(geo)
  local sx, sy = math.floor(geo.x + geo.width / 2), math.floor(geo.y + geo.height / 2)
  local ts = (tonumber(geo.ts) or 0) > 0 and geo.ts or 32
  local wx, wy = (sx - geo.cx) / ts, (sy - geo.cy) / ts
  if math.abs(wx) > 1.5 or math.abs(wy) > 1.5 then return geo.cx, geo.cy, 0, 0 end
  -- a pixel of rounding between the sprite and its tile while standing is not a step
  if math.abs(sx - geo.cx) <= 1 then wx = 0 end
  if math.abs(sy - geo.cy) <= 1 then wy = 0 end
  return sx, sy, wx, wy
end

-- The cheap per-frame half of viewGeometry, for a view already measured (sx, sy = the centre of the drawn map, ts =
-- the tile size): the tile under the centre, its top left border by bisecting at most one tile (about 2 * log2(ts)
-- probes instead of about 70), and from it the centre of the character's tile. Returns cx, cy or nil (the probe
-- failed: measure the view again).
function M.tileCentreNear(probe, sx, sy, ts, player)
  local c = probe(sx, sy)
  if not c or not player or not ts or ts < 1 then return nil end
  local span = math.ceil(ts) + 1
  local function borderX(x) local p = probe(x, sy) return p ~= nil and p.x >= c.x end
  local function borderY(y) local p = probe(sx, y) return p ~= nil and p.y >= c.y end
  if borderX(sx - span) or borderY(sy - span) then return nil end   -- tiles bigger than measured
  local left = bisect(sx - span, sx, borderX)
  local top = bisect(sy - span, sy, borderY)
  return math.floor(left + (player.x - c.x) * ts + ts / 2), math.floor(top + (player.y - c.y) * ts + ts / 2)
end

-- a walk offset in tiles -> whole minimap pixels at a zoom
function M.walkPixels(wx, wy, zoom)
  local ppt = M.pixelsPerTile(zoom)
  return math.floor((tonumber(wx) or 0) * ppt + 0.5), math.floor((tonumber(wy) or 0) * ppt + 0.5)
end

-- The part of the game view the player really sees: the view rect cut to the window and by the panels drawn over it
-- (insets = pixels taken from each side of the window area: left, top, right, bottom; nil = none).
-- Returns {x, y, width, height}.
function M.freeArea(view, win, insets)
  insets = insets or {}
  local x1, y1 = math.max(view.x, 0), math.max(view.y, 0)
  local x2, y2 = math.min(view.x + view.width, win.width), math.min(view.y + view.height, win.height)
  x1, y1 = math.max(x1, insets.left or 0), math.max(y1, insets.top or 0)
  x2, y2 = math.min(x2, win.width - (insets.right or 0)), math.min(y2, win.height - (insets.bottom or 0))
  return { x = x1, y = y1, width = math.max(0, x2 - x1), height = math.max(0, y2 - y1) }
end

-- the corner box (position mode "corner"): top right of the game view, a third of its width
function M.cornerRect(panelW, panelH)
  local w = math.floor(clamp(panelW * 0.32, 180, 420))
  local h = math.floor(clamp(panelH * 0.36, 140, 320))
  return w, h
end

-- A death sends the client through game end and game start again (the Ok button of the death window logs the character
-- back in). The overlay closes at game end, so a death note remembers it was open and the next game start reopens it,
-- for the same character within DEATH_REOPEN_MS. A plain logout or a character switch never reopens it.
M.DEATH_REOPEN_MS = 120000

-- the note kept at a death: nil when the overlay was closed
function M.deathNote(wasShown, name, now)
  if not wasShown or type(name) ~= 'string' or name == '' then return nil end
  return { name = name, at = tonumber(now) or 0 }
end

function M.reopenAfterDeath(note, name, now)
  if type(note) ~= 'table' or note.name ~= name then return false end
  local dt = (tonumber(now) or 0) - note.at
  return dt >= 0 and dt <= M.DEATH_REOPEN_MS
end
