-- Market: our own player market for gold and Chaos Coins (Economy > Market in the top menu, Alt+E; the market item
-- of a depot locker opens it too). Server: server/data/scripts/chaos/market.lua, extended opcode 221 (JSON {action,
-- data}, long answers in parts joined by ProtocolGame.registerExtendedJSONOpcode). The logic without client API is
-- marketview.lua (marketview_test.lua).
--   client -> server  open | browse {filter} | tip {id} | buy {id, cur} | sellable | list {ref|pos, sid|cid, iid, count,
--                     gold, coins, days} | cancel {id} | mine | history | wallet
--   server -> client  meta | page | tip | sellable | mine | history | wallet | done {what, text} | error {text} | openWindow
-- Tabs: Browse (search, filters, sorting, pages; hover = the full item tooltip of game_itemtooltip, Buy with a
-- confirmation), Sell (pick an item from the backpack or drag one in, prices, duration, the fee), My Offers (active,
-- sold, expired, cancelled; Cancel), History (purchases and sales).

local OPCODE = 221
local V = MarketView

local window
local meta
local tabs = {}
local tabIndex = 1
local tipCache = {} -- offer id -> tip
local tipAsked = {}
local hoveredRow
local lastFilter = { page = 1 }
local pageInfo = { page = 1, pages = 1, total = 0 }
local sellItems = {}
local selected -- the chosen Sell item: {ref | pos, sid | cid, iid, count, name, stack, rarity, ilvl}
local modOptions
local updating = false

local okText, Text = pcall(dofile, '/modules/game_spellsupports/supportstext.lua')
if not okText or type(Text) ~= 'table' then Text = nil end

local COLORS = { text = '#d6c9ae', dim = '#8c8070', gold = '#e8b84a', coins = '#7fd0ff', error = '#e03a1e', ok = '#8fd16a' }

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function tooltips()
  return modules.game_itemtooltip
end

local function tipLogic()
  local tt = tooltips()
  return tt and tt.ItemTooltipLogic
end

local function rarityColor(row)
  local L = tipLogic()
  if L and L.titleColor then
    return L.titleColor({ rarity = row.rarity or 0, unique = row.unique })
  end
  return COLORS.text
end

local function wrapTip(text)
  if Text and Text.wrap then
    local out = {}
    for line in (tostring(text) .. '\n'):gmatch('(.-)\n') do out[#out + 1] = Text.wrap(line, 64, '  ') end
    return table.concat(out, '\n')
  end
  return text
end

local function setStatus(text, color)
  if not window then return end
  window.statusLabel:setText(text or '')
  window.statusLabel:setColor(color or COLORS.dim)
end

-- a one-line label shows the longest start of `text` that fits, cut at a word with "..." (never clipped)
local function fitText(label, text)
  text = tostring(text or '')
  label.fullText = text
  local function apply()
    if label:isDestroyed() then return end
    local w = label:getWidth()
    if w <= 1 then return end
    if not Text or not Text.shorten then
      label:setText(text)
      return
    end
    local s, cut = Text.shorten(text, function(candidate)
      label:setText(candidate)
      return label:getTextSize().width <= w
    end)
    label:setText(s)
    if cut and not label.tipSet then label:setTooltip(wrapTip(text)) end
  end
  label:setText(text)
  if not label.fitConnected then
    label.fitConnected = true
    connect(label, { onGeometryChange = function() apply() end })
  end
  addEvent(apply)
end

local function attr(item, key)
  if getItemAttribute then return getItemAttribute(item, key) end
  local ok, v = pcall(function() return item:getCustomAttribute(key) end)
  return ok and tonumber(v) or 0
end

-- ---------------------------------------------------------------- wallet and combos
local function updateWallet(gold, coins)
  if not window then return end
  if gold then meta = meta or {}; meta.gold = gold end
  if coins then meta = meta or {}; meta.coins = coins end
  local m = meta or {}
  window.walletLabel:setText(string.format('%s market   Bank: %s gold   Chaos Coins: %s', m.realmName or 'Standard',
    V.money(m.gold or 0), V.money(m.coins or 0)))
end

local function fillCombo(combo, options, current)
  updating = true
  combo:clearOptions()
  local index = 1
  for i, o in ipairs(options) do
    combo:addOption(o[1], o[2])
    if o[2] == current then index = i end
  end
  combo:setCurrentIndex(index)
  updating = false
end

local function comboValue(combo)
  local o = combo:getCurrentOption()
  return o and o.data or ''
end

local function fillFilterCombos()
  local cats = { { 'All items', '' } }
  for _, c in ipairs((meta and meta.categories) or { 'weapon', 'shield', 'helmet', 'armor', 'legs', 'boots', 'jewel', 'other', 'orb', 'gem', 'key', 'misc' }) do
    cats[#cats + 1] = { V.CATEGORY_NAMES[c] or c, c }
  end
  fillCombo(window.browsePanel.catCombo, cats, lastFilter.cat or '')
  local rar = { { 'Any rarity', 0 } }
  for i, name in ipairs(V.RARITIES) do rar[#rar + 1] = { name .. ' +', i } end
  fillCombo(window.browsePanel.rarityCombo, rar, lastFilter.rarity or 0)
  fillCombo(window.browsePanel.curCombo, { { 'Any price', '' }, { 'Gold', 'gold' }, { 'Chaos Coins', 'coins' } }, lastFilter.cur or '')
  local sorts = {}
  for _, s in ipairs((meta and meta.sorts) or { 'new', 'price', 'price_desc', 'ilvl', 'rarity', 'name', 'ending' }) do
    sorts[#sorts + 1] = { V.SORT_NAMES[s] or s, s }
  end
  fillCombo(window.browsePanel.sortCombo, sorts, lastFilter.sort or 'new')
  if not modOptions then
    local codex = modules.game_codex
    modOptions = V.modOptions(codex and codex.CodexData or CodexData)
  end
  fillCombo(window.browsePanel.modCombo, modOptions, lastFilter.mod or '')
  local days = {}
  for _, d in ipairs((meta and meta.durations) or { 1, 3, 7 }) do days[#days + 1] = { d == 1 and '1 day' or (d .. ' days'), d } end
  fillCombo(window.sellPanel.daysCombo, days, (meta and meta.defaultDuration) or 3)
end

-- ---------------------------------------------------------------- rows
local function clearList(list)
  if hoveredRow and hoveredRow:getParent() == list then
    local tt = tooltips()
    if tt and tt.hideTip then tt.hideTip(hoveredRow) end
    hoveredRow = nil
  end
  list:destroyChildren()
end

local function showRowTip(row)
  local tt = tooltips()
  local tip = tipCache[row.offer.id]
  if not tt or not tt.showTip or not tip then return end
  local extra = { { text = 'Seller: ' .. (row.offer.seller or tip.seller or '?'), color = COLORS.dim, sep = true } }
  for _, p in ipairs(V.priceLines(row.offer)) do
    extra[#extra + 1] = { text = p.text, color = p.cur == 'coins' and COLORS.coins or COLORS.gold }
  end
  tt.showTip(row, 'market:' .. row.offer.id, tip, extra)
end

local function onRowHover(row, hovered)
  if not hovered then
    if hoveredRow == row then
      local tt = tooltips()
      if tt and tt.hideTip then tt.hideTip(row) end
      hoveredRow = nil
    end
    return
  end
  hoveredRow = row
  if tipCache[row.offer.id] then
    showRowTip(row)
  elseif not tipAsked[row.offer.id] or os.time() - tipAsked[row.offer.id] > 3 then
    tipAsked[row.offer.id] = os.time()
    send('tip', { id = row.offer.id })
  end
end

-- the message box's buttons are of a fixed width: widen the ones whose text does not fit, then the box
local function widenButtons(box)
  if not box or box:isDestroyed() then return end
  local holder = box:getChildById('buttonHolder')
  if not holder then return end
  local total = 0
  for _, b in ipairs(holder:getChildren()) do
    local need = b:getTextSize().width + 24
    if need > b:getWidth() then b:setWidth(need) end
    total = total + b:getWidth() + b:getMarginLeft()
  end
  holder:setWidth(total)
  local inner = total + box:getPaddingLeft() + box:getPaddingRight()
  if inner > box:getWidth() then box:setWidth(inner) end
end

local function confirmBuy(offer)
  local lines = V.priceLines(offer)
  local buttons = {}
  local box
  local function close() if box then box:destroy() box = nil end end
  for _, p in ipairs(lines) do
    local cur = p.cur
    buttons[#buttons + 1] = { text = 'Pay ' .. p.text, callback = function()
      close()
      send('buy', { id = offer.id, cur = cur })
    end }
  end
  buttons[#buttons + 1] = { text = tr('Cancel'), callback = close }
  buttons.anchor = AnchorHorizontalCenter
  local what = ((offer.count or 1) > 1 and (offer.count .. 'x ') or '') .. (offer.name or 'item')
  local msg = string.format('Buy %s from %s?\nIt goes to your inbox (the depot).', what, offer.seller or '?')
  if displayGeneralBox then
    box = displayGeneralBox(tr('Buy'), msg, buttons, nil, close)
    widenButtons(box)
  elseif #lines == 1 then
    send('buy', { id = offer.id, cur = lines[1].cur })
  end
end

local function confirmCancel(offer)
  local box
  local function close() if box then box:destroy() box = nil end end
  local function yes() close() send('cancel', { id = offer.id }) end
  local msg = string.format('Cancel the offer of %s? The item goes back to your inbox; the listing fee is not refunded.', offer.name or 'item')
  if displayGeneralBox then
    box = displayGeneralBox(tr('Cancel offer'), msg, { { text = tr('Yes'), callback = yes }, { text = tr('No'), callback = close },
      anchor = AnchorHorizontalCenter }, yes, close)
  else
    yes()
  end
end

-- one offer row; mode = 'browse' | 'mine' | 'closed' | 'history'
local function addRow(list, offer, mode)
  local row = g_ui.createWidget('MarketRow', list)
  row.offer = offer
  local icon = row:getChildById('icon')
  icon:setItemId(tonumber(offer.item) or 0)
  if (offer.count or 1) > 1 then icon:setItemCount(offer.count) end
  local color = rarityColor(offer)
  if (offer.rarity or 0) > 0 or offer.unique then
    icon:setBorderWidth(2)
    icon:setBorderColor(color)
  end
  local name = row:getChildById('name')
  name:setColor(color)
  fitText(name, ((offer.count or 1) > 1 and (offer.count .. 'x ') or '') .. (offer.name or '?'))
  local sub = row:getChildById('sub')
  local subText
  if mode == 'browse' then
    subText = V.subLine(offer)
  elseif mode == 'history' then
    subText = V.historyLine(offer)
  else
    subText = V.stateLine(offer)
  end
  if mode == 'closed' and offer.state == 'sold' then sub:setColor(COLORS.ok) end
  fitText(sub, subText)
  local prices = V.priceLines(offer)
  local prow = row:getChildById('prices')
  if mode == 'history' or (mode == 'closed' and offer.state == 'sold') then
    prow:getChildById('gold'):setText(V.money(offer.paid or 0) .. (offer.cur == 'coins' and ' coins' or ' gold'))
    prow:getChildById('gold'):setColor(offer.cur == 'coins' and COLORS.coins or COLORS.gold)
    prow:getChildById('coins'):setText('')
  else
    local g, c = prow:getChildById('gold'), prow:getChildById('coins')
    g:setText('')
    c:setText('')
    local slots = { g, c }
    for i, p in ipairs(prices) do
      slots[i]:setText(p.text)
      slots[i]:setColor(p.cur == 'coins' and COLORS.coins or COLORS.gold)
    end
  end
  local button = row:getChildById('buttons'):getChildById('action')
  if mode == 'browse' and not offer.mine then
    button:setText(tr('Buy'))
    button.onClick = function() confirmBuy(offer) end
  elseif (mode == 'browse' and offer.mine) or mode == 'mine' then
    button:setText(tr('Cancel'))
    button.onClick = function() confirmCancel(offer) end
  else
    button:hide()
  end
  row.onHoverChange = onRowHover
  return row
end

local function addHeading(list, text)
  local h = g_ui.createWidget('MarketHeading', list)
  h:setText(text)
  return h
end

-- ---------------------------------------------------------------- Browse
local function readFilter(page)
  local p = window.browsePanel
  return V.filter({ q = p.searchEdit:getText(), cat = comboValue(p.catCombo), rarity = comboValue(p.rarityCombo),
    cur = comboValue(p.curCombo), sort = comboValue(p.sortCombo), mod = comboValue(p.modCombo), ilvlMin = p.ilvlMin:getText(),
    ilvlMax = p.ilvlMax:getText(), priceMin = p.priceMin:getText(), priceMax = p.priceMax:getText(), page = page })
end

local searchEvent
-- filter changes come in bursts (several combos, typing): one request 250 ms after the last change (the server drops
-- Browse requests closer than market_config.lua rate.browse)
function search(page)
  if not window then return end
  if searchEvent then removeEvent(searchEvent) end
  searchEvent = scheduleEvent(function()
    searchEvent = nil
    if not window then return end
    lastFilter = readFilter(page or 1)
    send('browse', lastFilter)
  end, 250)
end

function page(delta)
  local target = (pageInfo.page or 1) + delta
  if target < 1 or target > (pageInfo.pages or 1) then return end
  if not window then return end
  lastFilter = readFilter(target)
  send('browse', lastFilter)
end

function resetFilters()
  if not window then return end
  local p = window.browsePanel
  for _, id in ipairs({ 'searchEdit', 'ilvlMin', 'ilvlMax', 'priceMin', 'priceMax' }) do p[id]:setText('') end
  lastFilter = { page = 1 }
  fillFilterCombos()
  search(1)
end

local function onPage(data)
  local p = window.browsePanel
  clearList(p.offerList)
  pageInfo = { page = data.page or 1, pages = data.pages or 1, total = data.total or 0 }
  for _, offer in ipairs(data.rows or {}) do addRow(p.offerList, offer, 'browse') end
  p.emptyLabel:setVisible(#(data.rows or {}) == 0)
  p.pageLabel:setText(V.pageText(pageInfo.page, pageInfo.pages, pageInfo.total))
  p.pagePrev:setEnabled(pageInfo.page > 1)
  p.pageNext:setEnabled(pageInfo.page < pageInfo.pages)
  p.offerScroll:setValue(0)
end

-- ---------------------------------------------------------------- Sell
local function updateFee()
  if not window then return end
  local s = window.sellPanel
  local gold = V.parseAmount(s.goldEdit:getText()) or 0
  local coins = V.parseAmount(s.coinsEdit:getText()) or 0
  local days = tonumber(comboValue(s.daysCombo)) or 3
  local parts = {}
  local fee = V.fee(meta, gold, coins)
  parts[#parts + 1] = string.format('Listing fee: %s gold from your bank, not refunded.', V.money(fee))
  if gold > 0 then
    local tax, net = V.tax(meta, 'gold', gold)
    parts[#parts + 1] = string.format('Sold for gold: tax %s, you receive %s gold in your bank.', V.money(tax), V.money(net))
  end
  if coins > 0 then
    local tax, net = V.tax(meta, 'coins', coins)
    parts[#parts + 1] = string.format('Sold for coins: tax %s, you receive %s Chaos Coins on your account.', V.money(tax), V.money(net))
  end
  parts[#parts + 1] = string.format('The offer lasts %d day%s; if nothing sells, the item returns to your inbox.', days, days == 1 and '' or 's')
  s.feeText:setText(table.concat(parts, '\n'))
end

local function showSelected()
  local s = window.sellPanel
  if not selected then
    s.sellSlot:setItemId(0)
    s.sellSlot:setBorderWidth(0)
    s.sellName:setText(tr('No item chosen'))
    s.sellName:setColor(COLORS.gold)
    s.sellSub:setText('')
    s.countEdit:setText('')
    s.countEdit:setEnabled(false)
    s.countMax:setText('')
    s.listButton:setEnabled(false)
    return
  end
  s.sellSlot:setItemId(selected.item or 0)
  s.sellSlot:setItemCount(selected.count or 1)
  local color = rarityColor(selected)
  if (selected.rarity or 0) > 0 then
    s.sellSlot:setBorderWidth(2)
    s.sellSlot:setBorderColor(color)
  else
    s.sellSlot:setBorderWidth(0)
  end
  s.sellName:setText(selected.name or '?')
  s.sellName:setColor(color)
  local sub = {}
  if (selected.rarity or 0) > 0 then sub[#sub + 1] = V.rarityName(selected.rarity) end
  if (selected.ilvl or 0) > 0 then sub[#sub + 1] = 'iLvl ' .. selected.ilvl end
  s.sellSub:setText(table.concat(sub, ' - '))
  s.countEdit:setEnabled(selected.stack == true)
  s.countEdit:setText(tostring(selected.count or 1))
  s.countMax:setText(selected.stack and ('of ' .. (selected.count or 1)) or '')
  s.listButton:setEnabled(true)
end

local function choose(entry)
  if entry.why then
    setStatus(entry.why, COLORS.error)
    return
  end
  selected = { ref = entry.ref, sid = entry.sid, iid = entry.iid, count = entry.count, item = entry.item, name = entry.name,
    stack = entry.stack, rarity = entry.rarity, ilvl = entry.ilvl }
  showSelected()
  setStatus('')
end

local function onSellable(data)
  local s = window.sellPanel
  s.pickList:destroyChildren()
  sellItems = V.sortSellable(data.items or {})
  for _, entry in ipairs(sellItems) do
    local w = g_ui.createWidget('MarketPick', s.pickList)
    w:setItemId(tonumber(entry.item) or 0)
    if (entry.count or 1) > 1 then w:setItemCount(entry.count) end
    local tip = (entry.count or 1) > 1 and (entry.count .. 'x ' .. entry.name) or entry.name
    if entry.why then
      w:setOpacity(0.35)
      tip = tip .. '\n' .. entry.why
    end
    if (entry.rarity or 0) > 0 then
      w:setBorderWidth(1)
      w:setBorderColor(rarityColor(entry))
    end
    w:setTooltip(wrapTip(tip))
    w.onClick = function() choose(entry) end
  end
  s.pickHint:setText(#sellItems == 0 and tr('Your backpack is empty: put the items you want to sell in it.')
    or tr('Your backpack: click an item to sell it, or drag one onto the slot on the right.'))
end

-- an item dragged from the backpack (or another open container) onto the slot
local function onDropItem(self, widget, mousePos)
  local item = widget and (widget.currentDragThing or (widget.getItem and widget:getItem()))
  if not item or not item.isItem or not item:isItem() then return false end
  local A = ChaosItemAttr or { ID = 6 }
  local iid = attr(item, A.ID)
  local pos = item:getPosition()
  -- the same item in the picker list (same per-item id, or same look and count)
  for _, e in ipairs(sellItems) do
    if (iid > 0 and tostring(e.iid) == string.format('%.0f', iid)) or (iid <= 0 and e.item == item:getId() and e.count == item:getCount()) then
      choose(e)
      return true
    end
  end
  selected = { pos = { x = pos.x, y = pos.y, z = pos.z }, cid = item:getId(), iid = string.format('%.0f', iid), count = item:getCount(),
    item = item:getId(), name = tr('Dropped item'), stack = item:isStackable() }
  showSelected()
  return true
end

function listItem()
  if not window or not selected then return end
  local s = window.sellPanel
  local form, why = V.checkSell(meta, { gold = s.goldEdit:getText(), coins = s.coinsEdit:getText(),
    count = selected.stack and s.countEdit:getText() or 1, have = selected.count or 1, days = comboValue(s.daysCombo) })
  if not form then
    setStatus(why, COLORS.error)
    return
  end
  send('list', { ref = selected.ref, pos = selected.pos, sid = selected.sid, cid = selected.cid, iid = selected.iid, count = form.count,
    gold = form.gold, coins = form.coins, days = form.days })
end

-- ---------------------------------------------------------------- My Offers / History
local function onMine(data)
  local list = window.minePanel.mineList
  clearList(list)
  addHeading(list, string.format('Active offers (%d / %d)', #(data.active or {}), data.max or 20))
  for _, offer in ipairs(data.active or {}) do addRow(list, offer, 'mine') end
  if #(data.active or {}) == 0 then
    local t = g_ui.createWidget('MarketTextDim', list)
    t:setHeight(18)
    t:setText(tr('No active offers. List items in the Sell tab.'))
  end
  if (data.owed or 0) > 0 then
    local t = g_ui.createWidget('MarketText', list)
    t:setHeight(18)
    t:setColor(COLORS.gold)
    t:setText(string.format('%d deliveries are on the way to your inbox / bank.', data.owed))
  end
  addHeading(list, tr('Sold, expired and cancelled'))
  for _, offer in ipairs(data.closed or {}) do addRow(list, offer, 'closed') end
end

local function onHistory(data)
  local list = window.historyPanel.historyList
  clearList(list)
  addHeading(list, tr('Your purchases and sales'))
  for _, offer in ipairs(data.rows or {}) do addRow(list, offer, 'history') end
  if #(data.rows or {}) == 0 then
    local t = g_ui.createWidget('MarketTextDim', list)
    t:setHeight(18)
    t:setText(tr('Nothing bought or sold yet.'))
  end
end

-- ---------------------------------------------------------------- tabs
local PANELS = { 'browsePanel', 'sellPanel', 'minePanel', 'historyPanel' }

local function showTab(i)
  tabIndex = i
  for k, b in ipairs(tabs) do b:setChecked(k == i) end
  for k, id in ipairs(PANELS) do window[id]:setVisible(k == i) end
  local tt = tooltips()
  if hoveredRow and tt and tt.hideTip then tt.hideTip(hoveredRow) hoveredRow = nil end
  if i == 1 then
    send('browse', lastFilter)
  elseif i == 2 then
    send('sellable')
    updateFee()
  elseif i == 3 then
    send('mine')
  elseif i == 4 then
    send('history')
  end
end

-- ---------------------------------------------------------------- server messages
local function onMessage(protocol, opcode, msg)
  if not window or type(msg) ~= 'table' then return end
  local data = type(msg.data) == 'table' and msg.data or {}
  local a = msg.action
  if a == 'meta' then
    meta = data
    fillFilterCombos()
    updateWallet()
    local s = window.sellPanel
    s.rulesText:setText(string.format('Locked, equipped, store and quest items and bags with something inside cannot be listed. '
      .. 'Bought items and items that come back arrive in your inbox (the depot); gold goes to your bank, Chaos Coins to your '
      .. 'account. Up to %d offers at a time.%s', meta.maxActive or 20,
      (meta.realm or 0) > 0 and ' Season characters trade on their own season market.' or ''))
    updateFee()
    if not window:isVisible() then return end
    showTab(tabIndex)
  elseif a == 'openWindow' then
    window:show()
    window:raise()
    window:focus()
  elseif a == 'page' then
    onPage(data)
  elseif a == 'tip' then
    if data.id and type(data.tip) == 'table' then
      tipCache[data.id] = data.tip
      if hoveredRow and not hoveredRow:isDestroyed() and hoveredRow.offer.id == data.id then showRowTip(hoveredRow) end
    end
  elseif a == 'sellable' then
    onSellable(data)
  elseif a == 'mine' then
    onMine(data)
  elseif a == 'history' then
    onHistory(data)
  elseif a == 'wallet' then
    updateWallet(data.gold, data.coins)
  elseif a == 'done' then
    setStatus(data.text, COLORS.ok)
    if data.what == 'list' then
      selected = nil
      showSelected()
      window.sellPanel.goldEdit:setText('')
      window.sellPanel.coinsEdit:setText('')
      send('sellable')
    elseif data.what == 'buy' then
      send('browse', lastFilter)
    elseif data.what == 'cancel' then
      if tabIndex == 3 then send('mine') else send('browse', lastFilter) end
    end
  elseif a == 'error' then
    setStatus(data.text, COLORS.error)
  end
end

-- ---------------------------------------------------------------- public
function show()
  if not window or not g_game.isOnline() then return end
  window:show()
  window:raise()
  window:focus()
  send('open')
end

function hide()
  if not window then return end
  local tt = tooltips()
  if hoveredRow and tt and tt.hideTip then tt.hideTip(hoveredRow) end
  hoveredRow = nil
  window:hide()
end

function toggle()
  if not window then return end
  if window:isVisible() then hide() else show() end
end

local function onGameEnd()
  hide()
  meta, selected, tipCache, tipAsked, sellItems = nil, nil, {}, {}, {}
  lastFilter = { page = 1 }
end

function init()
  window = g_ui.displayUI('market')
  window:hide()
  for i, name in ipairs({ tr('Browse'), tr('Sell'), tr('My Offers'), tr('History') }) do
    local b = g_ui.createWidget('ChaosTabButton', window.tabBar)
    b:setText(name)
    b.onClick = function() showTab(i) end
    tabs[i] = b
  end
  tabs[1]:setChecked(true)
  local p = window.browsePanel
  p.searchEdit.onTextChange = function(w, text)
    p.searchHint:setVisible(text == '')
    if not updating then search(1) end
  end
  p.searchEdit.onKeyPress = function(w, keyCode)
    if keyCode == KeyEnter then search(1) return true end
    return false
  end
  for _, id in ipairs({ 'catCombo', 'rarityCombo', 'curCombo', 'sortCombo', 'modCombo' }) do
    p[id].onOptionChange = function() if not updating then search(1) end end
  end
  local s = window.sellPanel
  s.goldEdit.onTextChange = function() updateFee() end
  s.coinsEdit.onTextChange = function() updateFee() end
  s.daysCombo.onOptionChange = function() if not updating then updateFee() end end
  s.sellSlot.onDrop = onDropItem
  fillFilterCombos()
  showSelected()
  updateFee()
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, onMessage)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  if searchEvent then removeEvent(searchEvent) searchEvent = nil end
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if window then
    window:destroy()
    window = nil
  end
  tabs = {}
end
