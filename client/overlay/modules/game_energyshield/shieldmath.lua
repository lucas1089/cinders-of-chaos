-- Pure helpers of the energy shield bar (no engine calls, unit tested by shieldmath_test.lua).
ShieldMath = {}

-- "es:<current>:<max>" -> {current, max}, or nil for anything else; max 0 hides the bar
function ShieldMath.parse(buffer)
  if type(buffer) ~= 'string' then return nil end
  local cur, max = buffer:match('^es:(%-?%d+):(%-?%d+)$')
  if not cur then return nil end
  cur, max = tonumber(cur), tonumber(max)
  if max < 0 then max = 0 end
  if cur < 0 then cur = 0 end
  if cur > max then cur = max end
  return { current = cur, max = max }
end

-- width of the fill in pixels (0 when empty, at least 1 while above 0, never wider than the bar)
function ShieldMath.fillWidth(value, max, width)
  value, max, width = tonumber(value) or 0, tonumber(max) or 0, tonumber(width) or 0
  if max <= 0 or value <= 0 or width <= 0 then return 0 end
  if value >= max then return width end
  return math.max(1, math.floor(width * value / max))
end

-- the value shown while easing from `from` to `to` over `ms` milliseconds, `elapsed` ms in (whole numbers)
function ShieldMath.ease(from, to, elapsed, ms)
  from, to = tonumber(from) or 0, tonumber(to) or 0
  if not ms or ms <= 0 or (elapsed or 0) >= ms then return to end
  return math.floor(from + (to - from) * (elapsed or 0) / ms + 0.5)
end

-- "350 / 500" with the client's short number format when it is loaded
function ShieldMath.pair(value, max)
  local f = rawget(_G, 'formatShortNumber') or tostring
  return f(value or 0) .. ' / ' .. f(max or 0)
end

return ShieldMath
