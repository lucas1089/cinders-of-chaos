-- luajit waystonelogic_test.lua && lua5.3 waystonelogic_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'waystonelogic.lua')
local W = ChaosWaystone
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(c, what) eq(not not c, true, what) end

eq(W.OPCODE, 202, 'the base waystone opcode')
eq(#W.TIER_CLIENT_IDS, 6, 'six base tiers')
eq(#W.ROMAN, 15, 'fifteen numerals')

-- a patched server: the tiers held, a pick
local rows = W.rows({ action = 'show', tiers = {
  { clientId = 27189, look = 30001, tier = 1, count = 2 },
  { clientId = 27191, tier = 3, count = 1 },
  { clientId = 27194, tier = 6, count = 0 },
  { clientId = 99999, tier = 16, count = 5 },    -- not a tier: ignored
  'junk', { clientId = 'x' } }, pick = 27191 })
eq(#rows, 6, 'six rows')
eq(rows[1].roman, 'I', 'tier I')
eq(rows[1].count, 2, 'tier I: two held')
eq(rows[1].look, 30001, 'tier I: the server\'s look')
eq(rows[3].look, 27191, 'no look: the client id')
ok(rows[1].usable, 'tier I usable')
eq(rows[2].count, 0, 'tier II not listed: none')
ok(not rows[2].usable, 'tier II not usable')
eq(rows[6].count, 0, 'tier VI: none')
eq(W.firstRow(rows, 27191), 3, 'the pick first')
eq(W.firstRow(rows, nil), 1, 'no pick: the lowest tier held')
eq(W.firstRow(rows, 12345), 1, 'an unknown pick: the lowest held')
eq(W.countText(rows[1]), '2 held', 'count text')
eq(W.countText(rows[2]), 'none', 'none text')

-- part 3: fifteen tiers, VII-XV keyed by their server ids, with levels
local list = {}
for t = 1, 15 do
  list[#list + 1] = { clientId = t <= 6 and 27188 + t or 41944 + t, tier = t, count = t == 15 and 1 or 0, level = 1000 + 100 * t }
end
local r15 = W.rows({ action = 'show', tiers = list, pick = 41959 })
eq(#r15, 15, 'fifteen rows')
eq(r15[15].roman, 'XV', 'tier XV')
eq(r15[15].clientId, 41959, 'its key')
eq(r15[1].level, 1100, 'tier I level 1100')
eq(r15[15].level, 2500, 'tier XV level 2500')
eq(W.levelText(r15[15]), 'level 2500', 'level text')
eq(W.firstRow(r15, 41959), 15, 'tier XV picked')
ok(r15[15].usable and not r15[7].usable, 'held / not held')
eq(W.levelText({}), '', 'no level: no text')
r15 = W.rows({ tiers = { { clientId = 41951, tier = 7, count = 1, level = -5 } } })
eq(#r15, 7, 'the six and tier VII')
eq(r15[7].level, nil, 'a bad level: none')

-- the request
local req = W.teleportRequest(rows[3])
eq(req and req.action, 'teleport', 'teleport request')
eq(req and req.clientId, 27191, 'with the tier\'s client id')
eq(W.teleportRequest(rows[2]), nil, 'none held: no request')
eq(W.teleportRequest(nil), nil, 'no row: no request')

-- a server without part 2 of the patch: no counts, every row usable, the server decides
rows = W.rows({ action = 'show' })
eq(rows[4].count, nil, 'unknown count')
ok(rows[4].usable, 'usable when unknown')
eq(W.countText(rows[4]), '', 'no count text')
eq(W.firstRow(rows), 1, 'first row')
rows = W.rows(nil)
eq(#rows, 6, 'rows from nothing')

-- bad numbers
rows = W.rows({ tiers = { { clientId = 27190, count = -3 }, { clientId = 27192, count = 1.5 }, { clientId = 27193, count = 1/0 } } })
eq(rows[2].count, 0, 'negative count: none')
eq(rows[4].count, 0, 'fractional count: none')
eq(rows[5].count, 0, 'infinite count: none')

-- pad looks
local c = W.choices({ choices = { { id = 2, text = 'Gold Portal' }, { id = 0, text = 'Default Pad' }, { id = -1 }, 'x', { id = 1.5 } } })
eq(#c, 2, 'two valid looks')
eq(c[1].id, 0, 'the default first')
eq(c[2].text, 'Gold Portal', 'text kept')
eq(#W.choices({}), 0, 'no looks')

-- the server's answers
eq(W.classify({ action = 'show' }), 'show', 'show')
eq((W.classify({ action = 'teleport_done' })), 'close', 'portals open: close')
local kind, text = W.classify({ action = 'teleport_error', text = 'You have no waystone of that tier.' })
eq(kind, 'status', 'error: status line')
eq(text, 'You have no waystone of that tier.', 'the server\'s text')
kind, text = W.classify({ action = 'choice_error' })
eq(text, 'The device refused.', 'an error without text')
eq(W.classify({ action = 'choice_show' }), 'choices', 'looks')
eq(W.classify({ action = 'what' }), nil, 'unknown')
eq(W.classify('x'), nil, 'not a table')
eq(W.classify({ action = 5 }), nil, 'no action string')

if fails > 0 then error(fails .. ' failure(s)') end
print('waystonelogic_test: OK')
