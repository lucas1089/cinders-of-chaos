-- client_chaos_screenfit (O572): where a window opens. The pure rules (centre_logic_test.lua, screenfit_centre_test.lua).
-- A window with no anchors, or with a saved position of (0,0), opened at the top left of the screen under the hub bar.
-- Now a window with no valid position (none, the origin, or off the screen) opens centred in the game screen: the map
-- panel's area inside the root widget, below the menu bar. A position the player gave it (a drag, or a layout the
-- game_chaoslayout module restored) is valid and kept. A window larger than the area keeps the screenfit rule: its
-- start edge, so the title is in view.
WindowCentreLogic = {}
local C = WindowCentreLogic

C.EDGE = 2              -- interface pixels: a window this close to an origin counts as not placed
C.VISIBLE_MIN = 48      -- a position keeps at least this much of the window on the screen on each axis

local function num(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end

local function rectOk(r)
  return type(r) == 'table' and num(r.x) and num(r.y) and num(r.width) and num(r.height) and r.width > 0 and r.height > 0
end
C.rectOk = rectOk

-- the start of a window of `size` centred in [start, start + extent); a window that does not fit starts at the edge
function C.centreAxis(size, start, extent)
  if size >= extent then return start end
  return start + math.floor((extent - size) / 2)
end

-- the position that centres a window of size { width, height } in the rect `area`
function C.centre(size, area)
  return { x = C.centreAxis(size.width, area.x, area.width), y = C.centreAxis(size.height, area.y, area.height) }
end

-- a position that has not been given: nothing, or the top left of the screen (0,0) or of the usable area
function C.atOrigin(pos, bounds)
  if not (pos and num(pos.x) and num(pos.y)) then return true end
  local e = C.EDGE
  if math.abs(pos.x) <= e and math.abs(pos.y) <= e then return true end
  if rectOk(bounds) and math.abs(pos.x - bounds.x) <= e and math.abs(pos.y - bounds.y) <= e then return true end
  return false
end

local function overlap(start, size, bStart, bSize)
  return math.min(start + size, bStart + bSize) - math.max(start, bStart)
end

-- a position the window may keep: given (not the origin) and with enough of the window on the screen
function C.validPosition(pos, size, bounds)
  if not (pos and num(pos.x) and num(pos.y) and size and num(size.width) and num(size.height)) then return false end
  if not rectOk(bounds) then return true end    -- no screen to judge by: leave the window alone
  if C.atOrigin(pos, bounds) then return false end
  local need = function(s) return math.min(s, C.VISIBLE_MIN) end
  if overlap(pos.x, size.width, bounds.x, bounds.width) < need(size.width) then return false end
  if overlap(pos.y, size.height, bounds.y, bounds.height) < need(size.height) then return false end
  return true
end

-- the saved position of a window (game_chaoslayout) to restore: not the (0,0) a window got from the old bug, not off screen
function C.keepSaved(rect, size, bounds)
  if type(rect) ~= 'table' or not (num(rect.x) and num(rect.y)) then return false end
  if num(rect.x) and num(rect.y) and math.abs(rect.x) <= C.EDGE and math.abs(rect.y) <= C.EDGE then return false end
  return C.validPosition({ x = rect.x, y = rect.y }, size, bounds)
end

-- the area to centre in: the map panel inside the usable area when there is one, else the usable area
function C.centreArea(bounds, map)
  if not rectOk(bounds) then return nil end
  if not rectOk(map) then return bounds end
  local x1, y1 = math.max(bounds.x, map.x), math.max(bounds.y, map.y)
  local x2 = math.min(bounds.x + bounds.width, map.x + map.width)
  local y2 = math.min(bounds.y + bounds.height, map.y + map.height)
  if x2 - x1 <= 0 or y2 - y1 <= 0 then return bounds end
  return { x = x1, y = y1, width = x2 - x1, height = y2 - y1 }
end

-- the usable area: the root rect without the menu bar at the top
function C.usableArea(root, barBottom)
  if not rectOk(root) then return nil end
  local top = root.y
  if num(barBottom) and barBottom > top and barBottom < root.y + root.height then top = barBottom end
  return { x = root.x, y = top, width = root.width, height = root.y + root.height - top }
end

-- one window as it opens. info = { pos = {x, y}, size = {width, height}, moved = true when the player dragged it,
-- root = rect, barBottom = number or nil, map = rect or nil }. Returns the position to move it to, or nil to leave it.
function C.openPosition(info)
  if not info or info.moved then return nil end
  local size = info.size
  if not (size and num(size.width) and num(size.height) and size.width > 0 and size.height > 0) then return nil end
  local bounds = C.usableArea(info.root, info.barBottom)
  if not bounds then return nil end
  -- a window that fills the screen (anchors.fill, a phone's full screen window) has nothing to centre
  if math.abs(size.width - info.root.width) <= C.EDGE and math.abs(size.height - info.root.height) <= C.EDGE then return nil end
  if C.validPosition(info.pos, size, bounds) then return nil end
  local area = C.centreArea(bounds, info.map)
  local p = C.centre(size, area)
  -- a window wider or taller than the map panel but not than the screen stays on the screen
  if size.width < bounds.width then p.x = math.max(bounds.x, math.min(bounds.x + bounds.width - size.width, p.x)) else p.x = bounds.x end
  if size.height < bounds.height then p.y = math.max(bounds.y, math.min(bounds.y + bounds.height - size.height, p.y)) else p.y = bounds.y end
  return p
end

return C
