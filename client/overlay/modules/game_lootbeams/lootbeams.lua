-- Loot beams: a thin light pillar over a corpse (or an item on the ground) that holds loot your loot filter makes
-- glow, in the colour of the best tier inside, with a soft glow pool at its base. It replaces the old loot ray map
-- effects (server lootfilter_config.lua rayEffects, now off).
--
-- Where the data comes from:
--   corpses  the server's "beam" message on the loot filter's opcode 238 (server lootfilter.lua; game_lootfilter
--            hands it here): {k, p = [x, y, z], i = [{r, u, o, pw, g, t}]}, the items still inside that may beam; i = []
--            when the corpse was looted empty, decayed or left the history. Sent to the owner and the party.
--   ground   the item rows game_groundlabels has for the tiles in view (getGroundItems), when "ground" is on.
-- The rules (tier -> colour, the filter, the best per tile, the cap, the engine calls) are in lootbeamslogic.lua.
--
-- How it is drawn (pair 36 and on): the animated loot beam effect of the beam's group (LootBeamsLogic.EFFECTS, effects
-- of the client pair) is added to the tile (Effect.create + g_map.addThing) when the beam starts and again every
-- LB.EFFECT_MS while it stands; it plays on the map like a spell effect. A pair without those effects (or a client
-- without Effect.create): the engine pillar below.
-- The engine pillar (client base patch 0069, g_map.setLootBeam(pos, color, height, intensity)): MapView
-- adds the pool on the floor under the creatures and the pillar over the floor, below names, bars and windows; it
-- follows walking and zoom like everything on the map, and pulses by itself, so this module only calls the engine when
-- the set of beams changes (no widgets, no per-frame Lua). A client without the patch logs once and draws nothing.

local LB = LootBeamsLogic

local TICK_MS = 300

local settings = LB.defaults()
local state = LB.newState()
local drawn = {}          -- posKey -> {sig, pos}: what the engine draws
local dirty = true
local lastKey = ''        -- filter + settings + ground version + player position: re-chosen when it changes
local engineOk = nil
local effectsOk = nil
local window
local updatingUi = false
local events, handlers = {}, {}
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[lootbeams] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function filterLogic()
  local lf = modules.game_lootfilter
  return lf and lf.LootFilterLogic or LootFilterLogic
end

local function filterSettings()
  local lf = modules.game_lootfilter
  local s = lf and lf.getSettings and lf.getSettings()
  return type(s) == 'table' and s or filterLogic().defaults()
end

local function hasEngine()
  if engineOk == nil then
    engineOk = type(g_map) ~= 'nil' and type(g_map.setLootBeam) == 'function'
    if not engineOk then
      g_logger.warning('[lootbeams] this client has no loot beams (base patch 0069): no beams are drawn')
    end
  end
  return engineOk
end

-- the pair has the beam effects and the client can add an effect to a tile
local function hasEffects()
  if effectsOk == nil then
    effectsOk = false
    local id = LB.effectFor('white')
    if id and type(Effect) == 'table' and Effect.create and g_map and g_map.addThing and g_things then
      local ok, valid = pcall(function()
        if g_things.isValidDatId then return g_things.isValidDatId(id, ThingCategoryEffect) end
        return g_things.getThingType(id, ThingCategoryEffect) ~= nil
      end)
      effectsOk = ok and valid and true or false
    end
    if not effectsOk then
      g_logger.info('[lootbeams] the client pair has no beam effects: the engine pillar is drawn')
    end
  end
  return effectsOk
end

local function addEffect(pos, id)
  local e = Effect.create()
  e:setId(id)
  g_map.addThing(e, pos, -1)
end

-- ---------------------------------------------------------------- settings
local function loadSettings()
  settings = LB.normalize(g_settings.getNode('lootBeams'))
end

local function saveSettings()
  g_settings.setNode('lootBeams', settings)
end

-- ---------------------------------------------------------------- engine
local function clearDrawn()
  if not hasEffects() and hasEngine() then g_map.clearLootBeams() end
  drawn = {}
end

local function groundVersion()
  local gl = modules.game_groundlabels
  return gl and gl.getRowsVersion and gl.getRowsVersion() or 0
end

local function apply()
  local effects = hasEffects()
  if not effects and not hasEngine() then return end
  local player = g_game.isOnline() and g_game.getLocalPlayer()
  local ppos = player and player:getPosition()
  local L = filterLogic()
  LB.setFilterLogic(L)
  if settings.ground then
    local gl = modules.game_groundlabels
    LB.setGround(state, gl and gl.getGroundItems and gl.getGroundItems() or {})
  else
    LB.setGround(state, {})
  end
  local want = LB.resolve(state, filterSettings(), settings, ppos, LB.MAX_BEAMS)
  local calls
  calls, drawn = LB.diff(drawn, want)
  if effects then -- a removed beam's effect ends by itself; a new one starts now
    for _, b in ipairs(calls.set) do
      local id = LB.effectFor(b.group)
      if id then addEffect(b.pos, id) end
    end
    return
  end
  for _, pos in ipairs(calls.remove) do g_map.removeLootBeam(pos) end
  for _, b in ipairs(calls.set) do
    if not g_map.setLootBeam(b.pos, b.color, b.height, b.intensity) then drawn[b.key] = nil end
  end
end

-- the beam effects again, every LB.EFFECT_MS (one play of the strip)
local function pulse()
  if not g_game.isOnline() or not hasEffects() then return end
  for _, p in ipairs(LB.pulse(drawn)) do addEffect(p.pos, p.id) end
end

local function tick()
  if not g_game.isOnline() then return end
  local player = g_game.getLocalPlayer()
  local ppos = player and player:getPosition()
  local key = table.concat({ LB.filterKey(filterSettings()), tostring(groundVersion()),
    ppos and LB.posKey(ppos) or '-' }, '#')
  if dirty or key ~= lastKey then
    dirty, lastKey = false, key
    apply()
  end
end

-- the server's "beam" message (game_lootfilter forwards it)
function onBeam(data)
  if LB.onBeam(state, data) then dirty = true end
end

local function reset()
  state = LB.newState()
  clearDrawn()
  dirty = true
end

-- ---------------------------------------------------------------- settings window
-- names are looked up when the window is filled (tr follows the language picked at login)
local function groupNames()
  return { white = tr('Common, Uncommon'), blue = tr('Magic, Rare'), orange = tr('Legendary'),
    divine = tr('Divine'), unique = tr('Uniques'), orb = tr('Orbs') }
end

local function heightNames()
  return { short = tr('Short'), normal = tr('Normal'), tall = tr('Tall') }
end

local function intensityNames()
  return { soft = tr('Soft'), normal = tr('Normal'), bright = tr('Bright') }
end

local function fillCombo(combo, order, names, current)
  combo:clearOptions()
  for _, k in ipairs(order) do combo:addOption(names[k], k) end
  for i, k in ipairs(order) do
    if k == current then combo:setCurrentIndex(i) end
  end
end

local function buildLegend()
  if not window or not window.legend then return end
  window.legend:destroyChildren()
  local names = groupNames()
  for _, key in ipairs(LB.GROUP_ORDER) do
    local row = g_ui.createWidget('LootBeamsLegendRow', window.legend)
    row.swatch:setBackgroundColor(LB.GROUPS[key].color)
    row.name:setText(names[key])
  end
end

local function refreshWindow()
  if not window then return end
  updatingUi = true
  window.enabled:setChecked(settings.enabled)
  window.orbs:setChecked(settings.orbs)
  window.ground:setChecked(settings.ground)
  fillCombo(window.heightCombo, LB.HEIGHT_ORDER, heightNames(), settings.height)
  fillCombo(window.intensityCombo, LB.INTENSITY_ORDER, intensityNames(), settings.intensity)
  updatingUi = false
end

local function onUiChange()
  if updatingUi or not window then return end
  settings.enabled = window.enabled:isChecked()
  settings.orbs = window.orbs:isChecked()
  settings.ground = window.ground:isChecked()
  local h = window.heightCombo:getCurrentOption()
  settings.height = h and LB.HEIGHTS[h.data] and h.data or settings.height
  local i = window.intensityCombo:getCurrentOption()
  settings.intensity = i and LB.INTENSITIES[i.data] and i.data or settings.intensity
  saveSettings()
  dirty = true
  tick()
end

function showSettings()
  if not window then return end
  buildLegend()
  refreshWindow()
  window:show()
  window:raise()
  window:focus()
end

function hideSettings()
  if window then window:hide() end
end

function toggleSettings()
  if window and window:isVisible() then hideSettings() else showSettings() end
end

-- for other modules and tests: the beams the engine draws {pos, color, height, intensity} and counts
function getBeams()
  local out = {}
  for _, d in pairs(drawn) do out[#out + 1] = { pos = d.pos, sig = d.sig } end
  return out
end

function getStats()
  local corpses = 0
  for _ in pairs(state.corpses) do corpses = corpses + 1 end
  local n = 0
  for _ in pairs(drawn) do n = n + 1 end
  return { corpses = corpses, drawn = n, engine = hasEngine(), engineCount = hasEngine() and g_map.getLootBeamCount() or 0,
    effects = hasEffects(), enabled = settings.enabled }
end

-- ---------------------------------------------------------------- init
function init()
  g_ui.importStyle('lootbeams')
  loadSettings()
  handlers.tick = safe('tick', tick)
  handlers.game = { onGameStart = safe('start', reset), onGameEnd = safe('end', reset) }
  local ok, ui = pcall(g_ui.createWidget, 'LootBeamsWindow', rootWidget)
  if ok and ui then
    window = ui
    window:hide()
    for _, id in ipairs({ 'enabled', 'orbs', 'ground' }) do window[id].onCheckChange = safe('ui', onUiChange) end
    window.heightCombo.onOptionChange = safe('ui', onUiChange)
    window.intensityCombo.onOptionChange = safe('ui', onUiChange)
    safe('legend', buildLegend)()
  else
    g_logger.warning('[lootbeams] settings window not loaded: ' .. tostring(ui))
  end
  connect(g_game, handlers.game)
  events.tick = cycleEvent(handlers.tick, TICK_MS)
  handlers.pulse = safe('pulse', pulse)
  if LB.EFFECT_MS > 0 then events.pulse = cycleEvent(handlers.pulse, LB.EFFECT_MS) end
end

function terminate()
  for k, e in pairs(events) do
    removeEvent(e)
    events[k] = nil
  end
  disconnect(g_game, handlers.game)
  pcall(clearDrawn)
  state = LB.newState()
  if window then window:destroy() window = nil end
  handlers = {}
end
