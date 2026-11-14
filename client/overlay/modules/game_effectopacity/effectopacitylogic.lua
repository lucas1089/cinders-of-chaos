-- Effect opacity, the logic without client API (tested by effectopacitylogic_test.lua).
-- Client base patch 0049 left ONE slider; 0202 (O567) has two, both 0..100 % in steps of 5, default 100:
--   * "Opacity of my effects"             g_settings key opacityEffects (the base key, kept): the effects the server marked as the
--     player's own (extended opcode 164, server data/lib/chaos_fx_owner.lua), the engine's own alpha;
--   * "Opacity of other players' effects"  key opacityOtherEffects: every effect that was not marked (other players', monsters'),
--     the engine's other-player alpha. The engine cannot tell those two apart, so monsters follow this one.
-- Warnings (boss circles and fills) ignore both (WARNING_IDS, g_client.setEffectAlphaExempt). Missiles have their own slider.
-- The server only sends marks while the two values differ (hello need = 1), so the default 100 / 100 costs nothing.
-- Once per settings file this module moves old values over: the lowest value a player had set on any of the old controls becomes
-- opacityEffects (flag chaosEffectOpacityMigrated, 0049), and that value is copied to the new opacityOtherEffects (flag
-- chaosEffectOpacityOthersMigrated, 0202), so someone who had dimmed effects keeps them dimmed for everybody's effects. After that
-- it only clamps a stored value that is out of range.
EffectOpacityLogic = {}
local L = EffectOpacityLogic

L.KEY = 'opacityEffects'                        -- the base key, kept: my effects
L.KEY_OTHERS = 'opacityOtherEffects'            -- the other players' effects (0202)
L.OLD_KEYS = { 'ownSpellOpacity', 'spellOpacityOwn' } -- Options > Effects "Own Spells Effect", HP/MP circle "Own Spells"
L.FLAG = 'chaosEffectOpacityMigrated'
L.FLAG_OTHERS = 'chaosEffectOpacityOthersMigrated'
L.MIN = 0                                       -- 0049 had 25 so warnings never vanished; warnings are exempt now (0202)
L.MAX = 100
L.STEP = 5
L.DEFAULT = 100

L.OPCODE = 164                                  -- ChaosOpcodes.fxOwner (server chaos_constants.lua)
-- effect ids of boss warnings (the ChaosVfx names with telegraph / warning / danger; server tests/fx_owner_test.lua keeps the list
-- whole): they ignore both sliders
L.WARNING_IDS = { 450, 451, 635, 636, 637, 745, 3905, 3906, 4072 }
L.MAX_MARKS = 400                               -- groups of one message (chaosfxowner.h kMaxMarks)
L.MAX_OFFSET = 127

-- any stored value -> a whole percent in MIN..MAX on the STEP grid (nil, text or junk -> DEFAULT)
function L.clamp(value)
  local n = tonumber(value)
  if not n or n ~= n or n == math.huge or n == -math.huge then
    return L.DEFAULT
  end
  n = math.floor(n / L.STEP + 0.5) * L.STEP
  if n < L.MIN then n = L.MIN end
  if n > L.MAX then n = L.MAX end
  return math.floor(n)
end

-- saved: {[key] = number or nil (not stored)} for KEY and OLD_KEYS -> the one value to keep
function L.migrate(saved)
  saved = saved or {}
  local low
  for _, k in ipairs({ L.KEY, L.OLD_KEYS[1], L.OLD_KEYS[2] }) do
    local n = tonumber(saved[k])
    if n and n == n and (not low or n < low) then
      low = n
    end
  end
  return L.clamp(low)
end

-- what to do at start: nil (nothing), or the value to store and apply
function L.plan(migrated, saved)
  if not migrated then
    return L.migrate(saved)
  end
  local cur = saved and saved[L.KEY]
  if cur == nil then
    return nil
  end
  local v = L.clamp(cur)
  return v ~= tonumber(cur) and v or nil
end

-- 0202: the other-players slider at start -> nil (nothing to do) or the value to store and apply. Not migrated yet: the value of
-- the first slider (nothing stored: nothing to do, both stay at the default). Migrated: only an out-of-range value is clamped.
function L.planOthers(migrated, saved)
  saved = saved or {}
  if not migrated then
    local own = tonumber(saved[L.KEY])
    if own == nil or own ~= own then
      return nil
    end
    return L.clamp(own)
  end
  local cur = saved[L.KEY_OTHERS]
  if cur == nil then
    return nil
  end
  local v = L.clamp(cur)
  return v ~= tonumber(cur) and v or nil
end

-- does the server need to mark the player's own effects: only while the two sliders differ
function L.needsMarks(own, others)
  return L.clamp(own) ~= L.clamp(others)
end

-- the message to the server: hello {need = 0 | 1}
function L.hello(need)
  return { action = 'hello', need = need and 1 or 0 }
end

local function whole(v)
  return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge and v == math.floor(v)
end

-- the server's message {action = 'marks', data = {b = {x, y, z}, m = {kind, dx, dy, id, ...}}} -> x, y, z, flat: the list the
-- engine reads, cut to whole groups of 4 with a kind of 0 or 1, offsets inside MAX_OFFSET and an id of 1..65535, at most MAX_MARKS
-- groups. nil when it is not a usable message or no group is left.
function L.parseMarks(msg)
  if type(msg) ~= 'table' or msg.action ~= 'marks' or type(msg.data) ~= 'table' then
    return nil
  end
  local b, m = msg.data.b, msg.data.m
  if type(b) ~= 'table' or type(m) ~= 'table' then
    return nil
  end
  local x, y, z = b[1], b[2], b[3]
  if not (whole(x) and whole(y) and whole(z)) or x < 0 or y < 0 or x > 65534 or y > 65534 or z < 0 or z > 15 then
    return nil
  end
  local flat, n = {}, 0
  for g = 0, math.floor(#m / 4) - 1 do
    local kind, dx, dy, id = m[4 * g + 1], m[4 * g + 2], m[4 * g + 3], m[4 * g + 4]
    if whole(kind) and whole(dx) and whole(dy) and whole(id) and (kind == 0 or kind == 1)
        and math.abs(dx) <= L.MAX_OFFSET and math.abs(dy) <= L.MAX_OFFSET and id >= 1 and id <= 65535 then
      flat[n + 1], flat[n + 2], flat[n + 3], flat[n + 4] = kind, dx, dy, id
      n = n + 4
      if n >= 4 * L.MAX_MARKS then break end
    end
  end
  if n == 0 then
    return nil
  end
  return x, y, z, flat
end
