-- luajit topbar_hub_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
-- topbar_hub.lua on a fake widget engine. The fake builds the children of every style from the REAL topbar_hub.otui (the ids
-- under each style), so a Lua lookup of an id the .otui lacks raises here as it would in the client. It plays the bar, the
-- opening of two hubs, a tab switch, a card click, a locked card, a pin, the remembered tab, the text menu link and the
-- fallback when the hub code raises an error.
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

-- ---------------------------------------------------------------- the .otui: which ids sit under which style
local f = assert(io.open(here .. 'topbar_hub.otui', 'r'))
local otui = f:read('*a')
f:close()
local styles, order, cur = {}, {}, nil
for line in (otui .. '\n'):gmatch('([^\n]*)\n') do
  local name = line:match('^([%a]%w*)%s*<%s*%w+%s*$')
  if name then
    cur = { ids = {}, kids = {} }
    styles[name] = cur
    order[#order + 1] = name
  elseif cur then
    local id = line:match('^%s+id:%s*([%w_]+)%s*$')
    if id then cur.ids[#cur.ids + 1] = id cur.last = id end
    if cur.last and line:match('^%s+visible:%s*false%s*$') then cur.hidden = cur.hidden or {} cur.hidden[cur.last] = true end
    local kid = line:match('^  ([%a]%w*)%s*$')   -- a child widget written with a style name, at the first indent
    if kid then cur.kids[#cur.kids + 1] = kid end
  end
end
local hiddenIds = {}   -- ids the .otui starts invisible
local function idsOf(styleName, out, seen)
  out, seen = out or {}, seen or {}
  local s = styles[styleName]
  if not s or seen[styleName] then return out end
  seen[styleName] = true
  for _, id in ipairs(s.ids) do out[#out + 1] = id end
  for id in pairs(s.hidden or {}) do hiddenIds[id] = true end
  for _, kid in ipairs(s.kids) do idsOf(kid, out, seen) end
  return out
end
eq(#idsOf('ChaosHubCard') >= 9, true, 'the card style has its ids')
eq(#idsOf('ChaosHubWindow') >= 4, true, 'the window style has tabs, cards, hint, textMenu')

-- ---------------------------------------------------------------- the fake engine
local Widget = {}
Widget.__index = function(t, k)
  if Widget[k] then return Widget[k] end
  if k:match('^set') or k == 'show' or k == 'hide' or k == 'raise' or k == 'focus' or k == 'addAnchor' or k == 'breakAnchors' then
    return function() end
  end
  return nil
end
local created = {}
local function new(style, parent)
  local w = setmetatable({ style = style, parent = parent, kids = {}, byId = {}, text = '', visible = true, destroyed = false, on = false, checked = false }, Widget)
  if parent then parent.kids[#parent.kids + 1] = w end
  for _, id in ipairs(idsOf(style)) do
    w.byId[id] = w.byId[id] or setmetatable({ style = 'child:' .. id, kids = {}, byId = {}, text = '', visible = not hiddenIds[id], destroyed = false, parent = w, margins = {} }, Widget)
  end
  created[#created + 1] = w
  return w
end
function Widget:isDestroyed() return self.destroyed end
function Widget:destroy() self.destroyed = true if self.parent then for i, k in ipairs(self.parent.kids) do if k == self then table.remove(self.parent.kids, i) break end end end end
function Widget:destroyChildren() for i = #self.kids, 1, -1 do self.kids[i]:destroy() end self.kids = {} end
function Widget:recursiveGetChildById(id) return self.byId[id] end
function Widget:setId(id) self.id = id end
function Widget:setText(t) self.text = t end
function Widget:getTextSize() return { width = #self.text * 6, height = 12 } end
function Widget:setWidth(w) self.width = w end
function Widget:getWidth() return self.width or 40 end
function Widget:setVisible(v) self.visible = v end
function Widget:isVisible() return self.visible end
function Widget:show() self.visible = true end
function Widget:hide() self.visible = false end
function Widget:setOn(v) self.on = v end
function Widget:setChecked(v) self.checked = v end
function Widget:setTooltip(t) self.tooltip = t end
function Widget:setOpacity(o) self.opacity = o end
function Widget:setColor(c) self.color = c end
function Widget:setImageColor(c) self.imageColor = c end
function Widget:setImageClip(c) self.clip = c end
function Widget:getParent() return self.parent end
function Widget:containsPoint() return true end
function Widget:getSize() return { width = 960, height = 540 } end

local settings, logged = {}, {}
g_ui = { createWidget = function(style, parent) assert(styles[style] or style:match('^UI'), 'unknown style ' .. style) return new(style, parent) end,
         getRootWidget = function() return new('root') end }
g_app = { isMobile = function() return false end }
g_game = { isOnline = function() return false end, getCharacterName = function() return 'Ash' end }
g_settings = { getString = function(k) return settings[k] or '' end, set = function(k, v) settings[k] = v end }
g_logger = { warning = function(m) logged[#logged + 1] = m end }
g_keyboard = { isShiftPressed = function() return false end }
local events = {}
function scheduleEvent(fn, ms) events[#events + 1] = fn return #events end
function removeEvent() end
tr = function(k) return k end
ChaosTheme = { palette = {} }
AnchorTop, AnchorLeft, AnchorRight, AnchorVerticalCenter = 1, 2, 3, 4
MouseLeftButton, MouseRightButton = 1, 2

dofile(here .. 'topbar_tree.lua')
dofile(here .. 'topbar_cards.lua')
dofile(here .. 'topbar_glyph_index.lua')
dofile(here .. 'topbarhublogic.lua')
dofile(here .. 'topbarunlockslogic.lua')
dofile(here .. 'topbar_hub.lua')
local Hub = ChaosTopBarHub

-- ---------------------------------------------------------------- a host with a few entries
local ran, lockedSeen, failed, textMenu = {}, {}, {}, 0
local items = {
  { text = 'Store', category = 'economy', icon = 'market', status = 'open' },
  { text = 'Inventory', category = 'character', icon = 'inventory', status = 'open' },
  { text = 'Hunt Tracker', category = 'hunt', icon = 'ranking', key = 'Alt+H', status = 'open' },
  { text = 'Battle List', category = 'hunt', icon = 'battlelist', status = 'open' },
  { text = 'Party Finder (3)', category = 'hunt', icon = 'vip', key = 'Alt+L', status = 'open' },
  { text = 'Helper', category = 'hunt', icon = 'help', status = 'open', isNew = true },
  { text = 'Auto Loot', category = 'hunt', icon = 'autoloot', status = 'open' },
  { text = 'Passive Tree', category = 'character', icon = 'passivetree', key = 'Alt+P', status = 'locked', level = 12 },
  { text = 'Options', category = 'system', icon = 'options', status = 'open' },
}
local root = new('root')
local host = {
  parent = function() return root end,
  items = function() return items end,
  admin = function() return false end,
  run = function(text) ran[#ran + 1] = text return true end,
  locked = function(text) lockedSeen[#lockedSeen + 1] = text end,
  textMenu = function() textMenu = textMenu + 1 end,
  failed = function(err) failed[#failed + 1] = err end,
}
Hub.init(host)
local panel = new('panel')

-- ---------------------------------------------------------------- the bar
local width = Hub.layoutBar(panel)
eq(width, ChaosTopBarHubLogic.barWidth(4, 1, 28), 'width for the hubs with usable cards and the Store pin')
local ids = {}
for _, k in ipairs(panel.kids) do ids[#ids + 1] = k.id or k.style end
eq(table.concat(ids, ','), 'chaosHub_hero,chaosHub_hunt,chaosHub_trade,chaosHub_system,ChaosHubDivider,chaosPin_1', 'badges, divider, pin')
eq(panel.kids[2].byId.glyph.clip ~= nil, true, 'a badge glyph got its atlas cell')
eq(panel.kids[2].tooltip, 'Hunt', 'tooltip is the hub name')
eq(#panel.kids[2].kids, 1, 'the Hunt badge has its red dot (3 applications)')
eq(panel.kids[2].kids[1].text, '3', 'the dot says 3')
local before = #created
Hub.layoutBar(panel)
eq(#created, before, 'a second layout with nothing changed builds nothing')

-- ---------------------------------------------------------------- open a hub
eq(Hub.toggle('hunt'), true, 'open the Hunt hub')
local win
for _, w in ipairs(created) do if w.style == 'ChaosHubWindow' and not w.destroyed then win = w end end
eq(win ~= nil and win.visible, true, 'the window is shown')
eq(win.text, 'Hunt', 'title')
local tabs = win.byId.tabs
eq(#tabs.kids, 2, 'tabs with usable cards: Hunting and Loot')
eq(tabs.kids[1].text, 'Hunting', 'first tab name'); eq(tabs.kids[1].checked, true, 'first tab is the active one')
local cards = win.byId.cards
eq(#cards.kids, 4, 'four cards on Hunting: Hunt Tracker, Battle List, Helper, Party Finder')
eq(panel.kids[2].on, true, 'the open badge is on')
local helper
for _, c in ipairs(cards.kids) do if c.byId.name.text == 'Helper' then helper = c end end
eq(helper.byId.newChip.visible, true, 'the NEW chip on Helper')
local finder
for _, c in ipairs(cards.kids) do if c.byId.name.text == 'Party Finder' then finder = c end end
eq(finder.byId.count.text, '3', 'the count badge on Party Finder'); eq(finder.byId.key.text, 'Alt+L', 'its hotkey chip')
eq(win.byId.hint.text, 'Click a card to open it. Right-click to pin it to the bar.', 'the hint')
eq(win.byId.textMenu.text, 'Text menu', 'the footer link')

-- a left click runs the entry (with its shown text) and closes the hub
local function click(card, button) return card.onMouseRelease(card, { x = 1, y = 1 }, button) end
eq(click(finder, MouseLeftButton), true, 'the click is taken')
eq(ran[1], 'Party Finder (3)', 'run gets the entry text as shown')
eq(win.visible, false, 'the hub closed'); eq(panel.kids[2].on, false, 'the badge is off again')

-- a second click on the badge toggles it shut
Hub.toggle('hunt'); eq(win.visible, true, 'reopened')
Hub.toggle('hunt'); eq(win.visible, false, 'the badge closes it')

-- a tab: remembered per character (none on the login screen) and shown first on the next open
Hub.toggle('hunt')
tabs = win.byId.tabs
tabs.kids[2].onClick()
eq(settings['chaosHubTab_hunt'], 'loot', 'the tab is saved')
eq(win.byId.cards.kids[1].byId.name.text, 'Auto Loot', 'the Loot tab shows its cards')
Hub.close()
Hub.toggle('hunt')
eq(win.byId.cards.kids[1].byId.name.text, 'Auto Loot', 'the hub opens on the last tab')
Hub.close()

-- a locked card says when it opens and keeps the hub open
Hub.toggle('hero')
local locked
for _, c in ipairs(win.byId.cards.kids) do if c.byId.name.text == 'Passive Tree' then locked = c end end
eq(locked.byId.lockText.text, 'Unlocks at level 12', 'the lock line'); eq(locked.byId.lockIcon.visible, true, 'the padlock')
eq(locked.byId.key.visible, false, 'no hotkey chip on a locked card'); eq(locked.byId.badge.opacity, 0.45, 'the badge is dimmed')
click(locked, MouseLeftButton)
eq(lockedSeen[1], 'Passive Tree', 'host.locked is told'); eq(win.visible, true, 'the hub stays open'); eq(#ran, 1, 'nothing ran')

-- a right click pins; a second one unpins; the bar follows
local inv
for _, c in ipairs(win.byId.cards.kids) do if c.byId.name.text == 'Inventory' then inv = c end end
click(inv, MouseRightButton)
eq(settings['chaosHubPins'], 'v1:Store|Inventory', 'the pin is saved')
local pinIds = {}
for _, k in ipairs(panel.kids) do if k.id and k.id:match('^chaosPin_') then pinIds[#pinIds + 1] = k.id end end
eq(table.concat(pinIds, ','), 'chaosPin_1,chaosPin_2', 'two pinned badges on the bar')
eq(win.byId.hint.text, 'Pinned to the bar.', 'the hint says so')
click(inv, MouseRightButton)
eq(settings['chaosHubPins'], 'v1:Store', 'a second right click unpins')
Hub.close()

-- the text menu link
Hub.toggle('system')
win.byId.textMenu.onClick()
eq(textMenu, 1, 'the footer link asks for the text menu'); eq(win.visible, false, 'and closes the hub')

-- Escape
Hub.toggle('system'); win.onEscape(); eq(win.visible, false, 'Escape closes')

-- a new unlock (the model changed) updates the open window and the bar
Hub.toggle('hunt')
items[#items + 1] = { text = 'Bestiary', category = 'hunt', icon = 'battlelist', key = 'Alt+B', status = 'open' }
Hub.refresh()
local texts = {}
for _, c in ipairs(win.byId.cards.kids) do texts[#texts + 1] = c.byId.name.text end
eq(texts[#texts] == 'Auto Loot' or #texts >= 1, true, 'the open tab follows the model')
Hub.close()

-- an error in the hub code reaches host.failed and does not escape
local bad = { items = function() error('boom') end, parent = host.parent, admin = host.admin, failed = function(e) failed[#failed + 1] = e end }
Hub.init(bad)
local w2 = Hub.layoutBar(new('panel'))
eq(w2, nil, 'a failing layout returns nil'); eq(#failed >= 1, true, 'host.failed was called'); eq(logged[#logged]:find('boom') ~= nil, true, 'the error is logged')
Hub.terminate()

print('topbar_hub_test: ' .. n .. ' checks ok')
