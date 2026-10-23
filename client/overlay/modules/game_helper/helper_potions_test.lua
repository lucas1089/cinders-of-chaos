-- luajit helper_potions_test.lua && lua5.3 helper_potions_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'helper_potions.lua')
local P = ChaosHelperPotions
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the Everfull flasks under their client looks
eq(P.EVERFULL.health, 266, 'everfull health look')
eq(P.EVERFULL.mana, 268, 'everfull mana look')
eq(P.EVERFULL_SERVER.health, 32085, 'everfull health server id')
eq(P.EVERFULL_SERVER.mana, 32086, 'everfull mana server id')
eq(P.isHealth(266), true, '266 is a health potion')
eq(P.isMana(268), true, '268 is a mana potion')
eq(P.isPotion(2160), false, 'gold is no potion')
eq(P.isPotion(nil), false, 'nil is no potion')
eq(P.isBoth(7642), true, 'spirit potion gives both')

-- no rune is in the list
for _, p in ipairs(P.LIST) do
  eq(p.name:lower():find('rune', 1, true), nil, p.name .. ' is not a rune')
end

-- percent: 3 + 0.01 per level, capped at 10
eq(P.percentOf(0), 3, 'percent at level 0')
eq(math.abs(P.percentOf(100) - 4) < 1e-9, true, 'percent at 100')
eq(P.percentOf(100000), 10, 'percent cap')

-- expected heal of the everfull health flask at 1000 health: avg 150 + 3.01 % of 1000
eq(P.expected(266, 1000), 180, 'everfull health at 1000 max')
eq(P.expected(268, 1000), 130, 'everfull mana at 1000 max')
eq(P.expected(99999, 1000), nil, 'unknown item')

-- classes
eq(P.canDrink(266, 'mystic', 1), true, 'the everfull flask: everyone')
eq(P.canDrink(23375, 'warrior', 200), true, 'supreme for a warrior at 200')
eq(P.canDrink(23375, 'warrior', 199), false, 'supreme below its level')
eq(P.canDrink(23375, 'mystic', 300), false, 'supreme is not for mages')
eq(P.canDrink(23373, 'mystic', 130), true, 'ultimate mana for a mystic')
local offered = P.offered('mystic', 1)
eq(#offered, 3, 'a level 1 mystic: the small, the health and the mana potion') -- 7876, 266, 268
local have = {}
for _, p in ipairs(offered) do have[p.id] = true end
eq(have[266] and have[268] and have[7876], true, 'level 1 offer')

-- rowKind
eq(P.rowKind({ id = 266 }), 'health', 'row kind health')
eq(P.rowKind({ id = 268 }), 'mana', 'row kind mana')
eq(P.rowKind({ id = 7642 }), 'health', 'spirit defaults to health')
eq(P.rowKind({ id = 7642, priority = 2 }), 'mana', 'spirit with priority 2 is mana')
eq(P.rowKind({ id = 5 }), nil, 'unknown row')

-- pick: health before mana, the lowest threshold first
local rows = {
  { id = 266, percent = 70 },
  { id = 236, percent = 40 },
  { id = 268, percent = 60 },
}
local id, kind = P.pick(rows, { healthPct = 100, manaPct = 100 })
eq(id, nil, 'nothing is due')
id, kind = P.pick(rows, { healthPct = 65, manaPct = 50 })
eq(id, 266, 'health first')
eq(kind, 'health', 'kind health')
id, kind = P.pick(rows, { healthPct = 30, manaPct = 50 })
eq(id, 236, 'the lowest threshold first')
id, kind = P.pick(rows, { healthPct = 100, manaPct = 50 })
eq(id, 268, 'mana when health is fine')
eq(kind, 'mana', 'kind mana')

-- availability: a potion that is not at hand is skipped
id = P.pick(rows, { healthPct = 30, manaPct = 100, available = function(i) return i ~= 236 end })
eq(id, 266, 'the next health potion when one is missing')

-- a health potion due holds back mana, even when it is not at hand
eq(P.healthDue(rows, 65), true, 'health due by the numbers')
eq(P.healthDue(rows, 100), false, 'health not due')

-- a priority tie
local tie = { { id = 266, percent = 50, priority = 2 }, { id = 236, percent = 50, priority = 1 } }
eq(P.pick(tie, { healthPct = 10, manaPct = 100 }), 236, 'priority breaks a tie')

if fails > 0 then os.exit(1) end
print('helper_potions_test: ok')
