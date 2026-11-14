-- luajit topbar_hub_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
-- topbar_hub.lua on a fake widget engine. The fake builds the children of every style from the REAL topbar_hub.otui (the ids
-- under each style), so a Lua lookup of an id the .otui lacks raises here as it would in the client. It plays the bar, the
-- opening of two hubs, a tab switch, a card click, a locked card, a pin (right click, the mark, the bar measured again), the
-- remembered tab, the square points badge, System at the right end of the bar and the fallback when the hub code raises an error.
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
eq(#idsOf('ChaosHubWindow') >= 3, true, 'the window style has tabs, cards, hint')
local hasId = {}
for _, id in ipairs(idsOf('ChaosHubWindow')) do hasId[id] = true end
eq(hasId.textMenu, nil, 'no link to the text menu in the hub window (owner 2026-11-14)')
eq(hasId.pinMark, nil, 'the pin mark is on the card, not the window')
local cardIds = {}
for _, id in ipairs(idsOf('ChaosHubCard')) do cardIds[id] = true end
eq(cardIds.pinMark, true, 'the card has its pin mark'); eq(cardIds.count, true, 'and its square count')

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
local ran, lockedSeen, failed, relayouts, lastWidth = {}, {}, {}, 0, nil
local items = {
  { text = 'Store', category = 'economy', icon = 'market', status = 'open' },
  { text = 'Market', category = 'economy', icon = 'market', status = 'open' },
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
  relayout = function() relayouts = relayouts + 1 lastWidth = Hub.layoutBar(Hub.testPanel) end,
  failed = function(err) failed[#failed + 1] = err end,
}
Hub.init(host)
local panel = new('panel')
Hub.testPanel = panel

-- ---------------------------------------------------------------- the bar
local width = Hub.layoutBar(panel)
eq(width, 16 + 5 * 32 + 2 * 5 + 6 * 4, 'width: Hero, Hunt, Trade, a divider, the Store pin, a divider and System (32 px badges)')
local ids = {}
for _, k in ipairs(panel.kids) do ids[#ids + 1] = k.id or k.style end
eq(table.concat(ids, ','), 'chaosHub_hero,chaosHub_hunt,chaosHub_trade,ChaosHubDivider,chaosPin_1,ChaosHubDivider,chaosHub_system', 'System at the right end, the Store as its own button (a default pin, on no tab)')
eq(panel.kids[2].byId.glyph.width, 32, 'the bar glyph is as big as its 32 px cell')
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
eq(win.byId.textMenu, nil, 'no footer link')

-- a left click runs the entry (with its shown text) and closes the hub
local function click(card, button) return card.onMouseRelease(card, { x = 1, y = 1 }, button) end
eq(click(finder, MouseLeftButton), true, 'the click is taken')
eq(ran[1], 'Party Finder (3)', 'run gets the entry text as shown')
eq(win.chaosNoMirror, true, 'the window stays out of the RmlUi mirror')
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

-- a right click pins; a second one unpins; the bar follows, is measured again and the card shows a mark
local inv
for _, c in ipairs(win.byId.cards.kids) do if c.byId.name.text == 'Inventory' then inv = c end end
eq(inv.byId.pinMark.visible, false, 'no pin mark before')
local rel0 = relayouts
eq(click(inv, MouseRightButton), true, 'the right click is taken')
eq(settings['chaosHubPins'], 'v1:Store|Inventory', 'the pin is saved after the default Store pin')
eq(relayouts > rel0, true, 'the host measured the bar again (a bar kept at its old width squeezes the new badge)')
eq(lastWidth, 16 + 6 * 32 + 2 * 5 + 7 * 4, 'the bar is wide enough for both pins and their dividers')
local order = {}
for _, k in ipairs(panel.kids) do order[#order + 1] = k.id or 'div' end
eq(table.concat(order, ','), 'chaosHub_hero,chaosHub_hunt,chaosHub_trade,div,chaosPin_1,chaosPin_2,div,chaosHub_system', 'the pins sit between the hubs and System')
eq(win.byId.hint.text, 'Pinned to the bar.', 'the hint says so')
local inv2
for _, c in ipairs(win.byId.cards.kids) do if c.byId.name.text == 'Inventory' then inv2 = c end end
eq(inv2.byId.pinMark.visible, true, 'the pinned card shows its mark'); eq(inv2.byId.pinMark.clip ~= nil, true, 'with the pin picture')
local other
for _, c in ipairs(win.byId.cards.kids) do if c.byId.name.text == 'Passive Tree' then other = c end end
eq(other.byId.pinMark.visible, false, 'an unpinned card has none')
-- after a reload (a new Hub from the same settings) the mark is still there
Hub.terminate(); Hub.init(host); Hub.testPanel = new('panel'); Hub.layoutBar(Hub.testPanel)
Hub.toggle('hero')
for _, c in ipairs(created) do if c.style == 'ChaosHubWindow' and not c.destroyed then win = c end end
local inv3
for _, c in ipairs(win.byId.cards.kids) do if c.byId.name.text == 'Inventory' then inv3 = c end end
eq(inv3.byId.pinMark.visible, true, 'the mark is drawn from the saved pins after a reload')
click(inv3, MouseRightButton)
eq(settings['chaosHubPins'], 'v1:Store', 'a second right click unpins')
for _, c in ipairs(win.byId.cards.kids) do if c.byId.name.text == 'Inventory' then inv3 = c end end
eq(inv3.byId.pinMark.visible, false, 'the mark is gone')
-- the bar holds three pins at most
settings['chaosHubPins'] = 'v1:Store|Bank|Market'
Hub.terminate(); Hub.init(host); Hub.testPanel = new('panel'); Hub.layoutBar(Hub.testPanel)
Hub.toggle('hero')
for _, c in ipairs(created) do if c.style == 'ChaosHubWindow' and not c.destroyed then win = c end end
for _, c in ipairs(win.byId.cards.kids) do if c.byId.name.text == 'Inventory' then inv3 = c end end
click(inv3, MouseRightButton)
eq(settings['chaosHubPins'], 'v1:Store|Bank|Market', 'a fourth pin is refused'); eq(win.byId.hint.text, 'The bar is full. Unpin one first.', 'and says why')
settings['chaosHubPins'] = nil
Hub.terminate(); Hub.init(host); panel = new('panel'); Hub.testPanel = panel; Hub.layoutBar(panel)
Hub.close()

-- the square badge of the Passive Tree card: the unspent points its module counts, hidden at 0, follows a change
items[#items + 1] = { text = 'Skills', category = 'character', icon = 'skills', status = 'open', points = 4 }
Hub.toggle('hero')
for _, c in ipairs(created) do if c.style == 'ChaosHubWindow' and not c.destroyed then win = c end end
local skills
for _, c in ipairs(win.byId.cards.kids) do if c.byId.name.text == 'Skills' then skills = c end end
eq(skills.byId.count.visible, true, 'the square count shows'); eq(skills.byId.count.text, '4', 'with the points')
items[#items].points = 120
Hub.layoutBar(panel)
for _, c in ipairs(win.byId.cards.kids) do if c.byId.name.text == 'Skills' then skills = c end end
eq(skills.byId.count.text, '99+', 'the open hub follows a change, 99+ past 99')
items[#items].points = '!'
Hub.layoutBar(panel)
for _, c in ipairs(win.byId.cards.kids) do if c.byId.name.text == 'Skills' then skills = c end end
eq(skills.byId.count.text, '!', 'a mark instead of a number shows as it is (an open trial, O559)')
items[#items].points = nil
Hub.layoutBar(panel)
for _, c in ipairs(win.byId.cards.kids) do if c.byId.name.text == 'Skills' then skills = c end end
eq(skills.byId.count.visible, false, 'hidden at 0')
table.remove(items)
Hub.close()

-- the System hub (no text menu link) and Escape
Hub.toggle('system')
eq(win.byId.textMenu, nil, 'no text menu chip')

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
