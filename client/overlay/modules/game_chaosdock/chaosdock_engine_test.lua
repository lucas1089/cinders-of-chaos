-- luajit chaosdock_engine_test.lua: chaosdock.lua on a fake engine (widgets, settings, keys, events). The windows move into
-- the dock and back to their place, open or closed as before; the dock is one right panel column wide under the minimap
-- (O755), a two pane window stacks its panes there and gets them back, Market and Store float beside it; the right column
-- shows only the minimap while the dock is on; the menu, the keys and a bag click route; the state is per character.
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
function W:addAnchor(a, target, to) self.anchors = self.anchors or {} self.anchors[#self.anchors + 1] = a
  self.anchorTo = self.anchorTo or {} self.anchorTo[a] = target and (target .. ':' .. tostring(to)) or nil end
function W:removeAnchor(a)
  self.anchors = self.anchors or {}
  for i = #self.anchors, 1, -1 do if self.anchors[i] == a then table.remove(self.anchors, i) end end
  if self.anchorTo then self.anchorTo[a] = nil end
end
function W:anchorOf(a) return self.anchorTo and self.anchorTo[a] or nil end
function W:setMargin() end
function W:getMarginTop() return self.marginTop or 0 end
function W:getMarginLeft() return self.marginLeft or 0 end
function W:getMarginRight() return self.marginRight or 0 end
function W:getMarginBottom() return self.marginBottom or 0 end
function W:setMarginLeft(m) self.marginLeft = m end
function W:setMarginBottom(m) self.marginBottom = m end
function W:setMarginTop(m) self.marginTop = m end
function W:setMarginRight(m) self.marginRight = m end
function W:setValue(v) self.value = v end
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
function W:getText() return self.text or '' end
function W:getImageSource() return self.image or '' end
function W:getPaddingTop() return self.padTop or 0 end
function W:setPaddingTop(v) self.padTop = v end
function W:getPaddingLeft() return self.padLeft or 0 end
function W:setPaddingLeft(v) self.padLeft = v end
function W:getPaddingRight() return self.padRight or 0 end
function W:setPaddingRight(v) self.padRight = v end
function W:getPaddingBottom() return self.padBottom or 0 end
function W:setPaddingBottom(v) self.padBottom = v end
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
local menuBar = widget('UIWidget', 'chaosMenuBar', gameRoot) -- the hub menu bar, top centre
menuBar.x, menuBar.y, menuBar.width, menuBar.height = 458, 2, 364, 36
-- the right panel column: 178 px (a stock side panel) at the right edge, the minimap on top, then the other miniwindows
local container = widget('UIMiniWindowContainer', 'gameRightPanel', rightPanels)
container.x, container.width, container.height = 1102, 178, 720
local minimap = widget('UIMiniWindow', 'minimapWindow', container)
minimap.x, minimap.y, minimap.width, minimap.height = 1102, 0, 178, 180
local skillsMini = widget('UIMiniWindow', 'skillWindow', container)
local bag = widget('UIMiniWindow', 'bagPanel', container)
bag.width, bag.height = 178, 400
widget('UIButton', 'closeButton', bag)
local battle = widget('UIMiniWindow', 'battleWindow', container)
local bagDocked = {} -- the calls of game_bagpanel.setDocked (its title bar and tab row: BagPanelCore.dockChrome)
local bagShown = 0   -- the calls of game_bagpanel.showWindow (the dock turned off)

local function makeDock(parent)
  local p = widget('UIWidget', 'chaosDock', parent)
  p.width, p.height = 178, 720
  for _, id in ipairs({ 'title', 'closeX', 'tabs', 'subs', 'rule', 'note' }) do widget('UIWidget', id, p) end
  local content = widget('UIWidget', 'content', p)
  content.width, content.height = 170, 600
  local scroller = widget('UIScrollArea', 'scroller', content)
  scroller.width, scroller.height = 170, 600
  local bar = widget('UIScrollBar', 'scrollBar', content)
  bar.visible = false
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
local clock = 0
g_clock = { millis = function() return clock end }
local online = true
local who = 'Ash Walker'
g_game = { isOnline = function() return online end, getCharacterName = function() return who end }
local keys = {}
g_keyboard = { bindKeyDown = function(k, fn) keys[k] = fn end, unbindKeyDown = function(k) keys[k] = nil end }
local queue = {}
function scheduleEvent(fn) queue[#queue + 1] = fn return fn end
function removeEvent(ev) for i, f in ipairs(queue) do if f == ev then table.remove(queue, i) return end end end
-- runs what is queued now (and what that queues, up to max); the dock's column and tick cycles queue themselves again
local function runEvents(max)
  for _ = 1, max or 60 do
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
local spellbook, store960, questlog
local ran = {}
local function part(parent, id, w, h)
  local p = widget('UIWidget', id, parent)
  p.width, p.height = w or 100, h or 100
  return p
end
local fakeTopbar = { runRaw = function(text)
  ran[#ran + 1] = text
  if text == 'Spellbook' then
    if not spellbook then
      spellbook = widget('UIWindow', 'spellbookWindow', root)
      spellbook.text, spellbook.image, spellbook.padTop, spellbook.padLeft = 'Spellbook', '/images/chaos/window', 38, 16
      part(spellbook, 'searchEdit', 230, 22)
      part(spellbook, 'listFrame', 230, 380)
      local details = part(spellbook, 'details', 402, 400)
      part(details, 'stats', 182, 166)
      part(details, 'areaTitle', 214, 16)
      part(details, 'descSeparator', 402, 2).marginTop = 30
      part(spellbook, 'closeButton', 80, 22)
    end
    spellbook.width, spellbook.height = 640, 460
    spellbook:show()
  elseif text == 'Quest Log' then
    if not questlog then
      questlog = widget('UIWindow', 'questLogWindow', root)
      -- parts of its own with the ids of the dock's parts: the dock must never take them for its own
      local inner = widget('UIWidget', 'panel', questlog)
      widget('UIScrollBar', 'scrollBar', inner).visible = false
      widget('UILabel', 'note', inner)
    end
    questlog.width, questlog.height = 789, 537
    questlog:show()
  elseif text == 'Store' then
    store960 = store960 or widget('UIWindow', 'shopWindow', root)
    store960.width, store960.height = 960, 560
    store960:show()
  end
  return true
end }
modules = {
  game_interface = { getRootPanel = function() return gameRoot end },
  client_chaos_topbar = { ChaosTopBar = fakeTopbar, ChaosTopBarGlyphs = dofile(here .. '../client_chaos_topbar/topbar_glyph_index.lua') },
  game_bagpanel = { getWindow = function() return bag end, setDocked = function(on) bagDocked[#bagDocked + 1] = on end,
    showWindow = function() bagShown = bagShown + 1 bag:show() end },
  game_chaosnotify = {},
}
local toastMoves = 0
modules.game_chaosnotify.repositionNotifications = function() toastMoves = toastMoves + 1 end
local cardMoves = 0
modules.game_howitworks = { reposition = function() cardMoves = cardMoves + 1 end }
ChaosTheme = { palette = { accent2 = '#f6cf72', textDim = '#8c8070' } }

dofile(here .. 'chaosdocklogic.lua')
dofile(here .. 'chaosdockcolumn.lua')
dofile(here .. 'chaosdock.lua')
local D = ChaosDock
local L = ChaosDockLogic
local function key(k) return L.charKey(k, who) end
init()
local panel = gameRoot:getChildById('chaosDock')
eq(panel ~= nil, true, 'dock built'); eq(panel:isExplicitlyVisible(), false, 'hidden at start')
eq(keys['Alt+D'] ~= nil and keys['Alt+I'] ~= nil and keys['Alt+Q'] ~= nil and keys['Alt+A'] ~= nil, true, 'keys bound')
eq(#panel:getChildById('tabs').children, 5, 'five tabs')

-- closed: the right column shows only the minimap (O755)
eq(minimap.visible, true, 'minimap shown'); eq(bag.visible, false, 'the bag panel has no window of its own')
eq(battle.visible, false, 'other windows of the column hidden'); eq(skillsMini.visible, false, 'skills hidden')

-- Inventory: the hidden panel moves into the dock, one column wide under the minimap, and back hidden
local content = panel:getChildById('content')
local scroller = content:getChildById('scroller')
local scrollBar = content:getChildById('scrollBar')
eq(D.route('Bestiary'), false, 'not a dock entry')
eq(D.route('Inventory'), true, 'inventory routed')
runEvents()
eq(#ran, 0, 'the Inventory entry is not run: the dock takes the hidden panel')
eq(panel:isExplicitlyVisible(), true, 'dock shown'); eq(panel.marginRight, 0, 'slid in')
eq(bag.parent, scroller, 'bag panel in the dock'); eq(bag.visible, true, 'shown in the dock')
eq(bag.draggable, false, 'not draggable while docked')
eq(bag:getChildById('closeButton').visible, false, 'its close button hidden')
eq(bag.chaosRmlSkip, true, 'mirror leaves it'); eq(panel.width, 178, 'one column wide')
eq(panel.marginTop, 182, 'under the minimap')
eq(bagDocked[1], true, 'the bag panel was told: its title bar and tab row hide')
eq(scrollBar.visible, false, 'a miniwindow fills the room: no scroll bar')
eq(#bag.anchors, 4, 'filled: anchored on four sides')
eq(D.coverRight(), 178, 'covers the column')
eq(toastMoves >= 1, true, 'the toasts were told'); eq(cardMoves >= 1, true, 'the How it works card was told')
eq(store[key(L.SETTING_TAB)], 'equip', 'tab saved for the character'); eq(store[key(L.SETTING_OPEN)], 'true', 'open saved')
eq(store[L.SETTING_TAB], nil, 'not under the plain key')
local tabW = panel:getChildById('tabs').children[1].width
eq(tabW, L.share(5, 178 - 2 * L.PAD), 'the tabs share the column')
local h = D.held()
eq(#h, 1, 'held'); eq(h[1].home, container, 'home kept'); eq(h[1].index, 3, 'index kept'); eq(h[1].height, 400, 'height kept')
eq(D.route('Inventory'), true, 'second press'); runEvents()
eq(panel:isExplicitlyVisible(), false, 'dock hidden'); eq(bag.parent, container, 'bag back home')
eq(store[key(L.SETTING_OPEN)], 'false', 'closed saved')
eq(D.coverRight(), 0, 'closed: covers nothing')
eq(container:getChildIndex(bag), 3, 'at its index'); eq(bag.visible, false, 'hidden again: only the minimap')
eq(bag.draggable, true, 'draggable again'); eq(bag:getChildById('closeButton').visible, true, 'close button back')
eq(bag.width, 178, 'size back'); eq(#D.held(), 0, 'nothing held')
eq(bagDocked[#bagDocked], false, 'given back: its title bar and tab row return')

-- Spellbook: opened through its menu entry, its panes stacked in the column (chaosdockcolumn.lua), taller than the room:
-- it scrolls; the dock never widens; given back, every part has its anchors and size again
eq(keys['Alt+D'](), true, 'toggle key'); runEvents()
eq(bag.parent, scroller, 'toggle opens the last tab')
eq(D.route('Spellbook'), true, 'spellbook routed'); runEvents()
eq(bag.parent, container, 'tab change gives the bag back'); eq(bag.visible, false, 'and it hides there')
eq(ran[#ran], 'Spellbook', 'opened through the raw entry')
eq(spellbook.parent, scroller, 'spellbook in the dock'); eq(panel.width, 178, 'the dock keeps its column')
local list = spellbook:recursiveGetChildById('listFrame')
local details = spellbook:recursiveGetChildById('details')
eq(list.height, 200, 'the list on top'); eq(list:anchorOf(AnchorRight), 'parent:' .. AnchorRight, 'the list takes the width')
eq(list:anchorOf(AnchorBottom), nil, 'the list no longer reaches the bottom')
eq(details:anchorOf(AnchorTop), 'listFrame:' .. AnchorBottom, 'the details under the list')
eq(details.marginLeft, 0, 'the details at the left edge')
eq(spellbook:recursiveGetChildById('closeButton').width, 0, 'its hidden close takes no room')
eq(spellbook.height, 860, 'the stacked height')
eq(spellbook.text, '', 'no title of its own: the dock has it'); eq(spellbook.image, '', 'no frame of its own')
eq(spellbook.padTop, 2, 'no title bar room'); eq(spellbook.padLeft, 2, 'narrow padding'); eq(scrollBar.visible, true, 'it scrolls')
eq(scroller.marginRight, L.SCROLL, 'room for the bar')
eq(store[key(L.SETTING_SUBS)], 'equip=1,spells=1', 'windows saved')
spellbook:hide() -- Escape on the window
runEvents()
eq(panel:isExplicitlyVisible(), false, 'window closed: dock closed'); eq(spellbook.parent, root, 'spellbook back')
eq(spellbook.visible, false, 'closed as before'); eq(spellbook.width, 640, 'its own width again')
eq(spellbook.height, 460, 'its own height again')
eq(spellbook.text, 'Spellbook', 'its title back'); eq(spellbook.image, '/images/chaos/window', 'its frame back')
eq(spellbook.padTop, 38, 'its padding back'); eq(spellbook.padLeft, 16, 'its side padding back')
eq(list.height, 380, 'the list\'s own height'); eq(list:anchorOf(AnchorRight), nil, 'the list\'s right anchor gone')
eq(list:anchorOf(AnchorBottom), 'closeButton:' .. AnchorTop, 'the list reaches the buttons again')
eq(details:anchorOf(AnchorTop), 'parent:' .. AnchorTop, 'the details on top again')
eq(details:anchorOf(AnchorLeft), 'listFrame:' .. AnchorRight, 'the details right of the list again')
eq(spellbook:recursiveGetChildById('descSeparator').marginTop, 30, 'a margin back')
eq(spellbook:recursiveGetChildById('closeButton').width, 80, 'the close button\'s width back')

-- Quest Log: stacked, 800 high in the column; its own parts with the dock's ids are left alone
eq(D.route('Quest Log'), true, 'quest log routed'); runEvents()
eq(questlog.parent, scroller, 'quest log in the scroll area'); eq(panel.width, 178, 'still one column')
eq(questlog.height, 780, 'the stacked height'); eq(#questlog.anchors, 3, 'top, left, right: no bottom anchor')
eq(scrollBar.visible, true, 'scroll bar shown')
eq(questlog:recursiveGetChildById('scrollBar').visible, false, 'the window\'s own bar left alone')
eq(questlog:recursiveGetChildById('note').visible, true, 'the window\'s own note left alone')
eq(D.route('Quest Log'), true, 'second press'); runEvents()
eq(questlog.parent, root, 'given back'); eq(questlog.visible, false, 'closed as before'); eq(questlog.height, 537, 'height back')
eq(scrollBar.visible, false, 'bar hidden again'); eq(scroller.marginRight, 0, 'scroll area full width again')

-- Store: too wide a grid for a column: it opens on its own, centred in the game left of the dock; the dock stays open
eq(D.route('Store'), true, 'store routed'); runEvents()
eq(store960.parent, root, 'store stays a window'); eq(store960.visible, true, 'store open')
eq(panel:isExplicitlyVisible(), true, 'the dock stays open on its tab'); eq(D.isOpen(), true, 'open')
eq(D.floating(), store960, 'the floating window'); eq(panel:getChildById('note').visible, true, 'the dock says so')
eq(store960.x, math.floor((1280 - 178 - 960) / 2), 'centred left of the dock')
eq(store960.x + store960.width <= 1280 - 178, true, 'never over the dock')
eq(panel.width, 178, 'no widening')
eq(keys['Alt+I'](), true, 'equip key'); runEvents()
eq(store960.visible, false, 'the floating window the dock opened goes with its tab')
eq(bag.parent, scroller, 'equip tab'); eq(keys['Alt+I'](), true, 'equip key again'); runEvents()
eq(panel:isExplicitlyVisible(), false, 'key of the tab shown closes')

-- a bag click opens the Inventory tab (not in the login's first seconds)
clock = 1000
eq(D.bagOpened(false, false), false, 'login grace')
clock = 60000
eq(D.bagOpened(true, false), false, 'the login restore')
eq(D.bagOpened(false, false), true, 'a click'); runEvents()
eq(bag.parent, scroller, 'the Inventory shown')
eq(D.bagOpened(false, false), false, 'already shown: nothing')
D.close(); runEvents()

-- a window that shows in the right column again (the layout restore) hides there again
battle:show()
runEvents()
eq(battle.visible, false, 'the column keeps only the minimap')

-- turned off: entries float as before, keys gone, the right column and the bag panel's window back; on again
D.setEnabled(false)
eq(store[L.SETTING_ENABLED], 'false', 'saved off (one for the client)')
eq(D.route('Inventory'), false, 'off: not routed'); eq(keys['Alt+D'], nil, 'off: no keys')
eq(battle.visible, true, 'off: the column\'s windows back'); eq(skillsMini.visible, true, 'skills back')
eq(bagShown, 1, 'off: the bag panel shows its window again')
D.setEnabled(true)
eq(keys['Alt+D'] ~= nil, true, 'on: keys back'); eq(battle.visible, false, 'on: only the minimap again')

-- logout with the dock open: everything given back, the dock dropped; the next entry opens it again (per character)
D.route('Quest Log'); runEvents()
eq(questlog.parent, scroller, 'docked before logout')
online = false
gameHandlers.onGameEnd()
runEvents()
eq(questlog.parent, root, 'logout: quest log back'); eq(panel.destroyed, true, 'dock gone'); eq(keys['Alt+D'], nil, 'keys gone')
eq(D.route('Inventory'), false, 'offline: not routed')
eq(store[key(L.SETTING_OPEN)], 'true', 'the logout keeps the open state')
online = true
gameHandlers.onGameStart()
runEvents()
panel = gameRoot:getChildById('chaosDock')
eq(D.isOpen(), true, 'open again at the entry'); eq(questlog.parent, panel:getChildById('content'):getChildById('scroller'),
  'on the character\'s last window')
D.close(); runEvents()
online = false
gameHandlers.onGameEnd()
runEvents()
-- another character: its own state, closed
who = 'Bryn'
online = true
gameHandlers.onGameStart()
runEvents()
eq(D.isOpen(), false, 'another character: closed')
online = false
gameHandlers.onGameEnd()
runEvents()
terminate()

print('chaosdock_engine_test: ' .. n .. ' checks OK')
