-- Pure helpers of the Community window and the Brazier dialog (no client API), tested by communityview_test.lua.
-- The data comes from the server (server/data/scripts/chaos/community_core.lua C.payload):
--   {now, goal = {n, d, period, left, target, p, pct, realm, rn},
--    stages = [{i, pct, key, n, d, h, done, left}],
--    sources = [{k, n, cap, mine}],
--    mine = {p, today, cap, rank, token, tokenText, title, top},
--    top = [{n, p}],
--    week = {mods = [{k, n, d}], left, staff},
--    brazier = {near, min, max, gold, per, room}}
CommunityView = {}
local V = CommunityView

V.COLORS = {
  done = '#f6cf72',
  open = '#6fd86f',
  todo = '#8c8070',
  bar = '#c8641e',
  barDone = '#e8b84a',
  ok = '#6fd86f',
  bad = '#e05a3a',
}

local function num(v) return tonumber(v) or 0 end
local function list(v) return type(v) == 'table' and v or {} end

-- 1234567 -> "1,234,567"
function V.fmt(n)
  n = math.floor(num(n))
  local neg = n < 0
  local s = tostring(math.abs(n)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return (neg and '-' or '') .. s
end

-- 93784 -> "1d 2h", 4980 -> "1h 23m", 125 -> "2m"
function V.countdown(seconds)
  seconds = math.max(0, math.floor(num(seconds)))
  local d, h = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
  local m = math.floor(seconds % 3600 / 60)
  if d > 0 then return string.format('%dd %dh', d, h) end
  if h > 0 then return string.format('%dh %02dm', h, m) end
  return string.format('%dm', math.max(1, m))
end

-- seconds left `elapsed` seconds after the state arrived (the client counts down by itself)
function V.left(seconds, elapsed)
  return math.max(0, num(seconds) - math.max(0, num(elapsed)))
end

-- the goal bar: percent (0..100, whole) and its text
function V.barPercent(data)
  local g = data and data.goal or {}
  return math.max(0, math.min(100, math.floor(num(g.pct))))
end

function V.barText(data)
  local g = data and data.goal or {}
  local pct = num(g.pct)
  local shown = pct == math.floor(pct) and tostring(math.floor(pct)) or string.format('%.1f', pct)
  return string.format('%s / %s  (%s%%)', V.fmt(g.p), V.fmt(g.target), shown)
end

-- the x offset (pixels) of a stage marker on a bar `width` wide (the marker is `markerWidth` wide, centred, kept inside)
function V.markerX(pct, width, markerWidth)
  markerWidth = markerWidth or 0
  local x = math.floor(num(width) * num(pct) / 100 - markerWidth / 2 + 0.5)
  return math.max(0, math.min(num(width) - markerWidth, x))
end

-- a stage's state: 'open' (its buff runs now), 'done' (reached, the window over), 'todo'
function V.stageState(s, elapsed)
  if s and s.left and V.left(s.left, elapsed) > 0 then return 'open' end
  if s and s.done then return 'done' end
  return 'todo'
end

-- the line under a stage's icon
function V.stageLine(s, elapsed)
  local state = V.stageState(s, elapsed)
  if state == 'open' then return 'Active: ' .. V.countdown(V.left(s.left, elapsed)) .. ' left', V.COLORS.open end
  if state == 'done' then return string.format('Reached at %d%%', num(s and s.pct)), V.COLORS.done end
  return string.format('At %d%%', num(s and s.pct)), V.COLORS.todo
end

-- the chip's second line: the short text of the buff, else the full one
function V.stageShort(s)
  return tostring(s and (s.s or s.d) or '')
end

function V.stageTooltip(s)
  if not s then return '' end
  return string.format('%s (%d%%)\n%s for everyone online, %d hours.', tostring(s.n or ''), num(s.pct), tostring(s.d or ''),
    num(s.h))
end

-- the player's line: "1,018 points (rank 2)" and today's
function V.mineText(data)
  local m = data and data.mine or {}
  local rank = num(m.rank) > 0 and string.format(' (rank %d)', num(m.rank)) or ''
  return string.format('%s points%s', V.fmt(m.p), rank)
end

function V.todayText(data)
  local m = data and data.mine or {}
  return string.format('Today: %s / %s', V.fmt(m.today), V.fmt(m.cap))
end

-- what the rewards need, and whether the player has it
function V.rewardText(data)
  local m = data and data.mine or {}
  local parts = {}
  if num(m.top) > 0 and m.title then
    parts[#parts + 1] = string.format('Top %d: the title %s.', num(m.top), tostring(m.title))
  end
  if num(m.token) > 0 then
    local have = num(m.p) >= num(m.token)
    parts[#parts + 1] = string.format('%s points: %s%s', V.fmt(m.token), tostring(m.tokenText or 'a reward'),
      have and ' (earned)' or '')
  end
  return table.concat(parts, '\n')
end

-- the source rows: {name, "120 / 4,000" today, percent of the day's cap}
function V.sourceRows(data)
  local out = {}
  for _, s in ipairs(list(data and data.sources)) do
    local cap = num(s.cap)
    out[#out + 1] = {key = s.k, name = tostring(s.n or s.k), text = string.format('%s / %s', V.fmt(s.mine), V.fmt(cap)),
      pct = cap > 0 and math.min(100, math.floor(num(s.mine) * 100 / cap)) or 0}
  end
  return out
end

-- the top rows: {place, name, points text}
function V.topRows(data)
  local out = {}
  for i, r in ipairs(list(data and data.top)) do
    out[#out + 1] = {place = i, name = tostring(r.n or '?'), text = V.fmt(r.p)}
  end
  return out
end

function V.modIcon(key)
  if type(key) ~= 'string' or not key:match('^[%w_]+$') then return '/images/game/buffs/wmod_week' end
  return '/images/game/buffs/wmod_' .. key
end

function V.stageIcon(key)
  if type(key) ~= 'string' or not key:match('^[%w_]+$') then return '/images/game/buffs/community_goal' end
  return '/images/game/buffs/community_' .. key
end

function V.weekText(data, elapsed)
  local w = data and data.week or {}
  local n = #list(w.mods)
  if n == 0 then return 'No world modifier this week.' end
  return string.format('This week (%s left)%s', V.countdown(V.left(w.left, elapsed)), w.staff and ', set by the staff' or '')
end

function V.goalTimeText(data, elapsed)
  local g = data and data.goal or {}
  return 'Ends in ' .. V.countdown(V.left(g.left, elapsed))
end

-- ---------------------------------------------------------------- the Brazier dialog
-- "150k" / "1.5m" / "25,000" / "2kk" -> gold, or nil
function V.parseGold(text)
  text = tostring(text or ''):lower():gsub('[%s,]', '')
  if text == '' then return nil end
  local n, suffix = text:match('^(%d+%.?%d*)(%a*)$')
  n = tonumber(n)
  if not n then return nil end
  local mult = ({[''] = 1, k = 1000, kk = 1000000, m = 1000000})[suffix]
  if not mult then return nil end
  return math.floor(n * mult + 0.5)
end

-- what a donation of `gold` would take: whole `per` units, within the limits; returns gold, points, problem (or nil)
function V.donation(data, gold)
  local b = data and data.brazier or {}
  local per = math.max(1, num(b.per))
  gold = math.floor(num(gold))
  if gold <= 0 then return 0, 0, 'Enter an amount of gold.' end
  if gold < num(b.min) then return 0, 0, string.format('At least %s gold.', V.fmt(b.min)) end
  local take = math.min(gold, num(b.max) > 0 and num(b.max) or gold, num(b.room))
  take = math.floor(take / per) * per
  if take <= 0 then return 0, 0, 'The Brazier takes no more from you today.' end
  if take > num(b.gold) then return 0, 0, 'You do not have that much gold.' end
  return take, math.floor(take / per), nil
end

-- the dialog's preview line and whether the button may be pressed
function V.donateState(data, text)
  local b = data and data.brazier or {}
  if not b.near then return 'Stand next to the Great Brazier in the temple.', false, V.COLORS.bad end
  local gold = V.parseGold(text)
  local take, pts, why = V.donation(data, gold)
  if why then return why, false, V.COLORS.bad end
  return string.format('Give %s gold for %s points.', V.fmt(take), V.fmt(pts)), true, V.COLORS.ok
end

function V.quickAmounts(data)
  local b = data and data.brazier or {}
  local out = {}
  for _, g in ipairs({10000, 100000, 1000000}) do
    if g >= num(b.min) and g <= math.max(num(b.max), g) then out[#out + 1] = g end
  end
  return out
end

-- 10000 -> "10k", 1000000 -> "1m"
function V.short(g)
  g = num(g)
  if g >= 1000000 and g % 1000000 == 0 then return math.floor(g / 1000000) .. 'm' end
  if g >= 1000 and g % 1000 == 0 then return math.floor(g / 1000) .. 'k' end
  return V.fmt(g)
end

return V
