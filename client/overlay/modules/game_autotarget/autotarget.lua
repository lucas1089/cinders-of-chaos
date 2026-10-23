-- game_autotarget: the engine side of ChaosAutoTarget (autotarget_core.lua holds the rules). Global
-- ChaosAutoTargetEngine; base patch 0117 calls it from modules/game_helper/classes/auto_target.lua. The only engine calls
-- are here: g_map.findPath and g_map.isSightClear for the reach, the monster bar's cached tier for the class, and
-- g_settings for the two options of the helper's Targeting panel (both on by default):
--   chaosAutoTargetPriority  "Priority targets": loot goblins, bosses and special monsters first
--   chaosAutoTargetReachable "Only reachable": never a monster the character cannot get to or shoot
-- Not run in a client yet; the rules are tested in autotarget_core_test.lua.
ChaosAutoTargetEngine = ChaosAutoTargetEngine or {}
local E = ChaosAutoTargetEngine
local T = ChaosAutoTarget

E.PRIORITY_KEY = 'chaosAutoTargetPriority'
E.REACHABLE_KEY = 'chaosAutoTargetReachable'
E.MODE_CLOSEST_LOWEST = 6 -- the helper's autoTargetMode F, the default
E.MODE_OWN_LIST = 10      -- mode J: the player's own priority list
local FLAG_IGNORE_CREATURES = 16 -- Otc::PathFindIgnoreCreatures: other monsters move, they do not wall a monster off
local RESULT_OK = 0 -- Otc::PathFindResultOk

local options = { priority = nil, reachable = nil } -- read once from g_settings
local pathCache = {}  -- creature id -> { t, steps (nil: no path), sight, straight }
local asked = {}      -- creature id -> when the server was last asked its tier
local budget = { t = -1, paths = 0, queries = 0 }

local function now()
  return g_clock and g_clock.millis() or 0
end

local function readOption(key)
  local ok, v = pcall(function()
    if g_settings.exists(key) then
      return g_settings.getBoolean(key)
    end
    return true
  end)
  if not ok then
    return true
  end
  return v ~= false
end

function E.priorityEnabled()
  if options.priority == nil then
    options.priority = readOption(E.PRIORITY_KEY)
  end
  return options.priority
end

function E.reachableEnabled()
  if options.reachable == nil then
    options.reachable = readOption(E.REACHABLE_KEY)
  end
  return options.reachable
end

local function setOption(key, field, on)
  options[field] = on == true
  pcall(function()
    g_settings.set(key, on == true)
    g_settings.save()
  end)
end

function E.setPriority(on) setOption(E.PRIORITY_KEY, 'priority', on) end
function E.setReachable(on) setOption(E.REACHABLE_KEY, 'reachable', on) end

-- true when the engine has anything to do for this mode (the patch skips the calls otherwise)
function E.active(modeId)
  return E.reachableEnabled() or E.priorityEnabled() or modeId == E.MODE_CLOSEST_LOWEST
end

local function newTick()
  local t = now()
  if t - budget.t >= 50 then -- one Auto Target tick (check() and its lock test) shares one budget
    budget.t, budget.paths, budget.queries = t, 0, 0
  end
  return t
end

local function monsterBar()
  local m = modules and modules.game_monsterbar
  return m
end

-- the class of a creature: its name, and the tier the server named (asks it for a creature it has not named yet)
local function classOf(creature, t)
  local bar = monsterBar()
  local tier, role
  if bar and bar.tierInfo then
    local id = creature:getId()
    tier, role = bar.tierInfo(id)
    if tier == nil and bar.requestInfo and budget.queries < T.cfg.queryBudget and (t - (asked[id] or -1e9)) >= T.cfg.queryEveryMs then
      asked[id] = t
      budget.queries = budget.queries + 1
      pcall(bar.requestInfo, id)
    end
  end
  return T.classOf(creature:getName(), tier, role)
end

local function isRanged()
  local p = g_game.getLocalPlayer()
  return p ~= nil and T.isRanged(p:getVocation())
end

local function search(from, to)
  local steps
  local ok, a, b = pcall(g_map.findPath, from, to, T.cfg.maxComplexity, FLAG_IGNORE_CREATURES)
  if ok then
    local dirs, res = a, b
    if type(a) == 'table' and b == nil then
      dirs, res = a[1], a[2]
    end
    if type(dirs) == 'table' and res == RESULT_OK then
      steps = #dirs
    end
  end
  return steps
end

-- reachable (true | false | nil when the budget of path searches is spent and no answer is kept), distance
local function reach(creature, from, ranged, t)
  local id = creature:getId()
  local to = creature:getPosition()
  local straight = to and T.distance(from, to)
  if not straight then
    return false, nil
  end
  local e = pathCache[id]
  if not e or (t - e.t) > T.cfg.freshMs then
    if budget.paths < T.cfg.pathBudget then
      budget.paths = budget.paths + 1
      local steps = search(from, to)
      local sight = ranged and (straight <= 1 or g_map.isSightClear(from, to)) or false
      e = { t = t, steps = steps, sight = sight, straight = straight }
      pathCache[id] = e
    elseif not e or (t - e.t) > T.cfg.staleMs then
      return nil, nil
    end
  end
  e.straight = straight
  local ok, dist = T.assess(e, ranged)
  return ok, dist
end

-- the candidate table of a creature for ChaosAutoTarget
local function describe(creature, from, ranged, t, useReach)
  local c = { creature = creature, id = creature:getId(), health = creature:getHealthPercent(),
    class = classOf(creature, t) }
  if useReach then
    c.reachable, c.dist = reach(creature, from, ranged, t)
  end
  if c.dist == nil then
    c.dist = T.distance(from, creature:getPosition()) or 99
  end
  return c
end

local function candidates(monsters, from, useReach)
  local t = newTick()
  local ranged = isRanged()
  local list = {}
  -- the nearest first, so a spent path budget leaves out the far ones
  local order = {}
  for _, m in ipairs(monsters) do
    order[#order + 1] = m
  end
  table.sort(order, function(a, b)
    local da = T.distance(from, a:getPosition()) or 99
    local db = T.distance(from, b:getPosition()) or 99
    if da ~= db then return da < db end
    return a:getId() < b:getId()
  end)
  for _, m in ipairs(order) do
    list[#list + 1] = describe(m, from, ranged, t, useReach)
  end
  return list
end

-- The monsters the character can get to (all of them when the option is off). The helper's list is not changed.
function E.filter(monsters, from)
  if not E.reachableEnabled() then
    return monsters
  end
  local out = {}
  for _, c in ipairs(candidates(monsters, from, true)) do
    if c.reachable == true then
      out[#out + 1] = c.creature
    end
  end
  return out
end

-- The creature the helper attacks, given the one its mode picked (`target`, may be nil) from `monsters` (already
-- filtered by E.filter): the priority class first when the option is on and the mode is not the player's own list;
-- mode F (the default) by the order of ChaosAutoTarget (nearest by the way to walk, equal distance the lowest health);
-- any other mode keeps what it picked.
function E.adjust(target, monsters, from, modeId)
  if #monsters == 0 then
    return target
  end
  local priority = E.priorityEnabled() and modeId ~= E.MODE_OWN_LIST
  if not priority and modeId ~= E.MODE_CLOSEST_LOWEST then
    return target
  end
  local cands = candidates(monsters, from, E.reachableEnabled())
  local reachFn = E.reachableEnabled() and function(c) return c.reachable end or nil
  local p = priority and T.pickPriority(cands, reachFn)
  if p then
    return p.creature
  end
  if modeId == E.MODE_CLOSEST_LOWEST then
    local pick = T.choose(cands, { priority = false, reachable = reachFn })
    return pick and pick.creature or target
  end
  return target
end

-- May the locked target stay: false when it can no longer be reached, or a goblin, boss or special monster that can be
-- reached has appeared while it fights a normal one. `gather(from)` is the helper's list of the monsters in reach.
function E.keepLock(locked, from, modeId, gather)
  local useReach, priority = E.reachableEnabled(), E.priorityEnabled() and modeId ~= E.MODE_OWN_LIST
  if not useReach and not priority then
    return true
  end
  local t = newTick()
  local ranged = isRanged()
  local lockedCand = describe(locked, from, ranged, t, useReach)
  local reachFn = useReach and function(c) return c.reachable end or nil
  local cands = { lockedCand }
  if priority and gather then
    local list = gather(from) or {}
    cands = candidates(list, from, useReach)
    local found = false
    for _, c in ipairs(cands) do
      if c.id == lockedCand.id then
        found = true
      end
    end
    if not found then
      cands[#cands + 1] = lockedCand
    end
  end
  return T.keepLock(lockedCand, cands, reachFn, priority)
end

function E.reset()
  pathCache, asked = {}, {}
end

function E.init()
  connect(g_game, { onGameEnd = E.reset })
end

function E.terminate()
  disconnect(g_game, { onGameEnd = E.reset })
  E.reset()
end

return E
