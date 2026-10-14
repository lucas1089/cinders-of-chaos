-- Pure text helpers of the Guild Wars window (game_guildwar; tested by guildwarview_test.lua, no client calls).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
GuildWarView = {}
local V = GuildWarView

function V.money(n)
  n = math.floor(tonumber(n) or 0)
  local s = tostring(math.abs(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  if out:sub(1, 1) == ',' then out = out:sub(2) end
  return (n < 0 and '-' or '') .. out
end

function V.duration(s)
  s = math.max(0, math.floor(tonumber(s) or 0))
  local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
  if d > 0 then return string.format('%dd %dh', d, h) end
  if h > 0 then return string.format('%dh %dm', h, m) end
  return string.format('%dm', m)
end

-- a duration option: "6 hours", "1 day", "3 days"
function V.hoursText(h)
  h = math.floor(tonumber(h) or 0)
  if h >= 24 and h % 24 == 0 then
    local d = h / 24
    return string.format('%d day%s', d, d == 1 and '' or 's')
  end
  return string.format('%d hour%s', h, h == 1 and '' or 's')
end

function V.clock(s)
  s = math.max(0, math.floor(tonumber(s) or 0))
  return string.format('%d:%02d', math.floor(s / 60), s % 60)
end

-- "5k" / "2.5m" / "1,500,000" -> number, '' / '0' -> 0, else nil
function V.parseAmount(s)
  s = tostring(s or ''):lower():gsub(',', ''):gsub('%s', '')
  if s == '' then return 0 end
  local n, suffix = s:match('^(%d+%.?%d*)([km]?)$')
  if not n then return nil end
  n = tonumber(n)
  if suffix == 'k' then n = n * 1000 elseif suffix == 'm' then n = n * 1000000 end
  return math.floor(n)
end

-- what the winner of a war with `stake` per side gets (both stakes minus the fee percent)
function V.winnings(stake, fee)
  local pot = 2 * math.max(0, math.floor(tonumber(stake) or 0))
  return pot - math.floor(pot * (tonumber(fee) or 0) / 100)
end

function V.stakeText(stake, fee)
  stake = tonumber(stake) or 0
  if stake <= 0 then return tr('no stake') end
  return tr('%s gold per side (the winner gets %s)', V.money(stake), V.money(V.winnings(stake, fee)))
end

-- form = {target, fragLimit, hours, stake (text)}; options from the server. Returns the request data or nil, why.
function V.declareRequest(form, options)
  options = options or {}
  local target = tostring(form.target or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if target == '' then return nil, tr('Type the name of the guild.') end
  local stake = V.parseAmount(form.stake)
  if not stake then return nil, tr('The stake is a number of gold (500k, 2m, ...).') end
  if stake > 0 and stake < (tonumber(options.stakeMin) or 0) then
    return nil, tr('A stake is at least %s gold (or none).', V.money(options.stakeMin))
  end
  if options.stakeMax and stake > options.stakeMax then
    return nil, tr('A stake is at most %s gold.', V.money(options.stakeMax))
  end
  local frag, hours = tonumber(form.fragLimit), tonumber(form.hours)
  if not frag or not hours then return nil, tr('Pick a frag limit and a duration.') end
  return { target = target, fragLimit = frag, hours = hours, stake = stake }
end

function V.declareSummary(req, options)
  if not req then return '' end
  return tr('War on %s: first to %d counted kills within %d hours, %s.', req.target, req.fragLimit, req.hours,
    V.stakeText(req.stake, options and options.fee))
end

-- a war row of the server (guildwar_core.lua C.row)
function V.title(w)
  w = w or {}
  return string.format('%s vs %s', tostring(w.own or '?'), tostring(w.enemy or '?'))
end

function V.score(w)
  w = w or {}
  return string.format('%d : %d', tonumber(w.ownKills) or 0, tonumber(w.enemyKills) or 0)
end

function V.status(w)
  w = w or {}
  if w.status == 'pending' then
    if w.incoming then return tr('Declared on you: answer within %s', V.duration(w.left)) end
    return tr('Offer sent: waiting %s for the answer', V.duration(w.left))
  elseif w.status == 'active' then
    return tr('%s (first to %d), ends in %s', V.score(w), tonumber(w.fragLimit) or 0, V.duration(w.left))
  end
  local r = w.result or w.status or ''
  local word = ({ won = 'Won', lost = 'Lost', draw = 'Draw', declined = 'Declined', cancelled = 'Taken back',
    expired = 'Expired' })[r] or r
  if w.status == 'ended' then
    return string.format('%s %s - %s', word, V.score(w), tostring(w.reason or ''))
  end
  return word
end

function V.color(w)
  w = w or {}
  if w.status == 'pending' then return w.incoming and '#f6cf72' or '#d6c9ae' end
  if w.status == 'active' then return '#e05a4a' end
  if w.result == 'won' then return '#9fd68a' end
  if w.result == 'lost' then return '#e05a4a' end
  return '#8c8070'
end

-- the server board: the declarer's name first
function V.boardLine(w)
  w = w or {}
  local s = string.format('%s %d : %d %s', tostring(w.own or '?'), tonumber(w.ownKills) or 0, tonumber(w.enemyKills) or 0,
    tostring(w.enemy or '?'))
  if w.status == 'active' then
    return s .. tr(' (first to %d, %s left)', tonumber(w.fragLimit) or 0, V.duration(w.left))
  end
  return s .. ' - ' .. tostring(w.reason or '')
end

-- a kill of the war log
function V.killLine(k)
  k = k or {}
  return string.format('%s %s killed %s (level %d)%s', tostring(k.at or ''), tostring(k.killer or '?'), tostring(k.victim or '?'),
    tonumber(k.level) or 0, k.counted and '' or (tr(' - not counted: %s', tostring(k.reason or ''))))
end

-- ---------------------------------------------------------------- the guild boss
function V.fuelPercent(b)
  b = b or {}
  local need = tonumber(b.need) or 0
  if need <= 0 then return 0 end
  return math.max(0, math.min(100, math.floor((tonumber(b.fuel) or 0) * 100 / need)))
end

function V.fuelText(b)
  b = b or {}
  return tr('%s / %s embers (%d%%)', V.money(b.fuel), V.money(b.need), V.fuelPercent(b))
end

function V.bossState(b)
  b = b or {}
  if not b.guild then return tr('Join a guild to fight the guild boss.'), '#8c8070' end
  if b.killed then
    return tr('Slain this week in %s. The stone rests until the reset (%s).', V.clock(b.bestSeconds),
      V.duration(b.resetIn)), '#9fd68a'
  end
  if b.running then return tr('Your guild is fighting the guild boss now.'), '#f6cf72' end
  if b.canSummon then return tr('The stone is full: summon the guild boss.'), '#f6cf72' end
  return tostring(b.reason or ''), '#8c8070'
end

function V.attemptsText(b)
  b = b or {}
  return tr('Summons this week: %d of %d', tonumber(b.attempts) or 0, tonumber(b.maxAttempts) or 0)
end

function V.bannerText(bn)
  bn = bn or {}
  if (tonumber(bn.tier) or 0) <= 0 then
    return tr('No guild banner yet: the first kill raises the Ember Banner.')
  end
  local k = tonumber(bn.kills) or 0
  local s = string.format('%s (%d kill%s)', tostring(bn.name or ''), k, k == 1 and '' or 's')
  if (tonumber(bn.next) or 0) > 0 then s = s .. tr(', next tier at %d', bn.next) end
  return s
end

function V.goldEmbers(amount, perEmber)
  local n = V.parseAmount(amount)
  perEmber = tonumber(perEmber) or 0
  if not n or perEmber <= 0 then return 0 end
  return math.floor(n / perEmber)
end

function V.bossBoardLine(r)
  r = r or {}
  if r.killed then
    return tr('%d. %s - slain in %s by %d', tonumber(r.rank) or 0, tostring(r.name or '?'), V.clock(r.seconds),
      tonumber(r.players) or 0)
  end
  return string.format('%d. %s - %s damage', tonumber(r.rank) or 0, tostring(r.name or '?'), V.money(r.damage))
end

function V.contributorLine(c)
  c = c or {}
  return string.format('%s: %s embers%s', tostring(c.name or '?'), V.money(c.embers),
    (tonumber(c.gold) or 0) > 0 and string.format(' (%s gold)', V.money(c.gold)) or '')
end

-- a member's share of the kill's gold pool: 'Vex: 2,250,000 gold (30%)'
function V.spoilsLine(sp, pool)
  sp = sp or {}
  local gold, total = tonumber(sp.gold) or 0, tonumber(pool) or 0
  local pct = total > 0 and math.floor(gold * 100 / total + 0.5) or 0
  return tr('%s: %s gold (%d%%)', tostring(sp.name or '?'), V.money(gold), pct)
end
