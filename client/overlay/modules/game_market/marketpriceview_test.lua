-- Run from the repo root: luajit client/overlay/modules/game_market/marketpriceview_test.lua (also lua5.3)
-- The market window's price history logic (marketpriceview.lua): stats lines, the currency shown, the Sell form's
-- suggested price and warning, the Browse row marks, the 30-day chart (the Orb Exchange chart code) and its scale.
local here = (arg and arg[0] or ''):match('^(.*)/[^/]*$') or '.'
dofile(here .. '/marketview.lua')
dofile(here .. '/../game_orbexchange/orbexchangeview.lua')
dofile(here .. '/marketpriceview.lua')
local V = MarketView
local fails, n = 0, 0
local function eq(a, b, name)
  n = n + 1
  if a ~= b then fails = fails + 1; print('FAIL ' .. name .. ': got ' .. tostring(a) .. ', want ' .. tostring(b)) end
end
local function ok(c, name) eq(c and true or false, true, name) end

-- ------------------------------------------------------------------ texts
eq(V.priceAgo(30), 'just now', 'ago now')
eq(V.priceAgo(600), '10m ago', 'ago minutes')
eq(V.priceAgo(7200), '2h ago', 'ago hours')
eq(V.priceAgo(3 * 86400), '3d ago', 'ago days')
eq(V.priceAgo(nil), '', 'ago none')
eq(V.priceKeyText(3, 'iLvl 60-69'), 'Magic - iLvl 60-69', 'key text')
eq(V.priceKeyText(0, ''), '', 'key text empty')
eq(V.priceKeyText(0, 'iLvl 10-19'), 'iLvl 10-19', 'key text band only')

local none = { n7 = 0, n30 = 0, need = 5, days = 30, points = {} }
eq(V.typicalLine(none, 'gold').text, 'No sales of this item yet.', 'no sales')
eq(V.typicalLine(nil, 'gold').text, 'No sales of this item yet.', 'no stats')
local few = { n7 = 3, n30 = 3, need = 5, days = 30, median7 = 1000, min7 = 900, max7 = 1100, lo = 900, hi = 1100, last = 1000, lastAgo = 120, units7 = 3, points = {} }
eq(V.typicalLine(few, 'gold').text, 'Typical price: not enough sales yet (3 of 5).', 'minimum sample')
local full = { n7 = 8, n30 = 10, need = 5, days = 30, median7 = 1000, min7 = 1, max7 = 1000000, lo = 950, hi = 1050, last = 1000,
  lastAgo = 3600, units7 = 9, typical = 1000, basis = '7d', points = {} }
eq(V.typicalLine(full, 'gold').text, 'Typical price: 1,000 gold each (median of 8 sales, 7 days)', 'typical 7d')
eq(V.typicalLine({ n7 = 1, n30 = 6, typical = 2025, basis = '30d', days = 30 }, 'coins').text,
  'Typical price: 2,025 Chaos Coins each (daily medians of 6 sales, 30 days)', 'typical 30d coins')
local lines = V.priceStatsLines(full, 'gold')
eq(#lines, 4, 'four lines')
eq(lines[2].text, 'Last sale: 1,000 gold, 1h ago', 'last sale')
eq(lines[3].text, '7 days: median 1,000, 8 sales (9 units)', 'week')
eq(lines[4].text, 'Usual range: 950 - 1,050 (lowest 1, highest 1,000,000)', 'trimmed range')
lines = V.priceStatsLines(few, 'gold')
eq(lines[4].text, 'Lowest 900, highest 1,100', 'untrimmed range')
lines = V.priceStatsLines({ n7 = 0, n30 = 4, need = 5, days = 30, last = 700, lastAgo = 9 * 86400, points = {} }, 'gold')
eq(lines[3].text, 'No sales in 7 days; 4 in 30 days.', 'only older sales')
eq(V.priceCurrency({ gold = full, coins = few }), 'gold', 'gold first')
eq(V.priceCurrency({ gold = none, coins = few }), 'coins', 'coins when gold has none')
eq(V.priceCurrency({ gold = full, coins = few }, 'coins'), 'coins', 'coins asked')
eq(V.priceCurrency({ gold = full, coins = none }, 'coins'), 'gold', 'coins asked but empty')
eq(V.priceCurrency({}), 'gold', 'nothing: gold')

-- ------------------------------------------------------------------ the Sell form
eq(V.suggestPrice(1000, 1), 1000, 'suggest 1000')
eq(V.suggestPrice(123456, 1), 123000, 'suggest: 3 significant digits')
eq(V.suggestPrice(987, 1), 987, 'suggest small')
eq(V.suggestPrice(50, 20, 100), 1000, 'suggest x units')
eq(V.suggestPrice(3, 1, 100), 100, 'suggest at least the minimum')
eq(V.suggestPrice(nil, 1), nil, 'no typical, no suggestion')
eq(V.suggestPrice(1234567, 2), 2460000, 'suggest 1.23m x2')
local warn = { low = 0.5, high = 2.0 }
eq(V.sellWarning(1000, 1, 1000, warn, 'gold'), nil, 'at typical: no warning')
eq(V.sellWarning(600, 1, 1000, warn, 'gold'), nil, '60%: no warning')
local w = V.sellWarning(400, 1, 1000, warn, 'gold')
eq(w and w.kind, 'low', 'far below')
eq(w and w.text, 'Far below the typical price: 40% of 1,000 gold each. Is that what you want?', 'below text')
w = V.sellWarning(25000, 10, 1000, warn, 'gold')
eq(w and w.kind, 'high', 'far above per unit')
eq(w and w.text, 'Far above the typical price: 250% of 1,000 gold each; it may not sell.', 'above text')
eq(V.sellWarning(10000, 10, 1000, warn, 'gold'), nil, 'a stack at the typical unit price')
eq(V.sellWarning(0, 1, 1000, warn, 'gold'), nil, 'no price yet')
eq(V.sellWarning(5, 1, nil, warn, 'gold'), nil, 'no typical')

-- ------------------------------------------------------------------ Browse marks
local m = V.rowMark({ gold = 400, count = 1, typ = 1000, tcur = 'gold', pm = 'low' })
eq(m and m.text, '60% under typical', 'low mark')
eq(m and m.kind, 'low', 'low kind')
m = V.rowMark({ gold = 0, coins = 50, count = 1, typ = 20, tcur = 'coins', pm = 'high' })
eq(m and m.text, '150% over typical', 'high mark coins')
m = V.rowMark({ gold = 2000, count = 20, typ = 50, tcur = 'gold', pm = 'high' })
eq(m and m.text, '100% over typical', 'stack: per unit')
eq(V.rowMark({ gold = 1000, count = 1, typ = 1000, tcur = 'gold' }), nil, 'no mark')
eq(V.rowMark({ gold = 1000, count = 1, pm = 'low' }), nil, 'mark without typical')
eq(V.rowTypicalText({ typ = 1500, tcur = 'gold' }), 'Typical price: 1,500 gold each', 'row typical text')
eq(V.rowTypicalText({}), nil, 'no typical text')

-- ------------------------------------------------------------------ the chart
local pts = { { h = 20, p = 700, v = 1 }, { h = 9, p = 800, v = 1 }, { h = 3, p = 1000, v = 4 }, { h = 0, p = 1025, v = 2 } }
local rects = V.priceChart(pts, 30, 300, 90)
local lineN, volN = 0, 0
for _, r in ipairs(rects) do
  if r.kind == 'line' then lineN = lineN + 1 else volN = volN + 1 end
  ok(r.x >= 0 and r.y >= 0 and r.x + r.w <= 300 + 2 and r.y + r.h <= 90 + 2, 'inside the box ' .. _)
end
eq(lineN, 7, '4 steps + 3 risers')
eq(volN, 4, 'a sales bar per day')
-- the oldest day sits left of the newest
local first, last
for _, r in ipairs(rects) do
  if r.kind == 'line' and r.h == 2 then
    first = first or r
    last = r
  end
end
ok(first.x < last.x, 'oldest left')
ok(first.y > last.y, 'cheaper lower')
eq(#V.priceChart({}, 30, 300, 90), 0, 'no points, no chart')
local sc = V.chartScale(pts, 30)
eq(sc.high, '1,025', 'scale high')
eq(sc.low, '700', 'scale low')
eq(sc.from, '29 days ago', 'scale from')
eq(V.chartScale({}, 30), nil, 'no scale')

print(string.format('marketpriceview_test: %d checks, %d failures', n, fails))
if fails > 0 then os.exit(1) end
