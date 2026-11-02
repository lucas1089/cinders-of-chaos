-- Pure part of the movable tower panel of game_infinitytower (towerpanelpos_test.lua): where the panel sits, the
-- saved spot per character (g_settings node chaosTowerPanel, key "world/name" -> { x, y } relative to the parent),
-- the clamp that keeps it fully on screen, and the panel / Automatic box widths from the measured texts.
-- No saved spot: the default place (top centre, margin-top DEFAULT_TOP, as in infinity_tower.otui).
TowerPanelPos = {}
local M = TowerPanelPos

M.NODE = 'chaosTowerPanel'
M.DEFAULT_TOP = 40      -- margin-top of TowerPanel in infinity_tower.otui
M.DRAG_MIN = 3          -- pixels the panel must move before a release saves the spot
M.MIN_WIDTH = 290       -- width of TowerPanel in infinity_tower.otui
M.EDGE = 6              -- panel edge and gap between the button and the box
M.BOX_MIN = 84
M.BOX_PAD = 24          -- the box image and its gap before the text, plus a little air
M.BUTTON_PAD = 16

local function num(v)
  v = tonumber(v)
  if v and v == v and v ~= math.huge and v ~= -math.huge then return v end
  return nil
end

local function clamp(v, lo, hi)
  if v > hi then v = hi end
  if v < lo then v = lo end
  return v
end

-- the settings key of a character (nil without a name)
function M.key(world, name)
  if type(name) ~= 'string' or name == '' then return nil end
  return (type(world) == 'string' and world ~= '' and world or '-') .. '/' .. name
end

-- a saved entry -> { x, y } whole numbers, or nil. Read back from g_settings the numbers may be strings.
function M.parse(entry)
  if type(entry) ~= 'table' then return nil end
  local x, y = num(entry.x), num(entry.y)
  if not x or not y then return nil end
  return { x = math.floor(x), y = math.floor(y) }
end

-- the saved spot of a character in the settings node, or nil
function M.saved(node, key)
  if type(node) ~= 'table' or not key then return nil end
  return M.parse(node[key])
end

-- the node with this character's spot set (pos nil: forgotten, back to the default place)
function M.store(node, key, pos)
  node = type(node) == 'table' and node or {}
  if not key then return node end
  local p = pos and M.parse(pos)
  node[key] = p and { x = p.x, y = p.y } or nil
  return node
end

-- a position that keeps a panel of w x h fully inside a parent of pw x ph (top left wins when it does not fit)
function M.clamp(x, y, w, h, pw, ph)
  x, y = num(x) or 0, num(y) or 0
  return math.floor(clamp(x, 0, math.max(0, (pw or 0) - (w or 0)))),
    math.floor(clamp(y, 0, math.max(0, (ph or 0) - (h or 0))))
end

-- the default place, relative to the parent: centred, DEFAULT_TOP down
function M.default(w, h, pw, ph)
  return M.clamp(math.floor(((pw or 0) - (w or 0)) / 2), M.DEFAULT_TOP, w, h, pw, ph)
end

-- where the panel goes: nil when nothing is saved (keep the default anchors), else the clamped saved spot
function M.place(saved, w, h, pw, ph)
  local p = M.parse(saved)
  if not p then return nil end
  local x, y = M.clamp(p.x, p.y, w, h, pw, ph)
  return { x = x, y = y }
end

-- the drag: the mouse in screen pixels, the grab offset inside the panel, the parent's screen origin
function M.dragTo(mx, my, offX, offY, parentX, parentY, w, h, pw, ph)
  return M.clamp(mx - offX - parentX, my - offY - parentY, w, h, pw, ph)
end

-- did a drag move the panel far enough to save it
function M.moved(fromX, fromY, toX, toY)
  return math.abs((toX or 0) - (fromX or 0)) >= M.DRAG_MIN or math.abs((toY or 0) - (fromY or 0)) >= M.DRAG_MIN
end

-- the panel width and the Automatic box width from the measured texts (button text, box text), so neither is cut
function M.widths(buttonTextW, boxTextW)
  local box = math.max(M.BOX_MIN, math.ceil((num(boxTextW) or 0) + M.BOX_PAD))
  local button = math.ceil((num(buttonTextW) or 0) + M.BUTTON_PAD)
  local panel = math.max(M.MIN_WIDTH, M.EDGE + button + M.EDGE + box + M.EDGE)
  return panel, box
end
