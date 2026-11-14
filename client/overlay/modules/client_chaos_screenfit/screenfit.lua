-- client_chaos_screenfit (O313): a window taller or wider than the screen used to open centred with its title and its
-- bottom buttons cut off, and a drag pushed it back to the top edge (the engine binds a widget into its parent). Now:
--  * it opens with its title in view (top or left edge of the parent);
--  * dragging it, also by any empty part on a phone, scrolls it: it moves until its far edge reaches the screen edge;
--  * the mouse wheel over an empty part scrolls it too.
--  * (O572) a window with no valid position (no anchors so it sat at the top left, a saved (0,0), off the screen) opens
--    centred in the game screen, below the menu bar; a position the player gave it is kept. Rules in centre_logic.lua.
-- One hook on UIWindow, no edit of the windows themselves. A window that fits behaves as before. Rules in screenfit_logic.lua.
local L = ScreenFitLogic
local C = WindowCentreLogic

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

-- windows that keep the place their style gives them (a HUD anchored to the top left corner)
local KEEP_PLACE = { chaosPerfWindow = true }

local function isMobile()
  return g_app and g_app.isMobile and g_app.isMobile() == true
end

local function rectOf(w)
  local r = w:getRect()
  return { x = r.x, y = r.y, width = r.width, height = r.height }
end

-- the game screen as the centre rules want it: the root rect, the bottom of the menu bar, the map panel
local function screenInfo()
  local root = g_ui.getRootWidget()
  if not root then return nil end
  local info = { root = rectOf(root) }
  local ok, bar = pcall(function() return root:recursiveGetChildById('chaosMenuBar') end)
  if ok and bar and not bar:isDestroyed() and bar:isVisible() then
    local r = bar:getRect()
    info.barBottom = r.y + r.height
  end
  local gi = modules and modules.game_interface
  if g_game and g_game.isOnline and g_game.isOnline() and gi and gi.getMapPanel then
    local okMap, map = pcall(gi.getMapPanel)
    if okMap and map and not map:isDestroyed() then info.map = rectOf(map) end
  end
  return info
end

-- once the window has had its layout: no valid position, so centre it (an anchored window is already placed)
local function centreNow(w)
  w.chaosCentreQueued = nil
  if fitting or not alive(w) or w.chaosMoved or w.chaosCentreDone or KEEP_PLACE[w:getId()] then return end
  if not w:isVisible() or not topLevel(w) or isMobile() then return end
  local info = screenInfo()
  if not info then return end
  local r = w:getRect()
  info.pos, info.size = { x = r.x, y = r.y }, { width = r.width, height = r.height }
  w.chaosCentreDone = true
  local p = C.openPosition(info)
  if not p or (p.x == r.x and p.y == r.y) then return end
  fitting = true
  w:breakAnchors()
  w:setPosition(p)
  fitting = false
end

local function queueCentre(w)
  if w.chaosCentreDone or w.chaosCentreQueued or w.chaosMoved or not topLevel(w) then return end
  w.chaosCentreQueued = true
  addEvent(function() centreNow(w) end)
end

local function hook_onDragMove(self, mousePos, mouseMoved)
  self.chaosMoved = true
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
  if visible then fitOpen(self) queueCentre(self) else self.chaosFitOpened = nil self.chaosCentreDone = nil end
end

-- a window made visible by g_ui.createWidget / displayUI announces no visibility change: its first layout that overflows
-- does. Once per opening (chaosFitOpened), so a scroll by the player is not undone.
local function hook_onGeometryChange(self, oldRect, newRect)
  if base.onGeometryChange then base.onGeometryChange(self, oldRect, newRect) end
  if not fitting and not self.chaosFitOpened and overflowing(self) then fitOpen(self) end
  if not fitting and self:isVisible() then queueCentre(self) end
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
