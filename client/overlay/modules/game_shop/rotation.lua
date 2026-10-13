-- Pure helpers of the store's weekly rotation ("This week", server shop.lua / shop_config.lua storefront.featured):
-- the countdown on its category. No client API; rotation_test.lua.
RotationView = {}

-- seconds -> "3d 04h", "5h 07m", "12m" (never negative)
function RotationView.left(seconds)
  local s = math.max(0, math.floor(tonumber(seconds) or 0))
  local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
  if d > 0 then return string.format('%dd %02dh', d, h) end
  if h > 0 then return string.format('%dh %02dm', h, m) end
  return string.format('%dm', math.max(m, s > 0 and 1 or 0))
end

-- the category label: "This week (3d 04h)"; the name alone without a countdown
function RotationView.label(name, endsAt, now)
  if not tonumber(endsAt) then return tostring(name or '') end
  return string.format('%s (%s)', tostring(name or ''), RotationView.left(endsAt - (now or 0)))
end
