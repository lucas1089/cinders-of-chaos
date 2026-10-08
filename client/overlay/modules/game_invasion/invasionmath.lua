-- Pure helpers of the invasion HUD and the upcoming events window (no client API), tested by invasionmath_test.lua.
InvasionMath = {}

-- 725 -> "12:05"
function InvasionMath.clock(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  return string.format('%d:%02d', math.floor(seconds / 60), seconds % 60)
end

-- seconds left now, from the value the server sent and the time since it arrived
function InvasionMath.left(sent, receivedAt, now)
  return math.max(0, (tonumber(sent) or 0) - math.max(0, (now or 0) - (receivedAt or 0)))
end

-- "in 2d 3h", "in 5h 12m", "in 12m", "now"
function InvasionMath.countdown(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  if seconds <= 0 then return 'now' end
  local d, h, m = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600), math.floor(seconds % 3600 / 60)
  if d > 0 then return string.format('in %dd %dh', d, h) end
  if h > 0 then return string.format('in %dh %02dm', h, m) end
  return string.format('in %dm', math.max(1, m))
end

function InvasionMath.title(d)
  d = type(d) == 'table' and d or {}
  if d.phase == 'occupied' then return tostring(d.area or '?') .. ' is occupied' end
  return 'Invasion: ' .. tostring(d.area or '?')
end

function InvasionMath.subtitle(d)
  d = type(d) == 'table' and d or {}
  if d.phase == 'occupied' then return 'Slay the occupiers to free it' end
  return tostring(d.faction or 'A horde') .. ' - defend ' .. tostring(d.target or 'the target')
end

function InvasionMath.waveLine(d)
  d = type(d) == 'table' and d or {}
  if d.phase == 'occupied' then
    return string.format('%d occupier%s left', tonumber(d.left) or 0, (tonumber(d.left) or 0) == 1 and '' or 's')
  end
  if (tonumber(d.wave) or 0) == 0 then
    return string.format('Wave 1 of %d in %s', tonumber(d.waves) or 0, InvasionMath.clock(d.next))
  end
  return string.format('Wave %d of %d - %d invader%s left', tonumber(d.wave) or 0, tonumber(d.waves) or 0,
    tonumber(d.left) or 0, (tonumber(d.left) or 0) == 1 and '' or 's')
end

-- breach bar colour: amber, orange from 50, red from 80
function InvasionMath.breachColor(b)
  b = tonumber(b) or 0
  if b >= 80 then return '#d01818' end
  if b >= 50 then return '#d86a10' end
  return '#b08a20'
end

-- "1. Name  42%"
function InvasionMath.topLines(top)
  local out = {}
  for i, t in ipairs(type(top) == 'table' and top or {}) do
    out[#out + 1] = string.format('%d. %s  %d%%', i, tostring(t.name), tonumber(t.share) or 0)
  end
  return out
end

function InvasionMath.youLine(you)
  if type(you) ~= 'table' then return 'You: not in the defence yet' end
  return string.format('You: #%d, %d%% of the defence, %d kill%s', tonumber(you.rank) or 0, tonumber(you.share) or 0,
    tonumber(you.kills) or 0, (tonumber(you.kills) or 0) == 1 and '' or 's')
end

function InvasionMath.resultColor(result)
  if result == 'win' or result == 'liberated' then return '#7fd07f' end
  if result == 'withdrawn' then return '#d6c9ae' end
  return '#ff5030'
end

-- colour of an upcoming-events row by kind
function InvasionMath.kindColor(kind)
  local colors = { invasion = '#e0603a', storm = '#b07aff', merchant = '#e8b84a', golden = '#f6cf72', buff = '#7fd07f', world = '#a89c86' }
  return colors[kind] or '#d6c9ae'
end

return InvasionMath
