-- luajit tradewindow_test.lua && lua5.3 tradewindow_test.lua   (CI runs every client *_test.lua from the repo root)
-- The glue of tradewindow.lua against a mocked client: the packets of a shop (items, player goods), the currency of opcode 113,
-- buying and selling, the keys, Sell all with its queue, the ignore list, the x and Esc, and what the module takes from the
-- base game_npctrade and gives back. The widgets are the real tradewindow.otui on tradefake.lua.
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

dofile(here .. 'tradefake.lua')
local fake = TradeFake.install(here .. 'tradewindow.otui')
local Widget, new = fake.Widget, fake.new
function Widget:setParent(p) self.parent = p end
function Widget:getParent() return self.parent end
function Widget:setSize(s) self.size = s end
function Widget:setPosition(p) self.position = p end
function Widget:getWidth() return self.size and self.size.width or 720 end
function Widget:getHeight() return self.size and self.size.height or 480 end
function Widget:raise() self.raised = true end
function Widget:setGameMenu() end
function Widget:addOption(label, fn) self.options = self.options or {} self.options[#self.options + 1] = { label, fn } end
function Widget:addCheckBoxOption(label, fn) self.options = self.options or {} self.options[#self.options + 1] = { label, fn } end
function Widget:addSeparator() end
function Widget:display() self.displayed = true end

-- ---------------------------------------------------------------- the fake client
local logs, infoBoxes, events, nextEvent = {}, {}, {}, 0
g_logger = { warning = function(m) logs[#logs + 1] = m end }
g_clock = { seconds = function() return 1000 end }
function scheduleEvent(fn, ms) nextEvent = nextEvent + 1 events[nextEvent] = { fn = fn, ms = ms or 0 } return nextEvent end
function removeEvent(e) events[e] = nil end
local function runEvents()
  local again = true
  while again do
    again = false
    for k, ev in pairs(events) do
      if ev.ms < 1000 then events[k] = nil ev.fn() again = true break end
    end
  end
end
local function fireTimeouts() for k, ev in pairs(events) do if ev.ms >= 1000 then events[k] = nil ev.fn() end end end
local keys = {}
g_keyboard = { bindKeyDown = function(key, fn, w) keys[w] = keys[w] or {} keys[w][key] = fn end,
  isShiftPressed = function() return false end }
g_client = { setInputLockWidget = function(w) g_client.locked = w end }
local files = {}
g_resources = { fileExists = function(f) return files[f] ~= nil end, readFileContents = function(f) return files[f] end,
  writeFileContents = function(f, t) files[f] = t end }
LoadedPlayer = { isLoaded = function() return true end, getId = function() return 7 end }
json = { decode = function(t) return type(t) == 'table' and t or (JSONS or {})[t] end, encode = function(t) return 'list:' .. table.concat(t, ',') end }
comma_value = function(s) return (tostring(s):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')) end
formatShortNumber = function(x) return x >= 1000 and string.format('%.1fk', x / 1000) or tostring(x) end
displayInfoBox = function(title, text) infoBoxes[#infoBoxes + 1] = text end
GOLD_COINS = 3031
InventorySlotsWorn = { 1, 2, 3 }
MouseLeftButton, MouseRightButton = 1, 2
LocalPlayer = {}
local connected = {}
function connect(obj, handlers) connected[obj] = connected[obj] or {} for k, v in pairs(handlers) do connected[obj][k] = v end end
function disconnect(obj, handlers) if connected[obj] then for k, v in pairs(handlers) do if connected[obj][k] == v then connected[obj][k] = nil end end end end
local opcodes = {}
ProtocolGame = { registerExtendedOpcode = function(op, fn) opcodes[op] = fn end, unregisterExtendedOpcode = function(op) opcodes[op] = nil end }

local function itemPtr(id, name, stackable)
  return { id = id, name = name, getId = function(self) return self.id end, isStackable = function() return stackable == true end,
    isFluidContainer = function() return false end, getCountOrSubType = function() return 0 end,
    getAverageMarketValue = function(self) return self.market or 0 end, getCount = function() return 1 end }
end
local potion, mana, arrow, blade = itemPtr(100, 'strong health potion'), itemPtr(101, 'mana potion'), itemPtr(102, 'light arrow', true), itemPtr(103, 'cursed blade')
blade.market = 1500
local worn = {}  -- slot -> item
local freeCap = 100
local player = { getFreeCapacity = function() return freeCap end, getInventoryItem = function(_, slot) return worn[slot] end }
local sent = {}
g_game = {
  isOnline = function() return true end, getLocalPlayer = function() return player end,
  doThing = function() end, closeNpcTrade = function() sent[#sent + 1] = { 'close' } end,
  buyItem = function(ptr, amount, ignoreCap, bags) sent[#sent + 1] = { 'buy', ptr.id, amount, ignoreCap, bags } end,
  sellItem = function(ptr, amount, ignoreEquipped) sent[#sent + 1] = { 'sell', ptr.id, amount, ignoreEquipped } end,
  inspectNpcTrade = function(ptr) sent[#sent + 1] = { 'look', ptr.id } end,
  sendInspectionObject = function(kind, id) sent[#sent + 1] = { 'inspect', id } end,
}
g_things = { getThingType = function(id)
  return { isFluidContainer = function() return false end, isSplash = function() return false end,
    isChargeable = function() return false end, getClothSlot = function() return id == 103 and 6 or 0 end }
end }
getItemCategory = function(id) return (id == 100 or id == 101) and 10 or id == 102 and 16 or 0 end

local root = new('root')
TradeFake.root = root
function root:getX() return 0 end
function root:getY() return 0 end
function root:getWidth() return 1920 end
function root:getHeight() return 1080 end
local toggles = {}
local ended = 0
local baseCalls = {}
local function baseFn(name) return function(...) baseCalls[#baseCalls + 1] = name end end
modules = {
  game_interface = { getRootPanel = function() return root end, toggleFocus = function(on, why) toggles[#toggles + 1] = { on, why } end },
  game_console = { getConsole = function() return { focus = function() end } end },
  game_npctrade = {
    show = baseFn('show'), hide = baseFn('hide'), isTrading = baseFn('isTrading'), closeNpcTrade = baseFn('closeNpcTrade'),
    sellAll = baseFn('sellAll'), getPlayerMoney = baseFn('getPlayerMoney'),
    onOpenNpcTrade = function() end, onCloseNpcTrade = function() end, onPlayerGoods = function() end,
    onFreeCapacityChange = function() end, onInventoryChange = function() end,
    endNpcConversation = function() ended = ended + 1 end,
  },
}
local trade = modules.game_npctrade
local baseShow, baseOpen = trade.show, trade.onOpenNpcTrade
connected[g_game] = { onOpenNpcTrade = baseOpen, onCloseNpcTrade = trade.onCloseNpcTrade, onPlayerGoods = trade.onPlayerGoods }
connected[LocalPlayer] = { onFreeCapacityChange = trade.onFreeCapacityChange, onInventoryChange = trade.onInventoryChange }

for _, f in ipairs({ 'tradewindowlogic', 'trademodel', 'tradeview' }) do dofile(here .. f .. '.lua') end
local env = setmetatable({}, { __index = _G })
local chunk = assert(loadfile(here .. 'tradewindow.lua', 't', env))
chunk()
-- the .otmod's @onLoad / @onUnload call these two
local init, terminate = env.init, env.terminate

-- ---------------------------------------------------------------- the module takes the shop over
init()
local win
for _, k in ipairs(root.kids) do if k.id == 'tradeWindow' then win = k end end
eq(win ~= nil, true, 'the window is made on the game view'); eq(win.visible, false, 'hidden until a shop opens')
eq(connected[g_game].onOpenNpcTrade ~= baseOpen, true, 'the base handler of the shop packet is disconnected')
eq(trade.show ~= baseShow, true, 'show is ours'); eq(trade.isTrading(), false, 'no shop open')
eq(trade.getPlayerMoney(), 0, 'no balance outside a shop')
eq(opcodes[113] ~= nil, true, 'opcode 113 is ours')
local ui = {}
local function find(id) return win:recursiveGetChildById(id) end

local function row(ptr, name, weight, buy, sell) return { ptr, name, math.floor(weight * 100), buy, sell } end
local function open(rows, money, owned)
  connected[g_game].onOpenNpcTrade(rows)
  connected[g_game].onPlayerGoods(money, owned or {})
  runEvents()
end
local rows = { row(potion, 'strong health potion', 3.5, 100, 40), row(mana, 'mana potion', 3.5, 50, 20),
  row(arrow, 'light arrow', 0.7, 3, 1), row(blade, 'cursed blade', 20, 0, 900) }
open(rows, 1000, { { potion, 5 }, { blade, 2 }, { arrow, 250 } })
eq(win.visible, true, 'the window opens'); eq(trade.isTrading(), true, 'a shop is open')
eq(win.size.width, 720, 'its size'); eq(win.size.height, 480, 'its height'); eq(win.position.x, 600, 'centred in x'); eq(win.position.y, 300, 'and in y')
eq(find('buyTab').text, 'Buy (3)', 'three things to buy'); eq(find('sellTab').text, 'Sell (4)', 'four to sell')
eq(find('buyTab').checked, true, 'the Buy tab first')
eq(find('currencyLabel').text, 'Currency: Gold Coin', 'the currency line')
eq(find('balanceLabel').text, 'Gold: 1.0k', 'the gold'); eq(find('balanceLabel').tooltip, '1,000', 'the exact gold')
eq(#find('list').kids, 3, 'a card per thing to buy')
eq(find('list').kids[1]:getChildById('nameLabel').text, 'Light Arrow', 'sorted by name')
eq(find('chips').visible, true, 'category chips'); eq(find('chips').kids[1].text, 'All 3', 'All')
eq(find('content').visible, false, 'nothing selected yet')
eq(trade.getPlayerMoney(), 1000, 'getPlayerMoney answers from here')

-- buying: select, change the amount, trade
local view = nil
local function card(name) for _, k in ipairs(find('list').kids) do if k:getChildById('nameLabel').text == name then return k end end end
card('Strong Health Potion').onClick()
eq(find('content').visible, true, 'details'); eq(find('selName').text, 'Strong Health Potion', 'selected')
eq(find('amountText').text, '1', 'a buy starts at 1'); eq(find('quantityScroll').scroll.max, 10, 'gold limits it to 10')
eq(find('totalValue').text, '100', 'total'); eq(find('afterValue').text, '900', 'gold after')
find('plusButton').onClick(); eq(find('amountText').text, '2', 'plus')
find('plusButton').onClick(); find('minusButton').onClick(); eq(find('amountText').text, '2', 'minus')
find('maxButton').onClick(); eq(find('amountText').text, '10', 'max')
find('amountText'):setText('4'); eq(find('totalValue').text, '400', 'a typed amount')
find('amountText'):setText('99'); eq(find('amountText').text, '10', 'a too big amount is cut to the limit')
find('amountText'):setText('3')
find('tradeButton').onClick()
eq(sent[#sent][1], 'buy', 'a buy packet'); eq(sent[#sent][2], 100, 'of the potion'); eq(sent[#sent][3], 3, 'three of them')
eq(sent[#sent][4], false, 'capacity counts'); eq(sent[#sent][5], false, 'no bags')
-- shopping bags and ignore capacity
find('bagsCheck'):setChecked(true); eq(find('totalValue').text, '320', 'the bag fee is in the total (3 x 100 + 20)')
find('tradeButton').onClick(); eq(sent[#sent][5], true, 'bags asked')
find('bagsCheck'):setChecked(false)
find('ignoreCapCheck'):setChecked(true); find('tradeButton').onClick(); eq(sent[#sent][4], true, 'ignore capacity asked')
find('ignoreCapCheck'):setChecked(false)
-- the card of what the player cannot afford is dimmed and a heavy buy is capped by capacity
connected[LocalPlayer].onFreeCapacityChange(nil, 7)
eq(find('quantityScroll').scroll.max, 2, 'capacity caps the amount (7 / 3.5)'); eq(find('warnLabel').text, 'That is all you can carry.', 'and says so')
connected[LocalPlayer].onFreeCapacityChange(nil, 100)
-- the gold changes: the player goods after a purchase
connected[g_game].onPlayerGoods(300, { { potion, 8 } })
eq(find('balanceLabel').text, 'Gold: 300', 'the balance follows the packet'); eq(find('quantityScroll').scroll.max, 3, 'and the limit')
connected[g_game].onPlayerGoods(1000, { { potion, 5 }, { blade, 2 }, { arrow, 250 } })

-- search, category, sort
find('searchText'):setText('man')
local shown = 0
for _, k in ipairs(find('list').kids) do if k.visible then shown = shown + 1 end end
eq(shown, 1, 'the search narrows the list'); eq(find('selName').text, '', 'a selection that is filtered out is dropped')
find('searchText'):setText('')
find('chips').kids[3].onClick() -- ammo (All, Potions, Ammunition)
shown = 0
for _, k in ipairs(find('list').kids) do if k.visible then shown = shown + 1 end end
eq(shown, 1, 'a category chip narrows it'); find('chips').kids[1].onClick()
find('sortButton').onClick(); eq(find('sortButton').text, 'Sort: Price', 'the sort cycles')
find('sortButton').onClick(); find('sortButton').onClick()
eq(find('sortButton').text, 'Sort: Name', 'and comes round')

-- right click: Look and Inspect
card('Mana Potion').onMouseRelease(nil, { x = 0, y = 0 }, MouseRightButton)
-- (the menu is made by the glue; its entries call the game)
-- selling
find('sellTab').onClick()
eq(find('sellTab').checked, true, 'the Sell tab'); eq(find('tradeButton').text, 'Sell', 'the button')
eq(#find('list').kids, 4, 'the sell list has its own cards')
local visibleSell = 0
for _, k in ipairs(find('list').kids) do if k.visible then visibleSell = visibleSell + 1 end end
eq(visibleSell, 3, 'only what the player carries: potions, blades, arrows')
card('Light Arrow').onClick()
eq(find('amountText').text, '100', 'a sale starts at the most (100 at a time)'); eq(find('ownedValue').text, '250', 'owned')
find('tradeButton').onClick(); eq(sent[#sent][1], 'sell', 'a sell packet'); eq(sent[#sent][3], 100, 'a hundred'); eq(sent[#sent][4], true, 'equipped copies are kept')
find('equippedCheck'):setChecked(true); find('tradeButton').onClick(); eq(sent[#sent][4], false, 'sell equipped when asked')
find('equippedCheck'):setChecked(false)
-- a copy the player wears does not count
worn[1] = potion
connected[LocalPlayer].onInventoryChange()
card('Strong Health Potion').onClick()
eq(find('ownedValue').text, '4', '5 carried, 1 worn: 4 to sell'); worn[1] = nil
connected[LocalPlayer].onInventoryChange()

-- Sell all: a window with what will be sold, the total, the ignore list
find('sellAllButton').onClick()
local sa
for _, k in ipairs(root.kids) do end
local saWin = g_client.locked
eq(saWin ~= nil and saWin.id == 'tradeSellAllWindow' or saWin.style == 'TradeSellAllWindow', true, 'the Sell all window locks the input')
local rowsPanel = saWin:recursiveGetChildById('rows')
eq(#rowsPanel.kids, 3, 'three rows: blades, arrows, potions')
eq(rowsPanel.kids[1]:getChildById('nameLabel').text, '2x Cursed Blade', 'the dearest first')
eq(rowsPanel.kids[1]:getChildById('infoLabel').text, '1,800  -  below the market value', 'a blade sells under its market value (900 < 1500)')
eq(saWin:recursiveGetChildById('totalLabel').text, '257 items, 2,250 for Gold Coin', 'the total: 1800 + 250 + 200')

-- the ignore list: "Never sell" on the blades moves them out of the sale and is saved
local function press(w, key) return keys[w][key]() end
local keepBlade = rowsPanel.kids[1]:getChildById('keepButton')
eq(keepBlade.text, 'Never sell', 'the button')
keepBlade.onClick()
eq(files['/characterdata/7/sellAllWhitelist.json'], 'list:103', 'the ignore list is saved where the base wrote it')
rowsPanel = saWin:recursiveGetChildById('rows')
eq(#rowsPanel.kids, 2, 'two rows are left'); eq(saWin:recursiveGetChildById('totalLabel').text, '255 items, 450 for Gold Coin', 'the new total')
eq(saWin:recursiveGetChildById('ignoreTab').text, 'Ignored (1)', 'one ignored')
-- Enter on the window sells; the queue sends one packet and waits for the server
local before = #sent
press(saWin, 'Enter')
eq(g_client.locked, nil, 'the window is closed'); eq(#sent, before + 1, 'one packet')
eq(sent[#sent][1] .. sent[#sent][2] .. ':' .. sent[#sent][3], 'sell102:100', 'the arrows first (250 gold), a hundred at a time')
runEvents(); eq(#sent, before + 1, 'nothing more before the server answers')
local function goods(money, ...) connected[g_game].onPlayerGoods(money, { ... }) runEvents() end
goods(1100, { potion, 5 }, { blade, 2 }, { arrow, 150 })
eq(#sent, before + 2, 'the next packet'); eq(sent[#sent][3], 100, 'a hundred again')
goods(1200, { potion, 5 }, { blade, 2 }, { arrow, 50 })
eq(sent[#sent][3], 50, 'the rest of the arrows')
goods(1250, { potion, 5 }, { blade, 2 })
eq(sent[#sent][2], 100, 'then the potions'); eq(sent[#sent][3], 5, 'all five')
goods(1450, { blade, 2 })
eq(infoBoxes[#infoBoxes], 'The server confirmed 255 items sold for 450 Gold Coin.', 'the player is told what the server confirmed')
eq(find('list').kids ~= nil, true, 'the window is still there')

-- a sale whose answer never comes stops with a message
open(rows, 1000, { { potion, 5 } })
find('sellTab').onClick(); find('sellAllButton').onClick()
saWin = g_client.locked
press(saWin, 'Enter'); local count = #sent
fireTimeouts()
eq(infoBoxes[#infoBoxes], 'Sale stopped: the server did not confirm the sale. Please refresh the shop.', 'a timeout is told')
goods(1200, { potion, 4 }); eq(#sent, count, 'and nothing is sent after it')

-- Esc closes the Sell all window first, then the shop
open(rows, 1000, { { potion, 5 }, { arrow, 20 } })
find('sellTab').onClick(); find('sellAllButton').onClick()
saWin = g_client.locked
press(saWin, 'Escape'); eq(g_client.locked, nil, 'Esc in Sell all closes it'); eq(win.visible, true, 'the shop stays')
-- Enter trades the selected card; in the search box it picks the first card instead
find('buyTab').onClick()
card('Strong Health Potion').onClick()
local sentBefore = #sent
press(win, 'Enter'); eq(sent[#sent][1], 'buy', 'Enter trades'); eq(#sent, sentBefore + 1, 'once')
find('searchText').focused = true
sentBefore = #sent
press(win, 'Enter'); eq(#sent, sentBefore, 'Enter in the search does not trade')
find('searchText').focused = false
-- Up and Down move through the list
press(win, 'Down'); eq(find('selName').text ~= '', true, 'Down selects')
-- the sale of the whole list for a bot: no window, the same queue
find('sellTab').onClick()
local selling = #sent
eq(trade.sellAll(false, { 100 }), true, 'sellAll for other modules'); eq(#sent, selling + 1, 'it starts the queue')
-- Esc closes the shop and tells the server
press(win, 'Escape')
eq(sent[#sent][1], 'close', 'Esc tells the server'); eq(win.visible, false, 'the window is closed'); eq(trade.isTrading(), false, 'no shop')
eq(ended, 0, 'Esc does not end the conversation')
-- the x ends the conversation
open(rows, 1000, {})
find('closeButton').onClick()
eq(sent[#sent][1], 'close', 'the x closes the shop'); eq(ended, 1, 'and ends the conversation')

-- a currency other than gold
JSONS = { azure = { action = 'currency', data = { code = 'AZ', name = 'azure coin', item = 26780, amount = 42 } },
  again = { action = 'currency', data = { code = 'AZ', name = 'azure coin', item = 26780, amount = 12, again = true } } }
opcodes[113](nil, 113, 'azure')
open({ row(potion, 'strong health potion', 3.5, 30, 0) }, 1000000, {})
eq(find('currencyLabel').text, 'Currency: Azure Coin', 'the currency of the NPC'); eq(find('currencyItem').itemId, 26780, 'its icon')
eq(find('balanceLabel').text, 'Balance: 42', 'the balance in that currency, not the gold'); eq(trade.getPlayerMoney(), 42, 'for the other modules too')
eq(find('bagsCheck').visible, false, 'no shopping bags')
eq(find('list').kids[1]:getChildById('coin').itemId, 26780, 'the price shows that coin')
card('Strong Health Potion').onClick(); eq(find('quantityScroll').scroll.max, 1, 'the limit is the 42 coins (30 each)')
opcodes[113](nil, 113, 'again'); eq(find('balanceLabel').text, 'Balance: 12', 'the balance after a purchase')
eq(find('quantityScroll').scroll.max, 0, 'and the limit'); eq(find('warnLabel').text, 'You cannot afford this.', 'cannot afford')
press(win, 'Escape')
open({ row(potion, 'strong health potion', 3.5, 30, 0) }, 500, {})
eq(find('currencyLabel').text, 'Currency: Gold Coin', 'the next shop is gold again'); eq(find('balanceLabel').text, 'Gold: 500', 'and its gold')
press(win, 'Escape')

-- unloading gives everything back
terminate()
eq(trade.show, baseShow, 'show is the base\'s again'); eq(connected[g_game].onOpenNpcTrade, baseOpen, 'its handlers are connected again')
eq(opcodes[113], nil, 'opcode 113 is free'); eq(win.destroyed, true, 'the window is gone')
eq(#logs, 0, 'nothing was logged: ' .. tostring(logs[1]))

print(string.format('tradewindow_test: %d checks OK', n))
