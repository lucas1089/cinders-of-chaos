-- Keep attacking while moving (logic and the protocol: kitewalklogic.lua; server: src-patch 0028 and
-- data/scripts/chaos/kitewalk.lua; server/README.md "Keep attacking while moving"). The kiting itself is the server's;
-- this module sends the option "Keep attacking while moving" (Options > Interface, client base patch 0039) at every
-- login and when it changes.
local L = KiteWalkLogic
local lastSent
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[kitewalk] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

-- the settings value, or nil when the settings module or the option is not there (counts as on)
local function option()
  local s = modules.client_settings
  local opts = s and s.GameOptions
  if not opts or not opts.getDataSet then return nil end
  local ok, data = pcall(opts.getDataSet, opts, L.OPTION)
  if not ok or type(data) ~= 'table' then return nil end
  return data.value
end

local function send(value, force)
  if not g_game.isOnline() then return end
  local on = L.isOn(value)
  if not L.needsSend(lastSent, on, force) then return end
  local protocol = g_game.getProtocolGame()
  if not protocol then return end
  protocol:sendExtendedOpcode(L.OPCODE, json.encode(L.message(on)))
  lastSent = on
end

-- called by the settings module (dataset.lua, base patch 0039) before the new value is stored
function onOptionChange(value)
  safe('option', send)(value, false)
end

local handlers = {}

function init()
  handlers.start = safe('start', function()
    lastSent = nil
    send(option(), true)
  end)
  handlers.stop = function() lastSent = nil end
  connect(g_game, { onGameStart = handlers.start, onGameEnd = handlers.stop })
  if g_game.isOnline() then addEvent(handlers.start) end
end

function terminate()
  disconnect(g_game, { onGameStart = handlers.start, onGameEnd = handlers.stop })
  lastSent = nil
end
