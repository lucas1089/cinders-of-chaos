-- Pure part of game_hudmove (hudmove_test.lua): the movable HUD panels. Where a panel sits, the saved spot per panel and
-- character (g_settings node chaosHudPos: { [panel id] = { ["world/name"] = { x, y } } }, relative to the panel's
-- parent), the clamp that keeps a panel fully on screen, which press may start a drag (not one on a button or a
-- checkbox), and the default anchors read from an .otui block (for the double-click back to the default place).
-- Generalised from game_infinitytower/towerpanelpos.lua and the drag of game_dpsmeter.
HudMoveCore = {}
local M = HudMoveCore

M.NODE = 'chaosHudPos'
M.DRAG_MIN = 3          -- pixels the mouse must move before a press becomes a drag (less is a click)

-- widgets a press on must not start a drag: the press is theirs
M.INTERACTIVE = {
  UIButton = true, UICheckBox = true, UIRadioButton = true, UITextEdit = true, UIScrollBar = true,
  UIComboBox = true, UISpinBox = true, UIItem = true, UIHorizontalScrollBar = true, UIVerticalScrollBar = true,
  UIResizeBorder = true, UISplitter = true, UIProgressBarButton = true,
}

M.EDGES = { top = true, bottom = true, left = true, right = true, horizontalCenter = true, verticalCenter = true }

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

-- the saved spot of a panel for a character, or nil
function M.saved(node, id, key)
  if type(node) ~= 'table' or not id or not key then return nil end
  local panel = node[id]
  if type(panel) ~= 'table' then return nil end
  return M.parse(panel[key])
end

-- the node with this panel's spot for this character set (pos nil: forgotten, back to the default place)
function M.store(node, id, key, pos)
  node = type(node) == 'table' and node or {}
  if not id or not key then return node end
  local panel = type(node[id]) == 'table' and node[id] or {}
  local p = pos and M.parse(pos)
  panel[key] = p and { x = p.x, y = p.y } or nil
  node[id] = next(panel) ~= nil and panel or nil
  return node
end

-- the room a panel may use, relative to its parent: the part of the parent that is on screen.
-- rects are { x, y, width, height } in screen pixels; no screen: the whole parent.
function M.bounds(parent, screen)
  local px, py = num(parent and parent.x) or 0, num(parent and parent.y) or 0
  local pw, ph = num(parent and parent.width) or 0, num(parent and parent.height) or 0
  local x0, y0, x1, y1 = 0, 0, pw, ph
  if type(screen) == 'table' and num(screen.width) and num(screen.height) then
    local sx, sy = num(screen.x) or 0, num(screen.y) or 0
    x0 = math.max(x0, sx - px)
    y0 = math.max(y0, sy - py)
    x1 = math.min(x1, sx + screen.width - px)
    y1 = math.min(y1, sy + screen.height - py)
  end
  if x1 < x0 then x1 = x0 end
  if y1 < y0 then y1 = y0 end
  return { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end

-- a position that keeps a panel of w x h fully inside the bounds (top left wins when it does not fit)
function M.clamp(x, y, w, h, b)
  x, y = num(x) or 0, num(y) or 0
  w, h = num(w) or 0, num(h) or 0
  b = b or { x0 = 0, y0 = 0, x1 = 0, y1 = 0 }
  return math.floor(clamp(x, b.x0, math.max(b.x0, b.x1 - w))), math.floor(clamp(y, b.y0, math.max(b.y0, b.y1 - h)))
end

-- where the panel goes: nil when nothing is saved (keep the default anchors), else the clamped saved spot
function M.place(saved, w, h, b)
  local p = M.parse(saved)
  if not p then return nil end
  local x, y = M.clamp(p.x, p.y, w, h, b)
  return { x = x, y = y }
end

-- the drag: the mouse in screen pixels, the grab offset inside the panel, the parent's screen origin
function M.dragTo(mx, my, offX, offY, parentX, parentY, w, h, b)
  return M.clamp(mx - offX - parentX, my - offY - parentY, w, h, b)
end

-- did the mouse (or the panel) move far enough to be a drag
function M.moved(fromX, fromY, toX, toY)
  return math.abs((toX or 0) - (fromX or 0)) >= M.DRAG_MIN or math.abs((toY or 0) - (fromY or 0)) >= M.DRAG_MIN
end

-- one widget between the pressed spot and the drag source: { class, click, draggable, handle }
function M.interactive(w)
  if type(w) ~= 'table' then return false end
  return (M.INTERACTIVE[w.class] or w.click or w.draggable) and true or false
end

-- may a press start a drag: chain lists the widgets from the one under the mouse up to (not with) the drag source.
-- A button, checkbox, edit, item or anything with its own click below a handle keeps the press.
function M.canStartDrag(chain)
  if type(chain) ~= 'table' then return true end
  for _, w in ipairs(chain) do
    if type(w) == 'table' and w.handle then return true end
    if M.interactive(w) then return false end
  end
  return true
end

-- the default anchors of a widget from .otui text: the block of style `style` ("Style < Base"), or without a style the
-- loaded root (the first top-level line that is not a style definition). Only the block's own lines (two spaces in);
-- $states and children are left out. Returns a list of { edge, target, targetEdge } / { 'fill', target } /
-- { 'centerIn', target }, or nil when the block has none.
function M.parseAnchors(text, style)
  if type(text) ~= 'string' then return nil end
  local out, inBlock = {}, false
  for raw in (text .. '\n'):gmatch('([^\n]*)\n') do
    local line = raw:gsub('\r$', ''):gsub('%s*//.*$', '')
    if line:match('^%S') then
      if inBlock then break end
      local name = line:match('^([%w_]+)%s*<')
      if style then
        inBlock = name == style
      else
        inBlock = name == nil and line:match('^[%w_]+%s*$') ~= nil
      end
    elseif inBlock and line:match('^  [^%s]') then
      local key, val = line:match('^  anchors%.(%a+):%s*([%w_%.]+)%s*$')
      if key == 'fill' or key == 'centerIn' then
        if val ~= 'none' then out[#out + 1] = { key, val } end
      elseif key and M.EDGES[key] and val ~= 'none' then
        local target, edge = val:match('^(.-)%.(%a+)$')
        if target and target ~= '' and M.EDGES[edge] then out[#out + 1] = { key, target, edge } end
      end
    end
  end
  return #out > 0 and out or nil
end
