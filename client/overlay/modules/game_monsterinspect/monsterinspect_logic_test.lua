-- luajit monsterinspect_logic_test.lua && lua5.3 monsterinspect_logic_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'monsterinspect_logic.lua')
local L = MonsterInspectLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(L.OPCODE, 166, 'opcode')
eq(L.numberText(1234567), '1,234,567', 'thousands')
eq(L.numberText(nil), '0', 'nil')

-- chunks
local parts = {}
eq(L.joinPart(parts, '{"a":1}'), '{"a":1}', 'a whole message')
eq(L.joinPart(parts, 'S{"a"'), nil, 'first part')
eq(L.joinPart(parts, 'P:1,'), nil, 'middle part')
eq(L.joinPart(parts, 'E"b":2}'), '{"a":1,"b":2}', 'last part joins')
eq(L.joinPart(parts, 'Eorphan'), nil, 'a last part without a first one')
eq(L.joinPart(parts, ''), nil, 'empty')

-- clicks: Shift + left on a monster only
local function creature(kind)
  local c = { getId = function() return 5 end }
  c.isMonster = function() return kind == 'monster' end
  c.isPlayer = function() return kind == 'player' end
  c.isNpc = function() return kind == 'npc' end
  return c
end
local LEFT, RIGHT = 1, 2
local function mods(ctrl, shift, alt) return { ctrl = ctrl, shift = shift, alt = alt } end
eq(L.shouldInspectClick(LEFT, LEFT, mods(false, true, false), creature('monster')), true, 'shift + left on a monster')
eq(L.shouldInspectClick(RIGHT, LEFT, mods(false, true, false), creature('monster')), false, 'shift + right is Look')
eq(L.shouldInspectClick(LEFT, LEFT, mods(false, false, false), creature('monster')), false, 'a plain left click attacks')
eq(L.shouldInspectClick(LEFT, LEFT, mods(true, true, false), creature('monster')), false, 'ctrl + shift is not ours')
eq(L.shouldInspectClick(LEFT, LEFT, mods(false, true, true), creature('monster')), false, 'alt + shift is not ours')
eq(L.shouldInspectClick(LEFT, LEFT, mods(false, true, false), creature('player')), false, 'a player')
eq(L.shouldInspectClick(LEFT, LEFT, mods(false, true, false), creature('npc')), false, 'an NPC')
eq(L.shouldInspectClick(LEFT, LEFT, mods(false, true, false), nil), false, 'no creature (an item, the ground)')
eq(L.shouldInspectClick(nil, LEFT, mods(false, true, false), creature('monster')), false, 'no button')
eq(L.isMonster({ getId = function() return 1 end, isPlayer = function() return false end, isNpc = function() return false end }), true,
  'a creature object without isMonster that is no player and no NPC')

-- the header
local d = {
  cid = 5, name = 'Slagborer', level = 412, tier = 'rare',
  flags = { { key = 'tier', name = 'Rare' }, { key = 'elite' }, { key = 'boss' } },
  health = { cur = 450, max = 900, pct = 50 },
  family = { cat = 'Other', race = 'blood', diff = 'challenging' },
  mods = { { key = 'blazing', name = 'Blazing', text = 'x' }, { key = 'weird', name = 'Weird' } },
  exp = { base = 450, tier = 4, rate = 2, total = 3600, bonus = 2, rank = 1 },
  resist = { elements = { { name = 'fire', pct = -25 }, { name = 'physical', pct = 10 } }, immune = { 'earth', 'holy' },
    conditions = { 'poison' } },
  armour = { armor = 25, defense = 30, class = 'elite', spell = 25, weapon = 10 },
  attacks = { { name = 'melee', kind = 'melee', element = 'physical', chance = 100, interval = 2000, min = 0, max = 130, range = 1 },
    { name = 'fire', kind = 'ranged', element = 'fire', chance = 20, interval = 2000, min = 100, max = 200, range = 7 },
    { name = 'energy beam', kind = 'spell', element = 'energy', min = 60, max = 120 } },
  abilities = { { kind = 'defence', name = 'healing', min = 50, max = 100, chance = 15 }, { kind = 'defence', name = 'speed', value = 320, seconds = 5 },
    { kind = 'summon', name = 'Ghoul, Skeleton', count = 2 }, { kind = 'flag', name = 'runs', value = 90 } },
  speed = { base = 180, now = 200 },
  loot = { total = 8, bands = { { key = 'Common', n = 3 }, { key = 'Rare', n = 0 } }, tierText = '1 extra loot roll, gear of Magic quality or better',
    locked = 3, rows = { { name = 'Slag Plate', cid = 9001, chance = 0.5, max = 1, band = 'Rare' }, { name = 'Gold Coin', cid = 2148, chance = 80, max = 20, band = 'Common' } } },
  uniques = { { name = 'Slag Crown', cid = 9100, set = true }, { name = 'Boss Blade', cid = 9101, boss = true } },
  areas = { { text = 'near Ashford (underground, floor -1)', count = 12 } },
  bestiary = { kills = 40, stage = 2, th = { 1, 20, 150, 600 }, next = 110 },
}
local h = L.header(d)
eq(h.name, 'Slagborer', 'name')
eq(h.level, 'Level 412', 'level line')
eq(h.flags, 'Rare, Elite, Boss', 'flags')
eq(h.health, 'Health: 450 / 900 (50%)', 'health text')
eq(h.pct, 50, 'bar percent')
eq(h.color, L.COLORS.gold, 'half health is gold')
eq(L.healthColor({ pct = 80 }), L.COLORS.good, 'high health')
eq(L.healthColor({ pct = 10 }), L.COLORS.red, 'low health')
eq(L.healthText({ hidden = true, pct = 40 }), 'Health: 40%', 'hidden health shows the percent only')
eq(L.header({ name = 'Rat' }).level, nil, 'no level line without a level')
eq(L.header({ name = 'Rat' }).flags, nil, 'no flags line without flags')

local sections = L.sections(d)
local byTitle = {}
for _, s in ipairs(sections) do byTitle[s.title] = s end
local order = {}
for _, s in ipairs(sections) do order[#order + 1] = s.title end
eq(table.concat(order, '|'), 'Overview|Experience|Modifiers|Resistances|Defence|Attacks|Abilities|Loot|Unique items and set pieces|Where it lives|Your Bestiary progress', 'section order')
local function rowOf(title, label)
  for _, r in ipairs(byTitle[title].rows) do if r.label == label then return r end end
end
eq(rowOf('Overview', 'Family').value, 'Other', 'family')
eq(rowOf('Overview', 'Type').value, 'Blood', 'race')
eq(rowOf('Overview', 'Difficulty').value, 'Challenging', 'difficulty')
eq(rowOf('Overview', 'Speed').value, '180 (now 200)', 'speed now')
eq(rowOf('Experience', 'Experience').value, '3,600', 'experience total')
eq(rowOf('Experience', 'Rank factor').value, 'x4', 'rank factor')
eq(rowOf('Experience', 'Your experience stage').value, 'x2', 'stage factor')
eq(rowOf('Experience', 'Bestiary entry bonus').value, '+2%', 'bestiary bonus')
eq(rowOf('Experience', 'Bestiary rank bonus').value, '+1%', 'rank bonus')
eq(rowOf('Modifiers', 'Blazing') ~= nil, true, 'a modifier row')
eq(byTitle['Modifiers'].rows[2].note, 'Its hits can set you on fire.', 'its sentence')
eq(#byTitle['Modifiers'].rows, 3, 'a modifier with no sentence has a row only')
eq(rowOf('Resistances', 'Fire').value, '-25% more damage', 'a weakness')
eq(rowOf('Resistances', 'Fire').color, L.COLORS.red, 'a weakness is red')
eq(rowOf('Resistances', 'Physical').value, '+10% less damage', 'a resistance')
eq(rowOf('Resistances', 'Immune to').value, 'Earth, Holy', 'immunities')
eq(rowOf('Resistances', 'Cannot be affected by').value, 'Poison', 'condition immunities')
eq(rowOf('Defence', 'Armour').value, '25', 'flat armour')
eq(rowOf('Defence', 'Armour class').value, 'Elite', 'armour class')
eq(rowOf('Defence', 'Blocks of a typical spell hit').value, '25%', 'spell share')
eq(rowOf('Defence', 'Blocks of a typical weapon hit').value, '10%', 'weapon share')
eq(rowOf('Attacks', 'Melee').value, '0 - 130', 'melee row')
eq(rowOf('Attacks', 'Fire (Fire, range 7)').value, '100 - 200', 'a ranged attack with element and range')
eq(rowOf('Attacks', 'Fire (Fire, range 7)').tip, '20% chance per turn, every 2 s', 'attack tooltip')
eq(rowOf('Attacks', 'Energy beam (Energy)').value, '60 - 120', 'a spell row')
eq(rowOf('Abilities', 'Heals itself').value, '50 - 100', 'heals')
eq(rowOf('Abilities', 'Hastes itself').value, '+320 / 5 s', 'haste')
eq(rowOf('Abilities', 'Summons (up to 2)').value, 'Ghoul, Skeleton', 'summons')
eq(rowOf('Abilities', 'Runs away when hurt').value, 'below 90% health', 'runs')
eq(rowOf('Loot', 'Items in its loot table').value, '8', 'loot total')
eq(rowOf('Loot', 'Slag Plate').value, '0.50%', 'a rare drop')
eq(rowOf('Loot', 'Gold Coin').value, '80% (max 20)', 'a common drop with a count')
eq(rowOf('Loot', 'Gold Coin').item, 2148, 'the item id of the row')
local lootNotes = {}
for _, r in ipairs(byTitle['Loot'].rows) do if r.note then lootNotes[#lootNotes + 1] = r.note end end
eq(lootNotes[1], 'Common 3', 'bands with items')
eq(lootNotes[2], '1 extra loot roll, gear of Magic quality or better', 'the tier line')
eq(lootNotes[3], 'Study this monster in the Bestiary to see more of its loot (stage 3).', 'the locked line')
eq(rowOf('Unique items and set pieces', 'Slag Crown (set piece)') ~= nil, true, 'a set piece')
eq(rowOf('Unique items and set pieces', 'Boss Blade (boss only)') ~= nil, true, 'a boss unique')
eq(rowOf('Where it lives', 'near Ashford (underground, floor -1)').value, '12 spawns', 'a place')
eq(rowOf('Your Bestiary progress', 'Bestiary stage').value, 'Studied', 'stage name')
eq(rowOf('Your Bestiary progress', 'Kills for the next stage').value, '110', 'next stage')

-- a bare result (a stage 0 monster, no entry, nothing known): only what is sent is drawn, nothing is made up
local bare = L.sections({ name = 'Rat', health = { cur = 20, max = 20, pct = 100 }, exp = { base = 5, total = 5 }, mods = {}, attacks = {}, abilities = {},
  uniques = {}, areas = {}, loot = { total = 2, bands = {}, rows = {}, locked = 2 }, resist = { elements = {}, immune = {}, conditions = {} } })
local titles = {}
for _, s in ipairs(bare) do titles[#titles + 1] = s.title end
eq(table.concat(titles, '|'), 'Experience|Resistances|Loot', 'bare sections')
eq(bare[2].rows[1].note, 'No resistances and no weaknesses.', 'no resistances is said')
eq(#L.sections({}), 0, 'an empty result draws nothing')
eq(#L.sections({ attacks = 'bad', abilities = 7, mods = false, loot = 'x', uniques = 1, areas = true, resist = 5, armour = 'x', exp = 'x' }), 0,
  'wrong shapes draw nothing and do not stop the window')

-- refusals
eq(L.deniedText('range'), 'That monster is too far away or out of sight.', 'range')
eq(L.deniedText('rate'), 'You are inspecting too fast. Wait a moment.', 'rate')
eq(L.deniedText('whatever'), 'That monster is not there any more.', 'unknown code')

-- the sentences of the server config all have a client word (the window translates by the modifier's key)
local f = io.open(dir .. '../../../../server/data/scripts/chaos/monster_inspect_config.lua', 'r')
if f then
  local text = f:read('*a')
  f:close()
  local n = 0
  for key, sentence in text:gmatch('\n\t\t([a-z]+) = "([^"]+)"') do
    if sentence:find('^It') then
      local probe = L.sections({ mods = { { key = key, name = key } } })
      if probe[1] and probe[1].rows[2] then
        n = n + 1
        eq(probe[1].rows[2].note, sentence, 'client sentence of ' .. key .. ' equals the server config')
      end
    end
  end
  eq(n >= 18, true, 'the modifier sentences were compared (' .. n .. ')')
end

if fails > 0 then
  print(fails .. ' of ' .. checks .. ' checks failed')
  os.exit(1)
end
print('monsterinspect_logic_test: all ' .. checks .. ' checks passed')
