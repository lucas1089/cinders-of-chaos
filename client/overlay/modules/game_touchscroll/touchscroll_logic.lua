-- game_touchscroll logic (pure, no engine calls). Owner 2026-11-04: on the phone a list or a bag only scrolled by
-- holding its scroll bar. Base patch 0184 asks Lua when a finger first moves more than 8 px whether the touch is a
-- scroll; these rules answer, move the scroll value with the finger and let it glide on after the lift.
TouchScrollLogic = TouchScrollLogic or {}
local L = TouchScrollLogic

L.HOLD_MS = 350        -- a finger that rested this long on a draggable thing (an item) drags it instead
L.SAMPLE_MS = 100      -- the glide speed is the finger speed over this last stretch
L.MIN_SPEED = 0.25     -- px per ms: slower lifts do not glide
L.MAX_SPEED = 4        -- px per ms: the glide never starts faster
L.FRICTION = 0.004     -- glide slows by this share per ms
L.STOP_SPEED = 0.03    -- px per ms: the glide ends below this
L.FRAME_MS = 16

local function num(v, d)
  v = tonumber(v)
  if v == nil or v ~= v or v == math.huge or v == -math.huge then return d end
  return v
end

-- which axis the gesture scrolls: 'v', 'h' or nil (not a scroll: the old drag or press goes on).
-- dx, dy: the movement so far; heldMs: time since the finger came down; canV / canH: the area under the finger can
-- scroll that way; draggable: the touched widget can be dragged (an item); onBar: the touch began on a scroll bar.
function L.decide(dx, dy, heldMs, canV, canH, draggable, onBar)
  if onBar then return nil end
  dx, dy, heldMs = math.abs(num(dx, 0)), math.abs(num(dy, 0)), num(heldMs, 0)
  if draggable and heldMs >= L.HOLD_MS then return nil end
  if dy >= dx then
    if canV then return 'v' end
  elseif canH then
    return 'h'
  end
  return nil
end

-- the scroll value after the finger moved by delta px: content follows the finger (finger up -> value up)
function L.value(value, delta, minimum, maximum)
  value, delta = num(value, 0), num(delta, 0)
  local lo, hi = num(minimum, 0), num(maximum, 0)
  if hi < lo then lo, hi = hi, lo end
  return math.min(hi, math.max(lo, value - delta))
end

-- can a scroll bar with this range move at all
function L.canScroll(minimum, maximum)
  return num(maximum, 0) - num(minimum, 0) >= 1
end

-- finger samples: { {t, d}, ... } (time ms, movement px along the axis), newest last, kept for SAMPLE_MS
function L.addSample(samples, t, d)
  samples[#samples + 1] = { num(t, 0), num(d, 0) }
  local cut = num(t, 0) - L.SAMPLE_MS
  while #samples > 1 and samples[1][1] < cut do table.remove(samples, 1) end
  return samples
end

-- glide speed (px per ms, signed like the finger) at the lift
function L.speed(samples, now)
  now = num(now, 0)
  local sum, first = 0, nil
  for _, s in ipairs(samples) do
    if s[1] >= now - L.SAMPLE_MS then
      sum = sum + s[2]
      first = first or s[1]
    end
  end
  if not first then return 0 end
  local span = math.max(L.FRAME_MS, now - first)
  local v = sum / span
  if math.abs(v) < L.MIN_SPEED then return 0 end
  return math.max(-L.MAX_SPEED, math.min(L.MAX_SPEED, v))
end

-- one glide frame of dt ms: the movement (px, like a finger delta) and the new speed (0 when it stops)
function L.glide(v, dt)
  v, dt = num(v, 0), math.max(0, num(dt, 0))
  local d = v * dt
  v = v * math.max(0, 1 - L.FRICTION * dt)
  if math.abs(v) < L.STOP_SPEED then v = 0 end
  return d, v
end
