-- luajit howitworks_test.lua && lua5.3 howitworks_test.lua (CI runs every client module test from the repo root)
-- howitworks.lua on mocked widgets: init makes the hidden card window, attach puts a ? button in a window (once), the
-- button and show() fill the card with a heading and a text per row in the client's language, attachGoal only for goals
-- with a card, showForUnlock / hasUnlock / hasGoal, and a destroyed window is left alone.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails, count = 0, 0
local function eq(a, b, what)
  count = count + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- mocked widgets
local function widget(style, parent)
  local w = { style = style, parent = parent, children = {}, anchors = {}, visible = true, text = '', destroyed = false, ids = {} }
  function w:setText(t) self.text = t end
  function w:setTooltip(t) self.tooltip = t end
  function w:addAnchor(a, to, b) self.anchors[#self.anchors + 1] = { a, to, b } end
  function w:setMarginTop(v) self.mt = v end
  function w:setMarginRight(v) self.mr = v end
  function w:setMarginBottom(v) self.mb = v end
  function w:hide() self.visible = false end
  function w:show() self.visible = true end
  function w:raise() end
  function w:focus() end
  function w:isDestroyed() return self.destroyed end
  function w:isVisible() return self.visible end
  function w:destroy() self.destroyed = true end
  function w:destroyChildren() self.children = {} end
  function w:getChildById(id) return self.ids[id] end
  function w:getParent() return self.parentWidget end
  function w:getRect() return { x = self.x or 0, y = self.y or 0, width = self.width or 0, height = self.height or 0 } end
  function w:getWidth() return self.width or 0 end
  function w:setWidth(v) self.width = v end
  function w:getHeight() return self.height or 0 end
  function w:breakAnchors() self.anchorsBroken = true end
  function w:setPosition(p) self.x, self.y = p.x, p.y end
  function w:destroy() self.destroyed = true end
  if parent then parent.children[#parent.children + 1] = w end
  return w
end
local root
g_ui = {
  displayUI = function(name)
    root = widget(name)
    root.ids.list = widget('UIScrollArea', root)
    root.children = {}
    return root
  end,
  createWidget = function(style, parent) return widget(style, parent) end,
}
g_logger = { warning = function(m) print('WARN ' .. m) end }
AnchorTop, AnchorRight, AnchorBottom = 1, 2, 3
function tr(s) return s end
ChaosLocale = { lang = 'en', get = function() return ChaosLocale.lang end }

dofile(dir .. 'howitworks_data.lua')
dofile(dir .. 'howcore.lua')
dofile(dir .. '../client_chaos_locale/locale_core.lua')
dofile(dir .. 'howitworks.lua')

init()
eq(root.visible, false, 'card window starts hidden')

-- attach
local win = widget('ArenaWindow')
function win:getPaddingTop() return 38 end
function win:getPaddingRight() return 16 end
local b = attach(win, 'arena')
eq(b.mt, -31, 'button margin top: the title bar, padding taken out')
eq(b.mr, 6, 'button margin right: padding taken out')
eq(b.text, '?', 'button text')
eq(b.parent, win, 'button in the window')
eq(#b.anchors, 2, 'top and right anchors')
eq(win.howButton, b, 'remembered')
local b2 = attach(win, 'arena')
eq(b.destroyed, true, 'a second attach replaces the first')
eq(win.howButton, b2, 'the new one is kept')
eq(attach(win, 'no-such-card'), nil, 'unknown card: no button')
eq(attach(win, nil, 'game_siege').parent, win, 'by module name')
local dead = widget('Gone'); dead.destroyed = true
eq(attach(dead, 'arena'), nil, 'destroyed window left alone')

-- the card
b2.onClick()
eq(root.visible, true, 'click opens the card')
eq(root.text, 'How it works: Arena', 'title')
local list = root.ids.list
eq(#list.children, 10, 'heading + text for 5 rows')
eq(list.children[1].text, 'Who is it for', 'first heading')
eq(list.children[2].text:sub(1, 8), 'Level 50', 'first text from the data')
eq(list.children[7].text, 'If you die', 'death heading')
hide()
eq(root.visible, false, 'hide')

-- pt-BR, converted to the client font
ChaosLocale.lang = 'pt-BR'
eq(show('arena'), true, 'show returns true')
eq(list.children[2].text:sub(1, 8), 'N\237vel 50', 'pt text in cp1252')
ChaosLocale.lang = 'en'
eq(show('nope'), false, 'unknown card')

-- unlock and goal lookups
eq(hasUnlock('tower'), true, 'hasUnlock tower')
eq(hasUnlock('zzz'), false, 'hasUnlock unknown')
eq(hasGoal('rift6'), true, 'hasGoal rift6')
eq(hasGoal('lvl300'), false, 'hasGoal level goal')
eq(showForUnlock('rifts'), true, 'showForUnlock')
eq(root.text, 'How it works: Rifts', 'rift card title')

-- the card keeps left of the side dock (O732 follow-up): a 330 px dock leaves the centred card clear, a dock widened for
-- Character Info (714 px) would be under it
local screen = widget('Root')
screen.width, screen.height = 1280, 720
root.parentWidget, root.width, root.height = screen, 520, 440
ChaosDock = { coverRight = function() return 330 end }
show('arena')
eq(root.x, 380, 'a narrow dock: centred is clear of it'); eq(root.y, 140, 'centred in height')
ChaosDock = { coverRight = function() return 714 end }
show('arena')
eq(root.x, 1280 - 714 - 8 - 520, 'a wide dock: left of it, 8 px clear')
ChaosDock = { coverRight = function() return 330 end }
show('arena')
eq(root.x, 380, 'narrow again')
modules = { game_chaosdock = { ChaosDock = { coverRight = function() return 714 end } } }
reposition()
eq(root.x, 38, 'the dock widened after the card opened: the dock module (sandboxed) is read, the card moves')
modules = { game_chaosdock = { ChaosDock = { coverRight = function() return 940 end } } }
reposition()
eq(root.x, 0, 'a Market dock: the card at the left edge'); eq(root.width, 332, 'narrowed to the room left of it')
modules = { game_chaosdock = { ChaosDock = { coverRight = function() return 0 end } } }
reposition()
eq(root.width, 520, 'dock closed: its own width again'); eq(root.x, 380, 'centred')
modules = nil
ChaosDock = { coverRight = function() return 0 end }
show('arena')
eq(root.x, 380, 'dock closed: centred again')
root.x = nil
show('arena')
eq(root.x, nil, 'never moved while no dock covers the screen')
ChaosDock = nil
eq(showForGoal('wb1'), true, 'showForGoal')
eq(root.text, 'How it works: Boss Spawns', 'boss card title')
local row = widget('GoalRow')
eq(attachGoal(row, 'tower10').parent, row, 'goal row button')
eq(attachGoal(row, 'lvl300'), nil, 'no button for a level goal')

terminate()
eq(root.destroyed, true, 'terminate destroys the window')
eq(showForUnlock('tower'), false, 'after terminate nothing shows')

-- first open: the card opens by itself once per character and window, never with the setting off
local store = {}
saves = 0
g_settings = {
  exists = function(k) return store[k] ~= nil end,
  getBoolean = function(k) return store[k] == true end,
  set = function(k, v) store[k] = v end,
  getNode = function(k) return store[k] end,
  setNode = function(k, v) store[k] = v end,
  save = function() saves = saves + 1 end,
}
local handlers = {}
function connect(w, t) handlers[w] = t end
g_game = { getCharacterName = function() return 'Ash' end }
init()
eq(autoOn(), true, 'auto on by default')
hide()
local tower = widget('TowerWindow')
attach(tower, 'tower')
eq(root.visible, true, 'a visible window opens its card the first time')
eq(saves, 1, 'the seen mark is on disk at once (V41: a killed client brought the card back)')
hide()
tower:hide(); tower:show(); handlers[tower].onVisibilityChange(tower, true)
eq(root.visible, false, 'not the second time')
attach(tower, 'tower')
eq(root.visible, false, 'nor on a new attach')
local siege = widget('SiegeWindow')
siege.visible = false
attach(siege, 'siege')
eq(root.visible, false, 'a hidden window waits')
siege:show(); handlers[siege].onVisibilityChange(siege, true)
eq(root.visible, true, 'and opens its card when shown')
hide()
g_game = { getCharacterName = function() return 'Bo' end }
local before = saves
setAuto(false)
eq(autoOn(), false, 'setting off')
eq(saves, before + 1, 'the check box is on disk at once')
attach(widget('TowerWindow'), 'tower')
eq(root.visible, false, 'no card with the setting off')
setAuto(true)
attach(widget('TowerWindow'), 'tower')
eq(root.visible, true, 'another character gets its own first time')
hide()

-- a window of many pages (game_chaosinfo, O732 follow-up): the card of the page shown, none on a page without one
g_game = { getCharacterName = function() return 'Cy' end }
local info = widget('InfoWindow')
detach(info)
eq(info.howButton, nil, 'detach on a bare window: nothing')
attach(info, 'invasion')
eq(root.text, 'How it works: Invasions', 'the Events page opens its card the first time')
hide()
detach(info)
eq(info.howKey, nil, 'another page: no card key'); eq(info.howButton == nil, true, 'and no button')
info:hide(); info:show(); handlers[info].onVisibilityChange(info, true)
eq(root.visible, false, 'shown on a page with no card: no card')

-- O761: a window opened by itself (the Daily Reward at a first login, howQuiet) brings no card; the player's own opening does
g_game = { getCharacterName = function() return 'Di' end }
hide()
local daily = widget('DailyWindow')
daily.visible = false
attach(daily, 'tower')
daily.howQuiet = true
daily:show(); handlers[daily].onVisibilityChange(daily, true)
eq(root.visible, false, 'a window opened by itself: no card')
daily.howQuiet = nil
daily:hide(); daily:show(); handlers[daily].onVisibilityChange(daily, true)
eq(root.visible, true, 'the player opens it: the card, the first time')
hide()

-- V34: a window loaded visible and hidden by its module in the same call (the passive tree at login) brings no card;
-- the look at attach time runs one event later, the card stays due for the player's own opening
g_game = { getCharacterName = function() return 'Ev' end }
local queue = {}
scheduleEvent = function(fn) queue[#queue + 1] = fn end
local function run() local q = queue queue = {} for _, fn in ipairs(q) do fn() end end
hide()
local tree = widget('PassiveTreeWindow')
attach(tree, 'passive')
tree:hide()
run()
run()
eq(root.visible, false, 'built at login and hidden at once: no card')
tree:show(); handlers[tree].onVisibilityChange(tree, true)
run()
eq(root.visible, true, 'the player opens it: the card, the first time')
hide()
local open = widget('TowerWindow')
attach(open, 'tower')
run()
run()
eq(root.visible, true, 'a window still shown after the event: the card')
hide()
scheduleEvent = nil

print(string.format('howitworks: %d checks, %d failed', count, fails))
if fails > 0 then os.exit(1) end
