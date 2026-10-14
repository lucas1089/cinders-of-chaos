-- Charms (server data/scripts/chaos/charms.lua, extended opcode 198, JSON {action, data}; the state comes through
-- Chaos.sendChunked and is joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | place {ref | pos, sid, iid, x, y} | move {id, x, y} | take {id} | salvage {ref, sid, iid} |
--                     reforge {ref, sid, iid}
--   server -> client  state {...} | result {ok, text}
-- The grid on the left: open cells, locked cells (a padlock; the tooltip says what opens them), the placed charms. Your
-- charms (the ones in your backpack) on the right: drag one onto the grid to place it (the cells it would cover light
-- up green or red), drag a placed charm to move it or onto the list to take it out. An item dragged in from an open
-- backpack works as well. Salvage / Reforge act on the selected charm of the list. The server decides everything.
-- Menu: Character > Charms (ChaosTopBar.addEntry).

local OPCODE = 198
local V = CharmsView

local window
local state
local drag -- {kind = 'bag' | 'placed', id | ref, w, h, icon, ...}
local ghost
local selectedRef
local cellWidgets = {}
local handlers = {}
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[charms] ' .. name .. ': ' .. tostring(res))
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

local function setStatus(text, color)
  if window then
    window.status:setText(text or '')
    window.status:setColor(color or V.COLORS.dim)
  end
end

local function gridPanel() return window and window.gridFrame.grid end

-- ---------------------------------------------------------------- drawing
local function paintCells(preview)
  local lit = {}
  if preview then
    for _, c in ipairs(preview.cells) do lit[V.key(c[1], c[2])] = preview.ok and V.COLORS.ok or V.COLORS.no end
  end
  for k, w in pairs(cellWidgets) do
    w:setImageColor(w.cellOpen and V.COLORS.open or V.COLORS.locked)
    w.hl:setVisible(lit[k] ~= nil)
    if lit[k] then w.hl:setBackgroundColor(lit[k] .. '70') end
  end
end

-- the charm's look on a tile (or the drag ghost): the slot of its shape, its item sprite, the rarity frame and glow.
-- cw, ch: the cells the tile covers (1 x 1 in the list)
local function dressTile(w, c, cw, ch)
  local color = c.color or V.COLORS.gold
  local r = V.rect(1, 1, cw, ch)
  w:setSize({ width = r.width, height = r.height })
  local slot = V.slotImage(cw, ch)
  if slot then
    w:setImageSource(slot)
    w:setImageBorder(0)
  else -- a shape without its own slot: the sliced item slot
    w:setImageSource('/images/chaos/itemslot')
    w:setImageBorder(4)
  end
  w.look:setItemId(V.lookOf(c))
  local side = V.lookSide(cw, ch)
  w.look:setSize({ width = side, height = side })
  w.frame:setImageColor(color)
  w.glow:setImageColor(color)
  w.glow:setVisible(V.glows(c))
end

local function makeCharmWidget(parent, c, kind)
  local w = g_ui.createWidget('CharmTile', parent)
  if kind == 'placed' then dressTile(w, c, c.w, c.h) else dressTile(w, c, 1, 1) end
  w:setTooltip(V.tooltip(c, kind == 'placed'))
  w.charm, w.kind = c, kind
  w:setDraggable(true)
  w.onDragEnter = function(self, mousePos)
    drag = { kind = kind, id = c.id, ref = c.ref, sid = c.sid, iid = c.iid, w = c.w, h = c.h, x = c.x, y = c.y }
    ghost = g_ui.createWidget('CharmGhost', rootWidget)
    dressTile(ghost, c, c.w, c.h)
    local r = V.rect(1, 1, c.w, c.h)
    ghost:setPosition({ x = mousePos.x - r.width / 2, y = mousePos.y - r.height / 2 })
    g_mouse.pushCursor('target')
    return true
  end
  w.onDragMove = function(self, mousePos, moved)
    if ghost then
      local sz = ghost:getSize()
      ghost:setPosition({ x = mousePos.x - sz.width / 2, y = mousePos.y - sz.height / 2 })
    end
    local grid = gridPanel()
    if grid and grid:containsPoint(mousePos) then
      local gp = grid:getPosition()
      paintCells(V.preview(state, drag, mousePos.x - gp.x, mousePos.y - gp.y))
    else
      paintCells(nil)
    end
    return true
  end
  w.onDragLeave = function(self, droppedWidget, mousePos)
    g_mouse.popCursor('target')
    if ghost then ghost:destroy() ghost = nil end
    paintCells(nil)
    local d = drag
    drag = nil
    if not window or not d then return true end
    local grid, bag = gridPanel(), window.bagFrame
    local target, px, py
    if grid:containsPoint(mousePos) then
      local gp = grid:getPosition()
      target, px, py = 'grid', mousePos.x - gp.x, mousePos.y - gp.y
    elseif bag:containsPoint(mousePos) then
      target = 'bag'
    end
    local act, why = V.dropAction(state, d, target, px, py)
    if act then
      send(act.action, act.data)
    elseif why then
      setStatus(why, V.COLORS.bad)
    end
    return true
  end
  return w
end

local function drawGrid()
  local grid = gridPanel()
  if not grid then return end
  grid:destroyChildren()
  cellWidgets = {}
  if not state then return end
  local full = V.rect(1, 1, state.cols, state.rows)
  grid:setSize({ width = full.width, height = full.height })
  for _, c in ipairs(state.cells or {}) do
    local w = g_ui.createWidget('CharmCell', grid)
    local r = V.rect(c.x, c.y, 1, 1)
    w:setMarginLeft(r.x)
    w:setMarginTop(r.y)
    w.cellOpen = c.open and true or false
    if not c.open then
      w.lock:setImageSource(V.LOCK_IMAGE)
      w.lock:setVisible(true)
      w:setTooltip('Locked: ' .. tostring(c.why or ''))
    end
    cellWidgets[V.key(c.x, c.y)] = w
  end
  paintCells(nil)
  for _, p in ipairs(state.placed or {}) do
    local w = makeCharmWidget(grid, p, 'placed')
    local r = V.rect(p.x, p.y, p.w, p.h)
    w:addAnchor(AnchorTop, 'parent', AnchorTop)
    w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    w:setMarginLeft(r.x)
    w:setMarginTop(r.y)
    w:setOpacity(p.active == false and 0.4 or 1)
  end
end

local function highlightBag()
  if not window then return end
  for _, w in ipairs(window.bagFrame.bagList:getChildren()) do
    local on = w.charm and w.charm.ref == selectedRef
    w:setBorderWidth(on and 1 or 0) -- the selected charm: a thin light outline over its frame
    w:setBorderColor(V.COLORS.select)
  end
  local b = V.bagEntry(state, selectedRef)
  window.salvageButton:setEnabled(b ~= nil)
  window.reforgeButton:setEnabled(b ~= nil and b.reforge ~= nil)
  window.reforgeButton:setTooltip(b and b.reforge and string.format(tr('Roll the values again for %d charm shards'), b.reforge)
    or tr('Select a charm of your list (uniques cannot be reforged)'))
  window.salvageButton:setTooltip(b and string.format(tr('Break the charm into %d charm shards'), b.salvage or 0)
    or tr('Select a charm of your list'))
end

local function drawBag()
  if not window then return end
  local list = window.bagFrame.bagList
  list:destroyChildren()
  local bag = state and state.bag or {}
  window.bagFrame.empty:setVisible(#bag == 0)
  if not V.bagEntry(state, selectedRef) then selectedRef = nil end
  for _, b in ipairs(bag) do
    local w = makeCharmWidget(list, b, 'bag')
    w.onClick = function()
      selectedRef = b.ref
      highlightBag()
    end
  end
  highlightBag()
end

local function drawSide()
  if not window then return end
  window.header:setText(V.header(state))
  local list = window.totalsFrame.totals
  list:destroyChildren()
  for _, line in ipairs(V.totalsLines(state)) do
    local w = g_ui.createWidget('CharmLine', list)
    w:setText(line.text)
    w:setColor(line.color)
  end
  local ul = window.unlockFrame.unlocks
  ul:destroyChildren()
  for _, line in ipairs(V.unlockLines(state)) do
    local w = g_ui.createWidget('CharmLine', ul)
    w:setText(line.text)
    w:setColor(line.color)
  end
end

local function redraw()
  drawGrid()
  drawBag()
  drawSide()
end

-- ---------------------------------------------------------------- an item dragged in from a game container
local function onDropItem(self, widget, mousePos)
  if drag then return false end -- our own tiles are handled by their drag
  local item = widget and (widget.currentDragThing or (widget.getItem and widget:getItem()))
  if not item or not item.isItem or not item:isItem() or not state then return false end
  local pos = item:getPosition()
  local A = ChaosItemAttr or { ID = 6 }
  local iid = 0
  if item.getCustomAttribute then
    local ok, v = pcall(item.getCustomAttribute, item, A.ID)
    iid = ok and tonumber(v) or 0
  end
  local gp = gridPanel():getPosition()
  -- the item's size is known from the list of charms in the backpack (same per-item id), else 1x1
  local w, h = 1, 1
  for _, b in ipairs(state.bag or {}) do
    if iid > 0 and tostring(b.iid) == string.format('%.0f', iid) then w, h = b.w, b.h end
  end
  local x, y = V.anchor(state, mousePos.x - gp.x, mousePos.y - gp.y, w, h)
  if not x then return false end
  send('place', { pos = { x = pos.x, y = pos.y, z = pos.z }, iid = string.format('%.0f', iid), x = x, y = y })
  return true
end

-- ---------------------------------------------------------------- server messages
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    state = data
    redraw()
  elseif msg.action == 'result' then
    setStatus(data.text or '', data.ok and V.COLORS.good or V.COLORS.bad)
  end
end

-- ---------------------------------------------------------------- buttons
function salvageSelected()
  local b = V.bagEntry(state, selectedRef)
  if b then send('salvage', { ref = b.ref, sid = b.sid, iid = b.iid }) end
end

function reforgeSelected()
  local b = V.bagEntry(state, selectedRef)
  if b then send('reforge', { ref = b.ref, sid = b.sid, iid = b.iid }) end
end

function refresh()
  send('open')
end

function show()
  if not window then return end
  send('open')
  window:show()
  window:raise()
  window:focus()
end

function hide()
  if ghost then ghost:destroy() ghost = nil end
  drag = nil
  if window then window:hide() end
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

-- for other modules and tests
function getState()
  return { state = state, visible = window and window:isVisible() or false, selected = selectedRef }
end

function getWindow() return window end

function setState(s)
  state = s
  redraw()
end

-- ---------------------------------------------------------------- menu
local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'character',
      { text = 'Charms', icon = 'inventory', modules = { 'game_charms' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  state, selectedRef, drag = nil, nil, nil
  addMenu()
end

local function onGameEnd()
  hide()
  state = nil
end

function init()
  g_ui.importStyle('charms')
  local ok, ui = pcall(g_ui.createWidget, 'CharmsWindow', rootWidget)
  if ok and ui then
    window = ui
    window:hide()
    window.gridFrame.grid.onDrop = safe('drop', onDropItem)
  else
    g_logger.warning('[charms] window not loaded: ' .. tostring(ui))
  end
  handlers.opcode = safe('opcode', onMessage)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  addMenu()
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game)
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if ghost then ghost:destroy() ghost = nil end
  if window then window:destroy() window = nil end
  handlers = {}
end
