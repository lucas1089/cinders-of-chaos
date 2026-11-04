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

-- Walking on the pad (owner 2026-11-04: one tap walked far). A tap is one step; holding walks on after HOLD_MS and
-- asks for the next step every REPEAT_MS; the lift ends it, and the step queued by the hold is dropped.
L.HOLD_MS = 280
L.REPEAT_MS = 40

-- the direction under the finger, from its place on the pad as fractions 0..1 (the base pad's areas): a corner square
-- of 0.3 is a diagonal, the middle 0.1 nothing, else the larger axis. Returns 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W',
-- 'NW' or nil.
function L.direction(fx, fy)
  fx, fy = num(fx, 0.5), num(fy, 0.5)
  fx, fy = math.min(1, math.max(0, fx)), math.min(1, math.max(0, fy))
  if fy < 0.3 and fx < 0.3 then return 'NW' end
  if fy < 0.3 and fx > 0.7 then return 'NE' end
  if fy > 0.7 and fx < 0.3 then return 'SW' end
  if fy > 0.7 and fx > 0.7 then return 'SE' end
  local ax, ay = math.abs(fx - 0.5), math.abs(fy - 0.5)
  if ay <= 0.1 and ax <= 0.1 then return nil end
  if ay > ax then return fy < 0.5 and 'N' or 'S' end
  return fx < 0.5 and 'W' or 'E'
end

-- the pointer knob's margins (top, left) for the finger place, as the base pad draws it
function L.pointer(fx, fy)
  fx, fy = num(fx, 0.5), num(fy, 0.5)
  fx, fy = math.min(1, math.max(0, fx)), math.min(1, math.max(0, fy))
  local angle = math.atan2 and math.atan2(fx - 0.5, fy - 0.5) or math.atan(fx - 0.5, fy - 0.5)
  local maxTop = math.abs(math.cos(angle)) * 75
  local maxLeft = math.abs(math.sin(angle)) * 75
  return math.max(-maxTop, math.min(maxTop, (fy - 0.5) * 150)), math.max(-maxLeft, math.min(maxLeft, (fx - 0.5) * 150))
end

-- does the hold walk on at this moment (pressed at downMs)
function L.repeating(downMs, now)
  return num(now, 0) - num(downMs, 0) >= L.HOLD_MS
end

-- at the lift: drop the queued step? Only after a hold; a short tap keeps its one step even when it was queued
-- behind the step that was still running.
function L.dropQueued(downMs, now)
  return L.repeating(downMs, now)
end
