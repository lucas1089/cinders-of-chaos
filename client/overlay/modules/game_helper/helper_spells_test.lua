-- luajit helper_spells_test.lua && lua5.3 helper_spells_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local modules = dir .. '../'
dofile(modules .. 'game_chaosspells/spelldata.lua') -- ChaosSpellData, ChaosSpellNames
dofile(modules .. 'game_chaosspells/spellfix.lua')  -- ChaosSpellFix.allowsVocation
dofile(modules .. 'game_helpersupport/supportspells.lua')
dofile(modules .. 'game_helpertimers/helpertimers.lua')
dofile(dir .. 'helper_spells.lua')
local S = ChaosHelperSpells
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- the channel is the server's (ChaosHelperTimers)
for _, g in ipairs({ { 1 }, { 2 }, { 3 }, { 4 }, { 1, 3 }, { 2, 3 }, { 8 }, {} }) do
  local spell = { group = {} }
  for _, id in ipairs(g) do spell.group[id] = 2000 end
  eq(S.channel(spell), ChaosHelperTimers.castChannel(spell.group), 'channel of groups ' .. table.concat(g, ','))
end
eq(S.channel({ group = 2 }), 'heal', 'a group number')

-- ---------------------------------------------------------------- a fixture table in the client's form
local function entry(id, name, words, group, vocations, extra)
  local e = { id = id, name = name, words = words, level = 1, mana = 20, group = { [group] = 2000 }, vocations = vocations,
    range = 0, needTarget = false }
  for k, v in pairs(extra or {}) do e[k] = v end
  return e
end
local table_ = {
  Strike = entry(10, 'Strike', 'kah one', 1, { 4 }, { range = 3, needTarget = true }),
  Wave = entry(11, 'Wave', 'kah two', 1, { 4, 8 }, { level = 30 }),
  Mend = entry(12, 'Mend', 'saen one', 2, { 4 }),
  Greater = entry(13, 'Greater Mend', 'saen two', 2, { 4 }, { level = 50 }),
  Haste = entry(6, 'Haste', 'utani hur', 3, { 4 }),
  Ward = entry(14, 'Ward', 'tor one', 3, { 4 }),
  Lantern = entry(15, 'Lantern', 'vael lyss', 3, { 4 }),
  Rope = entry(16, 'Ghost Rope', 'ash gor', 3, { 4 }),
  Portal = entry(254, 'Town Portal', 'ash domh', 3, { 4 }),
  Missing = entry(17, 'Missing', 'x y', 1, { 4 }, { notOnServer = true }),
  Typed = entry(18, 'Typed', 'exiva', 3, { 4 }, { parameter = true }),
  Rune = entry(19, 'Rune', 'adori', 1, { 4 }, { type = 'Rune' }),
  Other = entry(20, 'Other class', 'kah three', 1, { 17 }),
  Vigil = entry(162, 'Vigil of Clarity', 'tor vigil', 3, { 4 }),
}
local ctx = { vocation = 4, level = 20 }

local function names(kind, c)
  local out = {}
  for _, e in ipairs(S.list(kind, table_, c or ctx)) do out[#out + 1] = e.name end
  return table.concat(out, '|')
end
eq(names('attack'), 'Strike', 'attack picker: the class, the level, no wave of level 30')
eq(names('attack', { vocation = 4, level = 30 }), 'Strike|Wave', 'level 30 brings the wave')
eq(names('attack', { vocation = 8, level = 30 }), 'Wave', 'another class of the wave')
eq(names('heal'), 'Mend', 'healing picker')
eq(names('heal', { vocation = 4, level = 50 }), 'Greater Mend|Mend', 'level 50 brings the greater heal')
eq(names('haste'), 'Haste', 'haste picker')

-- utilities, toggles, parameters, runes, spells the server lacks never appear in any picker
for _, kind in ipairs({ 'attack', 'heal', 'training', 'haste' }) do
  local list = names(kind, { vocation = 4, level = 1000 })
  for _, bad in ipairs({ 'Lantern', 'Ghost Rope', 'Town Portal', 'Missing', 'Typed', 'Rune', 'Vigil', 'Other class' }) do
    eq(list:find(bad, 1, true), nil, bad .. ' is not in the ' .. kind .. ' picker')
  end
end
eq(S.eligible('attack', table_.Portal, ctx), false, 'town portal is not an attack spell')
local ok, why = S.castable(table_.Portal, ctx)
eq(ok, false, 'town portal is never cast')
eq(why, 'utility', 'because it is a utility')
ok, why = S.castable(table_.Lantern, ctx)
eq(why, 'utility', 'the lantern by its name')

-- a spell the character has not learnt
local known = { [10] = true }
eq(S.castable(table_.Strike, { vocation = 4, level = 20, known = function(id) return known[id] end }), true, 'learnt')
ok, why = S.castable(table_.Mend, { vocation = 4, level = 20, known = function(id) return known[id] end })
eq(why, 'unknown', 'not learnt')

-- ---------------------------------------------------------------- the real Chaos data, every class
local lines = { 1, 3, 4, 5, 7, 8, 10, 11, 12, 13, 14, 15, 17, 18, 19, 20, 21, 22, 23, 24, 25 }
local utilityIds = { [254] = true, [232] = true, [179] = true, [255] = true, [161] = true, [162] = true }
for _, voc in ipairs(lines) do
  local attack, heal = 0, 0
  for _, s in ipairs(ChaosSpellData) do
    local entryS = { id = s.id, name = s.name, words = s.words, level = s.level, mana = s.mana,
      group = { [s.group] = s.groupCooldown }, needTarget = s.needTarget, range = s.range, vocations = s.vocations }
    local c = { vocation = voc, level = 1000 }
    if S.eligible('attack', entryS, c) then
      attack = attack + 1
      eq(utilityIds[s.id], nil, s.name .. ' (utility) offered as attack to ' .. voc)
    end
    if S.eligible('heal', entryS, c) then
      heal = heal + 1
      eq(utilityIds[s.id], nil, s.name .. ' (utility) offered as heal to ' .. voc)
    end
  end
  if attack == 0 then print('FAIL class ' .. voc .. ' has no attack spell'); fails = fails + 1 end
end

-- the stock utilities under their Chaos words are never offered (ChaosSpellNames)
for stock, e in pairs(ChaosSpellNames) do
  if stock == 'utevo lux' or stock == 'utevo gran lux' or stock == 'utevo vis lux' or stock == 'exani tera' then
    local spell = { id = 900, name = e.name, words = e.words, level = 1, group = { [3] = 2000 }, vocations = { 4 } }
    ok, why = S.castable(spell, { vocation = 4, level = 100 })
    eq(ok, false, e.name .. ' (' .. e.words .. ') is never cast')
  end
end

-- the strongest haste the class can cast
local hastes = { [39] = entry(39, 'Strong Haste', 'utani gran hur', 3, { 4 }, { level = 20 }), [6] = table_.Haste }
local function spellOf(id) return hastes[id] end
eq(S.bestHaste(spellOf, { vocation = 4, level = 20 }), 6, 'Haste: the retired strong haste (39) is never offered')
eq(S.bestHaste(spellOf, { vocation = 4, level = 10 }), 6, 'haste below it')
eq(S.bestHaste(spellOf, { vocation = 17, level = 100 }), nil, 'a class without the haste')

if fails > 0 then os.exit(1) end
print('helper_spells_test: ok')
