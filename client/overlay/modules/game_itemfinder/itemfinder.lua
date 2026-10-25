-- Item finder: "where does this drop" (server data/scripts/chaos/itemfinder.lua, extended opcode 155, JSON
-- {action, data}; answers joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  search {q, p} | item {id} | item {cid} | page {id, k, p}
--   server -> client  results {...} | item {...} | page {...} | busy {}   (itemfinderlogic.lua checks them)
-- The window: a search box (type-ahead), the results with their icons and pages, the item with every source by section
-- (monsters and bosses with the chance, Chaos drops, chests and rewards, recipes, NPC shops with the town, the store,
-- the Gambler, gathering) and what it is used for (recipes, NPCs that buy it). A linked item (a recipe's product or
-- material) opens on a click; Back / Backspace goes back. The Codex button opens the item's Codex page when it has one.
-- Opened from the menu (Economy > Item Finder), the right-click menu of an item (inventory, containers, the map:
-- "Where to find"), a right-click on an item of the market or the loot channel (attach), and the Codex
-- ("Where to find" on an item's page). Logic without client API: itemfinderlogic.lua (itemfinderlogic_test.lua).

local L = ItemFinderLogic
local OPCODE = L.OPCODE

local window
local handlers = {}
local reported = {}
local results          -- the last results (L.results)
local item             -- the item shown (L.item)
local history = {}     -- {id, cid} of the items before (links)
local lastSent         -- the last search text sent
local searchEvent, resendEvent
local codexMap         -- server id -> Codex entry id (built on first use)
local hooked = false

local function alive(w)
  return w ~= nil and w ~= false and not w:isDestroyed()
end

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[itemfinder] ' .. name .. ': ' .. tostring(res))
      end
      return false
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

-- a request that waits for its answer: the server drops requests that come too fast, so one without an answer after
-- L.RESEND_MS goes out once more (any answer clears it)
local pending
local function request(action, data)
  pending = { action = action, data = data }
  send(action, data)
  removeEvent(resendEvent)
  resendEvent = scheduleEvent(function()
    resendEvent = nil
    if pending and pending.action == action and pending.data == data then
      pending = nil
      send(action, data)
    end
  end, L.RESEND_MS)
end

local function setStatus(text)
  if alive(window) then window.status:setText(text or '') end
end

local function setIcon(widget, cid)
  if L.validClientId(cid) then
    widget:setItemId(cid)
    widget:setVisible(true)
  else
    widget:setItemId(0)
  end
end

-- ---------------------------------------------------------------- the Codex link
-- game_codex loads on first use (autoload: false, client/MANIFEST.md "Lazy modules")
local function ensureCodex()
  if not modules.game_codex and g_modules and g_modules.ensureModuleLoaded then
    pcall(g_modules.ensureModuleLoaded, 'game_codex')
  end
  return modules.game_codex
end

local function codexModule()
  local m = ensureCodex()
  return m and m.open and m or nil
end

local function codexEntry(id)
  if not codexMap then
    local m = ensureCodex()
    local data = m and (m.getData and m.getData() or rawget(m, 'CodexData'))
    if not data then return nil end
    codexMap = L.codexIndex(data)
  end
  return codexMap[id]
end

-- ---------------------------------------------------------------- the item
local openItem

local function addRow(parent, row)
  local w = g_ui.createWidget('ItemFinderRow', parent)
  local main, sub, value = L.rowTexts(row)
  w.name:setText(main)
  w.detail:setText(sub)
  w.value:setText(value)
  if row.b then w.name:setColor('#e07a5a') end
  local tip = main .. (sub ~= '' and ('\n' .. sub) or '') .. (value ~= '' and ('\n' .. value) or '')
  w:setTooltip(tip)
  if row.i and L.validClientId(row.i) then
    w.icon:setItemId(row.i)
    w.icon:setVisible(true)
    w.name:setMarginLeft(40)
  end
  if row.l then
    w.name:setColor('#7fa8ff')
    w:setTooltip(tip .. '\n' .. tr('Click: where to find it'))
    w.onClick = function() openItem(row.l, nil, true) end
  end
  if row.m then
    w.mats:setHeight(26)
    w:setHeight(64)
    for _, m in ipairs(row.m) do
      local mw = g_ui.createWidget('ItemFinderMat', w.mats)
      if L.validClientId(m.i) then mw:setItemId(m.i) end
      if m.c > 1 then mw:setItemCount(m.c) end
      mw:setTooltip(L.materialText(m))
      if m.l then mw.onClick = function() openItem(m.l, nil, true) end end
    end
  end
  return w
end

local function drawItem()
  if not alive(window) then return end
  local detail = window.detail
  detail:destroyChildren()
  window.backButton:setEnabled(#history > 0)
  window.codexButton:setVisible(false)
  if not item then
    window.itemIcon:setItemId(0)
    window.itemName:setText(tr('Where does it drop?'))
    window.itemSub:setText(tr('Search an item, or right-click one and choose "Where to find".'))
    return
  end
  setIcon(window.itemIcon, item.cid)
  window.itemName:setText(item.name or tr('Unknown item'))
  if item.none then
    window.itemSub:setText(tr('No known source: no monster, NPC, recipe or reward gives it.'))
    return
  end
  window.itemSub:setText(tr(L.totalText(item.total)))
  local entry = item.id > 0 and codexEntry(item.id)
  if entry and codexModule() then
    window.codexButton:setVisible(true)
    window.codexButton.onClick = function() codexModule().open(entry) end
  end
  for _, sec in ipairs(item.secs) do
    local head = g_ui.createWidget('ItemFinderHeading', detail)
    head.text:setText(L.sectionHead(sec))
    if sec.pages > 1 then
      head.pageText:setText(L.pageText(sec.p, sec.pages))
      head.prevPage:setVisible(true)
      head.nextPage:setVisible(true)
      head.prevPage:setEnabled(sec.p > 1)
      head.nextPage:setEnabled(sec.p < sec.pages)
      head.prevPage.onClick = function() request('page', { id = item.id, k = sec.k, p = sec.p - 1 }) end
      head.nextPage.onClick = function() request('page', { id = item.id, k = sec.k, p = sec.p + 1 }) end
    end
    for i, row in ipairs(sec.rows) do
      local w = addRow(detail, row)
      if i % 2 == 0 then w:setBackgroundColor('#ffffff08') end
    end
  end
end

-- open an item by server id (id) or client id (cid); fromLink keeps the one shown for Back
openItem = function(id, cid, fromLink)
  if fromLink and item and (item.id > 0 or item.cid > 0) then
    L.push(history, { id = item.id, cid = item.cid })
  end
  if id then
    request('item', { id = id })
  elseif cid then
    request('item', { cid = cid })
  end
  setStatus(tr('Looking it up...'))
end

-- ---------------------------------------------------------------- the results
local function drawResults()
  if not alive(window) then return end
  local list = window.resultList
  list:destroyChildren()
  local r = results
  local rows = r and r.rows or {}
  for _, row in ipairs(rows) do
    local w = g_ui.createWidget('ItemFinderResult', list)
    setIcon(w.icon, row.cid)
    w.name:setText(row.name)
    w.kinds:setText(L.kindsText(row.kinds, 3))
    w:setTooltip(row.name .. '\n' .. L.kindsText(row.kinds, 20))
    w.onClick = function() history = {} openItem(row.id) end
  end
  if not r then
    window.listInfo:setText(tr('Type at least %d letters of an item name.', L.MIN_QUERY))
  elseif #rows == 0 then
    window.listInfo:setText(tr('No item with a known source matches "%s".', r.q))
  else
    window.listInfo:setText('')
  end
  window.listInfo:setVisible(not r or #rows == 0)
  local p, pages = r and r.p or 1, r and r.pages or 1
  window.listPager.pageLabel:setText(L.pageText(p, pages))
  window.listPager.prevButton:setEnabled(r ~= nil and p > 1)
  window.listPager.nextButton:setEnabled(r ~= nil and p < pages)
  window.resultScroll:setValue(0)
end

local function doSearch(page)
  if not alive(window) then return end
  local go, q = L.shouldSearch(window.searchEdit:getText(), page and '' or lastSent)
  if not go then return end
  lastSent = q
  request('search', { q = q, p = page or 1 })
end

local function onSearchChange(widget, text)
  if not alive(window) then return end
  window.searchHint:setVisible(text == '')
  removeEvent(searchEvent)
  searchEvent = scheduleEvent(function()
    searchEvent = nil
    if #L.query(text) < L.MIN_QUERY then
      results, lastSent = nil, nil
      drawResults()
      return
    end
    doSearch()
  end, L.SEARCH_DELAY_MS)
end

-- ---------------------------------------------------------------- the server
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local data = msg.data
  pending = nil
  if msg.action == 'results' then
    local r = L.results(data)
    if not r then return end
    results = r
    setStatus(tr('%d items', r.total))
    drawResults()
  elseif msg.action == 'item' then
    local it = L.item(data)
    if not it then return end
    item = it
    setStatus('')
    drawItem()
    window.detailScroll:setValue(0)
    -- open() / lookupClientId() show the window; an answer never opens it again (a resent request answered after
    -- the player closed it reopened the window: live test winpkg-35)
  elseif msg.action == 'page' then
    if L.applyPage(item, data) then drawItem() end
  elseif msg.action == 'busy' then
    setStatus(tr('The item index is being built. Try again in a moment.'))
  end
end

-- ---------------------------------------------------------------- public
function show()
  if not alive(window) then return end
  window:show()
  window:raise()
  window:focus()
  window.searchEdit:focus()
end

function hide()
  if alive(window) then window:hide() end
end

function toggle()
  if not alive(window) then return end
  if window:isVisible() then hide() else show() end
end

-- where to find an item: by server id (the Codex, links) or by client id (an item of the client)
function open(id)
  if not g_game.isOnline() then return false end
  history = {}
  openItem(tonumber(id), nil)
  show()
  return true
end

function lookupClientId(cid)
  if not g_game.isOnline() or not L.validClientId(cid) then return false end
  history = {}
  openItem(nil, tonumber(cid))
  show()
  return true
end

function back()
  local last = L.pop(history)
  if not last then return false end
  openItem(last.id > 0 and last.id or nil, last.id > 0 and nil or last.cid)
  return true
end

-- a right-click menu with "Where to find" for an item widget that is not on the map or in a container (the market,
-- the loot channel): attach(widget, clientId or function() return clientId end). Keeps the widget's own handler.
function attach(widget, cid)
  if not widget or widget.itemFinderAttached then return end
  widget.itemFinderAttached = true
  local own = widget.onMouseRelease
  widget.onMouseRelease = function(self, mousePos, button)
    if button == MouseRightButton and self:containsPoint(mousePos) then
      local id = type(cid) == 'function' and cid() or cid
      if L.validClientId(id) then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        menu:addOption(tr('Where to find'), function() lookupClientId(id) end)
        menu:display(mousePos)
        return true
      end
    end
    if own then return own(self, mousePos, button) end
    return false
  end
end

-- the game's right-click menu of an item (inventory, containers, the map)
local function hookMenu()
  local gi = modules.game_interface
  if not gi or not gi.addMenuHook then return end
  gi.addMenuHook('chaosItemFinder', tr('Where to find'),
    safe('menu', function(_, lookThing, useThing)
      local thing = L.menuThing(lookThing, useThing)
      if thing then lookupClientId(thing:getId()) end
    end),
    -- real items only, never ground, borders or fixed map pieces (L.menuThing)
    safe('menuCondition', function(_, lookThing, useThing)
      return L.menuThing(lookThing, useThing) ~= nil
    end))
  hooked = true
end

-- for tests and other modules
function getState()
  return { results = results, item = item, history = history, visible = alive(window) and window:isVisible() or false }
end

local function onGameStart()
  results, item, history, lastSent = nil, nil, {}, nil
  hookMenu()
  if alive(window) then
    drawResults()
    drawItem()
  end
end

local function onGameEnd()
  hide()
  removeEvent(searchEvent)
  removeEvent(resendEvent)
  searchEvent, resendEvent, pending = nil, nil, nil
end

function init()
  local ok, ui = pcall(g_ui.displayUI, 'itemfinder')
  if not ok or not ui then
    g_logger.warning('[itemfinder] window not loaded: ' .. tostring(ui))
    return
  end
  window = ui
  window:hide()
  window.searchEdit.onTextChange = safe('search', onSearchChange)
  window.listPager.prevButton.onClick = function() if results then doSearch(results.p - 1) end end
  window.listPager.nextButton.onClick = function() if results then doSearch(results.p + 1) end end
  window.backButton.onClick = function() back() end
  window.closeButton.onClick = function() hide() end
  window.onEscape = function() hide() end
  -- this handler replaces UIWindow:onKeyDown, which is what calls onEscape: Escape is handled here (live test
  -- winpkg-35: the window did not close)
  window.onKeyDown = function(widget, keyCode, keyboardModifiers)
    if keyCode == KeyEscape then
      hide()
      return true
    end
    if keyCode ~= KeyBackspace then return false end
    if window.searchEdit:isFocused() and window.searchEdit:getText() ~= '' then return false end
    return back()
  end
  handlers.opcode = safe('opcode', onMessage)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  drawResults()
  drawItem()
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  onGameEnd()
  if handlers.game then disconnect(g_game, handlers.game) end
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  local gi = modules.game_interface
  if hooked and gi and gi.removeMenuHook then pcall(gi.removeMenuHook, 'chaosItemFinder') end
  if alive(window) then window:destroy() end
  window, results, item, history, codexMap, hooked = nil, nil, nil, {}, nil, false
  handlers = {}
end
