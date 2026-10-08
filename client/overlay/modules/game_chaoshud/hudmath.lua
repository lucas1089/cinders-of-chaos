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

return HudMath
