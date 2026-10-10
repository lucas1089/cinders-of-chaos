-- luajit orbexchangeview_test.lua && lua5.3 orbexchangeview_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'orbexchangeview.lua')
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(c, what) eq(not not c, true, what) end
local V = OrbExchangeView

local meta = { orbs = { { k = 'fate', n = 'Orb of Fate', item = 1 }, { k = 'awakening', n = 'Orb of Awakening', item = 2 },
  { k = 'whetstone', n = 'Whetstone', item = 3 } },
  fees = { goldBps = 200, orbPairGold = 500 }, min = { orb = 1, gold = 1000 }, max = { orb = 100000, gold = 2000000000 },
  durations = { 1, 3, 7, 14 }, defaultDuration = 7 }

-- numbers
eq(V.money(1234567), '1,234,567', 'money')
eq(V.money(-1000), '-1,000', 'negative money')
eq(V.parseAmount('5k'), 5000, '5k')
eq(V.parseAmount('2.5m'), 2500000, '2.5m')
eq(V.parseAmount('1,000'), 1000, 'separators')
eq(V.parseAmount(' 12 '), 12, 'spaces')
eq(V.parseAmount('abc'), nil, 'not a number')
eq(V.parseAmount(''), nil, 'empty')
eq(V.parseAmount('-5'), nil, 'no negatives')
eq(V.parsePrice('0.25'), 0.25, 'price decimals')
eq(V.parsePrice('4.5k'), 4500, 'price 4.5k')
eq(V.parsePrice('0'), nil, 'price zero')
eq(V.priceText(5000), '5,000', 'price text')
eq(V.priceText(0.3333333), '0.3333', 'price fraction')
eq(V.priceText(12.5), '12.5', 'price trims zeros')
eq(V.compact(25000), '25k', 'compact k')
eq(V.compact(1500000), '1.5m', 'compact m')
eq(V.priceInput(10 / 3, true), '3.333334', 'price input up')
eq(V.priceInput(10 / 3, false), '3.333333', 'price input down')
eq(V.priceInput(5000, true), '5000', 'price input whole')

-- names
eq(V.assetName(meta, 'gold'), 'gold', 'gold name')
eq(V.assetName(meta, 'fate'), 'Orb of Fate', 'orb name')
eq(V.shortName(meta, 'fate'), 'Fate', 'short name')
eq(V.shortName(meta, 'whetstone'), 'Whetstone', 'short name without prefix')
local q = V.quotes(meta, 'fate')
eq(q[1], 'gold', 'gold is the first quote')
eq(#q, 3, 'the other orbs follow')
eq(q[2], 'awakening', 'not the base itself')

-- the form
local req, prev = V.form({ side = 'sell', qty = '10', price = '5k' }, 'fate', 'gold', meta)
eq(req.give, 'fate', 'sell gives the base')
eq(req.giveQty, 10, 'sell quantity')
eq(req.want, 'gold', 'sell wants the quote')
eq(req.wantQty, 50000, 'sell total')
eq(req.days, 7, 'default days')
eq(prev.fee, 1000, 'the seller pays 2% of the gold')
eq(prev.receive, 49000, 'and receives the rest')
ok(V.previewText(req, prev, 'sell', 'fate', 'gold', meta):find('Fee 1,000 gold'), 'preview names the fee')
req, prev = V.form({ side = 'buy', qty = '3', price = '4500', days = 14 }, 'fate', 'gold', meta)
eq(req.give, 'gold', 'buy gives the quote')
eq(req.giveQty, 13500, 'buy total')
eq(req.want, 'fate', 'buy wants the base')
eq(req.wantQty, 3, 'buy quantity')
eq(req.days, 14, 'days')
eq(prev.fee, 0, 'no fee for the buyer')
ok(V.previewText(req, prev, 'buy', 'fate', 'gold', meta):find('No fee'), 'preview: no fee')
req, prev = V.form({ side = 'buy', qty = '3', price = '3.333334' }, 'fate', 'awakening', meta)
eq(req.giveQty, 11, 'a buyer rounds up (3 x 3.33 -> 11)')
eq(prev.placeFee, 500, 'orb-for-orb placing fee')
req = V.form({ side = 'sell', qty = '3', price = '3.333333' }, 'fate', 'awakening', meta)
eq(req.wantQty, 9, 'a seller rounds down (3 x 3.33 -> 9)')
local r, why = V.form({ side = 'sell', qty = '', price = '5' }, 'fate', 'gold', meta)
ok(r == nil and why:find('how many'), 'quantity missing')
r, why = V.form({ side = 'sell', qty = '2', price = '' }, 'fate', 'gold', meta)
ok(r == nil and why:find('price'), 'price missing')
r, why = V.form({ side = 'sell', qty = '2', price = '100' }, 'fate', 'gold', meta)
ok(r == nil and why:find('1,000 gold'), 'below the gold minimum')
r, why = V.form({ side = 'sell', qty = '200000', price = '1' }, 'awakening', 'fate', meta)
ok(r == nil and why:find('At most'), 'above the orb maximum')
r, why = V.form({ side = 'sell', qty = '1', price = '0.1' }, 'awakening', 'fate', meta)
ok(r == nil and why:find('less than one'), 'a total below one')

-- the book
local book = { asks = { { p = 5000, q = 8, n = 2, t = 40000 }, { p = 5500, q = 1, n = 1, t = 5500 } },
  bids = { { p = 4500, q = 2, n = 1, t = 9000 }, { p = 4000, q = 10, n = 1, t = 40000 } } }
local rows = V.bookRows(book, 8)
eq(#rows, 5, 'two asks, the spread, two bids')
eq(rows[1].kind, 'ask', 'asks on top')
eq(rows[1].price, '5,500', 'highest ask first')
eq(rows[2].price, '5,000', 'best ask just above the spread')
eq(rows[3].kind, 'spread', 'spread in the middle')
ok(rows[3].price:find('500'), 'spread text')
eq(rows[4].price, '4,500', 'best bid just below')
eq(rows[5].bar, 1, 'the biggest level has the full bar')
eq(rows[2].bar, 0.8, 'others in proportion')
eq(rows[2].total, '40k', 'total compact')
eq(V.bookRows({}, 8)[1].price, 'No orders', 'empty book')
eq(#V.bookRows(book, 1), 3, 'rows per side')
local fill = V.fromRow(rows[2])
eq(fill.side, 'buy', 'a click on an ask buys')
eq(fill.price, '5000', 'at its price')
eq(fill.qty, '8', 'all of the level')
eq(V.fromRow(rows[4]).side, 'sell', 'a click on a bid sells')
eq(V.fromRow(rows[3]), nil, 'the spread is not a price')
-- a click on an ask fills it: the form's order crosses it
local fr = V.fromRow({ kind = 'ask', p = 10 / 3, q = 3 })
req = V.form({ side = fr.side, qty = fr.qty, price = fr.price }, 'fate', 'awakening', meta)
ok(req.giveQty * 3 >= 10 * req.wantQty, 'the order from a click crosses the ask (' .. req.giveQty .. ' for ' .. req.wantQty .. ')')

-- stats and the chart
local text, color = V.changeText(12.34)
eq(text, '+12.3%', 'change up')
eq(color, V.COLORS.up, 'up colour')
eq((V.changeText(-3)), '-3.0%', 'change down')
eq((V.changeText(nil)), '-', 'no change')
local rects = V.chart({ { h = 5, p = 4500, v = 2 }, { h = 1, p = 5000, v = 3 }, { h = 0, p = 5500, v = 1 } }, 24, 240, 80)
local lines, vols = 0, 0
for _, rc in ipairs(rects) do
  ok(rc.x >= 0 and rc.x + rc.w <= 242 and rc.y >= 0 and rc.y + rc.h <= 80, 'inside the box ' .. rc.x .. ',' .. rc.y)
  if rc.kind == 'line' then lines = lines + 1 else vols = vols + 1 end
end
eq(lines, 5, 'three steps and two risers')
eq(vols, 3, 'one volume bar per hour with trades')
ok(rects[1].y > rects[4].y, 'a higher price is drawn higher')
eq(#V.chart({}, 24, 240, 80), 0, 'no points, no chart')
eq(#V.chart({ { h = 0, p = 100, v = 1 } }, 24, 240, 80), 2, 'one flat point')

-- my orders
local o = { id = 7, give = 'fate', giveQty = 10, want = 'gold', wantQty = 50000, given = 4, got = 20000, state = 'active', left = 90000 }
eq(V.orderTitle(o, meta), '10 Orb of Fate for 50,000 gold', 'order title')
ok(V.orderSub(o, meta):find('4 / 10 given'), 'order progress text')
ok(V.orderSub(o, meta):find('5,000 gold per Fate'), 'order ratio')
ok(V.orderSub(o, meta):find('1d 1h left'), 'time left')
eq(V.progress(o), 0.4, 'progress')
o.state, o.refunded = 'cancelled', 6
ok(V.orderSub(o, meta):find('^cancelled, 6 back'), 'closed order: the state first')
eq(V.orderPrice({ give = 'gold', giveQty = 13500, want = 'fate', wantQty = 3 }, meta), '4,500 gold per Fate', 'a buy order in gold per orb')
eq(V.orderPrice({ give = 'awakening', giveQty = 100, want = 'fate', wantQty = 4 }, meta), '25 Awakening per Fate', 'two orbs: the larger way round')
eq(V.orderPrice({ give = 'fate', giveQty = 1, want = 'awakening', wantQty = 30 }, meta), '30 Awakening per Fate', 'two orbs the other way')
eq(V.fillText({ ago = 120, gave = 'fate', gaveQty = 2, got = 'gold', gotQty = 9800, fee = 200 }, meta),
  '2m ago: gave 2 Orb of Fate, got 9,800 gold (fee 200)', 'fill text')
eq(V.fillText({ ago = 5, gave = 'fate', gaveQty = 1, got = 'gold', gotQty = 4900 }, meta), 'just now: gave 1 Orb of Fate, got 4,900 gold',
  'fill text now')
eq(V.ago(30), 'now', 'ago now')
eq(V.ago(7200), '2h', 'ago hours')
eq(V.timeLeft(0), 'ending', 'time left none')
eq(V.timeLeft(600), '10m', 'time left minutes')

print(string.format('orbexchangeview_test: %d checks, %d failed', checks, fails))
os.exit(fails == 0 and 0 or 1)
