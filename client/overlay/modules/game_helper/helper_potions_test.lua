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

-- classes: none (owner 2026-10-24); the level still gates
eq(P.canDrink(266, 'mystic', 1), true, 'the everfull flask: everyone')
eq(P.canDrink(23375, 'warrior', 200), true, 'supreme for a warrior at 200')
eq(P.canDrink(23375, 'warrior', 199), false, 'supreme below its level')
eq(P.canDrink(23375, 'mystic', 300), true, 'supreme for a mystic: no class limit')
eq(P.canDrink(7642, 'warrior', 80), true, 'spirit for a warrior')
eq(P.canDrink(238, 'warrior', 300), true, 'great mana for a warrior')
for _, p in ipairs(P.LIST) do eq(p.lines, nil, p.name .. ' has no class list') end
eq(#P.offered('mystic', 1), #P.LIST, 'every potion is offered to everyone')

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

-- the list against the server: every potion the Apothecary sells (server/data/scripts/chaos/apothecary_config.lua, the
-- tiers of the stock potions.lua) is in the list under its server id, with the same name and level; none is left out
local okLoad, shop = pcall(dofile, dir .. '../../../../server/data/scripts/chaos/apothecary_config.lua')
eq(okLoad and type(shop) == 'table', true, 'apothecary_config.lua loads')
if okLoad and type(shop) == 'table' then
  local bySrv, n = {}, 0
  for _, p in ipairs(P.LIST) do
    eq(type(p.server), 'number', p.name .. ' has a server id')
    eq(bySrv[p.server], nil, p.name .. ' server id is unique')
    bySrv[p.server] = p
  end
  for _, sp in ipairs(shop.potions) do
    if sp.id ~= 8474 then -- the antidote is no health or mana potion
      n = n + 1
      local p = bySrv[sp.id]
      eq(p ~= nil, true, 'server potion ' .. sp.id .. ' (' .. sp.name .. ') is in the helper list')
      if p then
        eq(p.name:lower(), sp.name, 'name of ' .. sp.id)
        eq(p.level, math.max(sp.level, 1), 'level of ' .. sp.id)
      end
      bySrv[sp.id] = nil
    end
  end
  -- what is left is the Everfull look (7618 is sold as the health potion; the Everfull flasks wear its look)
  eq(next(bySrv), nil, 'every helper potion is sold by the Apothecary')
  eq(n, #P.LIST, 'the same number of potions')
end

-- the dropdown: health, then mana, then spirit (health and mana entries), the strongest first
local function keys()
  local t = {}
  for _, e in ipairs(P.options()) do t[#t + 1] = e.key end
  return table.concat(t, ',')
end
eq(keys(), '23375,7643,239,236,266,7876,23373,238,237,268,23374:1,23374:2,7642:1,7642:2', 'the dropdown order')
local seenKey = {}
for _, e in ipairs(P.options()) do
  eq(seenKey[e.key], nil, 'no double entry ' .. e.key)
  seenKey[e.key] = true
end
eq(#P.options(), 14, '10 plain potions and two spirit potions with two entries each')

if fails > 0 then os.exit(1) end
print('helper_potions_test: ok')
