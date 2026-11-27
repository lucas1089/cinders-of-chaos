-- luajit locale_relabel_test.lua && lua5.3 locale_relabel_test.lua   (any directory; run from the repo root in CI)
-- V37: a language switch in game swaps the texts of the open windows (ChaosLocale.relabel) on a fake widget tree.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'locale_core.lua')
dofile(dir .. 'locale.lua')
local L, M = ChaosLocaleCore, ChaosLocale
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local W = {}
W.__index = W
local function widget(id, class, props, kids)
  local w = setmetatable({ id = id, class = class or 'UIWidget', kids = kids or {} }, W)
  for k, v in pairs(props or {}) do w[k] = v end
  return w
end
function W:getId() return self.id end
function W:getClassName() return self.class end
function W:getChildren() return self.kids end
function W:getText() return self.text or '' end
function W:setText(s) self.text = s end
function W:getTooltip() return self.tooltip or '' end
function W:setTooltip(s) self.tooltip = s end
function W:getPlaceholder() return self.placeholder or '' end
function W:setPlaceholder(s) self.placeholder = s end

M.tables['pt-BR'] = L.prepare({ ['Type to search'] = 'Digite para buscar', Close = 'Fechar', ['Say something...'] = 'Diga algo...', ['Level %d'] = 'N\195\173vel %d' })
local edit = widget('searchEdit', 'UITextEdit', { text = 'Close', placeholder = 'Type to search' })
local close = widget('closeButton', nil, { text = 'Close', tooltip = 'Close' })
local lvl = widget('lvl', nil, { text = 'Level 5' })
local chatLine = widget('line', nil, { text = 'Close' })
local console = widget('consoleBuffer', nil, nil, { chatLine })
local talk = widget('talkEdit', 'UITextEdit', { placeholder = 'Say something...' })
local root = widget('root', nil, nil, { widget('tradeWindow', nil, nil, { edit, close, lvl }), console, talk })
g_ui = { getRootWidget = function() return root end }

eq(M.relabel('en', 'pt-BR') > 0, true, 'relabel: something swapped')
eq(close.text, 'Fechar', 'a button text')
eq(close.tooltip, 'Fechar', 'a tooltip')
eq(edit.placeholder, 'Digite para buscar', 'a placeholder (trade "Type to search")')
eq(talk.placeholder, 'Diga algo...', 'the talk placeholder')
eq(edit.text, 'Close', 'typed text in an edit is never touched')
eq(chatLine.text, 'Close', 'the chat log is never touched')
eq(lvl.text, 'Level 5', 'a formatted text is left for its module')
M.relabel('pt-BR', 'en')
eq(close.text, 'Close', 'back to English')
eq(edit.placeholder, 'Type to search', 'placeholder back to English')

-- V39 (seen in a client): the engine binds setPlaceholder but no getPlaceholder; the .otui text is in the style
local E = setmetatable({}, { __index = W })
E.__index = E
E.getPlaceholder = false
function E:getStyle() return { placeholder = self.stylePlaceholder, ['__class'] = 'UITextEdit' } end
local function engineEdit(id, text)
  local w = setmetatable({ id = id, class = 'UITextEdit', kids = {}, stylePlaceholder = text, placeholder = text }, E)
  return w
end
local search2, say2 = engineEdit('searchText', 'Type to search'), engineEdit('input', 'Say something...')
search2.text = 'potion'
root = widget('root', nil, nil, { widget('tradeWindow', nil, nil, { search2 }), widget('npcTalkWindow', nil, nil, { say2 }) })
eq(M.placeholderOf(search2), 'Type to search', 'no getter: the style placeholder')
eq(M.relabel('en', 'pt-BR'), 2, 'engine edits: both placeholders swapped')
eq(search2.placeholder, 'Digite para buscar', 'engine edit: trade placeholder in pt-BR')
eq(say2.placeholder, 'Diga algo...', 'engine edit: talk placeholder in pt-BR')
eq(search2.text, 'potion', 'engine edit: typed text kept')
eq(M.placeholderOf(search2), 'Digite para buscar', 'the swapped placeholder is remembered (the style keeps the first)')
eq(M.relabel('pt-BR', 'en'), 2, 'and back')
eq(say2.placeholder, 'Say something...', 'engine edit: back to English')

-- V39: M.watch runs after a switch (a module redraws texts it formats itself); a second watch of a key replaces it
local seen = {}
M.watch('trade', function(lang) seen[#seen + 1] = 'a ' .. lang end)
M.watch('trade', function(lang) seen[#seen + 1] = 'b ' .. lang end)
M.watch('talk', function() error('a failing watcher does not stop the others') end)
g_settings = { set = function() end, get = function() end }
M.set('pt-BR', true)
eq(table.concat(seen, ','), 'b pt-BR', 'watch: the last function of a key, the new language')
M.set('pt-BR', true)
eq(#seen, 1, 'watch: no switch, no call')
M.watch('trade', nil)
M.watch('talk', nil)
M.set('en', true)
eq(#seen, 1, 'watch: removed')
-- the watchers draw first, the swap then catches a plain English text one of them took from elsewhere (an item name)
local card = widget('nameLabel', nil, { text = 'Close' })
root = widget('root', nil, nil, { card })
M.watch('trade', function() card.text = 'Close' end)
M.set('pt-BR', true)
eq(card.text, 'Fechar', 'watch: runs before the swap')
M.watch('trade', nil)

g_ui = nil
eq(M.relabel('en', 'pt-BR'), 0, 'no root: nothing')

if fails > 0 then error(string.format('locale_relabel_test: %d of %d checks failed', fails, checks)) end
print('locale_relabel_test: ok (' .. checks .. ' checks)')
