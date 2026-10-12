-- Pure part of game_monsterbar (monsterbarmath_test.lua): where the bar goes.
-- The bar is a child of the map panel, but the map panel is not the part of the game view you can see: in the
-- extended view it is taller than the window (it starts at y -80 at 1280x720, -120 at 1920x1080) and the top menu
-- bar and the side panels lie over it. The bar goes at the top of the part on screen, centred over the character
-- (the centre of the map panel) and moved sideways only as far as it takes to stay on screen and clear of the
-- character plate.
MonsterBarMath = {}
local M = MonsterBarMath

M.GAP = 6 -- below the top of what is visible (the menu bar or the window edge)

local function overlaps(a, x, y, w, h)
  return a.x < x + w and x < a.x + a.width and a.y < y + h and y < a.y + a.height
end

-- panel: the map panel rect; limits: {left, right, top, bottom} of the screen not covered (each may be nil);
-- width, height: the bar; avoid: rects that lie over the map near its top (the character plate in the top left
-- corner reaches under the bar at 1024 px wide): the bar moves right of them while it fits, else below them.
-- Returns the bar's margin-top (from the panel's top, for anchors.top: parent.top) and its offset from the panel's
-- horizontal centre (margin-left, for anchors.horizontalCenter: parent.horizontalCenter).
function M.place(panel, limits, width, height, gap, avoid)
  limits = limits or {}
  gap = gap or M.GAP
  local x1, y1 = panel.x, panel.y
  local x2, y2 = panel.x + panel.width, panel.y + panel.height
  if limits.left then x1 = math.max(x1, limits.left) end
  if limits.right then x2 = math.min(x2, limits.right) end
  if limits.top then y1 = math.max(y1, limits.top) end
  if limits.bottom then y2 = math.min(y2, limits.bottom) end

  local top = y1 + gap
  if top + height > y2 then top = math.max(y1, y2 - height) end -- a very short view: as high as it fits

  local center = panel.x + math.floor(panel.width / 2)
  local left = center - math.floor(width / 2)
  if left + width > x2 then left = x2 - width end
  if left < x1 then left = x1 end -- a view narrower than the bar: its left edge stays on screen

  for _, a in ipairs(avoid or {}) do
    if a.width > 0 and a.height > 0 and overlaps(a, left, top, width, height) then
      if a.x + a.width + gap + width <= x2 and a.x < left + math.floor(width / 2) then
        left = a.x + a.width + gap
      elseif a.y + a.height + gap + height <= y2 then
        top = a.y + a.height + gap
      end
    end
  end
  return top - panel.y, left + math.floor(width / 2) - center
end

-- what covers the map: the window's edges (the root panel), the side panels, the console and action bars below it and
-- the top menu bar. `rect(id)` gives the rect of the root panel's visible child `id`, or nil.
function M.screenLimits(root, rect)
  local limits = { left = root.x, right = root.x + root.width, top = root.y, bottom = root.y + root.height }
  local lp = rect('gameLeftPanels')
  if lp then limits.left = math.max(limits.left, lp.x + lp.width) end
  local rp = rect('gameRightPanels')
  if rp then limits.right = math.min(limits.right, rp.x) end
  for _, id in ipairs({ 'bottomSplitter', 'gameBottomActionPanel', 'gameBottomPanel' }) do
    local b = rect(id)
    if b and b.y > root.y + root.height / 2 then limits.bottom = math.min(limits.bottom, b.y) end
  end
  local bar = rect('chaosMenuBar')
  if bar and bar.y < root.y + 60 then limits.top = math.max(limits.top, bar.y + bar.height) end
  return limits
end
