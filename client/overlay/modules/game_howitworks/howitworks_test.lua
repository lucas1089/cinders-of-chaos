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
  function w:destroy() self.destroyed = true end
  function w:destroyChildren() self.children = {} end
  function w:getChildById(id) return self.ids[id] end
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
local b = attach(win, 'arena')
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
eq(showForGoal('wb1'), true, 'showForGoal')
eq(root.text, 'How it works: Boss Spawns', 'boss card title')
local row = widget('GoalRow')
eq(attachGoal(row, 'tower10').parent, row, 'goal row button')
eq(attachGoal(row, 'lvl300'), nil, 'no button for a level goal')

terminate()
eq(root.destroyed, true, 'terminate destroys the window')
eq(showForUnlock('tower'), false, 'after terminate nothing shows')

print(string.format('howitworks: %d checks, %d failed', count, fails))
if fails > 0 then os.exit(1) end
