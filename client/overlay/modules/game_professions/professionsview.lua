-- Professions window texts and rules (pure, no UI calls): shared by professions.lua and professionsview_test.lua.
-- `s` is the server's state (server data/scripts/chaos/professions_core.lua K.payload):
--   profs  = {{k, n, lv, xp, need, pct, tier, tool, d, g}}          the four professions
--   bonus, cap, per                                                 the experience bonus now, its cap, % per level
--   tiers  = {{n, p, c, g, col}}                                    name, profession level, character level, price, colour
--   demand = {{id, c, n, p, t, m, g, l, s, h}}                      per material: server id, client id, name, profession,
--                                                                   tier, multiplier, price, late price, sold today, held
--   areas  = {{n, t, f, m, near, x, y, z, nodes = {{k, r, t}}}}     where to gather: ready / total nodes for you
--   broker, full, capDay, late, nextDay, nextWeek, respawn          at a broker; the daily rule; seconds to the next day / week
-- The sale rule here mirrors the server's (professions_core.lua K.quote) for the estimates; the server decides.

ProfessionsView = ProfessionsView or {}
local V = ProfessionsView

V.COLORS = { gold = '#e8b84a', text = '#d8ccb4', dim = '#8c8070', good = '#8fd16a', bad = '#e07060', warn = '#e0a050',
  up = '#8fd16a', down = '#e07060', even = '#d8ccb4' }
V.ORDER = { 'delving', 'wortcunning', 'flaying', 'angling' }

local function num(v) return tonumber(v) or 0 end

-- 1234567 -> "1,234,567"
function V.fmtNum(n)
  n = math.floor(num(n))
  local s = tostring(math.abs(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return (n < 0 and '-' or '') .. out
end

-- 2.5 -> "2.5", 10 -> "10", 0.0253 -> "0.0253" (small numbers keep 4 decimals)
function V.fmtPct(v)
  v = num(v)
  local s = string.format(math.abs(v) < 0.1 and '%.4f' or '%.2f', v):gsub('0+$', ''):gsub('%.$', '')
  return s
end

function V.timeText(sec)
  sec = math.max(0, math.floor(num(sec)))
  local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
  if d > 0 then return string.format('%dd %dh', d, h) end
  if h > 0 then return string.format('%dh %dm', h, m) end
  return string.format('%dm', math.max(1, m))
end

function V.profName(s, key)
  for _, p in ipairs(s and s.profs or {}) do
    if p.k == key then return p.n end
  end
  return key
end

function V.tier(s, t)
  return (s and s.tiers or {})[num(t)] or { n = 'Tier ' .. tostring(t), col = V.COLORS.text }
end

function V.bonusText(s)
  if not s then return '' end
  return string.format('Experience bonus: +%s%% from monsters (every profession level above 1 adds %s%%, at most +%s%%)',
    V.fmtPct(s.bonus), V.fmtPct(s.per), V.fmtPct(s.cap))
end

-- one line per profession: {key, name, level, xpText, pct, tierText, tierColor, tool, desc, gathered}
function V.profRows(s)
  local out = {}
  for _, p in ipairs(s and s.profs or {}) do
    local t = V.tier(s, p.tier)
    out[#out + 1] = {
      key = p.k, name = p.n, level = num(p.lv),
      xpText = num(p.need) > 0 and string.format('%s / %s', V.fmtNum(p.xp), V.fmtNum(p.need)) or 'Mastered',
      pct = num(p.need) > 0 and math.max(0, math.min(100, num(p.pct))) or 100,
      tierText = 'Gathers ' .. t.n:lower() .. ' materials', tierColor = t.col or V.COLORS.text,
      tool = p.tool or '', desc = p.d or '', gathered = num(p.g)
    }
  end
  return out
end

function V.multText(m)
  m = num(m)
  if m > 1.001 then return 'x' .. V.fmtPct(m), V.COLORS.up end
  if m < 0.999 then return 'x' .. V.fmtPct(m), V.COLORS.down end
  return 'x1', V.COLORS.even
end

-- what selling `count` of a demand row brings now (mirror of K.quote): {units, gold}
function V.quote(s, row, count)
  local full, cap = num(s and s.full), num(s and s.capDay)
  local sold = num(row.s)
  count = math.max(0, math.floor(num(count)))
  local units = math.min(count, math.max(0, cap - sold))
  local atFull = math.min(units, math.max(0, full - sold))
  return { units = units, gold = atFull * num(row.g) + (units - atFull) * num(row.l) }
end

function V.canSell(s, row)
  return s ~= nil and s.broker == true and num(row.h) > 0 and num(row.s) < num(s.capDay)
end

-- demand rows of one profession (or every one when key is nil), by profession order then tier; each with texts
function V.demandRows(s, key)
  local out = {}
  local order = {}
  for i, k in ipairs(V.ORDER) do order[k] = i end
  for _, d in ipairs(s and s.demand or {}) do
    if not key or key == '' or d.p == key then
      local mt, mc = V.multText(d.m)
      local q = V.quote(s, d, d.h)
      out[#out + 1] = {
        id = d.id, clientId = num(d.c), name = d.n, prof = d.p, tier = num(d.t), tierColor = V.tier(s, d.t).col,
        priceText = V.fmtNum(d.g) .. ' gold', multText = mt, multColor = mc,
        soldText = string.format('%d / %d today', num(d.s), num(s.capDay)),
        haveText = V.fmtNum(d.h) .. ' carried',
        worth = q.gold, units = q.units, canSell = V.canSell(s, d), raw = d
      }
    end
  end
  table.sort(out, function(a, b)
    local oa, ob = order[a.prof] or 9, order[b.prof] or 9
    if oa ~= ob then return oa < ob end
    return a.tier < b.tier
  end)
  return out
end

-- what "Sell all" would bring now: {units, gold}
function V.sellAllEstimate(s)
  local units, gold = 0, 0
  for _, d in ipairs(s and s.demand or {}) do
    local q = V.quote(s, d, d.h)
    units, gold = units + q.units, gold + q.gold
  end
  return { units = units, gold = gold }
end

-- the hot materials of the week: multipliers above 1, best first
function V.hotList(s)
  local out = {}
  for _, d in ipairs(s and s.demand or {}) do
    if num(d.m) > 1.001 then out[#out + 1] = d end
  end
  table.sort(out, function(a, b)
    if num(a.m) ~= num(b.m) then return num(a.m) > num(b.m) end
    return num(a.g) > num(b.g)
  end)
  return out
end

-- where to gather, one entry per area: {title, text, color}
function V.areaLines(s)
  local out = {}
  for _, a in ipairs(s and s.areas or {}) do
    local t = V.tier(s, a.t)
    local parts = {}
    for _, n in ipairs(a.nodes or {}) do
      if n.k == 'angling' then
        parts[#parts + 1] = 'fishing'
      else
        parts[#parts + 1] = string.format('%s %d/%d ready', V.profName(s, n.k), num(n.r), num(n.t))
      end
    end
    local where = a.near and ('near ' .. a.near) or ''
    out[#out + 1] = {
      title = string.format('%s (%s)', a.n, t.n), color = t.col or V.COLORS.text,
      text = (#parts > 0 and table.concat(parts, ', ') or 'no nodes') .. (where ~= '' and ('; ' .. where) or ''),
      tip = string.format('%s%s\nPosition %d, %d, %d', a.n, a.m and (': hunting ground of ' .. a.m) or '', num(a.x),
        num(a.y), num(a.z)),
      monsters = a.m
    }
  end
  return out
end

function V.footer(s)
  if not s then return '' end
  local rule = string.format('Full price for %d a day per material, then %s%% up to %d.', num(s.full),
    V.fmtPct(num(s.late) * 100), num(s.capDay))
  return rule .. string.format(' New day in %s, new demand in %s.', V.timeText(s.nextDay), V.timeText(s.nextWeek))
end

return V
