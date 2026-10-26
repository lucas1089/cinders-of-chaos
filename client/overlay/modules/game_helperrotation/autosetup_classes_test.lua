-- luajit autosetup_classes_test.lua && lua5.3 autosetup_classes_test.lua (from the repository root or this folder)
-- O186: Auto setup / Auto rotation of every class. Owner report 2026-10-24: a Ninja got 2 attack spells in the shooter
-- although all of them were listed. At a high level every one of the 21 classes must get a full rotation (5 attack
-- spells, no repeats, every one an attack spell of the class), and the class's 11 attack spells must all be reachable
-- (a preset or the extras), as check_rotation_kit.py expects. The spell checks are the ones of autorotation_ui.lua's
-- canCastFor: the spell lists the vocation id as the server sends it (also through the client's translateVocation fold),
-- the level is met.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'autorotation_data.lua')
dofile(dir .. 'autorotation.lua')
dofile(dir .. '../game_chaosspells/spellfix.lua')
dofile(dir .. '../game_chaosspells/spelldata.lua')
local A, D = ChaosAutoRotation, ChaosAutoRotationData
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local CLASSES = {
  Mystic = 1, Ranger = 3, Warrior = 4, Elementalist = 5, Deadeye = 7, Juggernaut = 8, Illusionist = 10,
  Thief = 11, Ninja = 12, Samurai = 13, Berserker = 14, Beastmaster = 15, Monk = 17, Shadowfist = 18,
  ['Iron Sage'] = 19, Necromancer = 20, Lich = 21, ['Bone Lord'] = 22, Templar = 23, Inquisitor = 24, Sentinel = 25
}

-- the spells as the client has them: Chaos (spelldata.lua) and the stock ones (server/data/spells/stock_spells.csv)
local entries, attack = {}, {} -- id -> {vocations, level}; class id -> set of attack spell ids
for _, id in pairs(CLASSES) do attack[id] = {} end
local function add(id, level, group, vocations)
  entries[id] = { vocations = vocations, level = level }
  if group == 1 then
    for _, v in ipairs(vocations) do if attack[v] then attack[v][id] = true end end
  end
end
for _, s in ipairs(ChaosSpellData) do add(s.id, s.level, s.group, s.vocations) end
local f = assert(io.open(dir .. '../../../../server/data/spells/stock_spells.csv', 'r'))
local header = true
for line in f:lines() do
  if header then header = false else
    local c = {}
    for field in (line .. ','):gmatch('([^,]*),') do c[#c + 1] = field end
    local voc = {}
    for name in (c[12] or ''):gmatch('[^;]+') do voc[#voc + 1] = assert(CLASSES[name], 'vocation ' .. name) end
    add(tonumber(c[1]), tonumber(c[5]), c[4] == 'attack' and 1 or 0, voc)
  end
end
f:close()

-- the check of autorotation_ui.lua canCastFor (spell's class list, level), with the client's vocation fold
local function canCastFor(voc, level, translate)
  return function(id)
    local s = entries[id]
    if not s then return false end
    return ChaosSpellFix.allowsVocation({ vocations = s.vocations }, voc, translate) and s.level <= level
  end
end

-- the attack spells the rotation model flags utility (Snare Trap, Seeker Mine: cast by hand) or skip (Corpse Explosion needs
-- corpses): in no preset by design (rotation_model.csv flags)
local CAST_BY_HAND = { [99] = true, [100] = true, [185] = true }

local classes = 0
for name, id in pairs(CLASSES) do
  classes = classes + 1
  local want = 0
  for _ in pairs(attack[id]) do want = want + 1 end
  eq(want, 11, name .. ': 11 attack spells in the data')
  -- the rotation at a high level, with and without the client folding ascension ids onto a base class
  for _, translate in ipairs({ false, function(v) return v == 12 and 11 or (v == 13 and 11 or 0) end }) do
    local sel = A.select(id, 2000, canCastFor(id, 2000, translate or function() return 0 end), { topUp = true })
    eq(sel ~= nil, true, name .. ': a rotation')
    if sel then
      eq(#sel.ids, A.MAX_SPELLS, name .. ': ' .. A.MAX_SPELLS .. ' spells in the rotation')
      local seen = {}
      for _, sid in ipairs(sel.ids) do
        eq(seen[sid], nil, name .. ': ' .. sid .. ' twice')
        seen[sid] = true
        eq(attack[id][sid], true, name .. ': spell ' .. sid .. ' is an attack spell of the class')
      end
    end
  end
  -- every attack spell is reachable: in a preset or the extras
  local reach = {}
  local c = D.classes[id]
  for _, p in ipairs(c.presets) do for _, sid in ipairs(p.spells) do reach[sid] = true end end
  for _, sid in ipairs(c.extras or {}) do reach[sid] = true end
  for sid in pairs(attack[id]) do if not CAST_BY_HAND[sid] then eq(reach[sid], true, name .. ': attack spell ' .. sid .. ' reachable by Auto setup') end end
  for sid in pairs(reach) do eq(attack[id][sid], true, name .. ': preset spell ' .. sid .. ' is an attack spell of the class') end
  -- a character that can cast only some (not learned yet) still gets what it can, never fewer than it can cast up to 5
  local low = 0
  for sid in pairs(attack[id]) do if entries[sid].level <= 150 then low = low + 1 end end
  local sel = A.select(id, 150, canCastFor(id, 150, function() return 0 end), { topUp = true })
  eq(sel and #sel.ids or 0, math.min(low, A.MAX_SPELLS), name .. ': level 150 rotation holds what the class can cast')
end
eq(classes, 21, '21 classes')

if fails > 0 then
  print(fails .. ' failed')
  os.exit(1)
end
print('autosetup_classes_test: ' .. checks .. ' checks ok')
