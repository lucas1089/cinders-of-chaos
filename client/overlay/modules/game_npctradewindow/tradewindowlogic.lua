-- NPC trade window: the geometry without client API (tested by tradewindowlogic_test.lua with luajit and lua5.3).
TradeWindowLogic = {}
local L = TradeWindowLogic

L.WIDTH = 420
L.HEIGHT = 520
L.MIN_WIDTH = 300
L.MIN_HEIGHT = 300
L.MARGIN = 24

-- The window size and position for a game view of rootW x rootH: the preferred size, smaller when the view is, and
-- centred; `top` keeps it under the top menu bar. Returns {x, y, w, h}.
function L.geometry(rootW, rootH, top)
  rootW, rootH, top = tonumber(rootW) or 0, tonumber(rootH) or 0, tonumber(top) or 0
  local w = math.max(L.MIN_WIDTH, math.min(L.WIDTH, rootW - 2 * L.MARGIN))
  local h = math.max(L.MIN_HEIGHT, math.min(L.HEIGHT, rootH - top - 2 * L.MARGIN))
  local x = math.max(0, math.floor((rootW - w) / 2))
  local y = math.max(top, top + math.floor((rootH - top - h) / 2))
  return { x = x, y = y, w = w, h = h }
end

-- Should the trade window be lifted out of its side panel? Only a window that is shown and not already floating
-- (parent = the game view's root panel, which the base dialog uses too).
function L.needsFloat(visible, parentIsRoot)
  return visible == true and parentIsRoot ~= true
end
