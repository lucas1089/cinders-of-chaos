-- client_chaos_uifade (O223): short fades on main windows and dialogs, from one hook on the UIWindow class, so the dozens
-- of window modules need no edit. Timing and rules are in uifade_logic.lua.
--  * Open: UIWindow:onVisibilityChange(true) starts a fade-in (0 -> 1, about 140 ms). The window is clickable and has focus
--    from the first frame; only its opacity moves.
--  * Close: UIWindow:hide() starts a fade-out (about 100 ms) and the window really hides when it ends. While it fades out
--    it is phantom (clicks go through to what is under it), it has given its focus back (as a real hide does), and
--    Lua asking isVisible() / isExplicitlyVisible() is told "hidden" at once, so a toggle key pressed in that tenth of a
--    second opens it again instead of closing it twice. show() during a close turns the fade round.
--  * A window made visible by createWidget / loadUI (most dialogs: no show() ever follows) is made clear in UIWindow.create
--    and fades in from the first event of the next loop.
--  * Not faded, always instant: destroy() (most dialogs close that way: a ghost with the id of a window that is gone would
--    break getChildById lookups), setVisible(false), C++ callers, UIMiniWindow (side panels), phantom windows (tooltips),
--    windows under 140x80, windows that are not a child of the root or of gameRootPanel, and a window with
--    `chaosNoFade = true`.
--  * Every scheduled step checks that the window is alive and that its fade is still the current one. Any hide path, a
--    destroy and a terminate end with opacity 1 and the phantom flag as it was, so the next show starts clean.
-- The option uiFade (default on) comes from client_settings (base patch 0141); off, the hook passes everything through.
local L = UiFadeLogic

local enabled = true
local base = {}        -- the functions the hook wraps
local mine = {}        -- the functions the hook installed (so terminate only removes its own)
local installed = false
local live = {}        -- windows with a running fade (weak), so terminate can finish them

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

local function nowMs()
  return g_clock.millis()
end

local function closing(w)
  local st = w.chaosFade
  return st ~= nil and st.closing == true
end

-- back to normal: no timer, opacity 1, the phantom flag as it was
local function clear(w)
  local st = w.chaosFade
  w.chaosFade = nil
  if st then
    if st.event then removeEvent(st.event); st.event = nil end
    if st.closing and alive(w) then w:setPhantom(st.wasPhantom == true) end
  end
  if alive(w) then w:setOpacity(st and st.own or 1) end
  live[w] = nil
end

local function finish(w, st)
  if not alive(w) or w.chaosFade ~= st then return end
  if st.closing then
    -- the window is really hidden now; the state goes first so the visibility answers below are the real ones
    clear(w)
    base.hide(w)
  else
    clear(w)
  end
end

local function tick(w, st)
  if not alive(w) or w.chaosFade ~= st then return end
  st.event = nil
  local value, done, changed = L.step(st.fade, nowMs())
  if done then
    finish(w, st)
    return
  end
  if changed then w:setOpacity(value * st.own) end
  st.event = scheduleEvent(function() tick(w, st) end, L.CFG.tickMs)
end

-- start a fade of kind 'in' or 'out' from `from` (a share of the window's own opacity, 1 for most windows)
local function run(w, kind, from, closingNow)
  local old = w.chaosFade
  local own = old and old.own
  if not own then
    own = w:getOpacity()
    if own < 0.05 then own = 1 end                        -- a window that was left nearly clear is a mistake, not a design
  end
  if old and old.event then removeEvent(old.event); old.event = nil end
  local fade = L.begin(kind, nowMs(), from)
  local st = { fade = fade, own = own, closing = closingNow == true }
  w.chaosFade = st
  live[w] = true
  w:setOpacity(L.step(fade, fade.t0) * own)
  st.event = scheduleEvent(function() tick(w, st) end, L.CFG.tickMs)
  return st
end

local function canFade(w)
  if not enabled then return false end
  local parent = w:getParent()
  if not parent then return false end
  local root = g_ui.getRootWidget()
  local size = w:getSize()
  return L.eligible({
    on = true,
    className = w:getClassName(),
    topLevel = parent == root or parent:getId() == 'gameRootPanel',
    phantom = w:isPhantom(),
    noFade = w.chaosNoFade,
    w = size and size.width,
    h = size and size.height,
  })
end

-- hide(): fade out, then hide for real
local function hook_hide(self, ...)
  local st = self.chaosFade
  if st and st.closing then return end                      -- already on its way out
  -- nothing to fade out when it is not drawn yet (a window made clear at creation, closed before its first frame)
  if not alive(self) or not base.isExplicitlyVisible(self) or self:getOpacity() < 0.02 or not canFade(self) then
    if st then clear(self) end
    return base.hide(self, ...)
  end
  local own = st and st.own or self:getOpacity()
  local from = own > 0 and (self:getOpacity() / own) or 1
  local wasPhantom = self:isPhantom()
  local now = run(self, 'out', from, true)
  now.wasPhantom = wasPhantom
  self:setPhantom(true)
  -- a real hide gives the focus to the previous window; do that now so keys reach the game at once
  if self:isFocused() then
    local parent = self:getParent()
    if parent then parent:focusPreviousChild(ActiveFocusReason, true) end
  end
end

-- show(): a window on its way out turns round
local function hook_show(self, ...)
  local st = self.chaosFade
  if st and st.closing then
    local from = st.own > 0 and (self:getOpacity() / st.own) or 0
    self:setPhantom(st.wasPhantom == true)
    st.closing = false
    run(self, 'in', from, false)
  end
  return base.show(self, ...)
end

-- Lua code that asks whether the window is up is told the truth about the close that has begun
local function hook_isVisible(self)
  if closing(self) then return false end
  return base.isVisible(self)
end

local function hook_isExplicitlyVisible(self)
  if closing(self) then return false end
  return base.isExplicitlyVisible(self)
end

local function hook_onVisibilityChange(self, visible)
  if base.onVisibilityChange then base.onVisibilityChange(self, visible) end
  if not alive(self) then return end
  if not visible then
    if self.chaosFade then clear(self) end
    return
  end
  if canFade(self) then
    run(self, 'in', 0, false)
  elseif self.chaosFade then
    clear(self)
  end
end

-- a window made by g_ui.createWidget / loadUI is visible from the start, so no visibility change ever announces it: it is
-- made clear here and settled by the first event of the next loop, when its style, parent and size are in place
local function settleNew(w)
  if not alive(w) or w.chaosFade then return end
  if base.isExplicitlyVisible(w) and canFade(w) then
    run(w, 'in', 0, false)
  else
    w:setOpacity(1)
  end
end

local function hook_create(...)
  local w = base.create(...)
  if enabled and w and alive(w) then
    w:setOpacity(0)
    scheduleEvent(function() settleNew(w) end, 0)
  end
  return w
end

local function install()
  if installed or not UIWindow then return end
  base.hide = UIWindow.hide
  base.show = UIWindow.show
  base.isVisible = UIWindow.isVisible
  base.isExplicitlyVisible = UIWindow.isExplicitlyVisible
  base.onVisibilityChange = rawget(UIWindow, 'onVisibilityChange')
  base.create = rawget(UIWindow, 'create')
  if not (base.hide and base.show and base.isVisible and base.isExplicitlyVisible) then return end
  mine.hide, mine.show, mine.isVisible, mine.isExplicitlyVisible = hook_hide, hook_show, hook_isVisible, hook_isExplicitlyVisible
  mine.onVisibilityChange = hook_onVisibilityChange
  if base.create then mine.create = hook_create; UIWindow.create = hook_create end
  UIWindow.hide = hook_hide
  UIWindow.show = hook_show
  UIWindow.isVisible = hook_isVisible
  UIWindow.isExplicitlyVisible = hook_isExplicitlyVisible
  UIWindow.onVisibilityChange = hook_onVisibilityChange
  installed = true
end

local function uninstall()
  if not installed then return end
  for name, fn in pairs(mine) do
    if rawget(UIWindow, name) == fn then
      local was = nil
      if name == 'onVisibilityChange' then was = base.onVisibilityChange elseif name == 'create' then was = base.create end
      UIWindow[name] = was
    end
  end
  mine = {}
  installed = false
end

-- end every running fade at once: closing windows hide for real, opening ones are fully visible
local function finishAll()
  local list = {}
  for w in pairs(live) do list[#list + 1] = w end
  for _, w in ipairs(list) do
    local st = w.chaosFade
    if alive(w) and st then finish(w, st) else live[w] = nil end
  end
end

function onOption(name, value)
  if name ~= 'uiFade' then return end
  enabled = value ~= false
  if not enabled then finishAll() end
end

function init()
  setmetatable(live, { __mode = 'k' })
  local ok, value = pcall(function() return modules.client_settings.getOption('uiFade') end)
  enabled = not (ok and value == false)
  install()
end

function terminate()
  finishAll()
  uninstall()
end
