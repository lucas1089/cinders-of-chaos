-- The market window's price history logic without client API (tested by marketpriceview_test.lua): the texts of the
-- price stats of an item key (server/data/scripts/chaos/market_history.lua, action "prices" on opcode 221), the price the
-- Sell form suggests and its warning, the mark of a Browse row priced well under / over the typical price, and the
-- 30-day chart as rectangles (the Orb Exchange chart, game_orbexchange/orbexchangeview.lua OrbExchangeView.chart, with
-- days in place of hours).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

MarketView = MarketView or {}
local V = MarketView

local floor = math.floor

V.PRICE_COLORS = { low = '#8fd16a', high = '#e05a4a', warn = '#e8a040', dim = '#8c8070', text = '#d6c9ae', line = '#e8b84a', vol = '#3a3339' }

local function curName(cur, n)
  if cur == 'coins' then return n == 1 and tr('Chaos Coin') or tr('Chaos Coins') end
  return 'gold'
end
V.curName = curName

function V.priceAgo(s)
  s = tonumber(s)
  if not s then return '' end
  if s < 60 then return tr('just now') end
  if s < 3600 then return tr('%dm ago', floor(s / 60)) end
  if s < 86400 then return tr('%dh ago', floor(s / 3600)) end
  return tr('%dd ago', floor(s / 86400))
end

-- "Rare - iLvl 60-69" (the key the stats are of)
function V.priceKeyText(rarity, bandText)
  local parts = {}
  if (tonumber(rarity) or 0) > 0 and V.rarityName then parts[#parts + 1] = V.rarityName(rarity) end
  if bandText and bandText ~= '' then parts[#parts + 1] = bandText end
  return table.concat(parts, ' - ')
end

-- the typical price line: {text, color}
function V.typicalLine(s, cur)
  if not s or (s.n30 or 0) == 0 and (s.n7 or 0) == 0 then
    return { text = 'No sales of this item yet.', color = V.PRICE_COLORS.dim }
  end
  if not s.typical then
    local have = math.max(s.n7 or 0, s.n30 or 0)
    return { text = tr('Typical price: not enough sales yet (%d of %d).', have, s.need or 5), color = V.PRICE_COLORS.dim }
  end
  local basis = s.basis == '7d' and tr('median of %d sales, 7 days', s.n7 or 0)
    or tr('daily medians of %d sales, %d days', s.n30 or 0, s.days or 30)
  return { text = tr('Typical price: %s %s each (%s)', V.money(s.typical), curName(cur, s.typical), basis), color = V.PRICE_COLORS.line }
end

-- the stats as lines {text, color}: typical, last sale, 7 days (median, range, volume), lowest / highest
function V.priceStatsLines(s, cur)
  local out = { V.typicalLine(s, cur) }
  if not s then return out end
  local c = curName(cur)
  if s.last then
    out[#out + 1] = { text = tr('Last sale: %s %s, %s', V.money(s.last), c, V.priceAgo(s.lastAgo)), color = V.PRICE_COLORS.text }
  end
  if (s.n7 or 0) > 0 then
    out[#out + 1] = { text = tr('7 days: median %s, %d sale%s (%d unit%s)', V.money(s.median7), s.n7, s.n7 == 1 and '' or 's',
      s.units7 or s.n7, (s.units7 or s.n7) == 1 and '' or 's'), color = V.PRICE_COLORS.text }
    if s.lo and s.hi and (s.lo ~= s.min7 or s.hi ~= s.max7) then
      out[#out + 1] = { text = tr('Usual range: %s - %s (lowest %s, highest %s)', V.money(s.lo), V.money(s.hi), V.money(s.min7),
        V.money(s.max7)), color = V.PRICE_COLORS.dim }
    else
      out[#out + 1] = { text = string.format('Lowest %s, highest %s', V.money(s.min7), V.money(s.max7)), color = V.PRICE_COLORS.dim }
    end
  elseif (s.n30 or 0) > 0 then
    out[#out + 1] = { text = tr('No sales in 7 days; %d in %d days.', s.n30, s.days or 30), color = V.PRICE_COLORS.dim }
  end
  return out
end

-- which currency the detail shows first: gold when it has sales, else coins when those have, else gold
function V.priceCurrency(data, want)
  local function has(s) return s and ((s.n30 or 0) > 0 or (s.n7 or 0) > 0) end
  if want == 'coins' and has(data.coins) then return 'coins' end
  if want == 'gold' and has(data.gold) then return 'gold' end
  if has(data.gold) then return 'gold' end
  if has(data.coins) then return 'coins' end
  return 'gold'
end

-- the price the Sell form suggests: the typical price per unit rounded down to 3 significant digits (never under the
-- market's minimum), times the units; nil without a typical price
function V.suggestPrice(typical, count, minPrice)
  typical = tonumber(typical)
  if not typical or typical <= 0 then return nil end
  local unit = floor(typical)
  if unit >= 1000 then
    local step = 10 ^ (#tostring(unit) - 3)
    unit = floor(unit / step) * step
  end
  local total = unit * math.max(1, floor(tonumber(count) or 1))
  if minPrice and total < minPrice then total = minPrice end
  return floor(total)
end

-- the Sell form's warning for an asking price (the whole amount of count units): nil when it is near the typical price
-- (or there is none), else {text, color, kind = 'low' | 'high'}
function V.sellWarning(ask, count, typical, warn, cur)
  ask, typical = tonumber(ask) or 0, tonumber(typical)
  if ask <= 0 or not typical or typical <= 0 then return nil end
  warn = warn or { low = 0.5, high = 2.0 }
  local unit = floor(ask / math.max(1, floor(tonumber(count) or 1)))
  local r = unit / typical
  local pct = floor(r * 100 + 0.5)
  if r <= warn.low then
    return { kind = 'low', color = V.PRICE_COLORS.warn,
      text = tr('Far below the typical price: %d%% of %s %s each. Is that what you want?', pct, V.money(typical), curName(cur, typical)) }
  end
  if r >= warn.high then
    return { kind = 'high', color = V.PRICE_COLORS.warn,
      text = tr('Far above the typical price: %d%% of %s %s each; it may not sell.', pct, V.money(typical), curName(cur, typical)) }
  end
  return nil
end

-- a Browse row's mark (the server sets typ, tcur and pm = 'low' | 'high'): {text, color} or nil
function V.rowMark(offer)
  if not offer or not offer.pm or not tonumber(offer.typ) or tonumber(offer.typ) <= 0 then return nil end
  local price = offer.tcur == 'coins' and offer.coins or offer.gold
  local unit = floor((tonumber(price) or 0) / math.max(1, tonumber(offer.count) or 1))
  local diff = floor(math.abs(unit / offer.typ - 1) * 100 + 0.5)
  if offer.pm == 'low' then
    return { text = tr('%d%% under typical', diff), color = V.PRICE_COLORS.low, kind = 'low' }
  end
  return { text = tr('%d%% over typical', diff), color = V.PRICE_COLORS.high, kind = 'high' }
end

-- the tooltip line of a row's typical price (nil without one)
function V.rowTypicalText(offer)
  if not offer or not tonumber(offer.typ) then return nil end
  return tr('Typical price: %s %s each', V.money(offer.typ), curName(offer.tcur, offer.typ))
end

-- the chart: points {{h = days ago, p, v}} oldest first -> rectangles {x, y, w, h, kind = 'line' | 'vol'} (a step line
-- of the daily medians and the sales as bars), drawn by the Orb Exchange chart code
local function chartFn()
  local ov = type(modules) == 'table' and modules.game_orbexchange and modules.game_orbexchange.OrbExchangeView or OrbExchangeView
  if not ov and dofile then
    pcall(dofile, '/modules/game_orbexchange/orbexchangeview.lua')
    ov = OrbExchangeView
  end
  return ov and ov.chart
end

function V.priceChart(points, days, w, h)
  local f = chartFn()
  if not f then return {} end
  return f(points or {}, days or 30, w, h)
end

-- the chart's scale texts: highest and lowest daily median shown, and the first / last day
function V.chartScale(points, days)
  if not points or #points == 0 then return nil end
  local lo, hi = math.huge, -math.huge
  for _, p in ipairs(points) do lo, hi = math.min(lo, p.p), math.max(hi, p.p) end
  return { high = V.short and V.short(hi) or tostring(hi), low = V.short and V.short(lo) or tostring(lo),
    from = tr('%d days ago', (days or 30) - 1), to = 'today' }
end
