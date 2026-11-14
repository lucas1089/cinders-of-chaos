-- NPC trade window (O571): the widgets. tradeview.lua turns the plain data of trademodel.lua into the widgets of
-- tradewindow.otui and calls back what the player does; it never talks to the game (tradewindow.lua does). Tested on a
-- fake widget engine built from the real .otui by tradeview_test.lua.
TradeView = {}
local V = TradeView
local M = TradeModel

-- every id the code below looks up in the window (tradeview_test.lua holds the list to tradewindow.otui)
V.IDS = { 'closeButton', 'header', 'buyTab', 'sellTab', 'currencyItem', 'currencyLabel', 'balanceLabel', 'listColumn',
  'searchText', 'clearSearchButton', 'sortButton', 'chips', 'list', 'listScrollBar', 'emptyLabel', 'detail', 'selItem',
  'selName', 'selMeta', 'hintLabel', 'content', 'priceValue', 'weightValue', 'ownedValue', 'amountText', 'minusButton',
  'plusButton', 'maxButton', 'quantityScroll', 'totalCoin', 'totalValue', 'afterCaption', 'afterValue', 'capacityValue',
  'warnLabel', 'bagsCheck', 'ignoreCapCheck', 'equippedCheck', 'sellAllButton', 'tradeButton' }
V.CARD_IDS = { 'slot', 'nameLabel', 'coin', 'priceLabel', 'metaLabel' }
V.ROW_IDS = { 'tick', 'slot', 'nameLabel', 'infoLabel', 'keepButton' }
V.SELLALL_IDS = { 'introLabel', 'sellTab', 'ignoreTab', 'rows', 'rowsScrollBar', 'totalLabel', 'noteLabel', 'sellButton',
  'cancelButton' }

local GOLD_ITEM = 3031
local CHIP_HEIGHT, CHIP_PAD = 22, 18

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

-- the money texts: short in the lists (15.3k), exact where it counts; a host can replace them
V.fmt = {
  short = function(n) return formatShortNumber and formatShortNumber(n) or tostring(n) end,
  exact = function(n) return comma_value and comma_value(tostring(n)) or tostring(n) end,
}

-- the name of a category chip (the model holds the English ids and labels; the texts the player reads go through tr)
local function categoryName(id)
  if id == 'all' then return tr('All')
  elseif id == 'potions' then return tr('Potions')
  elseif id == 'runes' then return tr('Runes')
  elseif id == 'ammo' then return tr('Ammunition')
  elseif id == 'weapons' then return tr('Weapons')
  elseif id == 'armor' then return tr('Armor')
  elseif id == 'jewelry' then return tr('Jewelry')
  elseif id == 'tools' then return tr('Tools')
  elseif id == 'food' then return tr('Food')
  elseif id == 'containers' then return tr('Containers')
  elseif id == 'loot' then return tr('Loot')
  end
  return tr('Other')
end
V.categoryName = categoryName

-- the text cut to n characters, "..." in the last three when it was longer (the whole name is in the tooltip)
local function clip(text, n)
  text = tostring(text or '')
  if #text <= n then return text end
  return text:sub(1, math.max(1, n - 3)) .. '...'
end
V.clip = clip
V.CARD_NAME_MAX = 22   -- a card's name line holds about this many characters of the 11 px face
V.ROW_NAME_MAX = 40

local function weightText(w, unit)
  return string.format('%.2f', tonumber(w) or 0) .. ' ' .. (unit or 'oz')
end
V.weightText = weightText

local function setItemId(widget, id)
  if not alive(widget) then return end
  if id and id > 0 then
    widget:setItemId(id)
    widget:setVisible(true)
  else
    widget:setVisible(false)
  end
end

-- ---------------------------------------------------------------- the window
function V.new(window)
  local view = { window = window, ui = {}, cards = {}, chips = {}, on = {}, state = {}, unit = 'oz' }
  for _, id in ipairs(V.IDS) do
    view.ui[id] = window:recursiveGetChildById(id)
    if not view.ui[id] then error('tradewindow.otui has no widget ' .. id) end
  end
  local ui = view.ui
  setmetatable(view, { __index = V })

  ui.buyTab.onClick = function() view:fire('tab', M.BUY) end
  ui.sellTab.onClick = function() view:fire('tab', M.SELL) end
  ui.closeButton.onClick = function() view:fire('close') end
  ui.sortButton.onClick = function() view:fire('sort') end
  ui.clearSearchButton.onClick = function() view:fire('clearSearch') end
  ui.searchText.onTextChange = function(_, text) if not view.quiet then view:fire('search', text) end end
  ui.amountText.onTextChange = function(_, text) if not view.quiet then view:fire('amount', tonumber(text)) end end
  ui.minusButton.onClick = function() view:fire('step', -1) end
  ui.plusButton.onClick = function() view:fire('step', 1) end
  ui.maxButton.onClick = function() view:fire('max') end
  ui.quantityScroll.onValueChange = function(_, value) if not view.quiet then view:fire('amount', value) end end
  ui.tradeButton.onClick = function() view:fire('trade') end
  ui.sellAllButton.onClick = function() view:fire('sellAll') end
  ui.bagsCheck.onCheckChange = function(_, on) if not view.quiet then view:fire('option', 'bags', on) end end
  ui.ignoreCapCheck.onCheckChange = function(_, on) if not view.quiet then view:fire('option', 'ignoreCapacity', on) end end
  ui.equippedCheck.onCheckChange = function(_, on) if not view.quiet then view:fire('option', 'sellEquipped', on) end end
  ui.selItem.onMouseRelease = function(_, pos, button) return view:fire('itemMenu', view.selected, pos, button) end
  return view
end

function V:fire(name, ...)
  local fn = self.on[name]
  if fn then return fn(...) end
end

-- a change made from code does not come back as the player's change
function V:quietly(fn)
  local was = self.quiet
  self.quiet = true
  local ok, err = pcall(fn)
  self.quiet = was
  if not ok then error(err, 0) end
end

-- ---------------------------------------------------------------- the header and the tabs
function V:setTab(tab)
  local ui = self.ui
  ui.buyTab:setChecked(tab == M.BUY)
  ui.sellTab:setChecked(tab == M.SELL)
  ui.tradeButton:setText(tab == M.BUY and tr('Buy') or tr('Sell'))
  ui.bagsCheck:setVisible(tab == M.BUY and self.state.gold == true)
  ui.ignoreCapCheck:setVisible(tab == M.BUY)
  ui.equippedCheck:setVisible(tab == M.SELL)
  ui.sellAllButton:setVisible(tab == M.SELL)
  self.state.tab = tab
end

-- `h` = {name, fullName, item, caption, balance, gold}: the currency, its icon, the player's balance in it
function V:setHeader(h)
  local ui = self.ui
  ui.currencyLabel:setText(tr('Currency') .. ': ' .. h.name)
  ui.currencyLabel:removeTooltip()
  if h.fullName and h.fullName ~= h.name then ui.currencyLabel:setTooltip(h.fullName) end
  setItemId(ui.currencyItem, h.item)
  if alive(ui.currencyItem) and h.item then
    ui.currencyItem:setItemCount(100)
    ui.currencyItem:setShowCount(false)
  end
  self.state.gold = h.gold == true
  self.state.currencyItem = h.item
  self.state.caption = h.caption
  self:setBalance(h.balance)
  self.ui.bagsCheck:setVisible(self.state.tab == M.BUY and self.state.gold)
end

function V:setBalance(n)
  n = tonumber(n) or 0
  self.state.balance = n
  self.ui.balanceLabel:setText((self.state.caption or tr('Gold')) .. ': ' .. V.fmt.short(n))
  self.ui.balanceLabel:setTooltip(V.fmt.exact(n))
end

function V:setTabCounts(buyN, sellN)
  self.ui.buyTab:setText(tr('Buy') .. ' (' .. buyN .. ')')
  self.ui.sellTab:setText(tr('Sell') .. ' (' .. sellN .. ')')
  self.ui.buyTab:setEnabled(buyN > 0)
  self.ui.sellTab:setEnabled(sellN > 0)
end

function V:setSort(sort)
  local names = { name = tr('Name'), price = tr('Price'), weight = tr('Weight') }
  self.ui.sortButton:setText(tr('Sort: %s', names[sort] or names.name))
end

function V:setOptions(o)
  self:quietly(function()
    self.ui.bagsCheck:setChecked(o.bags == true)
    self.ui.ignoreCapCheck:setChecked(o.ignoreCapacity == true)
    self.ui.equippedCheck:setChecked(o.sellEquipped == true)
  end)
end

function V:setSearch(text)
  self:quietly(function() self.ui.searchText:setText(text or '') end)
end

-- ---------------------------------------------------------------- the cards
function V:clearCards()
  for _, w in pairs(self.cards) do if alive(w) then w:destroy() end end
  self.cards = {}
  self.selected = nil
  if alive(self.ui.list) then self.ui.list:destroyChildren() end
end

local function cardTooltip(card, unit, exact)
  return card.name .. '\n' .. tr('Price %s', exact(card.price)) .. (card.weight > 0 and (', ' .. weightText(card.weight, unit)) or '')
end

-- one widget per item of the shop's list (all of them, shown or not: `update` shows, hides and orders them)
function V:setCards(all)
  self:clearCards()
  local ui = self.ui
  for _, card in ipairs(all) do
    local w = g_ui.createWidget('TradeCard', ui.list)
    w:setId('card_' .. card.key)
    w.card = card
    local slot = w:getChildById('slot')
    slot:setItem(card.item.ptr)
    if ItemsDatabase and ItemsDatabase.setRarityItem then pcall(ItemsDatabase.setRarityItem, slot, card.item.ptr) end
    if ItemsDatabase and ItemsDatabase.setTier then pcall(ItemsDatabase.setTier, slot, card.item.ptr) end
    w:getChildById('nameLabel'):setText(clip(card.name, V.CARD_NAME_MAX))
    w:getChildById('priceLabel'):setText(V.fmt.short(card.price))
    setItemId(w:getChildById('coin'), self.state.currencyItem or (self.state.gold and GOLD_ITEM) or nil)
    w:setTooltip(cardTooltip(card, self.unit, V.fmt.exact))
    w.onClick = function() self:fire('select', card.key) end
    w.onMouseRelease = function(_, pos, button)
      if button == MouseRightButton then return self:fire('itemMenu', card, pos, button) end
      return false
    end
    self.cards[card.key] = w
  end
end

local function metaText(card, sellMode, unit)
  local parts = {}
  if card.weight > 0 then parts[#parts + 1] = weightText(card.weight, unit) end
  if card.owned ~= nil and (sellMode or card.owned > 0) then parts[#parts + 1] = tr('Owned: %s', tostring(card.owned)) end
  return table.concat(parts, '  |  ')
end

-- `s` = {visible (cards in order), all, selected (key), tab, empty (text)}: orders, shows and hides the card widgets, greys
-- the ones the player cannot trade now, marks the selected one
function V:update(s)
  local ui = self.ui
  local shown = {}
  for i, card in ipairs(s.visible) do
    shown[card.key] = true
    local w = self.cards[card.key]
    if w then
      w.card = card
      w:setVisible(true)
      ui.list:moveChildToIndex(w, i)
      w:setChecked(s.selected == card.key)
      w:setOpacity(card.can and 1 or 0.55)
      w:getChildById('nameLabel'):setColor(card.can and '#d6c9ae' or '#6b6258')
      w:getChildById('priceLabel'):setColor(card.can and '#f6cf72' or '#8c8070')
      w:getChildById('metaLabel'):setText(metaText(card, s.tab == M.SELL, self.unit))
    end
  end
  for key, w in pairs(self.cards) do
    if not shown[key] then
      w:setVisible(false)
      w:setChecked(false)
    end
  end
  self.selected = s.selected and s.selected or nil
  ui.emptyLabel:setVisible(#s.visible == 0)
  if #s.visible == 0 then ui.emptyLabel:setText(s.empty or tr('Nothing matches.')) end
end

-- ---------------------------------------------------------------- the category chips
function V:setChips(chips, selected)
  local ui = self.ui
  ui.chips:destroyChildren()
  self.chips = {}
  local widths = {}
  for i, c in ipairs(chips) do
    local w = g_ui.createWidget('TradeChip', ui.chips)
    w:setId('chip_' .. c.id)
    w:setText(categoryName(c.id) .. ' ' .. c.count)
    w.fullWidth = w:getTextSize().width + CHIP_PAD
    w:setWidth(w.fullWidth)
    w:addAnchor(AnchorTop, 'parent', AnchorTop)
    w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    w:setChecked(c.id == selected)
    w.onClick = function() self:fire('category', c.id) end
    self.chips[i] = w
    widths[i] = w.fullWidth
  end
  local places, height = M.flow(widths, self.chipsWidth or 430, CHIP_HEIGHT, 4, 4)
  for i, w in ipairs(self.chips) do
    w:setMarginLeft(places[i].x)
    w:setMarginTop(places[i].y)
    w:setWidth(places[i].width)
  end
  ui.chips:setHeight(math.max(0, height))
  ui.chips:setVisible(#chips > 1)
  if #chips <= 1 then ui.chips:setHeight(0) end
end

-- ---------------------------------------------------------------- the side panel
function V:setSelection(card, d, ctx)
  local ui = self.ui
  local empty = card == nil or d == nil or d.empty
  ui.content:setVisible(not empty)
  ui.hintLabel:setVisible(empty)
  if empty then
    ui.selItem:setVisible(false)
    ui.selName:setText('')
    ui.selMeta:setText('')
    ui.tradeButton:setEnabled(false)
    self:quietly(function()
      ui.amountText:setText('')
      ui.quantityScroll:setMinimum(0)
      ui.quantityScroll:setMaximum(0)
      ui.quantityScroll:setValue(0)
    end)
    return
  end
  ui.selItem:setVisible(true)
  ui.selItem:setItem(card.item.ptr)
  if ItemsDatabase and ItemsDatabase.setRarityItem then pcall(ItemsDatabase.setRarityItem, ui.selItem, card.item.ptr) end
  if ItemsDatabase and ItemsDatabase.setTier then pcall(ItemsDatabase.setTier, ui.selItem, card.item.ptr) end
  ui.selName:setText(card.name)
  ui.selMeta:setText(categoryName(card.category))
  ui.priceValue:setText(V.fmt.exact(d.unit))
  ui.weightValue:setText(card.weight > 0 and weightText(card.weight, self.unit) or '-')
  ui.ownedValue:setText(card.owned ~= nil and tostring(card.owned) or '-')
  self:quietly(function()
    ui.quantityScroll:setMinimum(0)
    ui.quantityScroll:setMaximum(d.max)
    ui.quantityScroll:setMinimum(d.max > 0 and 1 or 0)
    ui.quantityScroll:setValue(d.amount)
    if tostring(ui.amountText:getText()) ~= tostring(d.amount) then ui.amountText:setText(tostring(d.amount)) end
  end)
  ui.totalValue:setText(V.fmt.exact(d.total))
  setItemId(ui.totalCoin, self.state.currencyItem or (self.state.gold and GOLD_ITEM) or nil)
  local caption = self.state.caption or tr('Gold')
  ui.afterCaption:setText(caption == tr('Gold') and tr('Gold after') or tr('Balance after'))
  ui.afterValue:setText(V.fmt.exact(d.after))
  ui.afterValue:setColor(d.after < 0 and '#e03a1e' or '#d6c9ae')
  ui.capacityValue:setText(weightText(d.capacityAfter, self.unit))
  ui.capacityValue:setColor(d.tooHeavy and '#e03a1e' or '#d6c9ae')
  local warn = ''
  local sell = ctx and ctx.type == M.SELL
  if d.warn == 'gold' then
    warn = tr('You cannot afford this.')
  elseif d.warn == 'capacity' then
    warn = tr('You cannot carry it: too heavy.')
  elseif sell and d.max == 0 then
    warn = tr('You have none to sell.')
  elseif d.hint == 'capacity' then
    warn = tr('That is all you can carry.')
  elseif d.hint == 'gold' then
    warn = tr('That is all you can afford.')
  end
  ui.warnLabel:setText(warn)
  ui.tradeButton:setEnabled(d.canTrade and d.amount >= 1)
end

function V:amountText()
  return tonumber(self.ui.amountText:getText())
end

function V:focusSearch()
  local w = self.ui.searchText
  if w.recursiveFocus then w:recursiveFocus(KeyboardFocusReason) else w:focus() end
end

-- ---------------------------------------------------------------- the Sell all window
-- `rows` from M.sellAllRows, `st` = {ignoredTab (bool), unticked = {[key] = true}, totals}
function V.newSellAll(window)
  local sa = { window = window, ui = {}, rowWidgets = {}, on = {} }
  for _, id in ipairs(V.SELLALL_IDS) do
    sa.ui[id] = window:recursiveGetChildById(id)
    if not sa.ui[id] then error('tradewindow.otui (Sell all) has no widget ' .. id) end
  end
  setmetatable(sa, { __index = V.SellAll })
  sa.ui.sellTab.onClick = function() sa:fire('tab', false) end
  sa.ui.ignoreTab.onClick = function() sa:fire('tab', true) end
  sa.ui.sellButton.onClick = function() sa:fire('sell') end
  sa.ui.cancelButton.onClick = function() sa:fire('cancel') end
  return sa
end

V.SellAll = {}
local SA = V.SellAll
function SA:fire(name, ...)
  local fn = self.on[name]
  if fn then return fn(...) end
end

function SA:render(rows, st, currencyName)
  local ui = self.ui
  ui.rows:destroyChildren()
  self.rowWidgets = {}
  local sellCount, ignoreCount = 0, 0
  for _, r in ipairs(rows) do
    if r.ignored then ignoreCount = ignoreCount + 1 else sellCount = sellCount + 1 end
  end
  ui.introLabel:setText(tr('These items are sold for %s. Untick what you want to keep, or move it to the ignored list for good.',
    currencyName or tr('Gold Coin')))
  ui.sellTab:setText(tr('To sell (%s)', tostring(sellCount)))
  ui.ignoreTab:setText(tr('Ignored (%s)', tostring(ignoreCount)))
  ui.sellTab:setChecked(not st.ignoredTab)
  ui.ignoreTab:setChecked(st.ignoredTab == true)
  for _, r in ipairs(rows) do
    if r.ignored == (st.ignoredTab == true) then
      local w = g_ui.createWidget('TradeSellRow', ui.rows)
      w:setId('row_' .. r.key)
      local tick = w:getChildById('tick')
      local slot = w:getChildById('slot')
      slot:setItem(r.item.ptr)
      w:getChildById('nameLabel'):setText(clip(r.qty .. 'x ' .. r.name, V.ROW_NAME_MAX))
      local info = V.fmt.exact(r.subtotal)
      if r.belowMarket then info = info .. '  -  ' .. tr('below the market value') end
      if r.manual then info = tr('Sell this one by hand.') end
      w:getChildById('infoLabel'):setText(info)
      w:getChildById('infoLabel'):setColor(r.belowMarket and '#e03a1e' or '#f6cf72')
      local keep = w:getChildById('keepButton')
      keep:setText(r.ignored and tr('Restore') or tr('Never sell'))
      keep.onClick = function() self:fire('keep', r) end
      if r.ignored or r.manual then
        tick:setVisible(false)
      else
        tick:setChecked(not (st.unticked and st.unticked[r.key]))
        tick.onCheckChange = function(_, on) self:fire('tick', r, on) end
      end
      self.rowWidgets[#self.rowWidgets + 1] = w
    end
  end
  local t = st.totals
  ui.totalLabel:setText(tr('%s items, %s for %s', tostring(t.pieces), V.fmt.exact(t.gold), currencyName or tr('Gold Coin')))
  local note = ''
  if t.below > 0 then note = tr('%s of them sell for less than their market value.', tostring(t.below)) end
  ui.noteLabel:setText(note)
  ui.sellButton:setEnabled(t.rows > 0)
end
