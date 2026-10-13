-- Spell effect opacity, the logic without client API (tested by effectopacitylogic_test.lua).
-- Client base patch 0049 leaves ONE control: the base settings' "opacityEffects" slider in Options > Effects, labelled
-- "Spell effects opacity", 25..100 % in steps of 5, saved under the same g_settings key as before. On 10.98 the
-- server sends no effect source, so every magic effect is drawn with the "own" alpha; the four per-source sliders
-- (Options > Effects and the HP/MP circle options) all set that same alpha and are removed by the patch.
-- This module runs once per settings file: the new value is the lowest a player had set on any of the old controls
-- (so someone who had dimmed effects keeps them dimmed), clamped to 25..100. After that it only clamps a stored value
-- that is out of range (an old 0..24, written before the patch).
EffectOpacityLogic = {}
local L = EffectOpacityLogic

L.KEY = 'opacityEffects'                        -- the base key, kept
L.OLD_KEYS = { 'ownSpellOpacity', 'spellOpacityOwn' } -- Options > Effects "Own Spells Effect", HP/MP circle "Own Spells"
L.FLAG = 'chaosEffectOpacityMigrated'
L.MIN = 25
L.MAX = 100
L.STEP = 5
L.DEFAULT = 100

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
