-- Pure helpers of the Boss Spawns window (no client API), tested by bossspawnsview_test.lua.
-- Rows come from the server (server/data/scripts/chaos/bossspawns_core.lua K.payload); every time is a number of
-- seconds counted from the moment the list arrived, so the window counts down by itself between two refreshes.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
BossSpawnsView = {}
local V = BossSpawnsView

V.COLORS = {
  alive = '#6fd86f',
  respawn = '#f6cf72',
  due = '#e8a040',
  scheduled = '#7fb8e8',
  starting = '#6fd86f',
  random = '#b98ae8',
  ondemand = '#c8b890',
  cooldown = '#e05a3a',
  ready = '#6fd86f',
  unknown = '#8c8070',
}

local function num(v) return tonumber(v) or 0 end

-- seconds left now, from the value the server sent and the time since it arrived
function V.left(sent, receivedAt, now)
  return math.max(0, num(sent) - math.max(0, num(now) - num(receivedAt)))
end

-- 93784 -> "1d 2h", 4980 -> "1h 23m", 125 -> "2m 05s", 9 -> "9s"
function V.countdown(seconds)
  seconds = math.max(0, math.floor(num(seconds)))
  local d, h = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
  local m, s = math.floor(seconds % 3600 / 60), seconds % 60
  if d > 0 then return string.format('%dd %dh', d, h) end
  if h > 0 then return string.format('%dh %02dm', h, m) end
  if m > 0 then return string.format('%dm %02ds', m, s) end
  return string.format('%ds', s)
end

-- seconds since -> "just now", "12m ago", "3h ago", "2d ago"
function V.ago(seconds)
  seconds = math.max(0, math.floor(num(seconds)))
  if seconds < 60 then return tr('just now') end
  if seconds < 3600 then return tr('%dm ago', math.floor(seconds / 60)) end
  if seconds < 86400 then return tr('%dh ago', math.floor(seconds / 3600)) end
  return tr('%dd ago', math.floor(seconds / 86400))
end

-- the status column: text, colour. elapsed = seconds since the list arrived
function V.status(row, elapsed)
  row = type(row) == 'table' and row or {}
  local st = row.st
  local left = row['in'] ~= nil and math.max(0, num(row['in']) - num(elapsed)) or nil
  if st == 'alive' then
    local n = num(row.alive)
    return n > 1 and tr('Alive (%d)', n) or 'Alive', V.COLORS.alive
  elseif st == 'respawn' then
    if left and left > 0 then return tr('Respawns in %s', V.countdown(left)), V.COLORS.respawn end
    return tr('Respawn due'), V.COLORS.due
  elseif st == 'due' then
    return tr('Respawn due'), V.COLORS.due
  elseif st == 'scheduled' then
    if left and left > 0 then return 'In ' .. V.countdown(left), V.COLORS.scheduled end
    return 'Starting', V.COLORS.starting
  elseif st == 'random' then
    return 'Random', V.COLORS.random
  elseif st == 'ondemand' then
    return tr('On demand'), V.COLORS.ondemand
  elseif st == 'cooldown' then
    if left and left > 0 then return tr('Your cooldown %s', V.countdown(left)), V.COLORS.cooldown end
    return 'Ready', V.COLORS.ready
  end
  return tr('Not seen yet'), V.COLORS.unknown
end

-- the small line under the status: the time of day of a far event, else the last kill
function V.statusSub(row, elapsed)
  row = type(row) == 'table' and row or {}
  if row.at and (row.st == 'scheduled' or row.st == 'respawn') then
    return tostring(row.at)
  end
  if row.ago ~= nil then
    local text = 'Slain ' .. V.ago(num(row.ago) + num(elapsed))
    if row.by then text = text .. ' by ' .. tostring(row.by) end
    return text
  end
  if row.st == 'ondemand' or row.st == 'cooldown' or row.st == 'random' then
    return tostring(row.sh or row.tx or '')
  end
  return ''
end

function V.levelText(row)
  local parts = {}
  if num(row and row.lv) > 0 then parts[#parts + 1] = string.format('Level %d+', num(row.lv)) end
  if num(row and row.party) > 1 then parts[#parts + 1] = tr('party of %d', num(row.party)) end
  return table.concat(parts, ', ')
end

function V.coords(p)
  if type(p) ~= 'table' or not tonumber(p.x) then return '' end
  return string.format('%d, %d, %d', p.x, p.y, p.z or 7)
end

-- the second line of the location: the coordinates, else the place note (the world boss portals)
function V.where(row)
  local c = V.coords(row and row.p)
  if c ~= '' then return c end
  return tostring(row and row.ln or '')
end

-- the row's tooltip: the rule, the last kill, the position
function V.tooltip(row, elapsed)
  row = type(row) == 'table' and row or {}
  local lines = { tostring(row.n or '?') }
  if row.tx and row.tx ~= '' then lines[#lines + 1] = tostring(row.tx) end
  if row.at then lines[#lines + 1] = 'Next: ' .. tostring(row.at) end
  if row.ago ~= nil then
    local line = tr('Last kill: %s', V.ago(num(row.ago) + num(elapsed)))
    if row.by then line = line .. ' by ' .. tostring(row.by) end
    if num(row.kills) > 0 then line = line .. string.format(' (%d kills)', num(row.kills)) end
    lines[#lines + 1] = line
  end
  local c = V.coords(row.p)
  if c ~= '' then lines[#lines + 1] = 'Position: ' .. c end
  return table.concat(lines, '\n')
end

function V.matches(row, filter)
  if not filter or filter == '' then return true end
  filter = filter:lower()
  for _, field in ipairs({ row.n, row.loc }) do
    if type(field) == 'string' and field:lower():find(filter, 1, true) then return true end
  end
  return false
end

-- categories in server order with their rows (filtered); a category without rows after the filter is left out.
-- -> {{cat = {k, n, c, t}, rows = {...}, total = n}}
function V.group(data, filter)
  data = type(data) == 'table' and data or {}
  local out, byKey = {}, {}
  for _, c in ipairs(type(data.cats) == 'table' and data.cats or {}) do
    if type(c) == 'table' and c.k then
      local g = { cat = c, rows = {}, total = 0 }
      out[#out + 1] = g
      byKey[c.k] = g
    end
  end
  for _, r in ipairs(type(data.rows) == 'table' and data.rows or {}) do
    local g = type(r) == 'table' and byKey[r.c]
    if g then
      g.total = g.total + 1
      if V.matches(r, filter) then g.rows[#g.rows + 1] = r end
    end
  end
  local kept = {}
  for _, g in ipairs(out) do
    if #g.rows > 0 then kept[#kept + 1] = g end
  end
  return kept
end

-- the category header: "World Bosses (5)" or "(2 of 5)" with a filter, and the count alive
function V.header(g, collapsed)
  local count = #g.rows == g.total and tostring(g.total) or string.format('%d of %d', #g.rows, g.total)
  local alive = 0
  for _, r in ipairs(g.rows) do
    if r.st == 'alive' then alive = alive + 1 end
  end
  local text = string.format('%s %s (%s)', collapsed and '+' or '-', tostring(g.cat.n or g.cat.k), count)
  if alive > 0 then text = text .. string.format(' - %d alive', alive) end
  return text
end
