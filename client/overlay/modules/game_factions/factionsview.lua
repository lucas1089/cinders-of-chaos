-- Pure helpers of the Factions window (no client API), tested by factionsview_test.lua.
-- The data comes from the server (server/data/scripts/chaos/factions_core.lua K.payload):
--   {now, nextDay, nextWeek, weekCap, gold, sel, ranks = [{k, n, min, c}],
--    factions = [{k, n, s, c, lore, rival, rep, rank, rn, rc, lo, hi, pct, nx, wk, dy, dr, ex, npc, near, tok, tn, tid, theme}],
--    contracts = [{key, f, per = "d" | "w", kind, label, p, n, rep, done, give}],
--    offers = [{key, f, kind, n, rank, rn, price, tokens, st = "ok" | "locked" | "owned" | "soldout", why, wl, wb, item,
--               lv, rar, mods, desc, craft}]}
FactionsView = {}
local V = FactionsView

V.COLORS = {
  ok = '#6fd86f',
  locked = '#8c8070',
  owned = '#7fb8e8',
  soldout = '#e05a3a',
  done = '#6fd86f',
  daily = '#e8b84a',
  weekly = '#b98ae8',
  rival = '#e05a3a',
  dim = '#8c8070',
}

local function num(v) return tonumber(v) or 0 end
local function list(v) return type(v) == 'table' and v or {} end
-- the rows of a server list; an entry that is no table is left out (game_chaosguard/opcode_fuzz_test.lua)
local function rows(v)
  local out = {}
  for _, r in ipairs(list(v)) do
    if type(r) == 'table' then out[#out + 1] = r end
  end
  return out
end

-- 1234567 -> "1,234,567"; -2500 -> "-2,500"
function V.fmt(n)
  n = math.floor(num(n))
  local neg = n < 0
  local s = tostring(math.abs(n)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return (neg and '-' or '') .. s
end

-- 93784 -> "1d 2h", 4980 -> "1h 23m", 125 -> "2m", 9 -> "1m"
function V.countdown(seconds)
  seconds = math.max(0, math.floor(num(seconds)))
  local d, h = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
  local m = math.floor(seconds % 3600 / 60)
  if d > 0 then return string.format('%dd %dh', d, h) end
  if h > 0 then return string.format('%dh %02dm', h, m) end
  return string.format('%dm', math.max(1, m))
end

-- the card's name: without a leading "The" (the cards are narrow)
function V.cardName(f)
  return (tostring(f and (f.n or f.k) or ''):gsub('^The ', ''))
end

function V.faction(data, key)
  for _, f in ipairs(rows(data and data.factions)) do
    if f.k == key then return f end
  end
  return nil
end

-- the faction to show: the one the server asked for (an NPC), the one shown before, else the first
function V.select(data, current)
  if data and data.sel and V.faction(data, data.sel) then return data.sel end
  if current and V.faction(data, current) then return current end
  local first = rows(data and data.factions)[1]
  return first and first.k or nil
end

-- the rank bar: text inside and the percent
function V.barText(f)
  if not f then return '' end
  if f.ex and num(f.rep) >= num(f.hi) then
    return string.format('%s  %s', f.rn or '', V.fmt(f.rep))
  end
  if not f.nx then
    return string.format('%s  %s', f.rn or '', V.fmt(f.rep))
  end
  return string.format('%s  %s / %s', f.rn or '', V.fmt(f.rep), V.fmt(f.hi))
end

function V.barPercent(f)
  return math.max(0, math.min(100, math.floor(num(f and f.pct))))
end

function V.nextText(f)
  if not f or not f.nx then return 'The highest rank.' end
  return string.format('%s more to %s', V.fmt(num(f.hi) - num(f.rep)), f.nx)
end

function V.weekText(f, cap)
  return string.format('This week %s / %s', V.fmt(f and f.wk), V.fmt(cap))
end

-- what the next activity point is worth today (contracts are not reduced)
function V.drText(f)
  local m = num(f and f.dr)
  if m >= 1 then return 'Kills, tokens and events at full value today' end
  if m >= 0.5 then return 'Kills, tokens and events at half value today' end
  if m > 0 then return string.format('Kills, tokens and events at %d%% today', math.floor(m * 100 + 0.5)) end
  return 'No more reputation from activity today'
end

function V.capped(f, cap)
  return f ~= nil and num(f.wk) >= num(cap) and num(cap) > 0
end

function V.rivalText(data, f)
  local r = f and f.rival and V.faction(data, f.rival)
  if not r then return '' end
  return string.format('Rival: %s. Every gain here costs them a quarter of it (not below Wary, never once they hold you Exalted).', r.n)
end

function V.tokenText(f)
  if not f then return '' end
  return string.format('%d %s carried', num(f.tok), f.tn or 'tokens')
end

-- the Turn in button: enabled, tooltip
function V.tokenButton(f, cap)
  if not f then return false, '' end
  if num(f.tok) <= 0 then return false, string.format('Bring %s from %s content.', f.tn or 'tokens', f.s or f.n) end
  if not f.near then return false, string.format('Speak with %s to turn them in.', f.npc or 'the faction NPC') end
  if V.capped(f, cap) or f.ex and num(f.rep) >= num(f.hi) then
    return false, 'No more reputation this week: keep them.'
  end
  return true, string.format('Give every %s to %s.', f.tn or 'token', f.npc or 'the NPC')
end

-- contracts of one faction: daily first, open ones first, then by key
function V.contractsFor(data, key)
  local out = {}
  for _, c in ipairs(rows(data and data.contracts)) do
    if c.f == key then out[#out + 1] = c end
  end
  table.sort(out, function(a, b)
    if (a.per == 'd') ~= (b.per == 'd') then return a.per == 'd' end
    if (a.done and true or false) ~= (b.done and true or false) then return not a.done end
    return tostring(a.key) < tostring(b.key)
  end)
  return out
end

function V.contractTag(c)
  if c.per == 'w' then return 'Weekly', V.COLORS.weekly end
  return 'Daily', V.COLORS.daily
end

function V.progressText(c)
  if c.done then return 'Done' end
  if c.kind == 'deliver' then return 'Bring it to the NPC' end
  return string.format('%s / %s', V.fmt(c.p), V.fmt(c.n))
end

function V.progressPercent(c)
  if c.done then return 100 end
  if num(c.n) <= 0 then return 0 end
  return math.max(0, math.min(100, math.floor(num(c.p) * 100 / num(c.n))))
end

-- the Deliver button of a delivery contract: shown, enabled, tooltip
function V.deliverButton(c, f)
  if c.kind ~= 'deliver' or c.done then return false, false, '' end
  if not (f and f.near) then return true, false, string.format('Speak with %s to deliver.', f and f.npc or 'the NPC') end
  return true, true, 'Hand over the materials and the gold.'
end

function V.contractsSummary(data, key)
  local open, done = 0, 0
  for _, c in ipairs(V.contractsFor(data, key)) do
    if c.done then done = done + 1 else open = open + 1 end
  end
  return open, done
end

-- quartermaster offers of one faction, by rank then price
function V.offersFor(data, key)
  local out = {}
  for _, o in ipairs(rows(data and data.offers)) do
    if o.f == key then out[#out + 1] = o end
  end
  table.sort(out, function(a, b)
    if num(a.rank) ~= num(b.rank) then return num(a.rank) < num(b.rank) end
    if num(a.price) ~= num(b.price) then return num(a.price) < num(b.price) end
    return tostring(a.key) < tostring(b.key)
  end)
  return out
end

function V.priceText(o, f)
  local parts = {}
  if num(o.price) > 0 then parts[#parts + 1] = V.fmt(o.price) .. ' gold' end
  if num(o.tokens) > 0 then
    parts[#parts + 1] = string.format('%d %s', num(o.tokens), f and f.tn or 'tokens')
  end
  if #parts == 0 then return 'Free' end
  return table.concat(parts, ' + ')
end

-- the offer's button: text, enabled, colour of the state line, tooltip
function V.offerButton(o, f)
  local near = f and f.near
  local who = f and f.npc or 'the quartermaster'
  if o.st == 'locked' then return 'Locked', false, V.COLORS.locked, o.why or '' end
  if o.st == 'soldout' then return 'Sold out', false, V.COLORS.soldout, o.why or '' end
  if o.st == 'owned' then
    if o.kind == 'recipe' then
      if not near then return 'Craft', false, V.COLORS.owned, string.format('Speak with %s to craft.', who) end
      return 'Craft', true, V.COLORS.owned, 'Craft once with the materials shown.'
    end
    return 'Owned', false, V.COLORS.owned, o.why or ''
  end
  if not near then return 'Buy', false, V.COLORS.ok, string.format('Speak with %s to buy.', who) end
  return 'Buy', true, V.COLORS.ok, 'Buy it now.'
end

function V.offerKindText(o)
  if o.kind == 'gear' then
    return string.format('Item level %d, %s', num(o.lv), V.rarityName(o.rar))
  elseif o.kind == 'orbs' then
    local t = o.desc or ''
    if o.wl then t = string.format('%s (%d of %d this week)', t, num(o.wb), num(o.wl)) end
    return t
  end
  return o.desc or ''
end

local RARITY = {'Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Exotic', 'Mythic', 'Chaos', 'Eternal', 'Divine',
  'Phantasmal', 'Celestial', 'Cosmic', 'Abyssal', 'Transcendent'}
function V.rarityName(r)
  return RARITY[math.floor(num(r))] or 'Normal'
end

function V.offerTooltip(o, f)
  local lines = { o.n or '' }
  lines[#lines + 1] = string.format('Needs %s', o.rn or '?')
  if o.kind == 'gear' then
    lines[#lines + 1] = V.offerKindText(o)
    for _, m in ipairs(list(o.mods)) do lines[#lines + 1] = '  ' .. tostring(m) end
  elseif o.desc and o.desc ~= '' then
    lines[#lines + 1] = o.desc
  end
  lines[#lines + 1] = 'Price: ' .. V.priceText(o, f)
  if o.why and o.why ~= '' then lines[#lines + 1] = o.why end
  return table.concat(lines, '\n')
end

-- the rank ladder of a faction: {name, min, colour, reached}
function V.ladder(data, f)
  local out = {}
  for i, r in ipairs(rows(data and data.ranks)) do
    out[#out + 1] = { name = r.n, min = r.min, color = r.c, reached = f ~= nil and num(f.rank) >= i }
  end
  return out
end

function V.resetText(data)
  if not data then return '' end
  return string.format('Daily contracts in %s, weekly in %s', V.countdown(data.nextDay), V.countdown(data.nextWeek))
end
