-- luajit helpsearch_test.lua && lua5.3 helpsearch_test.lua (CI runs every client module test from the repo root)
-- helpsearch.lua on mocked widgets: init makes the hidden window and adds System > Help Search with Alt+F, an empty box
-- shows the first steps, a query fills the rows (title, where, snippet) in the client's language and in cp1252, a click
-- opens the card (game_howitworks.show) or the Codex page (game_codex.open, loaded on first use), Enter opens the first
-- row, nothing found shows a line, and a missing window is left alone.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails, count = 0, 0
local function eq(a, b, what)
  count = count + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local function widget(style, parent)
  local w = { style = style, parent = parent, children = {}, visible = true, text = '', destroyed = false, ids = {} }
  function w:setText(t) self.text = t end
  function w:getText() return self.text end
  function w:setTooltip(t) self.tooltip = t end
  function w:setVisible(v) self.visible = v end
  function w:hide() self.visible = false end
  function w:show() self.visible = true end
  function w:raise() end
  function w:focus() end
  function w:isDestroyed() return self.destroyed end
  function w:isVisible() return self.visible end
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
    root.ids.list = widget('UIScrollArea')
    root.ids.searchEdit = widget('ChaosTextEdit')
    root.ids.searchHint = widget('UILabel')
    return root
  end,
  createWidget = function(style, parent)
    local w = widget(style, parent)
    if style == 'HelpResult' then
      w.ids.title, w.ids.where, w.ids.snippet = widget('UILabel'), widget('UILabel'), widget('UILabel')
    end
    return w
  end,
}
g_logger = { warning = function(m) print('WARN ' .. m) end }
KeyEscape, KeyEnter = 27, 13
ChaosLocale = { lang = 'en', get = function() return ChaosLocale.lang end }
local PT = { ['Level %d+'] = 'N\237vel %d+' } -- tr() gives cp1252, as client_chaos_locale does
function tr(s, ...)
  if ChaosLocale.lang == 'pt-BR' and PT[s] then s = PT[s] end
  if select('#', ...) > 0 then return string.format(s, ...) end
  return s
end

local opened, codexOpened, codexLoads, added = nil, nil, 0, {}
modules = {
  game_howitworks = { show = function(key) opened = key return true end },
  client_chaos_topbar = { ChaosTopBar = { addEntry = function(cat, e) added[#added + 1] = { cat = cat, e = e } return true end } },
}
g_modules = { ensureModuleLoaded = function(name)
  if name == 'game_codex' then
    codexLoads = codexLoads + 1
    modules.game_codex = { getData = function() return CodexData end, open = function(id) codexOpened = id return true end }
  end
end }

dofile(dir .. '../game_howitworks/howitworks_data.lua')
dofile(dir .. '../game_codex/codex_data.lua')
dofile(dir .. '../client_chaos_locale/locale_core.lua')
dofile(dir .. 'helpsearch_data.lua')
dofile(dir .. 'helpcore.lua')
dofile(dir .. 'helpsearch.lua')

-- before init nothing breaks
show(); search('orbs')
eq(#results(), 0, 'no window: nothing')

init()
eq(root.visible, false, 'window starts hidden')
eq(#added, 1, 'one menu entry')
eq(added[1].cat, 'system', 'in System')
eq(added[1].e.text, 'Help Search', 'its text')
eq(added[1].e.key, 'Alt+F', 'its hotkey')
eq(added[1].e.fns[1], 'toggle', 'it toggles the window')

-- empty box: the first steps
show()
eq(root.visible, true, 'shown')
local list = root.ids.list
eq(list.children[1].text, 'First steps', 'heading')
eq(#results(), #HelpSearchData.steps, 'one row per first step')
eq(results()[1].key, HelpSearchData.steps[1].card, 'in order')
eq(results()[1].snippet, HelpSearchData.steps[1].en, 'the tip is the snippet')
eq(codexLoads, 1, 'the Codex is loaded once for the index')

-- a query
search('how do I get orbs')
local rows = results()
eq(rows[1].kind, 'card', 'a card first')
local first = list.children[1]
eq(first.style, 'HelpResult', 'a result row')
eq(first.ids.title.text, rows[1].title, 'row title')
eq(first.ids.snippet.text ~= '', true, 'row snippet')
first.onClick()
eq(opened, rows[1].key, 'click opens the card')

-- Codex result
search('orb of fate')
eq(results()[1].kind, 'codex', 'Codex page first')
eq(results()[1].where:sub(1, 5), 'Codex', 'where says Codex')
list.children[1].onClick()
eq(codexOpened, 'orb:divine', 'click opens the Codex page')

-- pt-BR, cp1252 on the screen
ChaosLocale.lang = 'pt-BR'
search('masmorras')
eq(results()[1].key, 'dungeons', 'pt query')
eq(results()[1].title, 'Masmorras', 'pt title')
eq(results()[1].where:find('N\237vel', 1, true) ~= nil, true, 'pt where line in cp1252: ' .. results()[1].where)

-- Enter opens the first row
opened = nil
root.ids.searchEdit.onKeyDown(root.ids.searchEdit, KeyEnter)
eq(opened, 'dungeons', 'Enter opens the first answer')
root.ids.searchEdit.onKeyDown(root.ids.searchEdit, KeyEscape)
eq(root.visible, false, 'Escape hides')

-- nothing found
search('zzzqqx')
eq(#results(), 0, 'no rows')
eq(list.children[1].style, 'HelpHeading', 'a line says so')

toggle(); eq(root.visible, true, 'toggle shows')
toggle(); eq(root.visible, false, 'toggle hides')
terminate()
eq(root.destroyed, true, 'terminate destroys the window')

print(('helpsearch_test: %d of %d checks failed'):format(fails, count))
if fails > 0 then os.exit(1) end
