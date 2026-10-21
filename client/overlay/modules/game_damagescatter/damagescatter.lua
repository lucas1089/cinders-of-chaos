-- game_damagescatter: damage numbers spread out (client/MANIFEST.md "Damage number scatter"). Base patch 0081 gives the
-- animated texts above the map a pixel shift and a speed scale; on every new text (g_map.onAnimatedText) this module
-- rolls both (scatterlogic.lua) so an area hit or a group hunt does not stack the numbers in one column. The two
-- numbers of one hit (physical + element) share a roll, so they stay side by side. Window: Character > Damage Numbers
-- (on / off and strength: Subtle, Normal, Wide), kept per character in g_settings node chaosDamageScatter. A client
-- without patch 0081 has no setScatter: one warning, nothing changes.
-- Base patch 0100 (client/MANIFEST.md "Typed impact numbers"): the damage, heal, mana and experience numbers come
-- through g_map.onImpactText before they reach the map, with the type the server tagged (normal, critical, damage over
-- time, mana ...), so this module also gives them a drift (direction and speed of the float), a font per type (a big
-- one for critical hits) and turns on GameChaosAttachedImpactText (numbers follow their creature) at every game start
-- when the option Options > Interface "Damage numbers follow the creature" is on. Other animated texts (the server's
-- labels) still come through g_map.onAnimatedText and keep the shift and speed only.
local L = DamageScatterLogic

local window
local handlers = {}
local settings = L.sanitize(nil)
local charKey = nil
local group = {}
local rng = L.newRng(1)
local warned = false
local MENU_TEXT = 'Damage Numbers'

local function alive(w)
  return w and not w:isDestroyed()
end

local function loadSettings()
  local ok, node = pcall(g_settings.getNode, L.SETTINGS_NODE)
  settings = L.settingsFor(ok and node or nil, charKey)
end

local function saveSettings()
  if not charKey then return end
  local ok, node = pcall(g_settings.getNode, L.SETTINGS_NODE)
  pcall(g_settings.setNode, L.SETTINGS_NODE, L.withSettings(ok and node or nil, charKey, settings))
  pcall(g_settings.save)
end

local function levelNames()
  return { tr('Subtle'), tr('Normal'), tr('Wide') }
end

local function fontExists(name)
  return g_fonts and g_fonts.fontExists and g_fonts.fontExists(name) or false
end

-- ---------------------------------------------------------------- the hooks
-- base patch 0100: every damage, heal, mana and experience number, before it is put on the map; never cancels
local function onImpactText(thing, text, mode, typeId, value, percent, creatureId, pos)
  if not thing then return false end
  local font = L.fontFor(typeId, fontExists)
  if font and thing.setFont then thing:setFont(font) end
  if settings.enabled and thing.setScatter and thing.setSpeedScale then
    local dx, dy, speed, sx, sy = L.pickImpact(group, settings, pos, g_clock.millis(), rng, typeId, mode)
    if dx then
      thing:setScatter({ x = dx, y = dy })
      thing:setSpeedScale(speed)
      if thing.setAnimationSpeed then thing:setAnimationSpeed({ x = sx, y = sy }) end
    end
  end
  return false
end

local function onAnimatedText(thing)
  if not settings.enabled or not thing then return end
  -- an impact number (base patch 0100) was handled by onImpactText before it reached the map
  if thing.getImpactType and thing:getImpactType() >= 0 then return end
  if not thing.setScatter or not thing.setSpeedScale then
    if not warned then
      warned = true
      g_logger.warning('[damagescatter] the client has no base patch 0081: damage numbers stay as they are')
    end
    return
  end
  local pos = thing.getPosition and thing:getPosition() or nil
  local dx, dy, speed = L.pick(group, settings, pos, g_clock.millis(), rng)
  if not dx then return end
  thing:setScatter({ x = dx, y = dy })
  thing:setSpeedScale(speed)
end

-- ---------------------------------------------------------------- window
local function sync()
  if not alive(window) then return end
  window:recursiveGetChildById('enabledBox'):setChecked(settings.enabled)
  local combo = window:recursiveGetChildById('levelCombo')
  combo.syncing = true
  combo:setCurrentIndex(settings.level)
  combo.syncing = nil
  combo:setEnabled(settings.enabled)
end

local function build()
  window = g_ui.createWidget('DamageScatterWindow', g_ui.getRootWidget())
  window:hide()
  local combo = window:recursiveGetChildById('levelCombo')
  for i, text in ipairs(levelNames()) do combo:addOption(text, i) end
  combo.onOptionChange = function(self, text, data)
    if self.syncing then return end
    setLevel(data)
  end
end

function toggle()
  if not alive(window) then build() end
  if window:isVisible() then
    window:hide()
  else
    sync()
    window:show()
    window:raise()
    window:focus()
  end
end

function setEnabled(value)
  value = value and true or false
  if settings.enabled == value then return end
  settings.enabled = value
  saveSettings()
  sync()
end

function setLevel(level)
  settings = L.sanitize({ enabled = settings.enabled, level = level })
  saveSettings()
end

-- ---------------------------------------------------------------- menu
local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if not api or not api.addEntry or handlers.menu then return end
  local ok, shown = pcall(api.available)
  for _, text in ipairs(ok and type(shown) == 'table' and shown.character or {}) do
    if text == MENU_TEXT then
      handlers.menu = true
      return
    end
  end
  handlers.menu = pcall(api.addEntry, 'character',
    { text = MENU_TEXT, icon = 'skills', modules = { 'game_damagescatter' }, fns = { 'toggle' } })
end

-- ---------------------------------------------------------------- numbers follow their creature (base patch 0100)
local function attachedOption()
  local cs = modules.client_settings
  if cs and cs.getOption then
    local ok, value = pcall(cs.getOption, 'attachedImpactText')
    if ok then return L.attachedWanted(value) end
  end
  return true
end

local function applyAttached(on)
  if not GameChaosAttachedImpactText then return end -- a client without base patch 0100
  if on then
    g_game.enableFeature(GameChaosAttachedImpactText)
  else
    g_game.disableFeature(GameChaosAttachedImpactText)
  end
end

-- from the option's apply (client_settings dataset.lua); the features are reset at every login, so onGameStart sets it
-- again
function setAttached(value)
  applyAttached(L.attachedWanted(value))
end

-- ---------------------------------------------------------------- lifecycle
local function onGameStart()
  applyAttached(attachedOption())
  charKey = L.key(g_game.getWorldName and g_game.getWorldName() or nil, g_game.getCharacterName())
  group = {}
  loadSettings()
  sync()
  addMenu()
end

local function onGameEnd()
  charKey = nil
  settings = L.sanitize(nil)
  if alive(window) then window:hide() end
end

function init()
  rng = L.newRng((os.time() % 100000) * 1000 + g_clock.millis() % 1000)
  handlers.game = { onGameStart = onGameStart, onGameEnd = onGameEnd }
  connect(g_game, handlers.game)
  handlers.map = { onAnimatedText = onAnimatedText, onImpactText = onImpactText }
  connect(g_map, handlers.map)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  if handlers.game then disconnect(g_game, handlers.game) end
  if handlers.map then disconnect(g_map, handlers.map) end
  if alive(window) then window:destroy() end
  window, handlers, charKey = nil, {}, nil
end
