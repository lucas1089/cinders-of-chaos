-- client_chaos_screenfit: the pure rules (screenfit_test.lua). One axis at a time: a window that fits stays inside its
-- parent as before; a window larger than its parent may move only so far that it still covers the parent, so every part
-- of it can be brought into view and no empty strip opens at an edge.
ScreenFitLogic = {}
local L = ScreenFitLogic

L.WHEEL_STEP = 48          -- interface pixels per mouse wheel notch

function L.overflows(size, parentSize)
  return size ~= nil and parentSize ~= nil and parentSize > 0 and size > parentSize
end

-- the allowed start of a widget of `size` in a parent from `pStart` with `pSize`
function L.clamp(pos, size, pStart, pSize)
  if L.overflows(size, pSize) then
    return math.min(pStart, math.max(pStart + pSize - size, pos))
  end
  return math.max(pStart, math.min(pStart + pSize - size, pos))
end

-- where a window opens when it is taller (or wider) than the parent: its start edge, so the title is in view
function L.openStart(pos, size, pStart, pSize)
  if L.overflows(size, pSize) then return pStart end
  return pos
end

-- one wheel notch: up shows the part above (the window moves down), down the part below
function L.wheel(pos, size, pStart, pSize, up)
  if not L.overflows(size, pSize) then return pos end
  local step = up and L.WHEEL_STEP or -L.WHEEL_STEP
  return L.clamp(pos + step, size, pStart, pSize)
end

return L
