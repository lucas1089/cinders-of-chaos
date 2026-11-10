-- luajit / lua5.3, from the repo root: client/overlay/modules/game_itemtooltip/itemhelp_test.lua
local dir = (arg and arg[0] or ''):match('^(.*)/[^/]*$') or '.'
dofile(dir .. '/itemhelp.lua')
local H = ItemTooltipHelp
local function tr(s, ...) if select('#', ...) > 0 then return string.format(s, ...) end return s end
local function has(list, text)
  for _, l in ipairs(list) do if l == text then return true end end
  return false
end
local function count(list, pattern)
  local n = 0
  for _, l in ipairs(list) do if l:find(pattern, 1, true) then n = n + 1 end end
  return n
end

-- a rare item with tiers, a bound modifier, two absorbs (one line), leech, quality and sockets
local tip = {
  rarityName = 'Rare', level = 40, quality = { q = 6, cap = 20 },
  base = { { k = 'armor', l = 'Armour', v = 12 }, { k = 'weight', l = 'Weight', v = 3 } },
  mods = {
    { k = 'chaos_mod_dodge', g = 'chaos', t = 'Dodge +3%', tr = 5, sd = 'p', lo = 2, hi = 4 },
    { k = 'rarity_fireAbsorb', g = 'absorb', t = 'Fire +4%', tr = 3, sd = 's', bd = true },
    { k = 'rarity_iceAbsorb', g = 'absorb', t = 'Ice +2%', tr = 2, sd = 's' },
    { k = 'rarity_lifeLeechChance', g = 'special', t = 'Life Chance +5%, Life Amount +5%', tr = 1, sd = 's' },
  },
  sockets = { count = 2, list = {} },
}
local lines = H.lines(tip, tr)
assert(has(lines, 'Rare: the rarity. Rarer items roll more modifiers.'), 'rarity')
assert(has(lines, 'Item Level: a higher item level can roll higher tiers.'), 'item level')
assert(has(lines, 'Quality: makes the base stats stronger.'), 'quality')
assert(has(lines, 'Armour: lowers the physical damage you take.'), 'base armour')
assert(has(lines, 'T5: the tier, T1 weak to T8 best.'), 'best tier named')
assert(has(lines, 'Bound: orbs do not change this modifier.'), 'bound')
assert(has(lines, 'Dodge: a chance to avoid an attack completely.'), 'chaos key without prefix')
assert(has(lines, 'Life Leech: heals you by a part of the damage you deal.'), 'leech by key, any case')
assert(count(lines, 'Absorb:') == 1, 'two absorbs, one line')
assert(has(lines, 'Sockets: put gems in them for extra bonuses.'), 'sockets')
assert(has(lines, '[low-high]: the range this modifier can roll in.'), 'range')
-- reading order: rarity before tier before the modifiers
local function at(text) for i, l in ipairs(lines) do if l == text then return i end end end
assert(at('Rare: the rarity. Rarer items roll more modifiers.') < at('T5: the tier, T1 weak to T8 best.'), 'order 1')
assert(at('T5: the tier, T1 weak to T8 best.') < at('Dodge: a chance to avoid an attack completely.'), 'order 2')

-- a unique, a set piece, a plain item, rubbish
assert(H.lines({ unique = { name = 'X' } }, tr)[1]:find('^Unique:'), 'unique')
assert(H.lines({ unique = { name = 'X', set = {} } }, tr)[1]:find('^Set:'), 'set unique')
assert(#H.lines({ name = 'stone' }, tr) == 0, 'nothing to explain')
assert(#H.lines(nil, tr) == 0, 'nil tip')
assert(H.modLine({ k = 'unknown_key' }, H.modTexts(tr), H.groupTexts(tr)) == nil, 'unknown key, no group')
assert(H.modLine({ k = 'rarity_swordSkill', g = 'skill' }, H.modTexts(tr), H.groupTexts(tr)):find('^Skill bonus'), 'group fallback')
assert(H.lines({ mods = { { k = 'chaos_mod_deathblast', pw = true, t = 'Death Blast: ...' } } }, tr)[1]:find('^Power:'), 'power')

-- O461: the critical pair is two modifiers, the leech and the other new ones have lines of their own
do
  local tip2 = {
    rarityName = 'Rare', level = 120,
    mods = {
      { k = 'rarity_criticalHitChance', g = 'single', t = 'Critical Strike Chance +5%', tr = 4, sd = 'p' },
      { k = 'rarity_criticalHitAmount', g = 'single', t = 'Critical Strike Damage +25%', tr = 4, sd = 'p' },
      { k = 'chaos_mod_lifeleechw', g = 'chaos', t = 'Life Leech with Weapon +3.0%', tr = 5, sd = 's' },
      { k = 'chaos_mod_maxlife', g = 'chaos', t = 'Maximum Life +200', tr = 6, sd = 'p' },
      { k = 'chaos_mod_spelldamage', g = 'chaos', t = 'Spell Damage +20%', tr = 5, sd = 'p' },
    },
  }
  local l2 = H.lines(tip2, tr)
  assert(has(l2, 'Critical Strike Chance: your hits can be critical hits that deal more damage.'), 'critical chance')
  assert(has(l2, 'Critical Strike Damage: your critical hits deal more damage.'), 'critical damage: its own line')
  assert(has(l2, 'Life Leech with Weapon: a share of the damage of your weapon attacks comes back as health.'), 'weapon leech')
  assert(has(l2, 'Maximum Life: adds to your maximum health.'), 'maximum life')
  assert(has(l2, 'Spell Damage: your spells and wand hits deal more damage.'), 'spell damage')
  for _, k in ipairs({ 'lifeleech', 'manaleech', 'manaleechw', 'maxmana', 'manaregen', 'strength', 'dexterity', 'intelligence',
      'weapondamage' }) do
    assert(H.modLine({ k = 'chaos_mod_' .. k }, H.modTexts(tr), H.groupTexts(tr)), 'a help line for ' .. k)
  end
end

-- O464: the defence rows have help lines of their own (a resistance names the damage types of its group)
do
  local mods, groups = H.modTexts(tr), H.groupTexts(tr)
  local function line(k) return H.modLine({ k = 'chaos_mod_' .. k }, mods, groups) end
  assert(line('armour'):find('^Armour:'), 'armour')
  assert(line('spellsuppress'):find('^Spell Suppression:'), 'spell suppression')
  assert(line('fireres'):find('fire damage'), 'fire resistance')
  assert(line('coldres'):find('ice, water and drowning'), 'cold resistance names its types')
  assert(line('lightningres'):find('energy, holy and arcane'), 'lightning resistance names its types')
  assert(line('chaosres'):find('earth, death, life drain and mana drain'), 'chaos resistance names its types')
  assert(line('allres'):find('fire, cold and lightning'), 'all resistances')
  assert(line('block'):find('block an attack'), 'block')
  assert(line('physpen'):find('armour'), 'physical penetration ignores armour now')
  assert(line('elepen'):find('resistance'), 'elemental penetration ignores resistance')
  assert(H.modLine({ k = 'rarity_physicalAbsorb', g = 'absorb' }, mods, groups):find('^Physical Reduction:'), 'the physical row is its own line')
  assert(H.modLine({ k = 'rarity_fireAbsorb', g = 'absorb' }, mods, groups):find('resistance of its group'), 'an old absorb counts toward its group')
end

-- every modifier the server can roll has a line: the Chaos ones by key, the engine ones by key or group
local root = dir .. '/../../../..'
local function read(path)
  local f = assert(io.open(root .. '/' .. path, 'r'), path)
  local s = f:read('*a')
  f:close()
  return s
end
local mods, groups = H.modTexts(tr), H.groupTexts(tr)
local n = 0
for _, path in ipairs({ 'server/data/lib/chaos_item_mods.lua', 'server/data/lib/chaos_energy_shield.lua',
    'server/data/lib/chaos_archery_config.lua' }) do
  for key in read(path):gmatch('{key = "([%w_]+)", label = "') do
    n = n + 1
    assert(H.modLine({ k = 'chaos_mod_' .. key, g = 'chaos' }, mods, groups), 'no help line for modifier ' .. key)
  end
end
local crafting = read('server/data/lib/chaos_crafting.lua')
for key in crafting:gmatch('{key = "(rarity_[%w_]+)"') do
  n = n + 1
  local g = key:find('Absorb$') and 'absorb' or key:find('Skill$') and 'skill' or key:find('^rarity_element') and 'element'
    or 'special'
  assert(H.modLine({ k = key, g = g }, mods, groups), 'no help line for modifier ' .. key)
end
assert(n > 60, 'modifier lists read: ' .. n)
print('itemhelp_test: ok (' .. n .. ' modifiers)')
