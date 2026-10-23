-- luajit autotarget_engine_test.lua && lua5.3 autotarget_engine_test.lua (CI runs it from the repo root)
-- ChaosAutoTargetEngine on a mocked map: path searches, the monster bar's tiers, options, the lock test, the budgets.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ------------------------------------------------------------------------------------------------ mocked engine
local clock = 1000
g_clock = { millis = function() return clock end }
local store = {}
g_settings = {
  exists = function(k) return store[k] ~= nil end,
  getBoolean = function(k) return store[k] end,
  set = function(k, v) store[k] = v end,
  save = function() end,
}
local vocation = 4 -- a Warrior: melee
g_game = { getLocalPlayer = function() return { getVocation = function() return vocation end } end }
function connect() end
function disconnect() end

local walls = {}      -- "x,y" -> true: not walkable
local sightBlocked = {} -- id of a creature -> true
local searches = 0
local function key(p) return p.x .. ',' .. p.y end
g_map = {
  -- a straight walk on the larger axis; a wall on the target's tile or on the way (a crude line) is no path
  findPath = function(from, to, complexity, flags)
    searches = searches + 1
    assert(flags == 16, 'creatures are ignored')
    local x, y, steps = from.x, from.y, {}
    while x ~= to.x or y ~= to.y do
      x = x + (to.x > x and 1 or (to.x < x and -1 or 0))
      y = y + (to.y > y and 1 or (to.y < y and -1 or 0))
      if walls[x .. ',' .. y] then return {}, 4 end -- PathFindResultNoWay
      steps[#steps + 1] = 0
    end
    return steps, 0
  end,
  isSightClear = function(from, to) return not walls['sight'] and not sightBlocked[to.x .. ',' .. to.y] end,
}

local tiers, queries = {}, {}
modules = { game_monsterbar = {
  tierInfo = function(id) local t = tiers[id]; if t then return t[1], t[2] end return nil, nil end,
  requestInfo = function(id) queries[#queries + 1] = id end,
} }

local function monster(id, name, x, y, health)
  return { id = id, name = name, pos = { x = x, y = y, z = 7 }, health = health or 100,
    getId = function(self) return self.id end, getName = function(self) return self.name end,
    getPosition = function(self) return self.pos end, getHealthPercent = function(self) return self.health end }
end
local me = { x = 100, y = 100, z = 7 }

dofile(dir .. 'autotarget_core.lua')
dofile(dir .. 'autotarget.lua')
local E = ChaosAutoTargetEngine
local function ids(list) local t = {} for _, m in ipairs(list) do t[#t + 1] = m.id end return table.concat(t, ',') end
local function nextTick() clock = clock + 1000; E.reset() end

-- ------------------------------------------------------------------------------------------------ options
eq(E.priorityEnabled(), true, 'priority on by default')
eq(E.reachableEnabled(), true, 'reach on by default')
eq(E.active(1), true, 'active')
E.setPriority(false)
eq(store.chaosAutoTargetPriority, false, 'priority saved')
eq(E.priorityEnabled(), false, 'priority off')
E.setPriority(true)

-- ------------------------------------------------------------------------------------------------ reach filter
do
  nextTick()
  local near = monster(1, 'Orc', 101, 100)       -- 1 step
  local behind = monster(2, 'Orc', 103, 100)     -- a wall between
  walls['102,100'] = true
  local far = monster(3, 'Orc', 100, 105)        -- 5 steps
  local out = E.filter({ near, behind, far }, me)
  eq(ids(out), '1,3', 'the monster behind a wall is left out')
  walls['102,100'] = nil
  E.setReachable(false)
  walls['102,100'] = true
  eq(ids(E.filter({ near, behind, far }, me)), '1,2,3', 'option off: every monster stays')
  E.setReachable(true)
  walls['102,100'] = nil
end

-- melee does not get across water by sight; a ranged class shoots across
do
  nextTick()
  local across = monster(5, 'Orc', 103, 100)
  walls['102,100'] = true
  eq(ids(E.filter({ across }, me)), '', 'melee: sight alone is no way')
  nextTick()
  vocation = 7 -- a Deadeye
  eq(ids(E.filter({ across }, me)), '5', 'ranged: a clear sight is enough')
  nextTick()
  sightBlocked['103,100'] = true
  eq(ids(E.filter({ across }, me)), '', 'ranged: behind a wall (no sight, no path)')
  sightBlocked['103,100'] = nil
  vocation = 4
  walls['102,100'] = nil
end

-- other floor
do
  nextTick()
  local up = monster(6, 'Orc', 101, 100)
  up.pos.z = 6
  eq(ids(E.filter({ up }, me)), '', 'another floor is out')
end

-- ------------------------------------------------------------------------------------------------ adjust
do
  nextTick()
  local a = monster(1, 'Orc', 101, 100, 100)
  local b = monster(2, 'Orc', 102, 100, 100)
  local c = monster(3, 'Orc', 100, 102, 30) -- as far as b, weaker
  local ms = E.filter({ a, b, c }, me)
  eq(E.adjust(nil, ms, me, 6).id, 1, 'mode F: the nearest')
  eq(E.adjust(nil, { b, c }, me, 6).id, 3, 'mode F: equal distance, the lowest health')
  eq(E.adjust(b, ms, me, 1), b, 'mode A: the base pick stays when no priority monster')
  eq(E.adjust(nil, {}, me, 6), nil, 'no monsters')
end

-- a goblin, a boss, a special monster before a nearer normal one
do
  nextTick()
  local normal = monster(1, 'Orc', 101, 100)
  local goblin = monster(2, 'Treasure Goblin [30]', 100, 105)
  local boss = monster(3, 'Vhalkareth', 100, 104)
  local elite = monster(4, 'Orc', 100, 103)
  tiers[3] = { 'boss', nil }
  tiers[4] = { 'rare', nil }
  tiers[1] = { 'normal', nil }
  eq(E.adjust(normal, { normal, elite, boss }, me, 6).id, 3, 'boss over elite and normal')
  eq(E.adjust(normal, { normal, elite }, me, 6).id, 4, 'a rare monster over a normal one')
  eq(E.adjust(normal, { normal, elite, boss, goblin }, me, 6).id, 2, 'the goblin over all')
  eq(E.adjust(normal, { normal, goblin }, me, 1).id, 2, 'priority also in mode A')
  eq(E.adjust(normal, { normal, goblin }, me, 10), normal, 'mode J keeps the player\'s own list')
  E.setPriority(false)
  eq(E.adjust(normal, { normal, goblin }, me, 1), normal, 'option off: the mode decides')
  eq(E.adjust(normal, { normal, goblin }, me, 6).id, 1, 'option off, mode F: the nearest')
  E.setPriority(true)
  tiers = {}
end

-- ------------------------------------------------------------------------------------------------ the tier questions
do
  nextTick()
  queries = {}
  local a, b = monster(21, 'Orc', 101, 100), monster(22, 'Orc', 102, 100)
  E.adjust(nil, { a, b }, me, 6)
  eq(#queries, 2, 'a creature the monster bar has not heard of is asked')
  E.adjust(nil, { a, b }, me, 6)
  eq(#queries, 2, 'not asked again at once')
  clock = clock + 6000
  E.adjust(nil, { a, b }, me, 6)
  eq(#queries, 4, 'asked again after a while')
  nextTick()
  queries = {}
  local many = {}
  for i = 1, 8 do many[i] = monster(100 + i, 'Orc', 100 + (i % 4), 100 + math.floor(i / 4)) end
  E.adjust(nil, many, me, 6)
  eq(#queries <= ChaosAutoTarget.cfg.queryBudget, true, 'at most queryBudget questions per tick')
end

-- ------------------------------------------------------------------------------------------------ the path budget
do
  nextTick()
  searches = 0
  local many = {}
  for i = 1, 10 do many[i] = monster(200 + i, 'Orc', 100 + i % 6, 99 - math.floor(i / 6)) end
  local out = E.filter(many, me)
  eq(searches, ChaosAutoTarget.cfg.pathBudget, 'new path searches per tick are capped')
  eq(#out <= ChaosAutoTarget.cfg.pathBudget, true, 'the monsters beyond the budget wait for the next tick')
  local before = searches
  E.filter(many, me)
  eq(searches, before, 'the answers are kept for the next calls')
end

-- ------------------------------------------------------------------------------------------------ the lock
do
  nextTick()
  local locked = monster(1, 'Orc', 103, 100)
  local goblin = monster(2, 'Gem Goblin', 100, 105)
  local function gather() return { locked, goblin } end
  eq(E.keepLock(locked, me, 6, gather), false, 'a goblin can be reached: the lock goes')
  eq(E.keepLock(locked, me, 10, gather), true, 'mode J: the lock stays')
  E.setPriority(false)
  eq(E.keepLock(locked, me, 6, gather), true, 'priority off: the lock stays')
  nextTick()
  walls['102,100'] = true
  eq(E.keepLock(locked, me, 6, gather), false, 'the way is shut: the lock goes')
  E.setReachable(false)
  nextTick()
  eq(E.keepLock(locked, me, 6, gather), true, 'both off: the lock stays')
  E.setReachable(true)
  E.setPriority(true)
  walls['102,100'] = nil
end

if fails > 0 then
  print(fails .. ' of ' .. checks .. ' checks failed')
  os.exit(1)
end
print('autotarget_engine_test: ' .. checks .. ' checks ok')
