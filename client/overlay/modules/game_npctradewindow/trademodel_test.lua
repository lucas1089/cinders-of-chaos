-- luajit trademodel_test.lua && lua5.3 trademodel_test.lua
-- trademodel.lua: names, categories, search and sort, amounts and their limits, totals, the Sell all preview, the ignore
-- list, the session and the sale queue (the same cases the base's queue was held to: one packet at a time, the next only on
-- the server's acknowledgment, a timeout fails, an unrelated update is no acknowledgment).
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'trademodel.lua')
local M = TradeModel
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- names
eq(M.properName('sword of valor'), 'Sword of Valor', 'small words stay small')
eq(M.properName('the last ember'), 'The Last Ember', 'the first word is always a capital')
eq(M.properName("hunter's bow"), "Hunter's Bow", 'apostrophe')
eq(M.properName('ASHBORNE ARMOR'), 'Ashborne Armor', 'upper case')
eq(M.properName(nil), '', 'nil')

-- categories: the market category wins, then the name, then the slot
eq(M.category({ market = 10, name = 'x' }), 'potions', 'market potions')
eq(M.category({ market = 12 }), 'runes', 'market runes')
eq(M.category({ market = 16 }), 'ammo', 'market ammo')
eq(M.category({ market = 20 }), 'weapons', 'market swords')
eq(M.category({ market = 13 }), 'armor', 'market shields')
eq(M.category({ market = 14 }), 'tools', 'market tools')
eq(M.category({ market = 0, name = 'strong health potion' }), 'potions', 'no market data: the name')
eq(M.category({ name = 'ember arrow' }), 'ammo', 'arrow')
eq(M.category({ name = 'Sudden Death Rune' }), 'runes', 'rune')
eq(M.category({ name = 'shroud', clothSlot = 4 }), 'armor', 'the slot')
eq(M.category({ name = 'whisper', clothSlot = 9 }), 'jewelry', 'ring slot')
eq(M.category({ name = 'a thing' }), 'other', 'nothing known')
eq(M.category(nil), 'other', 'nil facts')
eq(M.category({ market = 10, name = 'rune' }), 'potions', 'market beats the name')
eq(M.categoryLabel('runes'), 'Runes', 'label')
eq(M.categoryLabel('nope'), 'Other', 'unknown label')

-- sort cycle
eq(M.nextSort('name'), 'price', 'name -> price')
eq(M.nextSort('weight'), 'name', 'weight -> name')
eq(M.nextSort('x'), 'name', 'unknown -> name')

-- cards
local function item(name, price, weight, extra)
  local t = { ptr = {}, name = name, price = price, weight = weight or 0 }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end
local items = {
  item('strong health potion', 100, 3.5), item('mana potion', 50, 3.5), item('light arrow', 3, 0.7),
  item('plate armor', 400, 120), item('rope', 50, 18),
}
local have = { [items[1]] = 5, [items[4]] = 1 }
local function facts(it)
  local n = it.name
  return { name = n, market = (n:find('potion') and 10) or (n:find('arrow') and 16) or (n:find('armor') and 1) or 0 }
end
local ctx = { type = M.BUY, items = items, sort = 'name', factsOf = facts, owned = function(it) return have[it] end }
local vis, all = M.cards(ctx)
eq(#all, 5, 'all cards')
eq(#vis, 5, 'all visible in a buy list')
eq(vis[1].name, 'Light Arrow', 'sorted by name')
eq(vis[1].owned, nil, 'owned unknown')
eq(vis[5].owned, 5, 'owned known')
ctx.sort = 'price'
vis = M.cards(ctx)
eq(vis[1].name, 'Light Arrow', 'cheapest first')
eq(vis[5].name, 'Plate Armor', 'dearest last')
ctx.sort = 'weight'
eq(M.cards(ctx)[1].name, 'Light Arrow', 'lightest first')
ctx.search = 'POT'
vis = M.cards(ctx)
eq(#vis, 2, 'search is case blind')
ctx.search = '%'
eq(#M.cards(ctx), 0, 'search takes no patterns')
ctx.search = ''
-- tradable only matters in a sell list
ctx.tradable = function(it) return it ~= items[2] end
eq(#M.cards(ctx), 5, 'a buy list keeps what the player cannot afford')
ctx.type = M.SELL
eq(#M.cards(ctx), 4, 'a sell list drops what the player does not have')
ctx.type = M.BUY
ctx.tradable = nil
-- chips
local chips = M.chips(M.cards(ctx))
eq(chips[1].id, 'all', 'All first'); eq(chips[1].count, 5, 'All counts every card')
eq(chips[2].id, 'potions', 'potions next'); eq(chips[2].count, 2, 'two potions')
eq(chips[3].id, 'ammo', 'then ammo')
eq(#chips, 5, 'only categories that are there (potions, ammo, armor, other)')
eq(#M.filterCategory(M.cards(ctx), 'potions'), 2, 'filter')
eq(#M.filterCategory(M.cards(ctx), 'all'), 5, 'filter all')
eq(#M.filterCategory(M.cards(ctx), nil), 5, 'filter nil')
-- flow
local places, h = M.flow({ 40, 50, 60 }, 100, 20, 4, 4)
eq(places[2].x, 44, 'second chip next to the first'); eq(places[3].y, 24, 'third on a new row'); eq(h, 44, 'two rows')
eq(select(2, M.flow({}, 100, 20)), 0, 'no chips no height')
eq(M.flow({ 300 }, 100, 20)[1].width, 100, 'a chip is never wider than the row')
-- step
local list = { { key = 1 }, { key = 2 }, { key = 3 } }
eq(M.step(list, nil, 1), 1, 'down from nothing: the first'); eq(M.step(list, nil, -1), 3, 'up from nothing: the last')
eq(M.step(list, 1, 1), 2, 'down'); eq(M.step(list, 3, 1), 3, 'down at the end stays'); eq(M.step(list, 1, -1), 1, 'up at the top stays')
eq(M.step({}, nil, 1), nil, 'empty list')

-- amounts, buying
local potion = items[1]
local b = { type = M.BUY, money = 1000, freeCapacity = 100, ignoreCapacity = false, bags = false }
local max, why = M.limit(b, potion)
eq(max, 10, 'gold limits to 10 potions'); eq(why, 'gold', 'the reason is gold')
b.money = 100000
max, why = M.limit(b, potion)
eq(max, 28, 'capacity limits to 28 (100 / 3.5)'); eq(why, 'capacity', 'the reason is capacity')
b.freeCapacity = 100000
max, why = M.limit(b, potion)
eq(max, 100, 'at most 100 a click'); eq(why, 'cap', 'the reason is the packet')
b.ignoreCapacity = true; b.freeCapacity = 0
max = M.limit(b, potion)
eq(max, 100, 'ignore capacity')
b.ignoreCapacity = false
max, why = M.limit(b, potion)
eq(max, 0, 'no room at all'); eq(why, 'capacity', 'nothing fits')
b.freeCapacity = 100; b.money = 50
max, why = M.limit(b, potion)
eq(max, 0, 'cannot pay one'); eq(why, 'gold', 'gold again')
-- a weightless item is not held back by capacity
b.freeCapacity = 0; b.money = 1000
eq(M.limit(b, item('gem', 10, 0)), 100, 'weight 0')
-- the shopping bag fee
b.bags = true; b.freeCapacity = 1e6
eq(M.total(b, item('arrow', 3, 0.1, { stackable = true }), 100), 320, 'stack: 20 once')
eq(M.total(b, item('rope', 50, 18), 41), 2050 + 60, 'single items: 20 per 20')
eq(M.total(b, item('rope', 50, 18), 0), 0, 'no fee for nothing')
b.money = 3 * 100 + 19
eq(M.limit(b, item('arrow', 3, 0.1, { stackable = true })), 99, 'the fee is part of the limit')
b.type = M.SELL
eq(M.total(b, item('arrow', 3, 0.1, { stackable = true }), 100), 300, 'no fee when selling')
-- amounts, selling
local s = { type = M.SELL, owned = function(it) return it == potion and 7 or 150 end }
max, why = M.limit(s, potion); eq(max, 7, 'owned 7'); eq(why, 'owned', 'owned reason')
max, why = M.limit(s, items[2]); eq(max, 100, '150 owned: 100 a click'); eq(why, 'cap', 'cap reason')
s.owned = function() return 0 end
max, why = M.limit(s, potion); eq(max, 0, 'nothing to sell'); eq(why, 'owned', 'nothing reason')
eq(M.clampAmount(5, 1, 3), 3, 'clamp above'); eq(M.clampAmount(0, 1, 3), 1, 'clamp below')
eq(M.clampAmount('x', 1, 3), 1, 'clamp text'); eq(M.clampAmount(5, 1, 0), 0, 'nothing to pick')

-- detail
local cardsB = M.cards({ type = M.BUY, items = items, sort = 'name', factsOf = facts })
local card
for _, c in ipairs(cardsB) do if c.item == potion then card = c end end
local d = M.detail({ type = M.BUY, money = 1000, freeCapacity = 100 }, card, 4)
eq(d.amount, 4, 'amount'); eq(d.total, 400, 'total'); eq(d.after, 600, 'gold after')
eq(d.weightTotal, 14, 'weight'); eq(d.capacityAfter, 86, 'capacity after'); eq(d.tooHeavy, false, 'not too heavy')
eq(d.canTrade, true, 'can trade'); eq(d.max, 10, 'max')
d = M.detail({ type = M.BUY, money = 1000, freeCapacity = 100 }, card, 99)
eq(d.amount, 10, 'amount clamped to the max'); eq(d.hint, 'gold', 'at the max the gold is said')
d = M.detail({ type = M.BUY, money = 1000, freeCapacity = 2 }, card, 1)
eq(d.max, 0, 'cannot carry'); eq(d.warn, 'capacity', 'warn: capacity'); eq(d.canTrade, false, 'cannot trade')
d = M.detail({ type = M.BUY, money = 10, freeCapacity = 100 }, card, 1)
eq(d.warn, 'gold', 'warn: gold')
d = M.detail({ type = M.SELL, money = 10, freeCapacity = 5, owned = function() return 3 end }, card, 2)
eq(d.total, 200, 'sell total'); eq(d.after, 210, 'gold after a sale'); eq(d.capacityAfter, 12, 'capacity after a sale')
eq(M.detail({ type = M.BUY }, nil, 1).empty, true, 'nothing selected')

-- Sell all
local sellItems = {
  item('ember shard', 40, 1, { id = 100 }), item('wolf fur', 5, 1, { id = 101 }), item('old flask', 3, 1, { id = 102 }),
  item('ember shard', 40, 1, { id = 100 }), item('cursed blade', 900, 20, { id = 103 }), item('lost thing', 7, 1, { id = 104 }),
}
local qty = { [100] = 12, [101] = 30, [102] = 4, [103] = 1, [104] = 0 }
local rows = M.sellAllRows({
  items = sellItems, owned = function(it) return qty[it.id] end, ignored = { [101] = true },
  idOf = function(it) return it.id end, subtypeOf = function(it) return it == sellItems[3] and 3 or 0 end,
  bulkOk = function(it) return it.id ~= 102 end, marketValue = function(it) return it.id == 100 and 50 or nil end,
})
eq(#rows, 4, 'the duplicate and the empty one are left out')
eq(rows[1].id, 103, 'dearest subtotal first'); eq(rows[1].subtotal, 900, 'subtotal')
eq(rows[2].id, 100, 'then the shards (480)'); eq(rows[2].belowMarket, true, 'shards sell under the market value')
local byId = {}
for _, r in ipairs(rows) do byId[r.id] = r end
eq(byId[101].ignored, true, 'ignore list'); eq(byId[102].manual, true, 'a subtype item is sold one by one')
local t = M.sellAllTotals(rows)
eq(t.rows, 2, 'two rows are sold'); eq(t.pieces, 13, 'pieces'); eq(t.gold, 1380, 'gold'); eq(t.below, 1, 'one under the market value')
t = M.sellAllTotals(rows, { ['100:0'] = true })
eq(t.rows, 1, 'an unticked row is left out'); eq(t.gold, 900, 'gold without it')
eq(#M.sellAllRows({ items = {}, owned = function() return 1 end }), 0, 'empty list')

-- ignore list
local clean = M.cleanIgnoreList({ 5, 5, 'x', 0, 70000, 2.5, 3, true })
eq(#clean, 2, 'only whole ids in range, once'); eq(clean[1], 3, 'sorted'); eq(clean[2], 5, 'sorted 2')
eq(#M.cleanIgnoreList(nil), 0, 'nil list'); eq(M.ignoreSet({ 4 })[4], true, 'set')

-- session
local queueEvents, nextEvent = {}, 0
local function schedule(fn, ms) nextEvent = nextEvent + 1 queueEvents[nextEvent] = { fn = fn, ms = ms } return nextEvent end
local function cancel(e) queueEvents[e] = nil end
local function fire(e) local ev = queueEvents[e] queueEvents[e] = nil if ev then ev.fn() end end
local session = M.newSession(schedule, cancel)
local ran = 0
session:begin()
local e1 = session:schedule(function() ran = ran + 1 end, 10)
fire(e1); eq(ran, 1, 'a callback of the open shop runs')
local e2 = session:schedule(function() ran = ran + 10 end)
session:begin() -- the next shop
eq(queueEvents[e2], nil, 'the old shop\'s event is cancelled')
local e3 = session:schedule(function() ran = ran + 100 end)
session:finish()
fire(e3); eq(ran, 1, 'nothing runs after the shop closed')

-- the sale queue
local inventory = { a = 250, b = 30 }
local price = { a = 10, b = 100 }
local money = 0
local sent, errors, finished = {}, {}, nil
local evs, n = {}, 0
local function sched(fn, ms) n = n + 1 evs[n] = { fn = fn, ms = ms } return n end
local function unsched(e) evs[e] = nil end
local function run() -- run every scheduled non-timeout callback
  local progressed = true
  while progressed do
    progressed = false
    for k, ev in pairs(evs) do
      if ev.ms ~= M.QUEUE_TIMEOUT then evs[k] = nil ev.fn() progressed = true break end
    end
  end
end
local entries = { { key = 'a', price = 10 }, { key = 'b', price = 100 } }
local q = M.newQueue({
  isValid = function() return true end,
  quantity = function(e) return inventory[e.key] end,
  money = function() return money end,
  sell = function(e, amount) sent[#sent + 1] = e.key .. amount end,
  schedule = sched, cancel = unsched,
  onFinish = function(sold, proceeds) finished = { sold, proceeds } end,
  onError = function(m) errors[#errors + 1] = m end,
})
q:start(entries)
eq(sent[1], 'a100', 'the first packet is 100'); eq(#sent, 1, 'one packet at a time')
-- an unrelated money update is no acknowledgment
money = 5; q:onGoods(); run()
eq(#sent, 1, 'an unrelated update does not advance')
money = 0
local function ack(key, amount) inventory[key] = inventory[key] - amount money = money + price[key] * amount q:onGoods() run() end
ack('a', 100); eq(sent[2], 'a100', 'next 100'); ack('a', 100); eq(sent[3], 'a50', 'the rest'); ack('a', 50)
eq(sent[4], 'b30', 'then the next item'); ack('b', 30)
eq(finished and finished[1], 280, 'sold'); eq(finished and finished[2], 250 * 10 + 30 * 100, 'proceeds')
eq(#errors, 0, 'no error')
-- a timeout fails the queue
sent, errors, finished, evs, n = {}, {}, nil, {}, 0
inventory = { a = 5 }
q = M.newQueue({
  isValid = function() return true end, quantity = function(e) return inventory[e.key] end, money = function() return money end,
  sell = function(e, amount) sent[#sent + 1] = amount end, schedule = sched, cancel = unsched,
  onFinish = function() finished = true end, onError = function(m) errors[#errors + 1] = m end,
})
q:start({ { key = 'a', price = 10 } })
for _, ev in pairs(evs) do if ev.ms == M.QUEUE_TIMEOUT then ev.fn() end end
eq(#errors, 1, 'the timeout is an error'); eq(finished, nil, 'and not a finish')
-- an invalid shop stops it quietly
q = M.newQueue({
  isValid = function() return false end, quantity = function() return 5 end, money = function() return 0 end,
  sell = function() error('sold') end, schedule = sched, cancel = unsched,
  onFinish = function() error('finished') end, onError = function() error('error') end,
})
q:start({ { key = 'a', price = 1 } })
eq(q.active, false, 'invalid shop: stopped')
-- the 255 cap: a capped count that stays at 255 still counts when the price was credited
inventory = { a = 255 }; money = 0; sent, finished, evs, n = {}, nil, {}, 0
q = M.newQueue({
  isValid = function() return true end, quantity = function(e) return inventory[e.key] end, money = function() return money end,
  capped = function() return true end, sell = function(e, amount) sent[#sent + 1] = amount end, schedule = sched,
  cancel = unsched, onFinish = function(sold) finished = sold end, onError = function() end,
})
q:start({ { key = 'a', price = 2 } })
money = money + 200; q:onGoods() -- the count stays 255
eq(q.pending, nil, 'capped count: acknowledged by the credited price')

print(string.format('trademodel_test: %d checks, %d failed', checks, fails))
os.exit(fails == 0 and 0 or 1)
