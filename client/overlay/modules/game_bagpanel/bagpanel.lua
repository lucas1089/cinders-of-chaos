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
--  * Quest / Status / Active / Shop link to the windows that exist (C.TABS); a tab with no target is not shown.
--  * The option (g_settings 'chaosBagPanel', on for a new player): Classic button in the panel and the top menu entry
--    Adventure > Inventory panel. Off: the hidden windows come back and the panel hides.
-- Container keys come from game_chaoslayout (ChaosLayout.Containers.keyOf); a container with no key is left alone.
local M = {}
local C = BagPanelCore

local window
local enabled = true
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
  if not alive(window) or not enabled then return end
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
  if not enabled or not c then return end
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
  if enabled and c and isMain(c) then shiftAll(slot, true) end
  M.refresh()
end

local function onRemove(c, slot)
  if enabled and c and isMain(c) then shiftAll(slot, false) end
  M.refresh()
end

local function onChange()
  M.refresh()
end

-- ---------------------------------------------------------------- pages and sort
function M.selectPage(key)
  if not enabled then return end
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
  if not c or not enabled then sorting = nil return end
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
  if not enabled or sorting or not g_game.isOnline() then return end
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
end

-- ---------------------------------------------------------------- the option
function M.isEnabled()
  return enabled
end

local function readOption()
  local ok, v = pcall(function() return g_settings.getBoolean(C.OPTION, true) end)
  return ok and C.isOn(v) or true
end

function M.setEnabled(on)
  on = on and true or false
  pcall(function() g_settings.set(C.OPTION, on) end)
  if on == enabled and alive(window) and window:isVisible() == on then return end
  enabled = on
  sorting = nil
  if not alive(window) then return end
  if on then
    window:show()
    hideAllInPanel()
    M.refresh()
    message(tr('Inventory panel on.'))
  else
    window:hide()
    showAllHidden()
    message(tr('Inventory panel off: backpacks open in their own windows.'))
  end
end

function M.toggle()
  M.setEnabled(not enabled)
end

-- the X of the window: the way back to the classic windows (without it the backpack would have no window at all)
function M.onWindowClose()
  if enabled then M.setEnabled(false) end
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'adventure',
      { text = 'Inventory panel', icon = 'inventory', modules = { 'game_bagpanel' }, fns = { 'toggle' } })
  end
end

-- ---------------------------------------------------------------- lifecycle
local function createWindow()
  if alive(window) then return end
  local gi = modules.game_interface
  local parent = gi and gi.getRightPanel and gi.getRightPanel() or nil
  if not alive(parent) then return end
  window = g_ui.loadUI('bagpanel', parent)
  pcall(function() window:setup() end)
  local grid = child('grid')
  if grid then connect(grid, { onGeometryChange = function() M.refresh() end }) end
  buildEquip()
  buildTabs()
end

local function ensureMain()
  if not enabled or not g_game.isOnline() or mainContainer() or restoring() then return end
  local player = g_game.getLocalPlayer()
  local item = player and player:getInventoryItem(C.BACK_SLOT)
  if item and item.isContainer and item:isContainer() then g_game.open(item) end
end

local function onGameStart()
  enabled = readOption()
  bagMemo, hiddenWindows, selected, sorting = {}, {}, 'main', nil
  createWindow()
  if not alive(window) then return end
  buildEquip()
  addMenu()
  if enabled then window:show() else window:hide() end
  scheduleEvent(safe('tabs', buildTabs), 1500)
  -- the login restore (game_chaoslayout) opens the containers of the last session first; the main backpack opens here
  -- when it did not
  scheduleEvent(safe('ensure', function() ensureMain() hideAllInPanel() M.refresh() end), 2500)
  if cycle then removeEvent(cycle) end
  cycle = cycleEvent(safe('money', function() if enabled and alive(window) then drawMoney() end end), 2000)
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
  enabled = readOption()
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
  if cycle then removeEvent(cycle) cycle = nil end
  showAllHidden()
  if alive(window) then window:destroy() end
  window = nil
  handlers = {}
end

-- ---------------------------------------------------------------- module functions (bagpanel.otui, the top menu, game_bagpanel.otmod)
function init() M.init() end
function terminate() M.terminate() end
function toggle() M.toggle() end
function sort() M.sort() end
function setEnabled(on) M.setEnabled(on) end
function isEnabled() return M.isEnabled() end
function selectPage(key) M.selectPage(key) end
function onWindowClose() M.onWindowClose() end
