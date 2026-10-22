-- Level-up effect: when a character on screen gains a level, the pack's level-up effect plays on it (pair 36; the
-- golden wing images of earlier versions are retired). The server (server/data/scripts/chaos/levelwings.lua) sends
-- extended opcode 191, JSON {action = 'play', data = {id = creature id, lv = new level, n = levels gained}}, to every
-- player who sees the character; the stock level-up text and effect are untouched.
--
-- Drawing: an effect of the client pair (LevelWingsMath.EFFECT) added to the character's tile with Effect.create and
-- g_map.addThing, so it plays on the map like a spell effect. A pair without it (older than 36): nothing is drawn.
--
-- Settings (Options > Effects, client base patch 0036): "Level-up wings on my character" (levelWingsOwn) and
-- "Level-up wings on other characters" (levelWingsOthers), both on by default; they switch this effect. Without them
-- (an older settings module) both count as on.

local OPCODE = 191

local reported = {}
local effectOk = nil

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[levelwings] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

-- a settings value, or nil when the settings module or the option is not there
local function option(key)
  local s = modules.client_settings
  local opts = s and s.GameOptions
  if not opts or not opts.getDataSet then return nil end
  local ok, data = pcall(opts.getDataSet, opts, key)
  if not ok or type(data) ~= 'table' then return nil end
  return data.value
end

-- the pair has the effect and the client can add one to a tile
local function hasEffect()
  if effectOk == nil then
    effectOk = false
    local id = LevelWingsMath.EFFECT.id
    if id > 0 and type(Effect) == 'table' and Effect.create and g_map and g_map.addThing and g_things then
      local ok, valid = pcall(function()
        if g_things.isValidDatId then return g_things.isValidDatId(id, ThingCategoryEffect) end
        return g_things.getThingType(id, ThingCategoryEffect) ~= nil
      end)
      effectOk = ok and valid and true or false
    end
    if not effectOk then
      g_logger.info('[levelwings] the client pair has no level-up effect (pair 36): nothing is drawn')
    end
  end
  return effectOk
end

-- play the effect on a creature now (also used by hand from the terminal: modules.game_levelwings.play(id))
function play(id)
  local c = g_map.getCreatureById(id)
  if not c or not hasEffect() then return false end
  if not LevelWingsMath.wanted(c:isLocalPlayer(), option('levelWingsOwn'), option('levelWingsOthers')) then
    return false
  end
  local pos = LevelWingsMath.effectPos(c:getPosition())
  if not pos then return false end
  local e = Effect.create()
  e:setId(LevelWingsMath.EFFECT.id)
  g_map.addThing(e, pos, -1)
  return true
end

local function onMessage(protocol, opcode, msg)
  local id = LevelWingsMath.playId(msg)
  if id then play(id) end
end

function init()
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, safe('opcode', onMessage))
end

function terminate()
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
end
