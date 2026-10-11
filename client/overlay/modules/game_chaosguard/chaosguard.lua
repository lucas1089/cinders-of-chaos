-- game_chaosguard: sends the client guard's module hello once per login (guardhello.lua; server clientguard.lua).
local OPCODE = 190 -- ChaosOpcodes.clientGuardHello

local function loadedModules()
  local list = {}
  for _, m in ipairs(g_modules.getModules()) do
    list[#list + 1] = { name = m:getName(), loaded = m:isLoaded() }
  end
  return list
end

local function sendHello()
  local protocol = g_game.getProtocolGame()
  if not protocol then
    return
  end
  local build = g_game.getChaosClientBuild and g_game.getChaosClientBuild() or 0
  protocol:sendExtendedOpcode(OPCODE, json.encode(GuardHello.payload(build, loadedModules())))
end

function onGameStart()
  sendHello()
end

function init()
  connect(g_game, { onGameStart = onGameStart })
  if g_game.isOnline() then
    sendHello()
  end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart })
end
