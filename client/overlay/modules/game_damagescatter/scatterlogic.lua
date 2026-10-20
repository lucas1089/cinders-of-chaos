-- game_damagescatter, pure logic (client/MANIFEST.md "Damage number scatter" and "Typed impact numbers"; tested by
-- scatterlogic_test.lua). Every animated number above the map (damage, healing, mana, experience) rises on the same
-- line, so an area hit or a group hunt stacks them into one column. Base patch 0081 lets Lua shift a number by a few
-- pixels and scale its speed; base patch 0100 adds a drift (the way and direction it floats), a font per number type
-- (the server tags each number) and numbers that follow their creature. This file decides how much. Settings are kept
-- per character (g_settings node SETTINGS_NODE, key "world/name").
-- No engine calls here: the engine file passes the clock and the settings in.
DamageScatterLogic = DamageScatterLogic or {}
local L = DamageScatterLogic

L.SETTINGS_NODE = 'chaosDamageScatter'
L.LEVELS = 3
L.DEFAULT = { enabled = true, level = 2 }
-- per level: the largest sideways and vertical shift in pixels, and how far the speed may stray (0.15 = 85% .. 115%)
-- Base patch 0100 adds the drift: sideways up to driftX pixels either way and a rise of riseMin .. riseMax pixels over
-- the life of the number (the stock rise is 48)
L.STRENGTH = {
  { x = 6,  y = 4,  speed = 0.08, driftX = 6,  riseMin = 44, riseMax = 52 },
  { x = 12, y = 8,  speed = 0.15, driftX = 14, riseMin = 40, riseMax = 56 },
  { x = 20, y = 12, speed = 0.25, driftX = 24, riseMin = 36, riseMax = 60 },
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
function L.sameGroup(group, pos, now)
  return type(pos) == 'table' and group.at ~= nil and now - group.at <= L.GROUP_MS and group.x == pos.x
    and group.y == pos.y and group.z == pos.z
end

function L.pick(group, settings, pos, now, rng)
  if not settings or not settings.enabled then return nil end
  if L.sameGroup(group, pos, now) then
    return group.dx, group.dy, group.speed
  end
  local dx, dy, speed = L.roll(settings.level, rng)
  group.x, group.y, group.z = pos and pos.x, pos and pos.y, pos and pos.z
  group.at, group.dx, group.dy, group.speed = now, dx, dy, speed
  return dx, dy, speed
end

-- ---------------------------------------------------------------- typed impact numbers (base patch 0100)
-- The number types the server sends (TextMessage typeId; server/src-patches/0051 ChaosImpactType, Chaos.impactType in
-- chaos_constants.lua). 6 and up are free for scripts (player:sendTextMessage(..., percent, typeId, creature)).
L.TYPE = { NORMAL = 0, CRITICAL = 1, CONDITION = 2, MANA_DRAIN = 3, MANA_GAIN = 4, ENERGY_SHIELD = 5 }
-- Otc::MessageMode of this client as g_map.onImpactText gets it (const.h; not the wire numbers 23..29 of 10.98)
L.MODE = {
  DAMAGE_DEALT = 21, DAMAGE_RECEIVED = 22, HEAL = 23, EXP = 24,
  DAMAGE_OTHERS = 25, HEAL_OTHERS = 26, EXP_OTHERS = 27, MANA = 41,
}
-- the font per type (a type not listed keeps the stock number font): a critical hit in the big bordered display font,
-- a damage-over-time tick in the small bordered one, so a tick never merges into a hit
L.FONTS = {
  [L.TYPE.CRITICAL] = 'chaos-display-16px',
  [L.TYPE.CONDITION] = 'chaos-outline-11px',
}
-- a critical hit floats a little slower, so it is read
L.CRIT_SPEED = 0.85

function L.isExperience(mode)
  return mode == L.MODE.EXP or mode == L.MODE.EXP_OTHERS
end

-- the font of a number type, or nil for the stock one; `exists(name)` tells whether the client has the font loaded
function L.fontFor(typeId, exists)
  local name = L.FONTS[tonumber(typeId) or -1]
  if not name then return nil end
  if type(exists) == 'function' and not exists(name) then return nil end
  return name
end

-- one drift for a level: sx (pixels sideways over the whole life, either way) and sy (up: negative)
function L.rollDrift(level, rng)
  local s = L.STRENGTH[level] or L.STRENGTH[L.DEFAULT.level]
  local sx = spread(rng.next(), s.driftX)
  local rise = s.riseMin + math.floor(rng.next() * (s.riseMax - s.riseMin + 1))
  if rise > s.riseMax then rise = s.riseMax end
  return sx, -rise
end

-- For an impact number: dx, dy, speed (as pick) and the drift sx, sy. The texts of one hit share the shift, the speed
-- and the drift. Experience floats straight up (sx 0), a critical hit a little slower. Nil when the settings are off.
function L.pickImpact(group, settings, pos, now, rng, typeId, mode)
  if not settings or not settings.enabled then return nil end
  local same = L.sameGroup(group, pos, now)
  local dx, dy, speed = L.pick(group, settings, pos, now, rng)
  if not same or group.sx == nil then
    group.sx, group.sy = L.rollDrift(settings.level, rng)
  end
  local sx, sy = group.sx, group.sy
  if L.isExperience(mode) then sx = 0 end
  if tonumber(typeId) == L.TYPE.CRITICAL then speed = speed * L.CRIT_SPEED end
  return dx, dy, speed, sx, sy
end

-- the option "Damage numbers follow the creature" (Options > Interface, `attachedImpactText`): on unless set to false
function L.attachedWanted(value)
  return value ~= false
end
