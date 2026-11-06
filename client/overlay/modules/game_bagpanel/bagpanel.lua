-- game_bagpanel (O420): one inventory panel in the right side panel instead of a window per backpack. Owner request
-- 2026-11-06 ("conseguimos fazer isso com as nossas bags?"). Rules in bagpanel_core.lua (tested by
-- bagpanel_core_test.lua); the tabs, the grid and the page buttons are drawn from bagpanel.otui.
--  * Equip tab: the ten equipment slots (UIItem widgets on the slot positions, so drag and drop, the right-click menu
--    and the rich tooltip of game_itemtooltip work as in the classic windows), the outfit, gold counted from the open
--    containers and the Chaos Coins of game_shop.
--  * The grid mirrors one container: page 1 is the main backpack (the container of inventory slot 3), every bag in it
--    is another page. A bag page opens the bag with g_game.open on its item and reuses the container id of the bag
--    shown before, so at most one bag is open for the panel. Cells carry the container slot position, so a drop
--    (UIItem:onDrop -> g_game.move) puts an item in the page like in a container window.
--  * The stock windows of the main backpack and its bags are hidden while the panel is on (the containers stay open:
--    they feed the grid). Any other container (a corpse, the depot, a bag in a bag, a quiver) keeps its window.
--  * Sort: moves items to the front of the page one by one (the server adds an item at the front), one move every
--    C.STEP_MS, recomputed from the page after each answer (bagpanel_core.lua C.sortStep).
--  * Quest / Stats / Buffs / Shop link to the windows that exist (C.TABS); a tab with no target is not shown.
--  * Always on (the Classic option was dropped, owner 2026-11-06). The stock inventory window is hidden; its fight
--    modes, soul, capacity, Stop and condition icons move into the panel (see "the stock inventory window").
-- Container keys come from game_chaoslayout (ChaosLayout.Containers.keyOf); a container with no key is left alone.
local M = {}
local C = BagPanelCore

local window
local selected = 'main'
local bagMemo = {}      -- container id -> { slot = index in the main backpack, id = the bag's item id }
local cells, cellsFor = {}, nil
local equip = {}        -- inventory slot -> widget
local tabButtons = {}
local sorting = nil
local queued = false
local cycle = nil
local handlers = {}
local reported = {}
local ensureTries = 0
local hiddenWindows = {} -- container id -> true for the stock windows this module hid

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[bagpanel] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

local function child(id)
  return alive(window) and window:recursiveGetChildById(id) or nil
end

local function message(text)
  local tm = modules.game_textmessage
  if tm and type(tm.displayStatusMessage) == 'function' then pcall(tm.displayStatusMessage, text) end
end

-- ---------------------------------------------------------------- containers
local function keyOf(c)
  local layout = ChaosLayout
  local k = layout and layout.Containers
  if not k or not k.keyOf then return nil end
  local ok, key = pcall(k.keyOf, c)
  return ok and key or nil
end

local function containers()
  local out = {}
  for _, c in pairs(g_game.getContainers() or {}) do
    local closed = false
    if c.isClosed then
      local ok, v = pcall(c.isClosed, c)
      closed = ok and v == true
    end
    if not closed then out[#out + 1] = c end
  end
  return out
end

local function mainContainer()
  for _, c in ipairs(containers()) do
    if C.classify(keyOf(c)) == 'main' then return c end
  end
  return nil
end

local function bagItemId(c)
  local ok, item = pcall(function() return c:getContainerItem() end)
  if ok and item then return item:getId() end
  return nil
end

-- the open bag of the main backpack that belongs to page `slot`
local function bagContainer(slot)
  for _, c in ipairs(containers()) do
    local m = bagMemo[c:getId()]
    if m and m.slot == slot then return c end
  end
  return nil
end

-- the main backpack's slots as the core wants them
local function mainItems(main)
  local out = {}
  for i = 0, main:getCapacity() - 1 do
    local item = main:getItem(i)
    if item then
      local isC = false
      if item.isContainer then
        local ok, v = pcall(item.isContainer, item)
        isC = ok and v == true
      end
      out[i + 1] = { id = item:getId(), container = isC }
    else
      out[i + 1] = false
    end
  end
  return out
end

local function slotPosition(c, i)
  if c.getSlotPosition then
    local ok, pos = pcall(c.getSlotPosition, c, i)
    if ok and pos then return pos end
  end
  return C.containerPos(c:getId(), i)
end

-- ---------------------------------------------------------------- drawing
local function drawMoney()
  local gold, coins = child('goldLabel'), child('coinsLabel')
  if not gold or not coins then return end
  local items = {}
  for _, c in ipairs(containers()) do
    for i = 0, c:getCapacity() - 1 do
      local item = c:getItem(i)
      if item and C.COINS[item:getId()] then items[#items + 1] = { id = item:getId(), count = item:getCount() } end
    end
  end
  local total = C.gold(items)
  local short = formatShortNumber and formatShortNumber(total) or tostring(total)
  gold:setText(tr('Gold: %s', short))
  gold:setTooltip(tr('Gold in your open backpacks: %s', comma_value and comma_value(total) or tostring(total)))
  local shop = modules.game_shop
  local n = shop and type(shop.getCoins) == 'function' and shop.getCoins() or nil
  if n then
    coins:setText(tr('Chaos Coins: %s', formatShortNumber and formatShortNumber(n) or tostring(n)))
    coins:setTooltip(tr('Chaos Coins: %s', comma_value and comma_value(n) or tostring(n)))
    coins:setVisible(true)
  else
    coins:setVisible(false)
  end
end

local function drawEquipSlot(slot)
  local w = equip[slot]
  if not alive(w) then return end
  local player = g_game.getLocalPlayer()
  local item = player and player:getInventoryItem(slot) or nil
  w:setItem(item)
  w:setTooltip(item and '' or tr(C.SLOT_NAMES[slot] or ''))
end

local function drawOutfit()
  local view = child('outfit')
  local player = g_game.getLocalPlayer()
  if not view or not player then return end
  view:setOutfit(player:getOutfit())
end

local function buildEquip()
  local panel = child('slots')
  if not panel then return end
  panel:destroyChildren()
  equip = {}
  for _, row in ipairs(C.EQUIP_ROWS) do
    for _, slot in ipairs(row) do
      if slot == 0 then
        g_ui.createWidget('UIWidget', panel):setSize({ width = C.CELL, height = C.CELL })
      else
        local w = g_ui.createWidget('BagPanelCell', panel)
        w:setId('equip' .. slot)
        w.position = C.slotPos(slot)
        equip[slot] = w
      end
    end
  end
  for slot in pairs(equip) do drawEquipSlot(slot) end
  drawOutfit()
end

local function clearGrid()
  local grid = child('grid')
  if grid then grid:destroyChildren() end
  cells, cellsFor = {}, nil
end

local function decorate(w, item)
  if ItemsDatabase then
    if ItemsDatabase.setRarityItem then pcall(ItemsDatabase.setRarityItem, w, item) end
    if ItemsDatabase.setTier then pcall(ItemsDatabase.setTier, w, item) end
  end
end

local function drawGrid(c)
  local grid = child('grid')
  local empty = child('emptyLabel')
  if not grid then return end
  if not c then
    clearGrid()
    grid:setHeight(0)
    if empty then empty:setVisible(true) end
    return
  end
  local cap = c:getCapacity()
  local key = c:getId() .. ':' .. cap
  if cellsFor ~= key then
    grid:destroyChildren()
    cells = {}
    for i = 0, cap - 1 do
      local w = g_ui.createWidget('BagPanelCell', grid)
      w:setId('slot' .. i)
      w.position = slotPosition(c, i)
      cells[i + 1] = w
    end
    cellsFor = key
  end
  local any = false
  for i = 0, cap - 1 do
    local w = cells[i + 1]
    local item = c:getItem(i)
    if item then any = true end
    if alive(w) then
      w:setItem(item)
      decorate(w, item)
    end
  end
  local cols = C.columns(grid:getWidth(), C.CELL, 2)
  local height = C.gridHeight(cap, cols, C.CELL, 2)
  if grid:getHeight() ~= height then grid:setHeight(height) end
  if empty then empty:setVisible(not any) end
end

local function drawPages(pages, main)
  local row = child('pages')
  if not row then return end
  row:destroyChildren()
  local n = 0
  for _, p in ipairs(pages) do
    n = n + 1
    local w = g_ui.createWidget('BagPanelPage', row)
    w.pageKey = p.key
    local id = p.id or (main and bagItemId(main))
    if id then w:setItemId(id) end
    w:setTooltip(p.key == 'main' and tr('Backpack') or tr('Bag %d', n - 1))
    w:setBorderColor(p.key == selected and '#f6cf72' or '#00000000')
    w.onMouseRelease = function(widget, pos, button)
      if button ~= MouseLeftButton then return false end
      M.selectPage(widget.pageKey)
      return true
    end
  end
  local cols = C.columns(row:getWidth(), 26, 2)
  local height = C.gridHeight(n, cols, 26, 2)
  if row:getHeight() ~= height then row:setHeight(height) end
end

local function pageContainer(main, pages)
  if selected == 'main' then return main end
  for _, p in ipairs(pages) do
    if p.key == selected then return bagContainer(p.slot) end
  end
  return nil
end

function M.draw()
  queued = false
  if not alive(window) then return end
  local main = mainContainer()
  local pages = { { key = 'main' } }
  if main then
    local bags = C.bagSlots(mainItems(main))
    pages = C.pages(bags)
    -- the bags opened for the panel: still a bag of the same item where they were, else the nearest of its kind
    for cid, m in pairs(bagMemo) do
      local c = g_game.getContainer(cid)
      if not c then
        bagMemo[cid] = nil
      else
        local here = false
        for _, b in ipairs(bags) do
          if b.slot == m.slot and b.id == m.id then here = true end
        end
        if not here then
          local s = C.rematch(m.slot, m.id, bags)
          if s then m.slot = s else bagMemo[cid] = nil end
        end
      end
    end
    selected = C.validKey(pages, selected)
  else
    selected = 'main'
  end
  local c = pageContainer(main, pages)
  drawGrid(c)
  drawPages(pages, main)
  drawMoney()
  -- the window grows to show the whole layout: the side panel's fitting shrank it when a stock window opened beside it
  -- and the pages and Sort went under the edge (seen in a client)
  addEvent(safe('fit', function()
    local buttons = child('buttons')
    if not (alive(window) and buttons) then return end
    local need = buttons:getRect().y + buttons:getHeight() + 10 - window:getRect().y
    if need > 0 and window:getHeight() < need then window:setHeight(need) end
  end))
end

function M.refresh()
  if queued then return end
  queued = true
  addEvent(safe('draw', M.draw))
end

-- ---------------------------------------------------------------- hiding the stock windows
local function hideStock(c)
  local w = c and c.window
  if alive(w) then
    w:hide()
    hiddenWindows[c:getId()] = true
  end
end

local function hideAllInPanel()
  for _, c in ipairs(containers()) do
    if C.inPanel(keyOf(c)) then hideStock(c) end
  end
end

local function showAllHidden()
  for cid in pairs(hiddenWindows) do
    local c = g_game.getContainer(cid)
    if c and alive(c.window) then c.window:show() end
  end
  hiddenWindows = {}
end

-- ---------------------------------------------------------------- container signals
local function restoring()
  local layout = ChaosLayout
  return layout and layout.Containers and layout.Containers.busy == true
end

local function onOpen(c, previous)
  if not c then return end
  local kind, slot = C.classify(keyOf(c))
  if not kind then return end
  hideStock(c)
  if kind == 'bag' then
    bagMemo[c:getId()] = { slot = slot, id = bagItemId(c) }
    -- a bag the player opened (a double click on it in the grid) is the page shown; the ones the login restore opens
    -- are not
    if not restoring() then selected = 'bag' .. slot end
  end
  M.refresh()
end

local function onClose(c)
  if not c then return end
  -- a bag opened into the id of the bag shown before: the old one's close comes after the new one's open
  local now = g_game.getContainer(c:getId())
  if now and now ~= c then return M.refresh() end
  hiddenWindows[c:getId()] = nil
  if bagMemo[c:getId()] then
    local m = bagMemo[c:getId()]
    bagMemo[c:getId()] = nil
    if selected == 'bag' .. m.slot then selected = 'main' end
  end
  M.refresh()
end

local function isMain(c)
  return C.classify(keyOf(c)) == 'main'
end

-- an item came into / left the main backpack: the bags opened for the panel moved with the list
local function shiftAll(slot, add)
  for cid, m in pairs(bagMemo) do
    local s = add and C.shiftAdd(m.slot, slot) or C.shiftRemove(m.slot, slot)
    if s then m.slot = s else bagMemo[cid] = nil end
  end
  local sel = tonumber(selected:sub(4))
  if selected:find('^bag') and sel then
    local s = add and C.shiftAdd(sel, slot) or C.shiftRemove(sel, slot)
    selected = s and ('bag' .. s) or 'main'
  end
end

local function onAdd(c, slot)
  if c and isMain(c) then shiftAll(slot, true) end
  M.refresh()
end

local function onRemove(c, slot)
  if c and isMain(c) then shiftAll(slot, false) end
  M.refresh()
end

local function onChange()
  M.refresh()
end

-- ---------------------------------------------------------------- pages and sort
function M.selectPage(key)
  if sorting then sorting = nil end
  if key == 'main' then
    selected = 'main'
    if not mainContainer() then
      local player = g_game.getLocalPlayer()
      local item = player and player:getInventoryItem(C.BACK_SLOT)
      if item then g_game.open(item) end
    end
    return M.refresh()
  end
  local slot = tonumber(tostring(key):sub(4))
  local main = mainContainer()
  if not slot or not main then return end
  selected = key
  if not bagContainer(slot) then
    local item = main:getItem(slot)
    if item then
      -- the bag shown before gives its container id to this one: at most one bag open for the panel
      local previous = nil
      for cid in pairs(bagMemo) do previous = g_game.getContainer(cid) or previous end
      g_game.open(item, previous)
    end
  end
  M.refresh()
end

local function pageEntries(c)
  local out = {}
  for i = 0, c:getCapacity() - 1 do
    local item = c:getItem(i)
    if item then
      out[#out + 1] = { id = item:getId(), count = item:getCount(), slot = i,
        stack = item.isStackable and item:isStackable() or false }
    end
  end
  return out
end

local function sortStep(cid, session)
  if sorting ~= session then return end
  local c = g_game.getContainer(cid)
  if not c then sorting = nil return end
  local action, slot = C.sortStep(session, pageEntries(c))
  if action == 'move' then
    local item = c:getItem(slot)
    if not item then sorting = nil return end
    g_game.move(item, C.wholePos(cid), item:getCount())
    scheduleEvent(safe('sort', function() sortStep(cid, session) end), C.STEP_MS)
    return
  end
  sorting = nil
  if action == 'done' then
    message(tr('Page sorted.'))
  else
    message(tr('Could not sort this page.'))
  end
  M.refresh()
end

function M.sort()
  if sorting or not g_game.isOnline() then return end
  local main = mainContainer()
  local pages = { { key = 'main' } }
  if main then pages = C.pages(C.bagSlots(mainItems(main))) end
  local c = pageContainer(main, pages)
  if not c then return end
  sorting = C.newSort(#pageEntries(c))
  sortStep(c:getId(), sorting)
end

-- ---------------------------------------------------------------- tabs
local function has(name, fn)
  local m = modules[name]
  return m ~= nil and type(m[fn]) == 'function'
end

local function buildTabs()
  local row = child('tabRow')
  if not row then return end
  row:destroyChildren()
  tabButtons = {}
  for _, t in ipairs(C.tabs(has)) do
    local b = g_ui.createWidget('BagPanelTab', row)
    b:setText(tr(t.text))
    if t.id == 'equip' then
      b:setChecked(true)
    else
      b.onClick = safe('tab', function()
        local m = modules[t.module]
        if m and type(m[t.fn]) == 'function' then m[t.fn]() end
      end)
    end
    tabButtons[#tabButtons + 1] = b
  end
  -- widths share the row by text length: the pt-BR names are longer than the English ones (seen in a client)
  local widths, total = {}, 0
  for i, b in ipairs(tabButtons) do
    widths[i] = b:getTextSize().width + 6
    total = total + widths[i]
  end
  local room = row:getWidth() - #tabButtons
  if room > 0 and total > 0 then
    for i, b in ipairs(tabButtons) do b:setWidth(math.floor(widths[i] * room / total)) end
  end
end

-- ---------------------------------------------------------------- the stock inventory window
-- The panel shows the equipment, so the stock window is hidden. Its fight modes, chase, safe fight, PvP, soul, capacity,
-- Stop and condition icons move into the panel's two rows: the same widgets, so game_inventory keeps updating them
-- and their clicks still reach g_game. They go back on terminate.
-- the PvP modes button opens the modes panel, which moves too: it floats under the row, over the status row
local MOVED_COMBAT = { 'fightOffensiveBox', 'fightBalancedBox', 'fightDefensiveBox', 'chaseModeBoxStand',
  'chaseModeBoxChase', 'safeFightBox', 'openPvpButton' }
local MOVED_STATUS = { 'soulLabel', 'capLabel', 'stopButton', 'conditionPanel' }
local moved = {}          -- widget -> its stock parent

local function stockWindow()
  local inv = modules.game_inventory
  local w = inv and inv.inventoryWindow
  return alive(w) and w or nil
end

local function hideStockInventory()
  local w = stockWindow()
  if w and w:isVisible() then w:hide() end
end

local function moveInto(row, ids)
  local stock = stockWindow()
  if not stock or not row then return end
  for _, id in ipairs(ids) do
    local w = stock:recursiveGetChildById(id)
    if alive(w) and w:getParent() ~= row then
      moved[w] = w:getParent()
      w:breakAnchors()
      w:setMargin(0)
      w:setParent(row)
    end
  end
end

local function moveControls()
  local row = child('combatRow')
  moveInto(row, MOVED_COMBAT)
  local stock = stockWindow()
  local modes = stock and stock:recursiveGetChildById('pvpModesPanel')
  if row and alive(modes) then
    moved[modes] = modes:getParent()
    modes:breakAnchors()
    modes:setMargin(0)
    modes:setParent(row:getParent())
    modes:addAnchor(AnchorTop, 'combatRow', AnchorBottom)
    modes:addAnchor(AnchorRight, 'combatRow', AnchorRight)
    modes:setMarginTop(2)
    modes:raise()
  end
  local status = child('statusRow')
  moveInto(status, MOVED_STATUS)
  local cond = status and status:getChildById('conditionPanel')
  if alive(cond) then
    local used = 0
    for _, id in ipairs(MOVED_STATUS) do
      local w = status:getChildById(id)
      if alive(w) and w ~= cond then used = used + w:getWidth() + 8 end
    end
    cond:setWidth(math.max(20, status:getWidth() - used))
  end
end

local function restoreControls()
  for w, parent in pairs(moved) do
    if alive(w) and alive(parent) then w:setParent(parent) end
  end
  moved = {}
end

local function watchStock()
  local w = stockWindow()
  if not w or handlers.stock then return end
  -- game_interface and the layout restore open it again (game_inventory.move): hide it each time it shows
  handlers.stock = { onVisibilityChange = function(widget, visible) if visible then addEvent(hideStockInventory) end end }
  connect(w, handlers.stock)
end

-- ---------------------------------------------------------------- lifecycle
local function createWindow()
  if alive(window) then return end
  local gi = modules.game_interface
  local parent = gi and gi.getRightPanel and gi.getRightPanel() or nil
  if not alive(parent) then return end
  window = g_ui.loadUI('bagpanel', parent)
  -- always shown, whatever the MiniWindow's saved closed state: setup closes a window saved closed, and a logout hide
  -- saved it so (seen in a local client 2026-11-06). forceOpen makes MiniWindow:close a no-op; the X is hidden
  window.forceOpen = true
  pcall(function() window:setup() end)
  local closeButton = window:getChildById('closeButton')
  if closeButton then closeButton:hide() end
  local grid = child('grid')
  if grid then connect(grid, { onGeometryChange = function() M.refresh() end }) end
  buildEquip()
  buildTabs()
end

local function ensureMain()
  if not g_game.isOnline() or mainContainer() or restoring() then return end
  local player = g_game.getLocalPlayer()
  local item = player and player:getInventoryItem(C.BACK_SLOT)
  if item and item.isContainer and item:isContainer() then g_game.open(item) end
end

local function onGameStart()
  bagMemo, hiddenWindows, selected, sorting = {}, {}, 'main', nil
  createWindow()
  if not alive(window) then return end
  buildEquip()
  window:open()
  hideStockInventory()
  watchStock()
  moveControls()
  scheduleEvent(safe('controls', function() hideStockInventory() moveControls() end), 1500)
  scheduleEvent(safe('tabs', buildTabs), 1500)
  -- the login restore (game_chaoslayout) opens the containers of the last session first; the main backpack opens here
  -- when it did not
  scheduleEvent(safe('ensure', function() ensureMain() hideAllInPanel() M.refresh() end), 2500)
  if cycle then removeEvent(cycle) end
  ensureTries = 0
  cycle = cycleEvent(safe('money', function()
    if not alive(window) then return end
    drawMoney()
    -- the first open at login can be lost (seen in a client: the panel stayed empty); a few more tries, then none
    if ensureTries < 5 and not mainContainer() then
      ensureTries = ensureTries + 1
      ensureMain()
    end
  end), 2000)
  M.refresh()
end

local function onGameEnd()
  sorting = nil
  if cycle then removeEvent(cycle) cycle = nil end
  bagMemo, hiddenWindows = {}, {}
  clearGrid()
  if alive(window) then window:hide() end
end

local function onInventoryChange(player, slot)
  if equip[slot] then safe('equip', drawEquipSlot)(slot) end
  M.refresh()
end

local function onOutfitChange(creature)
  if creature == g_game.getLocalPlayer() then safe('outfit', drawOutfit)() end
end

function M.init()
  handlers.container = {
    onOpen = safe('open', onOpen), onClose = safe('close', onClose),
    onAddItem = safe('add', onAdd), onRemoveItem = safe('remove', onRemove), onUpdateItem = safe('update', onChange),
  }
  connect(Container, handlers.container)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  connect(g_game, handlers.game)
  handlers.player = { onInventoryChange = safe('inventory', onInventoryChange) }
  connect(LocalPlayer, handlers.player)
  handlers.creature = { onOutfitChange = safe('outfit', onOutfitChange) }
  connect(Creature, handlers.creature)
  if g_game.isOnline() then addEvent(handlers.game.onGameStart) end
end

function M.terminate()
  disconnect(Container, handlers.container)
  disconnect(g_game, handlers.game)
  disconnect(LocalPlayer, handlers.player)
  disconnect(Creature, handlers.creature)
  local stock = stockWindow()
  if stock and handlers.stock then disconnect(stock, handlers.stock) end
  restoreControls()
  if stock then stock:show() end
  if cycle then removeEvent(cycle) cycle = nil end
  showAllHidden()
  if alive(window) then window:destroy() end
  window = nil
  handlers = {}
end

-- ---------------------------------------------------------------- module functions (bagpanel.otui, the top menu, game_bagpanel.otmod)
function init() M.init() end
function terminate() M.terminate() end
function sort() M.sort() end
function selectPage(key) M.selectPage(key) end
