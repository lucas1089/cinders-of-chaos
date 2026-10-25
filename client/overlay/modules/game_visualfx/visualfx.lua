-- game_visualfx: the dark-fantasy look of the map, one switch per effect (Options > Graphics, client_settings dataset.lua
-- hitFlash, screenShake, creatureShadow, screenGrade; client/MANIFEST.md "Visual effects"). The numbers and rules are in
-- visualfx_logic.lua.
--   hit flash      g_map.onImpactText (base patch 0100) tells which creature took a damage number; the creature draws with the
--                  outfit shader chaos_hit_white / chaos_hit_red for about 80 ms (Creature:flashHit, base patch 0126).
--   screen shake   the local player's big or critical hits move the picture a few pixels for 180 ms (UIMap.setShake, base
--                  patch 0126); one 16 ms timer runs only while it shakes.
--   soft shadow    Creature.setSoftShadow (base patch 0126) draws the ellipse under creatures.
--   grade          the map shader chaos_map_grade (vignette, a light grade) set on the game map panel; costs one extra texture
--                  read per pixel of the map picture.
--   spell light    a magic effect that plays lights the tiles around it for ~320 ms in a colour that matches it (O205, base patch
--                  0127): this file sends the colour table and the limits to g_map.setSpellLight*, the engine keeps at most 12
--                  live lights and adds them to the map light view (nothing shows in full light).
-- A client without base patch 0126 has none of the C++ functions: the flash, shake and shadow do nothing, the grade (shader
-- only) still works. Every engine call is guarded.
local L = VisualFxLogic

local handlers = {}
local flasher = L.newFlasher()
local shake = L.newShake()
local shakeEvent = nil
local rng = math.random
local GRADE = 'chaos_map_grade'
local created = false

local function now()
  return g_clock.millis()
end

local function optionValue(name)
  local cs = modules.client_settings
  if cs and cs.getOption then
    local ok, value = pcall(cs.getOption, name)
    if ok then return L.optionOn(name, value) end
  end
  return L.DEFAULTS[name] == true
end

local function mapPanel()
  local gi = modules.game_interface
  return gi and gi.getMapPanel and gi.getMapPanel() or nil
end

-- ---------------------------------------------------------------- shake
local function setShake(x, y)
  if UIMap and UIMap.setShake then pcall(UIMap.setShake, x, y) end
end

local function stopShake()
  if shakeEvent then
    removeEvent(shakeEvent)
    shakeEvent = nil
  end
  shake = L.newShake()
  setShake(0, 0)
end

local function shakeStep()
  local x, y, done = L.shakeOffset(shake, now(), rng)
  setShake(x, y)
  if done and shakeEvent then
    removeEvent(shakeEvent)
    shakeEvent = nil
  end
end

local function startShake(amp)
  if not (UIMap and UIMap.setShake) then return end
  if not L.shakeStart(shake, now(), amp) then return end
  if not shakeEvent then shakeEvent = cycleEvent(shakeStep, 16) end
end

-- ---------------------------------------------------------------- hit flash and shake: one hook
local function onImpactText(thing, text, mode, typeId, value, percent, creatureId, pos)
  local flashOn = optionValue('hitFlash')
  local shakeOn = optionValue('screenShake')
  if not flashOn and not shakeOn then return false end
  local player = g_game.getLocalPlayer()
  local mine = player ~= nil and creatureId ~= nil and creatureId ~= 0 and player:getId() == creatureId
  if flashOn then
    local shader, ms = L.flashPlan(flasher, now(), creatureId, mode, typeId, value, mine)
    if shader then
      local creature = g_map.getCreatureById(creatureId)
      if creature and creature.flashHit then creature:flashHit(shader, ms) end
    end
  end
  if shakeOn and mine and mode == L.MODE.DAMAGE_RECEIVED then
    startShake(L.shakeAmp(typeId, percent))
  end
  return false
end

-- ---------------------------------------------------------------- spell colour light
local lightTableSent = false

local function applySpellLight()
  if not (g_map and g_map.setSpellLightConfig) then return end
  local on = optionValue('spellLight')
  if on and not lightTableSent and g_map.setSpellLightColor then
    local A = L.LIGHT
    if g_map.clearSpellLightColors then g_map.clearSpellLightColors() end
    for id, theme in pairs(L.EFFECT_THEME) do
      pcall(g_map.setSpellLightColor, id, L.THEME_COLOR[theme], A.radius)
    end
    lightTableSent = true
  end
  local A = L.LIGHT
  pcall(g_map.setSpellLightConfig, on, A.max, A.ms, A.attack, A.minGap, A.minFade)
end

-- ---------------------------------------------------------------- shadow and grade
local function applyShadow()
  if Creature and Creature.setSoftShadow then pcall(Creature.setSoftShadow, optionValue('creatureShadow')) end
end

local function createGrade()
  if created then return end
  created = true
  local ok, err = pcall(g_shaders.createShader, GRADE, '/shaders/chaos_map_vertex', '/shaders/chaos_map_grade')
  if not ok then g_logger.warning('[visualfx] ' .. GRADE .. ': ' .. tostring(err)) end
end

-- sets or clears the grade on the game map; another map shader (the base's heat haze) is left alone
local function applyGrade()
  local panel = mapPanel()
  if not panel then return end
  local current = panel.getShader and panel:getShader() or ''
  if optionValue('screenGrade') then
    createGrade()
    if current == '' then panel:setShader(GRADE) end
  elseif current == GRADE then
    panel:setShader('')
  end
end

-- from the options' apply (client_settings dataset.lua) and after the base's enableShaders clears the map shader
function onOption(name, value)
  if name == 'creatureShadow' then
    applyShadow()
  elseif name == 'screenGrade' then
    applyGrade()
  elseif name == 'spellLight' then
    applySpellLight()
  elseif name == 'screenShake' and value == false then
    stopShake()
  end
end

function reapply()
  applyShadow()
  applyGrade()
  applySpellLight()
end

-- ---------------------------------------------------------------- lifecycle
local function onGameStart()
  flasher = L.newFlasher()
  stopShake()
  reapply()
end

local function onGameEnd()
  stopShake()
  flasher = L.newFlasher()
end

-- the two outfit shaders of the hit flash; one missing or broken file must not stop the client from starting
local function createFlashShaders()
  for _, name in ipairs({ L.FLASH.white, L.FLASH.red }) do
    local file = name:gsub('^chaos_hit_', 'chaos_outfit_hit_')
    local ok, err = pcall(g_shaders.createOutfitShader, name, '/shaders/chaos_outfit_vertex', '/shaders/' .. file)
    if not ok then g_logger.warning('[visualfx] ' .. name .. ': ' .. tostring(err)) end
  end
end

function init()
  createFlashShaders()
  handlers.game = { onGameStart = onGameStart, onGameEnd = onGameEnd }
  connect(g_game, handlers.game)
  handlers.map = { onImpactText = onImpactText }
  connect(g_map, handlers.map)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  if handlers.game then disconnect(g_game, handlers.game) end
  if handlers.map then disconnect(g_map, handlers.map) end
  stopShake()
  if Creature and Creature.setSoftShadow then pcall(Creature.setSoftShadow, false) end
  if g_map and g_map.setSpellLightConfig then pcall(g_map.setSpellLightConfig, false, 0, 0, 0, 0, 0) end
  local panel = mapPanel()
  if panel and panel.getShader and panel:getShader() == GRADE then panel:setShader('') end
  handlers = {}
end
