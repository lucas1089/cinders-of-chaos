-- luajit helper_sell_test.lua && lua5.3 helper_sell_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'helper_sell.lua')
local S = ChaosHelperSell
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(S.minutesOf(30), 30, 'a listed interval')
eq(S.minutesOf('15'), 15, 'a string interval')
eq(S.minutesOf(7), nil, 'an interval not in the list')
eq(S.minutesOf(nil), nil, 'nil interval')

local cfg = { enabled = true, minutes = 10, belowCap = false, capacity = 100 }
local seller = { known = true, unlocked = true, cooldown = 0 }
local MIN = 60000
local function input(now, cap) return { now = now, freeCap = cap or 500, helperOn = true } end

-- off
local st = S.newState()
eq(S.decide({ enabled = false }, st, seller, input(0)), nil, 'off: nothing')
eq(S.decide(nil, st, seller, input(0)), nil, 'no config: nothing')
local act, why = S.decide(cfg, st, seller, { now = 0, freeCap = 500, helperOn = false })
eq(act, nil, 'the helper off: nothing')
eq(why, 'helperoff', 'the helper off: reason')

-- the state is not known yet: one sync every 10 s
st = S.newState()
eq((S.decide(cfg, st, { known = false }, input(0))), 'sync', 'unknown state: ask for it')
eq((S.decide(cfg, st, { known = false }, input(5000))), nil, 'and not again at once')
eq((S.decide(cfg, st, { known = false }, input(10000))), 'sync', 'but again after 10 s')

-- not unlocked: never sells, looks again every 5 minutes
st = S.newState()
local locked = { known = true, unlocked = false, cooldown = 0 }
eq((S.decide(cfg, st, locked, input(0))), 'sync', 'locked: look at the state once')
for t = 1, 40 do eq((S.decide(cfg, st, locked, input(t * 10000))) == 'sell', false, 'locked never sells') end

-- the timer: no sale at the very login, one after the interval, then one per interval
st = S.newState()
eq((S.decide(cfg, st, seller, input(0))), nil, 'no sale at login')
eq((S.decide(cfg, st, seller, input(5 * MIN))), nil, 'not before the interval')
local a, w = S.decide(cfg, st, seller, input(10 * MIN))
eq(a, 'sell', 'sells when the timer is out')
eq(w, 'timer', 'and says why')
eq((S.decide(cfg, st, seller, input(10 * MIN + 1000))), nil, 'not again at once')
eq((S.decide(cfg, st, seller, input(19 * MIN))), nil, 'not before the next interval')
eq((S.decide(cfg, st, seller, input(20 * MIN))), 'sell', 'the next one')

-- the server's cooldown holds a sale back
st = S.newState()
S.decide(cfg, st, seller, input(0))
local act2, why2 = S.decide(cfg, st, { known = true, unlocked = true, cooldown = 12 }, input(11 * MIN))
eq(act2, nil, 'cooldown: no ask')
eq(why2, 'cooldown', 'cooldown reason')
eq((S.decide(cfg, st, seller, input(11 * MIN + 1000))), 'sell', 'asks when the cooldown is over')

-- low capacity: sells before the timer, at most once a minute, and only when the option is on
local capCfg = { enabled = true, minutes = 60, belowCap = true, capacity = 100 }
st = S.newState()
S.decide(capCfg, st, seller, input(0, 500))
eq((S.decide(capCfg, st, seller, input(1000, 500))), nil, 'plenty of capacity: wait')
local ca, cw = S.decide(capCfg, st, seller, input(2000, 80))
eq(ca, 'sell', 'low capacity: sells')
eq(cw, 'capacity', 'low capacity reason')
eq((S.decide(capCfg, st, seller, input(3000, 80))), nil, 'not again at once')
eq((S.decide(capCfg, st, seller, input(40000, 80))), nil, 'not before the capacity gap')
eq((S.decide(capCfg, st, seller, input(2000 + S.CAP_GAP_MS, 80))), 'sell', 'after the capacity gap')
st = S.newState()
S.decide({ enabled = true, minutes = 60, belowCap = false, capacity = 100 }, st, seller, input(0, 500))
eq((S.decide({ enabled = true, minutes = 60, belowCap = false, capacity = 100 }, st, seller, input(2000, 10))), nil,
  'the capacity option off: low capacity alone does not sell')
eq((S.decide(capCfg, S.newState(), seller, { now = 0, freeCap = nil, helperOn = true })), nil, 'unknown capacity: wait')

-- never closer than the server's 30 s limit
st = S.newState()
S.decide(capCfg, st, seller, input(0, 500))
S.decide(capCfg, st, seller, input(2000, 10))
for t = 3, 30 do
  eq((S.decide(capCfg, st, seller, input(t * 1000, 10))), nil, 'no ask within the limit at ' .. t)
end

-- a bad interval falls back to 30 minutes
st = S.newState()
S.decide({ enabled = true, minutes = 7 }, st, seller, input(0))
eq((S.decide({ enabled = true, minutes = 7 }, st, seller, input(29 * MIN))), nil, 'a bad interval is 30 minutes: not at 29')
eq((S.decide({ enabled = true, minutes = 7 }, st, seller, input(30 * MIN))), 'sell', 'and sells at 30')

-- the helper never sells an item itself: the module has no engine calls at all
local f = io.open(dir .. 'helper_sell.lua', 'r')
local text = f:read('*a')
f:close()
eq(text:find('g_game', 1, true), nil, 'no g_game call in the pure file')
eq(text:find('useInventory', 1, true), nil, 'no item use in the pure file')

if fails > 0 then os.exit(1) end
print('helper_sell_test: ok')
