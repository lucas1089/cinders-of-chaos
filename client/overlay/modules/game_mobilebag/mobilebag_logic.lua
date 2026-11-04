-- game_mobilebag logic (pure, no engine calls). Owner 2026-11-04: a backpack was too small to use with a finger (34 px
-- cells, about 4 mm on a phone). On a phone the cells grow to fill the side panel's width: as many columns of at least
-- MIN px as fit, never above MAX px. The item picture is drawn at the cell size (UIItem draws into its rect).
MobileBagLogic = MobileBagLogic or {}
local L = MobileBagLogic

L.MIN = 48
L.MAX = 56
L.FALLBACK = 52   -- before the panel has a width

local function num(v, d)
  v = tonumber(v)
  if v == nil or v ~= v or v == math.huge or v == -math.huge then return d end
  return v
end

-- the cell size for a contents width (px) and cell spacing (px)
function L.cell(width, spacing)
  width, spacing = math.floor(num(width, 0)), math.max(0, math.floor(num(spacing, 0)))
  if width < L.MIN then return L.FALLBACK end
  local cols = math.max(1, math.floor((width + spacing) / (L.MIN + spacing)))
  local size = math.floor((width + spacing) / cols) - spacing
  return math.max(L.MIN, math.min(L.MAX, size))
end

-- the largest content height a window may take for this cell size and line count
function L.maxHeight(cell, spacing, lines)
  return (num(cell, L.FALLBACK) + num(spacing, 0)) * math.max(1, math.floor(num(lines, 1)))
end
