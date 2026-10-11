-- Run from the repo root: luajit client/overlay/modules/game_arena/arenatext_test.lua (also lua5.3)
local here = (arg and arg[0] or ''):match('^(.*)/[^/]*$') or '.'
dofile(here .. '/arenatext.lua')
local T = ArenaText
local fails, n = 0, 0
local function eq(a, b, name)
  n = n + 1
  if a ~= b then fails = fails + 1; print('FAIL ' .. name .. ': got ' .. tostring(a) .. ', want ' .. tostring(b)) end
end
eq(T.clock(75), '1:15', 'clock')
eq(T.clock(300), '5:00', 'clock 5 min')
eq(T.clock(-3), '0:00', 'clock negative')
eq(T.clock(9.7), '0:09', 'clock floors')
eq(T.delta(12), '+12', 'delta +')
eq(T.delta(-8), '-8', 'delta -')
eq(T.delta(0), '+0', 'delta 0')
eq((T.result('win')), 'VICTORY', 'result win')
eq(select(2, T.result('loss')), '#e03a1e', 'result colour')
eq(T.ratingLine(1000, 1020, 20), 'Rating 1000 -> 1020 (+20)', 'rating line')
eq(T.record({wins = 3, losses = 1}), '3-1-0', 'record')
eq(T.record(nil), '0-0-0', 'record empty')
eq(T.ago(30), 'just now', 'ago s')
eq(T.ago(600), '10m ago', 'ago m')
eq(T.ago(7300), '2h ago', 'ago h')
eq(T.ago(200000), '2d ago', 'ago d')
eq(T.reason('timeout'), 'time ran out', 'reason')
eq((T.hudCenter('countdown', 7)), '7', 'hud countdown')
eq((T.hudCenter('fight', 125)), '2:05', 'hud fight')
eq(select(2, T.hudCenter('done', 0)), 'over', 'hud done')
eq(T.hpColor(80), '#2f7a2a', 'hp green')
eq(T.hpColor(10), '#8a1010', 'hp red')
eq(T.MODE_TITLE['3v3'], 'Warband 3v3', '3v3 title')
eq((T.seasonLine({ rating = 1650, placed = true, tierName = 'Kindled', color = '#f0a040' }, 2)), 'Season: Kindled 1650', 'season line')
eq((T.seasonLine({ rating = 1500, placed = false, matches = 2, placementLeft = 3 }, 2)), 'Season: placement 2/5', 'placement line')
eq((T.seasonLine(nil)), '', 'no season')
eq(T.seasonDelta({ before = 1500, after = 1520, delta = 20, placed = true, tierName = 'Kindled' }), 'Season 1500 -> 1520 (+20) Kindled', 'season delta')
eq(T.seasonDelta({ before = 1500, after = 1640, delta = 140, placed = false, placementLeft = 4 }), 'Season 1500 -> 1640 (+140), placement: 4 left', 'placement delta')
print(string.format('arenatext_test: %d checks, %d failed', n, fails))
if fails > 0 then os.exit(1) end
