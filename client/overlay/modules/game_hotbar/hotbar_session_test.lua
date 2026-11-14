-- luajit hotbar_session_test.lua && lua5.3 hotbar_session_test.lua
-- The action bar layout over whole sessions (client/MANIFEST.md "Floating chat and central hotbar (O414)", "Death and
-- re-login"): the real layoutmode.lua, hotbar.lua and floatchat.lua run on a small widget mock of the base client
-- (root panel, bottom action panel with three bars, console panel). Sequence: login, death (a fast relog: game end, game
-- start at once), a plain logout and login, a reconnect, and the base rebuilding things. After each start the bar is
-- adopted again, the globes are docked, the chat floats with the console in it.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'

-- ---------------------------------------------------------------- the clock and the event queue
local now = 1000
local queue, nextId = {}, 0
local function addEvent(fn)
  nextId = nextId + 1
  local e = { id = nextId, at = now, fn = fn, seq = nextId }
  queue[#queue + 1] = e
  return e
end
local function scheduleEvent(fn, ms)
  local e = addEvent(fn)
  e.at = now + (ms or 0)
  return e
end
local function removeEvent(e) if e then e.dead = true end end
local function pump(ms)
  local stop = now + ms
  while true do
    local best
    for _, e in ipairs(queue) do
      if not e.dead and e.at <= stop and (not best or e.at < best.at or (e.at == best.at and e.seq < best.seq)) then best = e end
    end
    if not best then break end
    best.dead = true
    if best.at > now then now = best.at end
    best.fn()
  end
  now = stop
end

-- ---------------------------------------------------------------- the widget mock
local Widget = {}
local function newWidget(id, parent)
  local w = setmetatable({ _id = id, _children = {}, _visible = true, _p = { x = 0, y = 0, width = 100, height = 20, ml = 0, mr = 0, mt = 0, mb = 0 } }, Widget)
  if parent then w._parent = parent; parent._children[#parent._children + 1] = w end
  return w
end
Widget.__index = function(t, k)
  local v = Widget[k]
  if v ~= nil then return v end
  if type(k) == 'string' and (k:match('^set') or k:match('^add') or k == 'raise' or k == 'lower' or k == 'fill' or k == 'breakAnchors' or k == 'focus') then
    return function() end
  end
end
function Widget:getId() return self._id end
function Widget:setId(id) self._id = id end
function Widget:getChildren() local out = {} for i, c in ipairs(self._children) do out[i] = c end return out end
function Widget:getChildById(id) for _, c in ipairs(self._children) do if c._id == id then return c end end end
function Widget:recursiveGetChildById(id)
  for _, c in ipairs(self._children) do
    if c._id == id then return c end
    local r = c:recursiveGetChildById(id)
    if r then return r end
  end
end
function Widget:getParent() return self._parent end
function Widget:isDestroyed() return self._destroyed == true end
function Widget:destroy()
  if self._destroyed then return end
  if self._parent then
    for i, c in ipairs(self._parent._children) do if c == self then table.remove(self._parent._children, i) break end end
  end
  self._parent = nil
  self._destroyed = true
  for _, c in ipairs(self._children) do c._destroyed = true end
end
function Widget:setParent(p)
  assert(not self._destroyed, 'setParent on a destroyed widget')
  if self._parent then
    for i, c in ipairs(self._parent._children) do if c == self then table.remove(self._parent._children, i) break end end
  end
  self._parent = p
  if p then p._children[#p._children + 1] = self end
end
function Widget:moveChildToIndex(child, index)
  for i, c in ipairs(self._children) do if c == child then table.remove(self._children, i) break end end
  table.insert(self._children, math.max(1, math.min(index, #self._children + 1)), child)
end
-- the engine's two flags: isVisible is the effective one (a hidden ancestor hides it), isExplicitlyVisible the widget's own
function Widget:isExplicitlyVisible() return self._visible end
function Widget:isVisible()
  local w = self
  while w do
    if not w._visible then return false end
    w = w._parent
  end
  return true
end
function Widget:setVisible(v) self._visible = v == true end
function Widget:setSize(s) self._p.width, self._p.height = s.width, s.height; self._sized = true end
function Widget:setWidth(v) self._p.width = v end
function Widget:setHeight(v) self._p.height = v end
function Widget:getWidth() return self._p.width end
function Widget:getHeight() return self._p.height end
function Widget:getX() return self._p.x end
function Widget:getY() return self._p.y end
function Widget:getRect() return { x = self._p.x, y = self._p.y, width = self._p.width, height = self._p.height } end
function Widget:setMarginLeft(v) self._p.ml = v end
function Widget:setMarginRight(v) self._p.mr = v end
function Widget:setMarginTop(v) self._p.mt = v end
function Widget:setMarginBottom(v) self._p.mb = v end
function Widget:getMarginTop() return self._p.mt end
function Widget:setText(t) self._text = t end
function Widget:getText() return self._text or '' end
function Widget:isEnabled() return true end
function Widget:containsPoint() return false end
function Widget:getLayout() return nil end
-- hit test of the mock: the child a test put under the pointer (nil: the widget itself)
function Widget:recursiveGetChildByPos() return self._hitChild end
function Widget:getClassName() return self._class or 'UIWidget' end
function Widget:setImageSource(s) self._image = s end
function Widget:setImageClip() end
function Widget:setClipping(v) self._clip = v end
function Widget:getChildCount() return #self._children end
function Widget:breakAnchors() end

local function add(parent, id, w, h)
  local c = newWidget(id, parent)
  if w then c._p.width, c._p.height = w, h or w end
  return c
end

-- ---------------------------------------------------------------- the base client's tree
local root, panel, bars, bottomPanel, consolePanel
local function buildBase()
  root = newWidget('gameRootPanel')
  root._p = { x = 0, y = 0, width = 1280, height = 720, ml = 0, mr = 0, mt = 0, mb = 0 }
  add(root, 'gameLeftPanels', 0, 720)._visible = false
  local rp = add(root, 'gameRightPanels', 190, 720)
  rp._p.x = 1090
  add(root, 'bottomSplitter', 1280, 6)
  bottomPanel = add(root, 'gameBottomPanel', 1280, 120)
  panel = add(root, 'gameBottomActionPanel', 800, 40)
  bars = {}
  for i = 1, 3 do
    local bar = add(panel, 'actionbar.' .. i, 800, 36)
    bars[i] = bar
    bar._visible = i == 1
    local tab = add(bar, 'tabBar', 800, 36)
    bar.tabBar = tab
    for n = 1, 50 do
      local b = add(tab, i .. '.' .. n, 34, 34)
      b.cooldown = { getDuration = function() return 0 end, getTimeElapsed = function() return 0 end, stop = function() end }
      add(b, 'text', 30, 27)
    end
    add(bar, 'lock', 12, 36)
  end
  -- the console: a panel in gameBottomPanel with its content panel and tab bar
  consolePanel = add(bottomPanel, 'consolePanel', 800, 100)
  add(consolePanel, 'consoleContentPanel', 800, 80)
  local tabBar = add(consolePanel, 'consoleTabBar', 800, 20)
  function tabBar:getTabs() return {} end
  function tabBar:getCurrentTab() return nil end
  add(consolePanel, 'consoleTextEdit', 700, 20)
end

local function buildStyle(style, parent)
  local w = newWidget(nil, parent)
  if style == 'ChaosHotbar' then
    w._id = 'chaosHotbar'
    for _, id in ipairs({ 'body', 'capL', 'capR', 'gem', 'line', 'socketL', 'socketR', 'handle', 'chatButton', 'gearButton', 'chatDot' }) do add(w, id, 20, 20) end
  elseif style == 'ChaosHotbarKey' then
    add(w, 'text', 30, 14)
  elseif style == 'ChaosFloatChat' then
    local header = add(w, 'header', 380, 24)
    for _, id in ipairs({ 'channels', 'private' }) do
      local t = add(header, id, 80, 20)
      for _, cid in ipairs({ 'icon', 'label', 'badge' }) do add(t, cid, 10, 10) end
    end
    add(header, 'close', 20, 20)
    add(header, 'options', 20, 20)
    add(w, 'content', 380, 120)
    add(w, 'grip', 12, 12)
  end
  return w
end

-- ---------------------------------------------------------------- engine globals
local handlers = {}  -- signal -> list of handler tables, in connect order
local online = false
local settings = {}
local warnings = {}
local docks = {}     -- every setOrbDock call of the hotbar
g_game = {
  isOnline = function() return online end,
  getLocalPlayer = function() return online and { getName = function() return 'Vexa' end } or nil end,
}
g_clock = { millis = function() return now end }
g_ui = {
  importStyle = function() end,
  createWidget = function(style, parent) return buildStyle(style, parent) end,
}
g_settings = {
  getNode = function(n) return settings[n] end,
  setNode = function(n, v) settings[n] = v end,
  save = function() end,
}
g_app = { isMobile = function() return false end }
g_logger = { warning = function(m) warnings[#warnings + 1] = m end, info = function() end }
g_window = { getMousePosition = function() return { x = 0, y = 0 } end }
g_keyboard = { bindKeyDown = function() end, unbindKeyDown = function() end }
AnchorLeft, AnchorRight, AnchorTop, AnchorBottom, AnchorHorizontalCenter = 1, 2, 3, 4, 5
MouseLeftButton, MouseRightButton = 1, 2
function tr(s, ...) if select('#', ...) > 0 then return string.format(s, ...) end return s end
function addEvent_(fn) return addEvent(fn) end
_G.addEvent, _G.scheduleEvent, _G.removeEvent = addEvent, scheduleEvent, removeEvent
function connect(obj, t)
  if obj ~= g_game then return end
  for k, f in pairs(t) do
    handlers[k] = handlers[k] or {}
    table.insert(handlers[k], f)
  end
end
function disconnect(obj, t)
  if obj ~= g_game then return end
  for k, f in pairs(t) do
    local list = handlers[k] or {}
    for i = #list, 1, -1 do if list[i] == f then table.remove(list, i) break end end
  end
end
local function fire(signal, ...)
  local list = {}
  for i, f in ipairs(handlers[signal] or {}) do list[i] = f end
  for _, f in ipairs(list) do if f(...) then break end end -- the engine stops at the first handler that returns true
end

modules = {
  game_interface = { getRootPanel = function() return root end, getBottomPanel = function() return bottomPanel end },
  game_console = {},
  game_shaderfx = { setOrbDock = function(d, s) docks[#docks + 1] = { diameter = d, suppress = s } end },
}
Options = nil

-- ---------------------------------------------------------------- load the real modules
dofile(dir .. 'hotbar_logic.lua')
dofile(dir .. '../game_floatchat/floatchat_logic.lua')
dofile(dir .. '../client_chaos_settings/settingslist.lua')
dofile(dir .. '../game_chatpanel/layoutmode_logic.lua')
dofile(dir .. '../game_chatpanel/layoutmode.lua')
dofile(dir .. 'hotbar_options.lua')
dofile(dir .. 'hotbar.lua')
dofile(dir .. '../game_floatchat/floatchat.lua')

local fails = 0
local function check(cond, what)
  if not cond then print('FAIL ' .. what); fails = fails + 1 end
end

local function login()
  online = true
  fire('onGameStart')
  pump(400)
end
local function logout()
  online = false
  fire('onGameEnd')
end

local function frameOf() return root:getChildById('chaosHotbar') end
local function lastDock() return docks[#docks] end

local function expectWorking(label)
  local frame = frameOf()
  check(frame ~= nil and not frame:isDestroyed(), label .. ': hotbar frame exists')
  if not frame then return end
  check(ChaosHotbar.isActive(), label .. ': hotbar active')
  check(bars[1]:getParent() == frame, label .. ': bar 1 is in the hotbar frame')
  check(frame._p.width > 200, label .. ': frame laid out (' .. tostring(frame._p.width) .. ')')
  local d = lastDock()
  check(d ~= nil and d.diameter ~= nil, label .. ': globes docked')
  local count = 0
  for _, c in ipairs(root._children) do if c._id == 'chaosHotbar' then count = count + 1 end end
  check(count == 1, label .. ': one hotbar frame in the root, not ' .. count)
  local fc = root:getChildById('chaosFloatChat') or nil
  check(consolePanel:getParent() ~= nil and consolePanel:getParent()._id == 'content', label .. ': the console is in the floating chat')
  check(ChaosFloatChat.getRect() ~= nil, label .. ': the chat floats')
end

local function expectOff(label)
  check(frameOf() == nil, label .. ': no hotbar frame after the end')
  check(not ChaosHotbar.isActive(), label .. ': hotbar not active')
  check(consolePanel:getParent() == bottomPanel, label .. ': the console went back to the bottom panel')
end

buildBase()
modules.game_console.consolePanel = consolePanel
ChaosLayoutMode.init()
ChaosFloatChat.init()
ChaosHotbar.init()

login()
expectWorking('first login')

-- O558: the Q and E sockets have a ring drawn over the base button (a square), above the bar and below the key box and the
-- cooldown number; the other slots have none
do
  local frame = frameOf()
  local kids, barAt, rings = frame._children, nil, {}
  for i, c in ipairs(kids) do
    if c == bars[1] then barAt = i end
    if c._image == '/modules/game_hotbar/images/hotbar_ring' then rings[#rings + 1] = i end
  end
  check(#rings == 2, 'O558: two rings (Q and E), not ' .. #rings)
  check(barAt ~= nil and rings[1] ~= nil and rings[1] > barAt, 'O558: the ring is drawn over the base bar')
  check(rings[2] ~= nil and rings[2] > rings[1], 'O558: both rings over the bar')
  local lastKey = 0
  for i, c in ipairs(kids) do if c._class == nil and c._children[1] and c._children[1]._id == 'text' then lastKey = math.max(lastKey, i) end end
  check(lastKey > rings[1], 'O558: the key boxes are over the ring')
end

-- O498: a press on a header button never begins a window drag; a drag whose release nobody heard ends at the next move
-- with the left button up; hiding and logout end a drag
do
  local win = consolePanel:getParent():getParent()
  local header = win:getChildById('header')
  local buttonDown = true
  g_mouse = { isPressed = function() return buttonDown end }
  local function marginLeft() return win._p.ml end
  local before = marginLeft()
  header._hitChild = header:getChildById('channels')
  header._hitChild._class = 'UIButton'
  check(header.onMousePress(header, { x = 40, y = 10 }, MouseLeftButton) == false, 'O498: a press on the Channels button is not a drag')
  header.onMouseMove(header, { x = 300, y = 200 })
  check(marginLeft() == before, 'O498: moving after a button press does not move the window')
  header._hitChild = nil
  check(header.onMousePress(header, { x = 200, y = 10 }, MouseLeftButton) == true, 'O498: a press on the header begins a drag')
  buttonDown = false -- the release went to another widget
  check(header.onMouseMove(header, { x = 300, y = 200 }) == false, 'O498: a move with the button up is not a drag')
  check(marginLeft() == before, 'O498: a stuck drag does not move the window')
  buttonDown = true
  header.onMousePress(header, { x = 200, y = 10 }, MouseLeftButton)
  header.onMouseMove(header, { x = 230, y = 40 })
  check(marginLeft() ~= before, 'O498: a live drag moves the window')
  check(header.onMouseRelease(header, { x = 230, y = 40 }, MouseLeftButton) == true, 'O498: a release ends the drag')
  local placed = marginLeft()
  header.onMouseMove(header, { x = 600, y = 300 })
  check(marginLeft() == placed, 'O498: after the release the window stays')
  -- a drag, then the chat is hidden: the drag ends
  header.onMousePress(header, { x = 200, y = 10 }, MouseLeftButton)
  ChaosFloatChat.hide()
  ChaosFloatChat.show()
  header.onMouseMove(header, { x = 700, y = 350 })
  check(marginLeft() == placed, 'O498: hide ends a drag (' .. tostring(marginLeft()) .. ' vs ' .. tostring(placed) .. ')')
  g_mouse = nil
end

-- a death: the death window's Ok logs out and in at once
logout()
expectOff('death logout')
login()
expectWorking('after the death')

-- a plain logout, a while on the character list, a login
logout()
pump(5000)
expectOff('logout')
login()
expectWorking('after a logout')

-- a reconnect: end and start in the same frame, the old session's events still queued
logout()
online = true
fire('onGameStart')
pump(30)
logout()
login()
expectWorking('after two quick relogs')

-- the bar given back at the end sits where it was: first in the panel (the base walks the panel in order)
logout()
check(panel._children[1] == bars[1], 'the bar is the first child of the bottom action panel again')
check(bars[1]:isVisible(), 'the bar is visible again')
login()

-- the base rebuilt the action bars (a destroyed bar widget): the hotbar adopts the new bar
logout()
local old = bars[1]
old:destroy()
local fresh = add(panel, 'actionbar.1', 800, 36)
bars[1] = fresh
panel:moveChildToIndex(fresh, 1)
fresh.tabBar = add(fresh, 'tabBar', 800, 36)
for n = 1, 50 do
  local b = add(fresh.tabBar, '1.' .. n, 34, 34)
  b.cooldown = { getDuration = function() return 0 end, getTimeElapsed = function() return 0 end, stop = function() end }
  add(b, 'text', 30, 27)
end
login()
expectWorking('after the base rebuilt the bar')

-- the bars appear late (21 s and more after the start): the hotbar still adopts them
logout()
local hold = {}
for i = #panel._children, 1, -1 do hold[#hold + 1] = panel._children[i]; panel._children[i]._parent = nil; table.remove(panel._children, i) end
online = true
fire('onGameStart')
pump(30000)
check(ChaosHotbar.isActive(), 'late bars: still waiting for them')
check(frameOf() == nil or not frameOf():isVisible(), 'late bars: no half-built frame is shown meanwhile')
for _, w in ipairs(hold) do w._parent = panel; panel._children[#panel._children + 1] = w end
panel:moveChildToIndex(bars[1], 1)
pump(5000)
expectWorking('late bars')

-- the layout mode handler chain is cut at the end (an earlier handler returned true): the next start cleans up
logout()
login()
local savedList = handlers.onGameEnd
handlers.onGameEnd = { function() return true end }
online = false
fire('onGameEnd')
handlers.onGameEnd = savedList
check(frameOf() ~= nil, 'a cut end chain: the hotbar frame is still there (nothing ended it)')
login()
expectWorking('after a cut end chain')

-- mid-session: the base destroys the bar and builds a new one (the watchdog adopts it), and rebuilds the console panel
do
  bars[1]:destroy()
  local fresh2 = add(panel, 'actionbar.1', 800, 36)
  bars[1] = fresh2
  panel:moveChildToIndex(fresh2, 1)
  fresh2.tabBar = add(fresh2, 'tabBar', 800, 36)
  for n = 1, 50 do
    local b = add(fresh2.tabBar, '1.' .. n, 34, 34)
    b.cooldown = { getDuration = function() return 0 end, getTimeElapsed = function() return 0 end, stop = function() end }
    add(b, 'text', 30, 27)
  end
  consolePanel:destroy()
  consolePanel = add(bottomPanel, 'consolePanel', 800, 100)
  add(consolePanel, 'consoleContentPanel', 800, 80)
  add(consolePanel, 'consoleTabBar', 800, 20).getTabs = function() return {} end
  add(consolePanel, 'consoleTextEdit', 700, 20)
  modules.game_console.consolePanel = consolePanel
  pump(1500)
  check(fresh2:getParent() == frameOf(), 'mid-session: the rebuilt bar is adopted')
  check(consolePanel:getParent() ~= nil and consolePanel:getParent()._id == 'content', 'mid-session: the rebuilt console is in the chat')
end

os.exit(fails == 0 and 0 or 1)
