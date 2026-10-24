-- luajit spellbook_classes_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
-- O184/O185: the Spellbook filters of every class. Owner report 2026-10-24: a Ninja with "Learned" + "Attack" saw
-- "0 spells". The list is the server's (spells with a type read from the spell scripts); here it is the Chaos spell data
-- of the client (spelldata.lua) plus the stock attack and healing spells (server/data/spells/stock_spells.csv), the same
-- spells check_attack_counts.py counts, so each of the 21 classes must show its 10 attack spells at a high level.
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local C = dofile(here .. 'spellbook_core.lua')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

-- server vocation ids (docs/CLASSES.md, client/tools/gen_spell_data.py VOC)
local CLASSES = {
  Mystic = 1, Ranger = 3, Warrior = 4, Elementalist = 5, Deadeye = 7, Juggernaut = 8, Illusionist = 10,
  Thief = 11, Ninja = 12, Samurai = 13, Berserker = 14, Beastmaster = 15, Monk = 17, Shadowfist = 18,
  ['Iron Sage'] = 19, Necromancer = 20, Lich = 21, ['Bone Lord'] = 22, Templar = 23, Inquisitor = 24, Sentinel = 25
}
local ATTACK_SPELLS = 10
local GROUP = { attack = 1, healing = 2, support = 3 }

dofile(here .. '../game_chaosspells/spelldata.lua')
local spells = {}
for _, s in ipairs(ChaosSpellData) do
  -- no `type`: the kind falls back to the XML group, as for every spell the server sends without one
  spells[#spells + 1] = { name = s.name, words = s.words, level = s.level, group = s.group, vocations = s.vocations }
end

local f = assert(io.open(here .. '../../../../server/data/spells/stock_spells.csv', 'r'))
local header = true
for line in f:lines() do
  if header then
    header = false
  else
    local c = {}
    for field in (line .. ','):gmatch('([^,]*),') do c[#c + 1] = field end
    local vocations = {}
    for name in (c[12] or ''):gmatch('[^;]+') do
      local id = CLASSES[name]
      assert(id, 'stock spell ' .. c[2] .. ': unknown vocation ' .. name)
      vocations[#vocations + 1] = id
    end
    spells[#spells + 1] = { name = c[2], words = c[3], level = tonumber(c[5]), group = GROUP[c[4]], vocations = vocations }
  end
end
f:close()

local function list(vocation, level, filter, kind)
  local ctx = { vocation = vocation, level = level, magicLevel = level, learned = {} }
  local out = {}
  for _, s in ipairs(spells) do
    if C.matches(s, ctx, filter, '', kind) then out[#out + 1] = s end
  end
  return out
end

local classes = 0
for name, id in pairs(CLASSES) do
  classes = classes + 1
  local attack = list(id, 2000, 'learned', 'attack')
  local support = list(id, 2000, 'learned', 'support')
  local all = list(id, 2000, 'learned', 'all')
  eq(#attack, ATTACK_SPELLS, name .. ' (' .. id .. '): Learned + Attack')
  eq(#attack + #support, #all, name .. ': every learned spell is an attack or a support spell')
  eq(#list(id, 2000, 'vocation', 'attack'), ATTACK_SPELLS, name .. ': My vocation + Attack')
  eq(#list(id, 2000, 'all', 'attack') >= ATTACK_SPELLS, true, name .. ': All spells + Attack')
  eq(#list(id, 2000, 'soon', 'all'), 0, name .. ': nothing is "available soon" at level 2000')
  eq(#list(id, 2000, 'runes', 'all'), 0, name .. ': no rune entries in this data')
  for _, s in ipairs(attack) do eq(C.kindOf(s), 'attack', name .. ' ' .. s.name) end
  -- a level 1 character has the first spells only, never more than the high level one
  eq(#list(id, 1, 'learned', 'attack') <= ATTACK_SPELLS, true, name .. ': level 1')
  -- every attack spell of the class is learned by the time its last one unlocks
  local last = 0
  for _, s in ipairs(attack) do last = math.max(last, s.level) end
  eq(#list(id, last, 'learned', 'attack'), ATTACK_SPELLS, name .. ': all 10 at level ' .. last)
  eq(#list(id, last - 1, 'learned', 'attack'), ATTACK_SPELLS - 1, name .. ': one short at level ' .. (last - 1))
end
eq(classes, 21, 'the 21 classes')

-- a vocation id the data does not know sees no class spell (nothing is silently shown to everyone)
eq(#list(99, 2000, 'learned', 'attack'), 0, 'unknown vocation')

-- the server sends an attack spell with a type; the filter must not need it, and a "damage" type is an attack
eq(C.kindOf({ type = 'damage', group = 3 }), 'attack', 'type damage')
eq(C.kindOf({ type = 'utility', group = 1 }), 'support', 'type utility is a support spell (what the server must not send for an attack spell)')

print('spellbook_classes_test: ' .. n .. ' checks ok')
