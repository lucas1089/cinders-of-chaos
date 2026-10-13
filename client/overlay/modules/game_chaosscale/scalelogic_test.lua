-- luajit scalelogic_test.lua && lua5.3 scalelogic_test.lua (from anywhere; CI runs it from the repo root)
-- The client half of the display scale: the message, the value rule and the spell mana costs.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'scalelogic.lua')
local S = ChaosScale
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the messages
eq(S.hello().action, 'hello', 'hello')
local f, level = S.parse({ action = 'scale', data = { level = 1000, f = 1000 } })
eq(f, 1000, 'factor'); eq(level, 1000, 'level')
eq(S.parse({ action = 'scale', data = { level = 50, f = 1 } }), 1, 'factor 1')
eq(S.parse({ action = 'other', data = { f = 5 } }), nil, 'another action')
eq(S.parse({ action = 'scale', data = { f = 0 } }), nil, 'below 1')
eq(S.parse({ action = 'scale', data = { f = 0 / 0 } }), nil, 'NaN')
eq(S.parse({ action = 'scale', data = { f = 1e12 } }), nil, 'absurd')
eq(S.parse({ action = 'scale', data = { f = '22' } }), 22, 'a string number')
eq(S.parse({ action = 'scale' }), nil, 'no data')
eq(S.parse(nil), nil, 'nothing')

-- a level change the server sends nothing for (a level lost): the client asks again
S.level = 0
eq(S.levelChanged(300), false, 'before the first factor: wait for the login message')
S.level = 1000
eq(S.levelChanged(1000), false, 'the same level')
eq(S.levelChanged(100), true, 'a level lost: ask')
eq(S.levelChanged(1001), true, 'a level gained: ask too (harmless)')
eq(S.levelChanged(nil), false, 'no level')
S.level = 0

-- values: whole numbers exact, fractions rounded, the rest untouched
eq(S.value(2600, 1000), 2600000, '2600 x 1000')
eq(S.value(7, 1), 7, 'factor 1')
eq(S.value(2.5, 3), 8, 'a fraction is rounded (7.5 -> 8)')
eq(S.value('x', 5), 'x', 'a string stays')
S.factor = 22
eq(chaosDisplayFactor(), 22, 'global factor')
eq(chaosDisplayValue(10), 220, 'global value')
S.factor = 1

-- spell mana costs: flat ones follow the factor from their raw cost, percent ones stay
local info = {
  Default = {
    ['Witchfire Bolt'] = { mana = 70 },
    ['Mana Surge'] = { mana = 300, manaPercent = 5 },
    ['Free'] = { mana = 0 },
  },
  Other = { ['Heal'] = { mana = 20 } },
}
eq(S.applySpells(info, 1000), 2, 'two flat costs changed (0 stays 0)')
eq(info.Default['Witchfire Bolt'].mana, 70000, 'flat cost x1000')
eq(info.Other['Heal'].mana, 20000, 'every profile')
eq(info.Default['Mana Surge'].mana, 300, 'a percent cost stays')
eq(info.Default['Witchfire Bolt'].chaosRawMana, 70, 'raw kept')
S.applySpells(info, 5)
eq(info.Default['Witchfire Bolt'].mana, 350, 'a new factor starts from the raw cost, not the scaled one')
S.applySpells(info, 1)
eq(info.Default['Witchfire Bolt'].mana, 70, 'back to the raw cost')
eq(S.applySpells(nil, 5), 0, 'no SpellInfo')

if fails > 0 then
  print(fails .. ' of ' .. checks .. ' checks failed')
  os.exit(1)
end
print('scalelogic_test: ' .. checks .. ' checks passed')
