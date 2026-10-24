-- NPC trade window: the buy / sell list of an NPC shown as a window in the middle of the game view (owner 2026-10-17:
-- "NPCs que vendem devem mostrar o inventario numa janela, nao num widget").
-- The base module game_npctrade builds the trade as a mini window (NpcWindow, 175 px wide) and docks it in a side
-- panel; only next to the base dialog window (which game_npctalk replaces by the speech bubble) it floats. This module
-- wraps game_npctrade.show: after the base put the window in a panel it lifts it to the game view's root panel (the
-- place the base dialog uses too), makes it 420 x 520 (smaller on a small view), and centres it. The base logic (items,
-- tabs, price, quantity, the buttons) is untouched; closing the window ends the conversation as before.
-- Without game_npctrade nothing happens. Geometry: tradewindowlogic.lua.
--
-- Currency (owner beta 2026-10-24, "broken window. Where do players get azure coins?"): the 10.98 shop packet has no
-- currency, so the base window always said "Currency: Gold Coin", showed the player's gold and cut every row to
-- "ashborne armor / Price 30, 85.00 ..." (short_text 15 and 16). An NPC that trades for something else announces
-- the currency on extended opcode 113 just before the shop (server data/lib/chaos_npc_currency.lua); after the base
-- built the window this puts the currency's name and icon in the header, the player's balance of it where the gold
-- was (the base's getPlayerMoney, which the buttons, the amount and the grey rows read), and rewrites every row
-- (gold shops too) with the whole item name and "Price 30, 85.00 oz". The balance is sent again after each purchase
-- and sale. Logic and rules: tradewindowlogic.lua.

local L = TradeWindowLogic
local OPCODE = 113 -- ChaosOpcodes.npcCurrency (server chaos_constants.lua)
local originalShow, originalRefreshItems, originalHide, originalGetMoney
local state = L.newState()

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function rootPanel()
  local gi = modules.game_interface
  return gi and gi.getRootPanel and gi.getRootPanel() or g_ui.getRootWidget()
end

local function tradeWidget()
  return g_ui.getRootWidget():recursiveGetChildById('tradeWindow')
end

local function float()
  local w = tradeWidget()
  local root = rootPanel()
  if not alive(w) or not alive(root) then return end
  if not L.needsFloat(w:isVisible(), w:getParent() == root) then return end
  local g = L.geometry(root:getWidth(), root:getHeight(), 0)
  w:setParent(root, true)
  w:setDraggable(true)
  w:setSize({ width = g.w, height = g.h })
  w:setPosition({ x = root:getX() + g.x, y = root:getY() + g.y })
  w:raise()
  w:focus()
end

local function now()
  local ok, t = pcall(function() return g_clock.seconds() end)
  return ok and t or os.time()
end

local function warn(err)
  g_logger.warning('[npctradewindow] ' .. tostring(err))
end

-- the base's own widgets and functions (module globals of game_npctrade)
local function tradeModule()
  return modules.game_npctrade
end

local function refreshBalance()
  local trade = tradeModule()
  if trade and type(trade.refreshPlayerGoods) == 'function' then
    local ok, err = pcall(trade.refreshPlayerGoods)
    if not ok then warn(err) end
  end
end

-- The header, the balance and the price rules of a window that trades for `spec` (nil: gold, as the base made it).
local function applyCurrency(spec)
  local trade = tradeModule()
  if not trade or not spec then return end
  if alive(trade.currencyItem) then
    if spec.item then
      trade.currencyItem:setItemId(spec.item)
      trade.currencyItem:setItemCount(100)
      trade.currencyItem:setShowCount(false)
      trade.currencyItem:setVisible(true)
    else
      trade.currencyItem:setVisible(false)
    end
  end
  if alive(trade.itemBorder) then trade.itemBorder:setVisible(spec.item ~= nil) end
  if alive(trade.currencyLabel) then
    trade.currencyLabel:setText(spec.name)
    trade.currencyLabel:removeTooltip()
    if spec.fullName ~= spec.name then trade.currencyLabel:setTooltip(spec.fullName) end
  end
  if alive(trade.currencyMoneyLabel) then trade.currencyMoneyLabel:setText(tr('Balance:')) end
  trade.CURRENCYID = spec.item or 0 -- not gold: no "buy with backpack" fee option
  if not originalGetMoney then originalGetMoney = trade.getPlayerMoney end
  trade.getPlayerMoney = function() return state.active and state.active.amount or originalGetMoney() end
end

local function restoreGold()
  local trade = tradeModule()
  L.release(state)
  if trade and originalGetMoney and type(originalGetMoney) == 'function' then trade.getPlayerMoney = originalGetMoney end
  originalGetMoney = nil
end

local function wrappedShow(...)
  local result = originalShow(...)
  local ok, err = pcall(float)
  if not ok then warn(err) end
  local spec = L.take(state, now())
  if spec then
    ok, err = pcall(applyCurrency, spec)
    if not ok then warn(err) end
    refreshBalance()
  end
  return result
end

local function moneyText(n)
  if comma_value then return comma_value(tostring(n)) end
  return tostring(n)
end

-- every row: the whole item name, then "Price 30, 85.00 oz" (the base cut them at 15 and 16 characters)
local function rewriteRows()
  local trade = tradeModule()
  if not trade or not alive(trade.itemsPanel) then return end
  local gold = state.active == nil
  local unit = trade.WEIGHT_UNIT or 'oz'
  for i = 1, trade.itemsPanel:getChildCount() do
    local box = trade.itemsPanel:getChildByIndex(i)
    local item = box and box.item
    if item and alive(box.nameLabel) then
      local price = gold and (formatShortNumber and formatShortNumber(item.price) or tostring(item.price)) or moneyText(item.price)
      local info = L.rowInfo(tr('Price %s', price), trade.showWeight ~= false and item.weight or 0, unit)
      box.nameLabel:setText(L.rowName(item.name) .. '\n' .. info, true)
      box:setTooltip(item.name .. '\n' .. info)
    end
  end
end

local function wrappedRefreshItems(...)
  local result = originalRefreshItems(...)
  local ok, err = pcall(rewriteRows)
  if not ok then warn(err) end
  return result
end

local function wrappedHide(...)
  restoreGold()
  return originalHide(...)
end

-- opcode 113: the currency of the shop that opens next, or the balance after a purchase or a sale
local function onCurrency(protocol, opcode, buffer)
  local spec = L.parseCurrency(buffer, json.decode)
  local what = L.receive(state, spec, now())
  if what == 'update' then refreshBalance() end
end

function init()
  local trade = modules.game_npctrade
  if not trade or type(trade.show) ~= 'function' then
    g_logger.warning('[npctradewindow] game_npctrade not found: the trade stays in the side panel')
    return
  end
  originalShow = trade.show
  trade.show = wrappedShow
  if type(trade.refreshTradeItems) == 'function' then
    originalRefreshItems = trade.refreshTradeItems
    trade.refreshTradeItems = wrappedRefreshItems
  end
  if type(trade.hide) == 'function' then
    originalHide = trade.hide
    trade.hide = wrappedHide
  end
  ProtocolGame.registerExtendedOpcode(OPCODE, onCurrency)
end

function terminate()
  local trade = modules.game_npctrade
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  restoreGold()
  if trade and originalShow and trade.show == wrappedShow then trade.show = originalShow end
  if trade and originalRefreshItems and trade.refreshTradeItems == wrappedRefreshItems then
    trade.refreshTradeItems = originalRefreshItems
  end
  if trade and originalHide and trade.hide == wrappedHide then trade.hide = originalHide end
  originalShow, originalRefreshItems, originalHide = nil, nil, nil
  state = L.newState()
end
