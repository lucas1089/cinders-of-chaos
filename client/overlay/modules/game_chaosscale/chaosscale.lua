-- game_chaosscale: keeps the display scale of the own level (scalelogic.lua; server display_scale.lua, opcode 157).
-- Spell mana costs are fixed numbers and never follow the factor (server/README.md "Fixed spell costs").
-- A hello at every game start (and when the module loads in game) asks the server for the factor: a reattach to a
-- character that stayed in the game runs no onLogin on the server. A hello too when the own level differs from the one
-- of the last factor: the server sends a new factor at a level up (onAdvance), but a level lost (death, a removed
-- experience) runs no event there.

local OPCODE = 157

local function apply(f)
  ChaosScale.factor = f
end

local function onMessage(protocol, opcode, msg)
  local f, level = ChaosScale.parse(msg)
  if not f then
    return
  end
  ChaosScale.level = level
  apply(f)
end

local function onGameEnd()
  ChaosScale.level = 0
  apply(1)
end

local function sendHello()
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, json.encode(ChaosScale.hello()))
  end
end

local function onLevelChange(localPlayer, level)
  if ChaosScale.levelChanged(level) then
    sendHello()
  end
end

function init()
  -- the module is sandboxed (its init / terminate stay its own); the factor and its helpers are shared globals
  _G.ChaosScale = ChaosScale
  _G.chaosDisplayFactor = chaosDisplayFactor
  _G.chaosDisplayValue = chaosDisplayValue
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, function(protocol, opcode, msg)
    local ok, err = pcall(onMessage, protocol, opcode, msg)
    if not ok then
      g_logger.warning('[chaosscale] ' .. tostring(err))
    end
  end)
  connect(g_game, { onGameStart = sendHello, onGameEnd = onGameEnd })
  connect(LocalPlayer, { onLevelChange = onLevelChange })
  if g_game.isOnline() then
    sendHello()
  end
end

function terminate()
  disconnect(g_game, { onGameStart = sendHello, onGameEnd = onGameEnd })
  disconnect(LocalPlayer, { onLevelChange = onLevelChange })
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  apply(1)
end
