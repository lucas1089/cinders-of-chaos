-- Eased bars of the character plate (O229): the same timing as the bars over creatures (base patch 0146, chaosbars.h), pure
-- Lua so hudbars_test.lua can run it under luajit and Lua 5.3. A bar track keeps the value last shown, the value it goes to
-- and two start times; shown() and chipAt() are computed from the clock the caller passes, nothing runs by itself.
--   * a bar eases to a new value in EASE_MS (ease-out) and reaches it exactly;
--   * a fall leaves a pale chip from where the bar stood (or where the chip on screen is) to the new value: it holds HOLD_MS,
--     then slides down in SLIDE_MS (smoothstep);
--   * a rise eases up with no chip, and drops an open chip;
--   * the first value, and a value after reset(), is taken at once (no slide in from 0 at login);
--   * observe(..., staleMs) with a number also takes the value at once when the bar was not observed for that long (the plate
--     does not use it: health changes minutes apart on an idle character).
-- Values are percents (0-100) as numbers.
HudBars = {}

HudBars.EASE_MS = 150
HudBars.HOLD_MS = 250
HudBars.SLIDE_MS = 300

local function easeOut(u)
  if u < 0 then u = 0 elseif u > 1 then u = 1 end
  local r = 1 - u
  return 1 - r * r
end

local function smoothStep(u)
  if u < 0 then u = 0 elseif u > 1 then u = 1 end
  return u * u * (3 - 2 * u)
end

function HudBars.new()
  return { valid = false, from = 0, target = 0, chip = 0, easeStart = 0, chipStart = 0, lastSeen = 0 }
end

function HudBars.reset(t)
  t.valid = false
end

function HudBars.shown(t, now)
  if not t.valid then return t.target end
  local el = now - t.easeStart
  if el >= HudBars.EASE_MS then return t.target end
  if el <= 0 then return t.from end
  return t.from + (t.target - t.from) * easeOut(el / HudBars.EASE_MS)
end

function HudBars.chipAt(t, now)
  local s = HudBars.shown(t, now)
  if not t.valid then return s end
  local el = now - t.chipStart
  local c
  if el <= HudBars.HOLD_MS then
    c = t.chip
  elseif el >= HudBars.HOLD_MS + HudBars.SLIDE_MS then
    c = t.target
  else
    c = t.chip + (t.target - t.chip) * smoothStep((el - HudBars.HOLD_MS) / HudBars.SLIDE_MS)
  end
  if c < s then c = s end
  return c
end

function HudBars.settled(t, now)
  return HudBars.shown(t, now) == t.target and HudBars.chipAt(t, now) == t.target
end

function HudBars.observe(t, value, now, staleMs)
  if not t.valid or now < t.lastSeen or (staleMs and now - t.lastSeen > staleMs) then
    t.valid = true
    t.from, t.target, t.chip = value, value, value
    t.easeStart, t.chipStart, t.lastSeen = now, now, now
    return
  end
  t.lastSeen = now
  if value == t.target then return end
  local cur = HudBars.shown(t, now)
  local chip = HudBars.chipAt(t, now)
  t.from, t.target, t.easeStart, t.chipStart = cur, value, now, now
  if value < cur then
    t.chip = math.max(chip, cur)
  else
    t.chip = cur
  end
end

-- value / max as a percent for a track (0 without a max)
function HudBars.percent(value, max)
  value, max = tonumber(value) or 0, tonumber(max) or 0
  if max <= 0 or value <= 0 then return 0 end
  if value >= max then return 100 end
  return value * 100 / max
end

-- the pixel widths to draw at `now`: the fill and the chip (the chip is never narrower than the fill). A bar at rest draws
-- the plain fill width of HudMath.fillWidth(value, max, width), exactly what the plate drew before the option existed.
-- Returns fillPx, chipPx, settled.
function HudBars.widths(t, value, max, width, now, fillWidth)
  if HudBars.settled(t, now) then
    local px = fillWidth(value, max, width)
    return px, px, true
  end
  local fillPx = fillWidth(HudBars.shown(t, now), 100, width)
  local chipPx = fillWidth(HudBars.chipAt(t, now), 100, width)
  if chipPx < fillPx then chipPx = fillPx end
  return fillPx, chipPx, false
end

return HudBars
