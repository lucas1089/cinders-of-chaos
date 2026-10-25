-- game_chaosweather: rain over the game window (O208; client/MANIFEST.md "Weather on the client (O208)"). The server
-- (server/data/scripts/chaos/weather.lua) only decides the weather and sends one JSON message on extended opcode 114 when a
-- player logs in, asks, enters or leaves a weather area, or the weather changes:
--   set {k = 'rain' | 'none', i = level 1..3, f = fade ms}
-- and this module draws the rain itself: three repeated rain pictures (ChaosWeatherLogic.LAYERS) on widgets that fill the game
-- map panel, scrolled by changing the image rectangle every 33 ms. Nothing is made or run while it does not rain.
--   * Only over the map: the root is a child of the game map panel (under the panels and the map's own HUD pieces).
--   * Capped: three layers, a fixed number of streaks in their tiles, a fixed number of rectangles (L.maxQuads).
--   * Under a roof the rain fades out: the player's tile is checked for a covering floor every 400 ms (g_map.isCovered).
--   * The option `weather` (Options > Graphics, base patch 0130) comes through game_visualfx (onOption -> setEnabled).
-- No engine patch: the base client's native weather manager can be driven only by a game-protocol packet and has no Lua
-- binding, so it is not used. Every engine call is guarded; a failure is logged once and the rain stays off.
local L = ChaosWeatherLogic

local weather = { kind = 'none', level = 0, fadeMs = L.DEFAULT_FADE_MS }
local cur = L.newOpacities()
local enabled = true
local covered = false
local root, widgets = nil, {}
local tickEvent, coverEvent
local lastTick, clock0 = 0, 0
local handlers = {}
local reported = {}

local function now()
  return g_clock.millis()
end

local function report(name, err)
  if not reported[name] then
    reported[name] = true
    g_logger.warning('[chaosweather] ' .. name .. ': ' .. tostring(err))
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

local function optionFromSettings()
  local cs = modules.client_settings
  if cs and cs.getOption then
    local ok, value = pcall(cs.getOption, 'weather')
    if ok then return L.optionOn(value) end
  end
  return true
end

-- ---------------------------------------------------------------- widgets
local function destroyWidgets()
  if alive(root) then root:destroy() end
  root, widgets = nil, {}
end

-- makes the root and the layers on the game map panel (once); false when the panel is not there yet
local function attach()
  if alive(root) then return true end
  local gi = modules.game_interface
  local panel = gi and gi.getMapPanel and gi.getMapPanel() or nil
  if not alive(panel) then return false end
  destroyWidgets()
  root = g_ui.createWidget('ChaosWeatherRoot')
  panel:insertChild(1, root)
  root:fill('parent')
  for _, layer in ipairs(L.LAYERS) do
    local w = g_ui.createWidget('ChaosWeatherLayer', root)
    w:setImageSource(L.IMAGES .. layer.image)
    w:setOpacity(0)
    widgets[layer.name] = w
  end
  clock0 = now()
  return true
end

local function hideAll()
  for _, layer in ipairs(L.LAYERS) do
    local w = widgets[layer.name]
    if alive(w) then
      w:setOpacity(0)
      w:setVisible(false)
    end
  end
end

-- ---------------------------------------------------------------- drawing
local function draw()
  if not alive(root) then return end
  local size = root:getSize()
  local w, h = size.width, size.height
  local t = now() - clock0
  for _, layer in ipairs(L.LAYERS) do
    local widget = widgets[layer.name]
    local opacity = cur[layer.name] or 0
    if alive(widget) then
      if opacity > L.MIN_OPACITY and w > 0 and h > 0 then
        local ox, oy = L.offset(layer, t)
        widget:setImageRect(L.imageRect(ox, oy, w, h))
        widget:setOpacity(opacity)
        if not widget:isVisible() then widget:setVisible(true) end
      elseif widget:isVisible() then
        widget:setOpacity(0)
        widget:setVisible(false)
      end
    end
  end
end

local function target()
  return L.targets(weather, enabled, covered)
end

local function stopTick()
  if tickEvent then
    removeEvent(tickEvent)
    tickEvent = nil
  end
end

local function tick()
  local t = now()
  local dt = t - lastTick
  lastTick = t
  local tgt = target()
  L.stepAll(cur, tgt, dt, L.fadeMs(weather, covered))
  draw()
  if not L.busy(cur, tgt) then
    stopTick()
    hideAll()
  end
end

local function startTick()
  if tickEvent then return end
  lastTick = now()
  tickEvent = cycleEvent(safe('tick', tick), L.TICK_MS)
end

-- called when the weather, the option or the roof state changed: starts the timer if something has to be drawn or faded
local function refresh()
  local tgt = target()
  if not L.busy(cur, tgt) then return end
  if not attach() then return end
  startTick()
end

-- ---------------------------------------------------------------- roof check
local function checkCover()
  local player = g_game.getLocalPlayer()
  if not player then return end
  local pos = player:getPosition()
  if not pos then return end
  local now_covered = g_map.isCovered(pos, 0) and true or false
  if now_covered ~= covered then
    covered = now_covered
    refresh()
  end
end

local function stopCover()
  if coverEvent then
    removeEvent(coverEvent)
    coverEvent = nil
  end
end

local function updateCover()
  if weather.kind == 'rain' and enabled then
    if not coverEvent then coverEvent = cycleEvent(safe('cover', checkCover), L.COVER_MS) end
  else
    stopCover()
    covered = false
  end
end

-- ---------------------------------------------------------------- server and options
local function onMessage(protocol, opcode, msg)
  local w = L.parse(msg)
  if not w then return end
  weather = w
  updateCover()
  if w.kind == 'rain' then checkCover() end
  refresh()
end

local function hello()
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(L.OPCODE, json.encode({ action = 'hello' }))
  end
end

-- from game_visualfx (the option's apply, and at every game start); off hides the rain at once, on shows it fading in
function setEnabled(on)
  on = L.optionOn(on)
  if on == enabled then return end
  enabled = on
  if not on then
    cur = L.newOpacities()
    stopTick()
    hideAll()
  end
  updateCover()
  if on and weather.kind == 'rain' then checkCover() end
  refresh()
end

function isEnabled()
  return enabled
end

-- the state, for the terminal: modules.game_chaosweather.state()
function state()
  return { kind = weather.kind, level = weather.level, enabled = enabled, covered = covered, opacity = cur }
end

local function onGameStart()
  weather = { kind = 'none', level = 0, fadeMs = L.DEFAULT_FADE_MS }
  cur = L.newOpacities()
  covered = false
  enabled = optionFromSettings()
  destroyWidgets()
  updateCover()
  hello()
end

local function onGameEnd()
  weather = { kind = 'none', level = 0, fadeMs = L.DEFAULT_FADE_MS }
  cur = L.newOpacities()
  stopTick()
  stopCover()
  destroyWidgets()
end

function init()
  g_ui.importStyle('chaosweather')
  enabled = optionFromSettings()
  handlers.opcode = safe('opcode', onMessage)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  ProtocolGame.registerExtendedJSONOpcode(L.OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, L.OPCODE)
  if handlers.game then disconnect(g_game, handlers.game) end
  stopTick()
  stopCover()
  destroyWidgets()
  handlers = {}
end
