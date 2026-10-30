-- client_chaos_screenfit (O313): a window taller or wider than the screen used to open centred with its title and its
-- bottom buttons cut off, and a drag pushed it back to the top edge (the engine binds a widget into its parent). Now:
--  * it opens with its title in view (top or left edge of the parent);
--  * dragging it, also by any empty part on a phone, scrolls it: it moves until its far edge reaches the screen edge;
--  * the mouse wheel over an empty part scrolls it too.
-- One hook on UIWindow, no edit of the windows themselves. A window that fits behaves as before. Rules in screenfit_logic.lua.
local L = ScreenFitLogic

local base = {}
local mine = {}
local installed = false
local fitting = false     -- guard: our own move fires onGeometryChange again

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

local function parentRect(w)
  local p = w:getParent()
  if not p then return nil end
  return p:getPaddingRect()
end

-- only the windows on the root: a side panel's mini windows are placed by their panel's layout
local function topLevel(w)
  return w:getParent() == g_ui.getRootWidget() and w:getClassName() ~= 'UIMiniWindow'
end

local function overflowing(w)
  if not topLevel(w) then return false end
  local pr = parentRect(w)
  if not pr then return false end
  return L.overflows(w:getHeight(), pr.height) or L.overflows(w:getWidth(), pr.width)
end

-- bring an oversized window's title into view, once it has a size and a parent
local function fitOpen(w)
  if fitting or not alive(w) or w.static or not topLevel(w) then return end
  if not overflowing(w) then return end     -- also before its first layout: the geometry hook comes back then
  local pr = parentRect(w)
  local r = w:getRect()
  local x = L.openStart(r.x, r.width, pr.x, pr.width)
  local y = L.openStart(r.y, r.height, pr.y, pr.height)
  w.chaosFitOpened = true
  if x == r.x and y == r.y then return end
  fitting = true
  w:breakAnchors()
  w:setPosition({ x = x, y = y })
  fitting = false
end

local function hook_onDragMove(self, mousePos, mouseMoved)
  if not overflowing(self) then return base.onDragMove(self, mousePos, mouseMoved) end
  if self.static or not self.movingReference then return end
  local pr = parentRect(self)
  local x = L.clamp(mousePos.x - self.movingReference.x, self:getWidth(), pr.x, pr.width)
  local y = L.clamp(mousePos.y - self.movingReference.y, self:getHeight(), pr.y, pr.height)
  self:setPosition({ x = x, y = y })
end

local function hook_onMouseWheel(self, mousePos, direction)
  if base.onMouseWheel and base.onMouseWheel(self, mousePos, direction) then return true end
  if self.static or not overflowing(self) then return false end
  local pr = parentRect(self)
  local r = self:getRect()
  local y = L.wheel(r.y, r.height, pr.y, pr.height, direction == MouseWheelUp)
  if y == r.y then return false end
  self:breakAnchors()
  self:setPosition({ x = r.x, y = y })
  return true
end

local function hook_onVisibilityChange(self, visible)
  if base.onVisibilityChange then base.onVisibilityChange(self, visible) end
  if visible then fitOpen(self) else self.chaosFitOpened = nil end
end

-- a window made visible by g_ui.createWidget / displayUI announces no visibility change: its first layout that overflows
-- does. Once per opening (chaosFitOpened), so a scroll by the player is not undone.
local function hook_onGeometryChange(self, oldRect, newRect)
  if base.onGeometryChange then base.onGeometryChange(self, oldRect, newRect) end
  if not fitting and not self.chaosFitOpened and overflowing(self) then fitOpen(self) end
end

local function install()
  if installed or not UIWindow then return end
  base.onDragMove = rawget(UIWindow, 'onDragMove')
  if not base.onDragMove then return end
  base.onMouseWheel = rawget(UIWindow, 'onMouseWheel')
  base.onVisibilityChange = rawget(UIWindow, 'onVisibilityChange')
  base.onGeometryChange = rawget(UIWindow, 'onGeometryChange')
  mine = { onDragMove = hook_onDragMove, onMouseWheel = hook_onMouseWheel,
    onVisibilityChange = hook_onVisibilityChange, onGeometryChange = hook_onGeometryChange }
  for name, fn in pairs(mine) do UIWindow[name] = fn end
  installed = true
  -- a widget takes its class methods when it is made: the windows already made get the hooks here
  local root = g_ui.getRootWidget()
  for _, w in ipairs(root and root:getChildren() or {}) do
    if w:getClassName() == 'UIWindow' then
      for name, fn in pairs(mine) do
        if rawequal(w[name], base[name]) then w[name] = fn end
      end
    end
  end
end

local function uninstall()
  if not installed then return end
  for name, fn in pairs(mine) do
    if rawget(UIWindow, name) == fn then UIWindow[name] = base[name] end
  end
  mine = {}
  installed = false
end

function init()
  install()
end

function terminate()
  uninstall()
end
