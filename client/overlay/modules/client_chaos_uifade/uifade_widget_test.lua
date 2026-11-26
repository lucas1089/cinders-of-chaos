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
root.children = {}
root.getChildren = function(self) return self.children end
root.recursiveGetChildById = function(self, id) if id == 'gameRootPanel' then return gamePanel end end
gamePanel.children = {}
gamePanel.getChildren = function(self) return self.children end
g_ui = { getRootWidget = function() return root end }
-- corelib connect / disconnect: a function field becomes a list, and the engine calls every function of a list field
function connect(o, t)
  for k, fn in pairs(t) do
    local cur = o[k]
    if cur == nil then o[k] = { fn }
    elseif type(cur) == 'function' then o[k] = { cur, fn }
    else cur[#cur + 1] = fn end
  end
end
function disconnect(o, t)
  for k, fn in pairs(t) do
    local cur = o[k]
    if type(cur) == 'table' then
      for i = #cur, 1, -1 do if cur[i] == fn then table.remove(cur, i) end end
    elseif cur == fn then o[k] = nil end
  end
end
modules = { client_settings = { getOption = function() return true end } }

-- the engine's model (corelib util.lua extends(), uiwindow.lua): UIWidget holds the engine methods and every widget finds them
-- through it; UIWindow is a plain table with NO metatable (UIWindow.hide is nil); UIWindow.create copies UIWindow's fields
-- into the new widget at that moment; the engine calls the widget's own onVisibilityChange field
UIWidget = {}
local W = UIWidget
local WIDGET = { __index = W }
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
  local f = s.onVisibilityChange
  if type(f) == 'table' then for _, fn in ipairs(f) do fn(s, v) end elseif f then f(s, v) end
end
function W.show(s) s:setVisible(true) end
function W.hide(s) s:setVisible(false) end
UIWindow = {}
eq(getmetatable(UIWindow), nil, 'the mock UIWindow has no metatable, like extends() makes it')
eq(UIWindow.hide, nil, 'and no hide of its own')

-- the base's UIWindow.create: a new widget with a copy of UIWindow's fields, visible, parent set later by the style/loader
local created = 0
function UIWindow.internalCreate()
  local w = setmetatable({ id = 'new', class = 'UIWindow', w = 300, h = 200, opacity = 1, phantom = false, visible = true,
    focused = false }, WIDGET)
  for k, v in pairs(UIWindow) do w[k] = v end
  return w
end
function UIWindow.create() created = created + 1; return UIWindow.internalCreate() end

-- a window as a module makes it, hidden until shown
local function newWindow(opts)
  opts = opts or {}
  local w = UIWindow.internalCreate()
  w.id, w.class, w.parent, w.w, w.h, w.visible = 'win', opts.class or 'UIWindow', opts.parent or root, opts.w or 300, opts.h or 200, false
  return w
end

-- corelib's dialog classes: uiinputbox.lua loads uiwindow.lua once before `dofiles 'ui'` loads it again, so UIMessageBox's
-- base is an older UIWindow table whose create calls the global UIWindow.internalCreate (the new table's fields, hooks
-- included) but never the global UIWindow.create
local oldWindow = { create = function() local w = UIWindow.internalCreate(); return w end }
local function extendsOld(name)
  local derived = {}
  function derived.internalCreate()
    local instance = oldWindow.create()
    for k, v in pairs(derived) do instance[k] = v end
    instance.class = name
    return instance
  end
  derived.create = derived.internalCreate
  return derived
end
UIMessageBox = extendsOld('UIMessageBox')
UIMessageBox.create = nil                  -- as corelib: "messagebox cannot be created from otui files"
UIInputBox = extendsOld('UIInputBox')
local mbInternal, ibCreate = UIMessageBox.internalCreate, UIInputBox.create

dofile(dir .. 'uifade_logic.lua')
dofile(dir .. 'uifade.lua')
local before = newWindow()                  -- made before the module loads, not at the top: never adopted
local seen = {}
local early = newWindow()                   -- the Options window: made at client_settings' init, a child of the root
early.onVisibilityChange = function() seen[#seen + 1] = 'own' end
root.children = { early }
local earlyGame = newWindow({ parent = gamePanel })
gamePanel.children = { earlyGame }
local earlyMini = newWindow({ class = 'UIMiniWindow' })
local ownHide = function(self) seen[#seen + 1] = 'ownHide'; W.hide(self) end
local earlyOwn = newWindow()
earlyOwn.hide = ownHide
root.children = { early, earlyMini, earlyOwn }
init()
eq(type(rawget(UIWindow, 'hide')), 'function', 'the hook is on UIWindow although it had no hide of its own')
eq(type(rawget(UIWindow, 'onVisibilityChange')), 'function', 'the visibility hook is on UIWindow')
before:show()
eq(before.opacity, 1, 'a window made before the hook, not on the top level: plain')
before:hide()

-- windows made before the hook at the top level are adopted (seen in a client 2026-11-26: the Options window)
do
  early:show()
  eq(early.opacity, 0, 'early window fades in')
  eq(seen[1], 'own', 'its own visibility handler still runs')
  advance(200)
  eq(early.opacity, 1, 'early window opaque after the fade')
  early:hide()
  eq(early.visible, true, 'early window fades out')
  eq(early:isVisible(), false, 'and Lua is told it is hidden')
  advance(200)
  eq(early.visible, false, 'early window hidden after the fade')
  eq(early.opacity, 1, 'early window back at opacity 1')
  earlyGame:show()
  eq(earlyGame.opacity, 0, 'early window in the game root panel fades in')
  advance(200)
  earlyGame:hide(); advance(200)
  eq(earlyGame.visible, false, 'and out')
  earlyMini:show()
  eq(earlyMini.opacity, 1, 'early mini window: not touched')
  eq(rawget(earlyMini, 'hide'), nil, 'no hide put on a mini window')
  earlyMini:hide()
  earlyOwn:show(); advance(200)
  earlyOwn:hide()
  eq(seen[#seen], 'ownHide', 'a window with its own hide keeps it')
  eq(earlyOwn.visible, false, 'and closes at once as before')
  local n0 = #early.onVisibilityChange
  init()
  eq(#early.onVisibilityChange, n0, 'a second init adopts nothing twice')
end

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
  local box = UIWindow.create(); box.class = 'UIMessageBox'; box.parent = root   -- displayGeneralBox: derived create
  advance(0)
  eq(box.opacity < 1, true, 'a message box dialog fades in')
  advance(200)
  eq(box.opacity, 1, 'message box opaque after the fade')
  box:hide()
  eq(box.visible, true, 'message box fades out on hide')
  advance(200)
  eq(box.visible, false, 'message box hidden after the fade')
  local gb = UIMessageBox.internalCreate(); gb.parent = root          -- displayGeneralBox: the older table's create
  eq(gb.opacity, 0, 'a displayGeneralBox dialog is made clear')
  advance(0)
  eq(gb.chaosFade ~= nil, true, 'and its fade-in starts on the next loop')
  advance(200)
  eq(gb.opacity, 1, 'displayGeneralBox dialog opaque after the fade')
  local ib = UIInputBox.create(); ib.parent = root
  eq(ib.opacity, 0, 'an input box is made clear')
  advance(200)
  eq(ib.opacity, 1, 'input box opaque after the fade')
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

-- a show that holds the loop: the first tick comes 446 ms late and the fade still plays (seen in a client 2026-11-26)
do
  local b = newWindow()
  b:show()
  eq(b.opacity, 0, 'busy open: clear at the show')
  clock = clock + 446                          -- the loop was held: the timer due in 16 ms runs now, 430 ms late
  for _, e in ipairs(queue) do if not e.dead and not e.ran and e.at < clock then e.at = clock end end
  advance(0)
  eq(b.opacity > 0 and b.opacity < 1, true, 'busy open: part way up at the first tick, not opaque at once')
  advance(60)
  eq(b.opacity > 0 and b.opacity < 1, true, 'busy open: still fading')
  advance(200)
  eq(b.opacity, 1, 'busy open: opaque after the fade')
  b:hide(); advance(200)
end

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
  eq(UIMessageBox.internalCreate, mbInternal, 'message box create back')
  eq(rawget(UIMessageBox, 'create'), nil, 'message box create stays nil')
  eq(UIInputBox.create, ibCreate, 'input box create back')
  eq(UIMessageBox.internalCreate().opacity, 1, 'a dialog made after terminate is not made clear')
  local fresh = UIWindow.create()
  eq(fresh.opacity, 1, 'the base create is back (new windows are not made clear)')
  local x = newWindow(); x:show(); x:hide()
  eq(x.visible, false, 'plain behaviour after terminate')
  eq(rawget(early, 'hide'), nil, 'adopted window: hide taken off')
  eq(rawget(early, 'isVisible'), nil, 'adopted window: isVisible taken off')
  early:show()
  eq(early.opacity, 1, 'adopted window: no fade after terminate')
  eq(#early.onVisibilityChange, 1, 'adopted window: only its own handler is left')
  early:hide()
  eq(early.visible, false, 'adopted window: hides at once')
  t:show()
  eq(t.opacity, 1, 'a window made while the hook was in passes straight through after terminate')
  t:hide()
  eq(t.visible, false, 'and hides at once')
  eq(t:isVisible(), false, 'isVisible is the engine answer')
end

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks failed'); os.exit(1) end
print('uifade_widget_test: ' .. checks .. ' checks passed')
