-- luajit waystoneegview_test.lua && lua5.3 waystoneegview_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'waystoneegview.lua')
local fails, checks = 0, 0
local function ok(c, what)
  checks = checks + 1
  if not c then print('FAIL ' .. what); fails = fails + 1 end
end
local function eq(a, b, what) ok(a == b, what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)) end
local E = WaystoneEgView

-- the server's payload (waystone_endgame.lua E.payload): 25 tiers from level 1100, tiers 12 and 25 paid
local levels, paid = {}, {}
for t = 1, 25 do levels[t] = 1000 + 100 * t; paid[t] = (t == 12 or t == 25) and 1 or 0 end
local payload = {
  points = 2, spent = 1, free = 1, respec = 500000, msg = 'Rank bought.', deepFrom = 16, levels = levels, paid = paid,
  stats = {
    { key = 'density', rank = 1, max = 5, per = 6, text = '+6% ...' },
    { key = 'bossChance', rank = 0, max = 5, per = 8, text = '+0% ...' },
    { key = 'chestChance', rank = 5, max = 5, per = 6, text = '+30% ...' },
    { key = 'fragmentChance', rank = 0, max = 5, per = 4, text = '+0% ...' },
  },
  bosses = { { tier = 25, name = 'Vharkul the Embered Tyrant' }, { tier = 5, name = 'Gravewatch Ulrim' },
    { tier = 10, name = 'Sister Morvane of Cinders' }, { tier = 15, name = 'The Hollow Colossus' } },
}
local m = E.parse(payload)
eq(m.points, 2, 'points')
eq(m.free, 1, 'free')
eq(#m.stats, 4, 'four stats')
eq(E.pointsLine(m), '1', 'points to spend')
eq(E.rankText(m.stats[1]), '1 / 5', 'rank text')
eq(E.nowText(m.stats[1]), 'Now: +6%', 'effect now')
eq(E.nowText(m.stats[3]), 'Now: +30%', 'effect of a full stat')

-- spend rules
eq(E.canSpend(m, 'density'), true, 'a point and a free rank')
eq(select(2, E.canSpend(m, 'chestChance')), 'maxed', 'top rank')
eq(select(2, E.canSpend(m, 'nope')), 'unknown', 'unknown key')
local none = E.parse({ points = 1, spent = 1, free = 0, stats = payload.stats })
eq(select(2, E.canSpend(none, 'density')), 'points', 'no point left')
eq(E.reasonText('points'), 'You have no atlas point to spend.', 'reason: points')
eq(E.reasonText('maxed'), 'That stat is at its top rank.', 'reason: maxed')
eq(E.reasonText('unknown'), 'No such stat.', 'reason: unknown')
eq(E.canReset(m), true, 'reset with ranks')
eq(E.canReset(E.parse({ spent = 0 })), false, 'nothing to reset')
eq(E.resetText(m), 'Reset ranks (500k gold)', 'reset button')
eq(E.resetConfirm(m), 'Refund every rank of your endgame atlas for 500k gold?', 'reset confirmation')

-- the deep tiers
local rows = E.deepRows(m)
eq(#rows, 10, 'ten deep tiers')
eq(rows[1].roman, 'XVI', 'first deep tier')
eq(rows[1].level, 2600, 'its level')
eq(rows[10].roman, 'XXV', 'last deep tier')
eq(rows[10].level, 3500, 'its level')
eq(rows[10].paid, true, 'tier XXV paid')
eq(rows[1].paid, false, 'tier XVI open')
eq(select(1, E.deepCount(m)), 1, 'one deep first clear (tier 12 is not deep)')
eq(select(2, E.deepCount(m)), 10, 'of ten')
eq(E.tierLine(rows[1]), 'Tier XVI  level 2600', 'tier line')
eq(E.tierStatus(rows[10]), 'First clear done', 'status done')
eq(E.tierStatus(rows[1]), 'First clear open', 'status open')
eq(E.earnedLine(m), '2 first clears, 1 points spent', 'earned line')

-- the band bosses: sorted by tier, with the tier's level
local b = E.bossRows(m)
eq(#b, 4, 'four band bosses')
eq(b[1].name, 'Gravewatch Ulrim', 'sorted: first')
eq(b[4].name, 'Vharkul the Embered Tyrant', 'sorted: last')
eq(b[4].level, 3500, 'boss level')
eq(E.bossLine(b[4]), 'Vharkul the Embered Tyrant (tier XXV, level 3500)', 'boss line')

-- defaults for an old or empty payload
local empty = E.parse(nil)
eq(#E.deepRows(empty), 10, 'default tiers when the server sends no levels')
eq(E.deepRows(empty)[1].level, 2600, 'default level of tier XVI')
eq(#E.bossRows(empty), 0, 'no bosses')
local junk = E.parse({ stats = { 5, { key = 3 }, { key = 'density' } }, paid = 'x', bosses = { 'x', {} }, points = 'many' })
eq(#junk.stats, 1, 'junk stats dropped')
eq(junk.stats[1].max, 1, 'max floor')
eq(junk.points, 0, 'junk points')

-- words
eq(E.statName('density'), 'Density', 'stat name')
eq(E.statName('mystery', 'Odd'), 'Odd', 'unknown name falls back')
ok(E.statDescription(m.stats[1]):find('6%%'), 'description names the per rank value')
eq(E.statDescription({ key = 'mystery', text = 'raw' }), 'raw', 'unknown description is the server text')
eq(E.toggleText(true), 'Back to map', 'toggle on')
eq(E.toggleText(false), 'Endgame', 'toggle off')
eq(E.roman(25), 'XXV', 'roman 25')
eq(E.roman(40), '40', 'roman beyond')

print(string.format('waystoneegview_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
