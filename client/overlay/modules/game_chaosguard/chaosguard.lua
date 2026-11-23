-- game_chaosguard: sends the client guard's module hello once per login (guardhello.lua; server clientguard.lua), and the bot
-- detection's two signals (O722; integrity.lua, server botdet.lua): the digests of the client's modules and mods, and the codes of
-- known external tools the Windows scan finds (base patch 0207). Both only report; nothing is closed, removed or stopped.
local OPCODE = 190 -- ChaosOpcodes.clientGuardHello
local BOTDET = 169 -- ChaosOpcodes.botdet

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

-- the digests of the modules: a slice of files every 30 ms, so the login screen of the game never stalls on it
local run = 0
local function sendIntegrity()
  run = run + 1
  local mine = run
  local files = {}
  for _, root in ipairs(Integrity.ROOTS) do
    local ok, list = pcall(g_resources.listDirectoryFiles, root, true, false, true)
    if ok and type(list) == 'table' then
      for _, f in ipairs(list) do
        if Integrity.split(f) then files[#files + 1] = f end
      end
    end
  end
  local hashes, i = {}, 1
  local function slice()
    if mine ~= run or not g_game.isOnline() then return end
    local stop = math.min(#files, i + 39)
    while i <= stop do
      local ok, h = pcall(g_resources.fileSha256, files[i])
      if ok and type(h) == 'string' then hashes[files[i]] = h end
      i = i + 1
    end
    if i <= #files then
      scheduleEvent(slice, 30)
      return
    end
    local sha = g_crypt and g_crypt.sha256Encode
    local protocol = g_game.getProtocolGame()
    if not sha or not protocol then return end
    local build = g_game.getChaosClientBuild and g_game.getChaosClientBuild() or 0
    local digests = Integrity.digests(files, function(p) return hashes[p] end, sha)
    for n, chunk in ipairs(Integrity.chunks(digests, build)) do
      scheduleEvent(function()
        local p = g_game.getProtocolGame()
        if mine == run and p then
          p:sendExtendedOpcode(BOTDET, json.encode(Integrity.integrityMessage(chunk)))
        end
      end, n * 400)
    end
  end
  scheduleEvent(slice, 6000) -- after the login settles
end

-- the server's list of known tools (hashed names and short codes, kept by staff): the scan answers with the codes it found only
local function onTools(protocol, opcode, data)
  if type(data) ~= 'table' or data.action ~= 'tools' or type(data.data) ~= 'table' then return end
  if not (g_game.chaosScanTools and protocol) then return end
  local spec = Integrity.toolSpec(data.data.t)
  if spec == '' then return end
  local ok, answer = pcall(g_game.chaosScanTools, spec)
  local codes = ok and Integrity.toolCodes(answer) or {}
  if #codes > 0 then
    protocol:sendExtendedOpcode(BOTDET, json.encode(Integrity.toolMessage(codes)))
  end
end

function onGameStart()
  sendHello()
  sendIntegrity()
end

function onGameEnd()
  run = run + 1
end

function init()
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  ProtocolGame.registerExtendedJSONOpcode(BOTDET, onTools)
  if g_game.isOnline() then
    sendHello()
  end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, BOTDET)
end
