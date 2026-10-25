-- luajit helper_potions_test.lua && lua5.3 helper_potions_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'helper_potions.lua')
local P = ChaosHelperPotions
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the Everfull flasks under their client looks
eq(P.everfullOf(266).server, 32085, 'everfull health: server id under the Health Potion look')
eq(P.everfullOf(268).server, 32086, 'everfull mana: server id under the Mana Potion look')
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


-- ---------------------------------------------------------------- the Everfull table (O246) against the server's config
local cfgFile = io.open('server/data/scripts/chaos/potions_config.lua', 'r') or io.open(dir .. '../../../../server/data/scripts/chaos/potions_config.lua', 'r')
if cfgFile then
  local src = cfgFile:read('*a') cfgFile:close()
  local cfg = load(src)()
  eq(#P.EVERFULL_ITEMS, #cfg.everfull, 'one client row per Everfull of the server')
  for _, e in ipairs(cfg.everfull) do
    local c
    for _, x in ipairs(P.EVERFULL_ITEMS) do if x.server == e.id then c = x end end
    eq(c ~= nil, true, 'client row for ' .. e.name)
    if c then
      eq(c.slot, e.key, e.name .. ': slot') eq(c.line, e.line, e.name .. ': line')
      eq(c.tier, e.tier, e.name .. ': tier') eq(c.level, e.level, e.name .. ': level')
      eq(c.kind, (e.line == 'spirit') and 'both' or e.key, e.name .. ': kind')
      -- while the looks are shared, the look is the stock potion's, and the list knows it with the stock level
      local stock = P.info(c.look)
      eq(stock ~= nil, true, e.name .. ': its look is in the potion list')
      if stock and stock.server == e.sourceId then eq(stock.level, math.max(e.level, 1), e.name .. ': the stock level') end
    end
  end
end

-- ---------------------------------------------------------------- resolve: a Health / Mana Potion row follows the carried Everfull
local function held(slot, look, line, level, ready)
  local h = {}
  h[slot] = { look = look, tier = 2, level = level, line = line or slot, ready = ready ~= false }
  return h
end
eq(P.resolve(266, nil, 100), 266, 'nothing held: unchanged')
eq(P.resolve(266, {}, 100), 266, 'an empty view: unchanged')
eq(P.resolve(266, held('health', 266, 'health', 0), 100), 266, 'tier 1 held: its own look')
eq(P.resolve(266, held('health', 239, 'health', 80), 100), 239, 'great health held: the Health Potion row drinks it')
eq(P.resolve(266, held('health', 23375, 'health', 200), 300), 23375, 'supreme health held')
eq(P.resolve(268, held('mana', 23373, 'mana', 130), 130), 23373, 'ultimate mana held')
eq(P.resolve(268, held('mana', 238, 'mana', 80), 79), 268, 'below the Everfull level: the stock row (the server would refuse)')
eq(P.resolve(266, held('health', 239, 'health', 80, false), 100), 266, 'an empty flask is not followed (it would drink a dearer stock potion)')
eq(P.resolve(266, held('health', 7642, 'spirit', 80), 100), 266, 'a spirit flask is chosen by a spirit row, not a health row')
eq(P.resolve(266, held('mana', 238, 'mana', 80), 100), 266, 'a mana flask does not serve a health row')
eq(P.resolve(266, held('health', 99999, 'health', 0), 100), 266, 'an unknown look is not followed')
eq(P.resolve(268, held('health', 239, 'health', 80), 100), 268, 'the health slot does not serve the mana row')
eq(P.resolve(239, held('health', 7643, 'health', 130), 200), 239, 'a row on the great potion is its own choice')
eq(P.resolve(7876, held('health', 239, 'health', 80), 100), 7876, 'so is the small potion')
eq(P.resolve('266', held('health', 239, 'health', 80), '100'), 239, 'strings from a saved config')
eq(P.resolve(nil, held('health', 239, 'health', 80), 100), nil, 'nil stays nil')

-- pick: the due row's resolved look is what goes out, and availability is asked for that look
local rows = { { id = 266, percent = 60, priority = 1 }, { id = 268, percent = 50, priority = 1 } }
local asked = {}
local id, kind = P.pick(rows, { healthPct = 40, manaPct = 100, held = held('health', 239, 'health', 80), level = 100,
  available = function(x) asked[#asked + 1] = x return true end })
eq(id, 239, 'pick: the follow') eq(kind, 'health', 'pick: still a health potion') eq(asked[1], 239, 'availability asked for the Everfull look')
id = P.pick(rows, { healthPct = 40, manaPct = 100, held = held('health', 239, 'health', 80), level = 100,
  available = function(x) return x ~= 239 end })
eq(id, nil, 'pick: the followed look is not available, nothing else is drunk for that row')
id, kind = P.pick(rows, { healthPct = 100, manaPct = 40, held = { mana = { look = 238, tier = 2, level = 80, line = 'mana', ready = true } }, level = 100 })
eq(id, 238, 'pick: mana follows') eq(kind, 'mana', 'pick: mana kind')
id = P.pick(rows, { healthPct = 40, manaPct = 100 })
eq(id, 266, 'pick without a held view: as before')
-- a row on a spirit look is the spirit flask's own look (the server picks the Everfull of that look)
id = P.pick({ { id = 7642, percent = 60, priority = 1 } }, { healthPct = 40, manaPct = 100, held = held('health', 7642, 'spirit', 80), level = 100 })
eq(id, 7642, 'a spirit row keeps its look')

-- ---------------------------------------------------------------- unique looks later: a new look joins the list from the table
local before = #P.LIST
eq(P.info(38645), nil, 'no look 38645 yet')
-- (the table is data: a row with a look of its own is a potion of the list; checked on a copy of the loading code)
for _, e in ipairs(P.EVERFULL_ITEMS) do eq(P.info(e.look) ~= nil, true, e.name .. ' is in the list') end
eq(#P.LIST, before, 'shared looks add nothing to the list')

if fails > 0 then os.exit(1) end
print('helper_potions_test: ok')
