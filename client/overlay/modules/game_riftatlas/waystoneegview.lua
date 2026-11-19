-- Pure helpers of the Waystone endgame page of the Atlas window (O670; no client API), tested by waystoneegview_test.lua.
-- Server: server/data/scripts/chaos/waystone_endgame.lua, extended opcode 159 (the Waystone Atlas opcode), actions eg_open,
-- eg_spend {key}, eg_reset; answer eg_state:
--   {points, spent, free, stats = [{key, rank, max, per, text}], paid = [0|1 per tier], respec (gold), msg,
--    levels = [monster level per tier], deepFrom (first deep tier), bosses = [{tier, name}]}
-- The rules mirror waystone_endgame_core.lua (the server checks again; this only greys the buttons).
local function tr(s, ...) local g = (rawget(_G, 'tr') or (rawget(_G, 'ChaosLocale') or {}).tr) if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
WaystoneEgView = {}
local E = WaystoneEgView

E.ROMAN = { 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII', 'XIII', 'XIV', 'XV', 'XVI', 'XVII', 'XVIII',
  'XIX', 'XX', 'XXI', 'XXII', 'XXIII', 'XXIV', 'XXV' }
E.DEEP_FROM = 16
E.TIERS = 25

local function num(v) return tonumber(v) or 0 end

function E.roman(t)
  return E.ROMAN[num(t)] or tostring(num(t))
end

local function short(n)
  n = num(n)
  if n >= 1000000 then
    return (string.format('%.1f', n / 1000000):gsub('%.0$', '')) .. 'M'
  elseif n >= 1000 then
    return (string.format('%.1f', n / 1000):gsub('%.0$', '')) .. 'k'
  end
  return tostring(math.floor(n))
end

-- the stat rows' words, by key (the server's own text is the English fallback of an unknown key)
local NAMES = {
  density = 'Density',
  bossChance = 'Band boss',
  chestChance = 'Boss chest',
  fragmentChance = 'Fragments',
}
function E.statName(key, fallback)
  local n = NAMES[key]
  return n and tr(n) or tostring(fallback or key)
end

function E.statDescription(stat)
  local per = num(stat and stat.per)
  local key = stat and stat.key
  if key == 'density' then
    return tr('A dead map monster is replaced by one more. Each rank adds %d%% chance.', per)
  elseif key == 'bossChance' then
    return tr('Chance the band boss of the run\'s band appears; it always appears at the last tier of the band. Each rank adds %d%%.', per)
  elseif key == 'chestChance' then
    return tr('Chance the map boss leaves a chest of orbs for every player in the map. Each rank adds %d%%.', per)
  elseif key == 'fragmentChance' then
    return tr('Fragment chance of a cleared run, for the pinnacle bosses. Each rank adds %d%%.', per)
  end
  return tostring(stat and stat.text or '')
end

-- the page model from an eg_state payload (unknown or missing fields get safe defaults)
function E.parse(d)
  local m = { points = 0, spent = 0, free = 0, stats = {}, paid = {}, levels = {}, bosses = {}, respec = 0, deepFrom = E.DEEP_FROM, msg = '' }
  if type(d) ~= 'table' then return m end
  m.points, m.spent, m.free = num(d.points), num(d.spent), num(d.free)
  m.respec = num(d.respec)
  m.msg = type(d.msg) == 'string' and d.msg or ''
  if num(d.deepFrom) >= 1 then m.deepFrom = math.floor(num(d.deepFrom)) end
  for _, s in ipairs(type(d.stats) == 'table' and d.stats or {}) do
    if type(s) == 'table' and type(s.key) == 'string' then
      m.stats[#m.stats + 1] = { key = s.key, rank = num(s.rank), max = math.max(1, num(s.max)), per = num(s.per), text = s.text }
    end
  end
  for t, v in ipairs(type(d.paid) == 'table' and d.paid or {}) do
    m.paid[t] = num(v) > 0
  end
  for t, v in ipairs(type(d.levels) == 'table' and d.levels or {}) do
    m.levels[t] = num(v)
  end
  for _, b in ipairs(type(d.bosses) == 'table' and d.bosses or {}) do
    if type(b) == 'table' and type(b.name) == 'string' then
      m.bosses[#m.bosses + 1] = { tier = num(b.tier), name = b.name }
    end
  end
  return m
end

function E.tierCount(m)
  local n = #(m and m.levels or {})
  return n > 0 and n or E.TIERS
end

function E.levelOf(m, t)
  local l = m and m.levels and m.levels[t]
  if l and l > 0 then return l end
  return math.min(2500, 1000 + 100 * t) -- the config's ladder (waystone_tiers_config.lua: tier I is 1100, +100 a tier, XVI-XXV at the cap 2500, O672)
end

function E.rankText(stat)
  return string.format('%d / %d', num(stat.rank), num(stat.max))
end

function E.nowText(stat)
  return tr('Now: +%d%%', num(stat.per) * num(stat.rank))
end

-- can the stat take a point? -> ok, why (points | maxed | unknown)
function E.canSpend(m, key)
  for _, s in ipairs(m and m.stats or {}) do
    if s.key == key then
      if s.rank >= s.max then return false, 'maxed' end
      if num(m.free) < 1 then return false, 'points' end
      return true
    end
  end
  return false, 'unknown'
end

function E.reasonText(why)
  if why == 'points' then return tr('You have no atlas point to spend.') end
  if why == 'maxed' then return tr('That stat is at its top rank.') end
  return tr('No such stat.')
end

function E.canReset(m)
  return num(m and m.spent) > 0
end

function E.pointsLine(m)
  return string.format('%d', num(m and m.free))
end

-- "6 first clears, 3 spent"
function E.earnedLine(m)
  local paid = 0
  for t = 1, E.tierCount(m) do
    if m.paid[t] then paid = paid + 1 end
  end
  return tr('%d first clears, %d points spent', paid, num(m and m.spent))
end

function E.resetText(m)
  return tr('Reset ranks (%s gold)', short(m and m.respec))
end

function E.resetConfirm(m)
  return tr('Refund every rank of your endgame atlas for %s gold?', short(m and m.respec))
end

-- the deep tiers, XVI-XXV: {tier, roman, level, paid}
function E.deepRows(m)
  local rows = {}
  for t = (m and m.deepFrom or E.DEEP_FROM), E.tierCount(m) do
    rows[#rows + 1] = { tier = t, roman = E.roman(t), level = E.levelOf(m, t), paid = m.paid[t] == true }
  end
  return rows
end

function E.deepCount(m)
  local done = 0
  local rows = E.deepRows(m)
  for _, r in ipairs(rows) do
    if r.paid then done = done + 1 end
  end
  return done, #rows
end

function E.tierLine(row)
  return tr('Tier %s  level %d', row.roman, row.level)
end

function E.tierStatus(row)
  return row.paid and tr('First clear done') or tr('First clear open')
end

-- the band bosses: {tier, roman, level, name, paid (the tier's first clear)}
function E.bossRows(m)
  local rows = {}
  for _, b in ipairs(m and m.bosses or {}) do
    rows[#rows + 1] = { tier = b.tier, roman = E.roman(b.tier), level = E.levelOf(m, b.tier), name = b.name, paid = m.paid[b.tier] == true }
  end
  table.sort(rows, function(a, b) return a.tier < b.tier end)
  return rows
end

function E.bossLine(row)
  return tr('%s (tier %s, level %d)', row.name, row.roman, row.level)
end

-- the Endgame button of the window: only in the Waystone Atlas; its words by the page on screen
function E.toggleText(showing)
  return showing and tr('Back to map') or tr('Endgame')
end
