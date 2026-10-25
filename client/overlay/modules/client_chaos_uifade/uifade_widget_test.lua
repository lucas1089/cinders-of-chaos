-- luajit uifade_widget_test.lua && lua5.3 uifade_widget_test.lua (from anywhere; CI runs it from the repo root)
-- The hook of uifade.lua against a mocked widget API: open, close, turn round, destroy mid-fade, option off, terminate.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- mocked engine ---------------------------------------------------------------------------------------------------
local clock = 0
g_clock = { millis = function() return clock end }
local queue = {}          -- scheduled events: { at, fn, dead }
function scheduleEvent(fn, ms) local e = { at = clock + ms, fn = fn }; queue[#queue + 1] = e; return e end
function removeEvent(e) if e then e.dead = true end end
local function advance(ms)
  local target = clock + ms
  while true do
    local best
    for _, e in ipairs(queue) do
      if not e.dead and not e.ran and e.at <= target and (not best or e.at < best.at) then best = e end
    end
    if not best then break end
    clock = best.at
    best.ran = true
    best.fn()
  end
  clock = target
end
local function pending()
  local n = 0
  for _, e in ipairs(queue) do if not e.dead and not e.ran then n = n + 1 end end
  return n
end

ActiveFocusReason = 2
local root = { id = 'root', getId = function(self) return self.id end, focusLog = 0 }
root.focusPreviousChild = function(self) self.focusLog = self.focusLog + 1 end
local gamePanel = { id = 'gameRootPanel', getId = function(self) return self.id end, focusLog = 0 }
gamePanel.focusPreviousChild = function(self) self.focusLog = self.focusLog + 1 end
g_ui = { getRootWidget = function() return root end }
modules = { client_settings = { getOption = function() return true end } }

UIWidget = {}
local W = UIWidget
W.__index = W
function W.isDestroyed(s) return s.destroyed == true end
function W.destroy(s) s.destroyed = true end
function W.setOpacity(s, v) s.opacity = v; s.opacityCalls = (s.opacityCalls or 0) + 1 end
function W.getOpacity(s) return s.opacity end
function W.setPhantom(s, v) s.phantom = v end
function W.isPhantom(s) return s.phantom end
function W.getParent(s) return s.parent end
function W.getSize(s) return { width = s.w, height = s.h } end
function W.getClassName(s) return s.class end
function W.isFocused(s) return s.focused end
function W.getId(s) return s.id end
function W.isVisible(s) return s.visible end
function W.isExplicitlyVisible(s) return s.visible end
function W.setVisible(s, v)
  if s.visible == v then return end
  s.visible = v
  if s.onVisibilityChange then s:onVisibilityChange(v) end
end
function W.show(s) s:setVisible(true) end
function W.hide(s) s:setVisible(false) end
function W.onVisibilityChange(s, v) s.vcLog = (s.vcLog or 0) + 1 end   -- stands for the UIWindow default (none in the base)
UIWindow = setmetatable({}, { __index = W })
UIWindow.__index = UIWindow
-- the default is not on UIWindow itself in the base: remove the stand-in so the hook finds none to chain
W.onVisibilityChange = nil

local function newWindow(opts)
  opts = opts or {}
  local w = setmetatable({ id = 'win', class = opts.class or 'UIWindow', parent = opts.parent or root, w = opts.w or 300,
    h = opts.h or 200, opacity = 1, phantom = false, visible = false, focused = false }, UIWindow)
  return w
end

-- the base's UIWindow.create: a new widget, visible, parent set later by the style/loader
local created = 0
function UIWindow.create() created = created + 1; return setmetatable({ id = 'new', class = 'UIWindow', w = 300, h = 200, opacity = 1, phantom = false, visible = true, focused = false }, UIWindow) end

dofile(dir .. 'uifade_logic.lua')
dofile(dir .. 'uifade.lua')
init()

-- a window made visible by the loader (no show() follows) fades in on the next loop
do
  local n = UIWindow.create()
  eq(created >= 1, true, 'the base create ran')
  eq(n.opacity, 0, 'made clear at creation')
  n.parent = root
  advance(0)
  eq(n.chaosFade ~= nil, true, 'fade started by the first event')
  advance(200)
  eq(n.opacity, 1, 'fully opaque')
  eq(pending(), 0, 'no timer left')
  local h = UIWindow.create()
  h.parent = root
  h:hide()
  eq(h.visible, false, 'hidden before the event: hides at once')
  advance(10)
  eq(h.opacity, 1, 'and is settled at opacity 1')
  local d = UIWindow.create()
  d:destroy()
  eq(pcall(advance, 20), true, 'destroyed before the event: quiet')
  local m = UIWindow.create(); m.class = 'UIMiniWindow'; m.parent = root
  advance(5)
  eq(m.opacity, 1, 'ineligible window settles at opacity 1')
  local s = UIWindow.create(); s.parent = root; s.visible = false
  s.opacity = 0
  advance(5)
  eq(s.opacity, 1, 'hidden new window settles at 1 for its later show')
  s:show()
  eq(s.opacity, 0, 'and fades in when shown')
  advance(200)
  eq(s.opacity, 1, 'then is opaque')
end

-- open ------------------------------------------------------------------------------------------------------------
local w = newWindow()
w:show()
eq(w.visible, true, 'visible at once')
eq(w.opacity, 0, 'opens clear')
eq(w.phantom, false, 'clickable while it fades in')
advance(70)
eq(w.opacity > 0 and w.opacity < 1, true, 'half way up')
advance(100)
eq(w.opacity, 1, 'fully opaque after the fade')
eq(w.chaosFade, nil, 'state dropped')
eq(pending(), 0, 'no timer left after an open')

-- close -----------------------------------------------------------------------------------------------------------
w.focused = true
w:hide()
eq(w.visible, true, 'still drawn while it fades out')
eq(w:isVisible(), false, 'but Lua is told it is hidden')
eq(w:isExplicitlyVisible(), false, 'explicit too')
eq(w.phantom, true, 'clicks go through while closing')
eq(root.focusLog, 1, 'the focus went on to the previous window in the same call')
advance(50)
eq(w.opacity < 1 and w.opacity > 0, true, 'half way down')
advance(80)
eq(w.visible, false, 'hidden for real after the fade')
eq(w.opacity, 1, 'next show starts at full opacity')
eq(w.phantom, false, 'phantom flag restored')
eq(w:isVisible(), false, 'still hidden')
eq(w.chaosFade, nil, 'state dropped after a close')
eq(pending(), 0, 'no timer left after a close')

-- a focused window hands its focus on at once
do
  local p = { id = 'x', getId = function(s) return s.id end, n = 0 }
  p.focusPreviousChild = function(s) s.n = s.n + 1 end
  local f = newWindow({ parent = root })
  f.parent = setmetatable({}, { __index = root })
  f.parent.id = 'gameRootPanel'; f.parent.n = 0
  f.parent.focusPreviousChild = function(s) s.n = s.n + 1 end
  f:show(); advance(200)
  f.focused = true
  f:hide()
  eq(f.parent.n, 1, 'focus moved on in the same call as hide()')
  advance(200)
end

-- toggle: show() during a close turns round without a jump
do
  local t = newWindow()
  t:show(); advance(200)
  t:hide(); advance(40)
  local mid = t.opacity
  t:show()
  eq(t.phantom, false, 'clickable again')
  eq(t:isVisible(), true, 'visible again')
  eq(math.abs(t.opacity - mid) < 0.001, true, 'no jump at the turn')
  advance(200)
  eq(t.opacity, 1, 'back to opaque')
  eq(t.visible, true, 'stays open')
  eq(pending(), 0, 'no timer left')
end

-- hide during the fade-in goes down from where it is
do
  local t = newWindow()
  t:show(); advance(30)
  local mid = t.opacity
  t:hide()
  eq(t.opacity <= mid + 0.001, true, 'starts down from the opacity it had')
  advance(300)
  eq(t.visible, false, 'hidden')
  eq(t.opacity, 1, 'opacity 1 for the next show')
end

-- a second hide() while closing does nothing
do
  local t = newWindow()
  t:show(); advance(200)
  t:hide(); advance(20)
  local mid = t.opacity
  t:hide()
  eq(t.opacity, mid, 'second hide changes nothing')
  advance(300)
  eq(t.visible, false, 'closed once')
end

-- destroyed mid-fade, both ways, never an error
do
  local t = newWindow()
  t:show(); advance(30)
  t:destroy()
  local ok = pcall(advance, 300)
  eq(ok, true, 'destroy in a fade-in: timers are quiet')
  local u = newWindow()
  u:show(); advance(200)
  u:hide(); advance(20)
  u:destroy()
  ok = pcall(advance, 300)
  eq(ok, true, 'destroy in a fade-out: timers are quiet')
end

-- other ways to hide are instant and leave a clean window
do
  local t = newWindow()
  t:show(); advance(30)
  t:setVisible(false)
  eq(t.opacity, 1, 'setVisible(false) mid-fade: opacity 1')
  eq(pending(), 0, 'and no timer')
  local u = newWindow()
  u:show(); advance(200)
  u:hide(); advance(20)
  u:setVisible(false)
  eq(u.visible, false, 'setVisible(false) mid-close hides at once')
  eq(u.opacity, 1, 'opacity 1')
  eq(u.phantom, false, 'phantom restored')
  advance(300)
  eq(u.visible, false, 'stays hidden')
end

-- windows that must not fade
do
  local mini = newWindow({ class = 'UIMiniWindow' })
  mini:show()
  eq(mini.opacity, 1, 'mini window: no fade-in')
  mini:hide()
  eq(mini.visible, false, 'mini window: hides at once')
  local small = newWindow({ w = 100, h = 40 })
  small:show(); eq(small.opacity, 1, 'small popup: no fade-in')
  small:hide(); eq(small.visible, false, 'small popup: hides at once')
  local phantom = newWindow(); phantom.phantom = true
  phantom:show(); eq(phantom.opacity, 1, 'phantom: no fade-in')
  phantom:hide(); eq(phantom.visible, false, 'phantom: hides at once'); eq(phantom.phantom, true, 'phantom flag untouched')
  local optout = newWindow(); optout.chaosNoFade = true
  optout:show(); eq(optout.opacity, 1, 'opt-out: no fade-in')
  optout:hide(); eq(optout.visible, false, 'opt-out: hides at once')
  local nested = newWindow({ parent = { id = 'panel', getId = function(s) return s.id end } })
  nested:show(); eq(nested.opacity, 1, 'nested: no fade-in')
  nested:hide(); eq(nested.visible, false, 'nested: hides at once')
  local orphan = newWindow(); orphan.parent = nil
  orphan:show(); eq(orphan.opacity, 1, 'no parent: no fade-in')
  orphan:hide(); eq(orphan.visible, false, 'no parent: hides at once')
  local hidden = newWindow()
  hidden:hide()
  eq(hidden.visible, false, 'hide of a hidden window is a no-op')
  eq(pending(), 0, 'no timers for any of these')
end

-- a window with its own opacity keeps it
do
  local t = newWindow(); t.opacity = 0.8
  t:show(); advance(300)
  eq(math.abs(t.opacity - 0.8) < 1e-9, true, 'own opacity after open')
  t:hide(); advance(300)
  eq(math.abs(t.opacity - 0.8) < 1e-9, true, 'own opacity after close')
end

-- option off: everything passes through; turning it off mid-fade finishes it
do
  local t = newWindow()
  t:show(); advance(200)
  t:hide(); advance(20)
  onOption('uiFade', false)
  eq(t.visible, false, 'option off mid-close: hidden at once')
  eq(t.opacity, 1, 'opacity 1')
  eq(pending(), 0, 'no timer')
  local u = newWindow()
  u:show()
  eq(u.opacity, 1, 'option off: no fade-in')
  u:hide()
  eq(u.visible, false, 'option off: hides at once')
  onOption('other', true)
  eq(newWindow().opacity, 1, 'unrelated option ignored')
  onOption('uiFade', true)
  local v = newWindow(); v:show()
  eq(v.opacity, 0, 'option on again: fades')
  advance(200)
end

-- terminate: finishes fades and removes the hook
do
  local t = newWindow()
  t:show(); advance(200)
  t:hide(); advance(20)
  terminate()
  eq(t.visible, false, 'terminate finishes a close')
  eq(t.opacity, 1, 'opacity 1')
  eq(rawget(UIWindow, 'hide'), nil, 'hide hook removed')
  eq(rawget(UIWindow, 'show'), nil, 'show hook removed')
  eq(rawget(UIWindow, 'isVisible'), nil, 'isVisible hook removed')
  eq(rawget(UIWindow, 'onVisibilityChange'), nil, 'visibility hook removed')
  local fresh = UIWindow.create()
  eq(fresh.opacity, 1, 'the base create is back (new windows are not made clear)')
  local x = newWindow(); x:show(); x:hide()
  eq(x.visible, false, 'plain behaviour after terminate')
end

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks failed'); os.exit(1) end
print('uifade_widget_test: ' .. checks .. ' checks passed')
