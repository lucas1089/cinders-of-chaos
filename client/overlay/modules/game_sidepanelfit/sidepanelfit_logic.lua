-- Pure rules of game_sidepanelfit (client/MANIFEST.md "Horizontal panels"; tested by sidepanelfit_logic_test.lua).
-- Lua 5.1 / LuaJIT and Lua 5.3.
SidePanelFitLogic = {}
local L = SidePanelFitLogic

L.DROP_HEIGHT = 80       -- an empty panel is this high while a window is dragged, so it can take the drop
L.MAX_HEIGHT = 800       -- the most the base's resize border gives a horizontal panel
L.KEEP_BELOW = 150       -- room left for the side panels under it

-- number of children that are shown
function L.visibleCount(children)
  local n = 0
  for _, c in ipairs(children or {}) do
    if c.visible then n = n + 1 end
  end
  return n
end

-- Height a verticalBox panel needs for its shown children.
-- children: { visible, height, marginTop, marginBottom }; pad: { top, bottom }; spacing: layout spacing (0).
function L.contentHeight(children, pad, spacing)
  local h, n = 0, 0
  spacing = spacing or 0
  for _, c in ipairs(children or {}) do
    if c.visible then
      h = h + (c.marginTop or 0) + (c.height or 0) + (c.marginBottom or 0)
      n = n + 1
    end
  end
  if n == 0 then return 0 end
  h = h + spacing * (n - 1)
  pad = pad or {}
  return h + (pad.top or 0) + (pad.bottom or 0)
end

-- Most height the panel may take: L.MAX_HEIGHT, and never so much the side panels below get no room.
function L.limit(parentHeight)
  local lim = L.MAX_HEIGHT
  if parentHeight and parentHeight > 0 then
    lim = math.min(lim, math.max(L.DROP_HEIGHT, parentHeight - L.KEEP_BELOW))
  end
  return lim
end

-- s: { optionOn (true, false or nil = unknown), height (now), children (count, shown or not), visible (shown count),
--      content (contentHeight of the shown ones), limit, dragging }
-- Returns { height = n or nil, evict = bool, opaque = bool }.
-- Option off: the panel must hold nothing and take no room. The base only clears it when the option is switched;
-- at login game_sidebars sets the saved height and the layout restore puts the saved windows back in, whatever the
-- option says. So any child is moved out (evict) and the height goes to 0.
-- Option on: the panel is as high as the windows it shows, so there is no gap under the last one.
function L.plan(s)
  local out = { height = nil, evict = false, opaque = false }
  if s.optionOn == nil then return out end
  local cur = s.height or 0
  if not s.optionOn then
    if (s.children or 0) > 0 then out.evict = true end
    if cur > 0 then out.height = 0 end
    return out
  end
  if (s.visible or 0) > 0 then
    out.opaque = true
    local want = math.min(s.content or 0, s.limit or L.MAX_HEIGHT)
    if s.dragging then
      -- a window is on the move: keep the drop target still
      if cur <= 0 then out.height = want end
    elseif want > 0 and want ~= cur then
      out.height = want
    end
  elseif s.dragging then
    out.opaque = true
    if cur <= 0 then out.height = L.DROP_HEIGHT end
  elseif cur > 0 then
    out.height = 0
  end
  return out
end

return SidePanelFitLogic
