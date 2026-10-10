-- luajit passview_test.lua && lua5.3 passview_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'passview.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local V = PassView

local set = V.claimedSet('0110')
eq(set[1], nil, 'claimed set 1')
eq(set[2], true, 'claimed set 2')
eq(set[3], true, 'claimed set 3')
eq(next(V.claimedSet(nil)), nil, 'claimed set nil')

local state = { tier = 3, maxTier = 5, premium = false, season = { status = 'active' }, claimed = { '10000', '00000' } }
eq(V.cellState(state, 1, V.FREE), 'claimed', 'claimed free 1')
eq(V.cellState(state, 2, V.FREE), 'claimable', 'claimable free 2')
eq(V.cellState(state, 4, V.FREE), 'locked', 'locked free 4')
eq(V.cellState(state, 2, V.PREMIUM), 'premium', 'premium needed')
eq(V.claimableCount(state), 2, 'two free to claim')
state.premium = true
eq(V.cellState(state, 2, V.PREMIUM), 'claimable', 'premium claimable')
eq(V.claimableCount(state), 5, 'two free and three premium')
state.season.status = 'grace'
eq(V.cellState(state, 2, V.FREE), 'claimable', 'claimable in the grace')
state.season.status = 'ended'
eq(V.cellState(state, 2, V.FREE), 'closed', 'closed after the grace')
eq(V.claimableCount(state), 0, 'nothing after the grace')
eq(V.claimableCount({}), 0, 'empty state')

eq(V.formatTime(93784), '1d 02h 03m', 'days')
eq(V.formatTime(3725), '1h 02m 05s', 'hours')
eq(V.formatTime(-4), '0h 00m 00s', 'negative')
eq(V.formatTime(nil), '0h 00m 00s', 'nil')
eq(V.left(100, 10, 15), 95, 'left counts down')
eq(V.left(3, 10, 20), 0, 'left never negative')

local pct, text = V.progress({ tier = 2, maxTier = 50, into = 512, need = 1050 })
eq(pct, 48, 'progress percent')
eq(text, '512 / 1050 XP to tier 3', 'progress text')
pct, text = V.progress({ tier = 50, maxTier = 50, into = 0, need = 0 })
eq(pct, 100, 'max percent')
eq(text, 'Max tier reached', 'max text')

local b, on = V.offerButton({ price = 600, full = 600 })
eq(b, 'Buy 600', 'buy')
eq(on, true, 'buy enabled')
b, on = V.offerButton({ price = 200, full = 1800 })
eq(b, 'Upgrade 200', 'upgrade')
b, on = V.offerButton({ owned = true, price = 1 })
eq(b, 'Owned', 'owned')
eq(on, false, 'owned disabled')
b, on = V.offerButton({ why = 'Only while the season runs.' })
eq(b, 'Unavailable', 'unavailable')
eq(on, false, 'unavailable disabled')

eq(V.sourceLine({ name = 'Experience', today = 120.7, cap = 300 }), 'Experience 120 / 300', 'source line')
local ct, cp, cpct = V.challenge({ text = 'Slay 300 monsters', progress = 150, target = 300 })
eq(cp, '150 / 300', 'challenge progress')
eq(cpct, 50, 'challenge percent')
ct, cp, cpct = V.challenge({ text = 'x', progress = 3, target = 3, done = true })
eq(cp, 'Done', 'challenge done')
eq(cpct, 100, 'challenge done percent')

local cache, complete = V.mergeTiers(nil, { season = 1, total = 3, rows = { { tier = 1 }, { tier = 2 } } })
eq(complete, false, 'two of three tiers')
cache, complete = V.mergeTiers(cache, { season = 1, total = 3, rows = { { tier = 3 } } })
eq(complete, true, 'all tiers')
cache, complete = V.mergeTiers(cache, { season = 2, total = 1, rows = {} })
eq(complete, false, 'a new season starts over')
eq(cache.season, 2, 'new season cache')

if fails > 0 then error(fails .. ' failure(s)') end
print('passview_test: OK')
