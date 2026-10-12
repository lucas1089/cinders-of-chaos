-- luajit communityview_test.lua && lua5.3 communityview_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'communityview.lua')
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local V = CommunityView

eq(V.fmt(1500000), '1,500,000', 'thousands')
eq(V.fmt(4.0), '4', 'float input')
eq(V.fmt(nil), '0', 'nil')
eq(V.countdown(93784), '1d 2h', 'days')
eq(V.countdown(4980), '1h 23m', 'hours')
eq(V.countdown(5), '1m', 'never 0m')
eq(V.left(100, 30), 70, 'counted down')
eq(V.left(100, 300), 0, 'never below 0')

-- a payload shaped like the server's (community_core.lua C.payload)
local data = {
  now = 0,
  goal = { n = 'Fuel the Brazier', d = 'Everything feeds it.', period = 20261005, left = 86400 + 7200, target = 1500000,
    p = 912345, pct = 60.8, realm = 0 },
  stages = {
    { i = 1, pct = 25, key = 'kindled', n = 'Kindled Brazier', d = '+10% experience from monsters', h = 24, done = true, left = 3600 },
    { i = 2, pct = 50, key = 'bounty', n = 'Ashen Bounty', d = '+10% Chaos loot quantity', h = 24, done = true },
    { i = 3, pct = 75, key = 'beacon', n = 'Rift Beacon', d = '+5% Rift Key chance', h = 24 },
    { i = 4, pct = 100, key = 'ablaze', n = 'Brazier Ablaze', d = '+20% reputation', h = 48 },
  },
  sources = { { k = 'kill', n = 'Monsters slain', cap = 4000, mine = 1000 }, { k = 'orb', n = 'Crafting orbs used', cap = 1500, mine = 0 } },
  mine = { p = 1018, today = 150, cap = 12000, rank = 2, token = 1500, tokenText = '2 Orbs of Upheaval', title = 'Keeper of the Flame', top = 3 },
  top = { { n = 'Bryn', p = 4000 }, { n = 'Hero', p = 1018 } },
  week = { mods = { { k = 'restless_dead', n = 'Restless Dead', d = 'Undead give 30% more.' } }, left = 7200 },
  brazier = { near = true, min = 1000, max = 10000000, gold = 2000000, per = 1000, room = 5000000 },
}
eq(V.barPercent(data), 60, 'bar percent')
eq(V.barText(data), '912,345 / 1,500,000  (60.8%)', 'bar text')
eq(V.barText({ goal = { p = 0, target = 10, pct = 0 } }), '0 / 10  (0%)', 'bar text at 0')
eq(V.barPercent({}), 0, 'no data')
eq(V.markerX(50, 400, 10), 195, 'marker centred')
eq(V.markerX(100, 400, 10), 390, 'marker kept inside')
eq(V.markerX(0, 400, 10), 0, 'marker at 0')
eq(V.stageState(data.stages[1], 0), 'open', 'stage 1 window open')
eq(V.stageState(data.stages[1], 4000), 'done', 'stage 1 window over after the countdown')
eq(V.stageState(data.stages[2], 0), 'done', 'stage 2 reached')
eq(V.stageState(data.stages[3], 0), 'todo', 'stage 3 ahead')
local line, color = V.stageLine(data.stages[1], 0)
eq(line, 'Active: 1h 00m left', 'open line')
eq(color, V.COLORS.open, 'open colour')
eq((V.stageLine(data.stages[3], 0)), 'At 75%', 'todo line')
eq((V.stageLine(data.stages[2], 0)), 'Reached at 50%', 'done line')
eq(V.stageShort(data.stages[1]), '+10% experience from monsters', 'chip line without a short text')
eq(V.stageShort({ pct = 50, s = '+10% loot', d = 'long' }), '+10% loot', 'chip line: the short text')
eq(V.stageTooltip(data.stages[4]), 'Brazier Ablaze (100%)\n+20% reputation for everyone online, 48 hours.', 'tooltip')
eq(V.mineText(data), '1,018 points (rank 2)', 'mine')
eq(V.mineText({ mine = { p = 0 } }), '0 points', 'mine without rank')
eq(V.todayText(data), 'Today: 150 / 12,000', 'today')
eq(V.rewardText(data), 'Top 3: the title Keeper of the Flame.\n1,500 points: 2 Orbs of Upheaval', 'rewards')
data.mine.p = 1600
eq(V.rewardText(data):find('(earned)', 1, true) ~= nil, true, 'token earned')
local rows = V.sourceRows(data)
eq(#rows, 2, 'source rows')
eq(rows[1].text, '1,000 / 4,000', 'source text')
eq(rows[1].pct, 25, 'source percent')
local top = V.topRows(data)
eq(top[1].name .. top[1].text .. top[2].place, 'Bryn4,0002', 'top rows')
eq(V.modIcon('restless_dead'), '/images/game/buffs/wmod_restless_dead', 'modifier icon')
eq(V.modIcon('../x'), '/images/game/buffs/wmod_week', 'bad key: the generic icon')
eq(V.stageIcon('kindled'), '/images/game/buffs/community_kindled', 'stage icon')
eq(V.weekText(data, 0), 'This week (2h 00m left)', 'week text')
eq(V.weekText({ week = { mods = {} } }, 0), 'No world modifier this week.', 'no modifiers')
data.week.staff = true
eq(V.weekText(data, 3600), 'This week (1h 00m left), set by the staff', 'staff override and countdown')
eq(V.goalTimeText(data, 0), 'Ends in 1d 2h', 'goal time')

-- the Brazier dialog
eq(V.parseGold('150k'), 150000, 'k')
eq(V.parseGold('1.5m'), 1500000, 'm')
eq(V.parseGold('2kk'), 2000000, 'kk')
eq(V.parseGold('25,000'), 25000, 'commas')
eq(V.parseGold(' 7 '), 7, 'spaces')
eq(V.parseGold('abc'), nil, 'garbage')
eq(V.parseGold('5x'), nil, 'unknown suffix')
eq(V.parseGold(''), nil, 'empty')
local g, p, why = V.donation(data, 25500)
eq(g .. '/' .. p .. '/' .. tostring(why), '25000/25/nil', 'whole thousands')
g, p, why = V.donation(data, 500)
eq(why, 'At least 1,000 gold.', 'minimum')
g, p, why = V.donation(data, 3000000)
eq(why, 'You do not have that much gold.', 'more than carried')
data.brazier.room = 4000
g = V.donation(data, 100000)
eq(g, 4000, 'today\'s room')
data.brazier.room = 0
g, p, why = V.donation(data, 100000)
eq(why, 'The Brazier takes no more from you today.', 'no room')
data.brazier.room = 5000000
local text, ok = V.donateState(data, '100k')
eq(text, 'Give 100,000 gold for 100 points.', 'preview')
eq(ok, true, 'button on')
text, ok = V.donateState(data, 'x')
eq(ok, false, 'bad text: button off')
data.brazier.near = false
text, ok = V.donateState(data, '100k')
eq(ok, false, 'too far: button off')
eq(text, 'Stand next to the Great Brazier in the temple.', 'too far text')
local q = V.quickAmounts(data)
eq(#q, 3, 'three quick amounts')
eq(V.short(q[1]) .. ',' .. V.short(q[2]) .. ',' .. V.short(q[3]), '10k,100k,1m', 'short amounts')

print(string.format('communityview_test: %s (%d checks)', fails == 0 and 'OK' or (fails .. ' FAILED'), checks))
if fails > 0 then os.exit(1) end
