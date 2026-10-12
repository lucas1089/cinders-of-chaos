-- luajit kitewalklogic_test.lua && lua5.3 kitewalklogic_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'kitewalklogic.lua')
local L = KiteWalkLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the protocol, the same numbers as the server (chaos_constants.lua ChaosOpcodes.kiteWalk)
eq(L.OPCODE, 186, 'opcode')
eq(L.OPTION, 'keepAttackingWhileMoving', 'option id (dataset.lua and interface.otui, base patch 0039)')
local f = io.open(dir .. '../../../../server/data/scripts/chaos/chaos_constants.lua', 'r')
if f then
  local text = f:read('*a'); f:close()
  eq(text:find('ChaosOpcodes.kiteWalk = 186', 1, true) ~= nil, true, 'server constant matches')
end
-- base patch 0039 adds the option under the same id and hands changes to this module
f = io.open(dir .. '../../../base-patches/0039-keep-attacking-while-moving-option.patch', 'r')
if f then
  local text = f:read('*a'); f:close()
  eq(text:find('+\tkeepAttackingWhileMoving = {', 1, true) ~= nil, true, 'patch 0039: dataset entry')
  eq(text:find('id: keepAttackingWhileMoving', 1, true) ~= nil, true, 'patch 0039: checkbox')
  eq(text:find('modules.game_kitewalk', 1, true) ~= nil, true, 'patch 0039: apply calls this module')
  -- the base "Auto Chase Off" must not switch the stance while the option is on (the server resumes the chase)
  eq(text:find("+  if m_settings.getOption('keepAttackingWhileMoving') ~= false then", 1, true) ~= nil, true,
    'patch 0039: Auto Chase Off skipped while the option is on')
end

-- the option: on unless explicitly off (an older settings module without it: on, the server's default)
eq(L.isOn(nil), true, 'no option: on')
eq(L.isOn(true), true, 'true: on')
eq(L.isOn(false), false, 'false: off')
eq(L.isOn(0), false, '0: off')
eq(L.isOn('0'), false, 'text 0: off')
eq(L.isOn('false'), false, 'text false: off')
eq(L.isOn(1), true, '1: on')

-- the message
eq(L.message(true).on, true, 'message on')
eq(L.message(false).on, false, 'message off')
eq(L.message(nil).on, false, 'message of nil is a boolean')
local keys = 0
for _ in pairs(L.message(true)) do keys = keys + 1 end
eq(keys, 1, 'one field')

-- when to send: a new session always, then only a change
eq(L.needsSend(nil, true, false), true, 'first send of a session')
eq(L.needsSend(true, true, false), false, 'same value: nothing')
eq(L.needsSend(true, false, false), true, 'turned off')
eq(L.needsSend(false, true, false), true, 'turned on')
eq(L.needsSend(true, true, true), true, 'forced')

print(string.format('kitewalklogic_test: %d checks, %d failures', checks, fails))
if fails > 0 then os.exit(1) end
