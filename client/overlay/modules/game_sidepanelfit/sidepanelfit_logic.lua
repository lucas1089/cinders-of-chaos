-- Pure rules of game_sidepanelfit (client/MANIFEST.md "Horizontal panels"; tested by sidepanelfit_logic_test.lua).
-- Lua 5.1 / LuaJIT and Lua 5.3.
SidePanelFitLogic = {}
local L = SidePanelFitLogic

L.DEFAULT_HEIGHT = 200   -- the height the base gives a panel when the option is switched on
L.MIN_HEIGHT = 60        -- a remembered height below this is not a real size
L.DROP_HEIGHT = 80       -- an empty panel is this high while a window is dragged, so it can take the drop

-- number of children that are shown
function L.visibleCount(children)
  local n = 0
  for _, c in ipairs(children or {}) do
    if c.visible then n = n + 1 end
  end
  return n
end

-- s: { optionOn, height (now), remembered (height of the last time it held a window), visible (count), dragging }
-- Returns { height = n or nil, remember = n or nil, opaque = bool }. Nothing to do when the option is off: the base
-- already set the height to 0 and moved the windows out.
function L.plan(s)
  local out = { height = nil, remember = nil, opaque = false }
  if not s.optionOn then return out end
  local cur = s.height or 0
  local good = s.remembered and s.remembered >= L.MIN_HEIGHT and s.remembered or L.DEFAULT_HEIGHT
  if (s.visible or 0) > 0 then
    out.opaque = true
    if cur <= 0 then
      out.height = good
    elseif not s.dragging and cur >= L.MIN_HEIGHT then
      out.remember = cur
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
