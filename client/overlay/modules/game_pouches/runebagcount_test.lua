-- luajit runebagcount_test.lua (CI runs every client *_test.lua)
-- The Rune Bag in the purse (O509): the count the client adds to its own, the old engine, the open bag, the poll, the wrap.
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'runebagcount.lua')
local R = RuneBagCount
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

local DISPEL, MENDING = 2261, 2265

-- a new state counts nothing
local st = R.newState()
eq(R.extra(st, DISPEL), 0, 'new state: nothing added')
eq(R.pollMs(st), 15000, 'new state: the slow poll')

-- the engine has the patch: the server's counts (JSON keys are text) are added
eq(R.apply(st, { engine = true, bag = true, poll = 2, counts = { ['2261'] = 12, ['2265'] = 3 } }), true, 'a new answer changes the count')
eq(R.extra(st, DISPEL), 12, 'the purse bag holds 12 Dispel runes') eq(R.extra(st, MENDING), 3, 'and 3 Mending')
eq(R.extra(st, 2273), 0, 'a rune it does not hold adds nothing')
eq(R.pollMs(st), 2000, 'a bag in the purse: poll every 2 s')
eq(R.apply(st, { engine = true, bag = true, poll = 2, counts = { ['2261'] = 12, ['2265'] = 3 } }), false, 'the same answer changes nothing')
eq(R.apply(st, { engine = true, bag = true, poll = 2, counts = { ['2261'] = 11, ['2265'] = 3 } }), true, 'a rune used: changed')
eq(R.extra(st, DISPEL), 11, 'the new count')

-- the old engine (no patch): the server says engine = false; nothing is added whatever it lists, no use that would fail
local old = R.newState()
R.apply(old, { engine = false, counts = { ['2261'] = 12 }, bag = true, poll = 2 })
eq(R.extra(old, DISPEL), 0, 'old engine: nothing added')
eq(R.signature(old), 'off', 'old engine: the signature is off')
eq(R.apply(old, { engine = false, counts = {} }), false, 'old engine: again, no change')
-- the engine is replaced while the client is online (a restart): the state follows the answer
eq(R.apply(old, { engine = true, bag = true, poll = 2, counts = { ['2261'] = 5 } }), true, 'the engine now has the patch')
eq(R.extra(old, DISPEL), 5, 'counted from then on')
eq(R.apply(old, { engine = false }), true, 'and back') eq(R.extra(old, DISPEL), 0, 'back to nothing')

-- a bad answer changes nothing and breaks nothing
local bad = R.newState()
R.apply(bad, { engine = true, counts = { ['2261'] = 4 } })
eq(R.apply(bad, nil), false, 'nil') eq(R.apply(bad, 'x'), false, 'text') eq(R.extra(bad, DISPEL), 4, 'the old state stays')
R.apply(bad, { engine = true, counts = { ['x'] = 4, ['0'] = 4, ['2261'] = -1, ['2265'] = 'many', ['2273'] = 2.9 } })
eq(R.extra(bad, DISPEL), 0, 'a negative count is dropped') eq(R.extra(bad, MENDING), 0, 'a text count is dropped')
eq(R.extra(bad, 2273), 2, 'a fraction is floored') eq(R.extra(bad, 0), 0, 'id 0 is dropped')
eq(R.apply(bad, { engine = true, counts = 'no' }), true, 'counts that are no table: emptied') eq(R.extra(bad, 2273), 0, 'nothing left')
eq(R.pollMs({ poll = 0 }), 1000, 'poll at least 1 s') eq(R.pollMs({ poll = 9999 }), 60000, 'poll at most 60 s')
local p = R.newState() R.apply(p, { engine = true, poll = 'soon' }) eq(R.pollMs(p), 15000, 'a bad poll is the default')

-- the bag is open in the client: its runes are in the client's count already, only the rest is added
local open = { { inPurseBag = true, items = { { id = DISPEL, count = 12 }, { id = MENDING, count = 3 } } } }
local function seen(id) return R.openSeen(open, id) end
eq(R.openSeen(open, DISPEL), 12, 'seen in the open bag')
eq(R.extra(st, DISPEL, seen), 0, 'the bag is open (and one rune short in the answer): nothing is counted twice')
R.apply(st, { engine = true, bag = true, poll = 2, counts = { ['2261'] = 12, ['2265'] = 3 } })
eq(R.extra(st, DISPEL, seen), 0, 'the bag is open: all 12 are seen, none added')
open[1].items[1].count = 9
eq(R.extra(st, DISPEL, seen), 3, 'the open bag shows 9 of 12 (a stale window): 3 added')
-- an open bag that is not the purse's (a Rune Bag in the backpack) is the client's own count, not ours
open = { { inPurseBag = false, items = { { id = DISPEL, count = 12 } } } }
eq(R.extra(st, DISPEL, seen), 12, 'a bag of the backpack open: the purse bag still adds its 12')
eq(R.openSeen(nil, DISPEL), 0, 'no containers') eq(R.openSeen({ { inPurseBag = true } }, DISPEL), 0, 'a bag with no items')
eq(R.openSeen({ { inPurseBag = true, items = { { id = DISPEL } } } }, DISPEL), 1, 'a stack with no count is one')

-- the wrapped count: the engine's count first, then the extra; an old engine is untouched
local calls = 0
local function original(self, id, tier) calls = calls + 1 return id == DISPEL and 5 or 0 end
local fresh = R.newState()
local wrapped = R.wrap(original, fresh, nil)
eq(wrapped('me', DISPEL, 0), 5, 'engine = false: the plain count') eq(calls, 1, 'the original is called once')
R.apply(fresh, { engine = true, counts = { ['2261'] = 12 } })
eq(wrapped('me', DISPEL, 0), 17, 'carried 5 plus 12 in the purse bag')
eq(wrapped('me', MENDING, 0), 0, 'a rune the bag does not hold: the plain count')
eq(wrapped('me', nil), 0, 'no id: the plain count')
local boom = R.wrap(original, fresh, function() error('no containers') end)
eq(boom('me', DISPEL, 0), 5, 'a failure in the extra gives the plain count, never an error')
R.reset(fresh)
eq(wrapped('me', DISPEL, 0), 5, 'reset in place: the same wrapped function counts nothing again')
eq(fresh.poll, 15, 'reset: the slow poll')
local nilOriginal = R.wrap(function() return nil end, fresh, nil)
eq(nilOriginal('me', DISPEL), nil, 'a nil count passes through')

print('runebagcount_test: ' .. n .. ' checks OK')
