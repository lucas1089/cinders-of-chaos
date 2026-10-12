-- luajit guildmath_test.lua && lua5.3 guildmath_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'guildmath.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local M = GuildMath
eq(M.money(5000000), '5,000,000', 'money')
eq(M.money(-1234), '-1,234', 'money negative')
eq(M.money(nil), '0', 'money nil')
eq(M.duration(90061), '1d 1h', 'duration')
eq(M.duration(-1), '0m', 'duration negative')
eq(M.levelText({ level = 3, maxLevel = 20 }), 'Guild level 3 / 20', 'level text')
eq(M.xpText({ into = 150, need = 850, pct = 17 }), '150 / 850 GXP (17%)', 'xp text')
eq(M.xpText({ into = 0, need = 0 }), 'Max level', 'xp max')
eq(M.percent({ into = 425, need = 850 }), 50, 'percent')
eq(M.percent({ need = 0 }), 100, 'percent max')
eq(M.percent({ into = 9999, need = 10 }), 100, 'percent clamped')
eq(M.perksNow({ xp = 1, loot = 2, scroll = true }), '+1% experience, +2% loot, daily hall scroll', 'perks')
eq(M.perksNow({}), 'No perks yet: they start at guild level 2.', 'no perks')
eq(M.rentText({ owned = false }), 'Your guild owns no guild hall.', 'no hall')
eq(M.rentText({ owned = true, rent = 300000, rentState = 'paid', paidUntil = '15.10 14:00', rentLeft = 3600 }),
  'Rent 300,000 gold a week, paid until 15.10 14:00 (1h 0m left).', 'rent paid')
eq(M.rentText({ owned = true, rent = 300000, rentState = 'grace', graceLeft = 7200 }),
  'Rent 300,000 gold a week is DUE. The upgrades lock in 2h 0m.', 'rent grace')
eq(M.rentText({ owned = true, rent = 400000, rentState = 'locked' }),
  'Rent 400,000 gold a week is UNPAID: the upgrades are locked until it is paid.', 'rent locked')
eq(M.rentColor({ rentState = 'locked' }), '#e05a4a', 'rent colour')
eq(M.upgradeText({ name = 'Teleport Hub', tier = 0, max = 1, cost = 2000000, level = 6 }), 'Teleport Hub - 2,000,000 gold, guild level 6', 'upgrade new')
eq(M.upgradeText({ name = 'Teleport Hub', tier = 1, max = 1, active = true }), 'Teleport Hub - owned', 'upgrade owned')
eq(M.upgradeText({ name = 'Teleport Hub', tier = 1, max = 1, active = false }), 'Teleport Hub - owned, locked', 'upgrade locked')
eq(M.upgradeText({ name = 'Decoration', tier = 1, max = 3, cost = 3000000, level = 16 }), 'Decoration 1/3 - next: 3,000,000 gold, level 16', 'upgrade tiers')
eq(M.memberText({ name = 'Tester', rank = 'Leader', level = 599 }), 'Tester (Leader, level 599)', 'member')
eq(M.memberPoints({ week = 120, total = 4500 }), '120 this week / 4,500', 'member points')
eq(M.topText({ rank = 1, name = 'Iron Wolves', level = 6 }), '1. Iron Wolves (level 6)', 'top')
eq(M.parseAmount('2.5m'), 2500000, 'parse m')
eq(M.parseAmount('50k'), 50000, 'parse k')
eq(M.parseAmount('1,000'), 1000, 'parse commas')
eq(M.parseAmount('abc'), nil, 'parse bad')
if fails > 0 then os.exit(1) end
print('guildmath tests OK')
