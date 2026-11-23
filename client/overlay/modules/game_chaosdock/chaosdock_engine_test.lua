-- luajit chaosdock_engine_test.lua: chaosdock.lua on a fake engine (widgets, settings, keys, events). The windows move into
-- the dock and back to their place, open or closed as before; a wide window floats; the menu and the keys route.
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

-- ---------------------------------------------------------------- fake engine
AnchorTop, AnchorBottom, AnchorLeft, AnchorRight = 1, 2, 3, 4
local W = {}
W.__index = W
local function widget(class, id, parent)
  local w = setmetatable({ class = class or 'UIWidget', id = id, children = {}, visible = true, x = 0, y = 0,
    width = 100, height = 100, handlers = {}, draggable = true }, W)
  if parent then parent:addChild(w) end
  return w
end
function W:isDestroyed() return self.destroyed == true end
function W:destroy() self.destroyed = true if self.parent then self.parent:removeChild(self) end end
function W:getClassName() return self.class end
function W:getId() return self.id end
function W:setId(id) self.id = id end
function W:getChildren() local out = {} for i, c in ipairs(self.children) do out[i] = c end return out end
function W:getChildCount() return #self.children end
function W:getParent() return self.parent end
function W:addChild(c) c.parent = self self.children[#self.children + 1] = c end
function W:removeChild(c)
  for i, x in ipairs(self.children) do if x == c then table.remove(self.children, i) c.parent = nil return end end
end
function W:insertChild(i, c) c.parent = self table.insert(self.children, i, c) end
function W:getChildIndex(c) for i, x in ipairs(self.children) do if x == c then return i end end end
function W:setParent(p) if self.parent then self.parent:removeChild(self) end if p then p:addChild(self) end end
function W:getChildById(id) for _, c in ipairs(self.children) do if c.id == id then return c end end end
function W:recursiveGetChildById(id)
  for _, c in ipairs(self.children) do
    if c.id == id then return c end
    local d = c:recursiveGetChildById(id)
    if d then return d end
  end
end
function W:destroyChildren() for _, c in ipairs(self:getChildren()) do c:destroy() end end
function W:isVisible() return self.visible and (not self.parent or self.parent:isVisible()) end
function W:isExplicitlyVisible() return self.visible end
function W:setVisible(v)
  local was = self.visible
  self.visible = v and true or false
  if was ~= self.visible then for _, h in ipairs(self.handlers) do if h.onVisibilityChange then h.onVisibilityChange(self, self.visible) end end end
end
function W:show() self:setVisible(true) end
function W:hide() self:setVisible(false) end
function W:raise() end
function W:focus() end
function W:breakAnchors() self.anchors = {} end
function W:addAnchor(a) self.anchors = self.anchors or {} self.anchors[#self.anchors + 1] = a end
function W:setMargin() end
function W:setMarginBottom(m) self.marginBottom = m end
function W:setMarginRight(m) self.marginRight = m end
function W:getSize() return { width = self.width, height = self.height } end
function W:setSize(s) self.width, self.height = s.width, s.height end
function W:getWidth() return self.width end
function W:getHeight() return self.height end
function W:setWidth(v) self.width = v end
function W:setHeight(v) self.height = v end
function W:getX() return self.x end
function W:getPosition() return { x = self.x, y = self.y } end
function W:setPosition(p) self.x, self.y = p.x, p.y end
function W:getRect() return { x = self.x, y = self.y, width = self.width, height = self.height } end
function W:setDraggable(v) self.draggable = v end
function W:isDraggable() return self.draggable end
function W:setText(t) self.text = t end
function W:setTooltip(t) self.tooltip = t end
function W:setChecked(v) self.checked = v end
function W:setImageSource(s) self.image = s end
function W:setImageClip(c) self.clip = c end
function W:setImageColor(c) self.color = c end

local root = widget('UIWidget', 'root')
root.width, root.height = 1280, 720
local gameRoot = widget('UIWidget', 'gameRootPanel', root)
gameRoot.width, gameRoot.height = 1280, 720
local rightPanels = widget('UIWidget', 'gameRightPanels', gameRoot)
local container = widget('UIMiniWindowContainer', 'gameRightPanel', rightPanels)
local skillsMini = widget('UIMiniWindow', 'skillWindow', container)
local bag = widget('UIMiniWindow', 'bagPanel', container)
bag.width, bag.height = 200, 400
widget('UIButton', 'closeButton', bag)

local function makeDock(parent)
  local p = widget('UIWidget', 'chaosDock', parent)
  p.width, p.height = 330, 720
  for _, id in ipairs({ 'title', 'closeX', 'tabs', 'subs', 'rule', 'note' }) do widget('UIWidget', id, p) end
  local content = widget('UIWidget', 'content', p)
  content.width, content.height = 310, 600
  return p
end

g_ui = {
  importStyle = function() end,
  getRootWidget = function() return root end,
  createWidget = function(style, parent)
    if style == 'ChaosDockPanel' then return makeDock(parent) end
    local w = widget('UIButton', nil, parent)
    if style == 'ChaosDockTab' then widget('UIWidget', 'glyph', w) widget('UILabel', 'label', w) end
    return w
  end,
}
local store = {}
g_settings = { getString = function(k) return store[k] or '' end, set = function(k, v) store[k] = tostring(v) end }
g_app = { isMobile = function() return false end }
local online = true
g_game = { isOnline = function() return online end }
local keys = {}
g_keyboard = { bindKeyDown = function(k, fn) keys[k] = fn end, unbindKeyDown = function(k) keys[k] = nil end }
local queue = {}
function scheduleEvent(fn) queue[#queue + 1] = fn return fn end
function removeEvent(ev) for i, f in ipairs(queue) do if f == ev then table.remove(queue, i) return end end end
local function runEvents(max)
  for _ = 1, max or 200 do
    local fn = table.remove(queue, 1)
    if not fn then return end
    fn()
  end
end
local gameHandlers
function connect(obj, h) if obj == g_game then gameHandlers = h else obj.handlers[#obj.handlers + 1] = h end end
function disconnect(obj, h)
  if obj == g_game then return end
  for i, x in ipairs(obj.handlers) do
    if x.onVisibilityChange == h.onVisibilityChange then table.remove(obj.handlers, i) return end
  end
end
function tr(s) return s end

-- the windows the menu entries open (a module that keeps its window local: the dock finds it as the new one)
local opened = {}
local spellbook, store960
local ran = {}
local fakeTopbar = { runRaw = function(text)
  ran[#ran + 1] = text
  if text == 'Spellbook' then
    spellbook = spellbook or widget('UIWindow', 'spellbookWindow', root)
    spellbook.width, spellbook.height = 640, 460
    spellbook:show()
  elseif text == 'Store' then
    store960 = store960 or widget('UIWindow', 'shopWindow', root)
    store960.width, store960.height = 960, 530
    store960:show()
  end
  opened[#opened + 1] = text
  return true
end }
modules = {
  game_interface = { getRootPanel = function() return gameRoot end },
  client_chaos_topbar = { ChaosTopBar = fakeTopbar, ChaosTopBarGlyphs = dofile(here .. '../client_chaos_topbar/topbar_glyph_index.lua') },
  game_bagpanel = { getWindow = function() return bag end },
}
ChaosTheme = { palette = { accent2 = '#f6cf72', textDim = '#8c8070' } }

dofile(here .. 'chaosdocklogic.lua')
dofile(here .. 'chaosdock.lua')
local D = ChaosDock
init()
local panel = gameRoot:getChildById('chaosDock')
eq(panel ~= nil, true, 'dock built'); eq(panel:isExplicitlyVisible(), false, 'hidden at start')
eq(keys['Alt+D'] ~= nil and keys['Alt+I'] ~= nil and keys['Alt+Q'] ~= nil and keys['Alt+A'] ~= nil, true, 'keys bound')
eq(#panel:getChildById('tabs').children, 5, 'five tabs')

-- Inventory: the panel window moves into the dock and back to its place, still open
local content = panel:getChildById('content')
eq(D.route('Bestiary'), false, 'not a dock entry')
eq(D.route('Inventory'), true, 'inventory routed')
runEvents()
eq(panel:isExplicitlyVisible(), true, 'dock shown'); eq(panel.marginRight, 0, 'slid in')
eq(bag.parent, content, 'bag panel in the dock'); eq(bag.draggable, false, 'not draggable while docked')
eq(bag:getChildById('closeButton').visible, false, 'its close button hidden')
eq(bag.chaosRmlSkip, true, 'mirror leaves it'); eq(panel.width, 330, 'dock width')
eq(store[ChaosDockLogic.SETTING_TAB], 'equip', 'tab saved')
local h = D.held()
eq(#h, 1, 'held'); eq(h[1].home, container, 'home kept'); eq(h[1].index, 2, 'index kept'); eq(h[1].height, 400, 'height kept')
eq(D.route('Inventory'), true, 'second press'); runEvents()
eq(panel:isExplicitlyVisible(), false, 'dock hidden'); eq(bag.parent, container, 'bag back home')
eq(container:getChildIndex(bag), 2, 'at its index'); eq(bag.visible, true, 'still open')
eq(bag.draggable, true, 'draggable again'); eq(bag:getChildById('closeButton').visible, true, 'close button back')
eq(bag.width, 200, 'size back'); eq(#D.held(), 0, 'nothing held')

-- Spellbook: opened through its menu entry, found as the new window, widens the dock; its own close closes the dock
eq(keys['Alt+D'](), true, 'toggle key'); runEvents()
eq(bag.parent, content, 'toggle opens the last tab')
eq(D.route('Spellbook'), true, 'spellbook routed'); runEvents()
eq(bag.parent, container, 'tab change gives the bag back')
eq(ran[#ran], 'Spellbook', 'opened through the raw entry')
eq(spellbook.parent, content, 'spellbook in the dock'); eq(panel.width, 664, 'dock widened')
eq(store[ChaosDockLogic.SETTING_SUBS], 'equip=1,spells=1', 'windows saved')
spellbook:hide() -- Escape on the window
runEvents()
eq(panel:isExplicitlyVisible(), false, 'window closed: dock closed'); eq(spellbook.parent, root, 'spellbook back')
eq(spellbook.visible, false, 'closed as before')

-- Store: wider than the dock may grow at 1280: it floats beside the dock
eq(D.route('Store'), true, 'store routed'); runEvents()
eq(store960.parent, root, 'store stays a window'); eq(store960.visible, true, 'store open')
eq(panel:getChildById('note').visible, true, 'the dock says why'); eq(panel.width, 330, 'dock keeps its width')
eq(store960.x, panel.x - 960 - 4 < 0 and 0 or panel.x - 964, 'placed left of the dock')
eq(keys['Alt+I'](), true, 'equip key'); runEvents()
eq(bag.parent, content, 'equip tab'); eq(keys['Alt+I'](), true, 'equip key again'); runEvents()
eq(panel:isExplicitlyVisible(), false, 'key of the tab shown closes')

-- turned off: entries float as before, keys gone; on again
D.setEnabled(false)
eq(store[ChaosDockLogic.SETTING_ENABLED], 'false', 'saved off')
eq(D.route('Inventory'), false, 'off: not routed'); eq(keys['Alt+D'], nil, 'off: no keys')
D.setEnabled(true)
eq(keys['Alt+D'] ~= nil, true, 'on: keys back')

-- logout gives everything back and drops the dock
D.route('Inventory'); runEvents()
eq(bag.parent, content, 'docked before logout')
online = false
gameHandlers.onGameEnd()
runEvents()
eq(bag.parent, container, 'logout: bag back'); eq(panel.destroyed, true, 'dock gone'); eq(keys['Alt+D'], nil, 'keys gone')
eq(D.route('Inventory'), false, 'offline: not routed')
terminate()

print('chaosdock_engine_test: ' .. n .. ' checks OK')
