-- luajit transmogview_test.lua (CI runs every client *_test.lua)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'transmogview.lua')
local V = TransmogView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

eq(V.progressText(12, 231), '12 / 231 (5%)', 'progress text') eq(V.progressText(0, 0), '0 / 0 (0%)', 'empty catalogue')
eq(V.percent(1, 4), 25, 'percent') eq(V.percent(5, 0), 0, 'no total') eq(V.percent(9, 4), 100, 'clamped')
eq(V.gold(1234567), '1,234,567', 'gold') eq(V.gold(999), '999', 'small') eq(V.gold(nil), '0', 'nil gold')
eq(V.gold(-2500), '-2,500', 'negative')

local slots = {
  { slot = 1, name = 'Helmet' },
  { slot = 4, name = 'Armor', item = { id = 2463, cid = 2463, name = 'plate armor', kind = 'armor', kindName = 'Armors',
    applyFee = 2000, removeFee = 0 } },
  { slot = 6, name = 'Left hand', item = { id = 2160, name = 'crystal coin' } },
  { slot = 5, name = 'Right hand', item = { id = 2400, name = 'magic sword', kind = 'sword', applyFee = 5000, removeFee = 0,
    look = { id = 2383, cid = 2383, name = 'spike sword' } } },
}
eq(V.slotSub(slots[1]), 'Empty', 'empty slot') eq(V.slotSub(slots[2]), 'Armors, own look', 'own look')
eq(V.slotSub(slots[3]), 'Cannot change its look', 'no kind') eq(V.slotSub(slots[4]), 'Look: spike sword', 'a look')
eq(V.pickSlot(slots, nil), 4, 'first slot that can change') eq(V.pickSlot(slots, 5), 5, 'the wanted slot')
eq(V.pickSlot(slots, 1), 4, 'an empty wanted slot falls back') eq(V.pickSlot({}, 4), nil, 'nothing')
eq(V.slotRow(slots, 6).name, 'Left hand', 'slot row') eq(V.slotRow(slots, 9), nil, 'no row')

local rows = { { id = 1, name = 'Golden Armor' }, { id = 2, name = 'plate armor' }, { id = 3, name = 'Leather Armor' } }
eq(#V.filter(rows, nil), 3, 'no search') eq(#V.filter(rows, '  '), 3, 'blank search')
eq(#V.filter(rows, 'ARMOR'), 3, 'case-insensitive') eq(V.filter(rows, 'gold')[1].id, 1, 'match')
eq(#V.filter(rows, '(%'), 0, 'plain find, no pattern error')

local d = V.detail(nil, nil, 0)
eq(d.apply, false, 'no row: no apply') eq(d.hint:find('Equip') ~= nil, true, 'equip hint')
d = V.detail(slots[3], nil, 0)
eq(d.hint:find('cannot') ~= nil, true, 'no kind hint')
d = V.detail(slots[2], nil, 10000)
eq(d.apply, false, 'nothing picked') eq(d.remove, false, 'nothing to remove') eq(d.fee, 'Fee: 2,000 gold', 'fee')
d = V.detail(slots[2], { id = 2476, name = 'knight armor' }, 10000)
eq(d.apply, true, 'apply') eq(d.hint:find('stats') ~= nil, true, 'appearance only hint')
d = V.detail(slots[2], { id = 2476 }, 1999)
eq(d.apply, false, 'not enough gold') eq(d.hint:find('gold') ~= nil, true, 'gold hint')
d = V.detail(slots[2], { id = 2463 }, 10000)
eq(d.apply, false, 'its own look') eq(d.hint:find('own look') ~= nil, true, 'own look hint')
d = V.detail(slots[4], { id = 2383 }, 10000)
eq(d.apply, false, 'same look again') eq(d.remove, true, 'remove allowed')
eq(d.fee:find('remove: free') ~= nil, true, 'free removal shown')

local sets = V.sortSets({ { name = 'Lionguard', owned = false, how = 'Store' }, { name = 'Arboreal', owned = false },
  { name = 'Spiritthorn', owned = true } })
eq(sets[1].name, 'Spiritthorn', 'owned first') eq(sets[2].name, 'Arboreal', 'then by name')
eq(V.setLine(sets[1]), 'Owned', 'owned line') eq(V.setLine(sets[3]), 'Store', 'how line')
eq(V.SOURCE_COLORS.store ~= nil, true, 'source colours')

print('transmogview_test: ' .. n .. ' checks OK')
