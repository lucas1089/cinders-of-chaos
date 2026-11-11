-- luajit tradewindow_test.lua && lua5.3 tradewindow_test.lua
-- The glue of tradewindow.lua against a mocked client: a fake game_npctrade with the widgets and functions the base has
-- (show, hide, refreshTradeItems, refreshPlayerGoods, getPlayerMoney, the header widgets, the item rows) and a fake
-- opcode registry. The owner's beta screenshot (2026-10-24, the azure NPC): a gold shop keeps "Gold Coin" and the gold
-- but gets whole row names; a currency packet before the shop puts the currency's name, icon and balance in the window;
-- the balance packet after a purchase updates it; closing the window gives the gold back.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- the fake client
local function widget(text)
  local w = { text = text or '', visible = true, tooltip = nil, children = {} }
  function w:setText(t) self.text = t end
  function w:setTooltip(t) self.tooltip = t end
  function w:removeTooltip() self.tooltip = nil end
  function w:setVisible(v) self.visible = v end
  function w:isVisible() return self.visible end
  function w:isDestroyed() return false end
  function w:setItemId(id) self.itemId = id end
  function w:setItemCount(n) self.count = n end
  function w:setShowCount(v) self.showCount = v end
  function w:getChildCount() return #self.children end
  function w:getChildByIndex(i) return self.children[i] end
  return w
end

local opcodes = {}
ProtocolGame = {
  registerExtendedOpcode = function(op, fn) opcodes[op] = fn end,
  unregisterExtendedOpcode = function(op) opcodes[op] = nil end,
}
g_logger = { warning = function(m) print('WARN ' .. m) end }
NOW = 1000
g_clock = { seconds = function() return NOW end }
-- O506: a fake game_interface with one side panel (windows from the top, as the base's forceSpaceInPanel closes them from the
-- bottom), and the trade window with the calls the module makes on it
local root = { name = 'root', getWidth = function() return 1920 end, getHeight = function() return 1080 end, getX = function() return 0 end,
  getY = function() return 0 end, isDestroyed = function() return false end }
local panelWindows, closedWindows
local function resetPanel()
  panelWindows = { 'inventoryWindow', 'containerBackpack', 'containerLootBag', 'containerGoldChest' }
  closedWindows = {}
end
resetPanel()
local npcWindow = widget()
function npcWindow:getId() return 'tradeWindow' end
function npcWindow:getParent() return self.parent end
function npcWindow:setParent(p) self.parent = p end
function npcWindow:setDraggable() end
function npcWindow:setSize(sz) self.size = sz end
function npcWindow:setPosition(pos) self.position = pos end
function npcWindow:raise() self.raised = true end
function npcWindow:focus() self.focused = true end
local gi = { getRootPanel = function() return root end }
-- what the base does for a window that wants a place: closes the windows at the bottom of the panel (priority true) or
-- closes backpacks (the other call), then puts the window in the panel
local function takeRoom(w)
  while #panelWindows > 1 do
    closedWindows[#closedWindows + 1] = table.remove(panelWindows)
  end
  w.parent = 'sidePanel'
  return true
end
gi.addToPanelsWithPriority = function(w, force) gi.lastCall = 'priority'; return takeRoom(w) end
gi.addToPanels = function(w, room) gi.lastCall = 'plain'; return takeRoom(w) end
local otherWindow = widget()
function otherWindow:getId() return 'someOtherWindow' end
g_ui = { getRootWidget = function() return { recursiveGetChildById = function(_, id) return id == 'tradeWindow' and npcWindow or nil end } end }
function tr(text, ...) if select('#', ...) > 0 then return string.format(text, ...) end return text end
-- the packets: the test hands json.decode an already decoded table by name
PACKETS = {}
json = { decode = function(text) return PACKETS[text] end }

local trade = {
  WEIGHT_UNIT = 'oz', showWeight = true, CURRENCYID = 3031,
  currencyItem = widget(), itemBorder = widget(), currencyLabel = widget('Gold Coin'),
  currencyMoneyLabel = widget('Gold:'), moneyLabel = widget(), itemsPanel = widget(),
  goldBalance = 30400000,
}
function trade.getPlayerMoney() return trade.goldBalance end
function trade.show()
  -- the base's show(): a place in a side panel first, then the window is shown
  local placed = modules.game_interface.addToPanelsWithPriority(npcWindow, true)
  if placed then npcWindow.visible = true end
  return placed
end
function trade.hide() end
local ITEMS = {
  { name = 'blightwoven armor', price = 30, weight = 110 },
  { name = 'exowing bow', price = 50, weight = 36.5 },
}
function trade.refreshTradeItems()
  trade.itemsPanel.children = {}
  for _, item in ipairs(ITEMS) do
    local box = widget()
    box.item = item
    box.nameLabel = widget('cut...\nPrice 30, 85.00 ...')
    trade.itemsPanel.children[#trade.itemsPanel.children + 1] = box
  end
end
function trade.refreshPlayerGoods()
  trade.moneyLabel.text = tostring(trade.getPlayerMoney())
end
modules = { game_npctrade = trade, game_interface = gi }

dofile(dir .. 'tradewindowlogic.lua')
dofile(dir .. 'tradewindow.lua')
init()

-- ---------------------------------------------------------------- wiring
eq(type(opcodes[113]), 'function', 'opcode 113 registered')

-- a gold shop: the header and the gold stay, the rows get whole names and one readable second line
trade.refreshTradeItems()
eq(trade.itemsPanel.children[1].nameLabel.text, 'blightwoven armor\nPrice 30, 110.00 oz', 'gold shop: whole row')
eq(trade.itemsPanel.children[2].nameLabel.text, 'exowing bow\nPrice 50, 36.50 oz', 'gold shop: second row')
eq(trade.itemsPanel.children[1].tooltip, 'blightwoven armor\nPrice 30, 110.00 oz', 'the tooltip has the same text')
trade.show()
eq(trade.currencyLabel.text, 'Gold Coin', 'gold shop: currency label untouched')
eq(trade.currencyMoneyLabel.text, 'Gold:', 'gold shop: balance label untouched')
eq(trade.getPlayerMoney(), 30400000, 'gold shop: the gold')

-- the azure NPC: the packet comes first, then the base hides the old window and opens the shop
PACKETS.az = { action = 'currency', data = { code = 'AZ', name = 'Azure Coin', item = 26780, amount = 42 } }
NOW = 2000
opcodes[113](nil, 113, 'az')
trade.hide()
trade.show()
eq(trade.currencyLabel.text, 'Azure Coin', 'currency name in the header')
eq(trade.currencyItem.itemId, 26780, 'currency icon is the item')
eq(trade.currencyItem.visible, true, 'icon visible')
eq(trade.currencyMoneyLabel.text, 'Balance:', 'balance label')
eq(trade.getPlayerMoney(), 42, "the balance is the player's azure coins, not the gold")
eq(trade.moneyLabel.text, '42', 'the money label shows it')
eq(trade.CURRENCYID, 26780, 'not gold: no backpack fee option')
trade.refreshTradeItems()
eq(trade.itemsPanel.children[1].nameLabel.text, 'blightwoven armor\nPrice 30, 110.00 oz', 'currency shop: whole row')

-- a purchase: the server sends the new balance
PACKETS.again = { action = 'currency', data = { code = 'AZ', name = 'Azure Coin', item = 26780, amount = 12, again = true } }
opcodes[113](nil, 113, 'again')
eq(trade.getPlayerMoney(), 12, 'the balance after the purchase')
eq(trade.moneyLabel.text, '12', 'and its label')

-- closing gives the gold back; a late balance packet is ignored and makes no currency for the next window
trade.hide()
eq(trade.getPlayerMoney(), 30400000, 'closed: the gold function is back')
opcodes[113](nil, 113, 'again')
trade.show()
eq(trade.getPlayerMoney(), 30400000, 'a late balance did not make a currency')

-- a storage currency has no icon
PACKETS.st = { action = 'currency', data = { code = 'H', name = 'hallowfall coins', amount = 17 } }
NOW = 3000
opcodes[113](nil, 113, 'st')
trade.hide()
trade.show()
eq(trade.currencyLabel.text, 'Hallowfall Coins', 'storage currency name')
eq(trade.currencyItem.visible, false, 'no icon for a storage currency')
eq(trade.itemBorder.visible, false, 'no icon border either')
eq(trade.getPlayerMoney(), 17, 'storage balance')

-- bad packets change nothing
trade.hide()
opcodes[113](nil, 113, 'nothing')
opcodes[113](nil, 113, nil)
trade.show()
eq(trade.getPlayerMoney(), 30400000, 'bad packets: still gold')

-- a pending currency that waited too long is dropped
NOW = 4000
opcodes[113](nil, 113, 'az')
NOW = 4000 + TradeWindowLogic.CURRENCY_TTL + 5
trade.show()
eq(trade.getPlayerMoney(), 30400000, 'stale pending: gold')

-- O506: opening the shop closes no backpack and takes no room in a side panel; the window floats on the root panel
resetPanel()
npcWindow.parent, npcWindow.visible, npcWindow.size, npcWindow.raised, npcWindow.focused = nil, false, nil, nil, nil
local origPriority, origPlain = gi.addToPanelsWithPriority, gi.addToPanels
eq(trade.show(), true, 'the shop opens')
eq(#closedWindows, 0, 'opening the shop closed no window') eq(#panelWindows, 4, 'the side panel keeps all its windows')
eq(npcWindow.parent, root, 'the trade window is on the root panel, not in a side panel')
eq(npcWindow.visible, true, 'and shown') eq(npcWindow.size.width, 420, 'at its size') eq(npcWindow.size.height, 520, 'at its size')
eq(npcWindow.raised, true, 'raised') eq(npcWindow.focused, true, 'and focused')
eq(gi.addToPanelsWithPriority, origPriority, 'game_interface.addToPanelsWithPriority is back as it was')
eq(gi.addToPanels, origPlain, 'game_interface.addToPanels is back as it was')
-- the second time (the window is already on the root panel) the same
npcWindow.visible = false
eq(trade.show(), true, 'the shop opens again') eq(#closedWindows, 0, 'and closes nothing again') eq(npcWindow.parent, root, 'on the root panel')
-- the plain call (a base without addToPanelsWithPriority) is guarded the same way
function trade.show() local placed = modules.game_interface.addToPanels(npcWindow); if placed then npcWindow.visible = true end; return placed end
trade.hide()
terminate()
init()
npcWindow.visible = false
eq(trade.show(), true, 'the plain call: the shop opens') eq(#closedWindows, 0, 'the plain call closed no window') eq(npcWindow.parent, root, 'the plain call: root panel')
-- another window still gets what the base gives: a place in the panel, with the windows it closes to make room
eq(gi.addToPanelsWithPriority(otherWindow, true), true, 'another window is placed as before') eq(#closedWindows, 3, 'and the base closes what it closes for it')
eq(otherWindow.parent, 'sidePanel', 'in the side panel')
-- a show() that fails puts the functions back and passes the error on
resetPanel()
function trade.show() modules.game_interface.addToPanels(npcWindow); error('boom') end
terminate()
init()
local okShow, errShow = pcall(trade.show)
eq(okShow, false, 'a failing show fails') eq(tostring(errShow):find('boom', 1, true) ~= nil, true, 'with its own error')
eq(gi.addToPanels, origPlain, 'and the function is back after the failure') eq(#closedWindows, 0, 'nothing was closed')
function trade.show() end

-- terminate puts everything back
terminate()
eq(opcodes[113], nil, 'terminate: opcode unregistered')
trade.show()
eq(trade.getPlayerMoney(), 30400000, 'terminate: gold')

print('npctradewindow glue tests OK (' .. checks .. ' checks)')
if fails > 0 then os.exit(1) end
