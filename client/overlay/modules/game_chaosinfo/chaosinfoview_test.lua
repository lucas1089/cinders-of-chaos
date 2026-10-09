-- luajit chaosinfoview_test.lua && lua5.3 chaosinfoview_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'chaosinfoview.lua')
local V = ChaosInfoView
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- every page has an id, a title and at least one command or client action; ids are unique
local seen = {}
for _, p in ipairs(V.PAGES) do
  eq(type(p.id), 'string', 'page id')
  eq(type(p.title), 'string', p.id .. ' title')
  eq(seen[p.id], nil, p.id .. ' unique')
  seen[p.id] = true
  local n = #(p.auto or {})
  for _, row in ipairs(p.rows or {}) do n = n + #(row.buttons or {}) end
  eq(n > 0, true, p.id .. ' has commands')
end
eq(V.page('services').title, 'Services', 'page lookup')
eq(V.page('nope'), nil, 'unknown page')

-- catalog filtering
local set = V.idSet({ 'rift', 'autosell', 'online', 3, nil })
eq(set.rift, true, 'set rift'); eq(set[3], nil, 'numbers ignored')
eq(V.pageShown(V.page('rift'), set), true, 'rift page offered')
eq(V.pageShown(V.page('house'), set), false, 'house page not offered')
eq(V.pageShown(V.page('autoseller'), set), true, 'auto seller page offered')
local auto = V.autoIds(V.page('server'), set)
eq(#auto, 1, 'server auto ids offered'); eq(auto[1], 'online', 'online kept')
eq(V.buttonShown({ id = 'buyhouse' }, set), false, 'button hidden without its command')
eq(V.buttonShown({ fn = 'calendar' }, set), true, 'client actions always shown')

-- params
eq(V.param(nil, 'x'), '', 'no template')
eq(V.param('on', ''), 'on', 'fixed param')
eq(V.param('add $', '  golden armor '), 'add golden armor', 'field put in, trimmed')
eq(V.param('$', '   '), nil, 'empty field refused')
eq(V.param('$', '50% off'), '50% off', 'percent kept')

-- choice lists
local voc = V.vocationOptions('warrior|juggernaut')
eq(#voc, 2, 'two vocations'); eq(voc[1].text, 'Warrior', 'capitalised'); eq(voc[2].value, 'juggernaut', 'value')
local st = V.storeOptions({ { param = '2, 1', label = 'Fiery Wings' }, { label = 'broken' } })
eq(#st, 1, 'store entries'); eq(st[1].value, '2, 1', 'store param')

-- result text
eq(V.resultText({ { id = 'a', text = 'one' }, { id = 'b', text = '' }, { id = 'c', text = 'two' } }), 'one\n\ntwo', 'result join')
eq(V.resultText(nil), '', 'no parts')

if fails > 0 then error(fails .. ' failure(s)') end
print('chaosinfoview: OK')
