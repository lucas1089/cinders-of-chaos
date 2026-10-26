-- Self test of weeklyview.lua (no client needed). Run from the repository root (CI runs it with luajit and lua5.3):
--   luajit client/overlay/modules/game_weeklychest/weeklyview_test.lua
local here = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(here .. 'weeklyview.lua')
local V = WeeklyView

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format('FAIL %s: got %q, want %q', what, tostring(got), tostring(want)))
  end
end
local P = V.plain

eq(V.short(999), '999', 'short small'); eq(V.short(1234), '1.2k', 'short k'); eq(V.short(2500000000), '2.5B', 'short B')
eq(V.short(-5), '0', 'short negative'); eq(V.short(0 / 0), '0', 'short NaN'); eq(V.short(nil), '0', 'short nil')
eq(P(V.left(3 * 86400)), '3 days', 'left days'); eq(P(V.left(86400)), '1 day', 'left one day')
eq(P(V.left(86400 + 7200)), '1 day', 'left a day and hours'); eq(P(V.left(7200)), '2 h', 'left h'); eq(P(V.left(10)), 'under an hour', 'left under')
eq(P(V.reward(12000, { { cid = 1, n = 2, name = 'Orb of Upheaval' }, { cid = 2, n = 1, name = 'Orb of Fate' } })),
  '12k gold, 2x Orb of Upheaval, Orb of Fate', 'reward')
eq(P(V.reward(500, {})), '500 gold', 'reward gold only')
eq(P(V.reward(500, { 'bad', { n = 1 } })), '500 gold', 'bad item rows skipped')

local state = {
  endsIn = 3 * 86400 + 100, got = 2, need = 3, bonusNeed = 5, open = 5, chests = 4,
  acts = { { k = 'dungeon', done = 1, open = 1, lv = 100 }, { k = 'rift', done = 0, open = 1, lv = 100 },
    { k = 'waystone', done = 0, open = 0, lv = 1100 }, { k = 'weird', done = 0, open = 1, lv = 5 } },
  chest = { given = 0, gold = 1500000, it = { { cid = 5, n = 4, name = 'Orb of Upheaval' } } },
  bonus = { given = 0, lo = 800000, hi = 1200000 },
}
local v = V.build(state)
eq(P(v.head), '2 of 3 activities done this week', 'head'); eq(P(v.ends), 'The week ends in 3 days', 'ends')
eq(#v.rows, 4, 'rows'); eq(P(v.rows[1].status), 'Done', 'done'); eq(v.rows[1].color, V.DONE, 'done colour')
eq(P(v.rows[2].status), 'Not yet', 'open'); eq(P(v.rows[3].status), 'Unlocks at level 1100', 'locked'); eq(v.rows[3].color, V.LOCKED, 'locked colour')
eq(P(v.rows[4].name), 'weird', 'unknown activity named by its key')
eq(P(v.chest), 'The chest opens at 3 of 5 activities.', 'chest line'); eq(P(v.reward), '1.5M gold, 4x Orb of Upheaval', 'reward line')
eq(P(v.bonus), 'All 5 activities add a bonus roll: 800k to 1.2M gold or orbs.', 'bonus line'); eq(P(v.chests), 'Chests opened so far: 4', 'chests')
state.chest.given, state.bonus.given = 1, 1
v = V.build(state)
eq(v.chestColor, V.DONE, 'chest given'); eq(P(v.bonus), 'Bonus roll taken this week.', 'bonus given')
state.bonusNeed = 0
eq(V.build(state).bonusColor, V.LOCKED, 'no bonus at this level')
-- junk never breaks it
local j = V.build(nil)
eq(#j.rows, 0, 'no state: no rows'); eq(P(j.head), '0 of 1 activities done this week', 'no state head')
j = V.build({ acts = { 'x', { k = 5 }, {} }, chest = 'no', bonus = 7, endsIn = 'soon' })
eq(#j.rows, 0, 'junk rows skipped')
for key, info in pairs(V.ACTS) do
  eq(type(info[1]) == 'string' and type(info[2]) == 'string', true, 'activity text ' .. key)
end

if failures > 0 then
  print(failures .. ' of ' .. checks .. ' checks FAILED')
  os.exit(1)
end
print('weeklyview_test: ' .. checks .. ' checks OK')
