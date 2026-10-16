-- luajit potiongate_test.lua && lua5.3 potiongate_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'potiongate.lua')
local G = ChaosPotionGate
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local EVERFULL_HEALTH = 266 -- the client look of the Everfull Health Potion (server 32085) and the Health Potion
local st = G.newState()
-- seen in an open backpack: used as before, every time the helper wants
eq(G.allowed(st, EVERFULL_HEALTH, 0, 1), true, 'a counted potion is used')
G.used(st, EVERFULL_HEALTH, 0, 1)
eq(G.allowed(st, EVERFULL_HEALTH, 10, 1), true, 'and again')

-- in a closed backpack: count 0, but the server finds it (base patch 0043 for the Everfull): a probe every 3 s
st = G.newState()
eq(G.allowed(st, EVERFULL_HEALTH, 1000, 0), true, 'count 0: a probe is allowed')
G.used(st, EVERFULL_HEALTH, 1000, 0)
eq(G.allowed(st, EVERFULL_HEALTH, 2000, 0), false, 'no second probe within 3 s')
eq(G.allowed(st, EVERFULL_HEALTH, 4000, 0), true, 'the next probe after 3 s')
eq(G.onText(st, 'You see an everfull health potion.', 1200), false, 'other texts are not a failure')

-- nothing carried (or a server without 0043 for the Everfull): the reply backs off 30 s
G.used(st, EVERFULL_HEALTH, 4000, 0)
eq(G.onText(st, 'Sorry, not possible.', 4500), true, 'the failure answers the probe')
eq(G.allowed(st, EVERFULL_HEALTH, 8000, 0), false, 'backed off')
eq(G.allowed(st, EVERFULL_HEALTH, 34600, 0), true, 'tried again after 30 s')
eq(G.allowed(st, EVERFULL_HEALTH, 8000, 1), true, 'a potion seen again is used at once')

-- a failure long after the probe is someone else's
G.used(st, 268, 50000, 0)
eq(G.onText(st, 'Sorry, not possible.', 60000), false, 'a late failure is not the probe\'s')
eq(G.allowed(st, 268, 53000, 0), true, 'no backoff from it')

if fails > 0 then error(fails .. ' failure(s)') end
print('potiongate_test: OK')
