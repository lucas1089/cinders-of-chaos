-- luajit playerinspect_logic_test.lua && lua5.3 playerinspect_logic_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'playerinspect_logic.lua')
local L = PlayerInspectLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(L.cleanName('  Sir  Lancelot '), 'Sir Lancelot', 'spaces')
eq(L.cleanName("O'Neil-Smith"), "O'Neil-Smith", 'apostrophe, hyphen')
eq(L.cleanName('a'), nil, 'too short')
eq(L.cleanName(string.rep('a', 30)), nil, 'too long')
eq(L.cleanName('x;y'), nil, 'punctuation')
eq(L.cleanName(''), nil, 'empty')
eq(L.cleanName(nil), nil, 'nil')
eq(L.numberText(1234567), '1,234,567', 'thousands')
eq(L.numberText(120), '120', 'small')
eq(L.numberText(nil), '0', 'nil')

local n = 0
for slot = 1, 10 do if L.SLOTS[slot] then n = n + 1 end end
eq(n, 10, 'all ten inventory slots have a place')
local seen = {}
for slot, p in pairs(L.SLOTS) do
  local k = p.col .. ',' .. p.row
  eq(seen[k], nil, 'slot ' .. slot .. ' has its own place')
  seen[k] = true
end

local lines = L.lines({ level = 120, voc = 'Berserker', ascended = true, guild = { name = 'Ravens', rank = 'Officer' },
  ach = 12500, rift = 7, trials = 2 })
eq(lines[1].text, 'Level 120 Berserker', 'level line')
eq(lines[2].text, 'Ascended class', 'ascended')
eq(lines[3].text, 'Officer of Ravens', 'guild')
eq(lines[4].text, 'Achievement points: 12,500', 'points')
eq(lines[5].text, 'Best rift sealed: tier 7', 'rift')
eq(lines[6].text, 'Vocation Trials: tier 2 of 3', 'trials')
lines = L.lines({ level = 8, voc = '', ach = 0, rift = 0, trials = 0 })
eq(lines[1].text, 'Level 8 No vocation', 'no vocation')
eq(lines[2].text, 'No guild', 'no guild')
eq(lines[4].text, 'No rift sealed yet', 'no rift')
eq(lines[5].text, 'No Vocation Trial cleared', 'no trial')
eq(#lines, 5, 'five lines without the ascended one')

local st = L.newState()
eq(L.complete(st), false, 'nothing yet')
eq(L.onEquip(st, { name = 'Anna', rows = {} }), false, 'equipment before a result is ignored')
L.onResult(st, { name = 'Anna', parts = 2 })
eq(L.complete(st), false, 'waiting for the equipment')
eq(L.onEquip(st, { name = 'Bob', rows = { { slot = 1, tip = { name = 'x' } } } }), false, 'another character')
eq(L.onEquip(st, { name = 'Anna', rows = { { slot = 1, tip = { name = 'Helm' } }, { slot = 99, tip = {} } } }), true, 'first packet')
eq(st.tips[1].name, 'Helm', 'tip kept')
eq(st.tips[99], nil, 'unknown slot ignored')
eq(L.complete(st), false, 'one packet of two')
L.onEquip(st, { name = 'Anna', rows = { { slot = 6, tip = { name = 'Sword' } } } })
eq(L.complete(st), true, 'complete')
L.onResult(st, { name = 'Bob', parts = 0 })
eq(L.complete(st), true, 'no equipment is complete at once')
eq(st.tips[1], nil, 'a new result clears the slots')
eq(L.tipKey('Anna', 1, { key = '5:6' }), 'inspect:Anna:1:5:6', 'tooltip key')

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks FAILED'); os.exit(1) end
print('playerinspect_logic_test: ' .. checks .. ' checks ok')
