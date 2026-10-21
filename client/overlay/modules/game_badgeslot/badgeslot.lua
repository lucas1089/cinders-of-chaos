-- The badge slot in the inventory window (logic: badgeslotlogic.lua). game_inventory (a base module, patch 0113)
-- builds the slot; this module only gives it the "Badge" tooltip while it is empty and drops "ammunition" from the
-- soul label's tooltip. The item tooltips (game_itemtooltip) are untouched.
local L = BadgeSlotLogic
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok and not reported[name] then
      reported[name] = true
      g_logger.warning('[badgeslot] ' .. name .. ': ' .. tostring(res))
    end
  end
end

local function panel()
  local inv = modules.game_inventory
  return inv and inv.getInventoryPanel and inv.getInventoryPanel() or nil
end

local function refresh()
  local p = panel()
  if not p then return end
  local w = p:getChildById('slot' .. L.SLOT)
  if w then
    local tip = L.slotTooltip(L.SLOT, w:getItem() ~= nil)
    if tip then w:setTooltip(tip) end
  end
  local soul = p:recursiveGetChildById('soulLabel')
  if soul then soul:setTooltip(L.SOUL_TOOLTIP) end
end

-- after game_inventory has put the item in (it restyles the widget in its own handler)
local function onInventoryChange(player, slot)
  if tonumber(slot) == L.SLOT then addEvent(safe('change', refresh)) end
end

local handlers = {}

function init()
  handlers.change = safe('inventory', onInventoryChange)
  handlers.start = function() addEvent(safe('start', refresh)) end
  connect(LocalPlayer, { onInventoryChange = handlers.change })
  connect(g_game, { onGameStart = handlers.start, onGameEnd = handlers.start })
  addEvent(safe('init', refresh))
end

function terminate()
  disconnect(LocalPlayer, { onInventoryChange = handlers.change })
  disconnect(g_game, { onGameStart = handlers.start, onGameEnd = handlers.start })
end
