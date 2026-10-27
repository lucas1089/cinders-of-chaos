-- luajit helper_potions_test.lua && lua5.3 helper_potions_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'helper_potions.lua')
local P = ChaosHelperPotions
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the Everfull flasks under their client looks (pair 44: one look each, so a row on a look is one server item)
eq(P.everfullOf(38645).server, 32085, 'everfull health: its own look')
eq(P.everfullOf(38649).server, 32086, 'everfull mana: its own look')
eq(P.everfullOf(38653).server, 32268, 'everfull spirit tier 1: its own look')
eq(P.everfullOf(38656).server, 32270, 'everfull supreme spirit: its own look')
eq(P.everfullOf(266), nil, 'the stock Health Potion look is no Everfull any more')
eq(P.isHealth(38645), true, 'an everfull health look is a health potion')
eq(P.isMana(38652), true, 'the everfull supreme mana look is a mana potion')
eq(P.isBoth(38655), true, 'an everfull spirit look is a spirit potion')
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
eq(P.expected(38645, 1000), 180, 'the everfull health look gives the same')
eq(P.expected(38652, 1000), 725, 'everfull supreme mana: avg 675 + 5 % (level 200)')
eq(P.expected(38654, 1000), 300 + 38, 'everfull great spirit, health part: avg 300 + 3.8 %')
eq(P.expected(38654, 1000, true), 150 + 38, 'everfull great spirit, mana part: avg 150 + 3.8 %')
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
  -- what is left is the Everfull flasks (they have looks of their own, the Apothecary does not sell them)
  local left = 0
  for srv, p in pairs(bySrv) do
    eq(p.everfull, true, p.name .. ' is an Everfull flask, not a potion the Apothecary lacks')
    left = left + 1
  end
  eq(left, #P.EVERFULL_ITEMS, 'every helper potion is sold by the Apothecary, but the Everfull flasks')
  eq(n + left, #P.LIST, 'the same number of potions')
end

-- the dropdown: health, then mana, then spirit (health and mana entries), the strongest first
local function keys()
  local t = {}
  for _, e in ipairs(P.options()) do t[#t + 1] = e.key end
  return table.concat(t, ',')
end
eq(keys(), '23375,38648,7643,38647,239,38646,236,266,7876,38645,38652,23373,38651,238,38650,237,268,38649,'
  .. '38656:1,38656:2,23374:1,23374:2,38655:1,38655:2,7642:1,7642:2,38654:1,38654:2,38653:1,38653:2', 'the dropdown order (an Everfull look after the stock potion of its level)')
local seenKey = {}
for _, e in ipairs(P.options()) do
  eq(seenKey[e.key], nil, 'no double entry ' .. e.key)
  seenKey[e.key] = true
end
eq(#P.options(), 30, '18 plain potions (10 health, 8 mana) and six spirit potions with two entries each')


-- ---------------------------------------------------------------- the Everfull table (O246, O247) against the server's config
local cfgFile = io.open('server/data/scripts/chaos/potions_config.lua', 'r') or io.open(dir .. '../../../../server/data/scripts/chaos/potions_config.lua', 'r')
eq(cfgFile ~= nil, true, 'potions_config.lua is readable')
if cfgFile then
  local src = cfgFile:read('*a') cfgFile:close()
  local cfg = load(src)()
  eq(#P.EVERFULL_ITEMS, #cfg.everfull, 'one client row per Everfull of the server')
  eq(#cfg.everfull, 12, 'twelve Everfull potions: three lines of four tiers')
  local looks = {}
  for _, e in ipairs(cfg.everfull) do
    local c
    for _, x in ipairs(P.EVERFULL_ITEMS) do if x.server == e.id then c = x end end
    eq(c ~= nil, true, 'client row for ' .. e.name)
    if c then
      eq(c.slot, e.key, e.name .. ': slot') eq(c.line, e.line, e.name .. ': line')
      eq(c.tier, e.tier, e.name .. ': tier') eq(c.level, e.level, e.name .. ': level')
      eq(c.kind, (e.line == 'spirit') and 'both' or e.key, e.name .. ': kind')
      eq(c.look, e.clientId, e.name .. ': the look is the server node\'s client id')
      eq(c.name:lower(), e.name, e.name .. ': name')
      local h, m = e.health, e.mana
      local roll, rollMana = (c.kind == 'mana') and m or h, (c.kind == 'both') and m or nil
      eq(c.roll[1] .. '-' .. c.roll[2], roll[1] .. '-' .. roll[2], e.name .. ': the fixed roll')
      eq(rollMana and (c.rollMana[1] .. '-' .. c.rollMana[2]) or nil, rollMana and (rollMana[1] .. '-' .. rollMana[2]) or nil, e.name .. ': the mana roll of a spirit flask')
      -- its own look, in the list and in the dropdown, never a stock look
      eq(looks[c.look], nil, e.name .. ': the look is its own') looks[c.look] = true
      local p = P.info(c.look)
      eq(p ~= nil and p.everfull == true and p.server == e.id, true, e.name .. ': in the list under its server id')
      -- the rank (Auto setup) is a stock potion of the list of the same kind
      local r = P.info(c.rank)
      eq(r ~= nil and r.everfull == nil, true, e.name .. ': its rank is a stock potion')
    end
  end
  -- every tier of every line exists once
  local seen = {}
  for _, x in ipairs(P.EVERFULL_ITEMS) do seen[x.line .. x.tier] = (seen[x.line .. x.tier] or 0) + 1 end
  for _, line in ipairs({ 'health', 'mana', 'spirit' }) do
    for tier = 1, 4 do eq(seen[line .. tier], 1, line .. ' tier ' .. tier .. ' once') end
  end
end

-- the dropdown lists the Everfull flasks: each look as a row of its own (a spirit flask as a health and a mana entry)
local inDropdown = {}
for _, e in ipairs(P.options()) do inDropdown[e.key] = true end
for _, x in ipairs(P.EVERFULL_ITEMS) do
  if x.kind == 'both' then
    eq(inDropdown[x.look .. ':1'] and inDropdown[x.look .. ':2'], true, x.name .. ' is in the dropdown (health and mana)')
  else
    eq(inDropdown[tostring(x.look)], true, x.name .. ' is in the dropdown')
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
eq(P.resolve(266, held('health', 38645, 'health', 0), 100), 38645, 'tier 1 held: its own look')
eq(P.resolve(266, held('health', 38646, 'health', 80), 100), 38646, 'great health held: the Health Potion row drinks it')
eq(P.resolve(266, held('health', 38648, 'health', 200), 300), 38648, 'supreme health held')
eq(P.resolve(268, held('mana', 38651, 'mana', 130), 130), 38651, 'ultimate mana held')
eq(P.resolve(268, held('mana', 38650, 'mana', 80), 79), 268, 'below the Everfull level: the stock row (the server would refuse)')
eq(P.resolve(266, held('health', 38646, 'health', 80, false), 100), 266, 'an empty flask is not followed (it would drink a dearer stock potion)')
eq(P.resolve(266, held('health', 38654, 'spirit', 80), 100), 266, 'a spirit flask is chosen by a spirit row, not a health row')
eq(P.resolve(266, held('mana', 38650, 'mana', 80), 100), 266, 'a mana flask does not serve a health row')
eq(P.resolve(266, held('health', 99999, 'health', 0), 100), 266, 'an unknown look is not followed')
eq(P.resolve(268, held('health', 38646, 'health', 80), 100), 268, 'the health slot does not serve the mana row')
eq(P.resolve(239, held('health', 38647, 'health', 130), 200), 239, 'a row on the stock great potion is its own choice')
eq(P.resolve(7876, held('health', 38646, 'health', 80), 100), 7876, 'so is the small potion')
eq(P.resolve('266', held('health', 38646, 'health', 80), '100'), 38646, 'strings from a saved config')
eq(P.resolve(nil, held('health', 38646, 'health', 80), 100), nil, 'nil stays nil')

-- pick: the due row's resolved look is what goes out, and availability is asked for that look
local rows = { { id = 266, percent = 60, priority = 1 }, { id = 268, percent = 50, priority = 1 } }
local asked = {}
local id, kind = P.pick(rows, { healthPct = 40, manaPct = 100, held = held('health', 38646, 'health', 80), level = 100,
  available = function(x) asked[#asked + 1] = x return true end })
eq(id, 38646, 'pick: the follow') eq(kind, 'health', 'pick: still a health potion') eq(asked[1], 38646, 'availability asked for the Everfull look')
id = P.pick(rows, { healthPct = 40, manaPct = 100, held = held('health', 38646, 'health', 80), level = 100,
  available = function(x) return x ~= 38646 end })
eq(id, nil, 'pick: the followed look is not available, nothing else is drunk for that row')
id, kind = P.pick(rows, { healthPct = 100, manaPct = 40, held = { mana = { look = 38650, tier = 2, level = 80, line = 'mana', ready = true } }, level = 100 })
eq(id, 38650, 'pick: mana follows') eq(kind, 'mana', 'pick: mana kind')
id = P.pick(rows, { healthPct = 40, manaPct = 100 })
eq(id, 266, 'pick without a held view: as before')
-- a row on a spirit flask's own look keeps it (the server picks the Everfull of that look)
id = P.pick({ { id = 38654, percent = 60, priority = 1 } }, { healthPct = 40, manaPct = 100, held = held('health', 38654, 'spirit', 80), level = 100 })
eq(id, 38654, 'a spirit row keeps its look')

-- ---------------------------------------------------------------- rows on an Everfull look
-- a row on an Everfull look is that item and nothing else (no follow: only 266 / 268 follow)
for _, x in ipairs(P.EVERFULL_ITEMS) do
  eq(P.resolve(x.look, held(x.slot, 38646, 'health', 80), 300), x.look, x.name .. ': a row on its own look stays')
end
-- a plain upgraded flask is followed to its own look, spirit and mana rows by their slot
eq(P.resolve(266, held('health', 38648, 'health', 200), 300), 38648, 'the Health Potion row drinks the Everfull supreme health look')
eq(P.resolve(268, held('mana', 38652, 'mana', 200), 300), 38652, 'the Mana Potion row drinks the Everfull supreme mana look')
eq(P.resolve(266, held('health', 38645, 'health', 0), 100), 38645, 'tier 1: the Health Potion row drinks its own look')
eq(P.resolve(266, held('health', 38653, 'spirit', 0), 100), 266, 'a spirit flask is not followed by a health row')

-- the dropdown order: (empty) first, then alphabetical, case-insensitive, accents as base letters; selections map by data
local sorted = P.sortOptions({
  { text = 'Ultimate Health Potion', data = '7643' }, { text = '(empty)', data = 0 }, { text = 'everfull Supreme Health Potion', data = '38648' },
  { text = 'Água Potion', data = 'a' }, { text = 'Supreme Health Potion', data = '23375' }, { text = 'Zebra', data = 'z' },
  { text = 'Aguardente', data = 'b' }, { text = 'Great Health Potion', data = '239' },
})
local order = {}
for _, o in ipairs(sorted) do order[#order + 1] = o.data end
eq(table.concat(order, ','), '0,a,b,38648,239,23375,7643,z', 'options: (empty) first, then alphabetical without case and accents')
local real = P.sortOptions((function() local o = { { text = '(empty)', data = 0 } }
  for _, e in ipairs(P.options()) do o[#o + 1] = { text = e.name, data = e.key } end return o end)())
eq(real[1].data, 0, 'the real list: (empty) first')
for i = 3, #real do
  eq(P.sortKey(real[i - 1].text) <= P.sortKey(real[i].text), true, 'the real list is alphabetical at ' .. real[i].text)
end
eq(#real, #P.options() + 1, 'sorting loses no option')
eq(P.sortOptions(nil)[1], nil, 'no options: empty')

if fails > 0 then os.exit(1) end
print('helper_potions_test: ok')
