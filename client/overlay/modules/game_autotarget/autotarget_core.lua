-- game_autotarget: which monster the helper's Auto Target picks (client/MANIFEST.md "Auto Target priority and reach").
-- Global ChaosAutoTarget, pure (no engine calls), so autotarget_core_test.lua runs it under LuaJIT and Lua 5.3. The thin
-- engine glue is autotarget.lua; base patch 0117 calls it from mods/game_helper/classes/auto_target.lua.
--
-- Before (the base client's check(), mode F "closest + lowest health", the default): every monster in the 7 x 5 reach
-- window that is not ignored, with the straight distance; the nearest won, equal distance went to the lowest health.
-- Nothing asked whether the character could get there, so a monster behind a wall, across water or a gap was picked and
-- the character stood and tried to walk to it, and every other monster waited.
--
-- Now:
--   * reach: a monster is a target only when the character can get to it. Melee: a walkable path (g_map.findPath, at
--     most cfg.maxSteps steps). A ranged class (Ranger, Mystic and Necromancer lines): a clear line of sight (it shoots
--     across water or a gap), or a path. The distance of the order is then the steps to walk (melee) or the straight
--     distance (ranged with sight), not the straight distance through a wall.
--   * priority: a loot goblin (Treasure, Gem, Shard Goblin), then a boss (tier boss, rift or Omen guardian), then a
--     special monster (magic, rare or legendary tier: the elites and champions) comes before every normal monster. Within
--     one class (and among normals) the nearest first, equal distance the lowest health percent, then the lowest id.
--   * no flapping: the current target stays while it is valid and reachable, unless a monster of a better class (a
--     goblin appeared while it fights a normal one) is reachable.
-- Where the client learns the class: the goblins by name (the server's treasure_goblin_config.lua variants; the plain
-- "Goblin" of the stock monsters is a normal monster); bosses, guardians and tiers from the server's monster bar
-- messages (extended opcode 125, game_monsterbar caches them per creature id: tier, role). Mode J (the player's own
-- priority list) keeps the player's order and only gets the reach rule.
ChaosAutoTarget = ChaosAutoTarget or {}
local T = ChaosAutoTarget

T.RANK = { goblin = 1, boss = 2, special = 3, normal = 4 }
T.cfg = {
  maxSteps = 16,       -- a path longer than this is a detour, not a way to the monster
  maxComplexity = 500, -- g_map.findPath search size
  pathBudget = 4,      -- new path searches per Auto Target tick (the nearest first; the rest wait for the next tick)
  queryBudget = 3,     -- tier questions to the server per tick (creatures the monster bar has not heard about)
  queryEveryMs = 5000, -- the same creature is asked again after this long
  freshMs = 600,       -- a path answer this young is reused as it is
  staleMs = 3000       -- when the budget is spent an answer up to this old is still better than none
}

-- the loot goblins: variants of server/data/scripts/chaos/treasure_goblin_config.lua (autotarget_core_test.lua checks them)
T.GOBLINS = { ['treasure goblin'] = true, ['gem goblin'] = true, ['shard goblin'] = true }
T.SPECIAL_TIERS = { magic = true, rare = true, legendary = true }
T.BOSS_ROLES = { guardian = true, omen = true }
-- server vocation ids (docs/CLASSES.md, base patch 0016) of the lines that shoot: Ranger, Deadeye, Beastmaster,
-- Mystic, Elementalist, Illusionist, Necromancer, Lich, Bone Lord
T.RANGED_VOCATIONS = { [3] = true, [7] = true, [15] = true, [1] = true, [5] = true, [10] = true, [20] = true,
  [21] = true, [22] = true }

-- the creature name without the server's level suffix ("Gem Goblin [25]"), lower case
function T.baseName(name)
  if type(name) ~= 'string' then
    return ''
  end
  return (name:gsub('%s*%[%d+%]%s*$', ''):lower())
end

function T.isLootGoblin(name)
  return T.GOBLINS[T.baseName(name)] == true
end

-- 'goblin' | 'boss' | 'special' | 'normal' for a creature's name, the server's tier ('normal' | 'magic' | 'rare' |
-- 'legendary' | 'boss'; nil when not heard yet) and role ('guardian' | 'omen' | nil)
function T.classOf(name, tier, role)
  if T.isLootGoblin(name) then
    return 'goblin'
  end
  if tier == 'boss' or T.BOSS_ROLES[role or ''] then
    return 'boss'
  end
  if T.SPECIAL_TIERS[tier or ''] then
    return 'special'
  end
  return 'normal'
end

function T.isRanged(vocation)
  return T.RANGED_VOCATIONS[tonumber(vocation) or 0] == true
end

-- the straight distance of the helper (the larger axis); nil on another floor
function T.distance(a, b)
  if not a or not b or a.z ~= b.z then
    return nil
  end
  local dx, dy = math.abs(a.x - b.x), math.abs(a.y - b.y)
  return dx > dy and dx or dy
end

-- Can the character get to the monster, and how far is it. f = { steps = path length or nil (no path), sight = line of
-- sight clear, straight = straight distance }. Returns reachable, distance.
function T.assess(f, ranged)
  if ranged and f.sight then
    return true, f.straight
  end
  if f.steps ~= nil and f.steps <= T.cfg.maxSteps then
    return true, f.steps
  end
  return false, nil
end

local function rankOf(c)
  return c.rank or T.RANK[c.class or 'normal'] or T.RANK.normal
end

-- the order: class (when `priority`), distance, health percent, id
local function before(a, b, priority)
  if priority then
    local ra, rb = rankOf(a), rankOf(b)
    if ra ~= rb then
      return ra < rb
    end
  end
  local da, db = a.dist or 99, b.dist or 99
  if da ~= db then
    return da < db
  end
  local ha, hb = a.health or 100, b.health or 100
  if ha ~= hb then
    return ha < hb
  end
  return (a.id or 0) < (b.id or 0)
end

local function sortedCopy(cands, priority)
  local list = {}
  for i, c in ipairs(cands or {}) do
    list[i] = c
  end
  table.sort(list, function(a, b) return before(a, b, priority) end)
  return list
end
T.sorted = sortedCopy

-- The candidates the character can get to, in the order given. `reach(c)` answers true, false, or nil (not known this
-- tick: the path budget is spent): the unknown ones are left out for now. The nearest are asked first, so a spent budget
-- leaves out the far ones.
function T.filterReachable(cands, reach)
  if not reach then
    return cands
  end
  local pass = {}
  for _, c in ipairs(sortedCopy(cands, false)) do
    if reach(c) == true then
      pass[c] = true
    end
  end
  local out = {}
  for _, c in ipairs(cands or {}) do
    if pass[c] then
      out[#out + 1] = c
    end
  end
  return out
end

-- the best candidate of a priority class (goblin, boss, special) that is reachable; nil when there is none
function T.pickPriority(cands, reach)
  for _, c in ipairs(sortedCopy(cands, true)) do
    if rankOf(c) >= T.RANK.normal then
      return nil
    end
    if not reach or reach(c) == true then
      return c
    end
  end
  return nil
end

-- The whole choice. cands: { id, dist, health, class | rank } each. opts:
--   priority  (default true) the class order; false: only distance and health
--   reachable function(c) -> true | false | nil (nil: not known, treated as "keep if current, else skip")
--   current   the id of the target being fought
-- Returns the candidate and "keep" (the current one stays) or "pick" (a new one); nil when none can be reached.
function T.choose(cands, opts)
  opts = opts or {}
  local priority = opts.priority ~= false
  local reach = opts.reachable
  local function ok(c)
    if not reach then
      return true
    end
    return reach(c)
  end
  local best
  for _, c in ipairs(sortedCopy(cands, priority)) do
    if ok(c) == true then
      best = c
      break
    end
  end
  local cur
  if opts.current then
    for _, c in ipairs(cands or {}) do
      if c.id == opts.current then
        cur = c
        break
      end
    end
  end
  if cur and ok(cur) ~= false and (best == nil or not priority or rankOf(cur) <= rankOf(best)) then
    return cur, 'keep'
  end
  if best then
    return best, 'pick'
  end
  return nil
end

-- May the locked target stay. `locked` = the candidate of the locked creature, `cands` all candidates (the locked one
-- included), `reach` as above, `priority` the class rule. False when it cannot be reached any more or a monster of a
-- better class can.
function T.keepLock(locked, cands, reach, priority)
  if reach and reach(locked) == false then
    return false
  end
  if priority then
    local better = T.pickPriority(cands, reach)
    if better and rankOf(better) < rankOf(locked) then
      return false
    end
  end
  return true
end

return T
