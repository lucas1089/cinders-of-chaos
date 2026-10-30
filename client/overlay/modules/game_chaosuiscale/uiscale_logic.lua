-- game_chaosuiscale logic: the interface scale steps, what fits a screen, how the saved value is read (pure, no engine calls).
-- The engine (g_app.scale, base patch 0129) draws the whole interface into a picture of window size / N and stretches it to
-- the window. Bitmap fonts and the skin are pixel art, so only whole N stay sharp (a stretch by 1.5 makes some pixels one
-- screen pixel wide and some two). That is why the steps are 100 / 200 / 300 % and nothing between.
UiScaleLogic = {}
local L = UiScaleLogic

L.STEPS = { 100, 200, 300 }          -- percent; the option stores the index (1 = 100 %), so it is the scrollbar value too
L.DEFAULT = 1
L.MIN_W, L.MIN_H = 1024, 576         -- smallest interface (in interface pixels) the windows and panels still fit in

local function floor(x) return x - x % 1 end

-- the saved option as a step index: a number 1..#STEPS is the index; a number of 50 or more is a percent (100, 200 ...) and
-- takes the nearest step; "200", "200%" and "2" read as numbers; anything else is the default
function L.parseSaved(v)
  if type(v) == 'string' then
    v = tonumber((v:gsub('%s*%%%s*$', '')))
  end
  if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then return L.DEFAULT end
  if v >= 50 then
    local best, bestd = 1, math.huge
    for i, p in ipairs(L.STEPS) do
      local d = math.abs(p - v)
      if d < bestd then best, bestd = i, d end
    end
    return best
  end
  return L.clampIndex(floor(v + 0.5))
end

function L.clampIndex(i)
  if type(i) ~= 'number' or i ~= i then return L.DEFAULT end
  if i < 1 then return 1 end
  if i > #L.STEPS then return #L.STEPS end
  return floor(i)
end

function L.percent(index)
  return L.STEPS[L.clampIndex(index)]
end

-- the highest step whose interface still has MIN_W x MIN_H pixels on a window of w x h (step 1 always fits)
function L.maxIndex(w, h)
  if type(w) ~= 'number' or type(h) ~= 'number' or w <= 0 or h <= 0 then return 1 end
  local best = 1
  for i, p in ipairs(L.STEPS) do
    local f = p / 100
    if w / f >= L.MIN_W and h / f >= L.MIN_H then best = i end
  end
  return best
end

-- the step in use: the wanted one, lowered to what the window allows
function L.effectiveIndex(wanted, w, h)
  local i = L.clampIndex(wanted)
  local m = L.maxIndex(w, h)
  if i > m then i = m end
  return i
end

-- the factor given to g_app.scale
function L.factor(wanted, w, h)
  return L.STEPS[L.effectiveIndex(wanted, w, h)] / 100
end

-- phones (O313): the base client zooms a phone to 3x, which leaves a 1080-pixel-high screen 360 interface pixels and
-- cuts the login panel and the windows. A phone gets the highest whole step whose interface still has PHONE_W x
-- PHONE_H pixels (a 1080-pixel-high phone: 2x, about 1170 x 540); the zoom buttons still change it afterwards
L.PHONE_W, L.PHONE_H = 960, 540
function L.phoneFactor(w, h)
  if type(w) ~= 'number' or type(h) ~= 'number' or w <= 0 or h <= 0 then return nil end
  if w < h then w, h = h, w end                   -- the game is landscape; a portrait size during a turn counts the same
  local best = 1
  for _, p in ipairs(L.STEPS) do
    local f = p / 100
    if w / f >= L.PHONE_W and h / f >= L.PHONE_H then best = f end
  end
  return best
end
