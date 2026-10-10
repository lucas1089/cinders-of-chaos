-- Run from the repo root: luajit client/overlay/modules/game_market/marketview_test.lua (also lua5.3)
-- The market window's logic (marketview.lua): texts, fee and tax (the same numbers as the server's market_core.lua for
-- market_config.lua), price input, the Sell form check, the Browse filter, row texts, the Codex modifier options.
local here = (arg and arg[0] or ''):match('^(.*)/[^/]*$') or '.'
dofile(here .. '/marketview.lua')
local V = MarketView
local fails, n = 0, 0
local function eq(a, b, name)
  n = n + 1
  if a ~= b then fails = fails + 1; print('FAIL ' .. name .. ': got ' .. tostring(a) .. ', want ' .. tostring(b)) end
end

eq(V.money(1234567), '1,234,567', 'money')
eq(V.money(999), '999', 'small')
eq(V.money(-5000), '-5,000', 'negative')
eq(V.short(2500000), '2.5m', 'short m')
eq(V.short(25000), '25k', 'short k')
eq(V.short(9999), '9,999', 'short small')
eq(V.timeLeft(2 * 86400 + 5 * 3600 + 7), '2d 5h', 'days')
eq(V.timeLeft(3 * 3600 + 12 * 60), '3h 12m', 'hours')
eq(V.timeLeft(45 * 60), '45m', 'minutes')
eq(V.timeLeft(20), '<1m', 'seconds')
eq(V.timeLeft(0), 'ended', 'ended')

eq(V.parseAmount('5k'), 5000, '5k')
eq(V.parseAmount('2.5m'), 2500000, '2.5m')
eq(V.parseAmount('1,500'), 1500, 'commas')
eq(V.parseAmount(''), 0, 'empty = 0')
eq(V.parseAmount('1.5'), nil, 'fraction')
eq(V.parseAmount('-3'), nil, 'negative')
eq(V.parseAmount('abc'), nil, 'text')
eq(V.parseAmount('1b'), 1000000000, '1b')

-- the server's meta for market_config.lua
local meta = { fee = { pct = 1, min = 100, max = 1000000, coinGold = 100 }, tax = { gold = 5, coins = 5 },
  price = { gold = { min = 100, max = 2000000000 }, coins = { min = 1, max = 100000 } }, defaultDuration = 3 }
eq(V.fee(meta, 100000, 0), 1000, 'fee 1%')
eq(V.fee(meta, 500, 0), 100, 'fee minimum')
eq(V.fee(meta, 2000000000, 0), 1000000, 'fee maximum')
eq(V.fee(meta, 0, 100), 100, 'coins-only fee')
eq(V.fee(meta, 0, 5000), 5000, 'coins-only fee, bigger')
local tax, net = V.tax(meta, 'gold', 100000)
eq(tax .. '/' .. net, '5000/95000', 'gold tax')
tax, net = V.tax(meta, 'coins', 19)
eq(tax .. '/' .. net, '0/19', 'small coin price: no tax')

local s, why = V.checkSell(meta, { gold = '100k', coins = '', count = 1, have = 1, days = 7 })
eq(s and s.gold, 100000, 'sell gold')
eq(s and s.days, 7, 'sell days')
s, why = V.checkSell(meta, { gold = '', coins = '', count = 1, have = 1 })
eq(s, nil, 'no price')
eq(why:find('price') ~= nil, true, 'why: price')
eq((V.checkSell(meta, { gold = '50', count = 1, have = 1 })), nil, 'below the gold minimum')
eq((V.checkSell(meta, { coins = '200000', count = 1, have = 1 })), nil, 'over the coin maximum')
eq((V.checkSell(meta, { gold = '1000', count = 21, have = 20 })), nil, 'more than the stack')
eq((V.checkSell(meta, { gold = '1.5k5', count = 1, have = 1 })), nil, 'bad number')
eq(V.checkSell(meta, { coins = '100', count = 20, have = 50 }).count, 20, 'part of a stack')
eq(V.checkSell(meta, { gold = '1000', count = 1, have = 1 }).days, 3, 'default duration')

local f = V.filter({ q = 'sword', cat = 'weapon', rarity = '5', cur = 'gold', ilvlMin = '100', ilvlMax = 'x', priceMin = '10k',
  priceMax = '', mod = 'chaos_mod_attackspeed', sort = 'price', page = 2 })
eq(f.ilvlMin, 100, 'filter ilvl min')
eq(f.ilvlMax, 0, 'unreadable number left out')
eq(f.priceMin, 10000, 'filter price min')
eq(f.rarity, 5, 'filter rarity')
eq(f.page, 2, 'filter page')
eq(V.filter({}).sort, 'new', 'default sort')

local lines = V.priceLines({ gold = 1500, coins = 20 })
eq(#lines, 2, 'two prices')
eq(lines[1].text, '1,500 gold', 'gold line')
eq(lines[2].cur, 'coins', 'coins line')
eq(#V.priceLines({ gold = 0, coins = 5 }), 1, 'coins only')

eq(V.subLine({ rarity = 5, ilvl = 150, cat = 'weapon', seller = 'Ash', left = 3700 }), 'Legendary - iLvl 150 - Weapons - by Ash - 1h 1m left', 'sub line')
eq(V.subLine({ unique = true, rarity = 0, cat = 'jewel', left = 60 }), 'Unique - Jewellery - 1m left', 'unique sub line')
eq(V.subLine({ rarity = 0, cat = 'orb', left = 90000 }), 'Orbs - 1d 1h left', 'plain sub line')
eq(V.stateLine({ state = 'sold', buyer = 'Bob', paid = 100000, tax = 5000, cur = 'gold' }), 'Sold to Bob for 100,000 gold (tax 5,000, you got 95,000)', 'sold line')
eq(V.stateLine({ state = 'expired' }):find('inbox') ~= nil, true, 'expired line')
eq(V.historyLine({ side = 'bought', seller = 'Ann', paid = 20, cur = 'coins' }), 'Bought from Ann for 20 coins', 'history bought')
eq(V.historyLine({ side = 'sold', buyer = 'Bob', paid = 1000, tax = 50 }), 'Sold to Bob for 1,000 gold (tax 50)', 'history sold')
eq(V.pageText(2, 5, 57), 'Page 2 / 5  (57 offers)', 'page text')
eq(V.pageText(1, 1, 1), 'Page 1 / 1  (1 offer)', 'one offer')

local opts = V.modOptions({ tabs = { { entries = { { id = 'mod:rarity_firedamage', name = 'Fire Damage' },
  { id = 'mod:chaos_mod_attackspeed', name = 'Attack Speed' }, { id = 'orb:x', name = 'Orb' },
  { id = 'mod:rarity_firedamage', name = 'Fire Damage' }, { id = 'power:deathblast', name = 'Death Blast' } } } } })
eq(#opts, 4, 'any + two modifiers + a power (no orbs, no duplicates)')
eq(opts[3][1] .. '=' .. opts[3][2], 'Death Blast (power)=chaos_mod_deathblast', 'a power filters on its chaos_mod_ key')
eq(opts[2][1] .. '=' .. opts[2][2], 'Attack Speed=chaos_mod_attackspeed', 'sorted by name, value = key')
eq(#V.modOptions(nil), 1, 'no Codex data: only Any')
-- the real Codex data, when present
local okData = pcall(dofile, here .. '/../game_codex/codex_data.lua')
if okData and CodexData then
  local real = V.modOptions(CodexData)
  eq(#real > 30, true, 'the Codex modifiers (' .. #real .. ')')
end

local sorted = V.sortSellable({ { name = 'b', why = 'locked' }, { name = 'a', rarity = 1 }, { name = 'c', rarity = 5 } })
eq(sorted[1].name .. sorted[2].name .. sorted[3].name, 'cab', 'listable first, by rarity')

print(string.format('marketview_test: %d checks, %d failed', n, fails))
os.exit(fails == 0 and 0 or 1)
