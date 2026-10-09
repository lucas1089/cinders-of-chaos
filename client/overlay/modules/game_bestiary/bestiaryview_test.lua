-- luajit bestiaryview_test.lua && lua5.3 bestiaryview_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'bestiaryview.lua')
local V = BestiaryView
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local raw = {
  { 1, 'Rat', 'beasts', 'harmless', 4, 300, 4, 21 },
  { 2, 'Cave Rat', 'beasts', 'harmless', 5, 0, 0, 0 },
  { 3, 'Dragon', 'dragons', 'easy', 42, 30, 2, 34 },
  { 4, 'Dragon Lord', 'dragons', 'medium', 73, 0, 0, 0 },
}
local rows = {}
for i, r in ipairs(raw) do rows[i] = V.row(r) end
eq(rows[3].name, 'Dragon', 'row name')
eq(rows[3].look, 34, 'row look')
eq(rows[2].stage, 0, 'row stage')
eq(#V.filter(rows, V.ALL, ''), 4, 'all')
eq(#V.filter(rows, 'dragons', nil), 2, 'category')
eq(#V.filter(rows, V.ALL, 'RAT'), 2, 'search is case-insensitive')
eq(#V.filter(rows, V.ALL, '  dragon '), 2, 'search trims')
eq(#V.filter(rows, V.ALL, 'dragon l'), 1, 'search with spaces')
eq(#V.filter(rows, V.ALL, '(', false), 0, 'plain text search (no pattern error)')
eq(#V.filter(rows, V.ALL, '', true), 2, 'known only')
eq(V.filter(rows, 'beasts', '', true)[1].name, 'Rat', 'known only in a category')

local list = {}
for i = 1, 105 do list[i] = i end
local part, page, pages = V.page(list, 1, 50)
eq(#part, 50, 'first page'); eq(page, 1, 'page 1'); eq(pages, 3, '3 pages')
part, page = V.page(list, 9, 50)
eq(page, 3, 'clamped to the last page'); eq(#part, 5, 'the rest'); eq(part[1], 101, 'starts at 101')
part, page, pages = V.page({}, 1, 50)
eq(#part, 0, 'empty'); eq(pages, 1, 'one empty page')

local names = { 'Discovered', 'Studied', 'Mastered', 'Completed' }
eq(V.stageName(0, names), 'Undiscovered', 'stage 0')
eq(V.stageName(3, names), 'Mastered', 'stage 3')
eq(V.killText(30, 250), 'Kills 30 / 250', 'kills to next')
eq(V.killText(1200, nil), 'Kills 1200', 'complete')
local th = { 1, 25, 250, 1000 }
eq(V.stagePercent(0, th), 0, '0 kills')
eq(V.stagePercent(13, th), 50, 'halfway from 1 to 25')
eq(V.stagePercent(25, th), 0, 'a new stage starts at 0')
eq(V.stagePercent(1000, th), 100, 'complete')

eq(V.elementsText({ { name = 'fire', pct = 20 }, { name = 'energy', pct = -10 } }), 'fire -20%, energy +10%',
  'damage taken')
eq(V.elementsText({}), '', 'no elements')
eq(V.chanceText(25.4), '25%', 'chance big')
eq(V.chanceText(2.5), '2.5%', 'chance mid')
eq(V.chanceText(0.1), '0.10%', 'chance small')
eq(V.pctText(1.5), '1.5%', 'pct fraction')
eq(V.pctText(2), '2%', 'pct whole')

eq(V.rewardText({ gold = 4000, chaos = 1, exp = 12500, points = 5 }), '4k gold, 1 Orb of Upheaval, 12.5k exp, 5 points',
  'reward')
eq(V.rewardText({ gold = 1200000, chaos = 4, divine = 1 }), '1.2M gold, 4 Orbs of Upheaval, 1 Orb of Fate', 'reward big')
eq(V.rewardText(nil), '', 'no reward')
eq(V.rewardShort({ gold = 30000, chaos = 1, divine = 1, exp = 14300, points = 16 }), '30k gold, 1 Upheaval, 1 Fate, 14.3k exp, 16 points',
  'short reward')
eq(V.taskText({ kind = 'hunt', label = 'Dragon', required = 150 }), 'Kill 150 Dragons.', 'hunt text')
eq(V.taskText({ kind = 'hunt', label = 'Cyclops', required = 1 }), 'Kill 1 Cyclops.', 'singular')
eq(V.taskText({ kind = 'family', label = 'Dragons', required = 270, lo = 40, hi = 120 }),
  'Kill 270 Dragons of level 40-120.', 'family text')
eq(V.plural('Dwarf Guard', 2), 'Dwarf Guards', 'plural')
eq(V.plural('Fury', 2), 'Furies', 'plural y')
eq(V.plural('Witch', 2), 'Witches', 'plural ch')

local line, pct, done = V.trackerLine({ k = 'task', label = 'Dragon', p = 30, r = 120 })
eq(line, 'Dragon 30/120', 'tracker line'); eq(pct, 25, 'tracker pct'); eq(done, false, 'not done')
line, pct, done = V.trackerLine({ label = 'X', p = 5, r = 5 })
eq(pct, 100, 'done pct'); eq(done, true, 'done')
eq(V.limitsText({ active = 1, maxActive = 3, doneDay = 2, dailyLimit = 4, doneWeek = 5, weeklyLimit = 20 }),
  'Active 1 / 3   Today 2 / 4   This week 5 / 20', 'limits')
eq(V.clock(3 * 3600 + 5 * 60 + 9), '3h 05m', 'clock')
local lim = { active = 1, maxActive = 3, doneDay = 1, dailyLimit = 4, doneWeek = 2, weeklyLimit = 20 }
eq(V.acceptBlock(lim), nil, 'may accept')
lim.active = 3
eq(V.acceptBlock(lim) ~= nil, true, 'active cap')
lim.active, lim.doneDay = 1, 3
eq(V.acceptBlock(lim):find('a day') ~= nil, true, 'daily limit')
lim.doneDay, lim.doneWeek = 0, 19
eq(V.acceptBlock(lim):find('a week') ~= nil, true, 'weekly limit')
eq(V.short(950), '950', 'short')

if fails > 0 then error(fails .. ' failure(s)') end
print('bestiaryview_test: ok')
