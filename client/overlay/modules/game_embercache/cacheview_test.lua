-- Self test of cacheview.lua (no client needed). Run from the repository root (CI runs it with luajit and lua5.3):
--   luajit client/overlay/modules/game_embercache/cacheview_test.lua
local here = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(here .. 'cacheview.lua')
local V = CacheView

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

-- numbers and times
eq(V.short(999), '999', 'short small'); eq(V.short(1234), '1.2k', 'short k'); eq(V.short(1000000), '1M', 'short M')
eq(V.short(2500000000), '2.5B', 'short B'); eq(V.short(-5), '0', 'short negative'); eq(V.short(0 / 0), '0', 'short NaN')
eq(P(V.duration(3700)), '1 h 1 min', 'duration h'); eq(P(V.duration(59)), '0 min', 'duration min')
eq(P(V.left(2 * 86400)), '2 days', 'left days'); eq(P(V.left(86400)), '1 day', 'left day')
eq(P(V.left(7200)), '2 h', 'left h'); eq(P(V.left(10)), 'under an hour', 'left under')
eq(P(V.reward(12000, { { 1, 2, 'Orb of Upheaval' }, { 2, 1, 'Orb of Fate' } })), '12k gold, 2x Orb of Upheaval, Orb of Fate',
  'reward')
eq(P(V.reward(500, {})), '500 gold', 'reward gold only')
eq(V.reward(500, { 'bad', { 1, 1, 5 } })[1], '%s gold', 'bad item rows skipped')

-- sources
local src = V.sources({ { 'kill', 1, 20, 60, 12 }, { 'dungeon', 12, 1, 0, 0 }, { 'craft', 1, 1, 15, 3 }, { 'nope', 1, 1, 0, 0 },
  'bad' })
eq(#src, 3, 'unknown and bad rows skipped')
eq(P(src[1].pts), '20 for 1 point', 'kills per point'); eq(P(src[1].cap), 'at most 60 a day (12 today)', 'cap')
eq(P(src[2].pts), '12 points', 'points'); eq(src[2].cap, nil, 'no cap'); eq(P(src[3].pts), '1 point', 'one point')
eq(src[1].label[1], 'Monster kills', 'label is a key')

-- the whole state
local state = {
  week = { pts = 150, got = 1, sparks = 2, ends = 3 * 86400,
    tiers = { { p = 120, g = 10000, it = { { 1, 2, 'Orb of Upheaval' } } }, { p = 300, g = 20000, it = {} } } },
  day = { pts = 26, raw = 13, bonus = 27, goal = 30, spark = 0, ends = 100, g = 3000, it = { { 5, 1, 'Orb of Awakening' } } },
  src = { { 'rift', 12, 1, 0, 0 } },
  book = { xp = 1234567, lv = 2, kills = 300, loot = 5000, sup = 7000, orbs = 3, uniq = 1, rares = 4, deaths = 1, secs = 1800,
    pts = 26 }
}
local v = V.build(state)
eq(P(v.week), 'This week: 150 Ember points', 'week')
eq(#v.tiers, 2, 'tiers'); ok(v.tiers[1].reached, 'first reached'); eq(P(v.tiers[1].status), 'reached', 'reached text')
eq(P(v.tiers[2].status), '150 to go', 'to go'); eq(v.tiers[2].color, V.OPEN, 'open colour')
eq(P(v.tiers[1].title), 'Milestone 1: 120 points', 'tier title')
eq(P(v.spark), 'Daily Spark at 30 points: 4 to go', 'spark to go')
eq(P(v.bonus), 'Your next 27 points today count double.', 'bonus')
eq(P(v.book[1][2]), '1.2M', 'xp'); eq(P(v.book[6][2]), '-2k', 'profit negative'); eq(P(v.book[9][2]), '30 min', 'time')
eq(P(v.book[7][2]), '3 / 1 / 4', 'drops')
state.day.spark = 1; state.day.bonus = 0
v = V.build(state)
eq(P(v.spark), 'Daily Spark lit', 'spark lit'); eq(v.sparkColor, V.REACHED, 'lit colour')
eq(P(v.bonus), 'Double points used up today.', 'bonus used')

-- the junk orb offering (server embercache.lua E.offerQuote)
src = V.sources({ { 'offering', 1, 10, 60, 17 } })
eq(src[1].label[1], 'Junk orbs offered (the button below)', 'offering label')
eq(P(src[1].pts), '10 for 1 point', 'offering rate'); eq(P(src[1].cap), 'at most 60 a day (17 today)', 'offering cap')
local o = V.offer({ orbs = 600, points = 60, room = 60, per = 10, carried = 2000 })
ok(o.can, 'an offer to confirm')
eq(P(o.text), 'Offer 600 junk orbs for 60 Ember points? They are destroyed. (10 orbs a point, 60 points left today)',
  'offer text')
o = V.offer({ orbs = 0, points = 0, room = 60, per = 10, carried = 7 })
ok(not o.can, 'nothing to offer'); eq(P(o.text), 'You carry 7 junk orbs: at least 10 make an Ember point (locked orbs do not count).', 'too few')
o = V.offer({ orbs = 0, points = 0, room = 0, per = 10, carried = 500 })
ok(not o.can, 'day full'); eq(P(o.text), 'The Ember Cache takes no more junk orbs today. More tomorrow.', 'day full text')
o = V.offer('bad'); ok(not o.can, 'garbage: nothing to offer')

-- garbage never errors
v = V.build(nil); eq(#v.tiers, 0, 'nil state'); eq(P(v.week), 'This week: 0 Ember points', 'nil week')
v = V.build({ week = 'x', day = 5, book = {}, src = 'y' }); eq(#v.sources, 0, 'bad shapes')
v = V.build({ week = { tiers = { 'bad', { p = 'x' } } } }); eq(#v.tiers, 2, 'bad tiers drawn as zero')

print(string.format('cacheview_test: %d checks, %d failures', checks, failures))
if failures > 0 then os.exit(1) end
