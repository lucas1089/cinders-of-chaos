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

-- ---------------------------------------------------------------- where the HUD goes
-- Rects are {x, y, width, height} in screen pixels. The HUD is a column under the character plate (top left of the
-- game view); before 2026-10-10 it had fixed margins in the map panel (40, 192), and the map panel starts above the
-- window in the extended view (y -80 at 1280x720, -120 at 1920x1080), so it sat on the plate.

InvasionMath.GAP = 8

local function hits(x, y, w, h, o, gap)
  return o.width > 0 and o.height > 0 and x < o.x + o.width + gap and o.x < x + w + gap
    and y < o.y + o.height + gap and o.y < y + h + gap
end

-- the top of the HUD column: under the plate, or 40 px into the visible view without one
function InvasionMath.columnTop(plate, viewTop, gap)
  gap = gap or InvasionMath.GAP
  if type(plate) == 'table' and (plate.height or 0) > 0 then return plate.y + plate.height + gap end
  return math.max(0, viewTop or 0) + 40
end

-- the column above the character (the centre of the game view) down to its feet: the cast bar (152 px wide) shows
-- above the character's name, how high depends on the tile size
function InvasionMath.characterZone(view)
  local cx, cy = view.x + math.floor(view.width / 2), view.y + math.floor(view.height / 2)
  local top = math.max(0, view.y)
  return { x = cx - 80, y = top, width = 160, height = math.max(0, cy + 40 - top) }
end

-- From (x, top) down: the first spot where a w x h HUD keeps `gap` pixels from every obstacle and ends above `bottom`.
-- Returns x, y, or nil when there is no such spot (the caller then keeps x, top).
function InvasionMath.place(x, top, w, h, obstacles, bottom, gap)
  gap = gap or InvasionMath.GAP
  local y = top
  for _ = 1, 64 do
    if bottom and y + h > bottom then return nil end
    local below
    for _, o in ipairs(obstacles or {}) do
      if hits(x, y, w, h, o, gap) then
        local b = o.y + o.height + gap
        if not below or b > below then below = b end
      end
    end
    if not below then return x, y end
    y = below
  end
  return nil
end

return InvasionMath
