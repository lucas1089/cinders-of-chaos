-- luajit ringslotlogic_test.lua && lua5.3 ringslotlogic_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'ringslotlogic.lua')
local L = RingSlotLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(L.SLOT, 10, 'the second ring slot is inventory slot 10 (the old ammunition slot)')
eq(L.slotTooltip(10, false), 'Ring', 'empty: "Ring"')
eq(L.slotTooltip(10, true), '', 'an item in it: its own tooltip')
eq(L.slotTooltip('10', false), 'Ring', 'a slot number as text')
eq(L.slotTooltip(9, false), nil, 'the first ring slot is left as it is')
eq(L.slotTooltip(5, false), nil, 'other slots are left as they are')
eq(L.SOUL_TOOLTIP:lower():find('ammunition', 1, true), nil, 'the soul tooltip names no ammunition')
eq(L.SOUL_TOOLTIP:find('runes', 1, true) ~= nil, true, 'it still names runes')

if fails > 0 then print('ringslotlogic_test: ' .. fails .. ' failure(s)') os.exit(1) end
print('ringslotlogic_test: ' .. checks .. ' checks ok')
