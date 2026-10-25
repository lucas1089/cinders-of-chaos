-- game_chaosweather, ambient particles (O226; client/MANIFEST.md "Ambient particles (O226)"): slow embers, motes or dust over
-- the game window, by the mood the server names in its weather message (a = 'embers' | 'motes' | 'dust', weather.lua). The
-- weather part of this module (chaosweather.lua) decodes the message and calls ChaosAmbient.setKind; this file only draws.
--   * Same method as the rain and no engine change: two image-repeated widgets (far, near) of the current kind on a clipping
--     root over the game map panel, their image rectangle moved by whole pixels every 50 ms (ChaosAmbientLogic.offset).
--   * Capped: two layers per kind, a fixed number of specks in their tiles (ChaosAmbientLogic.ART), a fixed number of
--     rectangles (maxQuads). Nothing is made or run while there is no mood or the option is off.
--   * Nothing while the window is hidden (g_window.isVisible false, e.g. minimized): the timer stops, the widgets are hidden and
--     one slow poll (HIDDEN_POLL_MS) waits for the window to come back.
--   * The option `ambientParticles` (Options > Graphics, base patch 0144) comes through game_visualfx (onOption -> setAmbientEnabled).
-- Every engine call is guarded; a failure is logged once and the effect stays off.
ChaosAmbient = {}
local M = ChaosAmbient
local A = ChaosAmbientLogic

local kind, fadeMs = nil, A.DEFAULT_FADE_MS
local enabled = true
local visible = true
local cur = A.newOpacities()
local root, widgets = nil, {}
local tickEvent, pollEvent
local lastTick, clock0 = 0, 0
local reported = {}

local function now()
  return g_clock.millis()
end

local function report(name, err)
  if not reported[name] then
    reported[name] = true
    g_logger.warning('[chaosambient] ' .. name .. ': ' .. tostring(err))
  end
end

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      report(name, res)
      return nil
    end
    return res
  end
end

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

-- the window is shown (not minimized or hidden); true when the engine cannot say
local function windowVisible()
  if not g_window or not g_window.isVisible then return true end
  local ok, res = pcall(g_window.isVisible)
  if not ok then return true end
  return res ~= false
end

-- ---------------------------------------------------------------- widgets
local function destroyWidgets()
  if alive(root) then root:destroy() end
  root, widgets = nil, {}
end

local function attach()
  if alive(root) then return true end
  local gi = modules.game_interface
  local panel = gi and gi.getMapPanel and gi.getMapPanel() or nil
  if not alive(panel) then return false end
  destroyWidgets()
  root = g_ui.createWidget('ChaosWeatherRoot')
  panel:insertChild(1, root)
  root:fill('parent')
  for _, layer in ipairs(A.LAYERS) do
    local w = g_ui.createWidget('ChaosWeatherLayer', root)
    w:setImageSource(A.IMAGES .. layer.image)
    w:setOpacity(0)
    widgets[layer.name] = w
  end
  clock0 = now()
  return true
end

local function hideAll()
  for _, layer in ipairs(A.LAYERS) do
    local w = widgets[layer.name]
    if alive(w) then
      w:setOpacity(0)
      w:setVisible(false)
    end
  end
end

local function draw()
  if not alive(root) then return end
  local size = root:getSize()
  local w, h = size.width, size.height
  local t = now() - clock0
  for _, layer in ipairs(A.LAYERS) do
    local widget = widgets[layer.name]
    local opacity = cur[layer.name] or 0
    if alive(widget) then
      if opacity > A.MIN_OPACITY and w > 0 and h > 0 then
        local ox, oy = A.offset(layer, t)
        widget:setImageRect(A.imageRect(ox, oy, w, h))
        widget:setOpacity(opacity * A.pulse(layer, t))
        if not widget:isVisible() then widget:setVisible(true) end
      elseif widget:isVisible() then
        widget:setOpacity(0)
        widget:setVisible(false)
      end
    end
  end
end

-- ---------------------------------------------------------------- timers
local function target()
  return A.targets(kind, enabled, visible)
end

local function stopTick()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

local function stopPoll()
  if pollEvent then removeEvent(pollEvent) pollEvent = nil end
end

local refresh

-- the window went away: nothing drawn, nothing fading, one slow look until it is back
local function goHidden()
  visible = false
  cur = A.newOpacities()
  stopTick()
  hideAll()
  if kind and enabled and not pollEvent then
    pollEvent = cycleEvent(safe('poll', function()
      if windowVisible() then
        stopPoll()
        visible = true
        refresh()
      end
    end), A.HIDDEN_POLL_MS)
  end
end

local function tick()
  if not windowVisible() then
    goHidden()
    return
  end
  local t = now()
  local dt = t - lastTick
  lastTick = t
  local tgt = target()
  A.stepAll(cur, tgt, dt, fadeMs)
  draw()
  if not A.busy(cur, tgt) then
    stopTick()
    hideAll()
  end
end

-- called when the kind, the option or the window state changed: starts the timer if something is to be drawn or faded
refresh = function()
  if not windowVisible() then
    if visible then goHidden() end
    return
  end
  visible = true
  stopPoll()
  local tgt = target()
  if not A.busy(cur, tgt) then return end
  if not attach() then return end
  if tickEvent then return end
  lastTick = now()
  tickEvent = cycleEvent(safe('tick', tick), A.TICK_MS)
end

-- ---------------------------------------------------------------- called by the weather part and game_visualfx
-- the mood of the player's place (nil for none) and the fade of the message
function M.setKind(newKind, newFadeMs)
  if newKind ~= nil and not A.KINDS[newKind] then newKind = nil end
  fadeMs = newFadeMs or A.DEFAULT_FADE_MS
  if newKind == kind then return end
  kind = newKind
  safe('refresh', refresh)()
end

function M.setEnabled(on)
  on = A.optionOn(on)
  if on == enabled then return end
  enabled = on
  if not on then
    cur = A.newOpacities()
    stopTick()
    stopPoll()
    hideAll()
  end
  safe('refresh', refresh)()
end

function M.isEnabled()
  return enabled
end

-- game start and end: no mood, nothing drawn, no widgets
function M.reset(optionValue)
  kind, fadeMs = nil, A.DEFAULT_FADE_MS
  cur = A.newOpacities()
  stopTick()
  stopPoll()
  destroyWidgets()
  if optionValue ~= nil then enabled = A.optionOn(optionValue) end
end

function M.terminate()
  M.reset(nil)
end

-- the state, for the terminal: modules.game_chaosweather.ambientState()
function M.state()
  return { kind = kind, enabled = enabled, visible = visible, opacity = cur, ticking = tickEvent ~= nil, polling = pollEvent ~= nil }
end
