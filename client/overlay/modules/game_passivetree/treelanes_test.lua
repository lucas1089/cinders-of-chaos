-- luajit treelanes_test.lua && lua5.3 treelanes_test.lua (CI runs every client module test from the repo root)
-- The names of the passive tree as each class sees them (treelanes.lua on the real treedata/nodes.lua and classlanes.lua):
-- for every variant key and every node, the name the tooltip shows (setNodeTooltip: node[key].name or node.name) must fit
-- the stats the class gets (node[key].customStats or node.customStats). Regression of the class lanes that re-skinned a
-- node's stats but left its name ("Pyre Litany" gave a Beastmaster physical damage, "Speed" gave a Berserker strength).
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'treelanes.lua')
dofile(dir .. 'treedata/nodes.lua')
dofile(dir .. 'treedata/classlanes.lua')
dofile(dir .. 'treedata/icons.lua')
dofile(dir .. 'passivetree.lua') -- KEYSTONE_NAMES, CLASS_NOTABLE_NAMES (top level only defines functions and tables)
local T = TreeLanes
local fails, count = 0, 0
local function eq(a, b, what)
  count = count + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(cond, what)
  eq(cond and true or false, true, what)
end
local function statText(t)
  local keys = {}
  for k, v in pairs(t or {}) do keys[#keys + 1] = k .. '=' .. tostring(v) end
  table.sort(keys)
  return table.concat(keys, ',')
end

-- the name maker
eq(T.name({incrementPhysical = 3}), 'Physical Damage', 'one stat')
eq(T.name({absorbFire = 2}), 'Fire Absorption', 'absorption')
eq(T.name({incrementHoly = 3, absorbHoly = 1}, {incrementHoly = 3, absorbHoly = 1}), 'Holy Damage & Absorption',
  'damage and absorption of one element are one label')
eq(T.name({criticalHitChance = 2, criticalHitAmount = 2, magicSkill = 1}, {criticalHitChance = 2, criticalHitAmount = 2,
  magicSkill = 1}), 'Critical Hits and Magic Level', 'crit pair is one label, ties by label')
eq(T.name({incrementLifeDrain = 2, incrementManaDrain = 2}), 'Life & Mana Drain Damage', 'the tree\'s own drain name')
eq(T.name({speed = 500}), 'Speed', 'speed')
eq(T.name({strength = 10, vitality = 2}, {strength = 2, vitality = 2}), 'Strength and Vitality', 'strongest first')
eq(T.name({strength = 2, vitality = 10}, {strength = 2, vitality = 2}), 'Vitality and Strength', 'by value / median')
eq(T.name({}), nil, 'no stats, no name')
eq(T.laneName({name = 'Attribute', customStats = {strength = 1}}, {spirit = 1}), nil, 'the generic name stays')
eq(T.laneName({name = 'Fire Damage', customStats = {incrementFire = 2}}, {incrementFire = 3}), nil,
  'a stat name that still fits stays')
eq(T.laneName({name = 'Pyre Litany', customStats = {incrementHoly = 3, strength = 2}}, {incrementPhysical = 5, vitality = 2},
  {incrementPhysical = 2, vitality = 1}), 'Physical Damage and Vitality', 'a re-skinned notable gets the name of its stats')

-- the real tree as each class sees it
local lanes, icons = getClassLanes(), getClassLaneIcons()
local nodes = T.apply(getTreeNodes(), lanes, icons)
local norm = T.norms(getTreeNodes())
local keys = {}
for key in pairs(lanes) do keys[#keys + 1] = key end
for _, n in pairs(nodes) do
  for key, v in pairs(n) do
    if type(v) == 'table' and v.customStats and key ~= 'masteries' and not lanes[key] then
      lanes[key] = {}
      keys[#keys + 1] = key
    end
  end
end
table.sort(keys)
ok(#keys >= 20, 'every variant key is checked (' .. #keys .. ')')

local FLAG = {}
for k, name in pairs(KEYSTONE_NAMES) do FLAG[k] = name end
for k, name in pairs(CLASS_NOTABLE_NAMES) do FLAG[k] = name end
local function flags(stats)
  local out = {}
  for k in pairs(stats or {}) do
    if k:match('^ks%u') or k:match('^ar%u') or k:match('^ct%u') then out[#out + 1] = k end
  end
  table.sort(out)
  return out
end
local function sameStats(a, b)
  return statText(a) == statText(b)
end

local laneNodes, renamed, problems = 0, 0, 0
for _, key in ipairs(keys) do
  for id = 1, #nodes do
    local n = nodes[id]
    if n and not n.hidden and not n.isStartNode and not n.isMastery then
      local v = n[key]
      local stats = (type(v) == 'table' and v.customStats) or n.customStats
      local name = T.displayName(n, key)
      local where = key .. ' node ' .. id .. ' "' .. tostring(name) .. '" {' .. statText(stats) .. '}'
      -- a keystone / archetype / class notable: the name of its effect
      for _, k in ipairs(flags(stats)) do
        if FLAG[k] ~= name then problems = problems + 1 end
        eq(name, FLAG[k], where .. ': the name of ' .. k)
      end
      if lanes[key][id] and #flags(stats) == 0 then
        laneNodes = laneNodes + 1
        eq(statText(v and v.customStats), statText(lanes[key][id]), where .. ': the lane is merged')
        if n.name ~= 'Attribute' and not sameStats(stats, n.customStats) then
          -- the stats changed: the shown name is made from them, never the old name (unless both are the same words)
          local want = T.name(stats, norm)
          if name ~= want then problems = problems + 1 end
          eq(name, want, where .. ': named after its stats (was "' .. tostring(n.name) .. '" {' .. statText(n.customStats) .. '})')
          if v.name then renamed = renamed + 1 end
          -- the name is made of labels of stat groups the class gets (one, or two joined by " and ")
          local labels, fits = {}, false
          for _, g in ipairs(T.groups(stats, norm)) do labels[#labels + 1] = g.label end
          for _, a in ipairs(labels) do
            fits = fits or name == a
            for _, b in ipairs(labels) do
              fits = fits or (a ~= b and name == a .. ' and ' .. b)
            end
          end
          ok(fits, where .. ': made of its own stats')
        end
      end
    end
  end
end
ok(laneNodes > 1000, 'lane nodes checked: ' .. laneNodes)
ok(renamed > 500, 'renamed lane nodes: ' .. renamed)
eq(problems, 0, 'names that do not fit the stats the class gets')

-- the cases of the report
eq(T.displayName(nodes[153], 'beastmaster'), 'Physical Damage and Vitality', 'Pyre Litany for the Beastmaster')
eq(T.displayName(nodes[153], nil), 'Pyre Litany', 'Pyre Litany as such')
eq(T.displayName(nodes[110], 'berserker'), 'Strength', 'a Speed node for the Berserker')
eq(T.displayName(nodes[14], 'beastmaster'), 'Physical Damage', 'Arcane Damage for the Beastmaster')
eq(T.displayName(nodes[297], 'lich'), 'Critical Hits and Magic Level', 'Hawk\'s Malice for the Lich')
eq(T.displayName(nodes[621], 'ninja'), 'Shadow Twin', 'a keystone variant keeps its own name')
eq(T.displayName(nodes[624], 'bonelord'), "Reaper's Toll", 'a keystone variant keeps its own name')

-- the old merge (no name) fails this check: the test sees the bug
local old = getTreeNodes()
for key, lane in pairs(getClassLanes()) do
  for id, stats in pairs(lane) do
    local node = old[id]
    if node and node.customStats and not node.masteries and node[key] == nil then
      node[key] = {customStats = stats}
    end
  end
end
local stale = 0
for key, lane in pairs(getClassLanes()) do
  for id, stats in pairs(lane) do
    local n = old[id]
    if n and n.name ~= 'Attribute' and T.displayName(n, key) ~= T.name(stats, norm) then stale = stale + 1 end
  end
end
ok(stale > 500, 'the merge without names shows the old names (' .. stale .. ')')

-- lane icons are known icons
local known = getTreeIcons()
for key, list in pairs(icons) do
  for id, icon in pairs(list) do
    ok(known[icon] ~= nil, key .. ' node ' .. id .. ': icon ' .. icon .. ' exists')
  end
end

print(string.format('treelanes_test: %d checks, %d failures', count, fails))
if fails > 0 then os.exit(1) end
