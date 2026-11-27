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
g_ui = nil
eq(M.relabel('en', 'pt-BR'), 0, 'no root: nothing')

if fails > 0 then error(string.format('locale_relabel_test: %d of %d checks failed', fails, checks)) end
print('locale_relabel_test: ok (' .. checks .. ' checks)')
