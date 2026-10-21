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

-- runes (owner 2026-10-20: "o helper nao esta usando runas"): the magic shooter and the healing rune ran only with a
-- count above 0, so a rune in a closed backpack was never used. The call sites (base patch 0082) go through
-- ChaosPotionGate.canUse / noteUse on the shared session
local SUDDEN_DEATH = 3155 -- the client look of the Reaper's Rune
G.session = G.newState()
eq(type(G.canUse), 'function', 'canUse exists')
eq(type(G.noteUse), 'function', 'noteUse exists')
eq(G.canUse(SUDDEN_DEATH, 0, 1000), true, 'a rune the client cannot count gets a probe')
G.noteUse(SUDDEN_DEATH, 0, 1000)
eq(G.canUse(SUDDEN_DEATH, 0, 2000), false, 'no second rune probe within 3 s')
eq(G.canUse(3191, 0, 2000), true, 'another rune has its own probe')
eq(G.canUse(SUDDEN_DEATH, 5, 2000), true, 'a rune the client counts is used at once')
G.noteUse(SUDDEN_DEATH, 5, 2000)
eq(G.canUse(SUDDEN_DEATH, 0, 2100), true, 'seeing it again cleared the wait')
G.noteUse(SUDDEN_DEATH, 0, 5000)
eq(G.onText(G.session, 'Sorry, not possible.', 5400), true, 'no rune carried: the answer backs the probe off')
eq(G.canUse(SUDDEN_DEATH, 0, 9000), false, 'rune backed off')
eq(G.canUse(SUDDEN_DEATH, 0, 35500), true, 'and tried again after 30 s')
G.reset()
eq(G.canUse(SUDDEN_DEATH, 0, 0), true, 'reset forgets the waits')

-- owner beta 2026-10-20: "the helper stopped using the potion" (Ranger at 21 mana, Everfull potions in a closed
-- backpack). The heal spell went out in the same tick as the potion probe and the server refused it for the mana.
local EVERFULL_MANA = 268
st = G.newState()
eq(G.allowed(st, EVERFULL_MANA, 1000, 0), true, 'mana potion: a probe')
G.used(st, EVERFULL_MANA, 1000, 0)
eq(G.onText(st, 'You do not have enough mana.', 1011), false, "a spell's mana refusal is not the potion's answer")
eq(G.onText(st, 'Using an everfull mana potion (never runs out).', 1012), true, 'the probe found it')
eq(G.allowed(st, EVERFULL_MANA, 1050, 0), true, 'found: used again at once (no 3 s probe wait)')
G.used(st, EVERFULL_MANA, 2000, 0)
eq(G.allowed(st, EVERFULL_MANA, 2100, 0), true, 'found: no probe wait after a use either')
-- a spell refused with "Sorry, not possible." just before the potion's own answer
G.used(st, EVERFULL_MANA, 3000, 0)
eq(G.onText(st, 'Sorry, not possible.', 3010), true, 'a failure is held for the probe')
eq(G.allowed(st, EVERFULL_MANA, 3100, 0), false, 'not settled yet: wait')
eq(G.onText(st, 'Using an everfull mana potion (never runs out).', 3012), true, 'its own "Using" takes it back')
eq(G.allowed(st, EVERFULL_MANA, 3700, 0), true, 'no 30 s back-off')
eq(G.allowed(st, EVERFULL_MANA, 40000, 0), true, 'still found later')
-- the potion is really gone (dropped): the failure settles, back to probes after 30 s
G.used(st, EVERFULL_MANA, 50000, 0)
G.onText(st, 'Sorry, not possible.', 50010)
eq(G.allowed(st, EVERFULL_MANA, 50600, 0), false, 'gone: backed off')
eq(G.allowed(st, EVERFULL_MANA, 79000, 0), false, 'still within 30 s')
eq(G.allowed(st, EVERFULL_MANA, 80100, 0), true, 'a probe again after 30 s')
-- a rune and a potion probed in the same tick: the server answers in order
st = G.newState()
G.used(st, SUDDEN_DEATH, 1000, 0)
G.used(st, EVERFULL_MANA, 1000, 0)
G.onText(st, 'Using one of 3 sudden death runes...', 1010)
G.onText(st, 'Sorry, not possible.', 1011)
eq(G.allowed(st, SUDDEN_DEATH, 1700, 0), true, 'the first answer is the rune\'s: found')
eq(G.allowed(st, EVERFULL_MANA, 1700, 0), false, 'the second the potion\'s: backed off')
st = G.newState()
G.used(st, SUDDEN_DEATH, 1000, 0)
G.used(st, EVERFULL_MANA, 1000, 0)
G.onText(st, 'Sorry, not possible.', 1010)
G.onText(st, 'Using an everfull mana potion (never runs out).', 1011)
eq(G.allowed(st, SUDDEN_DEATH, 1700, 0), false, 'rune refused')
eq(G.allowed(st, EVERFULL_MANA, 1700, 0), true, 'potion found')

if fails > 0 then error(fails .. ' failure(s)') end
print('potiongate_test: OK')
