-- game_bagpanel (O420): one inventory panel in the right side panel instead of a window per backpack. Owner request
-- 2026-11-06 ("conseguimos fazer isso com as nossas bags?"). Rules in bagpanel_core.lua (tested by
-- bagpanel_core_test.lua); the tabs, the grid and the page buttons are drawn from bagpanel.otui.
--  * Equip tab: the equipment slots (UIItem widgets on the slot positions, so drag and drop, the right-click menu
--    and the rich tooltip of game_itemtooltip work as in the classic windows), the fight controls of the stock
--    window, gold counted from the open containers and the Chaos Coins of game_shop.
--  * The grid mirrors one container: page 1 is the main backpack (the container of inventory slot 3), every bag in it
--    is another page. A bag page opens the bag with g_game.open on its item and reuses the container id of the bag
--    shown before, so at most one bag is open for the panel.
--  * The purse (O492, the engine's store inbox, inventory slot 11) is a page too, after the backpack's bags, and once it
--    is open every bag in it (Loot Bag, the pouches) is a page of its own. The panel holds at most four containers open:
--    the backpack, one bag of it, the purse, one bag of the purse (C.MAX_OPEN, 5 with the Loot Bag section). Their stock windows are hidden.
--  * The Loot Bag (O516) is the one bag that is no page: its button shows or hides a section under the grid of the page shown
--    (the backpack stays), 20 slots at a time with arrows (C.lootView). The engine pages it by 250 (server src-patch 0081):
--    the arrows ask for the next engine page with g_game.seekInContainer. Sort does not touch it (the server keeps it in
--    rarity order).
--  * A drop on a page button moves the item into that container (C.dropTarget). Cells carry the container slot position, so a drop
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
local bagMemo = {}      -- container id -> { fam = 'main' | 'purse', slot = index in that container, id = the bag's item id }
local purseCid = nil    -- the container id the purse is open in
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
local lootShown = false     -- the Loot Bag section is shown (O516)
local lootWant = 0          -- the client page of the Loot Bag asked for (C.lootView)
local lootSeek = nil        -- the engine page (first index) asked from the server, until it arrives
local lootCells, lootCellsFor = {}, nil

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

local function purseContainer()
  for _, c in ipairs(containers()) do
    if C.classify(keyOf(c)) == 'purse' then return c end
  end
  return nil
end

local function purseItem()
  local player = g_game.isOnline() and g_game.getLocalPlayer() or nil
  return player and player:getInventoryItem(C.PURSE_SLOT) or nil
end

local function bagItemId(c)
  local ok, item = pcall(function() return c:getContainerItem() end)
  if ok and item then return item:getId() end
  return nil
end

-- the open bag of family `fam` ('main': the backpack, 'purse') that belongs to page `slot`; the Loot Bag (loot) is no page
local function bagContainer(fam, slot, loot)
  for _, c in ipairs(containers()) do
    local m = bagMemo[c:getId()]
    if m and m.fam == fam and m.slot == slot and (m.loot == true) == (loot == true) then return c end
  end
  return nil
end

-- the client ids the server named for the pouches (game_pouches), nil before they came: C.isLootBag then uses its own
local function lootIds()
  local p = modules.game_pouches
  if p and type(p.getState) == 'function' then
    local ok, st = pcall(p.getState)
    if ok and type(st) == 'table' then return st.ids end
  end
  return nil
end

local function lootContainer()
  for _, c in ipairs(containers()) do
    local m = bagMemo[c:getId()]
    if m and m.loot then return c end
  end
  return nil
end

-- the slots of a container as the core wants them
local function containerItems(main)
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
  -- only the slots in use and a spare row (O557): a rift bag or a pouch has 36 slots and more, a wall of empty cells
  local cols = C.columns(grid:getWidth(), C.CELL, 2)
  local used = C.usedSlots(cap, function(i) return c:getItem(i) end)
  local vis = C.visibleSlots(cap, used, cols)
  local key = c:getId() .. ':' .. vis
  if cellsFor ~= key then
    grid:destroyChildren()
    cells = {}
    for i = 0, vis - 1 do
      local w = g_ui.createWidget('BagPanelCell', grid)
      w:setId('slot' .. i)
      w.position = slotPosition(c, i)
      cells[i + 1] = w
    end
    cellsFor = key
  end
  for i = 0, vis - 1 do
    local w = cells[i + 1]
    if alive(w) then
      local item = c:getItem(i)
      w:setItem(item)
      decorate(w, item)
    end
  end
  local height = C.gridHeight(vis, cols, C.CELL, 2)
  if grid:getHeight() ~= height then grid:setHeight(height) end
  if empty then empty:setVisible(used == 0) end
end

-- the Loot Bag section (O516): a header (name and items, arrows, hide) and a grid of at most C.LOOT_SLOTS slots under the grid
-- of the page shown. The cells carry the slot position inside the engine page, as the main grid's do.
local LOOT_HEADER = 40

local function clearLoot()
  local lg = child('lootGrid')
  if lg then lg:destroyChildren() end
  lootCells, lootCellsFor = {}, nil
end

local function lootCounts(c)
  local cap = c:getCapacity()
  local first, size = 0, 0
  if c.getFirstIndex then
    local ok, v = pcall(c.getFirstIndex, c)
    if ok and tonumber(v) then first = tonumber(v) end
  end
  local paged = false
  if c.hasPages then
    local ok, v = pcall(c.hasPages, c)
    paged = ok and v == true
  end
  if paged and c.getSize then
    local ok, v = pcall(c.getSize, c)
    if ok and tonumber(v) then size = tonumber(v) end
  else
    for i = 0, cap - 1 do
      if c:getItem(i) then size = i + 1 end
    end
    first = 0
  end
  return cap, first, size
end

local function drawLoot()
  local section, lg = child('lootSection'), child('lootGrid')
  if not section or not lg then return end
  local c = lootShown and lootContainer() or nil
  if not c then
    clearLoot()
    section:setVisible(false)
    section:setHeight(0)
    section:setMarginTop(0)
    return
  end
  local cap, first, size = lootCounts(c)
  -- the engine page the asked client page lives in: ask the server for it once (the answer is a new open of the bag)
  local want = C.lootView(lootWant, size, cap)
  if first == want.seek then
    lootSeek = nil
  elseif lootSeek ~= want.seek and g_game.seekInContainer then
    lootSeek = want.seek
    pcall(g_game.seekInContainer, c:getId(), want.seek)
  end
  local view = C.lootView(C.lootPageFor(lootWant, first, size, cap), size, cap)
  -- the slots of the page in use and a spare row, not twenty empty cells under a bag with three items (O557)
  local lcols = C.columns(lg:getWidth(), C.CELL, 2)
  local onPage = math.max(math.min(size - first - view.first, view.count), 0)
  local shown = C.visibleSlots(view.count, onPage, lcols, 1)
  local key = c:getId() .. ':' .. first .. ':' .. view.first .. ':' .. shown
  if lootCellsFor ~= key then
    lg:destroyChildren()
    lootCells = {}
    for j = 0, shown - 1 do
      local w = g_ui.createWidget('BagPanelCell', lg)
      w:setId('lslot' .. j)
      w.position = slotPosition(c, view.first + j)
      lootCells[j + 1] = w
    end
    lootCellsFor = key
  end
  for j = 0, shown - 1 do
    local w = lootCells[j + 1]
    if alive(w) then
      local item = c:getItem(view.first + j)
      w:setItem(item)
      decorate(w, item)
    end
  end
  local gh = C.gridHeight(shown, lcols, C.CELL, 2)
  if lg:getHeight() ~= gh then lg:setHeight(gh) end
  local title, pageLabel = child('lootTitle'), child('lootPage')
  if title then
    -- the title has its own row: the whole text, or cut with "..." when the panel is narrower than it needs (O557)
    local full = tr('Loot Bag: %d items', size)
    local font = g_fonts and g_fonts.getFont and g_fonts.getFont('verdana-11px-antialised') or nil
    local room = title:getWidth()
    if font and font.calculateTextRectSize and room > 0 then
      full = C.elide(full, room, function(t) return font:calculateTextRectSize(t).width end)
    end
    title:setText(full)
    title:setTooltip(tr('Loot Bag: %d items', size))
  end
  if pageLabel then
    pageLabel:setText(C.pageText(view.page + 1, view.pages))
    pageLabel:setTooltip(tr('Page %d of %d', view.page + 1, view.pages))
  end
  local prev, nxt = child('lootPrev'), child('lootNext')
  if prev then prev:setEnabled(view.page > 0) end
  if nxt then nxt:setEnabled(view.page < view.pages - 1) end
  section:setMarginTop(4)
  section:setHeight(LOOT_HEADER + 2 + gh)
  section:setVisible(true)
end

-- the border of the page buttons of the purse family: a brown frame, so they read as another place than the backpack's
local PURSE_BORDER = '#7a5a3a'

local function restoring()
  local layout = ChaosLayout
  return layout and layout.Containers and layout.Containers.busy == true
end

-- ---------------------------------------------------------------- pinned bags (O557)
-- A pinned bag stays open: no other bag takes its place (C.previousFor and C.superseded skip it) and it opens again after
-- a login. Remembered per character in g_settings "chaosBagPins_<name>" as the keys of C.pinKey (the bag's item id and its
-- number among the bags of that id: it does not move when items come in front). At most C.MAX_PINS; the backpack itself is
-- always open and cannot be pinned. The Pin button pins the page shown, a right click on a bag button pins that bag.
local pins = {}
local pinPhase = false      -- the login reopen of the pins is running: what it opens is no page change
local pinEvent = nil
local pinAsked = {}         -- pin key -> the tick it was asked for

local function charName()
  local ok, name = pcall(function()
    if g_game and g_game.isOnline and g_game.isOnline() then return g_game.getCharacterName() end
    return ''
  end)
  return ok and type(name) == 'string' and name or ''
end

local function pinSettingKey()
  return 'chaosBagPins_' .. charName()
end

local function loadPins()
  local ok, v = pcall(g_settings.getString, pinSettingKey())
  pins = C.decodePins(ok and v or '')
end

local function savePins()
  pcall(g_settings.set, pinSettingKey(), C.encodePins(pins))
  if g_settings.save then pcall(g_settings.save) end
end

-- the pin key of a bag of family `fam` at `slot`, from the parent container as it is now
local function pinKeyOf(fam, slot)
  local parent = fam == 'purse' and purseContainer() or mainContainer()
  if not parent or not slot then return nil end
  return C.pinKey(fam, slot, containerItems(parent))
end

-- the pin key of a page: nil for the backpack
local function pinKeyOfPage(key)
  local kind, slot = C.parseKey(key)
  if kind == 'purse' then return 'purse' end
  if kind == 'bag' or kind == 'pbag' then return pinKeyOf(C.family(kind), slot) end
  return nil
end

local function refreshPinned()
  for _, m in pairs(bagMemo) do
    m.pinned = C.pinned(pins, pinKeyOf(m.fam, m.slot)) or nil
  end
end

function M.togglePin(key)
  local pk = pinKeyOfPage(key or selected)
  if not pk then return message(tr('The backpack is always open. Pin a bag or the purse.')) end
  local list, on, why = C.togglePin(pins, pk)
  if why == 'full' then return message(tr('You can pin up to %d bags.', C.MAX_PINS)) end
  pins = list
  savePins()
  if on then pinAsked[pk] = nil end
  M.refresh()
end

-- the login reopen: every few seconds, once the layout restore is done and the backpack is open, the next pinned bag that is
-- not open is opened (the purse first: its bags need it). Stops when nothing is left to open for a few ticks.
local function stopPins()
  if pinEvent then removeEvent(pinEvent) pinEvent = nil end
  pinPhase = false
end

local function startPins()
  stopPins()
  if #pins == 0 then return end
  pinPhase, pinAsked = true, {}
  local tick, idle = 0, 0
  pinEvent = cycleEvent(safe('pins', function()
    tick = tick + 1
    if not alive(window) or not g_game.isOnline() then return stopPins() end
    if restoring() then return end
    local main, purseC = mainContainer(), purseContainer()
    if not main then return end
    local open = {}
    for _, m in pairs(bagMemo) do
      local k = pinKeyOf(m.fam, m.slot)
      if k and C.pinned(pins, k) then open[k] = true end
    end
    for k, t in pairs(pinAsked) do
      if tick - t < 4 then open[k] = true end
    end
    local askedPurse = pinAsked.purse and tick - pinAsked.purse < 4
    local act = C.nextPinOpen(pins, { mainItems = containerItems(main),
      purseItems = purseC and containerItems(purseC) or nil, purseOpen = purseC ~= nil or askedPurse == true, open = open })
    if not act then
      idle = idle + 1
      if idle >= 4 or tick > 40 then stopPins() end
      return
    end
    idle = 0
    pinAsked[act.kind == 'purse' and 'purse' or act.key] = tick
    if act.kind == 'purse' then
      local item = purseItem()
      if item then g_game.use(item) end
    else
      local parent = act.kind == 'pbag' and purseC or main
      local item = parent and parent:getItem(act.slot)
      if item then g_game.open(item) end
    end
  end), 1500)
end

-- the tooltip of a page button: the backpack, the purse, a bag by its own name (the item's name the client has, O557), else
-- "Bag N" by its place in its container
local function itemNames(item)
  local names = {}
  if item then
    local ok, name = pcall(function() return item:getName() end)
    if ok then names[#names + 1] = name end
    local okM, market = pcall(function() local m = item:getMarketData() return m and m.name end)
    if okM then names[#names + 1] = market end
  end
  return names
end

local function pageTip(p, num, items, pinned)
  local tip
  if p.key == 'main' then tip = tr('Backpack')
  elseif p.key == 'purse' then tip = tr('Purse')
  else
    local name
    for _, item in ipairs(items) do
      name = C.bagName(itemNames(item))
      if name then break end
    end
    tip = name and tr(name) or tr('Bag %d', num)
  end
  if pinned then tip = tr('%s (pinned)', tip) end
  return tip
end

local function drawPages(pages, main)
  local row = child('pages')
  if not row then return end
  row:destroyChildren()
  local n = 0
  local nums = { main = 0, purse = 0 }
  local pitem = purseItem()
  local purseC = purseContainer()
  for _, p in ipairs(pages) do
    n = n + 1
    local w = g_ui.createWidget('BagPanelPage', row)
    w.pageKey = p.key
    w.pageLoot = p.loot == true
    local id = p.id
    if p.key == 'purse' then id = pitem and pitem:getId() or nil end
    if not id and p.key == 'main' then id = main and bagItemId(main) end
    if id then w:setItemId(id) end
    if p.slot then nums[p.fam] = nums[p.fam] + 1 end
    local parent = p.slot and (p.fam == 'purse' and purseC or main) or nil
    local real = parent and parent:getItem(p.slot) or nil
    local pk = pinKeyOfPage(p.key)
    local isPinned = pk ~= nil and C.pinned(pins, pk)
    w:setTooltip(pageTip(p, p.slot and nums[p.fam] or 0, { real, w:getItem() }, isPinned))
    if isPinned then
      local mark = g_ui.createWidget('BagPanelPinMark', w)
      mark:addAnchor(AnchorTop, 'parent', AnchorTop)
      mark:addAnchor(AnchorRight, 'parent', AnchorRight)
      mark:setMarginTop(1)
      mark:setMarginRight(1)
    end
    local border = p.fam == 'purse' and PURSE_BORDER or '#00000000'
    -- the Loot Bag button is lit while its section shows; it is never "the page"
    local lit = p.loot and (lootShown and lootContainer() ~= nil) or (not p.loot and p.key == selected)
    w:setBorderColor(lit and '#f6cf72' or border)
    w.onMouseRelease = function(widget, pos, button)
      if button == MouseRightButton then M.togglePin(widget.pageKey) return true end
      if button ~= MouseLeftButton then return false end
      if widget.pageLoot then M.toggleLoot() else M.selectPage(widget.pageKey) end
      return true
    end
    -- a drop on a page button moves the item into that container (the cells take drops the same way: the base UIItem
    -- refuses a virtual one, so the button answers the drop itself)
    w.onDrop = function(widget, dropped, mousePos)
      return M.dropOnPage(widget.pageKey, dropped)
    end
  end
  local cols = C.columns(row:getWidth(), 26, 2)
  local height = C.gridHeight(n, cols, 26, 2)
  if row:getHeight() ~= height then row:setHeight(height) end
end

function M.drawPinButton()
  local b = child('pinButton')
  if not b then return end
  local pk = pinKeyOfPage(selected)
  b:setEnabled(pk ~= nil)
  b:setColor((pk and C.pinned(pins, pk)) and '#f6cf72' or '#d6c9ae')
end

local function pageContainer(main, pages)
  local kind, slot = C.parseKey(selected)
  if kind == 'main' then return main end
  if kind == 'purse' then return purseContainer() end
  if kind == 'bag' then return bagContainer('main', slot) end
  if kind == 'pbag' then return bagContainer('purse', slot) end
  return nil
end

function M.draw()
  queued = false
  if not alive(window) then return end
  local main = mainContainer()
  local purseC = purseContainer()
  local bags = main and C.bagSlots(containerItems(main)) or {}
  local pbags = purseC and C.bagSlots(containerItems(purseC)) or {}
  -- the purse page shows whenever the character has a purse; its bags only while the purse is open (the client does not
  -- know what is in it before)
  local pages = C.pages(bags, purseItem() and { bags = pbags } or nil, lootIds())
  -- the bags opened for the panel: still a bag of the same item where they were, else the nearest of its kind
  local bagsOf = { main = bags, purse = pbags }
  for cid, m in pairs(bagMemo) do
    local c = g_game.getContainer(cid)
    if not c then
      bagMemo[cid] = nil
    else
      local list = bagsOf[m.fam] or {}
      local here = false
      for _, b in ipairs(list) do
        if b.slot == m.slot and b.id == m.id then here = true end
      end
      if not here then
        local s = C.rematch(m.slot, m.id, list)
        if s then m.slot = s else bagMemo[cid] = nil end
      end
    end
  end
  selected = C.validKey(pages, selected)
  local c = pageContainer(main, pages)
  drawGrid(c)
  drawLoot()
  refreshPinned()
  drawPages(pages, main)
  drawMoney()
  M.drawSortButton()
  M.drawPinButton()
  -- the window grows to show the whole layout: the side panel's fitting shrank it when a stock window opened beside it
  -- and the pages and Sort went under the edge (seen in a client)
  addEvent(safe('fit', function()
    local buttons = child('buttons')
    if not (alive(window) and buttons) then return end
    local need = buttons:getRect().y + buttons:getHeight() + 10 - window:getRect().y
    -- never past the room the side panel has left: taller, its fitAll closes other windows, the layout restore opens
    -- them again and this grows again, so windows opened and closed in a loop on a phone (owner 2026-11-06)
    local room = nil
    local parent = window:getParent()
    if alive(parent) and parent:getClassName() == 'UIMiniWindowContainer' then
      local used = 0
      for _, c in ipairs(parent:getChildren()) do
        if c ~= window and c:isVisible() then used = used + c:getHeight() end
      end
      room = parent:getHeight() - parent:getPaddingTop() - parent:getPaddingBottom() - used
    end
    local h = C.fitHeight(window:getHeight(), need, room)
    -- and the window is no taller than its content: no empty framed area under the buttons (O557)
    if not h and window:getHeight() > need + 2 then h = need end
    if h then window:setHeight(h) end
  end))
end

-- the Purse button (O420 follow-up, 2026-11-09; a page of the panel since O492): the stock window's purse button went
-- with the stock window and the store's purchases are delivered to the purse, so the panel has its own. It shows the
-- purse as the page of the grid. The purse opens as any container does (use the item of the purse slot); its stock
-- window is hidden like the backpack's (onOpen). A use on a container that is open closes it on the server, so an open
-- purse is only selected.
function M.openPurse()
  local purse = purseItem()
  if not purse then return message(tr('You have no purse.')) end
  if sorting then sorting = nil end
  selected = 'purse'
  if not purseContainer() then g_game.use(purse) end
  M.refresh()
end

function M.purseButton()
  return child('purseButton')
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
local function onOpen(c, previous)
  if not c then return end
  local kind, slot = C.classify(keyOf(c))
  if not kind then return end
  hideStock(c)
  local cid = c:getId()
  if kind == 'purse' then purseCid = cid end
  local loot = false
  local quiet = false    -- opened by the login reopen of a pinned bag: no page change, no Loot Bag section
  if kind == 'bag' or kind == 'pbag' then
    local fam = C.family(kind)
    local id = bagItemId(c)
    loot = kind == 'pbag' and C.isLootBag(id, lootIds())
    -- a bag opened with an id of its own (a double click on it in the grid) takes the place of the one open before:
    -- one bag stays open per family, so the server's limit of open containers is not eaten (the login restore keeps
    -- what it opens). The Loot Bag (O516) is a section of its own: it neither closes the other bag nor is closed by it
    local pin = not loot and C.pinned(pins, pinKeyOf(fam, slot)) or false
    if not restoring() and not loot and not pin then
      for _, old in ipairs(C.superseded(bagMemo, cid, fam)) do
        local oc = g_game.getContainer(old)
        bagMemo[old] = nil
        if oc then pcall(g_game.close, oc) end
      end
    end
    bagMemo[cid] = { fam = fam, slot = slot, id = id, loot = loot or nil, pinned = pin or nil }
    if loot and C.pinned(pins, pinKeyOf(fam, slot)) then bagMemo[cid].pinned = true end
    if bagMemo[cid].pinned and pinPhase then quiet = true end
  end
  -- (the server answers a seek with a new open of the same bag: the page asked for, lootWant, stays)
  if loot then lootShown = C.lootShownOnOpen(lootShown, restoring() or quiet) end
  -- what the player opened is the page shown; the ones the login restore opens are not; the Loot Bag is no page
  selected = C.selectOnOpen(selected, kind, slot, restoring() or quiet, loot)
  M.refresh()
end

local function onClose(c)
  if not c then return end
  -- a bag opened into the id of the bag shown before: the old one's close comes after the new one's open
  local now = g_game.getContainer(c:getId())
  if now and now ~= c then return M.refresh() end
  local cid = c:getId()
  hiddenWindows[cid] = nil
  local m = bagMemo[cid]
  if m then
    bagMemo[cid] = nil
    if m.loot then
      -- the Loot Bag closed (a use on it, the purse closing): the section goes, the page shown stays
      lootShown, lootWant, lootSeek = false, 0, nil
    else
      selected = C.selectOnClose(selected, m.fam == 'purse' and 'pbag' or 'bag', m.slot)
    end
  end
  if cid == purseCid then
    purseCid = nil
    selected = C.selectOnClose(selected, 'purse')
  end
  M.refresh()
end

local function isKind(c, want)
  return C.classify(keyOf(c)) == want
end

-- an item came into / left the backpack or the purse: the bags opened for the panel moved with the list
local function shiftAll(fam, slot, add)
  for cid, m in pairs(bagMemo) do
    if m.fam == fam then
      local s = add and C.shiftAdd(m.slot, slot) or C.shiftRemove(m.slot, slot)
      if s then m.slot = s else bagMemo[cid] = nil end
    end
  end
  selected = C.shiftSelected(selected, fam, slot, add)
end

local function onAdd(c, slot)
  if c then
    if isKind(c, 'main') then shiftAll('main', slot, true)
    elseif isKind(c, 'purse') then shiftAll('purse', slot, true) end
  end
  M.refresh()
end

local function onRemove(c, slot)
  if c then
    if isKind(c, 'main') then shiftAll('main', slot, false)
    elseif isKind(c, 'purse') then shiftAll('purse', slot, false) end
  end
  M.refresh()
end

local function onChange()
  M.refresh()
end

-- ---------------------------------------------------------------- pages and sort
function M.selectPage(key)
  if sorting then sorting = nil end
  local kind, slot = C.parseKey(key)
  if kind == 'main' then
    selected = 'main'
    if not mainContainer() then
      local player = g_game.getLocalPlayer()
      local item = player and player:getInventoryItem(C.BACK_SLOT)
      if item then g_game.open(item) end
    end
    return M.refresh()
  end
  if kind == 'purse' then return M.openPurse() end
  -- a bag page: the bag is a container item of the backpack ('bag') or of the purse ('pbag'), which must be open
  local fam = C.family(kind)
  local parent = fam == 'purse' and purseContainer() or mainContainer()
  if not slot or not parent then return end
  -- the Loot Bag is a section, not a page (O516)
  if fam == 'purse' then
    local item = parent:getItem(slot)
    if item and C.isLootBag(item:getId(), lootIds()) then return M.toggleLoot(slot) end
  end
  selected = key
  if not bagContainer(fam, slot) then
    local item = parent:getItem(slot)
    if item then
      -- the bag shown before gives its container id to this one: at most one bag open per family
      local previous = nil
      local pcid = C.previousFor(bagMemo, fam)
      if pcid then previous = g_game.getContainer(pcid) end
      g_game.open(item, previous)
    end
  end
  M.refresh()
end

-- the Loot Bag button (O516): shows the Loot Bag as the section under the grid, or hides it again (the bag stays open, its
-- stock window hidden). The bag opens as any container does when it is not open yet. `slot`: its place in the purse
-- (the page button knows it; nil: look for it).
function M.toggleLoot(slot)
  if sorting then sorting = nil end
  if lootShown and lootContainer() then
    lootShown = false
    return M.refresh()
  end
  lootShown, lootWant, lootSeek = true, 0, nil
  if not lootContainer() then
    local parent = purseContainer()
    if not parent then return end
    if not slot then
      for _, b in ipairs(C.bagSlots(containerItems(parent))) do
        if C.isLootBag(b.id, lootIds()) then slot = b.slot break end
      end
    end
    local item = slot and parent:getItem(slot)
    if not item then lootShown = false return end
    g_game.open(item)
  end
  M.refresh()
end

function M.lootArrow(delta)
  local c = lootContainer()
  if not c then return end
  local cap, first, size = lootCounts(c)
  local now = C.lootPageFor(lootWant, first, size, cap)
  lootWant = C.lootView(now + delta, size, cap).page
  lootSeek = nil
  M.refresh()
end

-- an item dropped on a page button goes into that container (C.dropTarget). A stack asks how many, as a drop on a cell does
function M.dropOnPage(key, dropped)
  local item = dropped and dropped.currentDragThing
  if not item or not item.isItem or not item:isItem() then return false end
  local main, purseC = mainContainer(), purseContainer()
  local to = C.dropTarget(key, { main = main and main:getId() or nil, purse = purseC and purseC:getId() or nil })
  if not to then return false end
  local from = item:getPosition()
  if C.samePlace(from, to) then return false end
  local count = item:getCount()
  local gi = modules.game_interface
  if count > 1 and gi and type(gi.moveStackableItem) == 'function' then
    gi.moveStackableItem(item, to)
  else
    g_game.move(item, to, count)
  end
  return true
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

-- the Sort button is off on the purse page: the store inbox takes no move of a plain item (C.sortBlock)
function M.drawSortButton()
  local b = child('sortButton')
  if not b then return end
  local why = C.sortBlock(selected)
  b:setEnabled(why == nil)
  if why then
    b:setTooltip(tr('The purse cannot be sorted: the game does not let items move inside it.'))
  else
    b:setTooltip(tr('Puts the items of this page in order: by item, then the bigger stack first.'))
  end
end

function M.sort()
  if sorting or not g_game.isOnline() then return end
  if C.sortBlock(selected) then
    return message(tr('The purse cannot be sorted: the game does not let items move inside it.'))
  end
  local c = pageContainer(mainContainer())
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
-- The panel shows the equipment, so the stock window is hidden. Its controls move into the panel, laid out as in that
-- window: the same widgets, so game_inventory keeps updating them and their clicks still reach g_game. They go back
-- on terminate. Right of the equipment, at { x, y } in the controls panel: the fight modes in one column, stand,
-- chase and the PvP modes button in the next, safe fight, Stop and the condition icons under them. Soul and capacity
-- sit in the empty corners of the last equipment row, under the ring and the badge (the stock window's places).
local CONTROLS = {
  fightOffensiveBox = { 0, 0 }, fightBalancedBox = { 0, 22 }, fightDefensiveBox = { 0, 44 },
  chaseModeBoxStand = { 22, 0 }, chaseModeBoxChase = { 22, 22 }, openPvpButton = { 22, 44 },
  safeFightBox = { 0, 68 }, stopButton = { 0, 92 }, conditionPanel = { 0, 112 },
  pvpModesPanel = { 0, 68 },   -- opens over safe fight and Stop
}
local CORNERS = { soulLabel = 0, capLabel = 2 }   -- equipment column of the last row
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

-- w goes into parent, its top left at (x, y) of target's top left
local function place(w, parent, target, x, y)
  if w:getParent() ~= parent then
    moved[w] = moved[w] or w:getParent()
    w:setParent(parent)
  end
  w:breakAnchors()
  w:setMargin(0)
  w:addAnchor(AnchorLeft, target, AnchorLeft)
  w:addAnchor(AnchorTop, target, AnchorTop)
  w:setMarginLeft(x)
  w:setMarginTop(y)
end

local function moveControls()
  local stock, controls, equipPanel = stockWindow(), child('controls'), child('equipPanel')
  if not stock or not controls or not equipPanel then return end
  for id, at in pairs(CONTROLS) do
    local w = stock:recursiveGetChildById(id) or controls:getChildById(id)
    if alive(w) then place(w, controls, 'parent', at[1], at[2]) end
  end
  local stop = controls:getChildById('stopButton')
  if alive(stop) then stop:setWidth(42) end
  local cond = controls:getChildById('conditionPanel')
  if alive(cond) then cond:setWidth(controls:getWidth()) end
  local modes = controls:getChildById('pvpModesPanel')
  if alive(modes) then modes:raise() end
  local step = C.CELL + 3
  for id, col in pairs(CORNERS) do
    local w = stock:recursiveGetChildById(id) or equipPanel:getChildById(id)
    if alive(w) then place(w, equipPanel, 'slots', col * step, 3 * step + 7) end
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
  handlers.stock = { onVisibilityChange = function(widget, visible)
    if visible then addEvent(hideStockInventory) end
  end }
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
  local lt = child('lootTitle')
  if lt then connect(lt, { onGeometryChange = function() M.refresh() end }) end
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
  bagMemo, hiddenWindows, selected, sorting, purseCid = {}, {}, 'main', nil, nil
  stopPins()
  lootShown, lootWant, lootSeek = false, 0, nil
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
  loadPins()
  scheduleEvent(safe('pins', startPins), 3500)
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
  stopPins()
  if cycle then removeEvent(cycle) cycle = nil end
  bagMemo, hiddenWindows, purseCid = {}, {}, nil
  lootShown, lootWant, lootSeek = false, 0, nil
  clearLoot()
  clearGrid()
  if alive(window) then window:hide() end
end

local function onInventoryChange(player, slot)
  if equip[slot] then safe('equip', drawEquipSlot)(slot) end
  M.refresh()
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
  if g_game.isOnline() then addEvent(handlers.game.onGameStart) end
end

function M.terminate()
  disconnect(Container, handlers.container)
  disconnect(g_game, handlers.game)
  disconnect(LocalPlayer, handlers.player)
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

-- ---------------------------------------------------------------- module functions (bagpanel.otui, game_bagpanel.otmod)
function init() M.init() end
function terminate() M.terminate() end
function sort() M.sort() end
function openPurse() M.openPurse() end
function getPurseButton() return M.purseButton() end
function selectPage(key) M.selectPage(key) end
function toggleLoot() M.toggleLoot() end
function togglePin() M.togglePin() end
function lootArrow(delta) M.lootArrow(delta) end
