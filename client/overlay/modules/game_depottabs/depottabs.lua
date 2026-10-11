-- Depot tabs (server data/scripts/chaos/depot.lua, extended opcode 111, JSON {action, data}; server -> client only).
--   tabs {tabs, max, size, used, ids, chest, hint}   see depottabsview.lua
-- The tabs are the boxes inside the depot chest (ordinary containers, game_containers shows them). This module only
-- decorates those windows: a tab's window title gets its count ("Tab 3 (87/100)") or "(locked)", and in the depot
-- chest window a locked tab is dimmed and every tab has a tooltip with its count or the store hint. No base file is
-- changed; without this module the tabs work the same, with their stock titles.

local OPCODE = 111
local V = DepotTabsView

local state = V.newState()
local open = {} -- the containers game_containers has open (id -> container)
local handlers = {}
local reported = {}

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

local function decorate(container)
  if not container or not container.window then return end
  local top = container:getContainerItem()
  local topId = top and top:getId() or 0
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
  for _, c in pairs(open) do
    decorate(c)
  end
end

-- after game_containers has built or refreshed the window
local function later(container)
  scheduleEvent(safe('decorate', function() decorate(container) end), 30)
end

local function onOpen(container)
  open[container:getId()] = container
  later(container)
end

local function onClose(container)
  open[container:getId()] = nil
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' or msg.action ~= 'tabs' then return end
  state = V.apply(state, msg.data)
  decorateAll()
end

-- for other modules and tests
function getState()
  return state
end

local function onGameEnd()
  open = {}
end

function init()
  handlers.opcode = safe('opcode', onExtendedOpcode)
  handlers.container = {
    onOpen = safe('open', onOpen),
    onClose = safe('close', onClose),
    onSizeChange = safe('size', later),
    onRemoveItem = safe('remove', later),
    onUpdateItem = safe('update', later),
    onAddItem = safe('add', later)
  }
  handlers.game = { onGameEnd = safe('end', onGameEnd) }
  ProtocolGame.registerExtendedOpcode(OPCODE, handlers.opcode)
  connect(Container, handlers.container)
  connect(g_game, handlers.game)
end

function terminate()
  disconnect(Container, handlers.container)
  disconnect(g_game, handlers.game)
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  open = {}
  handlers = {}
end
