-- Ember Cache window: pure parts (no client API), so cacheview_test.lua runs under plain Lua. The server's "state"
-- payload (server embercache.lua: embercache_core.lua K.view, daybook_core.lua D.view) becomes the lines the window
-- shows. Every text is {pattern, args...}: the window passes it to tr(pattern, args...), so each pattern is a key of the
-- client's pt-BR table (client_chaos_locale, "Run-time keys").
--   state = {week = {pts, got, sparks, ends, tiers = {{p, g, it = {{cid, n, name}}}}},
--            day = {pts, raw, bonus, goal, spark, ends, g, it},
--            src = {{key, points, per, cap, today}},
--            book = {xp, lv, kills, loot, sup, orbs, uniq, rares, deaths, secs, pts}}

CacheView = {}
local V = CacheView

V.MAX_TEXT = 48
V.REACHED = '#7ccf5c'
V.OPEN = '#c8b89a'

local function int(v)
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then return 0 end
  return math.max(0, math.floor(v))
end

local function tbl(v)
  return type(v) == 'table' and v or {}
end

local function str(v)
  if type(v) ~= 'string' then return '' end
  if #v > V.MAX_TEXT then return v:sub(1, V.MAX_TEXT) end
  return v
end

function V.plain(t)
  if type(t) ~= 'table' then return tostring(t or '') end
  if #t <= 1 then return tostring(t[1] or '') end
  local ok, s = pcall(string.format, t[1], (table.unpack or unpack)(t, 2))
  return ok and s or tostring(t[1])
end

-- 1234 -> '1.2k', 1234567 -> '1.2M' (a value, not a key)
function V.short(n)
  n = int(n)
  local units = { { 1e12, 'T' }, { 1e9, 'B' }, { 1e6, 'M' }, { 1e3, 'k' } }
  for _, u in ipairs(units) do
    if n >= u[1] then
      local v = n / u[1]
      local s = v >= 100 and string.format('%d', math.floor(v)) or string.format('%.1f', math.floor(v * 10) / 10)
      return (s:gsub('%.0$', '')) .. u[2]
    end
  end
  return tostring(n)
end

-- {'%d h %d min', 2, 5}, {'%d min', 5}
function V.duration(seconds)
  seconds = int(seconds)
  local h, m = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
  if h > 0 then return { '%d h %d min', h, m } end
  return { '%d min', m }
end

-- {'%d days', 3}, {'%d h', 5}, {'under an hour'}
function V.left(seconds)
  seconds = int(seconds)
  if seconds >= 86400 then
    local d = math.floor(seconds / 86400)
    return { d == 1 and '%d day' or '%d days', d }
  end
  if seconds >= 3600 then return { '%d h', math.floor(seconds / 3600) } end
  return { 'under an hour' }
end

-- a reward's text: {'%s gold, %s', '12k', '2x Orb of Upheaval'} (item names stay in English, like the wiki)
function V.reward(gold, items)
  local parts = {}
  for _, it in ipairs(tbl(items)) do
    local row = tbl(it)
    local n, name = int(row[2]), str(row[3])
    if name ~= '' then parts[#parts + 1] = (n > 1 and (n .. 'x ') or '') .. name end
  end
  if #parts == 0 then return { '%s gold', V.short(gold) } end
  return { '%s gold, %s', V.short(gold), table.concat(parts, ', ') }
end

V.SOURCES = {
  kill = 'Monster kills', elite = 'Rare and legendary monsters', dungeon = 'A dungeon cleared', rift = 'A rift run',
  descent = 'An Ember Descent run', tower = 'An Infinity Tower run', bounty = 'A bounty done', task = 'A kill task done',
  worldboss = 'A world boss', raid = 'An Ashen Sepulchre boss', omen = 'An Omen guardian', trial = 'A Vocation Trial run',
  invasion = 'An invasion fought', pvp = 'A battleground or a siege', goblin = 'A treasure goblin',
  craft = 'A crafting orb used'
}

-- one line per source: {label, points text, cap text or nil}
function V.sources(src)
  local out = {}
  for _, row in ipairs(tbl(src)) do
    local r = tbl(row)
    local label = V.SOURCES[r[1]]
    if label then
      local pts
      if int(r[3]) > 1 then
        pts = { '%d for 1 point', int(r[3]) }
      else
        pts = { int(r[2]) == 1 and '%d point' or '%d points', int(r[2]) }
      end
      local cap = int(r[4]) > 0 and { 'at most %d a day (%d today)', int(r[4]), int(r[5]) } or nil
      out[#out + 1] = { label = { label }, pts = pts, cap = cap }
    end
  end
  return out
end

function V.build(state)
  local st = tbl(state)
  local week, day, book = tbl(st.week), tbl(st.day), tbl(st.book)
  local v = {}
  v.week = { 'This week: %d Ember points', int(week.pts) }
  v.weekEnds = { 'The week ends in %s' }
  v.weekLeft = V.left(week.ends)
  v.tiers = {}
  for i, t in ipairs(tbl(week.tiers)) do
    local tier = tbl(t)
    local reached = i <= int(week.got)
    v.tiers[#v.tiers + 1] = {
      title = { 'Milestone %d: %d points', i, int(tier.p) },
      reward = V.reward(tier.g, tier.it),
      status = reached and { 'reached' } or { '%d to go', math.max(0, int(tier.p) - int(week.pts)) },
      color = reached and V.REACHED or V.OPEN,
      reached = reached
    }
  end
  v.sparks = { 'Daily Sparks this week: %d', int(week.sparks) }
  v.today = { 'Today: %d Ember points', int(day.pts) }
  local lit = int(day.spark) == 1
  v.spark = lit and { 'Daily Spark lit' } or { 'Daily Spark at %d points: %d to go', int(day.goal),
    math.max(0, int(day.goal) - int(day.pts)) }
  v.sparkColor = lit and V.REACHED or V.OPEN
  v.sparkReward = V.reward(day.g, day.it)
  v.bonus = int(day.bonus) > 0 and { 'Your next %d points today count double.', int(day.bonus) } or
    { 'Double points used up today.' }
  v.book = {
    { { 'Experience' }, { '%s', V.short(book.xp) } },
    { { 'Levels gained' }, { '%d', int(book.lv) } },
    { { 'Kills' }, { '%d', int(book.kills) } },
    { { 'Loot value' }, { '%s', V.short(book.loot) } },
    { { 'Supplies used' }, { '%s', V.short(book.sup) } },
    { { 'Profit' }, { '%s', (int(book.loot) < int(book.sup) and '-' or '') ..
      V.short(math.abs(int(book.loot) - int(book.sup))) } },
    { { 'Orbs, uniques, rarity items' }, { '%d / %d / %d', int(book.orbs), int(book.uniq), int(book.rares) } },
    { { 'Deaths' }, { '%d', int(book.deaths) } },
    { { 'Time played' }, V.duration(book.secs) },
  }
  v.sources = V.sources(st.src)
  return v
end

return V
