-- luajit autotarget_core_test.lua && lua5.3 autotarget_core_test.lua (CI runs it from the repo root)
-- The Auto Target choice (base patch 0117, ChaosAutoTarget): reach, priority classes, nearest / lowest health, no flapping.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'autotarget_core.lua')
local T = ChaosAutoTarget
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function idOf(c) return c and c.id or nil end

-- a candidate: id, distance, health percent, class
local function cand(id, dist, health, class) return { id = id, dist = dist, health = health, class = class or 'normal' } end
-- a reach function: ids listed false are unreachable, ids listed nil-ish (unknown) answer nil, everything else true
local function reachExcept(blocked, unknown)
  return function(c)
    if blocked and blocked[c.id] then return false end
    if unknown and unknown[c.id] then return nil end
    return true
  end
end

-- ------------------------------------------------------------------------------------------------ classes
eq(T.baseName('Gem Goblin [25]'), 'gem goblin', 'the level suffix goes')
eq(T.baseName(nil), '', 'no name')
eq(T.isLootGoblin('Treasure Goblin'), true, 'treasure goblin')
eq(T.isLootGoblin('Gem Goblin [120]'), true, 'gem goblin with level')
eq(T.isLootGoblin('Shard Goblin'), true, 'shard goblin')
eq(T.isLootGoblin('Goblin'), false, 'the stock goblin is a normal monster')
eq(T.isLootGoblin('Goblin Scavenger'), false, 'a goblin scavenger is a normal monster')
eq(T.classOf('Treasure Goblin', 'normal', nil), 'goblin', 'goblin class')
eq(T.classOf('Vhalkareth', 'boss', nil), 'boss', 'boss tier')
eq(T.classOf('Rift Warden', 'normal', 'guardian'), 'boss', 'rift guardian')
eq(T.classOf('Omen Warden', 'normal', 'omen'), 'boss', 'omen guardian')
eq(T.classOf('Orc', 'magic', nil), 'special', 'magic tier')
eq(T.classOf('Orc', 'rare', nil), 'special', 'rare tier')
eq(T.classOf('Orc', 'legendary', nil), 'special', 'legendary tier')
eq(T.classOf('Orc', 'normal', nil), 'normal', 'normal tier')
eq(T.classOf('Orc', nil, nil), 'normal', 'tier not heard of yet: normal')
eq(T.classOf('Treasure Goblin', 'boss', nil), 'goblin', 'a goblin stays a goblin')
eq(T.isRanged(3), true, 'ranger ranged')
eq(T.isRanged(5), true, 'elementalist ranged')
eq(T.isRanged(20), true, 'necromancer ranged')
eq(T.isRanged(4), false, 'warrior melee')
eq(T.isRanged(12), false, 'ninja melee')
eq(T.isRanged(nil), false, 'no vocation: melee')

-- the server's loot goblin variants are all known (cd to the repo root: CI does)
do
  local f = io.open('server/data/scripts/chaos/treasure_goblin_config.lua', 'r')
  if f then
    local src = f:read('*a')
    f:close()
    local n = 0
    for name in src:gmatch('{key = "[%w_]+", name = "([^"]+)"') do
      n = n + 1
      eq(T.isLootGoblin(name), true, 'server variant ' .. name .. ' is a loot goblin')
    end
    eq(n >= 3, true, 'read the server goblin variants (' .. n .. ')')
  end
end

-- ------------------------------------------------------------------------------------------------ reach
eq(select(1, T.assess({ steps = 5, sight = false, straight = 3 }, false)), true, 'melee: a path')
eq(select(2, T.assess({ steps = 5, sight = false, straight = 3 }, false)), 5, 'melee: the distance is the walk')
eq(select(1, T.assess({ steps = nil, sight = true, straight = 3 }, false)), false, 'melee: sight without a path is no way (across water)')
eq(select(1, T.assess({ steps = T.cfg.maxSteps + 1, sight = true, straight = 2 }, false)), false, 'melee: a long detour is no way')
eq(select(1, T.assess({ steps = nil, sight = true, straight = 4 }, true)), true, 'ranged: sight, no path (across water)')
eq(select(2, T.assess({ steps = 9, sight = true, straight = 4 }, true)), 4, 'ranged: the straight distance')
eq(select(1, T.assess({ steps = nil, sight = false, straight = 3 }, true)), false, 'ranged: behind a wall, no path')
eq(select(1, T.assess({ steps = 6, sight = false, straight = 3 }, true)), true, 'ranged: no sight but a path')

-- ------------------------------------------------------------------------------------------------ unreachable skipped
do
  local list = { cand(1, 1, 100), cand(2, 4, 100), cand(3, 6, 100) }
  eq(idOf(T.choose(list, { reachable = reachExcept({ [1] = true }) })), 2, 'the nearest is unreachable: the next one')
  eq(idOf(T.choose(list, { reachable = reachExcept({ [1] = true, [2] = true, [3] = true }) })), nil, 'none reachable: no target')
  eq(idOf(T.choose(list, { reachable = reachExcept({ [1] = true }, { [2] = true }) })), 3, 'unknown this tick is skipped')
  eq(idOf(T.choose(list, {})), 1, 'no reach rule: the nearest')
  local pass = T.filterReachable(list, reachExcept({ [2] = true }))
  eq(#pass, 2, 'filter keeps the reachable')
  eq(pass[1].id, 1, 'filter keeps the order (1)')
  eq(pass[2].id, 3, 'filter keeps the order (2)')
  -- the nearest are asked first: a budget that answers only 2 calls serves the 2 nearest
  local asked = {}
  T.filterReachable({ cand(10, 9, 100), cand(11, 2, 100), cand(12, 5, 100) },
    function(c) asked[#asked + 1] = c.id; return #asked <= 2 and true or nil end)
  eq(asked[1], 11, 'asked nearest first')
  eq(asked[2], 12, 'asked second nearest second')
end

-- ------------------------------------------------------------------------------------------------ priority classes
do
  local normal = cand(1, 1, 10, 'normal')
  eq(idOf(T.choose({ normal, cand(2, 5, 100, 'goblin') })), 2, 'a goblin before a nearer normal monster')
  eq(idOf(T.choose({ normal, cand(2, 6, 100, 'boss') })), 2, 'a boss before a nearer normal monster')
  eq(idOf(T.choose({ normal, cand(2, 6, 100, 'special') })), 2, 'a special monster before a nearer normal one')
  eq(idOf(T.choose({ cand(3, 1, 100, 'special'), cand(4, 6, 100, 'boss'), cand(5, 7, 100, 'goblin') })), 5, 'goblin, boss, special in that order')
  eq(idOf(T.choose({ cand(3, 1, 100, 'special'), cand(4, 6, 100, 'boss') })), 4, 'a boss before a special monster')
  eq(idOf(T.choose({ cand(6, 4, 100, 'boss'), cand(7, 2, 100, 'boss') })), 7, 'within a class the nearest')
  eq(idOf(T.choose({ cand(6, 3, 80, 'boss'), cand(7, 3, 20, 'boss') })), 7, 'within a class, equal distance: the lowest health')
  eq(idOf(T.choose({ normal, cand(2, 5, 100, 'goblin') }, { priority = false })), 1, 'priority off: the nearest')
  -- an unreachable goblin is no priority
  eq(idOf(T.choose({ normal, cand(2, 5, 100, 'goblin') }, { reachable = reachExcept({ [2] = true }) })), 1, 'an unreachable goblin is skipped')
  eq(idOf(T.pickPriority({ normal }, nil)), nil, 'no priority monster')
  eq(idOf(T.pickPriority({ normal, cand(2, 5, 100, 'special'), cand(3, 2, 100, 'boss') }, nil)), 3, 'pickPriority: the best class')
  eq(idOf(T.pickPriority({ cand(2, 5, 100, 'special'), cand(3, 2, 100, 'boss') }, reachExcept({ [3] = true }))), 2, 'pickPriority: reachable only')
end

-- ------------------------------------------------------------------------------------------------ nearest, then health
do
  eq(idOf(T.choose({ cand(1, 5, 5), cand(2, 2, 100), cand(3, 3, 1) })), 2, 'the nearest wins among normals, whatever the health')
  eq(idOf(T.choose({ cand(1, 3, 90), cand(2, 3, 40), cand(3, 3, 65) })), 2, 'equal distance: the lowest health')
  eq(idOf(T.choose({ cand(9, 3, 50), cand(4, 3, 50) })), 4, 'a full tie: the lowest id, so the pick is stable')
  eq(idOf(T.choose({})), nil, 'no monsters')
  eq(idOf(T.choose(nil)), nil, 'nil list')
end

-- ------------------------------------------------------------------------------------------------ no flapping
do
  local cur = cand(1, 4, 100)
  local list = { cur, cand(2, 2, 30) }
  local pick, why = T.choose(list, { current = 1 })
  eq(idOf(pick), 1, 'the current target stays although another is nearer and weaker')
  eq(why, 'keep', 'reason keep')
  pick, why = T.choose(list, {})
  eq(idOf(pick), 2, 'no current target: the nearest')
  eq(why, 'pick', 'reason pick')
  -- it leaves when it cannot be reached any more
  eq(idOf(T.choose(list, { current = 1, reachable = reachExcept({ [1] = true }) })), 2, 'the current target is unreachable: a new one')
  -- an unknown answer (budget spent) does not drop it
  eq(idOf(T.choose(list, { current = 1, reachable = reachExcept(nil, { [1] = true, [2] = true }) })), 1, 'unknown reach keeps the current target')
  -- a priority monster takes over
  pick, why = T.choose({ cur, cand(3, 6, 100, 'goblin') }, { current = 1 })
  eq(idOf(pick), 3, 'a goblin appears: the helper switches')
  eq(why, 'pick', 'switch is a pick')
  -- the current target is itself a priority monster: a nearer normal one does not take it away
  pick = T.choose({ cand(1, 6, 100, 'boss'), cand(2, 1, 10) }, { current = 1 })
  eq(idOf(pick), 1, 'a boss target is kept')
  -- a better class only
  pick = T.choose({ cand(1, 6, 100, 'special'), cand(2, 2, 100, 'special') }, { current = 1 })
  eq(idOf(pick), 1, 'the same class does not take the target away')
  pick = T.choose({ cand(1, 6, 100, 'special'), cand(2, 7, 100, 'boss') }, { current = 1 })
  eq(idOf(pick), 2, 'a boss takes it from a special monster')
  -- priority off: never switches for a class
  pick = T.choose({ cur, cand(3, 6, 100, 'goblin') }, { current = 1, priority = false })
  eq(idOf(pick), 1, 'priority off: the target is kept')
  -- the locked creature left the list: a new pick
  eq(idOf(T.choose({ cand(2, 2, 30) }, { current = 1 })), 2, 'the current target is gone')
end

-- ------------------------------------------------------------------------------------------------ keepLock
do
  local locked = cand(1, 3, 50, 'normal')
  eq(T.keepLock(locked, { locked }, nil, true), true, 'a lone target stays')
  eq(T.keepLock(locked, { locked }, function() return false end, true), false, 'unreachable: the lock goes')
  eq(T.keepLock(locked, { locked }, function() return nil end, true), true, 'reach unknown: the lock stays')
  eq(T.keepLock(locked, { locked, cand(2, 6, 100, 'goblin') }, nil, true), false, 'a goblin appeared: the lock goes')
  eq(T.keepLock(locked, { locked, cand(2, 6, 100, 'goblin') }, nil, false), true, 'priority off: the lock stays')
  eq(T.keepLock(locked, { locked, cand(2, 6, 100, 'goblin') }, reachExcept({ [2] = true }), true), true, 'the goblin is unreachable: the lock stays')
  eq(T.keepLock(cand(1, 3, 50, 'boss'), { cand(1, 3, 50, 'boss'), cand(2, 1, 100, 'special') }, nil, true), true, 'a lesser class does not take the lock')
end

if fails > 0 then
  print(fails .. ' of ' .. checks .. ' checks failed')
  os.exit(1)
end
print('autotarget_core_test: ' .. checks .. ' checks ok')
