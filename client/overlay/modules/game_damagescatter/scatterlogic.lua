-- game_damagescatter, pure logic (client/MANIFEST.md "Damage number scatter"; tested by scatterlogic_test.lua).
-- Every animated number above the map (damage, healing, mana, experience) rises on the same line, so an area hit or a
-- group hunt stacks them into one column. Base patch 0081 lets Lua shift a number by a few pixels and scale its speed;
-- this file decides how much. Settings are kept per character (g_settings node SETTINGS_NODE, key "world/name").
-- No engine calls here: the engine file passes the clock and the settings in.
DamageScatterLogic = DamageScatterLogic or {}
local L = DamageScatterLogic

L.SETTINGS_NODE = 'chaosDamageScatter'
L.LEVELS = 3
L.DEFAULT = { enabled = true, level = 2 }
-- per level: the largest sideways and vertical shift in pixels, and how far the speed may stray (0.15 = 85% .. 115%)
L.STRENGTH = {
  { x = 6,  y = 4,  speed = 0.08 },
  { x = 12, y = 8,  speed = 0.15 },
  { x = 20, y = 12, speed = 0.25 },
}
-- the texts of one hit (the physical number and the element number sit side by side) share one roll: texts on the same
-- square within this many milliseconds are one group
L.GROUP_MS = 80

function L.key(world, name)
  if type(name) ~= 'string' or name == '' then return nil end
  return (type(world) == 'string' and world ~= '' and world or '-') .. '/' .. name
end

-- a stored setting from anywhere (a hand-edited file): { enabled = bool, level = 1 .. LEVELS }
function L.sanitize(raw)
  local out = { enabled = L.DEFAULT.enabled, level = L.DEFAULT.level }
  if type(raw) ~= 'table' then return out end
  if type(raw.enabled) == 'boolean' then out.enabled = raw.enabled end
  local lv = tonumber(raw.level)
  if lv and lv == lv and lv ~= math.huge and lv ~= -math.huge then
    lv = math.floor(lv + 0.5)
    if lv < 1 then lv = 1 elseif lv > L.LEVELS then lv = L.LEVELS end
    out.level = lv
  end
  return out
end

-- the settings of one character out of the whole node
function L.settingsFor(node, key)
  if type(node) ~= 'table' or not key then return L.sanitize(nil) end
  return L.sanitize(node[key])
end

-- the node with this character's settings written in; only the known fields are kept
function L.withSettings(node, key, settings)
  local out = {}
  if type(node) == 'table' then
    for k, v in pairs(node) do out[k] = v end
  end
  if key then out[key] = L.sanitize(settings) end
  return out
end

-- a small generator of its own (Park-Miller; doubles keep it exact on LuaJIT and Lua 5.3), so the game's math.random
-- state is left alone. next() answers 0 <= r < 1.
function L.newRng(seed)
  local state = tonumber(seed) or 1
  state = math.floor(math.abs(state)) % 2147483647
  if state == 0 then state = 1 end
  local rng = {}
  function rng.next()
    state = (state * 16807) % 2147483647
    return (state - 1) / 2147483646
  end
  return rng
end

local function spread(r, limit)
  local v = (r * 2 - 1) * limit
  return v >= 0 and math.floor(v + 0.5) or -math.floor(-v + 0.5)
end

-- one roll for a level: dx, dy in pixels (up is negative) and the speed scale
function L.roll(level, rng)
  local s = L.STRENGTH[level] or L.STRENGTH[L.DEFAULT.level]
  local dx = spread(rng.next(), s.x)
  local dy = spread(rng.next(), s.y)
  local speed = 1 + (rng.next() * 2 - 1) * s.speed
  return dx, dy, speed
end

-- Group state: { x, y, z, at, dx, dy, speed }. For a text at pos (table x, y, z) at clock `now` (milliseconds) answer
-- dx, dy, speed: the roll of the group when the last text was on the same square within GROUP_MS, else a new roll.
-- Answers nil when the settings are off.
function L.pick(group, settings, pos, now, rng)
  if not settings or not settings.enabled then return nil end
  if type(pos) == 'table' and group.at and now - group.at <= L.GROUP_MS and group.x == pos.x and group.y == pos.y
      and group.z == pos.z then
    return group.dx, group.dy, group.speed
  end
  local dx, dy, speed = L.roll(settings.level, rng)
  group.x, group.y, group.z = pos and pos.x, pos and pos.y, pos and pos.z
  group.at, group.dx, group.dy, group.speed = now, dx, dy, speed
  return dx, dy, speed
end
