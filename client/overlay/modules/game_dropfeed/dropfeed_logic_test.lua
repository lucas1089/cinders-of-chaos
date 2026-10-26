-- luajit dropfeed_logic_test.lua && lua5.3 dropfeed_logic_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'dropfeed_logic.lua')
local L = DropFeedLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(L.OPCODE, 229, 'the records opcode')
eq(L.DEFAULT, 'legendary', 'default shows every kind')
eq(#L.MODES, 3, 'three modes')
eq(L.valid('off'), true, 'off')
eq(L.valid('unique'), true, 'unique')
eq(L.valid('legendary'), true, 'legendary')
eq(L.valid('all'), false, 'unknown')
eq(L.valid(nil), false, 'nil')
eq(L.normalize(nil).mode, 'legendary', 'nothing stored')
eq(L.normalize('junk').mode, 'legendary', 'not a table')
eq(L.normalize({ mode = 'bogus' }).mode, 'legendary', 'unknown mode')
eq(L.normalize({ mode = 'off' }).mode, 'off', 'off kept')
eq(L.normalize({ mode = 'unique' }).mode, 'unique', 'unique kept')
eq(L.indexOf('off'), 1, 'index off')
eq(L.indexOf('unique'), 2, 'index unique')
eq(L.indexOf('legendary'), 3, 'index legendary')
eq(L.indexOf('zzz'), 3, 'unknown: the last')
local names = L.modeNames()
for _, m in ipairs(L.MODES) do eq(type(names[m]), 'string', 'a name for ' .. m) end
-- a fake encoder: the packet carries the action and the mode
local function enc(t) return t.action .. ':' .. t.data.mode end
eq(L.packet('off', enc), 'feedopt:off', 'packet off')
eq(L.packet('unique', enc), 'feedopt:unique', 'packet unique')
eq(L.packet('bogus', enc), 'feedopt:legendary', 'a bad mode sends the default')

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks FAILED'); os.exit(1) end
print('dropfeed_logic_test: ' .. checks .. ' checks ok')
