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

if fails > 0 then print(fails .. ' failure(s)'); os.exit(1) end
print('achievementsview_test: OK')
