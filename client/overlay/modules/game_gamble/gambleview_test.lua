-- luajit gambleview_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'gambleview.lua')
local V = GambleView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function has(text, part, m) n = n + 1 if not tostring(text):find(part, 1, true) then error((m or '') .. ': ' .. tostring(text), 2) end end

local s = {
  w = 123456,
  items = {
    { i = 1, id = 29883, c = 9883, n = 'Dawnforged Blade', s = 'weapon', sn = 'Weapon', l = 123, p = 1950000 },
    { i = 2, id = 29879, c = 9879, n = 'Dawnforged Plate', s = 'armor', sn = 'Armor', l = 119, p = 1640000, sold = true },
    { i = 3, id = 2643, c = 2643, n = 'leather boots', s = 'boots', sn = 'Boots', l = 120, p = 1300000 },
    { i = 4, id = 29890, c = 9890, n = 'Dawnforged Ring', s = 'ring', sn = 'Ring', l = 121, p = 99000000 },
  },
  level = 1000, gate = 123, near = true, money = 5000000, left = 3 * 3600 + 5 * 60 + 9, hours = 4, at = '08:00', tz = 'UTC-3',
  reroll = 862500, rerolls = 1, rerollMax = 3,
  odds = { { r = 1, n = 'Common', p = 61.9 }, { r = 2, n = 'Uncommon', p = 11.62 }, { r = 5, n = 'Legendary', p = 3.46 },
    { r = 10, n = 'Divine', p = 2.24 }, { r = 9, n = 'Eternal', p = 0.75 } },
  npc = 'Mordecai Ashwager',
  last = { r = 5, rn = 'Legendary', id = 29879, c = 9879, n = 'Dawnforged Plate', l = 119, s = 'armor', i = 2 }
}

-- numbers and time
eq(V.fmtNum(1950000), '1,950,000', 'thousands')
eq(V.short(1950000), '1.95M', 'millions')
eq(V.short(1500000), '1.5M', 'trailing zero dropped')
eq(V.short(2000000), '2M', 'whole millions')
eq(V.short(97000), '97k', 'thousands short')
eq(V.short(3600), '3,600', 'small stays')
eq(V.countdown(3 * 3600 + 5 * 60 + 9), '3h 05m', 'hours')
eq(V.countdown(12 * 60 + 9), '12m 09s', 'minutes')
eq(V.countdown(45), '45s', 'seconds')
eq(V.countdown(-5), '0s', 'never negative')
eq(V.left(s, 60), s.left - 60, 'the countdown runs from the state')
eq(V.left(s, 99999), 0, 'and stops at zero')
has(V.refreshText(s, 0), 'New crates at 08:00 (UTC-3), in 3h 05m', 'refresh text')
has(V.refreshText(s, s.left - 30), 'in 30s', 'the last seconds')

-- cells
local c = V.cells(s)
eq(#c, 4, 'one cell per crate')
eq(c[1].name, 'Dawnforged Blade', 'name')
eq(c[3].name, 'Leather boots', 'capitalised')
eq(c[1].levelText, 'iLvl 123', 'item level')
eq(c[1].slotText, 'Weapon', 'slot')
eq(c[1].priceText, '1,950,000 gold', 'price')
eq(c[1].buyText, 'Buy 1.95M', 'buy text')
eq(c[1].canBuy, true, 'can buy')
eq(c[1].priceColor, V.COLORS.gold, 'affordable price colour')
eq(c[2].canBuy, false, 'sold: no')
eq(c[2].buyText, 'Sold', 'sold text')
eq(c[2].sold, true, 'sold flag')
has(c[2].tip, 'Sold.', 'sold tooltip')
eq(c[4].canBuy, false, 'too expensive')
eq(c[4].priceColor, V.COLORS.bad, 'too expensive colour')
has(c[4].tip, 'You need 99,000,000 gold', 'gold tooltip')
has(c[1].tip, 'Rarity: sealed until bought', 'the rarity is hidden')
has(c[1].tip, 'break the seal', 'buy tooltip')
for _, cell in ipairs(c) do
  n = n + 1
  if cell.tip:find('Legendary', 1, true) or cell.tip:find('Common', 1, true) then error('a cell names a rarity') end
end
s.near = false
eq(V.cells(s)[1].canBuy, false, 'away from the Gambler')
has(V.cells(s)[1].tip, 'in person', 'away tooltip')
local t, col = V.nearText(s)
has(t, 'buy from Mordecai Ashwager', 'away text')
eq(col, V.COLORS.warn, 'away colour')
s.near = true
t, col = V.nearText(s)
has(t, 'You stand before Mordecai Ashwager', 'near text')
eq(col, V.COLORS.good, 'near colour')

-- header and counts
eq(V.soldCount(s), 1, 'one sold')
has(V.header(s), 'level 1000 (item level up to 123): 1 of 4 sold', 'header')
has(V.header(s), '5,000,000', 'gold in the header')

-- early refresh
local rt, ok, tip = V.reroll(s)
eq(rt, 'Fresh Crates (862k)', 'refresh button')
eq(ok, true, 'refresh enabled')
has(tip, '1 of 3 used', 'refresh tooltip')
s.money = 100
rt, ok = V.reroll(s)
eq(ok, false, 'too poor to refresh')
s.money = 5000000
s.reroll = nil
rt, ok, tip = V.reroll(s)
eq(ok, false, 'none left')
has(tip, 'New crates at 08:00', 'none left tooltip')
eq(select(2, V.reroll({ rerollMax = 0 })), false, 'switched off')

-- odds and the reveal
has(V.oddsText(s), 'Common 61.9%', 'odds text')
has(V.oddsText(s), 'Eternal 0.75%', 'small odds keep two decimals')
eq(V.legendaryOrBetter(s), 3.46 + 2.24 + 0.75, 'legendary or better')
local rv, rc = V.reveal(s.last)
eq(rv, 'The seal breaks: Legendary Dawnforged Plate (item level 119)', 'reveal text')
eq(rc, V.RARITY[5], 'reveal colour')
eq(V.reveal(nil), '', 'no reveal yet')
eq(V.cells(nil)[1], nil, 'no state, no cells')
eq(V.header(nil), '', 'no state, no header')

print('gambleview_test: ' .. n .. ' checks passed')
