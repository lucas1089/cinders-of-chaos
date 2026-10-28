-- Totals of the passive tree window (O146), no client API, tested by totalsview_test.lua. The server sends
--   statTotals {attributes = [{k, n, raw, eff, cap, effect}], damage = [{k, n, raw, eff, cap}],
--               crit = {chance = {total, tree, other}, amount = {total, tree, paragon, other}}}
-- (server/data/scripts/chaos/passivetree_totals.lua). `raw` is what the nodes give, `eff` what counts after the soft cap
-- (full value up to `cap`, smaller gains without limit past it). The crit rows show the engine's own total, gear included.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
TotalsView = {}
local V = TotalsView

V.HEAD, V.OVER, V.TEXT = '#e8c860', '#f6cf72', '#d8cfc0'

-- 280 -> "280", 221.7 -> "221.7", 20.0 -> "20"
function V.num(v)
  local s = string.format('%.1f', tonumber(v) or 0)
  s = s:gsub('%.0$', '')
  return s
end

local function over(row)
  return (tonumber(row.raw) or 0) > (tonumber(row.cap) or 0)
end

-- the lines of the totals section: {text, color}; empty when the server sent nothing
function V.lines(data)
  local out = {}
  if type(data) ~= 'table' then
    return out
  end
  local function add(text, color) out[#out + 1] = {text = text, color = color or V.TEXT} end
  for _, row in ipairs(data.attributes or {}) do
    if over(row) then
      add(tr('%s: %s points -> %s effective (full value up to %s)', row.n or row.k, V.num(row.raw), V.num(row.eff), V.num(row.cap)), V.OVER)
    else
      add(tr('%s: %s points (full value up to %s)', row.n or row.k, V.num(row.raw), V.num(row.cap)))
    end
  end
  for _, row in ipairs(data.damage or {}) do
    if over(row) then
      add(tr('%s: +%s%% -> +%s%% effective (full value up to +%s%%)', row.n or row.k, V.num(row.raw), V.num(row.eff), V.num(row.cap)), V.OVER)
    else
      add(tr('%s: +%s%% (full value up to +%s%%)', row.n or row.k, V.num(row.raw), V.num(row.cap)))
    end
  end
  local c = data.crit
  if type(c) == 'table' and type(c.chance) == 'table' and type(c.amount) == 'table' then
    add(tr('Critical chance: %s%% (tree %s%%, gear and other %s%%)', V.num(c.chance.total), V.num(c.chance.tree), V.num(c.chance.other)), V.HEAD)
    add(tr('Critical damage: +%s%% (tree %s%%, Paragon %s%%, gear and other %s%%)', V.num(c.amount.total), V.num(c.amount.tree),
      V.num(c.amount.paragon), V.num(c.amount.other)), V.HEAD)
  end
  local a = data.attackSpeed
  if type(a) == 'table' and tonumber(a.total) then
    add(tr('Attack speed: +%s%% (tree %s%%, gear %s%%; at most 1 attack per second)', V.num(a.total), V.num(a.tree), V.num(a.gear)), V.HEAD)
  end
  return out
end
