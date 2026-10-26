-- Drop feed option window. Opened from the top menu (System > Drop Feed). The choice (off / unique / legendary) is kept in
-- the client settings and sent to the server (extended opcode 229, action feedopt) at login and when it changes; the
-- server filters the lines (retention_loot.lua). The logic is in dropfeed_logic.lua.

local L = DropFeedLogic

local window
local settings = L.normalize(nil)
local updatingUi = false

local function safe(name, fn)
  local reported = false
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok and not reported then
      reported = true
      g_logger.warning('[dropfeed] ' .. name .. ': ' .. tostring(err))
    end
  end
end

local function loadSettings()
  settings = L.normalize(g_settings.getNode(L.SETTINGS_NODE))
end

local function saveSettings()
  g_settings.setNode(L.SETTINGS_NODE, settings)
end

local function sendMode()
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(L.OPCODE, L.packet(settings.mode, json.encode))
  end
end

local function refreshWindow()
  if not window then return end
  updatingUi = true
  local names = L.modeNames()
  local combo = window.modeCombo
  combo:clearOptions()
  for _, k in ipairs(L.MODES) do combo:addOption(names[k], k) end
  combo:setCurrentIndex(L.indexOf(settings.mode))
  updatingUi = false
end

local function onModeChange()
  if updatingUi or not window then return end
  local o = window.modeCombo:getCurrentOption()
  if not o or not L.valid(o.data) or o.data == settings.mode then return end
  settings = L.normalize({ mode = o.data })
  saveSettings()
  sendMode()
end

function show()
  if not window then return end
  refreshWindow()
  window:show()
  window:raise()
  window:focus()
end

function hide()
  if window then window:hide() end
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

local function onGameStart()
  -- the server may not have the player's events registered the very moment the game starts
  scheduleEvent(safe('send', sendMode), 1500)
end

function init()
  g_ui.importStyle('dropfeed')
  loadSettings()
  local ok, ui = pcall(g_ui.createWidget, 'ChaosDropFeedWindow', rootWidget)
  if ok and ui then
    window = ui
    window:hide()
    window.modeCombo.onOptionChange = safe('ui', onModeChange)
  else
    g_logger.warning('[dropfeed] window not loaded: ' .. tostring(ui))
  end
  connect(g_game, { onGameStart = onGameStart })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart })
  if window then
    window:destroy()
    window = nil
  end
end
