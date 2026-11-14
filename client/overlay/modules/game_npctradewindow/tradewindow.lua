-- NPC trade window (O571, owner 2026-11-14: "melhore essas janelas de trade. pode refazer do zero"). The buy / sell list of an
-- NPC in a window of its own, in the middle of the game view: Buy and Sell tabs, search, category chips, a grid of item cards
-- (icon, name, price with the coin, weight, how many the player carries), a side panel with the amount (- / + / Max and a
-- slider), the total, the gold left and the capacity left, a Sell all window that shows what will be sold first. Enter trades,
-- Esc closes the shop, the x ends the conversation as before.
--
-- The base module game_npctrade still reads the shop packets (its dialog window and console hooks are what game_npctalk
-- replaces), but its own window was a 175 px mini window in a side panel. While this module is loaded it takes the shop over:
-- the base's handlers of the shop signals are disconnected, the calls other modules make (show, hide, isTrading,
-- closeNpcTrade, sellAll, getPlayerMoney) answer from here, and the base window never opens. Everything the base window
-- did is here: buy (also into shopping bags, gold only), sell (equipped copies kept unless asked), ignore capacity,
-- the quick sale in packets of 100 that waits for the server's player goods, the ignore list of that sale (the same file
-- the base wrote), Look / Inspect on a right click, sorting, a currency other than gold announced on extended opcode 113
-- (server data/lib/chaos_npc_currency.lua: the currency's name, icon and the player's balance in it).
--
-- Where the data goes: trademodel.lua (cards, limits, totals, the queue), the widgets: tradeview.lua + tradewindow.otui, the
-- currency and the window geometry: tradewindowlogic.lua. Tests: trademodel_test, tradeview_test, tradewindow_test.

local L = TradeWindowLogic
local M = TradeModel
local V = TradeView
local OPCODE = 113 -- ChaosOpcodes.npcCurrency (server chaos_constants.lua)
local MENU_ID = 'npctrade'

local window, view, sellAll, session
local base = {}            -- what was taken from game_npctrade: its functions and the handlers it had connected
local currency = L.newState()
local st                   -- the open shop (nil when none)
local prefs = { sort = 'name', bags = false, ignoreCapacity = false, sellEquipped = false }
local ignoreList = {}
local facts = {}           -- item id -> {market, clothSlot}
local sellAllState

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function warn(err)
  g_logger.warning('[npctradewindow] ' .. tostring(err))
end

local function now()
  local ok, t = pcall(function() return g_clock.seconds() end)
  return ok and t or os.time()
end

local function rootPanel()
  local gi = modules.game_interface
  return gi and gi.getRootPanel and gi.getRootPanel() or g_ui.getRootWidget()
end

local function goldId()
  return GOLD_COINS or 3031
end

-- ---------------------------------------------------------------- where the window opens (one place: O572)
local function placeWindow(w)
  local root = rootPanel()
  if not alive(w) or not alive(root) then return end
  local g = L.geometry(root:getWidth(), root:getHeight(), 0)
  if w:getParent() ~= root then w:setParent(root, true) end
  w:setSize({ width = g.w, height = g.h })
  w:setPosition({ x = root:getX() + g.x, y = root:getY() + g.y })
end

-- ---------------------------------------------------------------- the player's goods
local function player()
  return g_game.getLocalPlayer()
end

local function itemId(item)
  return item.ptr:getId()
end

local function wornSlots()
  return InventorySlotsWorn or { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
end

-- how many of the item the shop can take from the player: what he carries, less the copies he wears unless he said so
local function sellQuantity(ptr, excludeEquipped)
  local have = st and st.owned[ptr:getId()]
  if not have then return 0 end
  if excludeEquipped == nil then excludeEquipped = not prefs.sellEquipped end
  local worn = 0
  if excludeEquipped then
    local p = player()
    if not p then return 0 end
    for _, slot in ipairs(wornSlots()) do
      local it = p:getInventoryItem(slot)
      if it and it:getId() == ptr:getId() and
          (not ptr:isFluidContainer() or it:getCountOrSubType() == ptr:getCountOrSubType()) then
        worn = worn + (it:isStackable() and it:getCount() or 1)
      end
    end
  end
  return math.max(0, have - worn)
end

local function getMoney()
  if currency.active then return currency.active.amount end
  return st and st.money or 0
end

local function isGold()
  return currency.active == nil
end

local function subtypeOf(ptr)
  return ptr:isStackable() and 0 or ptr:getCountOrSubType()
end

-- an item the quick sale may send in packets: no fluid, splash or charges, and one copy per id (the sale packet cannot
-- tell two variants of an id apart)
local function bulkOk(item)
  local ptr = item.ptr
  if st and st.variants[itemId(item)] then return false end
  if ptr:isStackable() then return true end
  local t = g_things.getThingType(ptr:getId(), ThingCategoryItem)
  return (t and not t:isFluidContainer() and not t:isSplash() and not t:isChargeable() and
    not (ptr.isChargeableByCategory and ptr:isChargeableByCategory()) and ptr:getCountOrSubType() == 0) and true or false
end

local function factsOf(item)
  local id = itemId(item)
  local f = facts[id]
  if not f then
    f = {}
    if getItemCategory then
      local ok, c = pcall(getItemCategory, id)
      if ok then f.market = c end
    end
    local ok, t = pcall(g_things.getThingType, id, ThingCategoryItem)
    if ok and t and t.getClothSlot then
      local okSlot, slot = pcall(function() return t:getClothSlot() end)
      if okSlot then f.clothSlot = slot end
    end
    facts[id] = f
  end
  return { market = f.market, clothSlot = f.clothSlot, name = item.name }
end

-- ---------------------------------------------------------------- the model context
local function ownedOf(item)
  if st.tab == M.SELL then return sellQuantity(item.ptr) end
  return st.owned[itemId(item)]
end

local function tradable(item)
  if st.tab == M.BUY then
    local single = M.total({ type = M.BUY, bags = prefs.bags and isGold() }, item, 1)
    return (prefs.ignoreCapacity or st.freeCap >= item.weight) and getMoney() >= single
  end
  return sellQuantity(item.ptr) > 0
end

local function ctx()
  return { type = st.tab, items = st.items[st.tab], search = st.search, sort = prefs.sort, factsOf = factsOf,
    owned = ownedOf, tradable = tradable, money = getMoney(), freeCapacity = st.freeCap,
    ignoreCapacity = prefs.ignoreCapacity, bags = prefs.bags and isGold() }
end

local function headerSpec()
  local spec = currency.active
  if spec then
    return { name = spec.name, fullName = spec.fullName, item = spec.item, caption = tr('Balance'), balance = spec.amount,
      gold = false }
  end
  return { name = tr('Gold Coin'), item = goldId(), caption = tr('Gold'), balance = st and st.money or 0, gold = true }
end

local function currencyName()
  return currency.active and currency.active.fullName or tr('Gold Coin')
end

-- ---------------------------------------------------------------- showing the shop
local function signature(chips)
  local parts = {}
  for _, c in ipairs(chips) do parts[#parts + 1] = c.id .. c.count end
  return table.concat(parts, ',')
end

local refresh

local function selectedCard()
  return st.selectedKey and st.cardsByKey[st.selectedKey] or nil
end

-- recompute what the window shows; `rebuild`: the shop's list changed (new shop, other tab): new card widgets
refresh = function(rebuild)
  if not st or not alive(window) or not window:isVisible() then return end
  local c = ctx()
  local pre, all = M.cards(c)
  st.cardsByKey = {}
  for _, card in ipairs(all) do st.cardsByKey[card.key] = card end
  if rebuild then
    view:setCards(all)
    st.chipSig = nil
  end
  local chips = M.chips(pre)
  local known = false
  for _, ch in ipairs(chips) do if ch.id == st.category then known = true end end
  if not known then st.category = 'all' end
  local sig = signature(chips) .. '|' .. st.category
  if sig ~= st.chipSig then
    st.chipSig = sig
    view:setChips(chips, st.category)
  end
  local visible = M.filterCategory(pre, st.category)
  local keep = false
  for _, card in ipairs(visible) do if card.key == st.selectedKey then keep = true end end
  if not keep then st.selectedKey = nil end
  view:setBalance(getMoney())
  local empty
  if #st.items[st.tab] == 0 then
    empty = st.tab == M.BUY and tr('This seller sells nothing.') or tr('This seller buys nothing from you.')
  elseif st.tab == M.SELL and st.search == '' and #pre == 0 then
    empty = tr('You carry nothing this seller buys.')
  end
  view:update({ visible = visible, selected = st.selectedKey, tab = st.tab, empty = empty })
  local card = selectedCard()
  local d = card and M.detail(c, card, st.amount) or nil
  if d then st.amount = d.amount end
  view:setSelection(card, d, c)
end

local function select(key)
  if not st then return end
  local card = st.cardsByKey[key]
  if not card then return end
  st.selectedKey = key
  if st.tab == M.SELL then
    local max = M.limit(ctx(), card.item)
    st.amount = max
  else
    st.amount = 1
  end
  refresh()
end

local function setTab(tab, force)
  if not st or (st.tab == tab and not force) then return end
  if #st.items[tab] == 0 and not force then return end
  st.tab = tab
  st.selectedKey = nil
  st.category = 'all'
  st.amount = 1
  view:setTab(tab)
  refresh(true)
end

local function closeSellAll()
  if alive(sellAll and sellAll.window) then
    sellAll.window:destroy()
    if g_client and g_client.setInputLockWidget then g_client.setInputLockWidget(nil) end
  end
  sellAll, sellAllState = nil, nil
end

local function toggleFocus(on)
  local gi = modules.game_interface
  if gi and gi.toggleFocus then pcall(gi.toggleFocus, on, MENU_ID) end
end

local function hideShop()
  if session then session:finish() end
  closeSellAll()
  if alive(window) and window:isVisible() then
    window:hide()
    toggleFocus(false)
    local console = modules.game_console
    if console and console.getConsole then
      local okConsole, c = pcall(console.getConsole)
      if okConsole and c then pcall(function() c:focus() end) end
    end
  end
  if view then view:clearCards() end
  L.release(currency)
  st = nil
end

-- the shop closed by the player: tell the server, then hide
local function closeShop()
  if not (session and session.open) then
    hideShop()
    return
  end
  g_game.doThing(false)
  g_game.closeNpcTrade()
  g_game.doThing(true)
  hideShop()
end

-- the x: the conversation ends too (game_npctalk hooks endNpcConversation: it says bye)
local function endConversation()
  closeShop()
  local trade = modules.game_npctrade
  if trade and type(trade.endNpcConversation) == 'function' then
    local ok, err = pcall(trade.endNpcConversation)
    if not ok then warn(err) end
  end
end

-- ---------------------------------------------------------------- trading
local function inspect(item)
  if g_game.inspectNpcTrade then g_game.inspectNpcTrade(item.ptr) end
end

local function doTrade()
  if not (st and session and session.open) then return end
  local card = selectedCard()
  if not card or st.amount < 1 then return end
  if session.queue then
    session.queue:cancel()
    session.queue = nil
  end
  local max = M.limit(ctx(), card.item)
  local amount = M.clampAmount(st.amount, 1, max)
  if amount < 1 then return end
  if st.tab == M.BUY then
    g_game.buyItem(card.item.ptr, amount, prefs.ignoreCapacity, prefs.bags and isGold())
  else
    g_game.sellItem(card.item.ptr, amount, not prefs.sellEquipped)
  end
end

local function setAmount(n)
  if not st then return end
  local card = selectedCard()
  if not card then return end
  local max = M.limit(ctx(), card.item)
  st.amount = M.clampAmount(n, 1, max)
  refresh()
end

local function queueError(message)
  if message:find('too many', 1, true) then return tr('Sale stopped: too many chunks. Please refresh the shop.') end
  return tr('Sale stopped: the server did not confirm the sale. Please refresh the shop.')
end

local function infoBox(text)
  if displayInfoBox then displayInfoBox(tr('Sell all'), text) end
end

-- sell the rows one packet at a time, each only after the server's player goods confirmed the one before
local function startSale(rows)
  if not (st and session and session.open and g_game.isOnline()) then return false end
  if session.queue then session.queue:cancel() end
  session.queue = nil
  local generation = session.generation
  local excludeEquipped = not prefs.sellEquipped
  local entries = {}
  for _, r in ipairs(rows) do
    if sellQuantity(r.item.ptr, excludeEquipped) > 0 then
      entries[#entries + 1] = { ptr = r.item.ptr, price = r.price, key = r.key }
    end
  end
  local queue
  queue = M.newQueue({
    isValid = function() return session.open and session.generation == generation and g_game.isOnline() end,
    quantity = function(e) return sellQuantity(e.ptr, excludeEquipped) end,
    capped = function(e) return st and st.owned[e.ptr:getId()] == M.PLAYER_GOODS_CAP end,
    money = getMoney,
    sell = function(e, amount) g_game.sellItem(e.ptr, amount, excludeEquipped) end,
    schedule = function(fn, delay) return session:schedule(fn, delay) end,
    cancel = removeEvent,
    onFinish = function(sold, proceeds)
      if session.queue == queue then session.queue = nil end
      if sold > 0 then
        infoBox(tr('The server confirmed %s items sold for %s %s.', tostring(sold), comma_value and comma_value(tostring(proceeds)) or tostring(proceeds),
          currencyName()))
      end
    end,
    onError = function(message)
      if session.queue == queue then session.queue = nil end
      infoBox(queueError(message))
    end,
  })
  session.queue = queue
  queue:start(entries)
  return true
end

-- ---------------------------------------------------------------- the ignore list
local function ignoreFile()
  if LoadedPlayer and LoadedPlayer.isLoaded and LoadedPlayer:isLoaded() then
    return '/characterdata/' .. LoadedPlayer:getId() .. '/sellAllWhitelist.json'
  end
  return nil
end

local function loadIgnore()
  ignoreList = {}
  local file = ignoreFile()
  if not file or not g_resources.fileExists(file) then return end
  local ok, data = pcall(function() return json.decode(g_resources.readFileContents(file)) end)
  if ok then ignoreList = M.cleanIgnoreList(data) else warn('the ignore list could not be read: ' .. tostring(data)) end
end

local function saveIgnore()
  local file = ignoreFile()
  if not file then return end
  local ok, text = pcall(json.encode, ignoreList, 2)
  if ok then g_resources.writeFileContents(file, text) else warn(text) end
end

local function ignoreHas(id)
  for _, v in ipairs(ignoreList) do if v == id then return true end end
  return false
end

local function ignoreSet(id, on)
  if on and not ignoreHas(id) then
    ignoreList[#ignoreList + 1] = id
  elseif not on then
    for i, v in ipairs(ignoreList) do if v == id then table.remove(ignoreList, i) break end end
  end
  saveIgnore()
end

-- ---------------------------------------------------------------- Sell all
local function sellAllRows()
  local variants, firstSub = {}, {}
  for _, item in ipairs(st.items[M.SELL]) do
    local id, sub = itemId(item), subtypeOf(item.ptr)
    if firstSub[id] == nil then firstSub[id] = sub elseif firstSub[id] ~= sub then variants[id] = true end
  end
  st.variants = variants
  return M.sellAllRows({
    items = st.items[M.SELL], owned = function(item) return sellQuantity(item.ptr) end,
    ignored = M.ignoreSet(ignoreList), idOf = itemId, subtypeOf = function(item) return subtypeOf(item.ptr) end,
    bulkOk = bulkOk,
    marketValue = function(item)
      local ok, v = pcall(function() return item.ptr:getAverageMarketValue() end)
      return ok and tonumber(v) or nil
    end,
  })
end

local function renderSellAll()
  if not sellAll or not st then return end
  local rows = sellAllRows()
  sellAllState.rows = rows
  sellAllState.totals = M.sellAllTotals(rows, sellAllState.unticked)
  sellAll:render(rows, sellAllState, currencyName())
end

local function confirmSellAll()
  if not sellAll or not st then return end
  local totals = M.sellAllTotals(sellAllState.rows or {}, sellAllState.unticked)
  if totals.rows == 0 then return end
  local ok = totals.ok
  closeSellAll()
  startSale(ok)
end

local function openSellAll()
  if not st or st.tab ~= M.SELL then return end
  closeSellAll()
  local root = g_ui.getRootWidget()
  local w = g_ui.createWidget('TradeSellAllWindow', root)
  w.chaosNoMirror = true -- item icons in Lua-made rows (see init)
  sellAll = V.newSellAll(w)
  sellAllState = { ignoredTab = false, unticked = {}, rows = {}, totals = { rows = 0, pieces = 0, gold = 0, below = 0, ok = {} } }
  sellAll.on.tab = function(ignored) sellAllState.ignoredTab = ignored renderSellAll() end
  sellAll.on.tick = function(row, on) sellAllState.unticked[row.key] = (not on) or nil renderSellAll() end
  sellAll.on.keep = function(row) ignoreSet(row.id, not row.ignored) renderSellAll() end
  sellAll.on.sell = confirmSellAll
  sellAll.on.cancel = closeSellAll
  w.onEscape = closeSellAll
  g_keyboard.bindKeyDown('Escape', function() closeSellAll() return true end, w)
  g_keyboard.bindKeyDown('Enter', function() confirmSellAll() return true end, w)
  local r = rootPanel()
  if alive(r) then
    local rw, rh = r:getWidth(), r:getHeight()
    w:setPosition({ x = r:getX() + math.max(0, math.floor((rw - w:getWidth()) / 2)),
      y = r:getY() + math.max(0, math.floor((rh - w:getHeight()) / 2)) })
  end
  w:show(true)
  w:raise()
  w:focus()
  if g_client and g_client.setInputLockWidget then g_client.setInputLockWidget(w) end
  renderSellAll()
end

-- ---------------------------------------------------------------- the right click menu
local function itemMenu(card, pos, button)
  if button ~= MouseRightButton or not card then return false end
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addOption(tr('Look'), function() inspect(card.item) end)
  menu:addOption(tr('Inspect'), function() g_game.sendInspectionObject(3, itemId(card.item), 1) end)
  menu:addSeparator()
  for _, sort in ipairs(M.SORTS) do
    local label = sort == 'name' and tr('Sort by name') or sort == 'price' and tr('Sort by price') or tr('Sort by weight')
    menu:addCheckBoxOption(label, function()
      prefs.sort = sort
      view:setSort(sort)
      refresh()
    end, '', prefs.sort == sort)
  end
  menu:display(pos or g_window.getMousePosition())
  return true
end

-- ---------------------------------------------------------------- the shop opens
local function parseItems(items)
  local list = { [M.BUY] = {}, [M.SELL] = {} }
  for _, row in pairs(items) do
    local ptr = row[1]
    local function entry(price)
      return { ptr = ptr, name = row[2], weight = row[3] / 100, price = price, stackable = ptr:isStackable() }
    end
    if row[4] > 0 then table.insert(list[M.BUY], entry(row[4])) end
    if row[5] > 0 then table.insert(list[M.SELL], entry(row[5])) end
  end
  return list
end

local function showShop()
  if not (st and session and session.open and alive(window)) then return end
  L.take(currency, now())
  placeWindow(window)
  window:show()
  window:raise()
  window:focus()
  view:setHeader(headerSpec())
  view:setSort(prefs.sort)
  view:setOptions(prefs)
  view:setSearch('')
  local buyN, sellN = #st.items[M.BUY], #st.items[M.SELL]
  view:setTabCounts(buyN, sellN)
  st.tab = buyN > 0 and M.BUY or M.SELL
  view:setTab(st.tab)
  refresh(true)
end

local function onOpenNpcTrade(items)
  hideShop()
  session:begin()
  loadIgnore()
  local p = player()
  st = { tab = M.BUY, items = parseItems(items), owned = {}, money = 0, freeCap = p and p:getFreeCapacity() or 0,
    search = '', category = 'all', amount = 1, cardsByKey = {}, variants = {} }
  -- the player goods come right after this packet: the window waits for them
  session:schedule(showShop)
end

local function onCloseNpcTrade()
  hideShop()
end

local function onPlayerGoods(money, items)
  if not (st and session and session.open) then return end
  st.money = tonumber(money) or 0
  st.owned = {}
  for _, item in pairs(items or {}) do
    local id = item[1]:getId()
    st.owned[id] = (st.owned[id] or 0) + item[2]
  end
  refresh()
  if sellAll then renderSellAll() end
  if session.queue then session.queue:onGoods() end
end

local function onFreeCapacityChange(_, freeCapacity)
  if not st then return end
  st.freeCap = freeCapacity
  refresh()
end

local function onInventoryChange()
  if st then refresh() end
end

-- opcode 113: the currency of the shop that opens next, or the balance after a purchase or a sale
local function onCurrency(_, _, buffer)
  local spec = L.parseCurrency(buffer, json.decode)
  local what = L.receive(currency, spec, now())
  if what == 'update' and st then refresh() end
end

-- ---------------------------------------------------------------- keys
local function onEscape()
  if sellAll then
    closeSellAll()
    return true
  end
  if st and alive(window) and window:isVisible() then
    closeShop()
    return true
  end
  return false
end

local function searchHasFocus()
  return view and view.ui.searchText.isFocused and view.ui.searchText:isFocused()
end

local function onEnter()
  if not (st and alive(window) and window:isVisible()) then return false end
  if searchHasFocus() then
    -- Enter in the search picks the first card of the list
    local visible = M.filterCategory(M.cards(ctx()), st.category)
    if #visible > 0 then select(visible[1].key) end
    return true
  end
  doTrade()
  return true
end

local function onStep(dir)
  if not st then return false end
  local visible = M.filterCategory(M.cards(ctx()), st.category)
  local key = M.step(visible, st.selectedKey, dir)
  if key then select(key) end
  return true
end

-- ---------------------------------------------------------------- what other modules call on game_npctrade
local function takeOver(trade)
  base.trade = trade
  base.show, base.hide, base.isTrading = trade.show, trade.hide, trade.isTrading
  base.closeNpcTrade, base.sellAll, base.getPlayerMoney = trade.closeNpcTrade, trade.sellAll, trade.getPlayerMoney
  base.game = { onOpenNpcTrade = trade.onOpenNpcTrade, onCloseNpcTrade = trade.onCloseNpcTrade,
    onPlayerGoods = trade.onPlayerGoods }
  base.player = { onFreeCapacityChange = trade.onFreeCapacityChange, onInventoryChange = trade.onInventoryChange }
  pcall(disconnect, g_game, base.game)
  pcall(disconnect, LocalPlayer, base.player)
  trade.show = function() return true end
  trade.hide = function() hideShop() end
  trade.isTrading = function() return session ~= nil and session.open end
  trade.closeNpcTrade = function() closeShop() end
  trade.getPlayerMoney = getMoney
  -- the bot's and helper's "sell everything to the NPC next to me": the whole list, no window, the same queue
  trade.sellAll = function(delayed, exceptions)
    if type(delayed) == 'table' then exceptions = delayed end
    if not st then return false end
    local excluded = {}
    for _, id in pairs(exceptions or {}) do excluded[id] = true end
    local rows = {}
    for _, r in ipairs(sellAllRows()) do
      if not excluded[r.id] and not r.manual then rows[#rows + 1] = r end
    end
    return startSale(rows)
  end
end

local function giveBack()
  local trade = base.trade
  if not trade then return end
  trade.show, trade.hide, trade.isTrading = base.show, base.hide, base.isTrading
  trade.closeNpcTrade, trade.sellAll, trade.getPlayerMoney = base.closeNpcTrade, base.sellAll, base.getPlayerMoney
  pcall(connect, g_game, base.game)
  pcall(connect, LocalPlayer, base.player)
  base = {}
end

-- ---------------------------------------------------------------- module
function init()
  local npcTrade = modules.game_npctrade
  local root = rootPanel()
  if not npcTrade or not root then
    g_logger.warning('[npctradewindow] game_npctrade or the game view not found: the trade stays as the base made it')
    return
  end
  g_ui.importStyle('tradewindow')
  window = g_ui.createWidget('TradeWindow', root)
  window:setId('tradeWindow')
  window.chaosNoMirror = true -- item icons in Lua-made cards: the RmlUi window mirror leaves it in OTUI
  window:hide()
  view = V.new(window)
  session = M.newSession(scheduleEvent, removeEvent)
  view.on = {
    tab = function(tab) setTab(tab) end,
    close = endConversation,
    sort = function() prefs.sort = M.nextSort(prefs.sort) view:setSort(prefs.sort) refresh() end,
    clearSearch = function()
      if not st then return end
      st.search = ''
      view:setSearch('')
      refresh()
    end,
    search = function(text) if st then st.search = text or '' refresh() end end,
    category = function(id) if st then st.category = id st.chipSig = nil refresh() end end,
    select = function(key)
      if g_keyboard.isShiftPressed and g_keyboard.isShiftPressed() and st and st.cardsByKey[key] then
        inspect(st.cardsByKey[key].item)
        return
      end
      select(key)
    end,
    amount = function(n) if n then setAmount(n) end end,
    step = function(delta) if st then setAmount(st.amount + delta) end end,
    max = function()
      local card = st and selectedCard()
      if card then setAmount(M.limit(ctx(), card.item)) end
    end,
    trade = doTrade,
    sellAll = openSellAll,
    itemMenu = itemMenu,
    option = function(name, on)
      prefs[name] = on == true
      if name == 'sellEquipped' or name == 'ignoreCapacity' or name == 'bags' then refresh() end
    end,
  }
  for _, id in ipairs({ 'searchText', 'amountText' }) do
    view.ui[id].onFocusChange = function(_, focused) if focused then toggleFocus(true) end end
  end
  g_keyboard.bindKeyDown('Escape', onEscape, window)
  g_keyboard.bindKeyDown('Enter', onEnter, window)
  g_keyboard.bindKeyDown('Up', function() return onStep(-1) end, window)
  g_keyboard.bindKeyDown('Down', function() return onStep(1) end, window)
  takeOver(npcTrade)
  connect(g_game, { onOpenNpcTrade = onOpenNpcTrade, onCloseNpcTrade = onCloseNpcTrade, onPlayerGoods = onPlayerGoods,
    onGameEnd = hideShop })
  connect(LocalPlayer, { onFreeCapacityChange = onFreeCapacityChange, onInventoryChange = onInventoryChange })
  ProtocolGame.registerExtendedOpcode(OPCODE, onCurrency)
end

function terminate()
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  pcall(disconnect, g_game, { onOpenNpcTrade = onOpenNpcTrade, onCloseNpcTrade = onCloseNpcTrade,
    onPlayerGoods = onPlayerGoods, onGameEnd = hideShop })
  pcall(disconnect, LocalPlayer, { onFreeCapacityChange = onFreeCapacityChange, onInventoryChange = onInventoryChange })
  if session then session:finish() end
  closeSellAll()
  giveBack()
  if alive(window) then window:destroy() end
  window, view, session, st = nil, nil, nil, nil
  currency = L.newState()
end

-- for tests and other modules
function isTrading() return session ~= nil and session.open end
function getWindow() return window end
