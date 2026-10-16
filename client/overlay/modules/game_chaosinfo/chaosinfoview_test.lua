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
  local n = #(p.auto or {}) + #(p.ids or {})
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
eq(V.page('autoseller'), nil, 'no Auto Seller page: its own window (Economy > Auto Seller, game_pouches)')
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
local fr = V.frameOptions({ 'frost', '', 5, 'ember' })
eq(#fr, 2, 'frame names only'); eq(fr[1].text, 'Frost', 'frame capitalised'); eq(fr[2].value, 'ember', 'frame value')
eq(#V.frameOptions(nil), 0, 'no frames')

-- result text, with headings
eq(V.resultText({ { id = 'a', text = 'one' }, { id = 'b', text = '' }, { id = 'c', text = 'two' } }), 'one\n\ntwo', 'result join')
eq(V.resultText(nil), '', 'no parts')
eq(V.resultText({ { id = 'exp', text = 'No Double EXP active.' } }, V.page('character').headings,
  function(s) return s:upper() end), '[ DOUBLE EXP ]\nNo Double EXP active.', 'heading over a part, translated')

-- the Ancestral Store page: offered by its command, no dropdown row; the rows
eq(V.page('ancestral').store, true, 'store page')
eq(#(V.page('ancestral').rows or {}), 0, 'no dropdown row any more')
eq(V.pageShown(V.page('ancestral'), V.idSet({ 'ancestralstore' })), true, 'store page offered by ancestralstore')
eq(V.pageShown(V.page('ancestral'), V.idSet({ 'rift' })), false, 'store page hidden without it')
local rows, pts = V.storeRows({ points = 40, entries = {
  { id = 31, kind = 'Exercise Chest', name = 'Lasting Chest', item = 900, price = 750 },
  { id = 8, kind = 'Aura', name = 'Electric Shock Aura', item = 901, price = 35 },
  { id = 1, kind = 'Wings', name = 'Fiery Wings', item = 902, price = 25 },
  { id = 2, kind = 'Wings', name = 'bad', price = 'x' },
  'junk',
} })
eq(pts, 40, 'points'); eq(#rows, 3, 'bad entries left out')
eq(rows[1].name, 'Electric Shock Aura', 'sorted by kind'); eq(rows[1].afford, true, 'affordable')
eq(rows[2].kind, 'Exercise Chest', 'second kind'); eq(rows[2].afford, false, 'too expensive'); eq(rows[2].missing, 710, 'missing points')
eq(rows[3].item, 902, 'item id kept')
eq(#V.storeRows(nil), 0, 'no answer yet')

-- Services: a button is enabled by the state field it needs
eq(V.needMet(nil, { }), true, 'no need'); eq(V.needMet('nameTokens', nil), true, 'no state yet')
eq(V.needMet('nameTokens', { nameTokens = 0 }), false, 'no token'); eq(V.needMet('nameTokens', { nameTokens = 2 }), true, 'tokens')
eq(V.needMet('webshopOrders', { webshopOrders = -1 }), true, 'unknown orders: enabled')
eq(V.needMet('freeSwitch', { freeSwitch = '' }), false, 'no free switch')
eq(V.needMet('frames', { frames = {} }), false, 'no frames'); eq(V.needMet('frames', { frames = { 'frost' } }), true, 'frames')
eq(V.needMet('inTutorial', { inTutorial = false }), false, 'out of the tutorial')
for _, row in ipairs(V.page('services').rows) do
  eq(type(row.hint), 'string', (row.label or '?') .. ' row hint')
  for _, b in ipairs(row.buttons) do
    eq(type(b.hint), 'string', b.text .. ' hint')
    if b.need then eq(type(b.why), 'string', b.text .. ' says why it is disabled') end
  end
end
eq(V.page('services').rows[5].combo, 'frames', 'plate frame is a list of the own frames')

-- rows wrap: no button past the row's width. widths of the Character Info buttons at the 690 px window (508 px rows)
local function lineWidths(first, widths, avail, indent, spacing)
  local out = {}
  for n, line in ipairs(V.wrapRow(first, widths, avail, indent, spacing)) do
    local used = (n == 1) and first or indent
    for _, i in ipairs(line) do
      used = (used > 0 and used + spacing or 0) + widths[i]
    end
    out[n] = used
  end
  return out
end
local charW = { 92, 70, 70, 116, 82, 80 }
local lw = lineWidths(0, charW, 508, 0, 6)
eq(#lw, 2, 'six character buttons wrap to two lines')
for n, w in ipairs(lw) do eq(w <= 508, true, 'line ' .. n .. ' fits (' .. w .. ')') end
-- the plate frame row: label 84 + list 150, then three buttons (pt-BR texts are wider)
local frameW = { 120, 130, 140 }
lw = lineWidths(240, frameW, 508, 84, 6)
for n, w in ipairs(lw) do eq(w <= 508, true, 'frame line ' .. n .. ' fits (' .. w .. ')') end
local all = 0
for _, line in ipairs(V.wrapRow(240, frameW, 508, 84, 6)) do all = all + #line end
eq(all, 3, 'every button placed once')
eq(#V.wrapRow(0, { 50, 50 }, 508, 0, 6), 1, 'short rows stay on one line')
local big = V.wrapRow(240, { 300 }, 508, 84, 6)
eq(#big[1], 0, 'a button that does not fit next to the field starts the next line'); eq(big[2][1], 1, 'on line 2')
-- pages without auto commands have an idle text
eq(type(V.page('house').idle), 'string', 'house idle text'); eq(type(V.IDLE), 'string', 'default idle text')

if fails > 0 then error(fails .. ' failure(s)') end
print('chaosinfoview: OK')
