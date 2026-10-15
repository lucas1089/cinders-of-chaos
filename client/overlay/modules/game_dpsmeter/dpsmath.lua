-- DPS meter, pure parts (no UI calls): settings, number and time formats, the rows of a tab (share, bar length, per
-- second, average, crit rate), the segment list, the party rows, row icons and colours, and the exported summaries.
-- Tested by dpsmath_test.lua (luajit and lua5.3). Data comes from the server (combatlog_core.lua CL.state).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

DpsMath = {}

DpsMath.TEXT_COLOR = '#d6c9ae'
DpsMath.DIM_COLOR = '#8c8070'

-- the tabs: index into the view's t (server order: damage dealt, healing done, damage taken, healing received)
DpsMath.TABS = {
  { key = 'dmg', idx = 1, name = 'Damage', short = 'Dmg', rate = 'DPS', tip = 'Damage you dealt, by skill' },
  { key = 'heal', idx = 2, name = 'Healing', short = 'Heal', rate = 'HPS', tip = 'Healing you did, by skill' },
  { key = 'taken', idx = 3, name = 'Taken', short = 'Taken', rate = 'DTPS', tip = 'Damage you took, by attacker' },
  { key = 'recv', idx = 4, name = 'Received', short = 'Recv', rate = 'HPS', tip = 'Healing you received, by healer' },
}

function DpsMath.tab(key)
  for _, t in ipairs(DpsMath.TABS) do
    if t.key == key then return t end
  end
  return DpsMath.TABS[1]
end

-- our own icons (client/tools/gen_dpsmeter_icons.py draws exactly these; it checks this list)
DpsMath.ICONS = { 'sword', 'axe', 'club', 'fist', 'distance', 'wand', 'dot', 'other', 'supports', 'keystone', 'thorns',
  'power', 'elements', 'summon', 'potion', 'monster', 'player', 'env' }
local OWN = {}
for _, n in ipairs(DpsMath.ICONS) do OWN[n] = true end
-- the buff bar's icons used for damage over time and regeneration
local BUFF = { bleeding = true, burning = true, poison = true, energy = true, freezing = true, dazzled = true,
  cursed = true, drowning = true, regen = true }

-- bar colours by source kind (damage / healing / taken)
DpsMath.KIND_COLORS = {
  s = '#b8452a', r = '#8e4fc4', w = '#a8843a', d = '#4f9a34', p = '#2f8fc0', x = '#c8402a', m = '#4fb88e',
  i = '#c04a78', o = '#6b6258', c = '#9a1c14', u = '#c8a040', e = '#6b6258',
}
DpsMath.HEAL_COLOR = '#3f9a4a'
DpsMath.ELEMENT_NAMES = {
  physical = 'Physical', fire = 'Fire', earth = 'Earth', energy = 'Energy', ice = 'Ice', holy = 'Holy',
  death = 'Death', drown = 'Drown', lifedrain = 'Life drain', manadrain = 'Mana drain',
}

-- ---------------------------------------------------------------- settings (g_settings node)
DpsMath.DEFAULTS = { shown = false, w = 236, h = 200, tab = 'dmg', seg = 'c', party = false, share = true,
  locked = false, detailTab = 'dmg' }
DpsMath.MIN_W, DpsMath.MIN_H, DpsMath.MAX_W, DpsMath.MAX_H = 180, 110, 600, 700
DpsMath.DEFAULT_X, DpsMath.DEFAULT_Y = 8, 176 -- on the screen: under the character plate and the buff bar

local function num(v)
  v = tonumber(v)
  if v and v == v and v ~= math.huge and v ~= -math.huge then return v end
  return nil
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function DpsMath.sanitize(node)
  node = type(node) == 'table' and node or {}
  local d = DpsMath.DEFAULTS
  local s = {}
  for _, k in ipairs({ 'shown', 'party', 'share', 'locked' }) do
    if type(node[k]) == 'boolean' then s[k] = node[k] else s[k] = d[k] end
  end
  s.w = math.floor(clamp(num(node.w) or d.w, DpsMath.MIN_W, DpsMath.MAX_W))
  s.h = math.floor(clamp(num(node.h) or d.h, DpsMath.MIN_H, DpsMath.MAX_H))
  s.tab = DpsMath.tab(node.tab).key
  s.detailTab = DpsMath.tab(node.detailTab).key
  -- a fight id is not kept over a relog: the current fight or the session
  s.seg = (node.seg == 's') and 's' or 'c'
  local x, y = num(node.x), num(node.y)
  if x and y then s.x, s.y = math.floor(x), math.floor(y) end
  return s
end

-- a position that keeps a panel of w x h inside a parent of pw x ph (at least `keep` pixels stay visible)
function DpsMath.clampPosition(x, y, w, h, pw, ph, keep)
  keep = keep or 24
  return clamp(x, keep - w, math.max(keep - w, pw - keep)), clamp(y, 0, math.max(0, ph - math.min(h, keep)))
end

function DpsMath.clampSize(w, h)
  return math.floor(clamp(w, DpsMath.MIN_W, DpsMath.MAX_W)), math.floor(clamp(h, DpsMath.MIN_H, DpsMath.MAX_H))
end

-- ---------------------------------------------------------------- formats
function DpsMath.short(n)
  n = tonumber(n) or 0
  local sign = n < 0 and '-' or ''
  n = math.abs(n)
  local function fmt(v, suffix)
    if v >= 100 then return string.format('%s%d%s', sign, math.floor(v), suffix) end
    local s = string.format('%.1f', math.floor(v * 10) / 10):gsub('%.0$', '')
    return sign .. s .. suffix
  end
  -- the units of the rest of the client (client_chaos_numbers): k, M, B, T; the display scale (server/README.md
  -- "Display scale") puts a level-1000 meter in the millions and billions
  if n >= 1e12 then return fmt(n / 1e12, 'T') end
  if n >= 1e9 then return fmt(n / 1e9, 'B') end
  if n >= 1e6 then return fmt(n / 1e6, 'M') end
  if n >= 1e3 then return fmt(n / 1e3, 'k') end
  return sign .. tostring(math.floor(n))
end

function DpsMath.exact(n)
  n = math.floor(tonumber(n) or 0)
  local s = tostring(math.abs(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return (n < 0 and '-' or '') .. out
end

-- ms -> "0:42", "12:05", "1:02:05"
function DpsMath.duration(ms)
  local s = math.max(0, math.floor((tonumber(ms) or 0) / 1000))
  local h, m = math.floor(s / 3600), math.floor(s / 60) % 60
  s = s % 60
  if h > 0 then return string.format('%d:%02d:%02d', h, m, s) end
  return string.format('%d:%02d', m, s)
end

function DpsMath.perSecond(value, ms)
  ms = tonumber(ms) or 0
  if ms <= 0 then return 0 end
  return math.floor((tonumber(value) or 0) * 1000 / ms)
end

function DpsMath.percent(part, total)
  total = tonumber(total) or 0
  if total <= 0 then return 0 end
  local v = math.floor((tonumber(part) or 0) * 1000 / total + 0.5) / 10
  if v == math.floor(v) then return math.floor(v) end -- 60, not 60.0 (Lua 5.3)
  return v
end

-- ---------------------------------------------------------------- rows
-- the rows of tab `idx` of a segment view: {key, kind, name, icon, total, hits, crits, max, over, pct (share of the
-- tab), frac (bar length, the top row = 1), rate (per second), avg, critPct}
function DpsMath.rows(view, idx)
  local out = {}
  local tab = view and view.t and view.t[idx]
  if type(tab) ~= 'table' then return out, 0 end
  local total = tonumber(tab.tot) or 0
  local dur = tonumber(view.dur) or 0
  local top = 0
  for _, r in ipairs(tab.r or {}) do
    local v = tonumber(r[5]) or 0
    if v > top then top = v end
  end
  for i, r in ipairs(tab.r or {}) do
    local v, hits, crits = tonumber(r[5]) or 0, tonumber(r[6]) or 0, tonumber(r[7]) or 0
    out[i] = {
      key = r[1], kind = r[2], name = tostring(r[3] or '?'), icon = r[4], total = v, hits = hits, crits = crits,
      max = tonumber(r[8]) or 0, over = tonumber(r[9]) or 0,
      pct = DpsMath.percent(v, total), frac = top > 0 and v / top or 0, rate = DpsMath.perSecond(v, dur),
      avg = hits > 0 and math.floor(v / hits + 0.5) or 0, critPct = hits > 0 and math.floor(crits * 100 / hits + 0.5) or 0,
    }
  end
  return out, total
end

-- the elements of a tab, largest first: {name, amount, pct}
function DpsMath.elements(view, idx)
  local tab = view and view.t and view.t[idx]
  local out = {}
  if type(tab) ~= 'table' or type(tab.el) ~= 'table' then return out end
  local total = 0
  for _, v in pairs(tab.el) do total = total + (tonumber(v) or 0) end
  for el, v in pairs(tab.el) do
    out[#out + 1] = { key = el, name = DpsMath.ELEMENT_NAMES[el] or el, amount = tonumber(v) or 0 }
  end
  table.sort(out, function(a, b)
    if a.amount ~= b.amount then return a.amount > b.amount end
    return a.key < b.key
  end)
  for _, e in ipairs(out) do e.pct = DpsMath.percent(e.amount, total) end
  return out
end

-- the icon of a row: {kind = 'spell', words} | {kind = 'item', id} | {kind = 'image', path}
function DpsMath.iconSpec(kind, icon)
  if kind == 's' and type(icon) == 'string' and icon ~= '' then
    return { kind = 'spell', words = icon, fallback = '/images/game/dpsmeter/wand' }
  end
  if kind == 'r' and tonumber(icon) and tonumber(icon) > 0 then
    return { kind = 'item', id = tonumber(icon) }
  end
  if type(icon) == 'string' and BUFF[icon] then
    return { kind = 'image', path = '/images/game/buffs/' .. icon }
  end
  if type(icon) == 'string' and OWN[icon] then
    return { kind = 'image', path = '/images/game/dpsmeter/' .. icon }
  end
  if kind == 'c' then return { kind = 'image', path = '/images/game/dpsmeter/monster' } end
  if kind == 'u' then return { kind = 'image', path = '/images/game/dpsmeter/player' } end
  if kind == 'm' then return { kind = 'image', path = '/images/game/dpsmeter/summon' } end
  if kind == 'd' then return { kind = 'image', path = '/images/game/dpsmeter/dot' } end
  return { kind = 'image', path = '/images/game/dpsmeter/other' }
end

function DpsMath.barColor(kind, tabIdx)
  if tabIdx == 2 or tabIdx == 4 then
    if kind == 'u' then return DpsMath.KIND_COLORS.u end
    return DpsMath.HEAL_COLOR
  end
  return DpsMath.KIND_COLORS[kind] or DpsMath.KIND_COLORS.o
end

-- ---------------------------------------------------------------- segments
-- the dropdown entries: {id, text}; segs = [[id, label, dur, dmg, heal, taken, live, boss]]. The texts of the session
-- and the running fight do not carry the running time, so the list only changes when the fights change.
function DpsMath.segmentOptions(segs)
  local out = { { id = 'c', text = 'Current fight' } }
  for _, s in ipairs(segs or {}) do
    local id, label, dur, live, boss = s[1], tostring(s[2] or ''), s[3], s[7] == 1, s[8] == 1
    if id == 's' then
      out[#out + 1] = { id = 's', text = 'Session' }
    elseif not live then
      out[#out + 1] = { id = id, text = string.format('#%s %s%s (%s)', tostring(id), boss and '[Boss] ' or '', label,
        DpsMath.duration(dur)) }
    end
  end
  return out
end

function DpsMath.segmentKey(options)
  local parts = {}
  for _, o in ipairs(options) do parts[#parts + 1] = tostring(o.id) .. '=' .. o.text end
  return table.concat(parts, '|')
end

-- the title line of the panel: "<label>  0:42" (live: "<label>  0:42 *")
function DpsMath.title(view)
  if not view then return tr('No fight yet') end
  local label = view.id == 's' and 'Session' or tostring(view.label or 'Fight')
  return string.format('%s  %s%s', label, DpsMath.duration(view.dur), view.live == 1 and ' *' or '')
end

-- ---------------------------------------------------------------- party
-- party members [{n, self, fd, fh, ft, fdur, live, sd, sh, st, sdur}] -> rows for tab idx, best first:
-- {name, self, value, rate, frac}. session = true: the session numbers, else the current (or last) fight.
function DpsMath.partyRows(party, idx, session)
  local out = {}
  local field = ({ 'd', 'h', 't', 'h' })[idx] or 'd'
  for _, m in ipairs(party or {}) do
    local value = tonumber(m[(session and 's' or 'f') .. field]) or 0
    local dur = tonumber(m[session and 'sdur' or 'fdur']) or 0
    out[#out + 1] = { name = tostring(m.n or '?'), self = m.self == 1, value = value,
      rate = DpsMath.perSecond(value, dur), live = m.live == 1 }
  end
  table.sort(out, function(a, b)
    if a.rate ~= b.rate then return a.rate > b.rate end
    return a.name < b.name
  end)
  local top = out[1] and out[1].rate or 0
  for _, r in ipairs(out) do r.frac = top > 0 and r.rate / top or 0 end
  return out
end

-- ---------------------------------------------------------------- export (local only: clipboard, chat input line)
local function tabTitle(idx)
  for _, t in ipairs(DpsMath.TABS) do
    if t.idx == idx then return t end
  end
  return DpsMath.TABS[1]
end

-- several lines for the clipboard
function DpsMath.summary(view, idx, maxRows)
  if not view then return '' end
  local t = tabTitle(idx)
  local rows, total = DpsMath.rows(view, idx)
  local lines = {
    tr('DPS Meter - %s (%s)', view.id == 's' and 'Session' or tostring(view.label or 'Fight'),
      DpsMath.duration(view.dur)),
    string.format('%s: %s (%s %s)', t.name, DpsMath.exact(total), DpsMath.exact(DpsMath.perSecond(total, view.dur)), t.rate),
  }
  for i, r in ipairs(rows) do
    if i > (maxRows or 15) then break end
    lines[#lines + 1] = string.format('%2d. %s  %s  %s%%  %s/s  hits %d  crit %d%%  avg %s  max %s', i, r.name,
      DpsMath.exact(r.total), tostring(r.pct), DpsMath.exact(r.rate), r.hits, r.critPct, DpsMath.exact(r.avg),
      DpsMath.exact(r.max))
  end
  return table.concat(lines, '\n')
end

-- one line for the chat input (the player sends it, or not): at most maxLen characters
function DpsMath.chatLine(view, idx, maxLen)
  if not view then return '' end
  maxLen = maxLen or 240
  local t = tabTitle(idx)
  local rows, total = DpsMath.rows(view, idx)
  local line = string.format('[%s] %s %s: %s, %s %s', t.name, view.id == 's' and 'Session' or tostring(view.label or 'Fight'),
    DpsMath.duration(view.dur), DpsMath.short(total), DpsMath.short(DpsMath.perSecond(total, view.dur)), t.rate)
  for _, r in ipairs(rows) do
    local part = string.format(' | %s %s%%', r.name, tostring(r.pct))
    if #line + #part > maxLen then break end
    line = line .. part
  end
  return line
end
