-- luajit treespellmods_test.lua && lua5.3 treespellmods_test.lua (CI runs every client module test from the repo root)
-- The words of the spell modifier masteries (treespellmods.lua, O451): every effect of the mastery nodes that carries the tree
-- stat spellMod has a row and a text, and every row is pinned to the server's config (the spell, the support, the numbers of the
-- free support: Common rune, 75%) when the server data is in the checkout.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'treespellmods.lua')
dofile(dir .. 'treedata/nodes.lua')
local T = TreeSpellMods
local fails, count = 0, 0
local function eq(a, b, what)
  count = count + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function has(s, part, what)
  count = count + 1
  if not tostring(s):find(part, 1, true) then print('FAIL ' .. what .. ': "' .. tostring(s) .. '" has no "' .. part .. '"'); fails = fails + 1 end
end

-- the tree: every spellMod effect of a mastery node has a row; the row ids are 1..20
local nodes = getTreeNodes()
local seen, n = {}, 0
for id, node in pairs(nodes) do
  if node.isMastery then
    for i, effect in ipairs(node.masteries or {}) do
      local sm = effect.customStats and effect.customStats.spellMod
      if sm then
        n = n + 1
        seen[sm] = true
        eq(type(T.rows[sm]), 'table', 'node ' .. id .. ' effect ' .. i .. ' has a row')
        eq(type(T.text(sm)), 'string', 'node ' .. id .. ' effect ' .. i .. ' has a text')
        local one = 0
        for _ in pairs(effect.customStats) do one = one + 1 end
        eq(one, 1, 'node ' .. id .. ' effect ' .. i .. ' is the spell modifier and nothing else')
      end
    end
  end
end
eq(n, 20, '20 spell modifier effects in the tree')
for id in pairs(T.rows) do eq(seen[id], true, 'row ' .. id .. ' is used by a mastery effect') end
eq(T.text(0), nil, 'no choice 0'); eq(T.text(21), nil, 'no choice 21'); eq(T.text('x'), nil, 'no text for a word'); eq(T.text(nil), nil, 'nil')

-- the sentences
has(T.text(1), 'Gorehook forks to 1 more enemy within 3 sqm for 26% of the hit', 'fork text')
has(T.text(2), '11% chance that its hits strike again for 50%', 'echo text')
has(T.text(3), 'enemies it missed within 1 sqm take 26% of its hit', 'breadth text')
has(T.text(4), 'enemies next to the target take 15% of the hit', 'shatter text')
has(T.text(5), '+3 increased damage while it is cast', 'dawnbrand text (O473: a pool entry)')
has(T.text(6), 'take +2% damage from everyone for 4 s', 'hex text')
has(T.text(8), '+3 increased damage while it is cast', 'stormbrand text')
has(T.text(13), '+3 increased damage while it is cast', 'gravebrand text')
has(T.text(17), 'its cooldown is 4% shorter', 'quickening text')
local DAMAGE = {dawnbrand = true, gravebrand = true, stormbrand = true}
for id, row in pairs(T.rows) do
  if DAMAGE[row.support] then
    has(T.text(id), 'increased damage', 'row ' .. id .. ' says that the effect is increased damage (O473)')
  else
    has(T.text(id), 'A reduced', 'row ' .. id .. ' says that the effect is reduced')
  end
  has(T.text(id), row.spell, 'row ' .. id .. ' names the spell')
end

-- the server's config: the same spells, supports and numbers
local base = dir .. '../../../../server/data/'
local f = io.open(base .. 'lib/chaos_spell_masteries_config.lua', 'r')
if f then
  f:close()
  local cfg = dofile(base .. 'lib/chaos_spell_masteries_config.lua')
  local poolEach = dofile(base .. 'scripts/chaos/damage_pool_config.lua').sources.masteries.each
  local supports = dofile(base .. 'lib/chaos_supports_config.lua')
  local byKey = {}
  for _, s in ipairs(supports.supports) do byKey[s.key] = s end
  -- the rule of ChaosSupports.freeEffect: the rune's numbers at the tier, the reduced fields cut to the strength, rounded down
  local function free(key)
    local s = byKey[key]
    local e = {value = s.values[cfg.tier], value2 = s.values2 and s.values2[cfg.tier] or nil}
    for _, field in ipairs(cfg.reduce[key]) do
      e[field] = math.max(1, math.floor(e[field] * cfg.strength / 100 + 1e-6))
    end
    return e
  end
  local names = {}
  for _, s in ipairs(supports.supports) do names[s.key] = s.name end
  eq(#cfg.choices, 20, 'the server has 20 choices')
  for _, c in ipairs(cfg.choices) do
    local row = T.rows[c.id]
    eq(row.support, c.support, c.name .. ': the support')
    local e = cfg.damage and cfg.damage[c.support] and {value = poolEach} or free(c.support)
    if cfg.damage and cfg.damage[c.support] then
      eq(row.a, poolEach, c.name .. ': the pool entry (+3 raw, O473)')
    elseif c.support == 'fork' or c.support == 'breadth' then
      eq(row.a, e.value, c.name .. ': the number of enemies or the radius'); eq(row.b, e.value2, c.name .. ': the share')
    elseif c.support == 'echo' then
      eq(row.a, e.value, c.name .. ': the chance'); eq(row.b, e.value2, c.name .. ': the second strike')
    else
      eq(row.a, e.value, c.name .. ': the number')
    end
    if not (cfg.damage and cfg.damage[c.support]) then
      has(T.text(c.id), names[c.support], c.name .. ': the text names the support')
    end
    -- the spell's name from the Chaos spell files
  end
  -- the spell names against the spell data of the server (spells_chaos.xml), by id
  local xml = io.open(dir .. '../../../../server/data/spells/chaos/spells_chaos.xml', 'r')
  if xml then
    local text = xml:read('*a')
    xml:close()
    local nameOf = {}
    for id, name in text:gmatch('spellid="(%d+)" name="([^"]+)"') do nameOf[tonumber(id)] = name end
    for _, c in ipairs(cfg.choices) do
      if nameOf[c.spell] then eq(T.rows[c.id].spell, nameOf[c.spell], c.name .. ': the name of spell ' .. c.spell) end
    end
  end
else
  print('note: server/data not found, the rows were not compared with chaos_spell_masteries_config.lua')
end

if fails > 0 then
  print(fails .. ' of ' .. count .. ' checks failed')
  os.exit(1)
end
print('treespellmods_test: ' .. count .. ' checks OK')
