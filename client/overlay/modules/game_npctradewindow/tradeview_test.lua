-- luajit tradeview_test.lua && lua5.3 tradeview_test.lua   (CI runs every client *_test.lua from the repo root)
-- tradeview.lua on a fake widget engine. The fake builds every widget from the REAL tradewindow.otui (the ids under each
-- style, nested ones too), so a lookup of an id the file lacks raises here as it does in the client. It plays the header,
-- the tabs, the cards, the chips, the side panel and the Sell all window.
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

dofile(here .. 'tradefake.lua')
local fake = TradeFake.install(here .. 'tradewindow.otui')
local styles, new, build, windowOf = fake.styles, fake.new, fake.build, fake.windowOf

dofile(here .. 'trademodel.lua')
dofile(here .. 'tradeview.lua')
local M, V = TradeModel, TradeView
V.fmt = { short = function(x) return x >= 1000 and string.format('%.1fk', x / 1000) or tostring(x) end,
  exact = function(x) return (tostring(x):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')) end }

-- ---------------------------------------------------------------- the ids the code looks up are in the file
local win = windowOf('TradeWindow')
for _, id in ipairs(V.IDS) do eq(win:recursiveGetChildById(id) ~= nil, true, 'tradewindow.otui has ' .. id) end
local probe = g_ui.createWidget('TradeCard', new('x'))
for _, id in ipairs(V.CARD_IDS) do eq(probe:getChildById(id) ~= nil, true, 'TradeCard has ' .. id) end
probe = g_ui.createWidget('TradeSellRow', new('x'))
for _, id in ipairs(V.ROW_IDS) do eq(probe:getChildById(id) ~= nil, true, 'TradeSellRow has ' .. id) end
local saWin = windowOf('TradeSellAllWindow')
for _, id in ipairs(V.SELLALL_IDS) do eq(saWin:recursiveGetChildById(id) ~= nil, true, 'TradeSellAllWindow has ' .. id) end
-- every id in the main window is used by the view, so none is dead (the card, row and static ones aside)
local used = {}
for _, id in ipairs(V.IDS) do used[id] = true end
local dead = {}
local function walk(w)
  for _, k in ipairs(w.kids) do
    if k.id and not used[k.id] then dead[#dead + 1] = k.id end
    walk(k)
  end
end
walk(win)
local allowed = { priceCaption = true, weightCaption = true, ownedCaption = true, separator = true, amountCaption = true,
  amountRow = true, totalCaption = true, capacityCaption = true, optionsBox = true }
for _, id in ipairs(dead) do eq(allowed[id], true, 'widget id nothing looks up: ' .. id) end
local sty = 0
for _ in pairs(styles) do sty = sty + 1 end
eq(sty >= 7, true, 'the file defines the styles')

-- ---------------------------------------------------------------- the view
local view = V.new(win)
local fired = {}
view.on = setmetatable({}, { __index = function(_, name) return function(...) fired[#fired + 1] = { name, ... } end end })
view.on = (function()
  local t = {}
  for _, name in ipairs({ 'tab', 'close', 'sort', 'clearSearch', 'search', 'amount', 'step', 'max', 'trade', 'sellAll',
    'option', 'select', 'category', 'itemMenu' }) do
    t[name] = function(...) fired[#fired + 1] = { name, ... } end
  end
  return t
end)()
local function last() return fired[#fired] end
local ui = view.ui

view:setHeader({ name = 'Gold Coin', item = 3031, caption = 'Gold', balance = 18200000, gold = true })
eq(ui.currencyLabel.text, 'Currency: Gold Coin', 'the Currency line')
eq(ui.currencyItem.itemId, 3031, 'the currency icon'); eq(ui.currencyItem.visible, true, 'icon shown')
eq(ui.balanceLabel.text, 'Gold: 18200.0k', 'the balance'); eq(ui.balanceLabel.tooltip, '18,200,000', 'the exact balance in the tooltip')
eq(ui.currencyLabel.tooltip, nil, 'no tooltip when the name is whole')
view:setHeader({ name = 'Azure Coin', fullName = 'Azure Coin Of The Deep', item = nil, caption = 'Balance', balance = 42, gold = false })
eq(ui.currencyItem.visible, false, 'a currency without an icon hides it'); eq(ui.currencyLabel.tooltip, 'Azure Coin Of The Deep', 'long name in a tooltip')
eq(ui.balanceLabel.text, 'Balance: 42', 'the other currency balance')
view:setHeader({ name = 'Gold Coin', item = 3031, caption = 'Gold', balance = 100, gold = true })

view:setTabCounts(3, 0)
eq(ui.buyTab.text, 'Buy (3)', 'buy count'); eq(ui.sellTab.enabled, false, 'a seller that buys nothing: the Sell tab is off')
view:setTabCounts(3, 2)
view:setTab(M.BUY)
eq(ui.buyTab.checked, true, 'buy tab checked'); eq(ui.sellTab.checked, false, 'sell tab not')
eq(ui.tradeButton.text, 'Buy', 'the button says Buy'); eq(ui.bagsCheck.visible, true, 'bags option on a gold buy')
eq(ui.ignoreCapCheck.visible, true, 'ignore capacity on a buy'); eq(ui.equippedCheck.visible, false, 'no equipped option on a buy')
eq(ui.sellAllButton.visible, false, 'no Sell all on a buy')
view:setHeader({ name = 'Azure Coin', item = nil, caption = 'Balance', balance = 5, gold = false })
eq(ui.bagsCheck.visible, false, 'no shopping bags for another currency')
view:setHeader({ name = 'Gold Coin', item = 3031, caption = 'Gold', balance = 100, gold = true })
view:setSort('price'); eq(ui.sortButton.text, 'Sort: Price', 'sort button')
view:setOptions({ bags = true, ignoreCapacity = false, sellEquipped = true })
eq(ui.bagsCheck.checked, true, 'options shown'); eq(ui.equippedCheck.checked, true, 'equipped option shown')
eq(#fired, 0, 'showing options is not the player changing them')
ui.bagsCheck:setChecked(false); eq(last()[1], 'option', 'a changed option is reported')
eq(last()[2], 'bags', 'which one'); eq(last()[3], false, 'its value')
ui.equippedCheck:setChecked(false); eq(last()[2], 'sellEquipped', 'sell equipped')
view:setSearch('x'); eq(#fired, 2, 'setting the search from code is quiet'); eq(ui.searchText.text, 'x', 'search text set')
view:setSearch('')
ui.searchText:setText('pot'); eq(last()[1], 'search', 'typing reports'); eq(last()[2], 'pot', 'the text')

-- the cards
local function item(name, price, weight)
  return { ptr = { name = name }, name = name, price = price, weight = weight, stackable = false }
end
local items = { item('strong health potion', 100, 3.5), item('mana potion', 5000, 3.5), item('plate armor', 400, 120) }
local have = { [items[1]] = 5 }
local ctx = { type = M.BUY, items = items, sort = 'name', owned = function(it) return have[it] end,
  factsOf = function(it) return { name = it.name, market = it.name:find('potion') and 10 or 1 } end,
  tradable = function(it) return it ~= items[2] end }
local visible, all = M.cards(ctx)
view:setCards(all)
eq(#ui.list.kids, 3, 'a widget per item')
view:update({ visible = visible, selected = nil, tab = M.BUY })
local first = ui.list.kids[1]
eq(first:getChildById('nameLabel').text, 'Mana Potion', 'proper-case name, sorted by name')
eq(first:getChildById('priceLabel').text, '5.0k', 'short price'); eq(first:getChildById('coin').itemId, 3031, 'coin icon on the price')
eq(first.opacity, 0.55, 'a card the player cannot afford is greyed'); eq(first:getChildById('nameLabel').color, '#6b6258', 'grey name')
eq(ui.list.kids[3].opacity, 1, 'the others are not')
eq(ui.list.kids[2]:getChildById('metaLabel').text, '120.00 oz', 'weight, no owned count when none')
eq(ui.list.kids[3]:getChildById('metaLabel').text, '3.50 oz  |  Owned: 5', 'weight and owned count')
eq(first.tooltip, 'Mana Potion\nPrice 5,000, 3.50 oz', 'tooltip with the exact price')
eq(ui.emptyLabel.visible, false, 'the empty note is hidden')
-- a long name is cut on the card and whole in the tooltip
eq(V.clip('Light Magic Missile Rune Of The Deep', 22), 'Light Magic Missile...', 'clipped'); eq(V.clip('Rope', 22), 'Rope', 'short stays')
eq(#V.clip(string.rep('x', 60), 22), 22, 'at most n'); eq(V.clip(nil, 5), '', 'nil')
-- a filtered list hides the rest and keeps the order
local only = M.filterCategory(visible, 'armor')
view:update({ visible = only, selected = nil, tab = M.BUY })
eq(ui.list.kids[1]:getChildById('nameLabel').text, 'Plate Armor', 'filtered')
local shown = 0
for _, k in ipairs(ui.list.kids) do if k.visible then shown = shown + 1 end end
eq(shown, 1, 'the others are hidden')
view:update({ visible = {}, selected = nil, tab = M.BUY, empty = 'Nothing here.' })
eq(ui.emptyLabel.visible, true, 'empty note shown'); eq(ui.emptyLabel.text, 'Nothing here.', 'with its text')
view:update({ visible = visible, selected = visible[2].key, tab = M.BUY })
eq(view.cards[visible[2].key].checked, true, 'the selected card is checked'); eq(view.cards[visible[1].key].checked, false, 'others not')
-- a click selects; a right click asks for the menu
view.cards[visible[1].key].onClick()
eq(last()[1], 'select', 'a click selects'); eq(last()[2], visible[1].key, 'which card')
view.cards[visible[1].key].onMouseRelease(nil, { x = 1, y = 2 }, MouseRightButton)
eq(last()[1], 'itemMenu', 'a right click asks for the menu'); eq(last()[2].key, visible[1].key, 'for that card')

-- the chips
local chips = M.chips(M.cards(ctx))
view:setChips(chips, 'all')
eq(#ui.chips.kids, 3, 'All, potions, armor'); eq(ui.chips.kids[1].text, 'All 3', 'the All chip counts')
eq(ui.chips.kids[2].text, 'Potions 2', 'a category chip'); eq(ui.chips.kids[1].checked, true, 'All is checked')
eq(ui.chips.visible, true, 'chips shown'); eq(ui.chips.height, 22, 'one row')
ui.chips.kids[2].onClick(); eq(last()[1], 'category', 'a chip click'); eq(last()[2], 'potions', 'its category')
view:setChips({ { id = 'all', label = 'All', count = 3 } }, 'all')
eq(ui.chips.visible, false, 'one category only: no chips'); eq(ui.chips.height, 0, 'no height')

-- the side panel
view:setSelection(nil, nil, ctx)
eq(ui.content.visible, false, 'nothing selected: no details'); eq(ui.hintLabel.visible, true, 'a hint instead')
eq(ui.tradeButton.enabled, false, 'the button is off'); eq(ui.selItem.visible, false, 'no big icon')
local card
for _, c in ipairs(visible) do if c.name == 'Strong Health Potion' then card = c end end
local buy = { type = M.BUY, money = 1000, freeCapacity = 100, owned = ctx.owned }
local d = M.detail(buy, card, 4)
view:setSelection(card, d, buy)
eq(ui.content.visible, true, 'details shown'); eq(ui.hintLabel.visible, false, 'no hint')
eq(ui.selName.text, 'Strong Health Potion', 'the name'); eq(ui.selMeta.text, 'Potions', 'the category')
eq(ui.priceValue.text, '100', 'the price each'); eq(ui.weightValue.text, '3.50 oz', 'the weight')
eq(ui.ownedValue.text, '5', 'owned'); eq(ui.amountText.text, '4', 'the amount')
eq(ui.quantityScroll.scroll.max, 10, 'the slider max is what the player can buy'); eq(ui.quantityScroll.scroll.value, 4, 'at the amount')
eq(ui.totalValue.text, '400', 'the total'); eq(ui.afterCaption.text, 'Gold after', 'gold after'); eq(ui.afterValue.text, '600', 'the gold left')
eq(ui.capacityValue.text, '86.00 oz', 'the capacity left'); eq(ui.capacityValue.color, '#d6c9ae', 'not red')
eq(ui.warnLabel.text, '', 'no warning'); eq(ui.tradeButton.enabled, true, 'the button is on')
eq(#fired > 0 and last()[1] ~= 'amount', true, 'showing the amount is not a change by the player')
d = M.detail({ type = M.BUY, money = 1000, freeCapacity = 100, owned = ctx.owned }, card, 99)
view:setSelection(card, d, buy)
eq(ui.warnLabel.text, 'That is all you can afford.', 'at the maximum the limit is said')
d = M.detail({ type = M.BUY, money = 10, freeCapacity = 100 }, card, 1)
view:setSelection(card, d, buy)
eq(ui.warnLabel.text, 'You cannot afford this.', 'cannot afford'); eq(ui.tradeButton.enabled, false, 'button off'); eq(ui.afterValue.color, '#d6c9ae', 'gold after is the balance')
d = M.detail({ type = M.BUY, money = 1000, freeCapacity = 1 }, card, 1)
view:setSelection(card, d, buy)
eq(ui.warnLabel.text, 'You cannot carry it: too heavy.', 'too heavy')
d = M.detail({ type = M.SELL, money = 10, freeCapacity = 5, owned = function() return 0 end }, card, 1)
view:setSelection(card, d, { type = M.SELL })
eq(ui.warnLabel.text, 'You have none to sell.', 'nothing to sell')
-- the player types an amount, presses plus, minus, max
fired = {}
ui.amountText:setText('7'); eq(last()[1], 'amount', 'an amount typed'); eq(last()[2], 7, 'as a number')
ui.plusButton.onClick(); eq(last()[1], 'step', 'plus'); eq(last()[2], 1, 'by one')
ui.minusButton.onClick(); eq(last()[2], -1, 'minus')
ui.maxButton.onClick(); eq(last()[1], 'max', 'max')
ui.tradeButton.onClick(); eq(last()[1], 'trade', 'trade')
ui.sellAllButton.onClick(); eq(last()[1], 'sellAll', 'sell all')
ui.closeButton.onClick(); eq(last()[1], 'close', 'close')
ui.sortButton.onClick(); eq(last()[1], 'sort', 'sort')
ui.sellTab.onClick(); eq(last()[1], 'tab', 'tab'); eq(last()[2], M.SELL, 'sell tab')
view:setTab(M.SELL)
eq(ui.tradeButton.text, 'Sell', 'the button says Sell'); eq(ui.sellAllButton.visible, true, 'Sell all on a sell tab')
eq(ui.equippedCheck.visible, true, 'equipped option on a sell tab'); eq(ui.bagsCheck.visible, false, 'no bags on a sell tab')
-- another currency: coin icon and captions follow it
view:setHeader({ name = 'Azure Coin', item = 26780, caption = 'Balance', balance = 5, gold = false })
view:setSelection(card, M.detail(buy, card, 2), buy)
eq(ui.afterCaption.text, 'Balance after', 'balance after'); eq(ui.totalCoin.itemId, 26780, 'the total shows that coin')
-- clearing the cards
view:clearCards()
eq(#ui.list.kids, 0, 'cards cleared')

-- the Sell all window
local sa = V.newSellAll(saWin)
local sfired = {}
for _, name in ipairs({ 'tab', 'sell', 'cancel', 'keep', 'tick' }) do sa.on[name] = function(...) sfired[#sfired + 1] = { name, ... } end end
local rows = M.sellAllRows({
  items = { item('ember shard', 40, 1), item('wolf fur', 5, 1), item('cursed blade', 900, 20), item('old flask', 3, 1) },
  owned = function(it) return it.name == 'ember shard' and 12 or 3 end, ignored = { [2] = true },
  idOf = function(it) return it.name == 'ember shard' and 1 or it.name == 'wolf fur' and 2 or it.name == 'cursed blade' and 3 or 4 end,
  bulkOk = function(it) return it.name ~= 'old flask' end, marketValue = function(it) return it.name == 'ember shard' and 50 or nil end,
})
local state = { ignoredTab = false, unticked = {}, totals = M.sellAllTotals(rows) }
sa:render(rows, state, 'Gold Coin')
eq(#saWin:recursiveGetChildById('rows').kids, 3, 'three rows to sell: two ticked and one by hand')
eq(sa.ui.sellTab.text, 'To sell (3)', 'the sell tab counts'); eq(sa.ui.ignoreTab.text, 'Ignored (1)', 'the ignore tab counts')
local r1 = sa.ui.rows.kids[1]
eq(r1:getChildById('nameLabel').text, '3x Cursed Blade', 'a row'); eq(r1:getChildById('infoLabel').text, '2,700', 'its subtotal')
eq(r1:getChildById('keepButton').text, 'Never sell', 'the keep button'); eq(r1:getChildById('tick').checked, true, 'ticked at first')
local r2 = sa.ui.rows.kids[2]
eq(r2:getChildById('infoLabel').text, '480  -  below the market value', 'a row under the market value says so')
eq(r2:getChildById('infoLabel').color, '#e03a1e', 'in red')
local r3 = sa.ui.rows.kids[3]
eq(r3:getChildById('infoLabel').text, 'Sell this one by hand.', 'a manual row'); eq(r3:getChildById('tick').visible, false, 'no tick on it')
eq(sa.ui.totalLabel.text, '15 items, 3,180 for Gold Coin', 'the total'); eq(sa.ui.noteLabel.text, '1 of them sell for less than their market value.', 'the note')
eq(sa.ui.sellButton.enabled, true, 'the sell button is on')
r1:getChildById('tick'):setChecked(false); eq(sfired[#sfired][1], 'tick', 'a tick change'); eq(sfired[#sfired][3], false, 'off')
r1:getChildById('keepButton').onClick(); eq(sfired[#sfired][1], 'keep', 'keep'); eq(sfired[#sfired][2].id, 3, 'for that item')
sa.ui.ignoreTab.onClick(); eq(sfired[#sfired][1], 'tab', 'the ignore tab'); eq(sfired[#sfired][2], true, 'asks for the ignored list')
state.ignoredTab = true
sa:render(rows, state, 'Gold Coin')
eq(#sa.ui.rows.kids, 1, 'one ignored row'); eq(sa.ui.rows.kids[1]:getChildById('keepButton').text, 'Restore', 'restore')
sa.ui.sellButton.onClick(); eq(sfired[#sfired][1], 'sell', 'sell'); sa.ui.cancelButton.onClick(); eq(sfired[#sfired][1], 'cancel', 'cancel')
state.totals = M.sellAllTotals({})
sa:render({}, state, 'Gold Coin')
eq(sa.ui.sellButton.enabled, false, 'nothing to sell: the button is off')

print(string.format('tradeview_test: %d checks OK', n))
