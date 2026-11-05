-- The layout options window (client/MANIFEST.md "Floating chat and central hotbar (O414)"): the layout mode (Classic or
-- Action bar, applied at the next login), the hotbar (globes, slots, scale) and the floating chat (show while typing,
-- opacity, fade). Opened from the hotbar's right-click menu and gear button, the chat's gear, and a button added to
-- Options > Interface when the Options window has one (best effort; the other entries always work).
-- Global ChaosLayoutOptions.open() / close(). Values go to ChaosHotbar and ChaosFloatChat, which keep them per character.
ChaosLayoutOptions = ChaosLayoutOptions or {}
local M = ChaosLayoutOptions
local HL, FL = HotbarLogic, FloatChatLogic

local window
local updating = false

local function alive(w) return w ~= nil and not w:isDestroyed() end

local function modeNames()
  return { tr('Action bar (floating chat, central hotbar)'), tr('Classic (chat and action bars at the bottom)') }
end

local function refresh()
  if not alive(window) then return end
  updating = true
  local lm = rawget(_G, 'ChaosLayoutMode')
  local hb, fc = rawget(_G, 'ChaosHotbar'), rawget(_G, 'ChaosFloatChat')
  local bar = (hb and hb.getSettings and hb.getSettings()) or HL.settingsFor(nil, nil)
  local chat = (fc and fc.getSettings and fc.getSettings()) or FL.settingsFor(nil, nil)
  local names = modeNames()
  local picked = lm and lm.picked and lm.picked() or 'classic'
  window.mode:setCurrentIndex(picked == 'action' and 1 or 2, true)
  window.globes:setChecked(bar.globes ~= false)
  for i, c in ipairs(HL.COUNTS) do
    if c == bar.count then window.count:setCurrentIndex(i, true) end
  end
  window.scale:setValue(bar.scale)
  window.scaleLabel:setText(tr('Bar size: %d%%', bar.scale))
  window.hideOnSend:setChecked(chat.hideOnSend ~= false)
  window.opacity:setValue(chat.opacity)
  window.opacityLabel:setText(tr('Chat opacity: %d%%', chat.opacity))
  window.fade:setChecked(chat.fade == true)
  window.fadeSeconds:setValue(chat.fadeSeconds)
  window.fadeLabel:setText(tr('Fade after %d seconds', chat.fadeSeconds))
  -- the bar and chat options only mean something in the action bar layout
  local action = lm and lm.isAction and lm.isAction()
  for _, id in ipairs({ 'globes', 'count', 'scale', 'hideOnSend', 'opacity', 'fade', 'fadeSeconds', 'resetPlace' }) do
    window[id]:setEnabled(action == true)
  end
  updating = false
  return names
end

local function build()
  if alive(window) then return true end
  g_ui.importStyle('hotbar')
  local ok, w = pcall(g_ui.createWidget, 'ChaosLayoutOptionsWindow', rootWidget)
  if not ok or not w then
    g_logger.warning('[hotbar] options window not loaded: ' .. tostring(w))
    return false
  end
  window = w
  for _, name in ipairs(modeNames()) do window.mode:addOption(name) end
  for _, c in ipairs(HL.COUNTS) do window.count:addOption(tostring(c)) end
  window.scale:setRange(HL.SCALE_MIN, HL.SCALE_MAX)
  window.opacity:setRange(FL.OPACITY_MIN, FL.OPACITY_MAX)
  window.fadeSeconds:setRange(FL.FADE_MIN, FL.FADE_MAX)
  window.mode.onOptionChange = function(_, text, data)
    if updating then return end
    local lm = rawget(_G, 'ChaosLayoutMode')
    local index = window.mode.currentIndex or 1
    if lm and lm.set then lm.set(index == 1 and 'action' or 'classic') end
  end
  window.count.onOptionChange = function(_, text)
    if updating then return end
    local hb = rawget(_G, 'ChaosHotbar')
    if hb then hb.setOption('count', tonumber(text)) end
  end
  window.globes.onCheckChange = function(_, checked)
    if updating then return end
    local hb = rawget(_G, 'ChaosHotbar')
    if hb then hb.setOption('globes', checked) end
  end
  window.scale.onValueChange = function(_, value)
    if updating then return end
    local hb = rawget(_G, 'ChaosHotbar')
    window.scaleLabel:setText(tr('Bar size: %d%%', value))
    if hb then hb.setOption('scale', value) end
  end
  window.hideOnSend.onCheckChange = function(_, checked)
    if updating then return end
    local fc = rawget(_G, 'ChaosFloatChat')
    if fc then fc.setOption('hideOnSend', checked) end
  end
  window.opacity.onValueChange = function(_, value)
    if updating then return end
    local fc = rawget(_G, 'ChaosFloatChat')
    window.opacityLabel:setText(tr('Chat opacity: %d%%', value))
    if fc then fc.setOption('opacity', value) end
  end
  window.fade.onCheckChange = function(_, checked)
    if updating then return end
    local fc = rawget(_G, 'ChaosFloatChat')
    if fc then fc.setOption('fade', checked) end
  end
  window.fadeSeconds.onValueChange = function(_, value)
    if updating then return end
    local fc = rawget(_G, 'ChaosFloatChat')
    window.fadeLabel:setText(tr('Fade after %d seconds', value))
    if fc then fc.setOption('fadeSeconds', value) end
  end
  window.resetPlace.onClick = function()
    local hb, fc = rawget(_G, 'ChaosHotbar'), rawget(_G, 'ChaosFloatChat')
    if hb then hb.resetPlace() end
    if fc then fc.resetPlace() end
  end
  window.close.onClick = function() M.close() end
  window:hide()
  return true
end

function M.open()
  if g_app.isMobile() or not build() then return end
  refresh()
  window:show()
  window:raise()
  window:focus()
end

function M.close()
  if alive(window) then window:hide() end
end

function M.destroy()
  if alive(window) then window:destroy() end
  window = nil
end

-- A button in Options > Interface (the Options window is the base client's: its panel ids are not ours, so this looks for
-- the interface panel by a few names and does nothing when there is none)
function M.addOptionsButton()
  local cs = modules.client_settings
  local w = cs and cs.optionsWindow
  if not alive(w) or w.chaosLayoutButton then return end
  local panel
  for _, id in ipairs({ 'interfacePanel', 'interface', 'interfaceTab', 'optionsTabContent' }) do
    local ok, found = pcall(function() return w:recursiveGetChildById(id) end)
    if ok and found then panel = found break end
  end
  if not panel then return end
  local ok, b = pcall(g_ui.createWidget, 'ChaosButton', panel)
  if not ok or not b then return end
  b:setText(tr('Layout options...'))
  b:setWidth(180)
  b.onClick = function() M.open() end
  w.chaosLayoutButton = b
end

function M.init()
  if g_app.isMobile() then return end
  scheduleEvent(function() pcall(M.addOptionsButton) end, 2000)
end

function M.terminate()
  M.destroy()
end
