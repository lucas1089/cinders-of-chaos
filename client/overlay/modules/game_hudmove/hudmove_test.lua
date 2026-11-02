-- luajit hudmove_test.lua && lua5.3 hudmove_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'hudmove_core.lua')
local C = HudMoveCore
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- core
eq(C.key('Ember', 'Knight Bob'), 'Ember/Knight Bob', 'key world/name')
eq(C.key(nil, 'Knight'), '-/Knight', 'key without world')
eq(C.key('Ember', ''), nil, 'no name: no key')

local p = C.parse({ x = '120', y = '33.7' })
eq(p.x, 120, 'parse string x'); eq(p.y, 33, 'parse string y floored')
eq(C.parse({ x = 0 / 0, y = 1 }), nil, 'parse nan')
eq(C.parse({ x = 1 }), nil, 'parse missing y')
eq(C.parse('1,2'), nil, 'parse not a table')

-- one node, keyed by panel id, then world/name
local node = C.store(nil, 'bestiaryTracker', 'W/A', { x = 10, y = 20 })
node = C.store(node, 'riftHud', 'W/A', { x = 5, y = 6 })
node = C.store(node, 'bestiaryTracker', 'W/B', { x = 7, y = 8 })
eq(C.saved(node, 'bestiaryTracker', 'W/A').x, 10, 'stored for panel and character')
eq(C.saved(node, 'riftHud', 'W/A').y, 6, 'other panel, same character')
eq(C.saved(node, 'bestiaryTracker', 'W/B').x, 7, 'same panel, other character')
eq(C.saved(node, 'riftHud', 'W/B'), nil, 'nothing for that pair')
node = C.store(node, 'riftHud', 'W/A', nil)
eq(node.riftHud, nil, 'last spot of a panel forgotten: no empty table left')
node = C.store(node, 'bestiaryTracker', 'W/A', nil)
eq(C.saved(node, 'bestiaryTracker', 'W/A'), nil, 'forgotten')
eq(C.saved(node, 'bestiaryTracker', 'W/B').y, 8, 'other character kept')
eq(C.saved(node, nil, 'W/B'), nil, 'no id')
eq(C.saved(node, 'bestiaryTracker', nil), nil, 'no key')
eq(C.saved({ bestiaryTracker = 'junk' }, 'bestiaryTracker', 'W/B'), nil, 'junk panel entry')
eq(C.store(node, 'x', nil, { x = 1, y = 1 }), node, 'no key: node unchanged')

-- bounds: the parent's part on screen, relative to the parent
local b = C.bounds({ x = 0, y = 0, width = 1000, height = 600 }, { x = 0, y = 0, width = 1000, height = 600 })
eq(b.x0, 0, 'same rect x0'); eq(b.x1, 1000, 'same rect x1'); eq(b.y1, 600, 'same rect y1')
b = C.bounds({ x = -50, y = 20, width = 1200, height = 700 }, { x = 0, y = 0, width = 1000, height = 600 })
eq(b.x0, 50, 'parent starts left of the screen'); eq(b.x1, 1050, 'screen right edge in parent pixels')
eq(b.y0, 0, 'parent below the top'); eq(b.y1, 580, 'screen bottom in parent pixels')
b = C.bounds({ x = 0, y = 0, width = 300, height = 200 }, nil)
eq(b.x1, 300, 'no screen: parent'); eq(b.y1, 200, 'no screen: parent height')

-- clamp fully inside, again after a resize
b = C.bounds({ x = 0, y = 0, width = 1000, height = 600 })
local x, y = C.clamp(-50, -10, 210, 80, b)
eq(x, 0, 'clamp left'); eq(y, 0, 'clamp top')
x, y = C.clamp(900, 590, 210, 80, b)
eq(x, 790, 'clamp right'); eq(y, 520, 'clamp bottom')
x, y = C.clamp(50, 50, 210, 80, C.bounds({ x = 0, y = 0, width = 100, height = 40 }))
eq(x, 0, 'too narrow: left'); eq(y, 0, 'too low: top')
eq(C.place(nil, 210, 80, b), nil, 'nothing saved: default anchors kept')
p = C.place({ x = 1500, y = 900 }, 210, 80, b)
eq(p.x, 790, 'smaller window: x pulled in'); eq(p.y, 520, 'smaller window: y pulled in')

-- drag
x, y = C.dragTo(520, 300, 20, 10, 100, 50, 210, 80, b)
eq(x, 400, 'drag x relative to parent'); eq(y, 240, 'drag y relative to parent')
eq(C.moved(10, 10, 11, 12), false, 'tiny move: a click')
eq(C.moved(10, 10, 13, 10), true, 'moved x')

-- which press may start a drag
eq(C.canStartDrag({}), true, 'background')
eq(C.canStartDrag(nil), true, 'no chain')
eq(C.canStartDrag({ { class = 'UILabel' } }), true, 'plain label')
eq(C.canStartDrag({ { class = 'UIButton' } }), false, 'button')
eq(C.canStartDrag({ { class = 'UICheckBox' } }), false, 'checkbox')
eq(C.canStartDrag({ { class = 'UITextEdit' } }), false, 'text edit')
eq(C.canStartDrag({ { class = 'UIWidget' }, { class = 'UIButton' } }), false, 'inside a button')
eq(C.canStartDrag({ { class = 'UILabel', click = true } }), false, 'label with a click')
eq(C.canStartDrag({ { class = 'UILabel', click = true, handle = true } }), true, 'title handle with a click')
eq(C.canStartDrag({ { class = 'UIButton' }, { class = 'UIWidget', handle = true } }), false, 'button inside a handle')
eq(C.canStartDrag({ { class = 'UIWidget', draggable = true } }), false, 'draggable child')

-- default anchors from .otui
local otui = [[
// a comment
RaidHudLabel < UILabel
  anchors.top: parent.top

RaidHud < ChaosPanelDark
  id: raidHud
  anchors.top: parent.top
  anchors.horizontalCenter: gameMapPanel.horizontalCenter // centred on the map
  margin-top: 44
  $mobile:
    anchors.left: parent.left
  ChaosTitle
    anchors.top: parent.top
    anchors.left: parent.left
]]
local a = C.parseAnchors(otui, 'RaidHud')
eq(#a, 2, 'two own anchors')
eq(a[1][1], 'top', 'edge'); eq(a[1][2], 'parent', 'target'); eq(a[1][3], 'top', 'target edge')
eq(a[2][1], 'horizontalCenter', 'centre edge'); eq(a[2][2], 'gameMapPanel', 'target id'); eq(a[2][3], 'horizontalCenter', 'centre target edge')
eq(C.parseAnchors(otui, 'Missing'), nil, 'no such style')
local root = [[
Row < UIWidget
  anchors.left: parent.left

Panel
  anchors.bottom: parent.bottom
  anchors.left: parent.left
  size: 305 235
  Label
    anchors.top: parent.top
]]
a = C.parseAnchors(root, nil)
eq(#a, 2, 'loaded root: own anchors only'); eq(a[1][1], 'bottom', 'root first edge')
a = C.parseAnchors('Box < UIWidget\n  anchors.centerIn: parent\n  anchors.fill: none\n', 'Box')
eq(#a, 1, 'centerIn kept, fill none skipped'); eq(a[1][1], 'centerIn', 'centerIn'); eq(a[1][2], 'parent', 'centerIn target')
eq(C.parseAnchors('X\n  width: 3\n', nil), nil, 'no anchors')
eq(C.parseAnchors(nil, nil), nil, 'no text')

-- ---------------------------------------------------------------- engine with a mocked UI
AnchorTop, AnchorBottom, AnchorLeft, AnchorRight, AnchorHorizontalCenter, AnchorVerticalCenter = 1, 2, 3, 4, 5, 6
MouseLeftButton, MouseRightButton = 1, 2
local settings, events = {}, {}
g_settings = {
  getNode = function(k) return settings[k] end,
  setNode = function(k, v) settings[k] = v end,
  save = function() end,
}
local world, name = 'Ember', 'Bob'
g_game = { getWorldName = function() return world end, getCharacterName = function() return name end }
g_resources = { readFileContents = function() return otui end }
function tr(s) return s end
function addEvent(fn) events[#events + 1] = fn; return fn end
function removeEvent() end
function connect(obj, t)
  for k, fn in pairs(t) do
    local prev = obj[k]
    if prev then obj[k] = function(...) local r = prev(...); local r2 = fn(...); return r or r2 end else obj[k] = fn end
  end
end
function disconnect() end

local Widget = {}
Widget.__index = Widget
local function widget(t)
  t = t or {}
  t.children = t.children or {}
  t.margins = { top = t.mt or 0, right = 0, bottom = 0, left = t.ml or 0 }
  t.anchors = {}
  t.visible = true
  return setmetatable(t, Widget)
end
function Widget:isDestroyed() return false end
function Widget:getParent() return self.parent end
function Widget:getX() return self.x end
function Widget:getY() return self.y end
function Widget:getWidth() return self.w end
function Widget:getHeight() return self.h end
function Widget:getMarginTop() return self.margins.top end
function Widget:getMarginRight() return self.margins.right end
function Widget:getMarginBottom() return self.margins.bottom end
function Widget:getMarginLeft() return self.margins.left end
-- top/left anchors to the parent place the widget at once (the only layout the helper itself makes)
local function relayout(w)
  if w.anchors[1] and w.anchors[1][1] == AnchorTop and w.anchors[2] and w.anchors[2][1] == AnchorLeft then
    w.x, w.y = w.parent.x + w.margins.left, w.parent.y + w.margins.top
  end
end
function Widget:setMarginTop(v) self.margins.top = v; relayout(self) end
function Widget:setMarginLeft(v) self.margins.left = v; relayout(self) end
function Widget:setMarginRight(v) self.margins.right = v end
function Widget:setMarginBottom(v) self.margins.bottom = v end
function Widget:breakAnchors() self.anchors = {}; self.broken = (self.broken or 0) + 1 end
function Widget:addAnchor(e, t, te) self.anchors[#self.anchors + 1] = { e, t, te } end
function Widget:fill(t) self.anchors[#self.anchors + 1] = { 'fill', t } end
function Widget:centerIn(t) self.anchors[#self.anchors + 1] = { 'centerIn', t } end
function Widget:isVisible() return self.visible end
function Widget:setPhantom(v) self.phantom = v end
function Widget:grabMouse() self.grabbed = true end
function Widget:ungrabMouse() self.grabbed = false end
function Widget:getTooltip() return self.tooltip or '' end
function Widget:setTooltip(t) self.tooltip = t end
function Widget:getClassName() return self.class or 'UIWidget' end
function Widget:recursiveGetChildByPos(pos)
  for _, c in ipairs(self.children) do
    if pos.x >= c.x and pos.x < c.x + c.w and pos.y >= c.y and pos.y < c.y + c.h then return c end
  end
  return nil
end
local screen = widget({ x = 0, y = 0, w = 1000, h = 600 })
g_ui = { getRootWidget = function() return screen end }

dofile(dir .. 'hudmove.lua')
local H = ChaosHudMove

local parent = widget({ x = 0, y = 0, w = 1000, h = 600 })
local panel = widget({ x = 40, y = 192, w = 250, h = 100, mt = 192, ml = 40, parent = parent, phantom = true })
local title = widget({ x = 48, y = 200, w = 200, h = 16, parent = panel, class = 'UILabel', phantom = true })
local folds = 0
title.onClick = function() folds = folds + 1 end
local button = widget({ x = 48, y = 260, w = 80, h = 20, parent = panel, class = 'UIButton' })
panel.children = { title, button }

H.attach(panel, 'raidHud', { handles = { title }, otui = '/modules/game_raid/raid', style = 'RaidHud' })
eq(panel.phantom, false, 'background drag: panel takes the mouse')
eq(title.phantom, false, 'handle takes the mouse')
eq(panel.broken, nil, 'nothing saved: default anchors untouched')
eq(panel.tooltip, 'Drag to move. Double-click to put it back.', 'tooltip')

-- a press on the button is the button's
eq(panel.onMousePress(panel, { x = 50, y = 265 }, MouseLeftButton), false, 'button press not taken')
eq(panel.grabbed, nil, 'no grab on the button')
-- a right press is not a drag
eq(panel.onMousePress(panel, { x = 200, y = 280 }, MouseRightButton), false, 'right button')

-- a click on the background: no move, anchors kept
eq(panel.onMousePress(panel, { x = 200, y = 280 }, MouseLeftButton), true, 'background press')
panel.onMouseMove(panel, { x = 201, y = 281 })
panel.onMouseRelease(panel, { x = 201, y = 281 }, MouseLeftButton)
eq(panel.broken, nil, 'a click keeps the default anchors')
eq(settings.chaosHudPos, nil, 'a click saves nothing')

-- a drag saves the spot for this character
panel.onMousePress(panel, { x = 200, y = 280 }, MouseLeftButton)
panel.onMouseMove(panel, { x = 300, y = 330 })
panel.onMouseRelease(panel, { x = 300, y = 330 }, MouseLeftButton)
eq(panel.x, 140, 'dragged x'); eq(panel.y, 242, 'dragged y')
eq(C.saved(settings.chaosHudPos, 'raidHud', 'Ember/Bob').x, 140, 'saved x')
eq(H.isMoved(panel), true, 'moved')

-- a drag past the edge is clamped
panel.onMousePress(panel, { x = 200, y = 280 }, MouseLeftButton)
panel.onMouseMove(panel, { x = 5000, y = 5000 })
panel.onMouseRelease(panel, { x = 5000, y = 5000 }, MouseLeftButton)
eq(panel.x, 750, 'clamped right'); eq(panel.y, 500, 'clamped bottom')

-- the title drags too, and the click its release fires does not fold
title.x, title.y = panel.x + 8, panel.y + 8
title.onMousePress(title, { x = title.x + 5, y = title.y + 5 }, MouseLeftButton)
title.onMouseMove(title, { x = title.x - 95, y = title.y - 95 })
title.onMouseRelease(title, {}, MouseLeftButton)
title.onClick(title)
eq(folds, 0, 'no fold after a drag')
title.onClick(title)
eq(folds, 1, 'a plain click folds')
eq(panel.x, 650, 'title drag x')

-- a smaller window pulls the spot in
parent.w, parent.h, screen.w, screen.h = 700, 400, 700, 400
parent.onGeometryChange(parent)
for _, fn in ipairs(events) do fn() end
events = {}
eq(panel.x, 450, 'resize: clamped x'); eq(panel.y, 300, 'resize: clamped y')

-- another character: its own spot (none: the default place)
name = 'Ann'
panel.onVisibilityChange(panel, true)
eq(panel.anchors[1][1], AnchorTop, 'default anchors back: top')
eq(panel.anchors[2][1], AnchorHorizontalCenter, 'default anchors back: centre')
eq(panel.anchors[2][2], 'gameMapPanel', 'default target')
eq(panel.margins.top, 192, 'default margin back')
eq(H.isMoved(panel), false, 'not moved for this character')
name = 'Bob'
panel.onVisibilityChange(panel, true)
eq(H.isMoved(panel), true, 'Bob: his spot again')

-- double-click on a button does nothing; on the background: default place, spot forgotten
eq(panel.onDoubleClick(panel, { x = button.x + 1, y = button.y + 1 }), false, 'double-click on a button')
button.x, button.y = -100, -100
eq(panel.onDoubleClick(panel, { x = panel.x + 100, y = panel.y + 90 }), true, 'double-click on the background')
eq(C.saved(settings.chaosHudPos, 'raidHud', 'Ember/Bob'), nil, 'spot forgotten')
eq(panel.anchors[2][2], 'gameMapPanel', 'default place again')

-- a module's own reset
local resets = 0
local p2 = widget({ x = 10, y = 10, w = 100, h = 50, parent = parent })
H.attach(p2, 'bestiaryTracker', { reset = function() resets = resets + 1 end })
p2.onMousePress(p2, { x = 20, y = 20 }, MouseLeftButton)
p2.onMouseMove(p2, { x = 60, y = 60 })
p2.onMouseRelease(p2, {}, MouseLeftButton)
p2.onDoubleClick(p2, { x = p2.x + 1, y = p2.y + 1 })
eq(resets, 1, 'module reset used')

-- the handles only: the panel stays click-through
local p3 = widget({ x = 10, y = 10, w = 100, h = 50, parent = parent, phantom = true })
local t3 = widget({ x = 10, y = 10, w = 100, h = 14, parent = p3, phantom = true })
H.attach(p3, 'siegeHud', { panel = false, handles = { t3 }, reset = function() end })
eq(p3.phantom, true, 'panel stays phantom'); eq(p3.onMousePress, nil, 'panel not a drag source')
eq(t3.phantom, false, 'title is the handle')

print(string.format('hudmove_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
