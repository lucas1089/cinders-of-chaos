-- Spell effect opacity (effectopacitylogic.lua): at start, the old per-source opacity values are moved into the one
-- slider of base patch 0049 (Options > Effects, "Spell effects opacity", g_settings key opacityEffects) once, and a
-- stored value out of 25..100 is clamped. The slider and its apply are the settings module's own.

local function saved(key)
  local ok, has = pcall(g_settings.exists, key)
  if not ok or not has then return nil end
  local ok2, v = pcall(g_settings.getNumber, key)
  return ok2 and v or nil
end

function init()
  local L = EffectOpacityLogic
  local values = { [L.KEY] = saved(L.KEY) }
  for _, k in ipairs(L.OLD_KEYS) do values[k] = saved(k) end
  local okFlag, migrated = pcall(g_settings.getBoolean, L.FLAG)
  local v = L.plan(okFlag and migrated, values)
  if v then
    local s = modules.client_settings
    local opts = s and s.GameOptions
    if opts and opts.getDataSet and opts:getDataSet(L.KEY) then
      pcall(opts.setOption, opts, L.KEY, v)          -- stores it, applies it, moves the slider
    else
      pcall(g_settings.set, L.KEY, v)
      if g_client.setEffectAlpha then pcall(g_client.setEffectAlpha, v / 100) end
    end
  end
  if not (okFlag and migrated) then
    pcall(g_settings.set, L.FLAG, true)
  end
end

function terminate()
end
