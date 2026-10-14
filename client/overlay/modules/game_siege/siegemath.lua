-- Pure helpers of the guild siege HUD and window (no client API; tested by siegemath_test.lua).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
SiegeMath = {}

-- 725 -> "12:05"
function SiegeMath.clock(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  return string.format('%d:%02d', math.floor(seconds / 60), seconds % 60)
end

-- time until the next siege: "2d 3h", "5h 12m", "12m 30s"
function SiegeMath.countdown(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  local d, h = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
  local m, s = math.floor(seconds % 3600 / 60), seconds % 60
  if d > 0 then return string.format('%dd %dh', d, h) end
  if h > 0 then return string.format('%dh %02dm', h, m) end
  return string.format('%dm %02ds', m, s)
end

-- teams sorted by score (then kills, then name), the original table untouched
function SiegeMath.sorted(teams)
  local list = {}
  for _, t in ipairs(type(teams) == 'table' and teams or {}) do
    if type(t) == 'table' then list[#list + 1] = t end -- an entry that is no table is left out
  end
  table.sort(list, function(a, b)
    local sa, sb = tonumber(a.score) or 0, tonumber(b.score) or 0
    if sa ~= sb then return sa > sb end
    local ka, kb = tonumber(a.kills) or 0, tonumber(b.kills) or 0
    if ka ~= kb then return ka > kb end
    return tostring(a.name) < tostring(b.name)
  end)
  return list
end

-- the obelisk line and its colour
function SiegeMath.holder(data)
  data = type(data) == 'table' and data or {}
  if data.phase == 'gather' then return tr('Gates open in %s', SiegeMath.clock(data.left)), '#d6c9ae' end
  if data.phase == 'ending' then return tr('The siege is over'), '#8c8070' end
  if data.holder and data.holder ~= '' then
    return 'Obelisk: ' .. tostring(data.holder), type(data.holderColor) == 'string' and data.holderColor ~= '' and data.holderColor or '#f6cf72'
  end
  if data.contested then return tr('Obelisk: contested'), '#e8582a' end
  return tr('Obelisk: neutral'), '#8c8070'
end

function SiegeMath.title(data)
  data = type(data) == 'table' and data or {}
  if data.phase == 'gather' then return tr('Guild Siege - gathering') end
  if data.phase == 'ending' then
    local r = type(data.result) == 'table' and data.result or {}
    if r.winner and r.winner ~= '' then return r.winner .. ' wins!' end
    return tr('Siege over')
  end
  if (tonumber(data.brackets) or 1) > 1 then return tr('Guild Siege - arena %s', tostring(data.bracket)) end
  return tr('Guild Siege')
end

function SiegeMath.youText(you)
  if type(you) ~= 'table' then return '' end
  return string.format('You: %d kills, %d downed, %d points', tonumber(you.kills) or 0, tonumber(you.deaths) or 0, tonumber(you.points) or 0)
end
