-- Effect opacity (O567; client/MANIFEST.md "game_effectopacity"). Two sliders in Options > Effects (base patches 0049 and 0202):
-- "Opacity of my effects" (g_settings key opacityEffects) and "Opacity of other players' effects" (opacityOtherEffects); the
-- settings module's own applies set the engine's alphas. This module does the rest:
--   * at start it moves the old values over once (effectopacitylogic.lua: the lowest of the old per-source sliders into
--     opacityEffects, then that value into opacityOtherEffects) and clamps a stored value that is out of range;
--   * it tells the engine which effect ids are warnings (g_client.setEffectAlphaExempt: boss circles and fills never fade);
--   * the engine only knows an effect as "mine" when the server says so: with the engine part of base patch 0202
--     (g_client.markEffectSources) the module sends the server `hello {need}` at every game start and whenever a slider moves
--     (need = 1 only while the two values differ, so the default 100 / 100 costs the server nothing), and the server answers
--     with `marks` messages (extended opcode 164, server data/lib/chaos_fx_owner.lua) that list the effects and missiles of the
--     player's own spells; they are handed to the engine, which gives them the own alpha. An unmarked effect counts as the
--     others'. A client without the engine part never asks.
-- Rules and message reading: effectopacitylogic.lua (effectopacitylogic_test.lua). Not run in a client.

local L = EffectOpacityLogic

local handlers = {}
local reported = {}
local values = { own = L.DEFAULT, others = L.DEFAULT } -- the two sliders now, whole percent
local lastNeed = nil                                    -- what the server was told last in this game

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[effectopacity] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function saved(key)
  local ok, has = pcall(g_settings.exists, key)
  if not ok or not has then return nil end
  local ok2, v = pcall(g_settings.getNumber, key)
  return ok2 and v or nil
end

local function flag(name)
  local ok, v = pcall(g_settings.getBoolean, name)
  return ok and v or false
end

-- store a value as the settings module would (it applies it and moves the slider); without that module (or without the
-- option, a client that has no patch 0202) the value goes to g_settings and the engine alpha directly
local function store(key, v, setAlpha)
  local s = modules.client_settings
  local opts = s and s.GameOptions
  if opts and opts.getDataSet and opts:getDataSet(key) then
    pcall(opts.setOption, opts, key, v)
  else
    pcall(g_settings.set, key, v)
    if setAlpha then pcall(setAlpha, v / 100) end
  end
end

local function hasMarks()
  return type(g_client.markEffectSources) == 'function'
end

local function sendHello(force)
  if not g_game.isOnline() then return end
  local need = hasMarks() and L.needsMarks(values.own, values.others) or false
  if not force and need == lastNeed then return end
  local protocol = g_game.getProtocolGame()
  if not protocol then return end
  lastNeed = need
  protocol:sendExtendedOpcode(L.OPCODE, json.encode(L.hello(need)))
end

-- from the settings module's applies (base patch 0202): name is opacityEffects or opacityOtherEffects
function onOption(name, value)
  local v = L.clamp(value)
  if name == L.KEY then
    values.own = v
  elseif name == L.KEY_OTHERS then
    values.others = v
  else
    return
  end
  safe('hello', sendHello)(false)
end

function state()
  return { own = values.own, others = values.others, need = lastNeed, marks = hasMarks() }
end

local function onMarks(protocol, opcode, msg)
  if not hasMarks() then return end
  local x, y, z, flat = L.parseMarks(msg)
  if not x then return end
  g_client.markEffectSources(1, x, y, z, flat)  -- 1 = the engine's own source
end

local function readValues()
  values.own = L.clamp(saved(L.KEY))
  values.others = L.clamp(saved(L.KEY_OTHERS))
end

local function onGameStart()
  lastNeed = nil
  readValues()
  sendHello(true)
end

local function onGameEnd()
  lastNeed = nil
end

local function exemptWarnings()
  if type(g_client.setEffectAlphaExempt) ~= 'function' then return end
  if type(g_client.clearEffectAlphaExempt) == 'function' then g_client.clearEffectAlphaExempt() end
  for _, id in ipairs(L.WARNING_IDS) do
    g_client.setEffectAlphaExempt(id, true)
  end
end

local function migrate()
  -- 0049: the lowest old value into the first slider, once
  local v = L.plan(flag(L.FLAG), (function()
    local t = { [L.KEY] = saved(L.KEY) }
    for _, k in ipairs(L.OLD_KEYS) do t[k] = saved(k) end
    return t
  end)())
  if v then store(L.KEY, v, g_client.setEffectAlpha) end
  if not flag(L.FLAG) then pcall(g_settings.set, L.FLAG, true) end
  -- 0202: that value into the second slider, once
  local w = L.planOthers(flag(L.FLAG_OTHERS), { [L.KEY] = saved(L.KEY), [L.KEY_OTHERS] = saved(L.KEY_OTHERS) })
  if w then store(L.KEY_OTHERS, w, g_client.setOtherPlayerSpellEffectAlpha) end
  if not flag(L.FLAG_OTHERS) then pcall(g_settings.set, L.FLAG_OTHERS, true) end
end

function init()
  safe('migrate', migrate)()
  safe('exempt', exemptWarnings)()
  readValues()
  handlers.opcode = safe('marks', onMarks)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  ProtocolGame.registerExtendedJSONOpcode(L.OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, L.OPCODE)
  if handlers.game then disconnect(g_game, handlers.game) end
  handlers = {}
  if g_game.isOnline() and lastNeed then
    -- the server stops marking
    local protocol = g_game.getProtocolGame()
    if protocol then pcall(protocol.sendExtendedOpcode, protocol, L.OPCODE, json.encode(L.hello(false))) end
  end
  lastNeed = nil
end
