-- Card borders (server cards.lua, extended opcode 172, JSON {action, data}).
--   server -> client  state {on = [card ids], cards = [every card id], decks = [every deck id]}   (ids as drawn here)
--   client -> server  sync     asked once after login; the server also pushes the set at login and whenever it changes
-- Hooks the container windows from outside (the Container signals, like game_lootfilter): a card item inside a deck window
-- gets a border child on its slot widget, green when the card is on, dim red-grey when it is off. One redraw per container
-- per frame, no per-frame loop. Rules in cardborderlogic.lua (cardborder_test.lua).

local OPCODE = 172
local BORDER_ID = 'cardBorder'

local L = CardBorderLogic
local state = L.new()
local handlers = {}
local pending = {} -- container id -> true while a redraw is queued
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok and not reported[name] then
      reported[name] = true
      g_logger.warning('[cardborder] ' .. name .. ': ' .. tostring(err))
    end
  end
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function borderOf(widget, create)
  local b = widget:getChildById(BORDER_ID)
  if not b and create then
    b = g_ui.createWidget('UIWidget', widget)
    b:setId(BORDER_ID)
    b:setPhantom(true)
    b:setFocusable(false)
    b:fill('parent')
  end
  return b
end

local function paint(widget, kind)
  if not widget or widget:isDestroyed() then return end
  local style = kind and L.style(kind)
  if not style then
    local b = borderOf(widget, false)
    if b then b:hide() end
    return
  end
  local b = borderOf(widget, true)
  b:setBorderWidth(style.width)
  b:setBorderColor(style.color)
  b:show()
end

local function deckIdOf(container)
  local ok, item = pcall(function() return container:getContainerItem() end)
  if ok and item then
    local okId, id = pcall(function() return item:getId() end)
    if okId then return id end
  end
  return nil
end

local function decorate(container)
  if not container or not container.itemsPanel or container.itemsPanel:isDestroyed() then return end
  local deckId = deckIdOf(container)
  local isDeck = deckId and L.isDeck(state, deckId)
  -- the flag sits on the items panel, not on the container: a container opened in the window of a deck (same window,
  -- new Container object, base patch 0122 keeps the slot widgets) must still clear the borders the deck left
  local panel = container.itemsPanel
  if not L.needsPass(isDeck, panel.cardBorderDrawn) then return end
  panel.cardBorderDrawn = isDeck and true or nil
  for slot = 0, container:getCapacity() - 1 do
    local widget = container.itemsPanel:getChildById('item' .. slot)
    if widget then
      local item = isDeck and container:getItem(slot) or nil
      paint(widget, item and L.kind(state, deckId, item:getId()) or nil)
    end
  end
end

-- one redraw per container per frame
local function decorateLater(container)
  local cid = container:getId()
  if pending[cid] then return end
  pending[cid] = true
  addEvent(safe('decorate', function()
    pending[cid] = nil
    local c = g_game.getContainer(cid)
    if c then decorate(c) end
  end))
end

local function redrawAll()
  for _, container in pairs(g_game.getContainers()) do
    decorateLater(container)
  end
end

local function onContainerChange(container)
  decorateLater(container)
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local msg = buffer
  if type(buffer) == 'string' then
    local ok, decoded = pcall(json.decode, buffer)
    if not ok then return end
    msg = decoded
  end
  if type(msg) ~= 'table' or msg.action ~= 'state' then return end
  if L.apply(state, msg.data) then redrawAll() end
end

local function onGameStart()
  L.reset(state)
  scheduleEvent(function() if g_game.isOnline() then send('sync') end end, 1000)
end

local function onGameEnd()
  L.reset(state)
  pending = {}
end

function init()
  handlers.container = {
    onOpen = safe('open', onContainerChange), onAddItem = safe('add', onContainerChange),
    onRemoveItem = safe('remove', onContainerChange), onUpdateItem = safe('update', onContainerChange),
    onSizeChange = safe('size', onContainerChange)
  }
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  handlers.opcode = safe('opcode', onExtendedOpcode)
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, handlers.opcode)
  connect(Container, handlers.container)
  connect(g_game, handlers.game)
  if g_game.isOnline() then handlers.game.onGameStart() end
end

function terminate()
  if handlers.container then disconnect(Container, handlers.container) end
  if handlers.game then disconnect(g_game, handlers.game) end
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if g_game.isOnline() then
    L.reset(state)
    redrawAll()
  end
  handlers = {}
  pending = {}
end
