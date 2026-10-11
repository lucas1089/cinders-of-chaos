-- luajit guildwarview_test.lua && lua5.3 guildwarview_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'guildwarview.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local V = GuildWarView
local opts = { stakeMin = 100000, stakeMax = 500000000, fee = 10 }

eq(V.money(1500000), '1,500,000', 'money')
eq(V.duration(3700), '1h 1m', 'duration')
eq(V.clock(421), '7:01', 'clock')
eq(V.hoursText(6), '6 hours', 'hours')
eq(V.hoursText(24), '1 day', 'one day')
eq(V.hoursText(168), '7 days', 'days')
eq(V.parseAmount('500k'), 500000, 'parse k')
eq(V.parseAmount(''), 0, 'empty is no stake')
eq(V.parseAmount('x'), nil, 'parse bad')
eq(V.winnings(500000, 10), 900000, 'winnings')
eq(V.stakeText(0, 10), 'no stake', 'no stake')
eq(V.stakeText(500000, 10), '500,000 gold per side (the winner gets 900,000)', 'stake text')

-- the declaration form
local req, why = V.declareRequest({ target = '  Iron Crows ', fragLimit = 25, hours = 24, stake = '1m' }, opts)
eq(req.target, 'Iron Crows', 'target trimmed')
eq(req.stake, 1000000, 'stake parsed')
eq(V.declareSummary(req, opts), 'War on Iron Crows: first to 25 counted kills within 24 hours, 1,000,000 gold per side (the winner gets 1,800,000).', 'summary')
req, why = V.declareRequest({ target = '', fragLimit = 25, hours = 24, stake = '' }, opts)
eq(req, nil, 'no target')
req, why = V.declareRequest({ target = 'X', fragLimit = 25, hours = 24, stake = '50k' }, opts)
eq(why, 'A stake is at least 100,000 gold (or none).', 'stake under the minimum')
req, why = V.declareRequest({ target = 'X', fragLimit = 25, hours = 24, stake = '9999m' }, opts)
eq(why, 'A stake is at most 500,000,000 gold.', 'stake over the maximum')
req = V.declareRequest({ target = 'X', fragLimit = 25, hours = 24, stake = 'abc' }, opts)
eq(req, nil, 'stake not a number')
req = V.declareRequest({ target = 'X', fragLimit = nil, hours = 24, stake = '' }, opts)
eq(req, nil, 'no frag limit')

-- war rows
local pend = { status = 'pending', own = 'Iron Crows', enemy = 'Ashen Wolves', incoming = true, left = 7200 }
eq(V.title(pend), 'Iron Crows vs Ashen Wolves', 'title')
eq(V.status(pend), 'Declared on you: answer within 2h 0m', 'incoming offer')
eq(V.color(pend), '#f6cf72', 'incoming colour')
pend.incoming = false
eq(V.status(pend), 'Offer sent: waiting 2h 0m for the answer', 'outgoing offer')
local act = { status = 'active', ownKills = 7, enemyKills = 3, fragLimit = 25, left = 90000 }
eq(V.status(act), '7 : 3 (first to 25), ends in 1d 1h', 'active')
eq(V.color(act), '#e05a4a', 'active colour')
local done = { status = 'ended', result = 'won', ownKills = 25, enemyKills = 11, reason = 'frag limit reached' }
eq(V.status(done), 'Won 25 : 11 - frag limit reached', 'won')
eq(V.color(done), '#9fd68a', 'won colour')
eq(V.status({ status = 'declined', result = 'declined' }), 'Declined', 'declined')
eq(V.status({ status = 'cancelled', result = 'cancelled' }), 'Taken back', 'cancelled')
eq(V.boardLine({ status = 'active', own = 'A', enemy = 'B', ownKills = 3, enemyKills = 4, fragLimit = 10, left = 600 }),
  'A 3 : 4 B (first to 10, 10m left)', 'board active')
eq(V.boardLine({ status = 'ended', own = 'A', enemy = 'B', ownKills = 10, enemyKills = 4, reason = 'frag limit reached' }),
  'A 10 : 4 B - frag limit reached', 'board ended')
eq(V.killLine({ at = '11.10 12:00', killer = 'Vex', victim = 'Mira', level = 410, counted = true }),
  '11.10 12:00 Vex killed Mira (level 410)', 'kill counted')
eq(V.killLine({ at = '11.10 12:01', killer = 'Vex', victim = 'Alt', level = 120, counted = false, reason = 'same IP' }),
  '11.10 12:01 Vex killed Alt (level 120) - not counted: same IP', 'kill refused')

-- the guild boss
local b = { guild = true, fuel = 375, need = 750, attempts = 1, maxAttempts = 3, canSummon = false, reason = 'The stone holds 375 of 750 embers.' }
eq(V.fuelPercent(b), 50, 'fuel percent')
eq(V.fuelText(b), '375 / 750 embers (50%)', 'fuel text')
eq((V.bossState(b)), 'The stone holds 375 of 750 embers.', 'not ready')
eq(V.attemptsText(b), 'Summons this week: 1 of 3', 'attempts')
b.canSummon = true
eq((V.bossState(b)), 'The stone is full: summon the guild boss.', 'ready')
b.killed, b.bestSeconds, b.resetIn = true, 421, 90000
eq((V.bossState(b)), 'Slain this week in 7:01. The stone rests until the reset (1d 1h).', 'killed')
eq((V.bossState({})), 'Join a guild to fight the guild boss.', 'no guild')
eq(V.fuelPercent({ fuel = 9000, need = 750 }), 100, 'percent capped')
eq(V.fuelPercent({ need = 0 }), 0, 'no need')
eq(V.bannerText({ tier = 1, name = 'Ember Banner', kills = 1, next = 4 }), 'Ember Banner (1 kill), next tier at 4', 'banner one kill')
eq(V.bannerText({ tier = 0 }), 'No guild banner yet: the first kill raises the Ember Banner.', 'no banner')
eq(V.bannerText({ tier = 2, name = 'Cinder Banner', kills = 5, next = 10 }), 'Cinder Banner (5 kills), next tier at 10', 'banner')
eq(V.goldEmbers('1.5m', 10000), 150, 'gold embers')
eq(V.goldEmbers('bad', 10000), 0, 'gold embers bad')
eq(V.bossBoardLine({ rank = 1, name = 'Iron Crows', killed = true, seconds = 400, players = 9 }), '1. Iron Crows - slain in 6:40 by 9', 'board kill')
eq(V.bossBoardLine({ rank = 2, name = 'Ashen Wolves', damage = 1234567 }), '2. Ashen Wolves - 1,234,567 damage', 'board damage')
eq(V.contributorLine({ name = 'Vex', embers = 300, gold = 3000000 }), 'Vex: 300 embers (3,000,000 gold)', 'contributor')
eq(V.spoilsLine({ name = 'Vex', gold = 2250000 }, 7500000), 'Vex: 2,250,000 gold (30%)', 'spoils share')
eq(V.spoilsLine({ name = 'Ida', gold = 5 }, 0), 'Ida: 5 gold (0%)', 'spoils without a pool')

if fails > 0 then os.exit(1) end
print('guildwarview tests OK')
