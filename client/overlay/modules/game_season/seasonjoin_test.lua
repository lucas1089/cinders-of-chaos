-- luajit seasonjoin_test.lua && lua5.3 seasonjoin_test.lua (CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'seasonjoin.lua')
local J = SeasonJoin
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the four modes as season_modes.lua sends them
local data = { text = 'Join Season of Ash?', modes = {
  { key = 'standard', name = 'Standard', ssf = false, hc = false, warning = 'Trade with everyone.' },
  { key = 'ssf', name = 'Self-Found', ssf = true, hc = false, warning = 'No trading.' },
  { key = 'hc', name = 'Hardcore', ssf = false, hc = true, warning = 'One life.' },
  { key = 'hcssf', name = 'Hardcore Self-Found', short = 'HC Self-Found', ssf = true, hc = true, warning = 'Both.' },
  { key = 'hc', name = 'again' },          -- a duplicate is dropped
  { name = 'no key' }, 'junk' } }
local c = J.choices(data)
eq(#c, 4, 'four choices')
eq(c[1].key, 'standard', 'standard first')
eq(c[4].key, 'hcssf', 'order kept')
eq(J.find(c, 'hc').name, 'Hardcore', 'find')
eq(J.find(c, 'hcssf').short, 'HC Self-Found', 'short button label')
eq(J.find(c, 'hc').short, 'Hardcore', 'short falls back to the name')
eq(J.find(c, 'nope'), nil, 'find unknown')

-- an older server: no modes -> Standard only
local old = J.choices({ text = 'Join?' })
eq(#old, 1, 'older server: one choice')
eq(old[1].key, 'standard', 'older server: standard')
eq(J.payload(old[1]).mode, 'standard', 'older server still joins')
eq(#J.choices(nil), 1, 'no data at all')
-- modes without standard: it is added in front
eq(J.choices({ modes = { { key = 'ssf', name = 'SSF' } } })[1].key, 'standard', 'standard always offered')

-- Standard and Self-Found join at once
eq(J.canJoin(J.find(c, 'standard'), false), true, 'standard joins')
eq(J.payload(J.find(c, 'ssf'), false).mode, 'ssf', 'SSF joins without the box')
eq(J.payload(J.find(c, 'ssf'), false).confirm, true, 'payload confirms')
eq(J.joinLabel(J.find(c, 'ssf')), 'Join', 'SSF label')
-- Hardcore needs the box
eq(J.needsAck(J.find(c, 'hc')), true, 'HC asks')
eq(J.needsAck(J.find(c, 'hcssf')), true, 'HC SSF asks')
eq(J.needsAck(J.find(c, 'ssf')), false, 'SSF does not ask')
eq(J.payload(J.find(c, 'hc'), false), nil, 'HC not ticked: no join')
eq(J.payload(J.find(c, 'hcssf'), true).mode, 'hcssf', 'HC SSF ticked: joins')
eq(J.joinLabel(J.find(c, 'hc')), 'Join (one life)', 'HC label')
eq(J.payload(nil, true), nil, 'nothing chosen')
eq(J.warningText(J.find(c, 'hc')), 'One life.', 'warning')
eq(J.warningText({ name = 'X', warning = '' }), 'X', 'no warning: the name')

-- the Season window line and the heartbeat
eq(J.modeLine({ mode = 'standard' }), nil, 'standard: no line')
eq(J.modeLine({ mode = 'hcssf', modeName = 'Hardcore Self-Found' }), 'Mode: Hardcore Self-Found.', 'mode line')
eq(J.modeLine({ mode = 'standard', fallen = { level = 88, cause = 'killed by a dragon' } }),
  'Fallen in Hardcore at level 88 (killed by a dragon).', 'fallen line')
eq(J.modeLine(nil), nil, 'no state')
eq(J.heartbeat({ hc = true, heartbeat = 2 }), 2, 'HC beats')
eq(J.heartbeat({ hc = false, heartbeat = 2 }), nil, 'not HC')
eq(J.heartbeat({ hc = true }), nil, 'no interval')
eq(J.wrap('aaa bbb ccc', 7), 'aaa bbb\nccc', 'wrap')

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('seasonjoin_test: OK')
