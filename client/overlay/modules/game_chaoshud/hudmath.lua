-- Pure helpers of the character plate (no engine calls, unit tested by hud_test.lua).
HudMath = {}

-- width in pixels of a bar fill for value / max (0 when max <= 0, never wider than the bar,
-- at least 1 px while the value is above 0 so a nearly empty bar still shows)
function HudMath.fillWidth(value, max, width)
  value, max, width = tonumber(value) or 0, tonumber(max) or 0, tonumber(width) or 0
  if max <= 0 or value <= 0 or width <= 0 then return 0 end
  if value >= max then return width end
  return math.max(1, math.floor(width * value / max))
end

-- "15.3k / 20k" with the client's short number format when it is loaded
function HudMath.pair(value, max)
  local f = rawget(_G, 'formatShortNumber') or tostring
  return f(value or 0) .. ' / ' .. f(max or 0)
end

-- whole percent of value / max for the "percent" display: rounds down, but shows 1% while the value is above 0 and
-- 100% only when full (no rounding up to a false full bar); "0%" without a max
function HudMath.percent(value, max)
  value, max = tonumber(value) or 0, tonumber(max) or 0
  if max <= 0 or value <= 0 then return 0 end
  if value >= max then return 100 end
  return math.min(99, math.max(1, math.floor(value * 100 / max)))
end

-- text of a bar: the numbers pair, or "73%" when the percent option is on
function HudMath.barText(value, max, asPercent)
  if asPercent then return HudMath.percent(value, max) .. '%' end
  return HudMath.pair(value, max)
end

-- The option is kept per character: the saved node maps the lowercase character name to true. normalize drops
-- anything else (a damaged file), isOn / withChoice read and change it without touching the other characters.
local function key(name)
  if type(name) ~= 'string' or name == '' then return nil end
  return name:lower()
end

function HudMath.normalize(node)
  local out = {}
  if type(node) == 'table' then
    for k, v in pairs(node) do
      if type(k) == 'string' and k ~= '' and v == true then out[k] = true end
    end
  end
  return out
end

function HudMath.isOn(node, name)
  local k = key(name)
  return k ~= nil and type(node) == 'table' and node[k] == true
end

function HudMath.withChoice(node, name, on)
  local out = HudMath.normalize(node)
  local k = key(name)
  if k then out[k] = on and true or nil end
  return out
end

return HudMath
