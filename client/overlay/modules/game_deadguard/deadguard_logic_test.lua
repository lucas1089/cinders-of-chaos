-- luajit deadguard_logic_test.lua && lua5.3 deadguard_logic_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'deadguard_logic.lua')
local L = DeadGuardLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local function mon(over)
  local t = { isPlayer = false, isLocalPlayer = false, healthPercent = 0, removed = false, onMap = true }
  for k, v in pairs(over or {}) do t[k] = v end
  return t
end

eq(L.GRACE_MS, 3000, 'grace is 3 seconds')
eq(L.decide(mon(), 0), 'wait', 'just died')
eq(L.decide(mon(), 2999), 'wait', 'inside the grace')
eq(L.decide(mon(), 3000), 'remove', 'at the grace')
eq(L.decide(mon(), 60000), 'remove', 'long after')
eq(L.decide(mon({ isPlayer = true }), 60000), 'skip', 'a player is never removed')
eq(L.decide(mon({ isLocalPlayer = true }), 60000), 'skip', 'the local player is never removed')
eq(L.decide(mon({ isPlayer = true, healthPercent = 0 }), 0), 'skip', 'a player at 0 percent')
eq(L.decide(mon({ healthPercent = 1 }), 60000), 'skip', 'alive')
eq(L.decide(mon({ healthPercent = 100 }), 60000), 'skip', 'full health')
local unk = mon(); unk.healthPercent = nil
eq(L.decide(unk, 60000), 'skip', 'unknown health')
eq(L.decide(mon({ removed = true }), 60000), 'skip', 'the engine removed it')
eq(L.decide(mon({ onMap = false }), 60000), 'skip', 'not on a tile')
eq(L.decide(nil, 60000), 'skip', 'no info')
eq(L.decide(mon(), nil), 'wait', 'no age counts as zero')

local s = L.newState()
eq(L.wantsWatch(s, 7, false, false, 0), true, 'a monster at 0')
eq(L.wantsWatch(s, 7, true, false, 0), false, 'a player')
eq(L.wantsWatch(s, 7, false, true, 0), false, 'the local player')
eq(L.wantsWatch(s, 7, false, false, 50), false, 'alive')
eq(L.wantsWatch(s, 7, false, false, nil), false, 'no percent')
eq(L.wantsWatch(s, nil, false, false, 0), false, 'no id')
s.pending[7] = true
eq(L.wantsWatch(s, 7, false, false, 0), false, 'already watched')
L.forget(s, 7)
eq(L.wantsWatch(s, 7, false, false, 0), true, 'watched again after forget')

eq(L.shouldLog(s, 42), true, 'first report of an id')
eq(L.shouldLog(s, 42), false, 'once per id')
eq(L.shouldLog(s, 43), true, 'another id logs')
L.reset(s)
eq(L.shouldLog(s, 42), true, 'after reset logs again')

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks FAILED'); os.exit(1) end
print('deadguard_logic_test ok (' .. checks .. ' checks)')
