-- luajit professionsview_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'professionsview.lua')
local V = ProfessionsView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function has(text, part, m) n = n + 1 if not tostring(text):find(part, 1, true) then error((m or '') .. ': ' .. tostring(text), 2) end end

local s = {
  profs = {
    { k = 'delving', n = 'Delving', lv = 23, xp = 120, need = 468, pct = 25, tier = 2, tool = 'a pick', d = 'Ore.', g = 140 },
    { k = 'wortcunning', n = 'Wortcunning', lv = 1, xp = 0, need = 38, pct = 0, tier = 1, tool = 'a sickle', d = 'Herbs.', g = 0 },
    { k = 'flaying', n = 'Flaying', lv = 100, xp = 0, need = 0, pct = 100, tier = 5, tool = 'an obsidian knife', d = 'Hides.', g = 9000 },
    { k = 'angling', n = 'Angling', lv = 5, xp = 7, need = 81, pct = 8, tier = 1, tool = 'a fishing rod', d = 'Fish.', g = 3 },
  },
  bonus = 3.04, cap = 10, per = 0.0253,
  tiers = { { n = 'Common', p = 1, c = 8, g = 20, col = '#b8b0a0' }, { n = 'Fine', p = 20, c = 40, g = 80, col = '#7ec46a' } },
  demand = {
    { id = 32352, c = 5888, n = 'bloodiron ore', p = 'delving', t = 2, m = 1.5, g = 120, l = 60, s = 90, h = 30 },
    { id = 32351, c = 5880, n = 'ashstone ore', p = 'delving', t = 1, m = 0.75, g = 15, l = 8, s = 200, h = 12 },
    { id = 32366, c = 2667, n = 'mudfin', p = 'angling', t = 1, m = 1, g = 20, l = 10, s = 0, h = 0 },
    { id = 32356, c = 4838, n = 'gravemoss', p = 'wortcunning', t = 1, m = 1.25, g = 25, l = 13, s = 0, h = 3 },
  },
  areas = { { n = 'Dragon Scar', t = 2, f = true, m = 'dragons', near = 'Mirewake', x = 33215, y = 31297, z = 7,
    nodes = { { k = 'delving', r = 7, t = 10 }, { k = 'angling', r = 1, t = 1 } } } },
  broker = true, full = 100, capDay = 200, late = 0.5, nextDay = 3 * 3600 + 120, nextWeek = 2 * 86400 + 5 * 3600, respawn = 6
}

-- numbers and texts
eq(V.fmtNum(1234567), '1,234,567', 'thousands')
eq(V.fmtNum(999), '999', 'small number')
eq(V.fmtNum(-1500), '-1,500', 'negative')
eq(V.fmtPct(2.5), '2.5', 'pct')
eq(V.fmtPct(10), '10', 'whole pct')
eq(V.fmtPct(0.0253), '0.0253', 'small pct keeps its digits')
eq(V.timeText(3 * 3600 + 120), '3h 2m', 'hours')
eq(V.timeText(2 * 86400 + 5 * 3600), '2d 5h', 'days')
eq(V.timeText(10), '1m', 'at least a minute')
has(V.bonusText(s), '+3.04%', 'bonus text')
has(V.bonusText(s), 'at most +10%', 'bonus cap')

-- professions
local rows = V.profRows(s)
eq(#rows, 4, 'four professions')
eq(rows[1].xpText, '120 / 468', 'xp text')
eq(rows[1].tierText, 'Gathers fine materials', 'tier text')
eq(rows[3].xpText, 'Mastered', 'max level')
eq(rows[3].pct, 100, 'full bar at max')

-- demand board and the sale mirror
local d = V.demandRows(s)
eq(#d, 4, 'all materials')
eq(d[1].id, 32351, 'delving tier 1 first')
eq(d[2].id, 32352, 'then tier 2')
eq(d[3].prof, 'wortcunning', 'profession order')
eq(d[4].prof, 'angling', 'angling last')
eq(d[2].multText, 'x1.5', 'demand up')
eq(d[2].multColor, V.COLORS.up, 'up colour')
eq(d[1].multColor, V.COLORS.down, 'down colour')
-- bloodiron: 90 sold, 30 held: 10 at 120, 20 at 60
local q = V.quote(s, s.demand[1], 30)
eq(q.units, 30, 'all sold')
eq(q.gold, 10 * 120 + 20 * 60, 'full then late price')
-- ashstone: the cap is reached: nothing
eq(V.quote(s, s.demand[2], 12).units, 0, 'cap reached')
eq(V.canSell(s, s.demand[2]), false, 'cannot sell at the cap')
eq(V.canSell(s, s.demand[3]), false, 'cannot sell what you do not carry')
eq(V.canSell(s, s.demand[4]), true, 'can sell')
eq(#V.demandRows(s, 'delving'), 2, 'filter by profession')
local est = V.sellAllEstimate(s)
eq(est.units, 33, 'sell all units')
eq(est.gold, 2400 + 3 * 25, 'sell all gold')
s.broker = false
eq(V.canSell(s, s.demand[4]), false, 'away from the broker')
s.broker = true
-- hot list
local hot = V.hotList(s)
eq(#hot, 2, 'two hot materials')
eq(hot[1].id, 32352, 'hottest first')

-- areas
local a = V.areaLines(s)
eq(#a, 1, 'one area')
eq(a[1].title, 'Dragon Scar (Fine)', 'area title')
has(a[1].text, 'Delving 7/10 ready', 'ready nodes')
has(a[1].text, 'fishing', 'fishing water')
has(a[1].text, 'near Mirewake', 'nearest town')
has(a[1].tip, '33215, 31297, 7', 'the position in the tooltip')
has(a[1].tip, 'hunting ground of dragons', 'the monsters in the tooltip')
has(V.footer(s), 'Full price for 100 a day', 'footer rule')
has(V.footer(s), 'new demand in 2d 5h', 'footer week')

print('professionsview_test: ' .. n .. ' checks passed')
