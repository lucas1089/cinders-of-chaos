-- Depot tabs and the depot window (server data/scripts/chaos/depot.lua, extended opcode 111, JSON {action, data}).
--   server -> client  tabs {...} (depottabsview.lua) | open {tab, ok, text}
--   client -> server  open {tab} (switch to a tab) | style {tab, name, color} (rename / colour a tab)
--
-- The depot window. When the player opens a depot locker, the locker, its depot chest and one tab box are opened as
-- ordinary containers (the engine's own use packets, so container ids, range checks and every move rule stay the
-- engine's and the server's), but no stock container window is made for them: this module takes them over and shows one
-- centred window with the tab buttons, the active tab's items (normal drag and drop: Item widgets with the slot's
-- position), the counts, and Inbox / Market / Store buttons. A tab switch asks the server first (open {tab}: it checks
-- that the player stands at the locker with the chest open, rate limited), then opens that box into the tab's container
-- id. Walking away closes the containers, and the window with them. game_containers is not changed: its onOpen handler
-- is wrapped (disconnected and called from here for every other container). Without the server's tab list (an old
-- server) every container keeps its stock window.
-- Stock windows of a tab box or the chest (opened while the window is closed) still get the count in their title.

local OPCODE = 111
local V = DepotTabsView

local state = V.newState()
local open = {} -- the containers with a stock window (id -> container), for the titles
local handlers = {}
local reported = {}
local stockOpen -- game_containers' onOpen handler (wrapped)
local W = { } -- the depot window: window, locker, chest, tab (containers), active, pendingChest, pendingTab, asked
local lastTab = 1
local slots = {} -- the grid's Item widgets, by slot (0-based)
local tabButtons = {}
local styleWin, styleTab, styleColor
local swatchButtons = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[depottabs] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function itemIdOf(container)
  local top = container and container:getContainerItem()
  return top and top:getId() or 0
end

local function findItem(container, clientId)
  if not container or not clientId or clientId == 0 then return nil end
  for _, item in ipairs(container:getItems()) do
    if item:getId() == clientId then return item end
  end
  return nil
end

local function openContainerOf(clientId, except)
  for _, c in pairs(g_game.getContainers()) do
    if c and c ~= except and itemIdOf(c) == clientId then return c end
  end
  return nil
end

-- ---------------------------------------------------------------- stock windows: titles and tooltips
local function decorate(container)
  if not container or not container.window then return end
  local topId = itemIdOf(container)
  local tab = V.tabOf(state, topId)
  if tab then
    container.window:setText(V.title(state, tab))
    local color = V.titleColor(state, tab)
    if color then container.window:setColor(color) end
    container.window:setTooltip(V.tooltip(state, tab))
    return
  end
  if not V.isChest(state, topId) or not container.itemsPanel then return end
  for slot = 0, container:getCapacity() - 1 do
    local widget = container.itemsPanel:getChildById('item' .. slot)
    if widget then
      local item = container:getItem(slot)
      local t = item and V.tabOf(state, item:getId())
      if t then
        widget:setOpacity(V.isLocked(state, t) and V.LOCKED_OPACITY or 1)
        widget:setTooltip(V.tooltip(state, t))
        widget.chaosDepotTab = t
      elseif widget.chaosDepotTab then
        widget:setOpacity(1)
        widget:setTooltip('')
        widget.chaosDepotTab = nil
      end
    end
  end
end

local function decorateAll()
  for _, c in pairs(open) do decorate(c) end
end

local function later(container)
  scheduleEvent(safe('decorate', function() decorate(container) end), 30)
end

-- ---------------------------------------------------------------- the window
-- removes the stock window of a container the window takes over
function destroyStock(container)
  local gc = modules.game_containers
  if container.window and gc and gc.destroy then gc.destroy(container) end
end

local function setStatus(text)
  if W.window then W.window.status:setText(text or '') end
end

-- the fill and the text colour of a tab button (also on hover: the label does not get the button's hover style)
local function paintTab(t, b, hovered)
  local c = V.buttonColors(state, t, W.active, hovered)
  b.accent:setVisible(c.fill ~= nil)
  if c.fill then b.accent:setBackgroundColor(c.fill) end
  b.label:setColor(c.text)
  b.label:setShadow(c.shadow)
end

local function renderTabs()
  if not W.window then return end
  for t, b in pairs(tabButtons) do
    if t == 'store' then
      b:setVisible(state.tabs < state.max)
    else
      local label = b.label
      local look = V.button(state, t, W.active, nil, function(text)
        label:setText(text)
        return label:getTextSize().width + 1 -- the shadow
      end)
      label:setText(look.text)
      -- a locked tab: the text centred in the room left of the lock (the label also takes 3 px of the left padding)
      label:setMarginLeft(look.locked and -3 or 0)
      label:setMarginRight(look.locked and 12 or 0)
      b:setChecked(look.checked)
      b:setOpacity(look.opacity)
      b:setTooltip(look.tooltip)
      b.lock:setVisible(look.locked)
      paintTab(t, b, b:isHovered())
    end
  end
end

local function renderGrid()
  if not W.window then return end
  local c = W.tab
  for slot, w in pairs(slots) do
    local item = c and c:getItem(slot) or nil
    w:setItem(item)
    w.position = c and c:getSlotPosition(slot) or nil
    w:setEnabled(c ~= nil)
    if updateFlags then pcall(updateFlags, item, w) end
  end
end

local function renderText()
  if not W.window then return end
  W.window:setText(V.windowTitle(state))
  local tab = W.tab and W.active or nil
  W.window.header:setText(V.header(state, tab))
  W.window.header:setColor(tab and V.accent(state, tab) or V.COLORS.gold)
  local f = V.footer(state, tab)
  W.window.itemsLabel:setText(f.items)
  W.window.itemsLabel:setColor(f.itemsColor)
  W.window.tabsLabel:setText(f.tabs)
  W.window.inboxButton:setEnabled(findItem(W.locker, state.inbox) ~= nil)
  W.window.marketButton:setEnabled(findItem(W.locker, state.market) ~= nil)
  W.window.editButton:setVisible(tab ~= nil)
end

local function render()
  renderTabs()
  renderGrid()
  renderText()
end

local function buildWindow()
  local ok, win = pcall(g_ui.createWidget, 'DepotWindow', rootWidget)
  if not ok or not win then
    g_logger.warning('[depottabs] window: ' .. tostring(win))
    return nil
  end
  win:hide()
  -- the tab buttons
  tabButtons = {}
  for _, cell in ipairs(V.tabCells(state)) do
    local b
    if cell.tab == 'store' then
      b = g_ui.createWidget('DepotStoreButton', win.tabsPanel)
      b.onClick = function() openStore() end
      b:setTooltip(state.hint ~= '' and state.hint or tr('Buy more tabs in the Store.'))
    else
      b = g_ui.createWidget('DepotTabButton', win.tabsPanel)
      local t = cell.tab
      b.onClick = function() selectTab(t) end
      b.onHoverChange = function(widget, hovered) paintTab(t, widget, hovered) end
      b.onMouseRelease = function(widget, mousePos, button)
        if button == MouseRightButton then
          local menu = g_ui.createWidget('PopupMenu')
          if menu.setGameMenu then menu:setGameMenu(true) end
          menu:addOption(tr('Rename...'), function() editTab(t, 'name') end)
          menu:addOption(tr('Colour...'), function() editTab(t, 'color') end)
          menu:display(mousePos)
          return true
        end
        return false
      end
    end
    b:addAnchor(AnchorTop, 'parent', AnchorTop)
    b:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    b:setMarginTop(cell.y)
    b:setMarginLeft(cell.x)
    tabButtons[cell.tab] = b
  end
  -- the item grid
  slots = {}
  local count = math.max(1, state.size)
  for slot = 0, count - 1 do
    local w = g_ui.createWidget('Item', win.gridFrame.grid)
    w:setId('item' .. slot)
    w:setMargin(0)
    slots[slot] = w
  end
  -- a drop between the slots goes to the last slot (the engine then puts it anywhere in the tab)
  win.gridFrame.grid.onDrop = function(self, widget, mousePos)
    local last = slots[count - 1]
    if last and W.tab then return last:onDrop(widget, mousePos, true) end
    return false
  end
  return win
end

local function showWindow()
  if not W.window then
    W.window = buildWindow()
    if not W.window then return false end
  end
  if not W.window:isVisible() then
    W.window:show()
    W.window:raise()
    W.window:focus()
  end
  setStatus('')
  render()
  return true
end

-- close the containers the window holds (not `except`, which the server closed already) and hide the window
local function closeAll(except)
  local list = { W.tab, W.chest, W.locker }
  if W.active then lastTab = W.active end
  W.tab, W.chest, W.locker, W.active, W.pendingChest, W.pendingTab, W.asked = nil, nil, nil, nil, nil, nil, nil
  for _, c in ipairs(list) do
    if c ~= except and c and not c:isClosed() then
      g_game.close(c)
    end
  end
  if W.window then W.window:hide() end
  closeStyle()
end

function closeWindow()
  closeAll(nil)
end

-- ---------------------------------------------------------------- switching tabs
local ASK_TIMEOUT = 1500

-- the tab's box is already open somewhere (a stock window from before): take that container
local function adoptOpenBox(tab)
  local c = openContainerOf(state.ids[tab], W.tab)
  if not c then return false end
  destroyStock(c)
  open[c:getId()] = nil
  if W.tab and not W.tab:isClosed() then g_game.close(W.tab) end
  W.tab, W.active, W.pendingTab = c, tab, nil
  render()
  return true
end

function selectTab(tab)
  if not W.chest then return end
  if W.tab and W.active == tab then return end
  if W.asked and g_clock.millis() - W.asked.at < ASK_TIMEOUT then return end
  if adoptOpenBox(tab) then return end
  W.asked = { tab = tab, at = g_clock.millis() }
  send('open', { tab = tab })
end

local function onOpenAnswer(d)
  local tab = tonumber(d.tab)
  if not W.asked or W.asked.tab ~= tab then return end
  W.asked = nil
  if not d.ok then
    setStatus(d.text or tr('That tab cannot be opened now.'))
    return
  end
  local box = W.chest and findItem(W.chest, state.ids[tab])
  if not box then
    setStatus(tr('That depot tab does not exist.'))
    return
  end
  if adoptOpenBox(tab) then return end
  setStatus('')
  W.active = tab
  W.pendingTab = g_game.open(box, W.tab) -- into the tab's container id (a new one the first time)
  renderTabs()
end

-- ---------------------------------------------------------------- taking containers over
local function adopt(role, container, previous)
  if role == 'locker' then
    if W.locker and W.locker ~= container then closeAll(nil) end
    W.locker = container
    if not showWindow() then return false end
    local chestItem
    for _, item in ipairs(container:getItems()) do
      if V.isChest(state, item:getId()) then chestItem = item break end
    end
    local chest = chestItem and openContainerOf(chestItem:getId(), nil)
    if chest then
      destroyStock(chest)
      open[chest:getId()] = nil
      adopt('chest', chest)
    elseif chestItem then
      W.pendingChest = g_game.open(chestItem)
    end
    return true
  elseif role == 'chest' then
    if W.chest and W.chest ~= container and not W.chest:isClosed() then g_game.close(W.chest) end
    W.chest, W.pendingChest = container, nil
    if not showWindow() then return false end
    if not W.tab then selectTab(V.firstTab(state, W.active or lastTab)) end
    return true
  elseif role == 'tab' then
    if W.tab and W.tab ~= container and W.tab ~= previous and not W.tab:isClosed() and W.tab:getId() ~= container:getId() then
      g_game.close(W.tab)
    end
    W.tab, W.pendingTab = container, nil
    W.active = V.tabOf(state, itemIdOf(container))
    lastTab = W.active or lastTab
    if not showWindow() then return false end
    return true
  end
  return false
end

local function roleOf(container)
  local holdsChest = false
  if V.known(state) then
    for _, item in ipairs(container:getItems()) do
      if V.isChest(state, item:getId()) then holdsChest = true break end
    end
  end
  return V.classify(state, { clientId = itemIdOf(container), holdsChest = holdsChest, id = container:getId(),
    pendingChest = W.pendingChest, pendingTab = W.pendingTab, windowOpen = W.chest ~= nil })
end

local function isOurs(c)
  return c ~= nil and (c == W.locker or c == W.chest or c == W.tab)
end

local function onOpen(container, previous)
  local okRole, role = pcall(roleOf, container)
  if okRole and role then
    local okAdopt, done = pcall(adopt, role, container, previous)
    if okAdopt and done then return end
    if not okAdopt then g_logger.warning('[depottabs] adopt: ' .. tostring(done)) end
  end
  -- not ours: a stock window. When it replaced one of ours (a bag opened from the grid into the tab's id), the stock
  -- window is made new and the window opens its tab again.
  local replaced = isOurs(previous)
  if replaced then
    if previous == W.tab then
      W.tab = nil
      renderGrid()
      renderText()
      local t = W.active
      W.active = nil
      if t then scheduleEvent(function() selectTab(t) end, 50) end
    else
      closeAll(previous)
    end
  end
  if stockOpen then stockOpen(container, (not replaced) and previous or nil) end
  open[container:getId()] = container
  later(container)
end

local function onClose(container)
  open[container:getId()] = nil
  if container == W.locker or container == W.chest then
    closeAll(container)
  elseif container == W.tab then
    W.tab = nil
    renderGrid()
    renderText()
  end
end

local function onChange(container)
  if container == W.tab then
    renderGrid()
  elseif open[container:getId()] then
    later(container)
  end
end

-- ---------------------------------------------------------------- inbox, market, store
function openInbox()
  local item = findItem(W.locker, state.inbox)
  if not item then return end
  local c = openContainerOf(state.inbox, nil)
  if c and c.window then
    c.window:raise()
    return
  end
  g_game.open(item)
end

function openMarket()
  local item = findItem(W.locker, state.market)
  if item then g_game.use(item) end
end

-- the Store at its Depot Tabs category (game_shop: the categories come from the server after it opens)
function openStore()
  local sm = modules.game_shop
  if not sm or not sm.toggle then return end
  if not (sm.shop and sm.shop:isVisible()) then sm.toggle() end
  local tries = 0
  local function pick()
    tries = tries + 1
    local list = sm.shop and sm.shop.categories
    if list then
      for _, child in ipairs(list:getChildren()) do
        if child.name and child.name:getText() == state.store then
          if list:getFocusedChild() ~= child then list:focusChild(child) end
          break
        end
      end
    end
    if tries < 12 then scheduleEvent(pick, 200) end
  end
  scheduleEvent(pick, 200)
end

-- ---------------------------------------------------------------- rename / colour
local function markSwatch(key)
  styleColor = key or ''
  for k, b in pairs(swatchButtons) do b:setChecked(k == styleColor) end
end

function editTab(tab, focus)
  if not tab then return end
  if not styleWin then
    local ok, win = pcall(g_ui.createWidget, 'DepotStyleWindow', rootWidget)
    if not ok or not win then return end
    styleWin = win
  end
  styleTab = tab
  styleWin:setText(tr('Depot Tab') .. ' ' .. tab)
  styleWin.nameEdit:setMaxLength(state.nameMax)
  styleWin.nameEdit:setText(V.customName(state, tab) or '')
  styleWin.error:setText('')
  styleWin.swatches:destroyChildren()
  swatchButtons = {}
  for _, choice in ipairs(V.colorChoices(state)) do
    local b = g_ui.createWidget('DepotSwatch', styleWin.swatches)
    if choice.color then
      b:setBackgroundColor(choice.color)
    else
      b:setBackgroundColor('#1a151a')
      b:setText('-')
      b:setColor(V.COLORS.dim)
    end
    b:setTooltip(choice.name)
    local key = choice.key
    b.onClick = function() markSwatch(key) end
    swatchButtons[key] = b
  end
  markSwatch(state.colors[tab] or '')
  styleWin:show()
  styleWin:raise()
  styleWin:focus()
  if focus ~= 'color' then
    styleWin.nameEdit:focus()
    styleWin.nameEdit:setCursorPos(#styleWin.nameEdit:getText())
  end
end

function editActiveTab()
  editTab(W.active)
end

function saveStyle()
  if not styleWin or not styleTab then return end
  local name, why = V.cleanName(state, styleWin.nameEdit:getText())
  if not name then
    styleWin.error:setText(why)
    return
  end
  send('style', { tab = styleTab, name = name, color = styleColor or '' })
  V.setStyle(state, styleTab, name, styleColor)
  render()
  closeStyle()
end

function closeStyle()
  if styleWin then styleWin:hide() end
  styleTab = nil
end

-- ---------------------------------------------------------------- server messages
local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then return end
  if msg.action == 'tabs' then
    local wasKnown = V.known(state)
    state = V.apply(state, msg.data)
    decorateAll()
    if W.window then render() end
    -- the first tab list after a locker opened with its stock window: take it over now
    if not wasKnown and V.known(state) and not W.locker then
      for _, c in pairs(g_game.getContainers()) do
        if c and roleOf(c) == 'locker' then
          destroyStock(c)
          open[c:getId()] = nil
          adopt('locker', c)
          break
        end
      end
    end
  elseif msg.action == 'open' and type(msg.data) == 'table' then
    onOpenAnswer(msg.data)
  end
end

-- for other modules and tests
function getState()
  return state
end

function getWindow()
  return W
end

local function onGameEnd()
  open = {}
  W.tab, W.chest, W.locker, W.active, W.pendingChest, W.pendingTab, W.asked = nil, nil, nil, nil, nil, nil, nil
  if W.window then W.window:hide() end
  closeStyle()
end

function init()
  g_ui.importStyle('depottabs')
  handlers.opcode = safe('opcode', onExtendedOpcode)
  handlers.container = {
    onClose = safe('close', onClose),
    onSizeChange = safe('size', onChange),
    onRemoveItem = safe('remove', onChange),
    onUpdateItem = safe('update', onChange),
    onAddItem = safe('add', onChange)
  }
  local gc = modules.game_containers
  if gc and gc.onContainerOpen then
    stockOpen = gc.onContainerOpen
    disconnect(Container, { onOpen = stockOpen })
    handlers.container.onOpen = function(container, previous)
      local ok, err = pcall(onOpen, container, previous)
      if not ok then
        if not reported.open then
          reported.open = true
          g_logger.warning('[depottabs] open: ' .. tostring(err))
        end
        if not container.window then stockOpen(container, previous) end
      end
    end
  else
    handlers.container.onOpen = safe('open', function(container)
      open[container:getId()] = container
      later(container)
    end)
  end
  handlers.game = { onGameEnd = safe('end', onGameEnd) }
  ProtocolGame.registerExtendedOpcode(OPCODE, handlers.opcode)
  connect(Container, handlers.container)
  connect(g_game, handlers.game)
end

function terminate()
  disconnect(Container, handlers.container)
  disconnect(g_game, handlers.game)
  if stockOpen then
    connect(Container, { onOpen = stockOpen })
    stockOpen = nil
  end
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  if W.window then W.window:destroy() end
  if styleWin then styleWin:destroy() end
  W, open, handlers, slots, tabButtons, swatchButtons = {}, {}, {}, {}, {}, {}
  styleWin = nil
end
