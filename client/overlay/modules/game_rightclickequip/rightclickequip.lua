-- Right-click equips items (logic and the protocol: rightclickequiplogic.lua; server: src-patch 0024 and
-- data/scripts/chaos/rightclick_equip.lua; server/README.md "Right-click equips"). The equipping is the server's: the
-- base mouse controls already send a use for the click this needs (a right-click in Classic Controls). This module
-- sends the option "Right-click equips items" (Options > Interface, client base patch 0037) at every login and when it
-- changes, and wraps game_interface's processMouseAction for one case: the use click on a multi-use weapon from the
-- server's list, in the inventory or an open container, sends a plain use instead of starting a use with. Every
-- other click goes to the base handler unchanged.
local L = RightClickEquipLogic
local lastSent
local multiUse = {}
local original, wrapped
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[rightclickequip] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

-- a settings value, or nil when the settings module or the option is not there (ours counts as on)
local function option(key)
  local s = modules.client_settings
  local opts = s and s.GameOptions
  if not opts or not opts.getDataSet then return nil end
  local ok, data = pcall(opts.getDataSet, opts, key or L.OPTION)
  if not ok or type(data) ~= 'table' then return nil end
  return data.value
end

-- the base handler's arguments: (tile, menuPosition, mouseButton, autoWalkPos, lookThing, useThing, ...); an item
-- widget of the inventory or a container passes no tile (gamelib UIItem)
local function equipClick(tile, mouseButton, useThing)
  if tile or not useThing or not useThing.isItem or not useThing:isItem() then return false end
  if mouseButton ~= MouseLeftButton and mouseButton ~= MouseRightButton then return false end
  if not useThing:isMultiUse() then return false end
  local other = mouseButton == MouseLeftButton and MouseRightButton or MouseLeftButton
  local yes = L.shouldEquip({
    option = option(),
    multiUse = true,
    clientId = useThing:getId(),
    ids = multiUse,
    pos = useThing:getPosition(),
    mode = option('classicControl'),
    button = mouseButton == MouseLeftButton and 'left' or 'right',
    mods = { ctrl = g_keyboard.isCtrlPressed(), shift = g_keyboard.isShiftPressed(), alt = g_keyboard.isAltPressed() },
    both = g_mouse.isPressed(other),
  })
  if yes then g_game.use(useThing) end
  return yes
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

-- called by the settings module (dataset.lua, base patch 0037) before the new value is stored
function onOptionChange(value)
  safe('option', send)(value, false)
end

local function onMessage(protocol, opcode, msg)
  if type(msg) == 'table' and msg.action == 'multiuse' and type(msg.data) == 'table' then
    multiUse = L.idSet(msg.data.ids)
  end
end

local handlers = {}

function init()
  local gi = modules.game_interface
  if gi and gi.processMouseAction then
    original = gi.processMouseAction
    local check = safe('click', equipClick)
    wrapped = function(tile, menuPosition, mouseButton, ...)
      local useThing = select(3, ...)
      if check(tile, mouseButton, useThing) then return true end
      return original(tile, menuPosition, mouseButton, ...)
    end
    gi.processMouseAction = wrapped
  end
  ProtocolGame.registerExtendedJSONOpcode(L.OPCODE, safe('opcode', onMessage))
  handlers.start = safe('start', function()
    lastSent = nil
    send(option(), true)
  end)
  handlers.stop = function() lastSent = nil end
  connect(g_game, { onGameStart = handlers.start, onGameEnd = handlers.stop })
  if g_game.isOnline() then addEvent(handlers.start) end
end

function terminate()
  local gi = modules.game_interface
  if gi and wrapped and gi.processMouseAction == wrapped then gi.processMouseAction = original end
  original, wrapped = nil, nil
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, L.OPCODE)
  disconnect(g_game, { onGameStart = handlers.start, onGameEnd = handlers.stop })
  lastSent = nil
end
