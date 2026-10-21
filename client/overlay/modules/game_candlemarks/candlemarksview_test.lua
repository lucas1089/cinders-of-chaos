-- Self test of candlemarksview.lua (no client needed). Run from the repository root (CI runs it with luajit and lua5.3):
--   luajit client/overlay/modules/game_candlemarks/candlemarksview_test.lua
local here = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(here .. 'candlemarksview.lua')
local V = CandlemarksView

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format('FAIL %s: got %q, want %q', what, tostring(got), tostring(want)))
  end
end
local function ok(cond, what) eq(cond and true or false, true, what) end
local P = V.plain

-- the counter
local c = V.counter({ b = 12, p = 600, n = 1800, e = true }, 0)
eq(c.balance, 12, 'balance')
eq(c.left, 1200, 'seconds to the next coin')
eq(P(V.counterText(c)), '12 Candlemarks, next in 20 min', 'counter text')
c = V.counter({ b = 12, p = 600, n = 1800, e = true }, 300)
eq(c.left, 900, 'the client counts down while earning')
c = V.counter({ b = 12, p = 600, n = 1800, e = true }, 99999)
eq(c.left, 0, 'never below 0')
c = V.counter({ b = 3, p = 600, n = 1800, e = false, w = 'ip' }, 300)
eq(c.left, 1200, 'paused: no countdown')
eq(P(V.counterText(c)), '3 Candlemarks (paused)', 'paused text')
ok(P(V.counterTooltip(c)):find('logs out', 1, true) ~= nil, 'the IP reason explained')
eq(P(V.counterTooltip(V.counter({ e = false, w = 'weird' }))), 'Not earning right now. Your progress is kept.', 'unknown reason')
eq(V.minutes(30), 1, 'minutes round up')
eq(V.minutes(0), 0, 'zero minutes')
c = V.counter({ b = 0 / 0, p = 'x', n = -5, e = 'yes' }, 0 / 0)
eq(c.balance, 0, 'garbage balance')
eq(c.earning, false, 'only true is earning')
c = V.counter(nil, nil)
eq(c.balance, 0, 'nil hud')
c = V.counter({ balance = 7, progress = 0, block = 1800, earning = true }, 0)
eq(c.balance, 7, 'a state works as a hud')

-- offers
local state = { balance = 10, level = 60, weekEnds = 3 * 86400 + 5, progress = 0, block = 1800, earning = true, offers = {
  { k = 'orb_tempering', n = 'Orb of Tempering', d = 'Rolls again.', p = 8, w = 5, u = 0, l = 40, c = 12251, kind = 'item' },
  { k = 'orb_grafting', n = 'Orb of Grafting', d = 'Rare.', p = 30, w = 1, u = 0, l = 100, c = 9855 },
  { k = 'whetstone', n = '2 Whetstones', d = '', p = 8, w = 5, u = 5, l = 40, c = 0 },
  { k = 'pocket_charge.rotking', n = 'Pocket Boss Charge', b = 'The Rot King', d = 'One charge.', p = 15, w = 3, u = 0, l = 50, c = 70000 },
  'bad', { n = 'no key' }, { k = string.rep('x', 200) },
} }
local rows = V.offers(state)
eq(#rows, 4, 'four valid offers, bad ones skipped')
eq(rows[1].canBuy, true, 'affordable')
eq(P(rows[2].why), 'Level 100', 'level gate shown')
eq(P(rows[3].why), 'Weekly limit reached', 'weekly limit shown')
eq(P(rows[4].why), 'Not enough Candlemarks', 'balance shown')
eq(rows[4].cid, 0, 'a client id out of range is dropped')
local lines = V.offerLines(rows[4])
eq(P(lines.title), 'Pocket Boss Charge: The Rot King', 'boss in the title')
eq(lines.title[1], '%s', 'a title is a value, not a tr() key')
eq(P(lines.price), '15 Candlemarks', 'price line')
eq(P(V.offerLines(rows[3]).limit), 'This week: 5 of 5', 'limit line')
eq(#V.offers('garbage'), 0, 'garbage state')
eq(#V.offers({ offers = 'x' }), 0, 'garbage offers')

-- owned and far from Osric
local far = { balance = 500, level = 200, near = false, offers = {
  { k = 'orb_tempering', n = 'Orb of Tempering', p = 8, w = 5, u = 0, l = 40 },
  { k = 'cos_tallow', n = 'Tallow Labels', p = 100, w = 1, u = 0, l = 1, kind = 'cosmetic', own = true },
} }
local fr = V.offers(far)
eq(P(fr[1].why), 'Visit Osric the Chandler to buy (at the temple).', 'far from Osric: Buy off with the reason')
eq(fr[1].canBuy, false, 'far: cannot buy')
eq(P(fr[2].why), 'Owned', 'an owned cosmetic says so first')
eq(P(V.header(far, 0).shop), 'Visit Osric the Chandler to buy (at the temple).', 'header: where to buy')
far.near = true
eq(V.offers(far)[1].canBuy, true, 'near Osric: Buy on')
eq(P(V.header(far, 0).shop), 'Osric the Chandler is here: you can buy.', 'header: near')

-- header
local h = V.header(state, 0)
eq(P(h.balance), 'Your account has 10 Candlemarks', 'header balance')
eq(P(h.next), 'Next Candlemark in 30 min', 'header next')
eq(P(h.week), 'Weekly limits reset in 3 days', 'header week')
eq(P(V.header({ weekEnds = 100 }, 0).week), 'Weekly limits reset within a day', 'within a day')

-- every pattern given to tr() is listed and has a pt-BR entry
do
  local listed = {}
  for _, p in ipairs(V.PATTERNS) do listed[p] = true end
  local function seen(t, what)
    if type(t) == 'table' and t[1] ~= '%s' and t[1] ~= '' then ok(listed[t[1]], what .. ': ' .. tostring(t[1]) .. ' listed') end
  end
  for _, hh in ipairs({ { e = true }, { e = false, w = 'ip' }, { e = false, w = 'staff' }, { e = false, w = 'level' }, { e = false } }) do
    local cc = V.counter(hh, 0)
    seen(V.counterText(cc), 'counter'); seen(V.counterTooltip(cc), 'tooltip')
    local hd = V.header(hh, 0)
    seen(hd.balance, 'balance'); seen(hd.next, 'next'); seen(hd.week, 'week'); seen(hd.shop, 'shop')
  end
  seen(V.header({ weekEnds = 900000 }, 0).week, 'week days')
  for _, r in ipairs(fr) do seen(r.why, 'why far') end
  seen(V.header({ near = false }, 0).shop, 'shop far')
  for _, r in ipairs(rows) do
    local l = V.offerLines(r)
    seen(l.price, 'price'); seen(l.limit, 'limit'); seen(r.why, 'why')
  end
  local f = io.open(here .. '../client_chaos_locale/pt_br.lua')
  if f then
    local src = f:read('*a')
    f:close()
    local env = {}
    local chunk = (loadstring or load)(src)
    ChaosLocaleStrings = nil
    local okL, pt = pcall(chunk)
    ok(okL and type(pt) == 'table', 'pt_br.lua loads')
    for _, p in ipairs(V.PATTERNS) do ok(pt and pt[p] ~= nil, 'pt-BR for ' .. p) end
  end
end

-- the opcode is the server's
local c2 = io.open(here .. '../../../../server/data/scripts/chaos/chaos_constants.lua')
if c2 then
  local consts = c2:read('*a')
  c2:close()
  ok(consts:find('ChaosOpcodes.candlemarks = 176', 1, true) ~= nil, 'server opcode 176')
  local m = io.open(here .. 'candlemarks.lua')
  local mod = m and m:read('*a') or ''
  if m then m:close() end
  ok(mod:find('local OPCODE = 176', 1, true) ~= nil, 'client opcode 176')
end

print(string.format('candlemarksview_test: %d checks, %d failures', checks, failures))
if failures > 0 then os.exit(1) end
