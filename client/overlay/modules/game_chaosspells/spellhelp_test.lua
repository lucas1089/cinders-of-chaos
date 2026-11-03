-- luajit / lua5.3, from the repo root: client/overlay/modules/game_chaosspells/spellhelp_test.lua
local dir = (arg and arg[0] or ''):match('^(.*)/[^/]*$') or '.'
dofile(dir .. '/spellhelp.lua')
local H = ChaosSpellHelp
local function tr(s, ...) if select('#', ...) > 0 then return string.format(s, ...) end return s end
local function eq(a, b, msg)
  assert(#a == #b, msg .. ': count ' .. #a .. ' ~= ' .. #b .. ' (' .. table.concat(a, ' / ') .. ')')
  for i = 1, #a do assert(a[i] == b[i], msg .. ': line ' .. i .. ' ' .. tostring(a[i]) .. ' ~= ' .. tostring(b[i])) end
end

-- the spellbook's server entry
eq(H.lines({ name = 'Witchfire Bolt', type = 'damage', target = 'single', element = 'fire', group = 'attack',
  cooldown = 7000, groupCooldown = 2000 }, tr), {
  'Attack: deals damage to monsters.',
  'Single target: hits the creature you attack.',
  'Fire: monsters weak to it take more, monsters strong against it take less.',
  'Cooldown: you can cast it again after 7 s.',
  'Attack group: your other attack spells wait 2 s after it.',
}, 'spellbook attack')
eq(H.lines({ type = 'heal', target = 'self', element = 'holy', group = 'healing', cooldown = 1500, groupCooldown = 1000 }, tr), {
  'Healing: gives you health back.',
  'Self: works on you.',
  'Cooldown: you can cast it again after 1.5 s.',
  'Healing group: your other healing spells wait 1 s after it.',
}, 'heal: no element line')
eq(H.lines({ type = 'buff', target = 'self', group = 'support', groupCooldown = 2000 }, tr), {
  'Support: makes you stronger or faster for a while.',
  'Self: works on you.',
  'Group cooldown: the other spells of its group wait 2 s after it.',
}, 'buff')
eq(H.lines({ type = 'damage', target = 'front' }, tr), {
  'Attack: deals damage to monsters.', 'In front: hits the tiles in front of you, turn to aim it.' }, 'front')

-- the client entry (spelldata.lua shape and the helper's stock shape)
eq(H.lines({ group = 1, groupCooldown = 2000, cooldown = 4000, areaShape = 'around', element = 'ice' }, tr), {
  'Attack: deals damage to monsters.',
  'Around you: hits every monster next to you.',
  'Ice: monsters weak to it take more, monsters strong against it take less.',
  'Cooldown: you can cast it again after 4 s.',
  'Attack group: your other attack spells wait 2 s after it.',
}, 'client attack')
eq(H.lines({ group = { [2] = 1000 }, exhaustion = 1000, needTarget = false }, tr), {
  'Healing: gives you health back.',
  'Cooldown: you can cast it again after 1 s.',
  'Healing group: your other healing spells wait 1 s after it.',
}, 'stock heal group table')
assert(H.where({ areaShape = 'circle' }) == 'area' and H.where({ areaShape = 'wave' }) == 'front', 'shapes')
assert(H.where({ needTarget = true }) == 'single', 'needTarget')
assert(#H.lines({}, tr) == 0 and #H.lines(nil, tr) == 0, 'nothing known')

-- the tooltip rule: short without Alt plus the hint, the lines with Alt, unchanged when nothing is known
local spell = { type = 'damage', target = 'area' }
assert(H.tooltip('Spell', spell, false, tr) == 'Spell\nHold Alt for what this spell does.', 'hint')
assert(H.tooltip('Spell', spell, true, tr) == 'Spell\nAttack: deals damage to monsters.\nArea: hits every monster in its area.', 'alt')
assert(H.tooltip('Spell', {}, false, tr) == 'Spell', 'no help, no hint')

-- every Chaos spell of spelldata.lua says what it is for and where it hits
dofile(dir .. '/spelldata.lua')
local n = 0
for _, s in ipairs(ChaosSpellData) do
  n = n + 1
  assert(H.kind(s), 'no kind for ' .. tostring(s.name))
  assert(H.where(s), 'no target for ' .. tostring(s.name))
end
assert(n > 50, 'spells read: ' .. n)
print('spellhelp_test: ok (' .. n .. ' spells)')
