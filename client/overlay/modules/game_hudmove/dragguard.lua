-- Shared guard for modules that start a drag from a press handler (global ChaosDragGuard, not sandboxed; O498).
-- Why: the engine hands the release of a click to the pressed widget first and stops there when that widget's
-- onMouseRelease returns true. The base UIButton:onMouseRelease returns isPressed(), which is true at that moment, so a
-- release over a button never reaches the panel or header the button sits in. A panel whose press handler began a drag
-- (and grabbed the mouse) on a press that landed on one of its buttons never saw the end of it: the window followed the
-- pointer for good, or the mouse stayed grabbed by a panel nobody could click away from.
--   ChaosDragGuard.onChild(source, pos)  true when the press at pos landed on a child of `source` with clicks of its own
--                                        (button, check box, edit, item, ...): a drag must not begin, the child keeps it
--   ChaosDragGuard.stale()               true when a drag that is running has lost its button: the left button is up, or the
--                                        client window is out of focus. Call it from the move handler and end the drag.
-- Pure rules (tested by dragguard_test.lua): isStale, interactiveClass.
ChaosDragGuard = ChaosDragGuard or {}
local G = ChaosDragGuard

-- the classes that keep a press for themselves (the list of the movable HUD panels)
local INTERACTIVE = {
  UIButton = true, UICheckBox = true, UIRadioButton = true, UITextEdit = true, UIScrollBar = true,
  UIComboBox = true, UISpinBox = true, UIItem = true, UIHorizontalScrollBar = true, UIVerticalScrollBar = true,
  UIResizeBorder = true, UISplitter = true, UIProgressBarButton = true,
}

function G.interactiveClass(name)
  return INTERACTIVE[name] == true
end

-- leftDown: the left button is down now; focused: the client window has focus (nil: assumed)
function G.isStale(leftDown, focused)
  return leftDown == false or focused == false
end

-- the widgets from the one under the pointer up to (not with) `source`: true when one of them keeps its press
function G.onChild(source, pos)
  if source == nil or pos == nil then return false end
  local ok, hit = pcall(function() return source:recursiveGetChildByPos(pos, false) end)
  local w = ok and hit or nil
  local guard = 0
  while w and w ~= source and guard < 32 do
    local okc, class = pcall(function() return w:getClassName() end)
    if okc and G.interactiveClass(class) then return true end
    local okp, parent = pcall(function() return w:getParent() end)
    w = okp and parent or nil
    guard = guard + 1
  end
  return false
end

function G.stale()
  local down = true
  if g_mouse and g_mouse.isPressed and MouseLeftButton then
    local ok, v = pcall(g_mouse.isPressed, MouseLeftButton)
    if ok then down = v == true end
  end
  local focused = true
  if g_window and g_window.hasFocus then
    local ok, v = pcall(g_window.hasFocus)
    if ok then focused = v ~= false end
  end
  return G.isStale(down, focused)
end
