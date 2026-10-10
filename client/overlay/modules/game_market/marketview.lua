-- The market window's logic that needs no client API (tested by marketview_test.lua): money and time texts, the
-- listing fee and the tax as the server computes them (server/data/scripts/chaos/market_core.lua), reading price
-- inputs ("5k", "2.5m"), the Browse filter from the window's fields, the Sell form check, row texts, the modifier
-- options taken from the Codex data (game_codex CodexData), paging.

MarketView = {}
local V = MarketView

V.CATEGORY_NAMES = {
  weapon = 'Weapons', shield = 'Shields', helmet = 'Helmets', armor = 'Armors', legs = 'Legs', boots = 'Boots',
  jewel = 'Jewellery', other = 'Other gear', orb = 'Orbs', gem = 'Gems', key = 'Rift keys', misc = 'Other'
}
V.SORT_NAMES = {
  new = 'Newest', price = 'Price: low to high', price_desc = 'Price: high to low', ilvl = 'Item level',
  rarity = 'Rarity', name = 'Name', ending = 'Ending soon'
}
V.RARITIES = { 'Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Exotic', 'Mythic', 'Chaos', 'Eternal', 'Divine',
  'Phantasmal', 'Celestial', 'Cosmic', 'Abyssal', 'Transcendent' }

local floor = math.floor

function V.money(n)
  n = floor(tonumber(n) or 0)
  local s = tostring(math.abs(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  if out:sub(1, 1) == ',' then out = out:sub(2) end
  return (n < 0 and '-' or '') .. out
end

-- 1234567 -> "1.2m", 25000 -> "25k" (short form for narrow columns)
function V.short(n)
  n = tonumber(n) or 0
  if n >= 1000000000 then return (floor(n / 100000000) / 10) .. 'b' end
  if n >= 1000000 then return (floor(n / 100000) / 10) .. 'm' end
  if n >= 10000 then return floor(n / 1000) .. 'k' end
  return V.money(n)
end

-- "2d 5h", "3h 12m", "45m", "<1m"
function V.timeLeft(sec)
  sec = floor(tonumber(sec) or 0)
  if sec <= 0 then return 'ended' end
  local d, h, m = floor(sec / 86400), floor(sec % 86400 / 3600), floor(sec % 3600 / 60)
  if d > 0 then return d .. 'd ' .. h .. 'h' end
  if h > 0 then return h .. 'h ' .. m .. 'm' end
  if m > 0 then return m .. 'm' end
  return '<1m'
end

-- a typed amount: "1500", "1,500", "5k", "2.5m", "1b"; nil when it is not a whole positive number (0 allowed)
function V.parseAmount(text)
  text = tostring(text or ''):lower():gsub('[%s,]', '')
  if text == '' then return 0 end
  local num, suffix = text:match('^(%d+%.?%d*)([kmb]?)$')
  if not num then return nil end
  local v = tonumber(num)
  if suffix == 'k' then v = v * 1000 elseif suffix == 'm' then v = v * 1000000 elseif suffix == 'b' then v = v * 1000000000 end
  if v ~= floor(v) then return nil end
  return v
end

-- the listing fee (gold) and the tax, as market_core.lua: meta = the server's `meta` message
function V.fee(meta, gold, coins)
  local f = meta and meta.fee or {}
  gold, coins = tonumber(gold) or 0, tonumber(coins) or 0
  local base = gold > 0 and gold or coins * (f.coinGold or 0)
  local fee = floor(base * (f.pct or 0) / 100)
  if fee < (f.min or 0) then fee = f.min or 0 end
  if f.max and fee > f.max then fee = f.max end
  return fee
end

function V.tax(meta, currency, price)
  local pct = meta and meta.tax and meta.tax[currency] or 0
  local tax = floor((tonumber(price) or 0) * pct / 100)
  return tax, (tonumber(price) or 0) - tax
end

-- the Sell form: returns {gold, coins, days, count} or nil, the reason
function V.checkSell(meta, form)
  local gold, coins = V.parseAmount(form.gold), V.parseAmount(form.coins)
  if not gold or not coins then return nil, 'Prices are whole numbers (5k and 2.5m work).' end
  if gold == 0 and coins == 0 then return nil, 'Set a price in gold, in Chaos Coins or in both.' end
  local p = meta and meta.price or {}
  local pg, pc = p.gold or { min = 1, max = 2000000000 }, p.coins or { min = 1, max = 100000 }
  if gold > 0 and (gold < pg.min or gold > pg.max) then
    return nil, 'A gold price must be between ' .. V.money(pg.min) .. ' and ' .. V.money(pg.max) .. '.'
  end
  if coins > 0 and (coins < pc.min or coins > pc.max) then
    return nil, 'A coin price must be between ' .. V.money(pc.min) .. ' and ' .. V.money(pc.max) .. '.'
  end
  local count = floor(tonumber(form.count) or 1)
  if count < 1 or count > (tonumber(form.have) or 1) then return nil, 'You do not have that many.' end
  return { gold = gold, coins = coins, days = tonumber(form.days) or (meta and meta.defaultDuration) or 3, count = count }
end

-- the Browse filter from the window's fields (texts and combo values); numbers that do not read are left out
function V.filter(fields)
  local f = { q = fields.q or '', cat = fields.cat or '', rarity = tonumber(fields.rarity) or 0, cur = fields.cur or '',
    mod = fields.mod or '', sort = fields.sort or 'new', page = tonumber(fields.page) or 1 }
  f.ilvlMin = V.parseAmount(fields.ilvlMin) or 0
  f.ilvlMax = V.parseAmount(fields.ilvlMax) or 0
  f.priceMin = V.parseAmount(fields.priceMin) or 0
  f.priceMax = V.parseAmount(fields.priceMax) or 0
  return f
end

-- price lines of a row: { {text, currency} ... }
function V.priceLines(row)
  local out = {}
  if (row.gold or 0) > 0 then out[#out + 1] = { text = V.money(row.gold) .. ' gold', cur = 'gold' } end
  if (row.coins or 0) > 0 then out[#out + 1] = { text = V.money(row.coins) .. ' coins', cur = 'coins' } end
  return out
end

function V.rarityName(r)
  return V.RARITIES[tonumber(r) or 0]
end

-- the line under a Browse row's name
function V.subLine(row)
  local parts = {}
  if row.unique then parts[#parts + 1] = 'Unique'
  elseif (row.rarity or 0) > 0 then parts[#parts + 1] = V.rarityName(row.rarity) or ('Rarity ' .. row.rarity) end
  if (row.ilvl or 0) > 0 then parts[#parts + 1] = 'iLvl ' .. row.ilvl end
  parts[#parts + 1] = V.CATEGORY_NAMES[row.cat] or row.cat
  if row.seller then parts[#parts + 1] = 'by ' .. row.seller end
  parts[#parts + 1] = V.timeLeft(row.left) .. ' left'
  return table.concat(parts, ' - ')
end

-- what happened to one of my offers
function V.stateLine(row)
  if row.state == 'sold' then
    local tax, net = row.tax or 0, (row.paid or 0) - (row.tax or 0)
    local cur = row.cur == 'coins' and 'coins' or 'gold'
    return string.format('Sold to %s for %s %s (tax %s, you got %s)', row.buyer or '?', V.money(row.paid), cur, V.money(tax),
      V.money(net))
  elseif row.state == 'expired' then
    return 'Expired: the item went back to your inbox'
  elseif row.state == 'cancelled' then
    return 'Cancelled: the item went back to your inbox'
  elseif row.state == 'active' then
    return V.timeLeft(row.left) .. ' left'
  end
  return row.state or ''
end

function V.historyLine(row)
  local cur = row.cur == 'coins' and 'coins' or 'gold'
  if row.side == 'bought' then
    return string.format('Bought from %s for %s %s', row.seller or '?', V.money(row.paid), cur)
  end
  return string.format('Sold to %s for %s %s (tax %s)', row.buyer or '?', V.money(row.paid), cur, V.money(row.tax or 0))
end

-- the modifier filter's options from the Codex data: { {text, value} } sorted by name, value = the attribute key
function V.modOptions(codexData)
  local out = { { 'Any modifier', '' } }
  if type(codexData) ~= 'table' or type(codexData.tabs) ~= 'table' then return out end
  local list, seen = {}, {}
  for _, tab in ipairs(codexData.tabs) do
    for _, e in ipairs(tab.entries or {}) do
      local key = type(e.id) == 'string' and e.id:match('^mod:(.+)$')
      local power = type(e.id) == 'string' and e.id:match('^power:(.+)$')
      if power then
        -- a legendary power is stored as the modifier chaos_mod_<power> (game_codex codexview.lua idForMod)
        key = 'chaos_mod_' .. power
      end
      if key and not seen[key] then
        seen[key] = true
        list[#list + 1] = { (e.name or key) .. (power and ' (power)' or ''), key }
      end
    end
  end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  for _, o in ipairs(list) do out[#out + 1] = o end
  return out
end

function V.pageText(page, pages, total)
  total = tonumber(total) or 0
  return string.format('Page %d / %d  (%d offer%s)', tonumber(page) or 1, math.max(1, tonumber(pages) or 1), total, total == 1 and '' or 's')
end

-- the Sell picker: listable items first, then the others (greyed, with why)
function V.sortSellable(items)
  local out = {}
  for _, it in ipairs(items or {}) do out[#out + 1] = it end
  table.sort(out, function(a, b)
    if (a.why == nil) ~= (b.why == nil) then return a.why == nil end
    if (a.rarity or 0) ~= (b.rarity or 0) then return (a.rarity or 0) > (b.rarity or 0) end
    return tostring(a.name) < tostring(b.name)
  end)
  return out
end

return V
