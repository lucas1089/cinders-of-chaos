-- luajit npctravellogic_test.lua (CI runs every client/overlay/modules/*/*_test.lua from the repo root, under LuaJIT and Lua 5.3)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'npctravellogic.lua')
local L = NpcTravelLogic
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

-- keys: sorted, no duplicates, valid
local seen, prev = {}, ''
for _, k in ipairs(L.KEYS) do
  eq(seen[k], nil, 'duplicate key ' .. k)
  seen[k] = true
  eq(k > prev, true, 'sorted at ' .. k)
  prev = k
  eq(L.valid(k), true, 'valid ' .. k)
end
eq(L.valid('nothing'), false, 'unknown key')
eq(L.valid(nil), false, 'nil key')
eq(L.valid(5), false, 'number key')
eq(L.valid(''), false, 'empty key')

-- factions
eq(L.factionKey('vigil'), 'faction_vigil', 'faction key')
eq(L.factionKey('circle'), 'faction_circle', 'faction key circle')
eq(L.factionKey('nope'), nil, 'unknown faction')
eq(L.factionKey(nil), nil, 'nil faction')

-- the request
local m = L.message('stash')
eq(m.action, 'travel', 'action')
eq(m.data.k, 'stash', 'data.k')
eq(L.message('x'), nil, 'no message for an unknown key')

-- throttle
eq(L.tooSoon(10, nil), false, 'first request')
eq(L.tooSoon(10.5, 10), true, 'half a second later')
eq(L.tooSoon(11, 10), false, 'a second later')
eq(L.tooSoon(5, 10), false, 'clock went back')

print('npctravellogic_test: ' .. n .. ' checks ok')
