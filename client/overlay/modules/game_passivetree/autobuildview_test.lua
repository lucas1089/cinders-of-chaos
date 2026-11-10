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

-- the keystone cap (O447): Apply on top of the keystones held would go past it: the server's line replaces the Apply line
local capLine = 'You can hold at most 3 keystones. Refund one to take another.'
preview.add = {added = 80, skipped = 0, other = 0, keystones = 4, capText = capLine}
preview.reset = {added = 5, removed = 3, cost = 0, nodes = {1}, keystones = 3}
text = V.detail(b, state, preview)
eq(text:find(capLine, 1, true) ~= nil, true, 'the cap line is shown')
eq(text:find('Apply: adds', 1, true), nil, 'no Apply line over the cap')
eq(text:find('Reset and apply: takes back 3 nodes', 1, true) ~= nil, true, 'Reset and apply is still offered')
eq(V.canApply(preview), false, 'over the cap: no Apply')
eq(V.canReset(preview), true, 'over the cap: Reset and apply still works')

eq(V.canApply(nil), false, 'no preview, no apply')
eq(V.canApply({add = {added = 0}}), false, 'nothing to add')
eq(V.canApply({add = {added = 3}}), true, 'something to add')
eq(V.canReset({reset = {added = 0, removed = 0}}), false, 'nothing to reset')
eq(V.canReset({reset = {added = 0, removed = 2}}), true, 'taking back counts')
eq(V.canReset({reset = {added = 2, removed = 0}}), true, 'adding counts')
eq(V.confirmText({name = 'Slayer', reset = {removed = 4, cost = 1000}}), 'Reset your tree and apply Slayer?\nNodes taken back: 4. Price: 1,000 gold coins.', 'confirm text')
eq(V.confirmText({build = 'x', reset = {}}), 'Reset your tree and apply x?\nNodes taken back: 0. Price: free.', 'confirm text, no name')

-- a note (the server's answer) stands in for "Asking..." and follows a preview
text = V.detail(b, state, nil, {text = 'No answer.', color = '#e07060'})
eq(text:find('Asking the server', 1, true), nil, 'a note replaces the waiting line')
eq(select(2, V.detail(b, state, nil, {text = 'No answer.', color = '#e07060'})), '#e07060', 'in its colour')
text = V.detail(b, state, preview, {text = 'Auto build: 5 nodes added.', color = V.GOOD})
eq(text:sub(-#'Auto build: 5 nodes added.'), 'Auto build: 5 nodes added.', 'the applied message under the preview')

-- the preview request: when to ask, the tries, the timeout and the errors
eq(V.needsPreview(nil, nil, nil, nil), false, 'nothing picked')
eq(V.needsPreview('a', nil, nil, nil), true, 'picked, nothing shown: ask')
eq(V.needsPreview('a', {build = 'a'}, nil, nil), false, 'shown already')
eq(V.needsPreview('a', {build = 'b'}, nil, nil), true, 'another build shown')
eq(V.needsPreview('a', nil, {build = 'a', tries = 1}, nil), false, 'asked already')
eq(V.needsPreview('a', nil, {build = 'b', tries = 1}, nil), true, 'another build asked')
eq(V.needsPreview('a', nil, nil, 'a'), false, 'failed: not again until picked again')
local pend = V.ask(nil, 'a')
eq(pend.tries, 1, 'first try'); eq(V.ask(pend, 'a').tries, 2, 'again: second try'); eq(V.ask(pend, 'b').tries, 1, 'new pick')
eq(V.onTimeout(pend), 'retry', 'timeout: retry')
eq(V.onTimeout({build = 'a', tries = V.MAX_TRIES}), 'fail', 'timeout: give up after the last try')
eq(V.onTimeout(nil), 'fail', 'timeout without a request')
eq(V.onError(nil, {message = 'x'}), 'ignore', 'error without a request (an Apply error)')
eq(V.onError(pend, {message = 'x', build = 'b'}), 'ignore', 'error of another build')
eq(V.onError(pend, {message = 'x', build = 'a', retry = true}), 'retry', 'too fast: retry')
eq(V.onError({build = 'a', tries = V.MAX_TRIES}, {build = 'a', retry = true}), 'fail', 'too fast on the last try')
eq(V.onError(pend, {message = 'not your class', build = 'a'}), 'fail', 'refused')
eq(V.onError(pend, {message = 'old server'}), 'fail', 'an error without a build answers the pending one')

-- save to a loadout slot (O448)
do
  local choices = {slots = {{slot = 1, empty = true}, {slot = 2, name = 'Live', active = true}, {slot = 3, name = 'Boss run'},
    {slot = 4, empty = true, locked = true}, {slot = 5, name = 'Old', active = true, locked = true}}, level = 100, minLevel = 15, nextUnlock = 200}
  local r = V.slotRows(choices)
  eq(#r, 2, 'slot rows: the free slots only')
  eq(r[1].slot, 1, 'slot rows: first slot'); eq(r[1].empty, true, 'slot rows: empty'); eq(r[1].text, 'Slot 1 - (empty)', 'slot rows: empty text')
  eq(r[2].slot, 3, 'slot rows: held slot'); eq(r[2].empty, false, 'slot rows: held'); eq(r[2].name, 'Boss run', 'slot rows: name')
  eq(r[2].text, 'Slot 3 - Boss run', 'slot rows: held text')
  eq(#V.slotRows(nil), 0, 'slot rows: nothing yet'); eq(#V.slotRows({}), 0, 'slot rows: no list'); eq(#V.slotRows({slots = 'x'}), 0, 'slot rows: a bad list')
  eq(V.slotRows({slots = {{slot = 2}}})[1].text, 'Slot 2 - ?', 'slot rows: a held slot without a name')
  eq(V.noSlotText(choices), 'No loadout slot is free to pick: the active one holds your live build and the others are locked. One more opens at level 200.', 'no slot: with the next level')
  eq(V.noSlotText({level = 600, minLevel = 15}), 'No loadout slot is free to pick: the active one holds your live build and the others are locked.', 'no slot: nothing more to unlock')
  eq(V.noSlotText({level = 10, minLevel = 15}), 'Loadouts open at level 15.', 'no slot: below the loadouts level')
  eq(V.noSlotText(nil), 'No loadout slot is free to pick: the active one holds your live build and the others are locked.', 'no slot: nil')
  local intro = V.pickText({id = 'w_slayer', name = 'Slayer'})
  eq(intro:find('Save Slayer into one of your loadout slots.', 1, true) ~= nil, true, 'pick text: the build')
  eq(intro:find('gear, runes and Paragon stay as they were', 1, true) ~= nil, true, 'pick text: gear and runes stay')
  eq(intro:find('your live tree does not change', 1, true) ~= nil, true, 'pick text: the live tree stays')
  eq(V.pickText({id = 'w_slayer'}):find('Save w_slayer', 1, true) ~= nil, true, 'pick text: the id when there is no name')
  local ask = V.replaceText(3, 'Boss run', 'Slayer')
  eq(ask:find('Slot 3 holds Boss run.', 1, true) ~= nil, true, 'replace text: slot and held name')
  eq(ask:find('Replace its passive tree with Slayer?', 1, true) ~= nil, true, 'replace text: the question')
  eq(ask:find('gear, runes and Paragon stay as they were', 1, true) ~= nil, true, 'replace text: what stays')
  eq(V.savedText({message = 'Saved.', lines = {'A', '', 'B'}}), 'Saved.\nA\nB', 'saved text: message and lines')
  eq(V.savedText({}), 'Build saved.', 'saved text: a fallback'); eq(V.savedText(nil), 'Build saved.', 'saved text: nil')
  eq(V.isSlotAnswer({message = 'x', slot = 3}), true, 'a slot answer'); eq(V.isSlotAnswer({message = 'x', build = 'a'}), false, 'a preview error')
  eq(V.isSlotAnswer(nil), false, 'no answer'); eq(V.isSlotAnswer('x'), false, 'a string')
end

if fails > 0 then os.exit(1) end
print('autobuildview_test: ok')
