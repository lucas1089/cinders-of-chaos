-- luajit paragonmasterymath_test.lua && lua5.3 paragonmasterymath_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'paragonmath.lua')
dofile(dir .. 'paragonmasterymath.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local M = ParagonMath
local ms = {unlocked = true, free = 250, mastery = {maxRanks = 60000, rows = {
  {key = 'mDamage', name = 'Damage Mastery', ranks = 300, value = 11.6667, next = 0.0167},
  {key = 'mMana', name = 'Mana Mastery', ranks = 0, value = 0, next = 0.16}}},
  exchange = {ratio = 1, treeFree = 40, converted = 0}}
local row = ms.mastery.rows[1]
eq(M.masteryBuy(ms, row, 100), 100, 'buy 100 ranks')
eq(M.masteryBuy(ms, row, 1000), 250, 'buy stops at the free points')
row.ranks = 59990
eq(M.masteryBuy(ms, row, 100), 10, 'buy stops at the rank limit')
row.ranks = 300
eq(M.masteryBuy({unlocked = false, free = 9, mastery = ms.mastery}, row, 1), 0, 'locked')
eq(M.masteryBuy(nil, row, 1), 0, 'no state')
eq(M.masteryBuy({unlocked = true, free = 0, mastery = ms.mastery}, row, 1), 0, 'no free points')
eq(M.masteryValueText(row), '+11.67%', 'mastery value')
eq(M.masteryNextText(row), '+0.017%', 'next rank')
eq(M.fmt3(0.5), '0.5', 'fmt3'); eq(M.fmt3(2), '2', 'fmt3 integer')
eq(M.exchangeable(ms), 40, 'exchangeable')
eq(M.exchangeable({unlocked = false, exchange = ms.exchange}), 0, 'locked exchange')
eq(M.exchangeable(nil), 0, 'no state exchange')
eq(M.exchangeGain(ms, 40), 40, 'ratio 1')
eq(M.exchangeGain({exchange = {ratio = 2}}, 5), 10, 'ratio 2')
eq(#M.masteryLines(ms), 1, 'only masteries with ranks')
eq(M.masteryLines(ms)[1], '+11.67% Damage Mastery (300 ranks).', 'mastery line')
if fails > 0 then os.exit(1) end
print('paragon mastery math tests OK')
