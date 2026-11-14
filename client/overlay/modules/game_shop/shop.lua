-- game_shop: the Chaos store (server: data/scripts/chaos/shop.lua, extended opcode 218, JSON).
-- Categories and pages come from the server; prices are in Chaos Coins. The server decides every price: an offer
-- carries cost, oldCost (struck through), tags (Sale / New / Featured / Bundle), gift (can be bought for another
-- character) and owned; buying echoes title and cost back, so a price that changed is refused, never charged.
-- The Donate button opens the donation window (pay.lua: Pix / PayPal, Chaos Coins as a thank-you).
-- The layout (O556, 2026-11-14): a header (balance with its coin, Donate, search), a short side rail with Home and one entry
-- per top group (Cosmetics, Consumables, Premium & Services and the top categories; shoptree.lua builds the tree, the rule
-- of the rail and the home page is shopview.lua), the subcategories of a group as chips inside the page, the offers as
-- cards, and a details pane (description, price, Buy with a confirmation, Gift, Try on) for the picked card. The window
-- opens on the home page: the weekly offers with their timer, the starter packs and the bundles, read from the pages of
-- those categories (no protocol change). The search box asks the server (`search`), which answers with offers that
-- carry where they are (`at`), so buying from the results works as from a page.
-- private variables
local SHOP_EXTENTED_OPCODE = 218
local currentCategoryPage = {}
shop = nil
transferWindow = nil
local otcv8shop = false
local shopButton = nil
local msgWindow = nil
local browsingHistory = false
local transferValue = 0
local CATEGORIES = {}
local GROUPS = {} -- the parents of the tree ("category_groups"; none from a server without the tree)
local TREE = {} -- ShopTree.build(CATEGORIES, GROUPS)
local RAIL = {} -- ShopView.rail(TREE, has a home page)
local HOME = {} -- ShopView.homeSections(TREE)
local view = 'category' -- what the page shows: 'home', 'category', 'search' or 'history'
local railKey = nil -- the rail entry that is open (ShopView.HOME, 'g:Cosmetics', 'c:3'), nil in a search or the history
local selectedCategory = nil -- the index of the shown category
local pendingCategory = nil -- a category to show once the list comes (openCategory)
local wantHome = false -- the window was just opened: the home page once the list comes
local searching = nil -- the search text whose results are shown
local searchOffers = nil -- the offers of the last results, searchGroup the chip that filters them
local searchGroup = nil
local searchEvent = nil
local HISTORY = {}
local STATUS = {}
local AD = {}
local selectedOffer = {}
local selectedCard = nil -- the card whose details the pane shows
local giftWindow = nil
local lookPreview = nil -- the shared look preview (game_lookpreview), nil without it or on mobile
local ui = {} -- the widgets of the window by id (nested ones are not fields of the window)
local pathEndsAt = nil -- the weekly rotation's end while its category is shown (the path's timer)

local CARD_W, CARD_H, CARD_GAP = 168, 68, 6
local LOOK_HEIGHT = 190 -- the look preview's room in the details pane (offers that have a look)
local CHIP_W, CHIP_H, CHIP_GAP, CHIP_CHARS = 108, 22, 3, 19
local NAME_CHARS = 34 -- two lines of a card's name
local ONE_LINE_CHARS = 16 -- what fits on one line of it

local function sendAction(action, data)
  if not g_game.getFeature(GameExtendedOpcode) then
    return
  end

  local protocolGame = g_game.getProtocolGame()
  if data == nil then
    data = {}
  end
  if protocolGame then
    protocolGame:sendExtendedJSONOpcode(SHOP_EXTENTED_OPCODE, {action = action, data = data})
  end
end

function requestPage(categoryId, page)
  sendAction("get_page", { category = categoryId, page = page })
end

function init()
  -- pushFront: signalcall stops at the first handler that returns a value
  connect(g_game, {
    onGameStart = check,
    onGameEnd = hide
  }, true)

  ProtocolGame.registerExtendedJSONOpcode(SHOP_EXTENTED_OPCODE, onExtendedJSONOpcode)

  if g_game.isOnline() then
    check()
  end
  createShop()
  createTransferWindow()
end

function terminate()
  disconnect(g_game, {
    onGameStart = check,
    onGameEnd = hide
  })

  ProtocolGame.unregisterExtendedJSONOpcode(SHOP_EXTENTED_OPCODE, onExtendedJSONOpcode)

  if shopButton then
    shopButton:destroy()
    shopButton = nil
  end
  if lookPreview then lookPreview:destroy() end
  lookPreview = nil
  if searchEvent then removeEvent(searchEvent) end
  searchEvent = nil
  if shop then
    shop:destroy()
    shop = nil
  end
  ui = {}
  selectedCard = nil
  if msgWindow then
    msgWindow:destroy()
  end
  if giftWindow then
    giftWindow:destroy()
    giftWindow = nil
  end
  destroyPay()
end

function check()
  otcv8shop = false
  sendAction("init")
end

function hide()
  hidePay()
  if not shop then
    return
  end
  shop:hide()
end

function show()
  if not shop or not shopButton then
    return
  end
  if lookPreview then lookPreview:refresh() end -- the character may have changed its outfit
  shop:show()
  shop:raise()
  shop:focus()
end

function softHide()
  if not transferWindow then return end

  transferWindow:hide()
  shop:show()
end

function showTransfer()
  if not shop or not transferWindow then return end

  hide()
  transferWindow:show()
  transferWindow:raise()
  transferWindow:focus()
end

function hideTransfer()
  if not shop or not transferWindow then return end

  transferWindow:hide()
  show()
end

function toggle()
  if not shop then
    return
  end
  if shop:isVisible() then
    return hide()
  end
  wantHome = true -- opened: the home page once the list comes (an openCategory asked for wins)
  show()
  check()
end

-- the shared look preview (game_lookpreview): none on the small mobile layout, where the column folds away
local function lookCore()
  local lp = modules.game_lookpreview
  return lp and lp.LookPreviewCore or nil
end

local function createPreview()
  local lp = modules.game_lookpreview
  local mobile = g_app and type(g_app.isMobile) == 'function' and g_app.isMobile()
  if mobile or not lp or type(lp.create) ~= 'function' then
    ui.lookPreview:setHeight(0)
    ui.lookPreview:setVisible(false)
    return
  end
  lookPreview = lp.create(ui.lookPreview)
  -- the store's preview is compact: the figure and the turn buttons only. The other controls (slow turn, walk, simple
  -- figure, compare) stay in the Outfit window and keep their saved settings; they are clipped away here (the figure gets
  -- the room: 144 px of stage in the 190 px column instead of 76)
  pcall(function()
    local controls = lookPreview and lookPreview.widget and lookPreview.widget.controls
    if not controls then return end
    controls:setHeight(28)
    controls:setClipping(true)
    for _, id in ipairs({ 'autoTurn', 'walk', 'simple', 'compare' }) do
      if controls[id] then controls[id]:setVisible(false) end
    end
  end)
end

-- the preview column opens (the preview's own height) for an offer that has a look, and folds away for the others
local function setLookRoom(open)
  if not ui.lookPreview then return end
  open = open and lookPreview ~= nil
  ui.lookPreview:setHeight(open and LOOK_HEIGHT or 0)
  ui.lookPreview:setVisible(open)
end

-- The cosmetic itself as the icon (shopicon.lua; the server's `look` of the offer or category): a creature with the
-- outline on it, a print, a plate, the effect's own picture or sprites, a colour sample. Nothing here is needed to
-- sell: an engine call that is missing leaves the stand-in item or creature in place.
local function applyArt(widget, data, size)
  if not widget or not widget.art or type(data) ~= 'table' or type(data['look']) ~= 'table' then return end
  local ok, err = pcall(function()
    local lp = modules.game_lookpreview
    local plan = ShopIcon.plan(data, function(play)
      local LP = lp and lp.LookPreviewCore
      return LP and LP.mainEffect(play) or nil
    end)
    if plan.mode == 'native' then return end
    local art = widget.art
    local function show()
      if widget.item then widget.item:setVisible(false) end
      if widget.creature then widget.creature:setVisible(false) end
      art:setVisible(true)
    end
    local function exists(path) return g_resources.fileExists(path .. '.png') end
    if plan.mode == 'creature' then
      local fx = modules.game_cosmeticfx
      local c = widget.creature and widget.creature:getCreature() or nil
      if c and fx and type(fx.applyOutline) == 'function' and fx.applyOutline(c, plan.outline.art, plan.outline.pulse) == true then
        return
      end
      -- an engine without the outline pass (base patch 0038): the glow picture of the cosmetic instead
      if exists(plan.glow) then
        art:setImageSource(plan.glow)
        show()
      end
    elseif plan.mode == 'image' then
      if exists(plan.image) then
        art:setImageSource(plan.image)
        show()
      end
    elseif plan.mode == 'effect' then
      if lp and type(lp.effectIcon) == 'function' and lp.effectIcon(art, plan.spec, size, ShopIcon.FX) then show() end
    elseif plan.mode == 'swatch' then
      art:setBackgroundColor(plan.accent and plan.color or '#1c1a18')
      art:setText(ShopIcon.sampleText(plan))
      if not plan.accent then art:setColor(plan.color) end
      show()
    end
  end)
  if not ok then g_logger.warning('[shop] icon: ' .. tostring(err)) end
end

-- the widgets of the window that the code reaches by id (a nested widget is no field of the window)
local IDS = { 'infoPanel', 'points', 'buy', 'searchText', 'rail', 'detailPanel', 'lookPreview', 'dTitle', 'dTags', 'dCoin',
  'dPrice', 'dOld', 'dDesc', 'dNote', 'tryButton', 'giftButton', 'buyButton', 'mainPanel', 'adPanel', 'ad', 'pathLabel',
  'pathCount', 'chips', 'offers', 'offersScrollBar', 'home', 'homeScrollBar', 'emptyLabel', 'pageControls', 'pageLabel',
  'prevPage', 'nextPage' }

function createShop()
  if shop then return end
  shop = g_ui.displayUI('shop')
  pcall(function() modules.game_howitworks.attach(shop, 'shop') end) -- game_howitworks: the ? button
  shop:hide()
  for _, id in ipairs(IDS) do ui[id] = shop:recursiveGetChildById(id) end
  createPreview()

  ui.pageControls:show()
  ui.nextPage.onClick = function()
    local id = selectedCategory
    if not id or searching or browsingHistory or view ~= 'category' then return end
    requestPage(id, (currentCategoryPage[id] or 1) + 1)
  end
  ui.prevPage.onClick = function()
    local id = selectedCategory
    if not id or searching or browsingHistory or view ~= 'category' then return end
    requestPage(id, math.max(1, (currentCategoryPage[id] or 1) - 1))
  end
  shopButton = modules.client_topmenu.addRightGameToggleButton(
    'shopButton', tr('Shop'),
    '/images/topbuttons/shop', toggle, false, 8
  )
  showDetails(nil)
end

function createTransferWindow()
  if transferWindow then return end
  transferWindow = g_ui.displayUI('transfer')
  transferWindow:hide()
end

function transferCoins()
  if not transferWindow then return end
  local amount = transferWindow.coinsAmount:getValue()
  local recipient = transferWindow.recipient:getText()

  sendAction("gift_coins", {
    name = recipient,
    amount = amount
  })

  transferWindow.recipient:setText('')
  transferWindow.coinsAmount:setValue(0)
end

-- is category `catId` one the home page shows
local function onHome(catId)
  for _, s in ipairs(HOME) do
    if s.index == catId then return true end
  end
  return false
end

function onExtendedJSONOpcode(protocol, code, json_data)
  createShop()
  createTransferWindow()

  local action = json_data['action']
  local data = json_data['data']
  local status = json_data['status']
  if not action or not data then
    return false
  end
  -- donations (pay.lua)
  if type(action) == 'string' and action:sub(1, 4) == 'pay_' then
    onPayAction(action, data)
    if status then
      processStatus(status)
    end
    return
  end

  otcv8shop = true
  if action == 'category_groups' then
    -- the parents of the tree, sent right before "categories"
    GROUPS = type(data) == 'table' and data or {}
  elseif action == 'categories' then
    for i, cat in ipairs(data) do
      cat.offers = {}
      currentCategoryPage[i] = 1
    end
    processCategories(data)
  elseif action == 'history' then
    processHistory(data)
  elseif action == "category_page" then
    local catId = tonumber(data.category)
    local page  = tonumber(data.page) or 1
    local cat = catId and CATEGORIES[catId]
    if not cat or type(data.offers) ~= 'table' then return end
    local total = cat.pages or 1

    currentCategoryPage[catId] = page
    cat.offers[page] = {}
    for i, offerData in ipairs(data.offers) do
      cat.offers[page][i] = offerData
    end

    if searching then
      -- a page after a purchase from the search results: the results again, so "Owned" shows there
      sendAction("search", { text = searching })
    elseif view == 'home' then
      if page == 1 and onHome(catId) then renderHome() end
    elseif view == 'category' and not browsingHistory and catId == selectedCategory then
      renderCategoryPage(catId, page, data.offers)
    end
  elseif action == 'search_results' then
    processSearch(data)
  elseif action == 'message' then
    processMessage(data)
  end

  if status then
    processStatus(status)
  end
end

-- ---------------------------------------------------------------- clearing
local function destroyChildrenOf(widget)
  if not widget then return end
  while widget:getChildCount() > 0 do
    widget:destroyChildren(widget:getLastChild())
  end
end

function clearOffers()
  selectedCard = nil
  if lookPreview then lookPreview:setOption(nil) end
  destroyChildrenOf(ui.offers)
  showDetails(nil)
end

local function clearHome()
  selectedCard = nil
  if lookPreview then lookPreview:setOption(nil) end
  destroyChildrenOf(ui.home)
  showDetails(nil)
end

local function clearChips()
  destroyChildrenOf(ui.chips)
  ui.chips:setHeight(0)
end

function clearCategories()
  CATEGORIES = {}
  TREE = {}
  RAIL = {}
  HOME = {}
  clearOffers()
  clearHome()
  clearChips()
  destroyChildrenOf(ui.rail)
end

function clearHistory()
  HISTORY = {}
  if browsingHistory then
    clearOffers()
  end
end

-- which page the window shows: the cards (a category, the search, the history) or the home page
local function showPage(which)
  local home = which == 'home'
  ui.home:setVisible(home)
  ui.homeScrollBar:setVisible(home)
  ui.offers:setVisible(not home)
  ui.offersScrollBar:setVisible(not home)
  ui.emptyLabel:setVisible(false)
end

-- the empty page says why
local function showEmpty(text)
  ui.emptyLabel:setText(text or '')
  ui.emptyLabel:setVisible(text ~= nil)
end

-- ---------------------------------------------------------------- the list from the server
-- the list from the server: the rail again, the shown category kept by name (its index may have moved: a starter
-- pack bought, a category emptied), else the home page (the window was opened) or the first category
function processCategories(data)
  local pend = pendingCategory
  local keepName = pend
  if not keepName and view == 'category' and selectedCategory and CATEGORIES[selectedCategory] then
    keepName = CATEGORIES[selectedCategory].name
  end
  pendingCategory = nil
  local opened = wantHome
  wantHome = false
  if opened and not pend then
    -- opened again: not the old search or history
    searching = nil
    browsingHistory = false
    if ui.searchText and ui.searchText:getText() ~= '' then ui.searchText:setText('') end
  end
  clearCategories()
  CATEGORIES = data
  TREE = ShopTree.build(CATEGORIES, GROUPS)
  HOME = ShopView.homeSections(TREE)
  RAIL = ShopView.rail(TREE, #HOME > 0)
  renderRail()
  local leaf = pend and ShopTree.find(TREE, pend)
  if leaf then
    selectCategory(leaf.index)
  elseif searching then
    sendAction("search", { text = searching }) -- the results again (a purchase changed the list)
  elseif browsingHistory then
    showHistory(true)
  elseif (opened or view == 'home') and #HOME > 0 then
    showHome()
  else
    leaf = keepName and ShopTree.find(TREE, keepName) or ShopTree.firstLeaf(TREE)
    if leaf then
      selectCategory(leaf.index)
    elseif #HOME > 0 then
      showHome()
    end
  end
end

-- ---------------------------------------------------------------- the rail
-- a rail entry: style 'ShopRail' + Item, Creature or Image after the icon the server sends; the name (a run-time tr()
-- key, client_chaos_locale/pt_br.lua) and the subtle count
local function addRailEntry(entry)
  local data = entry.data or {}
  local w
  if entry.kind == 'home' then
    w = g_ui.createWidget('ShopRailImage', ui.rail)
    w.image:setImageSource('/images/chaos/small/topbutton_market')
  elseif data["type"] == "item" then
    w = g_ui.createWidget('ShopRailItem', ui.rail)
    w.item:setItemId(data["item"])
    w.item:setItemCount(data["count"])
    w.item:setShowCount(false)
    applyArt(w, data, 26)
  elseif data["type"] == "outfit" then
    w = g_ui.createWidget('ShopRailCreature', ui.rail)
    w.creature:setOutfit(data["outfit"])
    if data["outfit"] and data["outfit"]["rotating"] then
      w.creature:setAutoRotating(true)
    end
    applyArt(w, data, 26)
  elseif data["type"] == "image" then
    w = g_ui.createWidget('ShopRailImage', ui.rail)
    if data["image"] and data["image"]:sub(1, 4):lower() == "http" then
      HTTP.downloadImage(data['image'], function(path, err)
        if err then g_logger.warning("HTTP error: " .. err .. " - " .. data["image"]) return end
        if w.image then w.image:setImageSource(path) end
      end)
    else
      w.image:setImageSource(data["image"])
    end
  else
    g_logger.error("Invalid shop category type: " .. tostring(data["type"]))
    return nil
  end
  w.railKey = entry.key
  local label = entry.kind == 'home' and tr('Home') or tr(entry.name)
  w.name:setText(label)
  w:setTooltip(label)
  if entry.size then w.count:setText(tostring(entry.size)) end
  -- the weekly rotation ("This week"): the timer replaces the count (refreshed every 30 s while the store is open)
  if entry.endsIn then
    w.rotationEndsAt = g_clock.seconds() + entry.endsIn
    w:setTooltip(label .. '\n' .. tr('A new choice of offers every Monday at 06:00 server time.'))
  end
  -- on press (a row is a phantom panel: a click lands on its icon or label, the press reaches the row)
  w.onMousePress = function(_, _, button)
    if button == MouseLeftButton then onRailClick(entry.key) end
    return true
  end
  return w
end

function renderRail()
  if not ui.rail then return end
  destroyChildrenOf(ui.rail)
  for _, entry in ipairs(RAIL) do addRailEntry(entry) end
  markRail()
  updateRotationLabels()
end

-- the open entry: checked, its name gold, the bar on its edge
function markRail()
  if not ui.rail then return end
  for _, w in ipairs(ui.rail:getChildren()) do
    local on = w.railKey ~= nil and w.railKey == railKey
    w:setChecked(on)
    if w.bar then w.bar:setVisible(on) end
    if w.name then w.name:setColor(on and '#f6cf72' or '#d6c9ae') end
  end
end

function onRailClick(key)
  if key == ShopView.HOME then
    if view == 'home' and not searching and not browsingHistory then return end
    return showHome()
  end
  local entry = ShopView.entry(RAIL, key)
  local index = ShopView.indexFor(TREE, entry, selectedCategory)
  if not index then return end
  if view == 'category' and index == selectedCategory and not searching and not browsingHistory then return end
  selectCategory(index)
end

-- ---------------------------------------------------------------- the path and the pager
-- the path over the offers: "Cosmetics > Wings", the search, the history; the subtle count beside it
function updatePath(text, count)
  if not ui.pathLabel then return end
  ui.pathLabel:setText(text or '')
  ui.pathCount:setText(count or '')
end

local function updatePager(page, pages)
  local text = ShopView.pageText(page, pages)
  ui.pageControls:setVisible(text ~= '')
  ui.pageLabel:setText(text)
  ui.prevPage:setEnabled(page > 1)
  ui.nextPage:setEnabled(page < (pages or 1))
end

local function categoryPath(index)
  local parts = {}
  for _, p in ipairs(index and ShopTree.path(TREE, index) or {}) do
    parts[#parts + 1] = tr(p)
  end
  return table.concat(parts, ' > ')
end

-- the count beside the path of a category: how many offers, or the weekly rotation's timer
local function updateCategoryCount(index)
  local cat = CATEGORIES[index]
  pathEndsAt = nil
  if not cat then return updatePath(categoryPath(index), '') end
  if tonumber(cat.endsIn) then
    pathEndsAt = g_clock.seconds() + tonumber(cat.endsIn)
    return updatePath(categoryPath(index), tr('Ends in %s', RotationView.left(cat.endsIn)))
  end
  updatePath(categoryPath(index), cat.size and tr('%d offers', tonumber(cat.size)) or '')
end

-- ---------------------------------------------------------------- the home page
function showHome()
  if #HOME == 0 then return end
  view = 'home'
  browsingHistory = false
  selectedCategory = nil
  pathEndsAt = nil
  if searching then
    searching = nil
    if ui.searchText and ui.searchText:getText() ~= '' then ui.searchText:setText('') end
  end
  railKey = ShopView.HOME
  markRail()
  clearChips()
  clearOffers()
  updatePath('', '')
  updatePager(1, 1)
  showPage('home')
  renderHome()
  for _, s in ipairs(HOME) do requestPage(s.index, 1) end
end

-- the sections from the pages that came (the first page of each category; a page not here yet leaves its strip short)
function renderHome()
  if not ui.home or view ~= 'home' then return end
  clearHome()
  local width = ui.home:getWidth() - 15 - 12 -- the scrollbar room and the section's padding
  local cols = width > 0 and ShopView.columns(width, CARD_W, CARD_GAP) or 3
  for _, s in ipairs(HOME) do
    local cat = CATEGORIES[s.index]
    local pageOffers = cat and cat.offers and cat.offers[1] or {}
    local pick, more = ShopView.homePick(pageOffers, ShopView.homeLimit(s.key, cols), s.size)
    local section = g_ui.createWidget('ShopSection', ui.home)
    section.title:setText(tr(s.name))
    if s.endsIn then
      -- the weekly strip, highlighted, with the time left
      section:setImageSource('/images/chaos/panel_highlight')
      section.rotationEndsAt = g_clock.seconds() + s.endsIn
      section.note:setText(tr('Ends in %s', RotationView.left(s.endsIn)))
    end
    if more > 0 or (s.size and s.size > #pick) then
      section.seeAll:setText(tr('See all (%d)', tonumber(s.size) or #pick + more))
      section.seeAll:setVisible(true)
      section.seeAll.onClick = function() selectCategory(s.index) end
    end
    for i, offerData in ipairs(pick) do
      addOffer(s.index, offerData, { category = s.index, page = 1, offer = i }, section.grid)
    end
    local gridHeight = ShopView.gridHeight(#pick, cols, CARD_H, CARD_GAP)
    section.grid:setHeight(gridHeight)
    section:setHeight(34 + gridHeight)
  end
  updateRotationLabels()
end

-- ---------------------------------------------------------------- a category
-- show category `index`: its first page, its path over the offers, the chips of its group; leaves a search, the history
-- or the home page
function selectCategory(index)
  if not CATEGORIES[index] then return end
  selectedCategory = index
  view = 'category'
  browsingHistory = false
  if searching then
    searching = nil
    if ui.searchText and ui.searchText:getText() ~= '' then ui.searchText:setText('') end
  end
  railKey = ShopView.railKeyOf(TREE, index)
  markRail()
  currentCategoryPage[index] = 1
  showPage('cards')
  clearOffers()
  renderChips()
  updateCategoryCount(index)
  updatePager(1, CATEGORIES[index].pages or 1)
  sendAction("get_page", { category = index, page = 1 })
end

-- the offers of a page of the shown category as cards
function renderCategoryPage(catId, page, offers)
  clearOffers()
  showPage('cards')
  for row, offerData in ipairs(offers) do
    addOffer(catId, offerData, { category = catId, page = page, offer = row }, ui.offers)
  end
  updatePager(page, CATEGORIES[catId] and CATEGORIES[catId].pages or 1)
  showEmpty(#offers == 0 and tr('Nothing here yet.') or nil)
end

-- the chips under the path: the subcategories of the open group (none for a top category)
function renderChips()
  clearChips()
  local group = railKey and railKey:match('^g:(.+)$')
  if not group then return end
  local chips = ShopView.chips(TREE, group, CHIP_CHARS)
  if #chips < 2 then return end
  for _, c in ipairs(chips) do
    local chip = g_ui.createWidget('ShopChip', ui.chips)
    chip:setText(c.text)
    chip:setTooltip(tr(c.name))
    chip:setChecked(c.index == selectedCategory)
    chip.onClick = function() if c.index ~= selectedCategory or view ~= 'category' then selectCategory(c.index) end end
  end
  setChipsHeight(#chips)
end

function setChipsHeight(count)
  local width = ui.chips:getWidth()
  local cols = width > 0 and ShopView.columns(width, CHIP_W, CHIP_GAP) or 5
  ui.chips:setHeight(ShopView.gridHeight(count, cols, CHIP_H, CHIP_GAP))
end

-- for other modules: open the store at a category (by its name, as the server sends it)
function openCategory(name)
  if not shop then return end
  local opening = not shop:isVisible()
  if opening then toggle() end
  local leaf = ShopTree.find(TREE, name)
  if opening then
    -- the list is on its way (toggle asked for it): it keeps this category, not the home page
    pendingCategory = name
    wantHome = false
  end
  if leaf then selectCategory(leaf.index) end
end

-- ---------------------------------------------------------------- search (the server looks, shop.lua Shop.search)
function onSearchChange()
  if searchEvent then removeEvent(searchEvent) searchEvent = nil end
  if not shop or not ui.searchText then return end
  local text = ui.searchText:getText():gsub('^%s+', ''):gsub('%s+$', '')
  if #text < 2 then
    if searching then
      searching = nil
      searchOffers, searchGroup = nil, nil
      if selectedCategory then selectCategory(selectedCategory) else showHome() end
    end
    return
  end
  searchEvent = scheduleEvent(function()
    searchEvent = nil
    searching = text
    browsingHistory = false
    sendAction("search", { text = text })
  end, 400)
end

-- the cards of the results of the chip that is on (all, or one group)
local function renderSearchCards()
  clearOffers()
  showPage('cards')
  local shown = ShopView.filterResults(searchOffers, searchGroup)
  for _, offerData in ipairs(shown) do
    local at = type(offerData.at) == 'table' and offerData.at or nil
    if at then
      addOffer(tonumber(at.category) or 0, offerData,
        { category = tonumber(at.category), page = tonumber(at.page), offer = tonumber(at.offer) }, ui.offers)
    end
  end
  showEmpty(#shown == 0 and tr('Nothing found. Try another word.') or nil)
end

-- the chips over the results: All and one per group (when the results come from more than one)
local function renderResultChips()
  clearChips()
  local groups = ShopView.resultGroups(searchOffers)
  for _, g in ipairs(groups) do
    local chip = g_ui.createWidget('ShopChip', ui.chips)
    local label = g.name == nil and tr('All') or tr(g.name == '' and 'Other' or g.name)
    chip:setText(ShopView.chipText(label, g.count, CHIP_CHARS))
    chip:setTooltip(label)
    chip:setChecked(g.name == searchGroup)
    chip.onClick = function()
      searchGroup = g.name
      renderResultChips()
      renderSearchCards()
    end
  end
  if #groups > 0 then setChipsHeight(#groups) end
end

function processSearch(data)
  if not shop or not searching or type(data) ~= 'table' or data.text ~= searching then return end
  view = 'search'
  railKey = nil
  markRail()
  pathEndsAt = nil
  local offers = type(data.offers) == 'table' and data.offers or {}
  for _, offerData in ipairs(offers) do
    local where = {}
    for _, p in ipairs(type(offerData.path) == 'table' and offerData.path or {}) do where[#where + 1] = tr(p) end
    if #where > 0 and type(offerData.at) == 'table' then
      offerData.description = table.concat(where, ' > ') .. ': ' .. tostring(offerData.description or '')
    end
  end
  searchOffers = offers
  -- a chip of the last results that is no longer there: all
  local keep = false
  for _, g in ipairs(ShopView.resultGroups(offers)) do
    if g.name == searchGroup then keep = true end
  end
  if not keep then searchGroup = nil end
  renderResultChips()
  renderSearchCards()
  updatePager(1, 1)
  updatePath(#offers > 0 and tr('Search "%s": %d offers', searching, #offers) or tr('Search "%s": nothing found', searching), '')
end

function processHistory(data)
  if table.equal(HISTORY,data) then
    return
  end
  HISTORY = data
  if browsingHistory then
    showHistory(true)
  end
end

function processMessage(data)
  if msgWindow then
    msgWindow:destroy()
  end

  local title = tr(data["title"])
  local msg = data["msg"]
  msgWindow = displayInfoBox(title, msg)
  msgWindow.onDestroy = function(widget)
    if widget == msgWindow then
      msgWindow = nil
    end
  end
  msgWindow:show()
  msgWindow:raise()
  msgWindow:focus()
end

-- the balance changed: the cards and the details pane show what the coins buy (poor / affordable)
local function refreshStates()
  local function each(container)
    if not container then return end
    for _, child in ipairs(container:getChildren()) do
      if child.offerData then applyCardState(child) end
    end
  end
  each(ui.offers)
  if ui.home then
    for _, section in ipairs(ui.home:getChildren()) do each(section.grid) end
  end
  if selectedCard and not selectedCard:isDestroyed() then showDetails(selectedCard, true) end
end

function processStatus(data)
  if table.equal(STATUS,data) then
    return
  end
  STATUS = data

  if data['ad'] then
    processAd(data['ad'])
  end
  if data['points'] then
    -- the balance is shown short (15.3k), exact in the tooltip
    ui.points:setText(formatShortNumber(tonumber(data['points']) or data['points']))
    ui.points:setTooltip(tr("Chaos Coins:") .. " " .. comma_value(data['points']))
    refreshStates()
  end
  if data['buyUrl'] and data['buyUrl']:sub(1, 4):lower() == "http" then
    ui.buy:show()
    ui.buy.onMouseRelease = function()
      scheduleEvent(function() g_platform.openUrl(data['buyUrl']) end, 50)
    end
  else
    ui.buy:hide()
  end
end

-- the Chaos Coin balance of the last status, nil before one came (game_bagpanel shows it)
function getCoins()
  return tonumber(STATUS and STATUS['points'])
end

function processAd(data)
  if table.equal(AD,data) then
    return
  end
  AD = data
  local height = ui.infoPanel:getHeight()

  if data['image'] and data['image']:sub(1, 4):lower() == "http" then
    HTTP.downloadImage(data['image'], function(path, err)
      if err then g_logger.warning("HTTP error: " .. err .. " - " .. data['image']) return end
      ui.adPanel:setHeight(height)
      ui.ad:setText("")
      ui.ad:setImageSource(path)
      ui.ad:setImageFixedRatio(true)
      ui.ad:setImageAutoResize(true)
      ui.ad:setHeight(height)
    end)
  elseif data['text'] and data['text']:len() > 0 then
      ui.adPanel:setHeight(height)
      ui.ad:setText(data['text'])
      ui.ad:setHeight(height)
  else
      ui.adPanel:setHeight(0)
  end
  if data['url'] and data['url']:sub(1, 4):lower() == "http" then
    ui.ad.onMouseRelease = function()
      scheduleEvent(function() g_platform.openUrl(data['url']) end, 50)
    end
  else
    ui.ad.onMouseRelease = nil
  end
end

-- the countdowns of the weekly rotation (its rail entry, the home strip, the path), refreshed every 30 s while the
-- store is open (rotation.lua)
local rotationEvent
function updateRotationLabels()
  if rotationEvent then removeEvent(rotationEvent) rotationEvent = nil end
  if not shop or (shop.isDestroyed and shop:isDestroyed()) or not ui.rail then return end
  local any = false
  local now = g_clock.seconds()
  for _, child in ipairs(ui.rail:getChildren()) do
    if child.rotationEndsAt then
      any = true
      child.count:setText(RotationView.left(child.rotationEndsAt - now))
    end
  end
  if ui.home then
    for _, section in ipairs(ui.home:getChildren()) do
      if section.rotationEndsAt then
        any = true
        section.note:setText(tr('Ends in %s', RotationView.left(section.rotationEndsAt - now)))
      end
    end
  end
  if pathEndsAt and view == 'category' then
    any = true
    ui.pathCount:setText(tr('Ends in %s', RotationView.left(pathEndsAt - now)))
  end
  if any then rotationEvent = scheduleEvent(updateRotationLabels, 30000) end
end

function showHistory(force)
  -- Fixed Transaction History button
  if not force then
    sendAction("history")
  end
  browsingHistory = true
  view = 'history'
  railKey = nil
  pathEndsAt = nil
  markRail()
  if searching then
    searching = nil
    if ui.searchText then ui.searchText:setText('') end
  end
  clearChips()
  clearOffers()
  showPage('cards')
  for i, transaction in ipairs(HISTORY) do
    addOffer(0, transaction, nil, ui.offers)
  end
  updatePager(1, 1)
  updatePath(tr('Transaction history'), '')
  showEmpty(#HISTORY == 0 and tr('No purchases yet.') or nil)
end

-- ---------------------------------------------------------------- the cards
local BADGE_COLORS = { owned = '#8fcf7a', sale = '#ff9a5a', new = '#ffd24a', featured = '#f6cf72', other = '#d6c9ae' }
local PRICE_COLORS = { owned = '#8c8070', poor = '#e03a1e', sale = '#f6cf72', normal = '#f6cf72' }

-- owned, poor, sale and the new / featured tags of a card from the offer and the balance (again when the balance changes)
function applyCardState(card)
  local data = card.offerData
  if not data then return end
  local st = ShopView.cardState(data, getCoins())
  card.state = st
  card.price:setColor(PRICE_COLORS[st.priceKind] or PRICE_COLORS.normal)
  card.title:setColor(st.owned and '#8c8070' or '#d6c9ae')
  if card.sel == nil then
    -- a line of the history: the date as the sub line, "Bought" as the badge
    card.badge:setText(tr('Bought'))
    card.badge:setColor('#d6c9ae')
    card.badge:setVisible(true)
  elseif st.badge then
    local text
    if st.badge == 'owned' then text = tr('Owned')
    elseif st.badge == 'sale' then text = st.badgeText or tr('Sale')
    elseif st.badge == 'new' then text = tr('New')
    elseif st.badge == 'featured' then text = tr('Featured')
    else text = ShopView.clip(ShopView.tagLabel(st.badgeText or '', function(k) return tr(k) end), 9) end
    card.badge:setText(text)
    card.badge:setColor(BADGE_COLORS[st.badge] or BADGE_COLORS.other)
    card.badge:setVisible(true)
  else
    card.badge:setVisible(false)
  end
  if card.accent then card.title:setColor(card.accent) end
end

-- an offer card in `parent`; sel = where the server has it ({category, page, offer}: what buy, gift and preview
-- send), nil for a line of the history
function addOffer(category, data, sel, parent)
  parent = parent or ui.offers
  local card
  if data["type"] == "item" then
    card = g_ui.createWidget('ShopCardItem', parent)
    card.item:setItemId(data["item"])
    card.item:setItemCount(data["count"])
    card.item:setShowCount(false)
    applyArt(card, data, 40)
  elseif data["type"] == "outfit" then
    card = g_ui.createWidget('ShopCardCreature', parent)
    card.creature:setOutfit(data["outfit"])
    if data["outfit"]["rotating"] then
      card.creature:setAutoRotating(true)
    end
    applyArt(card, data, 40)
  elseif data["type"] == "image" then
    card = g_ui.createWidget('ShopCardImage', parent)
    if data["image"] and data["image"]:sub(1, 4):lower() == "http" then
      HTTP.downloadImage(data['image'], function(path, err)
        if err then g_logger.warning("HTTP error: " .. err .. " - " .. data['image']) return end
        if not card.image then return end
        card.image:setImageSource(path)
      end)
    elseif data["image"] and data["image"]:len() > 1 then
      card.image:setImageSource(data["image"])
    end
  else
    g_logger.error("Invalid shop offer type: " .. tostring(data["type"]))
    return
  end
  card:setId("offer_" .. category .. "_" .. (parent:getChildCount()))
  card.sel = sel
  card.offerData = data
  card.offerId = data["id"]
  -- a look offer (outfit, addons, mount, wings, aura, shader, pet) in the look preview: on hover, and kept once picked
  local LP = lookCore()
  card.lookOption = LP and LP.fromShopOffer(data) or nil
  card.onHoverChange = function(_, hovered)
    if not lookPreview or not card.lookOption then return end
    if hovered then lookPreview:setHover(card.lookOption) else lookPreview:clearHover() end
  end
  -- the name (two lines; the whole of it in the tooltip with the exact price)
  local title = tostring(data["title"] or '')
  card.title:setText(ShopView.clip(title, NAME_CHARS))
  card.title:setMarginTop(#title <= ONE_LINE_CHARS and 13 or 7) -- a one line name sits lower, between the icon's top and the price
  local cost = tonumber(data["cost"])
  card.price:setText(cost and formatShortNumber(cost) or tostring(data["cost"]))
  local oldCost = tonumber(data["oldCost"])
  if oldCost and cost and oldCost > cost then
    card.oldPrice:setText(formatShortNumber(oldCost))
    card.oldPrice:setVisible(true)
  end
  if cost then
    card:setTooltip(tr('%s (%s coins)', title, comma_value(cost)))
  else
    card:setTooltip(title)
  end
  if sel then
    card.sub:setText(ShopView.subLine(data))
  else
    card.sub:setText(ShopView.historyDate(data["description"]) or '')
  end
  -- a chat colour tints the name, a loot label accent sits behind it
  local preview = type(data["preview"]) == "table" and data["preview"] or nil
  card.accent = nil
  if preview and sel then
    if type(preview.color) == "string" and preview.color:match("^#%x%x%x%x%x%x$") then
      card.accent = preview.color
    end
    if type(preview.accent) == "string" and preview.accent:match("^#%x%x%x%x%x%x%x?%x?$") then
      card.title:setBackgroundColor(preview.accent)
    end
  end
  applyCardState(card)
  -- a click picks the card (its details open on the right); a double click asks to buy it
  card.onMousePress = function(_, _, button)
    if button == MouseLeftButton then selectCard(card) end
    return true
  end
  card.onDoubleClick = function()
    selectCard(card)
    if card.sel then buyOffer(card) end
    return true
  end
  return card
end

-- ---------------------------------------------------------------- the details pane
local function stillAlive(widget)
  return widget ~= nil and not widget:isDestroyed()
end

function selectCard(card)
  if selectedCard and stillAlive(selectedCard) then selectedCard:setChecked(false) end
  selectedCard = card
  if card then card:setChecked(true) end
  showDetails(card)
end

-- game_nameplate can draw a tried frame on the own plate (O318)
function plateTryable()
  local np = modules.game_nameplate
  return np ~= nil and type(np.previewFrame) == 'function'
end

-- the details of a card: its look in the preview column (look offers), the name, tags, price, text, the note (owned,
-- coins short) and the Buy / Gift / Try on buttons; nothing picked: a hint. `keepTry` leaves the Try on countdown alone.
function showDetails(card, keepTry)
  if not ui.dTitle then return end
  if not card or not stillAlive(card) then
    setLookRoom(false)
    if lookPreview then lookPreview:setOption(nil) end
    ui.dTitle:setText('')
    ui.dTags:setText('')
    ui.dCoin:setVisible(false)
    ui.dPrice:setText('')
    ui.dOld:setVisible(false)
    ui.dDesc:setText(tr('Pick an offer to see its details.'))
    ui.dDesc:setTooltip('')
    ui.dNote:setText('')
    ui.buyButton:setVisible(false)
    ui.giftButton:setVisible(false)
    ui.tryButton:setVisible(false)
    return
  end
  local data = card.offerData
  local tryPlan = card.sel and TryOn.plan(data, card.lookOption, lookPreview ~= nil, plateTryable()) or nil
  local plan = ShopView.detailPlan(data, getCoins(), card.sel, card.lookOption ~= nil and lookPreview ~= nil, tryPlan)
  local st = plan.state
  -- the look
  setLookRoom(plan.hasLook)
  if lookPreview then lookPreview:setOption(card.lookOption) end
  ui.dTitle:setText(tostring(data["title"] or ''))
  -- the tags and the text
  local tags = {}
  for _, t in ipairs(type(data["tags"]) == "table" and data["tags"] or {}) do
    if type(t) == "string" then tags[#tags + 1] = ShopView.tagLabel(t, function(k) return tr(k) end) end
  end
  ui.dTags:setText(table.concat(tags, '  '))
  ui.dDesc:setText(tostring(data["description"] or ''))
  ui.dDesc:setTooltip(tostring(data["description"] or ''))
  -- the price with its coin, the old price struck through
  local cost = tonumber(data["cost"])
  ui.dCoin:setVisible(cost ~= nil)
  ui.dPrice:setText(cost and formatShortNumber(cost) or tostring(data["cost"] or ''))
  ui.dPrice:setTooltip(cost and comma_value(cost) or '')
  ui.dPrice:setColor(PRICE_COLORS[st.priceKind] or PRICE_COLORS.normal)
  local oldCost = tonumber(data["oldCost"])
  if oldCost and cost and oldCost > cost then
    ui.dOld:setText(formatShortNumber(oldCost))
    ui.dOld:setVisible(true)
  else
    ui.dOld:setVisible(false)
  end
  -- the note: owned, or the coins short
  if plan.note == 'owned' then
    ui.dNote:setText(tr('You already own this.'))
    ui.dNote:setColor('#8fcf7a')
  elseif plan.note == 'poor' then
    ui.dNote:setText(tr('Not enough Chaos Coins. You need %s more.', formatShortNumber(plan.missing)))
    ui.dNote:setColor('#e03a1e')
  else
    ui.dNote:setText('')
  end
  -- the buttons
  ui.buyButton:setVisible(plan.showBuy)
  ui.buyButton:setEnabled(plan.buy)
  ui.buyButton.onClick = function() buyOffer(card) end
  ui.giftButton:setVisible(plan.gift)
  ui.giftButton:setEnabled(plan.giftEnabled)
  ui.giftButton.onClick = function() giftOffer(card) end
  ui.tryButton:setVisible(plan.try)
  if plan.try then
    if not keepTry then ui.tryButton:setText(tr('TRY ON')) end
    ui.tryButton.onClick = function() tryOffer(card) end
  end
end

-- the countdown on the button while a try runs
local function tickTry(widget, untilMs, token)
  if not widget or widget.tryToken ~= token or widget:isDestroyed() then return end
  local left = TryOn.secondsLeft(untilMs, g_clock.millis())
  local text = TryOn.countdown(left)
  if selectedCard == widget and ui.tryButton then ui.tryButton:setText(text or tr('TRY ON')) end
  if text then scheduleEvent(function() tickTry(widget, untilMs, token) end, 500) end
end

-- the TRY ON button: pin the offer's look on the character for TryOn.MS, and play the cosmetic's effect on the map
function tryOffer(widget)
  local plan = TryOn.plan(widget.offerData, widget.lookOption, lookPreview ~= nil, plateTryable())
  if not plan.show then return end
  if plan.panel and lookPreview then
    lookPreview:setTry(widget.lookOption, TryOn.MS)
    widget.tryToken = (widget.tryToken or 0) + 1
    tickTry(widget, g_clock.millis() + TryOn.MS, widget.tryToken)
  end
  if plan.plate and plateTryable() and modules.game_nameplate.previewFrame(plan.plate, TryOn.MS) then
    widget.tryToken = (widget.tryToken or 0) + 1
    tickTry(widget, g_clock.millis() + TryOn.MS, widget.tryToken)
  end
  if plan.server then previewOffer(widget) end
end

function previewOffer(widget)
  local sel = widget and widget.sel
  if not sel or not sel.category or not sel.page or not sel.offer then return end
  sendAction("preview", { category = sel.category, page = sel.page, offer = sel.offer })
end

function findWidgetIndex(widget)
  local parent = widget:getParent()
  local count  = parent:getChildCount()
  for i = 1, count do
    if parent:getChildByIndex(i) == widget then
      return i
    end
  end
  return nil
end

-- what buy and gift send for an offer card (a page's or a search result's), or nil: where the server has it, and the
-- title and price shown (the server refuses when either changed)
local function offerOf(widget)
  local sel, item = widget and widget.sel, widget and widget.offerData
  if not sel or not item or not sel.category or not sel.page or not sel.offer then return nil end
  return { category = sel.category, page = sel.page, offer = sel.offer, title = item.title, cost = item.cost,
    id = widget.offerId }
end

-- Gift: a name, then a confirmation; the server checks the character and the price again
function giftOffer(widget)
  if not widget then return end
  local sel = offerOf(widget)
  if not sel then return end
  if giftWindow then giftWindow:destroy() end
  giftWindow = g_ui.displayUI('giftoffer')
  giftWindow.selected = sel
  giftWindow:getChildById('info'):setText(tr('Buy %s (%s Chaos Coins) for another character. It gets it at once, or at its next login.', sel.title, sel.cost))
  giftWindow:show()
  giftWindow:raise()
  giftWindow:focus()
  giftWindow:getChildById('recipient'):focus()
end

function hideGiftOffer()
  if giftWindow then
    giftWindow:destroy()
    giftWindow = nil
  end
end

function confirmGiftOffer()
  if not giftWindow then return end
  local sel = giftWindow.selected
  local name = giftWindow:getChildById('recipient'):getText():gsub("^%s+", ""):gsub("%s+$", "")
  hideGiftOffer()
  if not sel or name == "" then return end
  sel.gift = name
  selectedOffer = sel
  scheduleEvent(function()
    if msgWindow then msgWindow:destroy() end
    msgWindow = displayGeneralBox(tr("Gift from the shop"),
      tr('Give %s to %s for %s Chaos Coins?', sel.title, name, sel.cost), {
      { text = tr('Yes'), callback = buyConfirmed },
      { text = tr('No'),  callback = buyCanceled },
      anchor = AnchorHorizontalCenter
    }, buyConfirmed, buyCanceled)
    msgWindow:show()
    msgWindow:raise()
    msgWindow:focus()
  end, 50)
end

-- the Buy button (or a double click): a confirmation first, the server checks the price again
function buyOffer(widget)
  if not widget then return end
  local sel = offerOf(widget)
  if not sel then return end
  -- an owned offer or one the coins do not reach is not asked about (the server would refuse it)
  local st = widget.state or ShopView.cardState(widget.offerData, getCoins())
  if st.owned or not st.affordable then return end
  selectedOffer = sel

  scheduleEvent(function()
    if msgWindow then msgWindow:destroy() end
    local title = tr("Buying from shop")
    local msg   = tr('Do you want to buy %s for %s Chaos Coins?', sel.title, sel.cost)
    msgWindow = displayGeneralBox(title, msg, {
      { text = tr('Yes'), callback = buyConfirmed },
      { text = tr('No'),  callback = buyCanceled },
      anchor = AnchorHorizontalCenter
    }, buyConfirmed, buyCanceled)
    msgWindow:show()
    msgWindow:raise()
    msgWindow:focus()
  end, 50)
end

function buyConfirmed()
  msgWindow:destroy()
  msgWindow = nil
  sendAction("buy", selectedOffer)
end

function buyCanceled()
  msgWindow:destroy()
  msgWindow = nil
  selectedOffer = {}
end
