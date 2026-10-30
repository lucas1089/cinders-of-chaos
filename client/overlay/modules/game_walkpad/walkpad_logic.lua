-- game_walkpad logic: where the phone walking pad sits (pure, no engine calls).
-- Positions are top-left corners in interface pixels, relative to the screen. The saved value is a pair of
-- fractions 0..1 of the free room (screen minus pad), so a scale or window change keeps the pad on screen.
WalkPadLogic = WalkPadLogic or {}
local L = WalkPadLogic

L.ORB = 130        -- room kept free at the bottom left for the health orb
L.EDGE = 8         -- gap to the screen edge
L.HANDLE = 34      -- handle size
L.TAP_MS = 400     -- two taps closer than this reset the pad
L.TAP_SLOP = 12    -- a tap moves less than this many pixels

local function num(v, d)
  v = tonumber(v)
  if v == nil or v ~= v or v == math.huge or v == -math.huge then return d end
  return v
end

function L.clamp(x, y, sw, sh, w, h)
  sw, sh, w, h = num(sw, 0), num(sh, 0), num(w, 0), num(h, 0)
  local maxX, maxY = math.max(0, sw - w), math.max(0, sh - h)
  x, y = num(x, 0), num(y, 0)
  return math.min(maxX, math.max(0, x)), math.min(maxY, math.max(0, y))
end

-- default: left edge, above the health orb at the bottom left
function L.defaultPos(sw, sh, w, h)
  return L.clamp(L.EDGE, num(sh, 0) - num(h, 0) - L.ORB - L.EDGE, sw, sh, w, h)
end

-- position -> saved fractions
function L.toFraction(x, y, sw, sh, w, h)
  x, y = L.clamp(x, y, sw, sh, w, h)
  local rx, ry = math.max(0, num(sw, 0) - num(w, 0)), math.max(0, num(sh, 0) - num(h, 0))
  return rx > 0 and x / rx or 0, ry > 0 and y / ry or 0
end

-- saved fractions (nil or bad -> default) -> position
function L.fromFraction(fx, fy, sw, sh, w, h)
  fx, fy = tonumber(fx), tonumber(fy)
  if not fx or not fy or fx ~= fx or fy ~= fy or fx < 0 or fx > 1 or fy < 0 or fy > 1 then
    return L.defaultPos(sw, sh, w, h)
  end
  local rx, ry = math.max(0, num(sw, 0) - num(w, 0)), math.max(0, num(sh, 0) - num(h, 0))
  return L.clamp(fx * rx, fy * ry, sw, sh, w, h)
end

-- drag: start position + finger movement
function L.drag(startX, startY, dx, dy, sw, sh, w, h)
  return L.clamp(num(startX, 0) + num(dx, 0), num(startY, 0) + num(dy, 0), sw, sh, w, h)
end

-- is this tap the second of a double tap
function L.isDoubleTap(prevMs, prevX, prevY, ms, x, y)
  if not prevMs then return false end
  if ms - prevMs > L.TAP_MS or ms < prevMs then return false end
  return math.abs(x - prevX) <= L.TAP_SLOP and math.abs(y - prevY) <= L.TAP_SLOP
end

function L.isTap(moved)
  return num(moved, 0) <= L.TAP_SLOP
end
