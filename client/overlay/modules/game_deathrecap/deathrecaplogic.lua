-- Death recap, pure parts (no UI calls): settings, number and time formats (short numbers by the rule of
-- client_chaos_numbers formatShortNumber, the one the damage numbers use), the attacker rows (share, bar length, crit
-- rate, element split sorted with colours), the killing blow, the header lines, the timeline of the last hits and the
-- history list. Tested by deathrecaplogic_test.lua (luajit and lua5.3). Data comes from the server
-- (server/data/scripts/chaos/deathrecap_core.lua R.build).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

DeathRecapLogic = {}
local L = DeathRecapLogic

L.DEFAULTS = { autoOpen = true }

-- element names and colours (the damage colours of the game's text effects, darkened for bars on the dark panels)
L.ELEMENTS = {
  physical = { name = 'Physical', color = '#a8a090' },
  fire = { name = 'Fire', color = '#e0602a' },
  earth = { name = 'Earth', color = '#5aa83a' },
  energy = { name = 'Energy', color = '#a050e0' },
  ice = { name = 'Ice', color = '#5ab0e0' },
  holy = { name = 'Holy', color = '#e8d070' },
  death = { name = 'Death', color = '#7a3a8a' },
  drown = { name = 'Drown', color = '#3a70c0' },
  lifedrain = { name = 'Life drain', color = '#c02a3a' },
  manadrain = { name = 'Mana drain', color = '#4a5ad0' },
  other = { name = 'Other', color = '#6b6258' },
}
L.KIND_NAMES = { c = 'Monster', u = 'Player', s = 'Yourself', e = 'Environment', h = 'Hidden', o = 'Others' }
L.KIND_COLORS = { c = '#f2e8d0', u = '#f6cf72', s = '#a8a090', e = '#a8a090', h = '#8c8070', o = '#8c8070' }

local function num(v)
  v = tonumber(v)
  if v and v == v and v ~= math.huge and v ~= -math.huge then return v end
  return nil
end

function L.sanitize(node)
  node = type(node) == 'table' and node or {}
  local s = {}
  if type(node.autoOpen) == 'boolean' then s.autoOpen = node.autoOpen else s.autoOpen = L.DEFAULTS.autoOpen end
  return s
end

-- ---------------------------------------------------------------- formats
function L.short(n)
  n = num(n) or 0
  if formatShortNumber then return formatShortNumber(math.floor(n)) end
  return tostring(math.floor(n))
end

function L.exact(n)
  n = math.floor(num(n) or 0)
  if formatExactNumber then return formatExactNumber(n) end
  local s = tostring(math.abs(n)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return (n < 0 and '-' or '') .. s
end

function L.percent(part, total)
  total = num(total) or 0
  if total <= 0 then return 0 end
  local v = math.floor((num(part) or 0) * 1000 / total + 0.5) / 10
  if v == math.floor(v) then return math.floor(v) end
  return v
end

-- ms -> "0.8 s", "12.4 s", "1:05"
function L.seconds(ms)
  ms = math.max(0, math.floor(num(ms) or 0))
  if ms < 60000 then
    local tenths = math.floor(ms / 100)
    return string.format('%d.%d s', math.floor(tenths / 10), tenths % 10)
  end
  local s = math.floor(ms / 1000)
  return string.format('%d:%02d', math.floor(s / 60), s % 60)
end

-- unix time -> "12 Oct 21:04" (local time of the client)
function L.clock(at)
  at = num(at)
  if not at or at <= 0 then return '?' end
  local ok, text = pcall(os.date, '%d %b %H:%M', math.floor(at))
  return ok and text or '?'
end

function L.elementName(el)
  local e = L.ELEMENTS[el or 'other'] or L.ELEMENTS.other
  return e.name
end

function L.elementColor(el)
  local e = L.ELEMENTS[el or 'other'] or L.ELEMENTS.other
  return e.color
end

-- an attacker's shown name: "War Wolf (Varek)" for a summon
function L.displayName(n, m)
  n = (type(n) == 'string' and n ~= '') and n or 'Unknown'
  if type(m) == 'string' and m ~= '' then return n .. ' (' .. m .. ')' end
  return n
end

-- ---------------------------------------------------------------- outfit
local OUTFIT_FIELDS = { type = 65535, auxType = 65535, head = 255, body = 255, legs = 255, feet = 255, addons = 3 }
function L.outfit(look)
  if type(look) ~= 'table' then return nil end
  local out = {}
  for k, top in pairs(OUTFIT_FIELDS) do
    local v = math.floor(num(look[k]) or 0)
    out[k] = (v >= 0 and v <= top) and v or 0
  end
  if out.type == 0 and out.auxType == 0 then return nil end
  return out
end

-- ---------------------------------------------------------------- elements, rows
-- {[element] = amount} -> [{key, name, color, amount, pct}] largest first
function L.elements(el)
  local out = {}
  if type(el) ~= 'table' then return out end
  local total = 0
  for k, v in pairs(el) do
    local a = num(v) or 0
    if type(k) == 'string' and a > 0 then
      total = total + a
      out[#out + 1] = { key = k, name = L.elementName(k), color = L.elementColor(k), amount = a }
    end
  end
  table.sort(out, function(a, b)
    if a.amount ~= b.amount then return a.amount > b.amount end
    return a.key < b.key
  end)
  for _, e in ipairs(out) do e.pct = L.percent(e.amount, total) end
  return out
end

-- the attacker rows of a recap, most damage first, "Others" last: {name, kind, kindName, color, total, hp, mp, hits,
-- crits, critPct, max, pct (share of all damage shown), frac (bar, the top row = 1), elements, outfit, elText}
function L.rows(recap)
  local out = {}
  if type(recap) ~= 'table' or type(recap.att) ~= 'table' then return out end
  local total = num(recap.tot) or 0
  local top = 0
  for _, a in ipairs(recap.att) do
    if type(a) == 'table' then
      local hits, crits = num(a.h) or 0, num(a.c) or 0
      local row = {
        name = L.displayName(a.n, a.m), kind = a.kind or 'c', total = num(a.tot) or 0, hp = num(a.hp) or 0,
        mp = num(a.mp) or 0, hits = hits, crits = crits, max = num(a.x) or 0,
        critPct = hits > 0 and math.floor(crits * 100 / hits + 0.5) or 0,
        elements = L.elements(a.el), outfit = L.outfit(a.look),
      }
      row.kindName = L.KIND_NAMES[row.kind] or L.KIND_NAMES.c
      row.color = L.KIND_COLORS[row.kind] or L.KIND_COLORS.c
      if row.total > top then top = row.total end
      out[#out + 1] = row
    end
  end
  table.sort(out, function(a, b)
    if (a.kind == 'o') ~= (b.kind == 'o') then return b.kind == 'o' end
    if a.total ~= b.total then return a.total > b.total end
    return a.name < b.name
  end)
  for _, r in ipairs(out) do
    r.pct = L.percent(r.total, total)
    r.frac = top > 0 and r.total / top or 0
    local parts = {}
    for i, e in ipairs(r.elements) do
      if i > 4 then break end
      parts[#parts + 1] = string.format('%s %s', e.name, L.short(e.amount))
    end
    r.elText = table.concat(parts, ', ')
  end
  return out
end

-- ---------------------------------------------------------------- header, killing blow, timeline
function L.killingBlow(recap)
  local kb = type(recap) == 'table' and type(recap.kb) == 'table' and recap.kb or {}
  local name = L.displayName(kb.n, kb.m)
  local a = num(kb.a)
  if not a or a <= 0 then return tr('Killing blow: %s', name) end
  return tr('Killing blow: %s, %s %s%s%s', name, L.exact(a), L.elementName(kb.el):lower(),
    kb.c == 1 and ' (critical)' or '', kb.mp == 1 and ' (mana)' or '')
end

-- {title, sub, loss, window, totals}
function L.header(recap)
  recap = type(recap) == 'table' and recap or {}
  local kb = type(recap.kb) == 'table' and recap.kb or {}
  local defeat = recap.real == 0
  local who = L.displayName(kb.n, kb.m)
  local h = {}
  if defeat then
    h.title = tr('Defeated by %s', who)
  else
    h.title = tr('Killed by %s', who)
  end
  local sub = { L.clock(recap.at) }
  if num(recap.lvl) then sub[#sub + 1] = string.format('level %d', num(recap.lvl)) end
  if type(recap.mode) == 'string' and recap.mode ~= '' then sub[#sub + 1] = recap.mode end
  if recap.pvp == 1 then sub[#sub + 1] = 'PvP' end
  h.sub = table.concat(sub, ', ')
  local xl, ll = num(recap.xl), num(recap.ll)
  if defeat then
    h.loss = 'Nothing lost'
  elseif not xl then
    h.loss = 'Experience lost: shown at your next login'
  elseif xl <= 0 and (ll or 0) <= 0 then
    h.loss = 'No experience lost'
  else
    h.loss = string.format('Lost %s experience', L.short(xl))
    if ll and ll > 0 then h.loss = h.loss .. string.format(' and %d level%s', ll, ll == 1 and '' or 's') end
  end
  local tot, hp, mp = num(recap.tot) or 0, num(recap.hp) or 0, num(recap.mp) or 0
  if tot <= 0 then
    h.window = 'No hits recorded before the death'
    h.totals = ''
  else
    h.window = tr('Last %s before the death, %d hit%s', L.seconds(recap.dur), num(recap.nh) or 0,
      (num(recap.nh) or 0) == 1 and '' or 's')
    h.totals = tr('Damage taken: %s', L.short(tot))
    if mp > 0 then h.totals = h.totals .. string.format(' (health %s, mana %s)', L.short(hp), L.short(mp)) end
  end
  return h
end

-- the last hits, oldest first: [{time ("-1.2 s", or "death" for a hit within DEATH_MS of it), name, amount, element,
-- color, crit, mana, text}]
L.DEATH_MS = 100
function L.timeline(recap)
  local out = {}
  if type(recap) ~= 'table' or type(recap.last) ~= 'table' then return out end
  for _, h in ipairs(recap.last) do
    if type(h) == 'table' then
      local dt = num(h.dt) or 0
      local e = {
        time = dt < L.DEATH_MS and 'death' or ('-' .. L.seconds(dt)), name = L.displayName(h.n), amount = num(h.a) or 0,
        element = L.elementName(h.el), color = L.elementColor(h.el), crit = h.c == 1, mana = h.mp == 1,
      }
      e.text = string.format('%s  %s  %s %s%s%s', e.time, e.name, L.exact(e.amount), e.element:lower(),
        e.crit and ' (critical)' or '', e.mana and ' (mana)' or '')
      out[#out + 1] = e
    end
  end
  return out
end

-- the history list (the server's order, newest first): [{id, title, sub, selected}]
function L.historyRows(list, sel)
  local out = {}
  for _, s in ipairs(type(list) == 'table' and list or {}) do
    if type(s) == 'table' and num(s.id) then
      local sub
      if s.real == 0 then
        sub = (type(s.mode) == 'string' and s.mode ~= '') and s.mode or 'Defeat'
      elseif num(s.xl) and num(s.xl) > 0 then
        sub = string.format('-%s exp', L.short(s.xl))
        if num(s.ll) and num(s.ll) > 0 then sub = sub .. string.format(', -%d lvl', num(s.ll)) end
      else
        sub = num(s.lvl) and string.format('Level %d', num(s.lvl)) or ''
      end
      out[#out + 1] = { id = num(s.id), title = L.clock(s.at), sub = sub, killer = L.displayName(s.k),
        selected = num(sel) == num(s.id) }
    end
  end
  return out
end

-- the bar segments of a row: [{color, frac}] in the order of the elements (fractions of the row's own bar)
function L.segments(row)
  local out = {}
  if type(row) ~= 'table' or (row.total or 0) <= 0 then return out end
  for _, e in ipairs(row.elements or {}) do
    out[#out + 1] = { color = e.color, frac = e.amount / row.total }
  end
  return out
end
