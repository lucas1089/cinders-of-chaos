-- Pure text helpers of the Guild window (tested by guildmath_test.lua; no client calls).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
GuildMath = {}

function GuildMath.money(n)
  n = math.floor(tonumber(n) or 0)
  local s = tostring(math.abs(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  if out:sub(1, 1) == ',' then out = out:sub(2) end
  return (n < 0 and '-' or '') .. out
end

function GuildMath.duration(s)
  s = math.max(0, math.floor(tonumber(s) or 0))
  local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
  if d > 0 then return string.format('%dd %dh', d, h) end
  if h > 0 then return string.format('%dh %dm', h, m) end
  return string.format('%dm', m)
end

-- header line under the guild name and the XP bar text
function GuildMath.levelText(g)
  g = g or {}
  return tr('Guild level %d / %d', tonumber(g.level) or 1, tonumber(g.maxLevel) or 20)
end

function GuildMath.xpText(g)
  g = g or {}
  if (tonumber(g.need) or 0) <= 0 then return tr('Max level') end
  return tr('%s / %s GXP (%d%%)', GuildMath.money(g.into), GuildMath.money(g.need), tonumber(g.pct) or 0)
end

function GuildMath.percent(g)
  g = g or {}
  if (tonumber(g.need) or 0) <= 0 then return 100 end
  return math.max(0, math.min(100, math.floor((tonumber(g.into) or 0) * 100 / g.need)))
end

function GuildMath.perksNow(p)
  p = p or {}
  local parts = {}
  if (tonumber(p.xp) or 0) > 0 then parts[#parts + 1] = '+' .. p.xp .. '% experience' end
  if (tonumber(p.loot) or 0) > 0 then parts[#parts + 1] = '+' .. p.loot .. '% loot' end
  if (tonumber(p.respec) or 0) > 0 then parts[#parts + 1] = 'respec -' .. p.respec .. '%' end
  if (tonumber(p.depotSlots) or 0) > 0 then parts[#parts + 1] = tr('+%s stash slots', p.depotSlots) end
  if p.scroll then parts[#parts + 1] = 'daily hall scroll' end
  if p.aura then parts[#parts + 1] = 'guild aura' end
  if #parts == 0 then return tr('No perks yet: they start at guild level 2.') end
  return table.concat(parts, ', ')
end

function GuildMath.rentText(h)
  h = h or {}
  if not h.owned then return tr('Your guild owns no guild hall.') end
  local rent = tr('%s gold a week', GuildMath.money(h.rent))
  if h.rentState == 'paid' then
    return tr('Rent %s, paid until %s (%s left).', rent, h.paidUntil or '?', GuildMath.duration(h.rentLeft))
  elseif h.rentState == 'grace' then
    return tr('Rent %s is DUE. The upgrades lock in %s.', rent, GuildMath.duration(h.graceLeft))
  end
  return tr('Rent %s is UNPAID: the upgrades are locked until it is paid.', rent)
end

function GuildMath.rentColor(h)
  if not h or h.rentState == 'paid' then return '#9fd68a' end
  if h.rentState == 'grace' then return '#f6cf72' end
  return '#e05a4a'
end

function GuildMath.upgradeText(u)
  u = u or {}
  local tiers = (tonumber(u.max) or 1) > 1 and string.format(' %d/%d', tonumber(u.tier) or 0, u.max) or ''
  local state
  if (tonumber(u.tier) or 0) >= (tonumber(u.max) or 1) then
    state = u.active and 'owned' or tr('owned, locked')
  elseif (tonumber(u.tier) or 0) > 0 then
    state = tr('next: %s gold, level %d', GuildMath.money(u.cost), tonumber(u.level) or 0)
  else
    state = tr('%s gold, guild level %d', GuildMath.money(u.cost), tonumber(u.level) or 0)
  end
  return string.format('%s%s - %s', u.name or '?', tiers, state)
end

function GuildMath.memberText(m)
  m = m or {}
  return tr('%s (%s, level %d)', m.name or '?', m.rank or '?', tonumber(m.level) or 0)
end

function GuildMath.memberPoints(m)
  m = m or {}
  return tr('%s this week / %s', GuildMath.money(m.week), GuildMath.money(m.total))
end

function GuildMath.topText(t)
  t = t or {}
  return tr('%d. %s (level %d)', tonumber(t.rank) or 0, t.name or '?', tonumber(t.level) or 0)
end

-- "5k" / "2.5m" / "1500" -> number, or nil
function GuildMath.parseAmount(s)
  s = tostring(s or ''):lower():gsub(',', ''):gsub('%s', '')
  local n, suffix = s:match('^(%d+%.?%d*)([km]?)$')
  if not n then return nil end
  n = tonumber(n)
  if suffix == 'k' then n = n * 1000 elseif suffix == 'm' then n = n * 1000000 end
  return math.floor(n)
end
