-- NPC trade window: the buy / sell list of an NPC shown as a window in the middle of the game view (owner 2026-10-17:
-- "NPCs que vendem devem mostrar o inventario numa janela, nao num widget").
-- The base module game_npctrade builds the trade as a mini window (NpcWindow, 175 px wide) and docks it in a side
-- panel; only next to the base dialog window (which game_npctalk replaces by the speech bubble) it floats. This module
-- wraps game_npctrade.show: after the base put the window in a panel it lifts it to the game view's root panel (the
-- place the base dialog uses too), makes it 420 x 520 (smaller on a small view), and centres it. The base logic (items,
-- tabs, price, quantity, the buttons) is untouched; closing the window ends the conversation as before.
-- Without game_npctrade nothing happens. Geometry: tradewindowlogic.lua.

local L = TradeWindowLogic
local originalShow

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function rootPanel()
  local gi = modules.game_interface
  return gi and gi.getRootPanel and gi.getRootPanel() or g_ui.getRootWidget()
end

local function tradeWidget()
  return g_ui.getRootWidget():recursiveGetChildById('tradeWindow')
end

local function float()
  local w = tradeWidget()
  local root = rootPanel()
  if not alive(w) or not alive(root) then return end
  if not L.needsFloat(w:isVisible(), w:getParent() == root) then return end
  local g = L.geometry(root:getWidth(), root:getHeight(), 0)
  w:setParent(root, true)
  w:setDraggable(true)
  w:setSize({ width = g.w, height = g.h })
  w:setPosition({ x = root:getX() + g.x, y = root:getY() + g.y })
  w:raise()
  w:focus()
end

local function wrappedShow(...)
  local result = originalShow(...)
  local ok, err = pcall(float)
  if not ok then g_logger.warning('[npctradewindow] ' .. tostring(err)) end
  return result
end

function init()
  local trade = modules.game_npctrade
  if not trade or type(trade.show) ~= 'function' then
    g_logger.warning('[npctradewindow] game_npctrade not found: the trade stays in the side panel')
    return
  end
  originalShow = trade.show
  trade.show = wrappedShow
end

function terminate()
  local trade = modules.game_npctrade
  if trade and originalShow and trade.show == wrappedShow then trade.show = originalShow end
  originalShow = nil
end
