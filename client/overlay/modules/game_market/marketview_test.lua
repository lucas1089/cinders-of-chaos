-- Run from the repo root: luajit client/overlay/modules/game_market/marketview_test.lua (also lua5.3)
-- The market window's logic (marketview.lua): texts, fee and tax (the same numbers as the server's market_core.lua for
-- market_config.lua), price input, the Sell form check, the Browse filter, row texts, the modifier filter (Codex catalog,
-- typeahead choices, the form -> request and its checks, matched tooltip lines).
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
eq(f.mods and f.mods[1].k, 'chaos_mod_attackspeed', 'one modifier (the old field) becomes a row')
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

-- the real Codex data, when present
local okData = pcall(dofile, here .. '/../game_codex/codex_data.lua')

-- the modifier filter: the catalog and the typeahead choices
local codex = { tabs = { { entries = { { id = 'mod:rarity_firedamage', name = 'Fire Damage', side = 'prefix' },
  { id = 'mod:rarity_arcaneabsorb', name = 'Arcane Absorb', side = 'suffix' }, { id = 'mod:chaos_mod_es', name = 'Energy Shield',
  side = 'prefix', tv = { '+1', '+50' } }, { id = 'mod:chaos_mod_espct', name = 'Energy Shield', side = 'prefix', tv = { '+1%', '+9%' } },
  { id = 'power:deathblast', name = 'Death Blast', side = 'suffix' }, { id = 'orb:x', name = 'Orb' } } } } }
local cat = V.modCatalog(codex)
eq(#cat.list, 5, 'catalog: four modifiers and a power')
eq(cat.list[1].group .. ':' .. cat.list[1].name, 'prefix:Energy Shield (+50)', 'prefixes first, by name; a repeated name tells its value')
eq(cat.byKey.chaos_mod_deathblast.group, 'power', 'a power is its own group, key chaos_mod_<power>')
eq(cat.list[5].key, 'chaos_mod_deathblast', 'powers last')
local ch, first = V.modChoices(cat, '')
eq(#ch, 1 + 3 + 5, 'no search: a heading per group and every modifier')
eq(ch[2][1] .. '|' .. ch[2][2], '-- Prefixes --|', 'a heading chooses nothing')
eq(first, 'chaos_mod_es', 'first match')
ch, first = V.modChoices(cat, 'ENERGY  shield #')
eq(#ch, 1, 'every word must be in the name (a # is a plain character)')
ch, first = V.modChoices(cat, ' energy ')
eq(#ch, 4, 'search: one heading and two matches')
eq(first, 'chaos_mod_es', 'the first match is chosen')
ch, first = V.modChoices(cat, 'blast')
eq(ch[2][1], '-- Legendary powers --', 'the power heading')
ch, first = V.modChoices(cat, 'zzz')
eq(ch[1][1] .. tostring(first), 'No modifier matchesnil', 'nothing found')
local texts = {}
for _, o in ipairs(V.modChoices(cat, '')) do
  eq(texts[o[1]], nil, 'combo texts unique: ' .. o[1])
  texts[o[1]] = true
end
eq(#V.tierOptions(8), 9, 'any tier + T1..T8')
eq(V.tierOptions(8)[6][1] .. '=' .. V.tierOptions(8)[6][2], 'T5+=5', 'T5 or better')
eq(V.tierOptions(8)[9][1], 'T8', 'T8 is the best')

-- the form -> the request
local req, why = V.modRequest({ rows = { { key = 'rarity_firedamage', min = '10', tier = 5 }, { key = '', min = '3' },
  { key = 'chaos_mod_deathblast', min = '', tier = 0 } }, mode = 'all', sockets = '2', quality = '', freeS = true, power = true })
eq(#req.mods, 2, 'rows without a modifier left out')
eq(req.mods[1].k .. '/' .. req.mods[1].min .. '/' .. req.mods[1].t, 'rarity_firedamage/10/5', 'row: key, min value, min tier')
eq(req.mods[2].min, nil, 'no minimum: not sent')
eq(req.need, nil, 'all rows: no need sent')
eq(req.sockets, 2, 'sockets')
eq(req.quality, nil, 'no quality')
eq(tostring(req.freeS) .. tostring(req.power) .. tostring(req.freeP), 'truetruenil', 'flags')
eq(V.modCount(req), 5, 'conditions counted: two rows, sockets, free suffix, power')
req = V.modRequest({ rows = { { key = 'a' }, { key = 'b' }, { key = 'c' } }, mode = 'count', need = '2' })
eq(req.need, 2, 'at least 2 of 3')
req = V.modRequest({ rows = { { key = 'a' }, { key = 'b' } }, mode = 'count', need = '2' })
eq(req.need, nil, 'at least 2 of 2 = all')
req, why = V.modRequest({ rows = { { key = 'a' }, { key = 'b' } }, mode = 'count', need = '3' })
eq(req, nil, 'at least 3 of 2 refused')
local saysRange = why and why:find('1 to 2') ~= nil
eq(saysRange, true, 'says the range')
eq((V.modRequest({ rows = { { key = 'a' } }, mode = 'count', need = 'x' })), nil, 'need not a number')
eq((V.modRequest({ rows = { { key = 'a' }, { key = 'a', tier = 3 } } })), nil, 'a modifier twice refused')
eq((V.modRequest({ rows = { { key = 'a', min = '1.5' } } })), nil, 'a fraction refused')
eq((V.modRequest({ rows = { { key = 'a', min = '-3' } } })), nil, 'a negative refused')
eq((V.modRequest({ sockets = 'two' })), nil, 'sockets not a number')
local seven = {}
for i = 1, 7 do seven[i] = { key = 'k' .. i } end
req, why = V.modRequest({ rows = seven })
eq(req, nil, 'seven rows refused')
eq(why, 'At most 6 modifiers per search.', 'says the limit')
req = V.modRequest({ rows = { { key = 'a', min = '99999999', tier = 12 } }, sockets = '40', quality = '99' })
eq(req.mods[1].min .. '/' .. req.mods[1].t .. '/' .. req.sockets .. '/' .. req.quality, '1000000/8/8/30', 'numbers clamped to the server limits')
eq(#V.modRequest({}).mods, 0, 'empty section')
-- the whole Browse filter with the section
f, why = V.filter({ q = 'axe', modForm = { rows = { { key = 'rarity_firedamage', tier = 3 } }, freeP = true }, page = 1 })
eq(f.mods[1].t .. '/' .. tostring(f.freeP) .. '/' .. f.q, '3/true/axe', 'filter carries the section')
f, why = V.filter({ modForm = { rows = { { key = 'a', min = 'x' } } } })
eq(f, nil, 'an invalid section: no filter')
eq(why, 'Row 1: the minimum value is a whole number.', 'and why')
-- the tooltip lines the search matched
local tip = { mods = { { k = 'rarity_fireDamage', t = 'Fire +12% dmg', v = 12, tr = 3 }, { k = 'chaos_mod_life', t = 'Life +50', v = 50, tr = 8 },
  { k = 'rarity_criticalhitchance', g = 'special', t = 'Critical +2%, +6%', v = 2, v2 = 6, tr = 7 } } }
local lines = V.matchedMods(tip, { mods = { { k = 'rarity_firedamage', min = 10 }, { k = 'chaos_mod_life', t = 9 },
  { k = 'rarity_criticalhitchance', min = 5 } } })
eq(#lines, 2, 'two rows matched (a tier too low is not)')
eq(lines[1].text, 'Matches: Fire +12% dmg (T3)', 'matched line (a key in mixed case on the item)')
eq(#V.matchedMods(tip, nil), 0, 'no search: nothing')
-- the real Codex data: names unique in the combo, every group present
if okData and CodexData then
  local real = V.modCatalog(CodexData)
  local seen, groups = {}, {}
  local dup = false
  for _, m in ipairs(real.list) do
    if seen[m.name] then dup = true end
    seen[m.name] = true
    groups[m.group] = (groups[m.group] or 0) + 1
  end
  eq(dup, false, 'the Codex modifier names are unique in the combo')
  eq((groups.prefix or 0) > 10 and (groups.suffix or 0) > 10 and (groups.power or 0) >= 12, true, 'prefixes, suffixes and powers')
end

local sorted = V.sortSellable({ { name = 'b', why = 'locked' }, { name = 'a', rarity = 1 }, { name = 'c', rarity = 5 } })
eq(sorted[1].name .. sorted[2].name .. sorted[3].name, 'cab', 'listable first, by rarity')

print(string.format('marketview_test: %d checks, %d failed', n, fails))
os.exit(fails == 0 and 0 or 1)
