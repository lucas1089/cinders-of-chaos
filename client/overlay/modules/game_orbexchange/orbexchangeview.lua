-- Orb Exchange window: the logic without client API (tested by orbexchangeview_test.lua with LuaJIT and Lua 5.3).
-- Numbers and texts, the order form -> the server request (orbexchange_core.lua checkOrder has the final word), the
-- rows of the book, the price chart as rectangles, my orders and fills as text.
-- The window always shows a pair as base / quote: the base is an orb, the quote gold or another orb; prices are quote
-- per base. "Buy" gives the quote and wants the base, "Sell" gives the base and wants the quote.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

OrbExchangeView = OrbExchangeView or {}
local V = OrbExchangeView

V.GOLD = 'gold'
V.COLORS = { ask = '#e05a4a', bid = '#6cc46c', text = '#d6c9ae', dim = '#8c8070', gold = '#e8b84a', up = '#6cc46c', down = '#e05a4a' }

local floor = math.floor

function V.money(n)
  n = tonumber(n)
  if not n then return '0' end
  local s = string.format('%.0f', floor(n))
  local sign = ''
  if s:sub(1, 1) == '-' then sign, s = '-', s:sub(2) end
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  if out:sub(1, 1) == ',' then out = out:sub(2) end
  return sign .. out
end

-- '5000', '5,000', '5k', '2.5m', '1b' -> a whole number (nil when it is not one)
function V.parseAmount(text)
  local s = tostring(text or ''):lower():gsub('[%s,]', '')
  if s == '' then return nil end
  local num, suffix = s:match('^(%d*%.?%d+)([kmb]?)$')
  num = tonumber(num)
  if not num then return nil end
  local mult = ({ k = 1000, m = 1000000, b = 1000000000 })[suffix] or 1
  local v = num * mult
  if v ~= floor(v) then
    v = floor(v + 0.5)
  end
  return v
end

-- a price: decimals allowed ('0.25', '4.5k')
function V.parsePrice(text)
  local s = tostring(text or ''):lower():gsub('[%s,]', '')
  if s == '' then return nil end
  local num, suffix = s:match('^(%d*%.?%d+)([kmb]?)$')
  num = tonumber(num)
  if not num or num <= 0 then return nil end
  return num * (({ k = 1000, m = 1000000, b = 1000000000 })[suffix] or 1)
end

-- 4 significant digits at most, thousands separated (the server's priceText)
function V.priceText(p)
  p = tonumber(p)
  if not p then return '-' end
  if p >= 1000 then return V.money(floor(p + 0.5)) end
  local s
  if p >= 100 then s = string.format('%.1f', p)
  elseif p >= 1 then s = string.format('%.2f', p)
  elseif p >= 0.01 then s = string.format('%.4f', p)
  else s = string.format('%.6f', p) end
  s = s:gsub('(%..-)0+$', '%1'):gsub('%.$', '')
  return s
end

function V.compact(n)
  n = tonumber(n) or 0
  if n >= 1000000000 then return V.priceText(n / 1000000000) .. 'b' end
  if n >= 1000000 then return V.priceText(n / 1000000) .. 'm' end
  if n >= 10000 then return V.priceText(n / 1000) .. 'k' end
  return V.money(n)
end

function V.orbs(meta)
  local byKey = {}
  for _, o in ipairs(meta and meta.orbs or {}) do byKey[o.k] = o end
  return byKey
end

function V.assetName(meta, key)
  if key == V.GOLD then return 'gold' end
  local o = V.orbs(meta)[key]
  return o and o.n or tostring(key or '?')
end

-- the short name of an orb for tight places: 'Orb of Fate' -> 'Fate'
function V.shortName(meta, key)
  local n = V.assetName(meta, key)
  return (n:gsub('^Orbs? of ', ''))
end

function V.amount(meta, key, n)
  return V.money(n) .. ' ' .. V.assetName(meta, key)
end

-- the quote choices of a base: gold first, then every other orb
function V.quotes(meta, base)
  local out = { V.GOLD }
  for _, o in ipairs(meta and meta.orbs or {}) do
    if o.k ~= base then out[#out + 1] = o.k end
  end
  return out
end

-- ------------------------------------------------------------------ the order form
-- f = {side = 'buy'|'sell', qty (text), price (text), days}; returns the request {give, giveQty, want, wantQty, days}
-- and a preview {total, fee, receive, each} or nil and why
function V.form(f, base, quote, meta)
  meta = meta or {}
  local qty = V.parseAmount(f.qty)
  if not qty or qty < 1 then return nil, tr('Enter how many %s.', V.assetName(meta, base)) end
  local price = V.parsePrice(f.price)
  if not price then return nil, tr('Enter a price per %s in %s.', V.shortName(meta, base), V.assetName(meta, quote)) end
  -- rounded to the aggressive side by less than one unit: a buyer pays up, a seller asks down (both still cross the
  -- order the price came from)
  local total
  if f.side == 'sell' then
    total = floor(qty * price + 1e-9)
  else
    total = math.ceil(qty * price - 1e-9)
  end
  if total < 1 then return nil, tr('The total is less than one %s.', V.assetName(meta, quote)) end
  local req
  if f.side == 'sell' then
    req = { give = base, giveQty = qty, want = quote, wantQty = total }
  else
    req = { give = quote, giveQty = total, want = base, wantQty = qty }
  end
  req.days = tonumber(f.days) or meta.defaultDuration or 7
  local function limits(asset, n)
    local kind = asset == V.GOLD and 'gold' or 'orb'
    local lo = meta.min and meta.min[kind] or 1
    local hi = meta.max and meta.max[kind]
    if n < lo then return tr('At least %s %s per order.', V.money(lo), V.assetName(meta, asset)) end
    if hi and n > hi then return tr('At most %s %s per order.', V.money(hi), V.assetName(meta, asset)) end
    return nil
  end
  local why = limits(req.give, req.giveQty) or limits(req.want, req.wantQty)
  if why then return nil, why end
  local fees = meta.fees or {}
  local preview = { total = total, each = total / qty, fee = 0, placeFee = 0 }
  if quote == V.GOLD then
    if f.side == 'sell' then
      preview.fee = floor(total * (fees.goldBps or 0) / 10000)
    end
  elseif base ~= V.GOLD then
    preview.placeFee = fees.orbPairGold or 0
  end
  preview.receive = (f.side == 'sell' and total or qty) - preview.fee
  return req, preview
end

-- the line under the form
function V.previewText(req, preview, side, base, quote, meta)
  if not req then return '' end
  local parts = {}
  if side == 'sell' then
    parts[#parts + 1] = tr('You give %s for at least %s (%s each).', V.amount(meta, base, req.giveQty), V.amount(meta, quote, req.wantQty),
      V.priceText(preview.each))
  else
    parts[#parts + 1] = tr('You give up to %s for at least %s (%s each).', V.amount(meta, quote, req.giveQty), V.amount(meta, base, req.wantQty),
      V.priceText(preview.each))
  end
  if preview.fee > 0 then
    parts[#parts + 1] = tr('Fee %s gold (%s%%) on the gold you receive.', V.money(preview.fee), V.priceText((meta.fees.goldBps or 0) / 100))
  elseif quote == V.GOLD and side == 'buy' then
    parts[#parts + 1] = 'No fee for the buyer.'
  end
  if preview.placeFee > 0 then
    parts[#parts + 1] = tr('Orb-for-orb orders cost %s gold from your bank.', V.money(preview.placeFee))
  end
  return table.concat(parts, ' ')
end

-- ------------------------------------------------------------------ the book
-- the rows top to bottom: asks highest price first (the best ask just above the spread), the spread line, then bids
-- best first. Each row {kind = 'ask'|'bid'|'spread', p, q, n, price, qty, orders, total, bar (0..1 of the biggest)}
function V.bookRows(book, rowsPerSide)
  book = book or {}
  rowsPerSide = rowsPerSide or 8
  local asks, bids = {}, {}
  for i = 1, math.min(rowsPerSide, #(book.asks or {})) do asks[i] = book.asks[i] end
  for i = 1, math.min(rowsPerSide, #(book.bids or {})) do bids[i] = book.bids[i] end
  local biggest = 0
  for _, l in ipairs(asks) do biggest = math.max(biggest, l.q or 0) end
  for _, l in ipairs(bids) do biggest = math.max(biggest, l.q or 0) end
  local rows = {}
  local function row(kind, l)
    return { kind = kind, p = l.p, q = l.q, price = V.priceText(l.p), qty = V.money(l.q), orders = tostring(l.n or 1), total = V.compact(l.t or 0),
      bar = biggest > 0 and (l.q or 0) / biggest or 0 }
  end
  for i = #asks, 1, -1 do rows[#rows + 1] = row('ask', asks[i]) end
  local spread
  if asks[1] and bids[1] then
    local mid = (asks[1].p + bids[1].p) / 2
    spread = { kind = 'spread', price = string.format('Spread %s', V.priceText(asks[1].p - bids[1].p)),
      qty = mid > 0 and string.format('%s%%', V.priceText((asks[1].p - bids[1].p) / mid * 100)) or '' }
  else
    spread = { kind = 'spread', price = (#asks + #bids) == 0 and tr('No orders') or tr('One side only'), qty = '' }
  end
  rows[#rows + 1] = spread
  for i = 1, #bids do rows[#rows + 1] = row('bid', bids[i]) end
  return rows
end

-- ------------------------------------------------------------------ stats and the chart
function V.changeText(change)
  if not change then return '-', V.COLORS.dim end
  local s = string.format('%+.1f%%', change)
  return s, change > 0 and V.COLORS.up or (change < 0 and V.COLORS.down or V.COLORS.dim)
end

-- points = {{h (hours ago), p, v}} oldest first; returns rectangles {x, y, w, h, kind = 'line'|'vol'} in a w x h box:
-- the price as a step line (2 px) and the volume as dim bars at the bottom (a quarter of the height at most)
function V.chart(points, hours, w, h)
  hours = hours or 24
  local rects = {}
  if not points or #points == 0 or w <= 0 or h <= 0 then return rects end
  local lo, hi, vmax = math.huge, -math.huge, 0
  for _, pt in ipairs(points) do
    lo, hi, vmax = math.min(lo, pt.p), math.max(hi, pt.p), math.max(vmax, pt.v or 0)
  end
  local pad = (hi - lo) * 0.1
  if pad == 0 then pad = hi > 0 and hi * 0.05 or 1 end
  lo, hi = lo - pad, hi + pad
  local lineH = h - floor(h / 4) - 2
  local slot = w / hours
  local function xOf(hAgo) return floor((hours - 1 - hAgo) * slot) end
  local function yOf(p) return floor((hi - p) / (hi - lo) * (lineH - 2)) end
  for i, pt in ipairs(points) do
    local x0 = xOf(pt.h)
    local x1 = i < #points and xOf(points[i + 1].h) or w
    local y = yOf(pt.p)
    rects[#rects + 1] = { kind = 'line', x = x0, y = y, w = math.max(2, x1 - x0), h = 2 }
    if i < #points then
      local y2 = yOf(points[i + 1].p)
      rects[#rects + 1] = { kind = 'line', x = x1, y = math.min(y, y2), w = 2, h = math.abs(y2 - y) + 2 }
    end
    if vmax > 0 then
      local vh = math.max(1, floor((pt.v or 0) / vmax * floor(h / 4)))
      rects[#rects + 1] = { kind = 'vol', x = x0 + 1, y = h - vh, w = math.max(1, floor(slot) - 2), h = vh }
    end
  end
  return rects
end

function V.ago(s)
  s = tonumber(s) or 0
  if s < 60 then return 'now' end
  if s < 3600 then return string.format('%dm', floor(s / 60)) end
  if s < 86400 then return string.format('%dh', floor(s / 3600)) end
  return string.format('%dd', floor(s / 86400))
end

function V.timeLeft(s)
  s = tonumber(s) or 0
  if s <= 0 then return 'ending' end
  if s >= 86400 then return string.format('%dd %dh', floor(s / 86400), floor(s % 86400 / 3600)) end
  if s >= 3600 then return string.format('%dh %dm', floor(s / 3600), floor(s % 3600 / 60)) end
  return string.format('%dm', math.max(1, floor(s / 60)))
end

-- ------------------------------------------------------------------ my orders and fills
-- o = the server's order view {id, give, giveQty, want, wantQty, given, got, state, left, refunded}
function V.orderTitle(o, meta)
  return string.format('%s for %s', V.amount(meta, o.give, o.giveQty), V.amount(meta, o.want, o.wantQty))
end

-- the price of an order as people say it: gold per orb, or the larger way round for two orbs
function V.orderPrice(o, meta)
  local give, want = tonumber(o.giveQty) or 0, tonumber(o.wantQty) or 0
  if give <= 0 or want <= 0 then return '' end
  if o.give == V.GOLD then
    return tr('%s gold per %s', V.priceText(give / want), V.shortName(meta, o.want))
  elseif o.want == V.GOLD then
    return tr('%s gold per %s', V.priceText(want / give), V.shortName(meta, o.give))
  elseif want >= give then
    return string.format('%s %s per %s', V.priceText(want / give), V.shortName(meta, o.want), V.shortName(meta, o.give))
  end
  return string.format('%s %s per %s', V.priceText(give / want), V.shortName(meta, o.give), V.shortName(meta, o.want))
end

function V.orderSub(o, meta)
  local done = string.format('%s / %s given, %s received', V.money(o.given), V.money(o.giveQty), V.money(o.got))
  if o.state == 'active' then
    return table.concat({ done, V.orderPrice(o, meta), V.timeLeft(o.left) .. ' left' }, '  |  ')
  elseif o.state == 'pending' then
    return table.concat({ done, V.orderPrice(o, meta), 'being placed' }, '  |  ')
  end
  -- closed: the state first (the row is narrow)
  return (o.state or '?') .. (o.refunded and (', ' .. V.money(o.refunded) .. ' back') or '') .. '  |  ' .. done
end

function V.progress(o)
  local g = tonumber(o.giveQty) or 0
  if g <= 0 then return 0 end
  return math.min(1, (tonumber(o.given) or 0) / g)
end

-- f = {ago, order, gave, gaveQty, got, gotQty, fee, role}
function V.fillText(f, meta)
  local when = V.ago(f.ago)
  local s = string.format('%s: gave %s, got %s', when == 'now' and tr('just now') or (when .. ' ago'), V.amount(meta, f.gave, f.gaveQty),
    V.amount(meta, f.got, f.gotQty))
  if f.fee then s = s .. string.format(' (fee %s)', V.money(f.fee)) end
  return s
end

-- a price as the form's text: up to 6 decimals, rounded up (up = true) or down, no separators
function V.priceInput(p, up)
  p = tonumber(p) or 0
  local scaled = p * 1000000
  local n = up and math.ceil(scaled - 1e-6) or floor(scaled + 1e-6)
  local s = string.format('%.6f', n / 1000000)
  s = s:gsub('(%..-)0+$', '%1'):gsub('%.$', '')
  return s
end

-- what a click on a book row puts in the form: a click on an ask buys at its price, on a bid sells at its price
function V.fromRow(row)
  if not row or (row.kind ~= 'ask' and row.kind ~= 'bid') then return nil end
  local buy = row.kind == 'ask'
  return { side = buy and 'buy' or 'sell', price = V.priceInput(row.p, buy), qty = string.format('%.0f', row.q or 0) }
end

return V
