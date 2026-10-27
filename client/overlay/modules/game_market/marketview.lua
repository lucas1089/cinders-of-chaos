-- The market window's logic that needs no client API (tested by marketview_test.lua): money and time texts, the
-- listing fee and the tax as the server computes them (server/data/scripts/chaos/market_core.lua), reading price
-- inputs ("5k", "2.5m"), the Browse filter from the window's fields, the Sell form check, row texts, the modifier
-- filter (up to 6 rows of modifier / lowest value / lowest tier, all or at least N, sockets, quality, free prefix /
-- suffix, power, bound) with its choices taken from the Codex data (game_codex CodexData), paging.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

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
-- by rarity id (1 Common, 2 Uncommon, 3 Magic, 4 Rare, 5 Legendary, 10 Divine; an old offer may hold 6 .. 9 or 11 .. 15,
-- which are the rarity they became); V.RARITY_IDS are the ids of today, in order, for the filter lists
V.RARITIES = { 'Common', 'Uncommon', 'Magic', 'Rare', 'Legendary', 'Legendary', 'Legendary', 'Legendary', 'Legendary', 'Divine',
  'Divine', 'Divine', 'Divine', 'Divine', 'Divine' }
V.RARITY_IDS = { 1, 2, 3, 4, 5, 10 }

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
  if sec <= 0 then return tr('ended') end
  local d, h, m = floor(sec / 86400), floor(sec % 86400 / 3600), floor(sec % 3600 / 60)
  if d > 0 then return tr('%dd %dh', d, h) end
  if h > 0 then return tr('%dh %dm', h, m) end
  if m > 0 then return tr('%dm', m) end
  return tr('<1m')
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
  if not gold or not coins then return nil, tr('Prices are whole numbers (5k and 2.5m work).') end
  if gold == 0 and coins == 0 then return nil, tr('Set a price in gold, in Chaos Coins or in both.') end
  local p = meta and meta.price or {}
  local pg, pc = p.gold or { min = 1, max = 2000000000 }, p.coins or { min = 1, max = 100000 }
  if gold > 0 and (gold < pg.min or gold > pg.max) then
    return nil, tr('A gold price must be between %s and %s.', V.money(pg.min), V.money(pg.max))
  end
  if coins > 0 and (coins < pc.min or coins > pc.max) then
    return nil, tr('A coin price must be between %s and %s.', V.money(pc.min), V.money(pc.max))
  end
  local count = floor(tonumber(form.count) or 1)
  if count < 1 or count > (tonumber(form.have) or 1) then return nil, tr('You do not have that many.') end
  return { gold = gold, coins = coins, days = tonumber(form.days) or (meta and meta.defaultDuration) or 3, count = count }
end

-- the Browse filter from the window's fields (texts and combo values); numbers that do not read are left out.
-- fields.modForm = the Modifiers section (V.modRequest); returns the filter, or nil and why the section is not valid
function V.filter(fields)
  local f = { q = fields.q or '', cat = fields.cat or '', rarity = tonumber(fields.rarity) or 0, cur = fields.cur or '',
    sort = fields.sort or 'new', page = tonumber(fields.page) or 1 }
  f.ilvlMin = V.parseAmount(fields.ilvlMin) or 0
  f.ilvlMax = V.parseAmount(fields.ilvlMax) or 0
  f.priceMin = V.parseAmount(fields.priceMin) or 0
  f.priceMax = V.parseAmount(fields.priceMax) or 0
  if fields.modForm then
    local m, why = V.modRequest(fields.modForm, fields.limits)
    if not m then return nil, why end
    for k, v in pairs(m) do f[k] = v end
  elseif fields.mod and fields.mod ~= '' then
    f.mods = { { k = fields.mod } }
  end
  return f
end

-- ---------------------------------------------------------------- the modifier filter (Browse > Modifiers)
-- the server's limits (market_config.lua modFilter; the `meta` message sends them)
V.MOD_LIMITS = { maxRows = 6, maxTier = 8, maxValue = 1000000, maxSockets = 8, maxQuality = 30 }
V.MOD_GROUPS = { { 'prefix', 'Prefixes' }, { 'suffix', 'Suffixes' }, { 'power', 'Legendary powers' } }

-- every modifier and legendary power of the Codex data: { list = { {key, name, group = prefix | suffix | power,
-- side} } (by group, then name), byKey }. A power is stored as the modifier chaos_mod_<power>
function V.modCatalog(codexData)
  local cat = { list = {}, byKey = {} }
  if type(codexData) ~= 'table' or type(codexData.tabs) ~= 'table' then return cat end
  for _, tab in ipairs(codexData.tabs) do
    for _, e in ipairs(tab.entries or {}) do
      local key = type(e.id) == 'string' and e.id:match('^mod:(.+)$')
      local power = type(e.id) == 'string' and e.id:match('^power:(.+)$')
      if power then key = 'chaos_mod_' .. power end
      if key and not cat.byKey[key] then
        local side = e.side == 'prefix' and 'prefix' or 'suffix'
        local m = { key = key, name = tostring(e.name or key), side = side, group = power and 'power' or side,
          tiers = type(e.tv) == 'table' and e.tv or nil }
        cat.byKey[key] = m
        cat.list[#cat.list + 1] = m
      end
    end
  end
  -- two modifiers of one name (a flat and a percent one): the best tier's value tells them apart (a combo picks by text)
  local count = {}
  for _, m in ipairs(cat.list) do count[m.name] = (count[m.name] or 0) + 1 end
  for _, m in ipairs(cat.list) do
    if count[m.name] > 1 then m.name = m.name .. ' (' .. tostring(m.tiers and m.tiers[#m.tiers] or m.key) .. ')' end
  end
  local order = { prefix = 1, suffix = 2, power = 3 }
  table.sort(cat.list, function(a, b)
    if a.group ~= b.group then return order[a.group] < order[b.group] end
    return a.name < b.name
  end)
  return cat
end

-- the choices of a modifier combo for what was typed in its search box: { {text, key} } with a heading per group
-- (key '' = no modifier); every word typed must be in the name. Also returns the key of the first match
function V.modChoices(cat, query)
  local words = {}
  for w in tostring(query or ''):lower():gmatch('%S+') do words[#words + 1] = w end
  local out = { { #words > 0 and tr('Matching modifiers...') or tr('Choose a modifier...'), '' } }
  local first
  for _, g in ipairs(V.MOD_GROUPS) do
    local head = false
    for _, m in ipairs(cat and cat.list or {}) do
      if m.group == g[1] then
        local name, hit = m.name:lower(), true
        for _, w in ipairs(words) do
          if not name:find(w, 1, true) then hit = false break end
        end
        if hit then
          if not head then
            out[#out + 1] = { '-- ' .. g[2] .. ' --', '' }
            head = true
          end
          out[#out + 1] = { m.name, m.key }
          first = first or m.key
        end
      end
    end
  end
  if #words > 0 and not first then out[1] = { 'No modifier matches', '' } end
  return out, first
end

-- the minimum tier choices: T1 is the lowest, T8 the best; "T5+" = T5 or better
function V.tierOptions(maxTier)
  local out = { { 'Any tier', 0 } }
  for t = 1, maxTier or 8 do out[#out + 1] = { 'T' .. t .. (t < (maxTier or 8) and '+' or ''), t } end
  return out
end

-- a whole number from a box: '' = 0, else nil when it does not read
local function whole(text)
  text = tostring(text or ''):gsub('%s', '')
  if text == '' then return 0 end
  if not text:match('^%d+$') then return nil end
  return tonumber(text)
end

-- the Modifiers section -> the filter fields the server reads (market_core.lua C.modFilter), or nil, why.
-- form = { rows = { {key, min (text), tier} }, mode = 'all' | 'count', need (text), sockets, quality (texts),
--          freeP, freeS, power, bound (booleans) }; rows without a modifier are left out
function V.modRequest(form, limits)
  limits = limits or V.MOD_LIMITS
  form = form or {}
  local mods, seen = {}, {}
  for i, r in ipairs(form.rows or {}) do
    if r.key and r.key ~= '' then
      if seen[r.key] then return nil, tr('Each modifier only once per search.') end
      seen[r.key] = true
      local min = whole(r.min)
      if not min then return nil, tr('Row %s: the minimum value is a whole number.', i) end
      if min > (limits.maxValue or 1000000) then min = limits.maxValue or 1000000 end
      local tier = math.max(0, math.min(tonumber(r.tier) or 0, limits.maxTier or 8))
      local row = { k = r.key }
      if min > 0 then row.min = min end
      if tier > 0 then row.t = tier end
      mods[#mods + 1] = row
    end
  end
  if #mods > (limits.maxRows or 6) then return nil, tr('At most %s modifiers per search.', (limits.maxRows or 6)) end
  local out = { mods = mods }
  if form.mode == 'count' and #mods > 0 then
    local need = whole(form.need)
    if not need or need < 1 or need > #mods then
      return nil, tr('"At least" needs a number from 1 to %d (the modifiers chosen).', #mods)
    end
    if need < #mods then out.need = need end
  end
  local sockets, quality = whole(form.sockets), whole(form.quality)
  if not sockets then return nil, tr('Sockets: a whole number.') end
  if not quality then return nil, tr('Quality: a whole number.') end
  if sockets > 0 then out.sockets = math.min(sockets, limits.maxSockets or 8) end
  if quality > 0 then out.quality = math.min(quality, limits.maxQuality or 30) end
  if form.freeP then out.freeP = true end
  if form.freeS then out.freeS = true end
  if form.power then out.power = true end
  if form.bound then out.bound = true end
  return out
end

-- how many conditions the Modifiers section holds (shown on its toggle button)
function V.modCount(req)
  if type(req) ~= 'table' then return 0 end
  local n = #(req.mods or {})
  for _, k in ipairs({ 'sockets', 'quality', 'freeP', 'freeS', 'power', 'bound' }) do
    if req[k] then n = n + 1 end
  end
  return n
end

-- the lines of an offer's tooltip that the modifier rows of the search matched: { {text} }, best first
function V.matchedMods(tip, req)
  local out = {}
  if type(tip) ~= 'table' or type(tip.mods) ~= 'table' or type(req) ~= 'table' or type(req.mods) ~= 'table' then return out end
  local want = {}
  for _, r in ipairs(req.mods) do want[tostring(r.k):lower()] = r end
  for _, m in ipairs(tip.mods) do
    local r = want[tostring(m.k):lower()] -- the item keeps some keys in mixed case (rarity_herbalistSkill)
    if r then
      local value = (m.g == 'special' and (tonumber(m.v2) or 0) ~= 0) and tonumber(m.v2) or (tonumber(m.v) or 0)
      if value >= (r.min or 0) and (tonumber(m.tr) or 0) >= (r.t or 0) then
        out[#out + 1] = { text = tr('Matches: ') .. tostring(m.t or m.l or m.k) .. ((m.tr or 0) > 0 and (' (T' .. m.tr .. ')') or '') }
      end
    end
  end
  return out
end

-- price lines of a row: { {text, currency} ... }
function V.priceLines(row)
  local out = {}
  if (row.gold or 0) > 0 then out[#out + 1] = { text = V.money(row.gold) .. ' ' .. tr('gold'), cur = 'gold' } end
  if (row.coins or 0) > 0 then out[#out + 1] = { text = V.money(row.coins) .. ' ' .. tr('coins'), cur = 'coins' } end
  return out
end

function V.rarityName(r)
  local name = V.RARITIES[tonumber(r) or 0]
  return name and tr(name) or nil
end

-- the line under a Browse row's name
function V.subLine(row)
  local parts = {}
  if row.unique then parts[#parts + 1] = tr('Unique')
  elseif (row.rarity or 0) > 0 then parts[#parts + 1] = V.rarityName(row.rarity) or tr('Rarity %d', row.rarity) end
  if (row.ilvl or 0) > 0 then parts[#parts + 1] = tr('iLvl %d', row.ilvl) end
  if row.veil then parts[#parts + 1] = row.veil == 'open' and tr('Unveiled') or tr('Veiled') end -- the veiled slot (server market.lua)
  parts[#parts + 1] = tr(V.CATEGORY_NAMES[row.cat] or row.cat)
  if row.seller then parts[#parts + 1] = tr('by %s', row.seller) end
  parts[#parts + 1] = tr('%s left', V.timeLeft(row.left))
  return table.concat(parts, ' - ')
end

-- what happened to one of my offers
function V.stateLine(row)
  if row.state == 'sold' then
    local tax, net = row.tax or 0, (row.paid or 0) - (row.tax or 0)
    local cur = row.cur == 'coins' and tr('coins') or tr('gold')
    return tr('Sold to %s for %s %s (tax %s, you got %s)', row.buyer or '?', V.money(row.paid), cur, V.money(tax),
      V.money(net))
  elseif row.state == 'expired' then
    return tr('Expired: the item went back to your inbox')
  elseif row.state == 'cancelled' then
    return tr('Cancelled: the item went back to your inbox')
  elseif row.state == 'active' then
    return tr('%s left', V.timeLeft(row.left))
  end
  return row.state or ''
end

function V.historyLine(row)
  local cur = row.cur == 'coins' and tr('coins') or tr('gold')
  if row.side == 'bought' then
    return tr('Bought from %s for %s %s', row.seller or '?', V.money(row.paid), cur)
  end
  return tr('Sold to %s for %s %s (tax %s)', row.buyer or '?', V.money(row.paid), cur, V.money(row.tax or 0))
end

function V.pageText(page, pages, total)
  total = tonumber(total) or 0
  return tr(total == 1 and 'Page %d / %d  (%d offer)' or 'Page %d / %d  (%d offers)', tonumber(page) or 1, math.max(1, tonumber(pages) or 1), total)
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

-- ---------------------------------------------------------------- buy orders (the Buy Orders tab)
-- the server's limits (market_config.lua orders; the `meta` message sends them)
V.ORDER_LIMITS = { maxQuantity = 1000, maxTotal = { gold = 2000000000, coins = 1000000 } }
V.ORDER_SORT_NAMES = { new = 'Newest', price = 'Best price', ending = 'Ending soon', name = 'Name' }

-- the order form: form = {sid, quantity, price (texts), cur, days, rarity, ilvl (text), mods = a V.modRequest result
-- or nil}. Returns the orderPost request {sid, quantity, price, cur, days, filter} and its total and fee, or nil, why
function V.checkOrder(meta, form)
  form = form or {}
  if not tonumber(form.sid) or tonumber(form.sid) <= 0 then return nil, tr('Choose the item you want: search for it first.') end
  local qty = V.parseAmount(form.quantity)
  if not qty or qty < 1 then return nil, tr('How many do you want? A whole number of 1 or more.') end
  local limits = meta and meta.orders or V.ORDER_LIMITS
  local maxQ = limits.maxQuantity or V.ORDER_LIMITS.maxQuantity
  if qty > maxQ then return nil, tr('At most %s per order.', V.money(maxQ)) end
  local cur = form.cur == 'coins' and 'coins' or 'gold'
  local price = V.parseAmount(form.price)
  local p = meta and meta.price or {}
  local lim = (p[cur]) or (cur == 'coins' and { min = 1, max = 100000 } or { min = 100, max = 2000000000 })
  if not price or price < lim.min or price > lim.max then
    return nil, tr('The price per item in %s must be between %s and %s.', cur == 'coins' and tr('Chaos Coins') or tr('gold'),
      V.money(lim.min), V.money(lim.max))
  end
  local total = price * qty
  local maxT = (limits.maxTotal or V.ORDER_LIMITS.maxTotal)[cur]
  if maxT and total > maxT then
    return nil, tr('One order may hold at most %s%s', V.money(maxT), (cur == 'coins' and tr(' Chaos Coins.') or tr(' gold.')))
  end
  local ilvl = V.parseAmount(form.ilvl)
  if not ilvl then return nil, tr('Item level: a whole number.') end
  local filter = { rarity = (tonumber(form.rarity) or 0) > 0 and tonumber(form.rarity) or nil, ilvl = ilvl > 0 and ilvl or nil }
  for k, v in pairs(form.mods or {}) do filter[k] = v end
  if filter.mods and #filter.mods == 0 then filter.mods = nil end
  local fee = V.fee(meta, cur == 'gold' and total or 0, cur == 'coins' and total or 0)
  return { sid = tonumber(form.sid), quantity = qty, price = price, cur = cur,
    days = tonumber(form.days) or (meta and meta.defaultDuration) or 3, filter = filter }, total, fee
end

-- what posting holds and costs, for the form's text
function V.orderCostText(meta, req, total, fee)
  if not req then return '' end
  local curName = req.cur == 'coins' and tr('Chaos Coins') or tr('gold')
  local lines = {}
  if req.cur == 'coins' then
    lines[#lines + 1] = tr('Held now: %s Chaos Coins from your account, and the listing fee of %s gold from your bank.', V.money(total), V.money(fee))
  else
    lines[#lines + 1] = tr('Held now: %s gold from your bank (%s for the items + %s listing fee).', V.money(total + fee),
      V.money(total), V.money(fee))
  end
  local tax = V.tax(meta, req.cur, req.price)
  lines[#lines + 1] = tr('Sellers get %s %s per item (%s sales tax). What is not bought comes back when the order ends; the fee does not.',
    V.money(req.price - tax), curName, V.money(tax))
  return table.concat(lines, '\n')
end

-- the filter of an order in words; modName(key) gives a modifier's name (the Codex catalog), else the key is shown
function V.orderFilterText(f, modName)
  if type(f) ~= 'table' then return tr('Any') end
  local parts = {}
  if (tonumber(f.rarity) or 0) > 0 then parts[#parts + 1] = (V.rarityName(f.rarity) or tr('Rarity %d', f.rarity)) .. '+' end
  if (tonumber(f.ilvl) or 0) > 0 then parts[#parts + 1] = tr('iLvl %d', f.ilvl) .. '+' end
  local mods = {}
  for _, m in ipairs(f.mods or {}) do
    local name = (modName and modName(m.k)) or tostring(m.k)
    local t = name
    if (tonumber(m.min) or 0) > 0 then t = t .. ' ' .. m.min .. '+' end
    if (tonumber(m.t) or 0) > 0 then t = t .. ' T' .. m.t .. '+' end
    mods[#mods + 1] = t
  end
  if #mods > 0 then
    if f.need and tonumber(f.need) < #mods then
      parts[#parts + 1] = tr('%d of: %s', f.need, table.concat(mods, ', '))
    else
      parts[#parts + 1] = table.concat(mods, ', ')
    end
  end
  if (tonumber(f.sockets) or 0) > 0 then parts[#parts + 1] = tr(tonumber(f.sockets) > 1 and '%d+ sockets' or '%d+ socket', f.sockets) end
  if (tonumber(f.quality) or 0) > 0 then parts[#parts + 1] = tr('quality %d%%+', f.quality) end
  if f.freeP then parts[#parts + 1] = tr('free prefix') end
  if f.freeS then parts[#parts + 1] = tr('free suffix') end
  if f.power then parts[#parts + 1] = tr('legendary power') end
  if f.bound then parts[#parts + 1] = tr('bound modifier') end
  if #parts == 0 then return tr('Any') end
  return table.concat(parts, ' - ')
end

-- the line under an order's name
function V.orderSubLine(row, modName)
  local parts = { tr('%s/%s bought', V.money(row.filled or 0), V.money(row.qty or 0)) }
  if row.buyer and not row.mine then parts[#parts + 1] = tr('by %s', row.buyer) end
  if row.state == 'active' then
    parts[#parts + 1] = tr('%s left', V.timeLeft(row.left))
  else
    parts[#parts + 1] = row.state and tr(row.state) or ''
  end
  local f = V.orderFilterText(row.filter, modName)
  if f ~= tr('Any') then parts[#parts + 1] = f end
  return table.concat(parts, ' - ')
end

-- the price column of an order: {each, held}
function V.orderPriceLines(row)
  local cur = row.cur == 'coins' and 'coins' or 'gold'
  local word = cur == 'coins' and tr('coins') or tr('gold')
  local out = { { text = tr('%s %s each', V.money(row.price or 0), word), cur = cur } }
  if row.state == 'active' then
    out[#out + 1] = { text = tr('%s held', V.money(row.escrow or 0)), cur = cur }
  elseif (row.refunded or 0) > 0 then
    out[#out + 1] = { text = tr('%s back', V.money(row.refunded)), cur = cur }
  end
  return out
end

-- what a fill of `n` pays the seller
function V.fillText(meta, row, n)
  n = tonumber(n) or 0
  if n <= 0 then return '' end
  local cur = row.cur == 'coins' and 'coins' or 'gold'
  local total = (tonumber(row.price) or 0) * n
  local tax, net = V.tax(meta, cur, total)
  return tr('Sell %s for %s %s: tax %s, you receive %s %s%s.', n > 1 and tr('%d items', n) or tr('1 item'), V.money(total),
    cur == 'coins' and tr('Chaos Coins') or tr('gold'), V.money(tax), V.money(net), cur == 'coins' and tr('Chaos Coins') or tr('gold'),
    cur == 'coins' and tr(' on your account') or tr(' in your bank'))
end

-- the seller's items for an order: those that fit first
function V.sortFillable(items)
  local out = {}
  for _, it in ipairs(items or {}) do out[#out + 1] = it end
  table.sort(out, function(a, b)
    if (a.why == nil) ~= (b.why == nil) then return a.why == nil end
    if (a.rarity or 0) ~= (b.rarity or 0) then return (a.rarity or 0) > (b.rarity or 0) end
    return (a.count or 0) > (b.count or 0)
  end)
  return out
end

return V
