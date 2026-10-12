-- luajit achievementsview_test.lua && lua5.3 achievementsview_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'achievementsview.lua')
local V = AchievementsView
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local rows = {
  { i = 'a', c = 'combat', v = 50, t = 100, u = 0, n = 'A' },
  { i = 'b', c = 'combat', v = 1, t = 1, u = 200, n = 'B', ti = 'Veteran', r = '3 Orb of Upheaval' },
  { i = 'c', c = 'rifts', v = 0, t = 0, u = 0, h = 1, n = '???' },
  { i = 'd', c = 'rifts', v = 1, t = 1, u = 300, h = 1, n = 'Secret' },
}
eq(#V.filter(rows, 'all'), 4, 'all')
eq(#V.filter(rows, 'combat'), 2, 'combat')
eq(V.filter(rows, 'combat', true)[1].i, 'b', 'unlocked first')
eq(V.filter(rows, 'combat', false)[1].i, 'a', 'server order')
local recent = V.filter(rows, 'recent')
eq(#recent, 2, 'recent = unlocked'); eq(recent[1].i, 'd', 'newest first')
eq(V.percent(rows[1]), 50, 'half'); eq(V.percent(rows[2]), 100, 'done'); eq(V.percent(rows[3]), 0, 'hidden')
eq(V.progressText(rows[1]), '50 / 100', 'progress'); eq(V.progressText(rows[3]), '???', 'hidden progress')
eq(V.progressText(rows[2]), 'Unlocked', 'unlocked text')
eq(V.progressText({ v = 2500, t = 10000, u = 0 }), '2,500 / 10,000', 'grouped')
eq(V.isHiddenLocked(rows[3]), true); eq(V.isHiddenLocked(rows[4]), false, 'unlocked hidden is shown')
eq(V.extraText(rows[2]), 'Title: Veteran   -   Reward: 3 Orb of Upheaval', 'extra')
eq(V.extraText(rows[1]), '', 'no extra')
eq(V.categoryLabel({ name = 'Rifts', done = 1, total = 13 }), 'Rifts  1/13')
eq(V.summaryText({ points = 15, accountPoints = 40, unlocked = 2, total = 93 }),
  'Points: 15   -   Account: 40   -   Unlocked: 2 / 93')
eq(V.titleParam('auto'), 'auto'); eq(V.titleParam('none'), 'none')
eq(V.titleParam('Veteran'), 'Veteran')
eq(V.dateText(0), '', 'no date')
eq(V.group(1234567), '1,234,567'); eq(V.group(12), '12')

-- reward track (the server's "track" message)
local track = { ap = 640, steps = {
  { p = 100, n = 'Ashen Name', k = 'chatcolor', d = 'Pale ash.', c = '#cfc4b4', o = 1 },
  { p = 250, n = 'Chronicle Labels', k = 'lootbeam', d = 'Deep teal.', a = '#0b2626f0', o = 1 },
  { p = 500, n = 'Verdigris Splash', k = 'killfx', d = 'A green splash.' },
  { p = 1000, n = "Chronicler's Teal", k = 'chatcolor', d = 'Teal.', c = '#5cc8c0' } },
  cats = { { key = 'rifts', cn = 'Rifts', dn = 3, t = 27, ti = 'Riftwarden', n = 'Rift Sigil', k = 'killfx', d = 'A sigil.' },
    { key = 'secrets', cn = 'Secrets', dn = 4, t = 4, ti = 'Keeper of Secrets', n = 'Falling Stars', k = 'killfx', x = 1, o = 1 } } }
local nxt, prev = V.trackNext(track)
eq(nxt.p, 1000, 'next milestone'); eq(prev, 500, 'previous milestone')
eq(V.trackReached(track), 3, 'three reached')
eq(V.trackPercent(track), 28, '640 of 500..1000')
eq(V.trackText(track), "640 / 1,000 account points  -  next: Chronicler's Teal (Chat name colour)", 'bar text')
eq(V.trackPercent({ ap = 50, steps = track.steps }), 50, 'from 0 to the first')
eq(V.trackPercent({ ap = 5000, steps = track.steps }), 100, 'all reached')
eq(V.trackNext({ ap = 1000, steps = track.steps }), nil, 'exactly at the last one: done')
eq(V.trackText({ ap = 1200, steps = track.steps }), '1,200 account points  -  every reward unlocked (4)', 'done text')
eq(V.trackPercent(nil), 100, 'no track'); eq(V.trackReached(nil), 0)
local tip = V.rewardTooltip(track.steps[4], 640)
eq(tip:find("Chronicler's Teal  -  Chat name colour", 1, true) ~= nil, true, 'tooltip head')
eq(tip:find('Colour: #5cc8c0', 1, true) ~= nil, true, 'colour preview')
eq(tip:find('Unlocks at 1,000 account points (360 to go).', 1, true) ~= nil, true, 'points to go')
eq(tip:find('never sold', 1, true) ~= nil, true, 'not for sale')
eq(V.rewardTooltip(track.steps[2], 640):find('Label background: #0b2626', 1, true) ~= nil, true, 'accent preview')
eq(V.rewardTooltip(track.steps[1], 640):find('Owned', 1, true) ~= nil, true, 'owned')
eq(V.categoryReward(track, 'rifts'), 'Complete all 27: title Riftwarden + Rift Sigil (Kill effect)', 'category reward')
eq(V.categoryReward(track, 'secrets'):find('done', 1, true) ~= nil, true, 'complete category')
eq(V.categoryReward(track, 'combat'), nil, 'no reward listed'); eq(V.categoryReward(nil, 'rifts'), nil, 'no track')
local tr = V.trackRows(track)
eq(#tr, 6, 'four milestones and two categories')
eq(tr[1].done, true); eq(tr[1].progress, 'Unlocked'); eq(tr[1].color, '#cfc4b4', 'the chat colour previews itself')
eq(tr[3].done, true, '500 reached'); eq(tr[2].accent, '#0b2626f0', 'the accent previews itself')
eq(tr[4].done, false); eq(tr[4].percent, 64); eq(tr[4].progress, '640 / 1,000 account points')
eq(tr[4].right, '1,000 pts')
eq(tr[5].name, 'Rifts: Rift Sigil'); eq(tr[5].percent, 11); eq(tr[5].progress, '3 / 27 achievements')
eq(tr[5].extra, 'Title: Riftwarden   -   Kill effect')
eq(tr[6].done, true); eq(tr[6].progress, 'Complete'); eq(tr[6].extra:find('owned', 1, true) ~= nil, true)
eq(#V.trackRows(nil), 0, 'no track: no rows')
eq(V.shortDesc('Pale ash for everyone. Reward track: 1000 points.'), 'Pale ash for everyone.', 'track tail cut')
eq(V.shortDesc('Stars fall over your kills. Complete Exploration & Social.'), 'Stars fall over your kills.', 'category tail cut')
eq(V.shortDesc('A sigil.'), 'A sigil.', 'nothing to cut'); eq(V.shortDesc(nil), '')
eq(V.kindName('lootbeam'), 'Loot label accent'); eq(V.kindName('nope'), 'Cosmetic')

if fails > 0 then print(fails .. ' failure(s)'); os.exit(1) end
print('achievementsview_test: OK')
