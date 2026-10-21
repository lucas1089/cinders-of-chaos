-- game_shop: the Chaos store (server: data/scripts/chaos/shop.lua, extended opcode 218, JSON).
-- Categories and pages come from the server; prices are in Chaos Coins. The server decides every price: an offer
-- carries cost, oldCost (struck through), tags (Sale / New / Featured / Bundle), gift (can be bought for another
-- character) and owned; buying echoes title and cost back, so a price that changed is refused, never charged.
-- The Donate button opens the donation window (pay.lua: Pix / PayPal, Chaos Coins as a thank-you).
-- The categories are a tree (2026-10-21, the layout of the base server's store window; shoptree.lua): top categories
-- and parents (Cosmetics, Consumables, Premium & Services) that open to their subcategories, one at a time, with the
-- number of offers; the path of the shown category sits over the offers. The search box asks the server (`search`),
-- which answers with offers that carry where they are (`at`), so buying from the results works as from a page.
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
local expanded = {} -- {[parent name] = true}: the open parent
local selectedCategory = nil -- the index of the shown category
local pendingCategory = nil -- a category to show once the list comes (openCategory)
local searching = nil -- the search text whose results are shown
local searchEvent = nil
local rendering = false -- the category list is being built: focus changes are not clicks
local HISTORY = {}
local STATUS = {}
local AD = {}
local selectedOffer = {}
local giftWindow = nil
local lookPreview = nil -- the shared look preview (game_lookpreview), nil without it or on mobile

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
    disconnect(shop.categories, { onChildFocusChange = changeCategory })
    shop:destroy()
    shop = nil
  end
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
    shop.lookPreview:setWidth(0)
    shop.adPanel:setMarginRight(0)
    return
  end
  lookPreview = lp.create(shop.lookPreview)
  connect(shop.offers, { onChildFocusChange = function(_, focused)
    if lookPreview then lookPreview:setOption(focused and focused.lookOption or nil) end
  end })
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

function createShop()
  if shop then return end
  shop = g_ui.displayUI('shop')
  shop:hide()
  createPreview()

  shop.prevPage     = shop:recursiveGetChildById('prevPage')
  shop.nextPage     = shop:recursiveGetChildById('nextPage')
  shop.pageControls = shop:recursiveGetChildById('pageControls')
  shop.pageControls:show()
  shop.prevPage:show()
  shop.nextPage:show()
  if shop.prevPage and shop.nextPage then
    shop.nextPage.onClick = function()
      local id = selectedCategory
      if not id or searching or browsingHistory then return end
      requestPage(id, (currentCategoryPage[id] or 1) + 1)
    end
    shop.prevPage.onClick = function()
      local id = selectedCategory
      if not id or searching or browsingHistory then return end
      requestPage(id, math.max(1, (currentCategoryPage[id] or 1) - 1))
    end
  end
  shopButton = modules.client_topmenu.addRightGameToggleButton(
    'shopButton', tr('Shop'),
    '/images/topbuttons/shop', toggle, false, 8
  )
  connect(shop.categories, { onChildFocusChange = changeCategory })
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
    elseif not browsingHistory and catId == selectedCategory then
      clearOffers()
      for row, offerData in ipairs(data.offers) do
        addOffer(catId, offerData, { category = catId, page = page, offer = row })
      end
      shop.prevPage:setEnabled(page > 1)
      shop.nextPage:setEnabled(page < total)
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

function clearOffers()
  if lookPreview then lookPreview:setOption(nil) end
  while shop.offers:getChildCount() > 0 do
    local child = shop.offers:getLastChild()
    shop.offers:destroyChildren(child)
  end
end

function clearCategories()
  CATEGORIES = {}
  TREE = {}
  clearOffers()
  rendering = true
  while shop.categories:getChildCount() > 0 do
    local child = shop.categories:getLastChild()
    shop.categories:destroyChildren(child)
  end
  rendering = false
end

function clearHistory()
  HISTORY = {}
  if browsingHistory then
    clearOffers()
  end
end

-- the list from the server: the tree again, the shown category kept by name (its index may have moved: a starter
-- pack bought, a category emptied), else the first one
function processCategories(data)
  local keepName = pendingCategory
  if not keepName and selectedCategory and CATEGORIES[selectedCategory] then
    keepName = CATEGORIES[selectedCategory].name
  end
  pendingCategory = nil
  clearCategories()
  CATEGORIES = data
  TREE = ShopTree.build(CATEGORIES, GROUPS)
  local leaf = keepName and ShopTree.find(TREE, keepName) or ShopTree.firstLeaf(TREE)
  selectedCategory = leaf and leaf.index or nil
  expanded = selectedCategory and ShopTree.reveal(TREE, selectedCategory) or {}
  renderCategories()
  if searching then
    sendAction("search", { text = searching }) -- the results again (a purchase changed the list)
  elseif selectedCategory and not browsingHistory then
    selectCategory(selectedCategory)
  end
end

-- the category rows: top categories, the parents (+ / -) and the subcategories of the open one
function renderCategories()
  if not shop then return end
  rendering = true
  while shop.categories:getChildCount() > 0 do
    shop.categories:destroyChildren(shop.categories:getLastChild())
  end
  local focusWidget
  for _, row in ipairs(ShopTree.rows(TREE, expanded)) do
    local node = row.node
    if node.kind == 'group' then
      local w = addCategory(node.data, 'ShopGroup', node.name, node.size)
      if w then
        w:setId('group_' .. node.name)
        w.groupName = node.name
        if w.arrow then w.arrow:setText(row.expanded and '-' or '+') end
        -- on press (a row is a phantom panel: a click lands on its icon or label, the press reaches the row)
        w.onMousePress = function(_, _, button)
          if button == MouseLeftButton then onGroupClick(node.name) end
          return true
        end
      end
    else
      local w = addCategory(node.data, row.depth > 0 and 'ShopSubCategory' or 'ShopCategory', node.name, node.size)
      if w then
        w:setId('category_' .. node.index)
        if node.index == selectedCategory then focusWidget = w end
      end
    end
  end
  if focusWidget and not browsingHistory and not searching then
    shop.categories:focusChild(focusWidget)
    shop.categories:ensureChildVisible(focusWidget)
  end
  rendering = false
  updateRotationLabels()
end

-- a click on a parent: open it (and show its first subcategory) or close it (ShopTree.toggle)
function onGroupClick(name)
  local sel
  expanded, sel = ShopTree.toggle(TREE, expanded, name, selectedCategory)
  -- built again after this click returns (the clicked row is replaced)
  addEvent(function()
    if sel then
      selectCategory(sel)
    end
    renderCategories()
  end)
end

-- show category `index`: its first page, its path over the offers; leaves a search or the history
function selectCategory(index)
  if not CATEGORIES[index] then return end
  selectedCategory = index
  browsingHistory = false
  if searching then
    searching = nil
    if shop.searchText and shop.searchText:getText() ~= '' then shop.searchText:setText('') end
  end
  currentCategoryPage[index] = 1
  updatePath()
  sendAction("get_page", { category = index, page = 1 })
end

-- the path over the offers: "Cosmetics > Wings", the search, the history
function updatePath(text)
  if not shop or not shop.pathLabel then return end
  if text then
    shop.pathLabel:setText(text)
    return
  end
  local parts = {}
  for _, p in ipairs(selectedCategory and ShopTree.path(TREE, selectedCategory) or {}) do
    parts[#parts + 1] = tr(p)
  end
  shop.pathLabel:setText(table.concat(parts, ' > '))
end

-- for other modules: open the store at a category (by its name, as the server sends it)
function openCategory(name)
  if not shop then return end
  if not shop:isVisible() then toggle() end
  local leaf = ShopTree.find(TREE, name)
  if not leaf then
    pendingCategory = name -- the list is on its way (toggle asked for it)
    return
  end
  expanded = ShopTree.reveal(TREE, leaf.index)
  selectCategory(leaf.index)
  renderCategories()
end

-- ---------------------------------------------------------------- search (the server looks, shop.lua Shop.search)
function onSearchChange()
  if searchEvent then removeEvent(searchEvent) searchEvent = nil end
  if not shop or not shop.searchText then return end
  local text = shop.searchText:getText():gsub('^%s+', ''):gsub('%s+$', '')
  if #text < 2 then
    if searching then
      searching = nil
      if selectedCategory then selectCategory(selectedCategory) end
      renderCategories()
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

function processSearch(data)
  if not shop or not searching or type(data) ~= 'table' or data.text ~= searching then return end
  clearOffers()
  shop.categories:focusChild(nil)
  local offers = type(data.offers) == 'table' and data.offers or {}
  for _, offerData in ipairs(offers) do
    local at = type(offerData.at) == 'table' and offerData.at or nil
    if at then
      local where = {}
      for _, p in ipairs(type(offerData.path) == 'table' and offerData.path or {}) do where[#where + 1] = tr(p) end
      if #where > 0 then
        offerData.description = table.concat(where, ' > ') .. ': ' .. tostring(offerData.description or '')
      end
      addOffer(tonumber(at.category) or 0, offerData,
        { category = tonumber(at.category), page = tonumber(at.page), offer = tonumber(at.offer) })
    end
  end
  shop.prevPage:setEnabled(false)
  shop.nextPage:setEnabled(false)
  updatePath(#offers > 0 and tr('Search "%s": %d offers', searching, #offers) or tr('Search "%s": nothing found', searching))
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
    shop.infoPanel.points:setText(tr("Chaos Coins:") .. " " .. formatShortNumber(tonumber(data['points']) or data['points']))
    shop.infoPanel.points:setTooltip(tr("Chaos Coins:") .. " " .. comma_value(data['points']))
  end
  if data['buyUrl'] and data['buyUrl']:sub(1, 4):lower() == "http" then
    shop.infoPanel.buy:show()
    shop.infoPanel.buy.onMouseRelease = function() 
      scheduleEvent(function() g_platform.openUrl(data['buyUrl']) end, 50)
    end
  else
    shop.infoPanel.buy:hide()
  end
end

function processAd(data)
  if table.equal(AD,data) then
    return
  end
  AD = data

  if data['image'] and data['image']:sub(1, 4):lower() == "http" then
    HTTP.downloadImage(data['image'], function(path, err) 
      if err then g_logger.warning("HTTP error: " .. err .. " - " .. data['image']) return end
      shop.adPanel:setHeight(shop.infoPanel:getHeight())
      shop.adPanel.ad:setText("")
      shop.adPanel.ad:setImageSource(path)
      shop.adPanel.ad:setImageFixedRatio(true)
      shop.adPanel.ad:setImageAutoResize(true)
      shop.adPanel.ad:setHeight(shop.infoPanel:getHeight())
    end)
  elseif data['text'] and data['text']:len() > 0 then
      shop.adPanel:setHeight(shop.infoPanel:getHeight())
      shop.adPanel.ad:setText(data['text'])
      shop.adPanel.ad:setHeight(shop.infoPanel:getHeight())
  else
      shop.adPanel:setHeight(0)
  end
  if data['url'] and data['url']:sub(1, 4):lower() == "http" then
    shop.adPanel.ad.onMouseRelease = function() 
      scheduleEvent(function() g_platform.openUrl(data['url']) end, 50)
    end
  else
    shop.adPanel.ad.onMouseRelease = nil
  end
end

-- a row of the category list: style 'ShopCategory' (a top category), 'ShopSubCategory' (indented) or 'ShopGroup' (a
-- parent, with + / -), each as Item, Creature or Image after the icon the server sends; name and count as the label
-- (category names are run-time tr() keys, client_chaos_locale/pt_br.lua)
function addCategory(data, style, name, size)
  local category
  style = style or 'ShopCategory'
  if data["type"] == "item" then
    category = g_ui.createWidget(style .. 'Item', shop.categories)
    category.item:setItemId(data["item"])
    category.item:setItemCount(data["count"])
    category.item:setShowCount(false)
    applyArt(category, data, 32)
  elseif data["type"] == "outfit" then
    category = g_ui.createWidget(style .. 'Creature', shop.categories)
    category.creature:setOutfit(data["outfit"])
    if data["outfit"]["rotating"] then
      category.creature:setAutoRotating(true)
    end
    applyArt(category, data, 32)
  elseif data["type"] == "image" then
    category = g_ui.createWidget(style .. 'Image', shop.categories)
    if data["image"] and data["image"]:sub(1, 4):lower() == "http" then
       HTTP.downloadImage(data['image'], function(path, err)
        if err then g_logger.warning("HTTP error: " .. err .. " - " .. data["image"]) return end
        if category.image then category.image:setImageSource(path) end
      end)
    else
      category.image:setImageSource(data["image"])
    end
  else
    g_logger.error("Invalid shop category type: " .. tostring(data["type"]))
    return nil
  end
  name = name or data["name"]
  category.name:setText(ShopTree.label(tr(name), size))
  -- the weekly rotation ("This week"): a countdown to the Monday change (rotation.lua)
  if style ~= 'ShopGroup' and tonumber(data["endsIn"]) then
    category.rotationName = tr(name)
    category.rotationEndsAt = g_clock.seconds() + tonumber(data["endsIn"])
    category:setTooltip(tr('A new choice of offers every Monday at 06:00 server time.'))
  end
  return category
end

-- the countdown on the rotation's category, refreshed every 30 s while the store is open
local rotationEvent
function updateRotationLabels()
  if rotationEvent then removeEvent(rotationEvent) rotationEvent = nil end
  if not shop or (shop.isDestroyed and shop:isDestroyed()) or not shop.categories then return end
  local any = false
  for _, child in ipairs(shop.categories:getChildren()) do
    if child.rotationEndsAt then
      any = true
      child.name:setText(RotationView.label(child.rotationName, child.rotationEndsAt, g_clock.seconds()))
    end
  end
  if any then rotationEvent = scheduleEvent(updateRotationLabels, 30000) end
end

function showHistory(force)
  -- Fixed Transaction History button
  if not force then
    sendAction("history")
  end
  browsingHistory = true
  if searching then
    searching = nil
    if shop.searchText then shop.searchText:setText('') end
  end
  clearOffers()
  rendering = true
  shop.categories:focusChild(nil)
  rendering = false
  for i, transaction in ipairs(HISTORY) do
    addOffer(0, transaction)
  end
  shop.prevPage:setEnabled(false)
  shop.nextPage:setEnabled(false)
  updatePath(tr('Transaction history'))
end

-- an offer row; sel = where the server has it ({category, page, offer}: what buy, gift and preview send), nil for a
-- line of the history
function addOffer(category, data, sel)
  local offer
  if data["type"] == "item" then
    offer = g_ui.createWidget('ShopOfferItem', shop.offers)  
    offer.item:setItemId(data["item"])
    offer.item:setItemCount(data["count"])
    offer.item:setShowCount(false)
    applyArt(offer, data, 48)
  elseif data["type"] == "outfit" then
    offer = g_ui.createWidget('ShopOfferCreature', shop.offers)
    offer.creature:setOutfit(data["outfit"])
    if data["outfit"]["rotating"] then
      offer.creature:setAutoRotating(true)
    end
    applyArt(offer, data, 48)
  elseif data["type"] == "image" then
    offer = g_ui.createWidget('ShopOfferImage', shop.offers)
    if data["image"] and data["image"]:sub(1, 4):lower() == "http" then
      HTTP.downloadImage(data['image'], function(path, err) 
        if err then g_logger.warning("HTTP error: " .. err .. " - " .. data['image']) return end
        if not offer.image then return end
        offer.image:setImageSource(path)
      end)
    elseif data["image"] and data["image"]:len() > 1 then
      offer.image:setImageSource(data["image"])
    end
  else
    g_logger.error("Invalid shop offer type: " .. tostring(data["type"]))
    return
  end
  local newIndex = shop.offers:getChildCount() + 1
  offer:setId("offer_" .. category .. "_" .. newIndex)
  offer.sel = sel
  offer.offerData = data
  -- a look offer (outfit, addons, mount, wings, aura, shader, pet) in the look preview: on hover, and kept once picked
  local LP = lookCore()
  offer.lookOption = LP and LP.fromShopOffer(data) or nil
  if offer.lookOption then
    offer.onHoverChange = function(_, hovered)
      if not lookPreview then return end
      if hovered then lookPreview:setHover(offer.lookOption) else lookPreview:clearHover() end
    end
  end
  -- the price in the list is short (15.3k), exact in the tooltip and in the buy confirmation
  local cost = tonumber(data["cost"])
  offer.title:setText(tr('%s (%s coins)', data["title"], (cost and formatShortNumber(cost) or tostring(data["cost"]))))
  if cost and (cost >= 1000 or cost <= -1000) then
    offer.title:setTooltip(tr('%s (%s coins)', data["title"], comma_value(cost)))
  end
  local oldCost = tonumber(data["oldCost"])
  if offer.oldPrice and oldCost and cost and oldCost > cost then
    offer.oldPrice:setText(formatShortNumber(oldCost))
    offer.oldPrice:setVisible(true)
  end
  if offer.tags and type(data["tags"]) == "table" then
    local parts = {}
    for _, t in ipairs(data["tags"]) do
      if type(t) == "string" then parts[#parts + 1] = t end
    end
    offer.tags:setText(table.concat(parts, "  "))
  end
  offer.description:setText(data["description"])  
  offer.offerId = data["id"]
  if sel then
    offer.onDoubleClick = buyOffer
    offer.buyButton.onClick = function() buyOffer(offer) end
    if data["owned"] then
      offer.buyButton:setEnabled(false)
    end
    if offer.giftButton and data["gift"] then
      offer.giftButton:setVisible(true)
      offer.giftButton.onClick = function() giftOffer(offer) end
    else
      offer.description:setMarginRight(60) -- no gift button: more room for the text
    end
  else
    offer.buyButton:hide()
  end
  -- a cosmetic's preview (server cosmetics.lua): the SHOW button plays its effects for this player only; a chat colour
  -- tints the title, a loot label accent sits behind it
  local preview = type(data["preview"]) == "table" and data["preview"] or nil
  if preview and sel then
    if preview.effect and offer.previewButton and not data["gift"] then
      offer.previewButton:setVisible(true)
      offer.previewButton.onClick = function() previewOffer(offer) end
      offer.description:setMarginRight(104)
    end
    if type(preview.color) == "string" and preview.color:match("^#%x%x%x%x%x%x$") then
      offer.title:setColor(preview.color)
    end
    if type(preview.accent) == "string" and preview.accent:match("^#%x%x%x%x%x%x%x?%x?$") then
      offer.title:setBackgroundColor(preview.accent)
    end
  end
end

function previewOffer(widget)
  local sel = widget and widget.sel
  if not sel or not sel.category or not sel.page or not sel.offer then return end
  sendAction("preview", { category = sel.category, page = sel.page, offer = sel.offer })
end

-- a click on a category row (the list's focus moved to it); the parents are no focus rows (onGroupClick)
function changeCategory(widget, newCategory)
  if rendering or not newCategory then
    return
  end
  local id = tonumber((newCategory:getId() or ''):match("^category_(%d+)$"))
  if not id then return end
  if id == selectedCategory and not browsingHistory and not searching then return end
  selectCategory(id)
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

-- what buy and gift send for an offer row (a page's or a search result's), or nil: where the server has it, and the
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

function buyOffer(widget)
  if not widget then return end
  local sel = offerOf(widget)
  if not sel then return end
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