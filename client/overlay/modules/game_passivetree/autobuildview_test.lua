-- luajit autobuildview_test.lua && lua5.3 autobuildview_test.lua (from this folder or the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'autobuildview.lua')
local V = AutoBuildView
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(V.gold(1234567), '1,234,567', 'gold')
eq(V.gold(nil), '0', 'gold nil')
eq(V.label({id = 'a', name = 'Slayer', points = 120, fit = 'primary'}), 'Slayer - 120 points [Primary]', 'label primary')
eq(V.label({id = 'a', name = 'Leech', points = 80, fit = 'secondary'}), 'Leech - 80 points [Secondary]', 'label secondary')
eq(V.label({id = 'a', name = 'Mana', points = 3}), 'Mana - 3 points', 'label plain')
eq(V.label({id = 'x'}), 'x - 0 points', 'label without a name')

local role = {{id = 'w_slayer', name = 'Slayer', points = 200}, {id = 'w_bulwark', name = 'Bulwark', points = 190}}
local focus = {{id = 'focus_leech', name = 'Leech', points = 150, fit = 'secondary'}}
local rows = V.rows({role = role, focus = focus})
eq(#rows, 5, 'two headings and three builds')
eq(rows[1].heading, true, 'first row is a heading'); eq(rows[1].text, '- Recommended -', 'heading text')
eq(rows[4].heading, true, 'focus heading'); eq(rows[4].text, '- Focus -', 'focus heading text')
eq(V.firstBuild(rows), 2, 'first build'); eq(V.indexOf(rows, 'focus_leech'), 5, 'index of a build')
eq(V.indexOf(rows, 'nope'), nil, 'unknown build')
eq(#V.rows({role = role}), 3, 'only recommended')
eq(#V.rows({}), 0, 'no lists yet'); eq(#V.rows(nil), 0, 'nil lists')
eq(V.firstBuild({}), nil, 'no build')

local state = {owned = 100, held = 20, free = 80, cap = 248}
local text = V.detail(nil, state, nil)
eq(text, 'Pick a build. The tree shows what it would take.', 'no build picked')
local b = {id = 'w_slayer', name = 'Slayer', text = 'Hits hard.', summary = 'Physical damage +50', points = 200}
text = V.detail(b, state, nil)
eq(text:find('Hits hard.', 1, true) ~= nil, true, 'text shown')
eq(text:find('The build uses 200 points. You own 100 and 80 are free.', 1, true) ~= nil, true, 'points line')
eq(text:find('Asking the server', 1, true) ~= nil, true, 'waiting for the preview')
text = V.detail(b, state, {build = 'other'})
eq(text:find('Asking the server', 1, true) ~= nil, true, 'a preview of another build is not shown')
local preview = {build = 'w_slayer', name = 'Slayer', add = {added = 80, skipped = 100, other = 2, nodes = {1, 2}},
  reset = {added = 150, removed = 20, cost = 25000, nodes = {1, 2, 3}}}
text = V.detail(b, state, preview)
eq(text:find('Apply: adds 80 nodes', 1, true) ~= nil, true, 'add line')
eq(text:find('100 more nodes of the build need points', 1, true) ~= nil, true, 'skipped line')
eq(text:find('2 nodes your class cannot hold', 1, true) ~= nil, true, 'other line')
eq(text:find('takes back 20 nodes', 1, true) ~= nil, true, 'reset line')
eq(text:find('25,000 gold coins', 1, true) ~= nil, true, 'price')
preview.reset = {added = 0, removed = 0, cost = 0, nodes = {}}
text = V.detail(b, state, preview)
eq(text:find('already fits', 1, true) ~= nil, true, 'nothing to take back')
preview.reset = {added = 5, removed = 3, cost = 0, free = 1, nodes = {1}}
text = V.detail(b, state, preview)
eq(text:find('free reset is used', 1, true) ~= nil, true, 'free reset')
preview.reset.free = nil
text = V.detail(b, state, preview)
eq(text:find('Price: free.', 1, true) ~= nil, true, 'free below the level')

eq(V.canApply(nil), false, 'no preview, no apply')
eq(V.canApply({add = {added = 0}}), false, 'nothing to add')
eq(V.canApply({add = {added = 3}}), true, 'something to add')
eq(V.canReset({reset = {added = 0, removed = 0}}), false, 'nothing to reset')
eq(V.canReset({reset = {added = 0, removed = 2}}), true, 'taking back counts')
eq(V.canReset({reset = {added = 2, removed = 0}}), true, 'adding counts')
eq(V.confirmText({name = 'Slayer', reset = {removed = 4, cost = 1000}}), 'Reset your tree and apply Slayer?\nNodes taken back: 4. Price: 1,000 gold coins.', 'confirm text')
eq(V.confirmText({build = 'x', reset = {}}), 'Reset your tree and apply x?\nNodes taken back: 0. Price: free.', 'confirm text, no name')

if fails > 0 then os.exit(1) end
print('autobuildview_test: ok')
