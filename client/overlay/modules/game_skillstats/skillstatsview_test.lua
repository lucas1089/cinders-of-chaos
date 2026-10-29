-- luajit skillstatsview_test.lua && lua5.3 skillstatsview_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'skillstatsview.lua')
local V = ChaosSkillStatsView
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- no message: the five rows read "-", never 0, and Mantra is hidden
local v = V.build(nil)
for _, name in ipairs({ 'damage', 'attack', 'defense', 'armor', 'mitigation' }) do
  eq(v[name].text, '-', 'no message: ' .. name .. ' reads -')
  eq(v[name].visible, true, 'no message: ' .. name .. ' visible')
end
eq(v.mantra.visible, false, 'mantra hidden without a message')
v = V.build('garbage')
eq(v.armor.text, '-', 'a non-table is no message')

-- a full message
v = V.build({ damage = 1234.4, attack = 55, defense = 41, armor = 75, mitigation = 0.2308 })
eq(v.damage.text, '1234', 'damage rounded'); eq(v.attack.text, '55', 'attack'); eq(v.defense.text, '41', 'defence')
eq(v.armor.text, '75', 'armor'); eq(v.mitigation.text, '+23.1%', 'mitigation in percent, one decimal')
eq(v.armor.color, V.GREEN, 'above 0: green'); eq(v.mantra.visible, false, 'mantra hidden with a message')
for _, name in ipairs(V.ROWS) do
  eq(type(v[name]), 'table', 'every row has a view: ' .. name)
end

-- the short number function is used for the big ones
v = V.build({ damage = 15300, attack = 2450000, defense = 1, armor = 2 }, function(n) return 'S' .. n end)
eq(v.damage.text, 'S15300', 'damage short'); eq(v.attack.text, 'S2450000', 'attack short'); eq(v.mitigation.text, '-', 'no mitigation field: -')

-- a wand or a fist: no attack, no damage: the rows go
v = V.build({ defense = 3, armor = 0, mitigation = 0 })
eq(v.damage.visible, false, 'no damage: row hidden'); eq(v.attack.visible, false, 'no attack: row hidden')
eq(v.armor.text, '0', 'a real zero is shown as 0'); eq(v.armor.color, V.GREY, 'zero is grey')
eq(v.mitigation.text, '+0.0%', 'a real zero mitigation')
v = V.build({ damage = 0, attack = 0, defense = 1, armor = 1, mitigation = 0.1 })
eq(v.damage.visible, false, 'damage 0 hidden'); eq(v.attack.visible, false, 'attack 0 hidden')

-- bad fields never show 0 or crash
v = V.build({ damage = 'x', attack = {}, defense = 0 / 0, armor = math.huge, mitigation = -3 })
eq(v.damage.visible, false, 'text damage hidden'); eq(v.attack.visible, false, 'table attack hidden')
eq(v.defense.text, '-', 'NaN defence is -'); eq(v.armor.text, '-', 'infinite armor is -')
eq(v.mitigation.text, '+0.0%', 'mitigation clamps at 0')
v = V.build({ defense = 1, armor = 1, mitigation = 7 })
eq(v.mitigation.text, '+100.0%', 'mitigation clamps at 1')

print(fails == 0 and 'skillstatsview_test: ok' or ('skillstatsview_test: ' .. fails .. ' failed'))
os.exit(fails == 0 and 0 or 1)
