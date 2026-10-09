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

M.DEFAULTS = { opacity = 0.6, zoom = 2, mode = 'center', party = true, town = true, events = true }

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
  for _, k in ipairs({ 'party', 'town', 'events' }) do
    if t[k] == nil then s[k] = M.DEFAULTS[k] else s[k] = (t[k] == true or t[k] == 'true') end
  end
  return s
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

-- the corner box (position mode "corner"): top right of the game view, a third of its width
function M.cornerRect(panelW, panelH)
  local w = math.floor(clamp(panelW * 0.32, 180, 420))
  local h = math.floor(clamp(panelH * 0.36, 140, 320))
  return w, h
end
