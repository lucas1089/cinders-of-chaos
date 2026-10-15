-- game_shop: the Chaos store (server: data/scripts/chaos/shop.lua, extended opcode 218, JSON).
-- Categories and pages come from the server; prices are in Chaos Coins. The server decides every price: an offer
-- carries cost, oldCost (struck through), tags (Sale / New / Featured / Bundle), gift (can be bought for another
-- character) and owned; buying echoes title and cost back, so a price that changed is refused, never charged.
-- The Donate button opens the donation window (pay.lua: Pix / PayPal, Chaos Coins as a thank-you).
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
local HISTORY = {}
local STATUS = {}
local AD = {}
local selectedOffer = {}
local giftWindow = nil

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

function createShop()
  if shop then return end
  shop = g_ui.displayUI('shop')
  shop:hide()

  shop.prevPage     = shop:recursiveGetChildById('prevPage')
  shop.nextPage     = shop:recursiveGetChildById('nextPage')
  shop.pageControls = shop:recursiveGetChildById('pageControls')
  shop.pageControls:show()
  shop.prevPage:show()
  shop.nextPage:show()
  if shop.prevPage and shop.nextPage then
    shop.nextPage.onClick = function()
      local cat = shop.categories:getFocusedChild()
      if not cat then return end
      local id   = tonumber(cat:getId():match("category_(%d+)"))
      local next = (currentCategoryPage[id] or 1) + 1
      requestPage(id, next)
    end
    shop.prevPage.onClick = function()
      local cat = shop.categories:getFocusedChild()
      if not cat then return end
      local id   = tonumber(cat:getId():match("category_(%d+)"))
      local prev = math.max(1, (currentCategoryPage[id] or 1) - 1)
      requestPage(id, prev)
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
  if action == 'categories' then
    for i, cat in ipairs(data) do
      cat.offers = {}
      currentCategoryPage[i] = 1
    end
    processCategories(data)
    sendAction("get_page", { category = 1, page = 1 })
  elseif action == 'history' then
    processHistory(data)
  elseif action == "category_page" then
  local catId = data.category
  local page  = data.page
  local total = CATEGORIES[catId].pages or 1

  currentCategoryPage[catId] = page

  CATEGORIES[catId].offers[page] = {}
  for i, offerData in ipairs(data.offers) do
    CATEGORIES[catId].offers[page][i] = offerData
  end

  clearOffers()
  for _, offerData in ipairs(data.offers) do
    addOffer(catId, offerData)
  end

  shop.prevPage:setEnabled(page > 1)
  shop.nextPage:setEnabled(page < total)
  elseif action == 'message' then
    processMessage(data)
  end

  if status then
    processStatus(status)
  end
end

function clearOffers()
  while shop.offers:getChildCount() > 0 do
    local child = shop.offers:getLastChild()
    shop.offers:destroyChildren(child)
  end
end

function clearCategories()
  CATEGORIES = {}
  clearOffers()
  while shop.categories:getChildCount() > 0 do
    local child = shop.categories:getLastChild()
    shop.categories:destroyChildren(child)
  end
end

function clearHistory()
  HISTORY = {}
  if browsingHistory then
    clearOffers()
  end
end

function processCategories(data)
  if table.equal(CATEGORIES,data) then
    return
  end
  clearCategories()
  CATEGORIES = data
  for i, category in ipairs(data) do
    addCategory(category)
  end
  if not browsingHistory then
    local firstCategory = shop.categories:getChildByIndex(1)
    if firstCategory then
      firstCategory:focus()
    end
  end
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

function addCategory(data)
  local category
  if data["type"] == "item" then
    category = g_ui.createWidget('ShopCategoryItem', shop.categories)  
    category.item:setItemId(data["item"])
    category.item:setItemCount(data["count"])
    category.item:setShowCount(false)
  elseif data["type"] == "outfit" then
    category = g_ui.createWidget('ShopCategoryCreature', shop.categories)
    category.creature:setOutfit(data["outfit"])
    if data["outfit"]["rotating"] then
      category.creature:setAutoRotating(true)
    end
  elseif data["type"] == "image" then
    category = g_ui.createWidget('ShopCategoryImage', shop.categories)
    if data["image"] and data["image"]:sub(1, 4):lower() == "http" then
       HTTP.downloadImage(data['image'], function(path, err) 
        if err then g_logger.warning("HTTP error: " .. err .. " - " .. data["image"]) return end
        category.image:setImageSource(path)
      end)
    else
      category.image:setImageSource(data["image"])
    end
  else
    g_logger.error("Invalid shop category type: " .. tostring(data["type"]))
    return
  end
  category:setId("category_" .. shop.categories:getChildCount())
  category.name:setText(data["name"])
  -- the weekly rotation ("This week"): a countdown to the Monday change (rotation.lua)
  if tonumber(data["endsIn"]) then
    category.rotationName = data["name"]
    category.rotationEndsAt = g_clock.seconds() + tonumber(data["endsIn"])
    category:setTooltip(tr('A new choice of offers every Monday at 06:00 server time.'))
    updateRotationLabels()
  end
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
  clearOffers()
  shop.categories:focusChild(nil)
  for i, transaction in ipairs(HISTORY) do
    addOffer(0, transaction)
  end
end

function addOffer(category, data)
  local offer
  if data["type"] == "item" then
    offer = g_ui.createWidget('ShopOfferItem', shop.offers)  
    offer.item:setItemId(data["item"])
    offer.item:setItemCount(data["count"])
    offer.item:setShowCount(false)
  elseif data["type"] == "outfit" then
    offer = g_ui.createWidget('ShopOfferCreature', shop.offers)
    offer.creature:setOutfit(data["outfit"])
    if data["outfit"]["rotating"] then
      offer.creature:setAutoRotating(true)
    end
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
  if category ~= 0 then
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
  if preview and category ~= 0 then
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
  local parts = widget and widget:getId():split("_") or {}
  local category = tonumber(parts[2])
  local row = findWidgetIndex(widget)
  if not category or not row then return end
  sendAction("preview", { category = category, page = currentCategoryPage[category] or 1, offer = row })
end

function changeCategory(widget, newCategory)
  if not newCategory then
    return
  end

  if otcv8shop then
    local id = tonumber(newCategory:getId():match("category_(%d+)"))
    currentCategoryPage[id] = 1
    sendAction("get_page", { category = id, page = 1 })
    return
  end
  browsingHistory = false
  local id = tonumber(newCategory:getId():split("_")[2])
  clearOffers()
  local page = currentCategoryPage[id] or 1
  local offers = CATEGORIES[id]["offers"][page]
  if offers then
    for i, offer in ipairs(offers) do
      addOffer(id, offer)
    end
  end
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

-- the offer data behind a widget of the current page, or nil
local function offerOf(widget)
  local parts = widget:getId():split("_")
  if #parts ~= 3 then return nil end
  local category = tonumber(parts[2])
  local row = findWidgetIndex(widget)
  local catData = category and CATEGORIES[category]
  if not row or not catData or type(catData.offers) ~= "table" then return nil end
  local page = currentCategoryPage[category] or 1
  local item = type(catData.offers[page]) == "table" and catData.offers[page][row] or nil
  if not item then return nil end
  return { category = category, page = page, offer = row, title = item.title, cost = item.cost, id = widget.offerId }
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

  local parts = widget:getId():split("_")
  if #parts ~= 3 then return end
  local category = tonumber(parts[2])
  if not category then return end

  local visualRow = findWidgetIndex(widget)
  if not visualRow then
    return
  end

  local currentPage = currentCategoryPage[category] or 1
  local catData     = CATEGORIES[category]
  if not catData or type(catData.offers) ~= "table" then return end

  local pageTable = catData.offers[currentPage]
  if not pageTable or type(pageTable) ~= "table" then return end

  local item = pageTable[visualRow]
  if not item then
    return
  end

  selectedOffer = {
    category = category,
    page     = currentPage,
    offer    = visualRow,
    title    = item.title,
    cost     = item.cost,
    id       = widget.offerId
  }

  scheduleEvent(function()
    if msgWindow then msgWindow:destroy() end
    local title = tr("Buying from shop")
    local msg   = tr('Do you want to buy %s for %s Chaos Coins?', item.title, item.cost)
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