-- luajit spellinfo_logic_test.lua && lua5.3 spellinfo_logic_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'spellinfo_logic.lua')
local I = ChaosHelperSpellInfo
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- a tr stub that returns the text (format arguments applied), and a pt-BR one
local function plain(text, ...)
  if select('#', ...) > 0 then return string.format(text, ...) end
  return text
end
local PT = {
  ['%s mana'] = '%s de mana', ['Single target'] = 'Alvo único', ['Area'] = 'Área', ['AOE'] = 'AOE', ['Self'] = 'Em si',
  ['Target'] = 'Alvo', ['Mana'] = 'Mana', ['Cooldown'] = 'Recarga', ['Group cooldown: %s'] = 'Recarga do grupo: %s',
  ['Spell range'] = 'Alcance', ['%d tiles'] = '%d casas', ['Level'] = 'Nível', ['Element'] = 'Elemento',
  ['Group'] = 'Grupo', ['Fire'] = 'Fogo', ['Ice'] = 'Gelo', ['Attack'] = 'Ataque', ['Healing'] = 'Cura',
  ['Support'] = 'Suporte', ['circle'] = 'círculo', ['around'] = 'ao redor', ['line'] = 'linha', ['wave'] = 'onda',
  ['of your maximum'] = 'do seu máximo', ['Spell: %s\nWords: %s'] = 'Magia: %s\nPalavras: %s',
}
local function pt(text, ...)
  local t = PT[text] or text
  if select('#', ...) > 0 then return string.format(t, ...) end
  return t
end

local single = { name = 'Witchfire Bolt', words = 'kah pyr vesh', level = 20, mana = 40, group = { [1] = 2000 },
  exhaustion = 7000, needTarget = true, range = 5, areaShape = 'single', element = 'fire' }
local circle = { name = 'Arrowstorm', words = 'drai sag vex', level = 220, mana = 85, group = { [1] = 2000 },
  exhaustion = 10000, needTarget = true, range = 7, areaShape = 'circle', areaSize = 2, element = 'ice' }
local around = { name = 'Blade Flurry', mana = 70, exhaustion = 4000, areaShape = 'around', areaSize = 1 }
local line = { name = 'Rift Cleaver', mana = 55, exhaustion = 11000, areaShape = 'line', areaSize = 6 }
local wave = { name = 'Shield Wave', mana = 60, exhaustion = 2500, areaShape = 'wave', areaSize = 3, areaWidth = 3 }
local selfy = { name = 'Haste', mana = 60, exhaustion = 22000, group = { [3] = 2000 }, areaShape = 'self' }

-- single target
eq(I.compact(single, plain), '40 mana | Single target | 7 s', 'single compact')
local kind, label = I.area(single, plain)
eq(kind, 'single', 'single kind')
eq(label, '', 'single has no label')
-- area shapes
eq(I.compact(circle, plain), '85 mana | AOE circle 2 | 10 s', 'circle compact')
eq(I.compact(around, plain), '70 mana | AOE around 1 | 4 s', 'around compact')
eq(I.compact(line, plain), '55 mana | AOE line 6 | 11 s', 'line compact')
eq(I.compact(wave, plain), '60 mana | AOE wave 3x3 | 2.5 s', 'wave compact')
eq(I.compact({ areaShape = 'wave', mana = 10 }, plain), '10 mana | AOE wave', 'wave without size')
eq(I.compact(selfy, plain), '60 mana | Self | 22 s', 'self compact')
-- the list row text
eq(I.optionText('Arrowstorm', circle, plain), 'Arrowstorm   85 mana | AOE circle 2 | 10 s', 'option text')
eq(I.optionText('Mystery', {}, plain), 'Mystery', 'no data: only the name')
eq(I.optionText('Mystery', nil, plain), 'Mystery', 'no entry: only the name')

-- missing fields are left out silently
eq(I.compact({ mana = 30 }, plain), '30 mana', 'mana only')
eq(I.compact({ exhaustion = 3000 }, plain), '3 s', 'cooldown only')
eq(I.compact({}, plain), '', 'empty entry')
eq(#I.lines({}, plain), 0, 'no lines for an empty entry')
eq(I.tooltip({}, plain), 'Spell: \nWords: ', 'tooltip of an empty entry is the name block')
-- a stock entry: the target it needs, the matrix of a beam
eq(I.compact({ mana = 20, needTarget = true, exhaustion = 2000 }, plain), '20 mana | Single target | 2 s', 'stock single')
eq(I.compact({ mana = 20, range = 3 }, plain), '20 mana | Single target', 'stock range means a target')
eq(I.compact({ mana = 20, directional = true }, plain), '20 mana | AOE wave', 'stock wave')
eq(I.compact({ mana = 20, area = { { 1, 1, 1 }, { 1, 3, 1 }, { 1, 1, 1 } } }, plain), '20 mana | AOE', 'stock matrix')
eq(I.compact({ mana = 20, area = { { 3 } } }, plain), '20 mana', 'one tile is no area')
-- a share of the maximum mana
eq(I.compact({ manaPercent = 12 }, plain), '12% mana', 'mana percent')
eq(I.lines({ manaPercent = 12 }, plain)[1], 'Mana: 12% of your maximum', 'mana percent line')

-- the tooltip, English
local lines = I.lines(circle, plain)
eq(table.concat(lines, '\n'), table.concat({ 'Mana: 85', 'Target: Area (circle 2)', 'Cooldown: 10 s',
  'Group cooldown: 2 s', 'Spell range: 7 tiles', 'Level: 220', 'Element: Ice', 'Group: Attack' }, '\n'), 'circle lines')
eq(I.tooltip(single, plain), 'Spell: Witchfire Bolt\nWords: kah pyr vesh\nMana: 40\nTarget: Single target\nCooldown: 7 s\n' ..
  'Group cooldown: 2 s\nSpell range: 5 tiles\nLevel: 20\nElement: Fire\nGroup: Attack', 'single tooltip')
-- the self spell has no range line and says Self
eq(table.concat(I.lines(selfy, plain), '|'), 'Mana: 60|Target: Self|Cooldown: 22 s|Group cooldown: 2 s|Group: Support', 'self lines')
-- heal group
eq(I.kind({ group = { [2] = 1000 } }), 'healing', 'healing kind')
eq(I.kind({ group = { [4] = 2000 } }), 'attack', 'special counts as attack')
eq(I.kind({}), nil, 'no group no kind')

-- pt-BR through a tr stub
eq(I.compact(single, pt), '40 de mana | Alvo único | 7 s', 'pt single')
eq(I.compact(circle, pt), '85 de mana | AOE círculo 2 | 10 s', 'pt circle')
eq(I.compact(wave, pt), '60 de mana | AOE onda 3x3 | 2.5 s', 'pt wave')
eq(I.compact(selfy, pt), '60 de mana | Em si | 22 s', 'pt self')
eq(table.concat(I.lines(circle, pt), '\n'), table.concat({ 'Mana: 85', 'Alvo: Área (círculo 2)', 'Recarga: 10 s',
  'Recarga do grupo: 2 s', 'Alcance: 7 casas', 'Nível: 220', 'Elemento: Gelo', 'Grupo: Ataque' }, '\n'), 'pt circle lines')
eq(I.tooltip(single, pt):match('^[^\n]*\n[^\n]*'), 'Magia: Witchfire Bolt\nPalavras: kah pyr vesh', 'pt tooltip head')
-- the default tr: the global one when there is one
tr = function(text, ...) return '<' .. plain(text, ...) .. '>' end
eq(I.compact({ needTarget = true }, nil), '<Single target>', 'global tr')
tr = nil
eq(I.compact({ needTarget = true }, nil), 'Single target', 'identity tr without a global')

-- every spell of the generated table: no error, an attack spell says where it hits, a known shape has its label
dofile(dir .. '../game_chaosspells/spelldata.lua')
local attacks, areas = 0, 0
for _, sp in ipairs(ChaosSpellData) do
  local text = I.compact(sp, plain)
  local has = text ~= ''
  eq(has, true, sp.name .. ' has a compact text')
  eq(#I.tooltip(sp, pt) > 0, true, sp.name .. ' has a tooltip')
  if sp.group == 1 then
    attacks = attacks + 1
    local kind = I.area(sp, plain)
    eq(kind ~= nil, true, sp.name .. ' (attack) says single, area or self')
    if kind == 'area' then areas = areas + 1 end
  end
  if sp.areaShape == 'circle' or sp.areaShape == 'around' or sp.areaShape == 'line' then
    eq(sp.areaSize ~= nil and sp.areaSize > 0, true, sp.name .. ' has a size')
  end
end
eq(attacks > 40, true, 'attack spells counted')
eq(areas > 10, true, 'area attack spells counted')

if fails > 0 then os.exit(1) end
print('spellinfo_logic_test ok')
