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
-- How it is drawn (O569, since 2026-11-14): ONE widget per beam over its tile (Tile:addOverlayWidget, client base patch 0041, drawn in
-- screen pixels so the size and the margins follow the zoom), a strip of soft light frames made by client/tools/gen_lootbeam_art.py
-- (images/<style>_<group>.png; the rarity colours, three styles the player picks in the settings window, default a): a feathered
-- column with a bright centre line, a pulse travelling up, motes drifting up and a ground ring lying on the floor in the game's
-- oblique view. The burst frames play once when a beam appears, then a loop of 12. The best RICH_CAP (8) beams animate; the others
-- (up to MAX_BEAMS) stand still on one loop frame, so a pile of corpses costs no timer work. Rules and sizes: lootbeamslogic.lua.
-- A client without Tile:addOverlayWidget (or without the pictures) draws the older beams below.
--
-- The older beams (pair 36 and on): the animated loot beam effect of the beam's group (LootBeamsLogic.EFFECTS, effects
-- of the client pair) is added to the tile (Effect.create + g_map.addThing) when the beam starts and again every
-- LB.EFFECT_MS while it stands; it plays on the map like a spell effect. From pair 65 the effect is 3 x 5 tiles and is
-- added at the tile + (1, 1) (LB.effectPos; pair 36 to 64: 1 x 2, on the tile). A pair without those effects (or a client
-- without Effect.create): the engine pillar below.
-- The engine pillar (client base patch 0069, g_map.setLootBeam(pos, color, height, intensity)): MapView
-- adds the pool on the floor under the creatures and the pillar over the floor, below names, bars and windows; it
-- follows walking and zoom like everything on the map, and pulses by itself, so this module only calls the engine when
-- the set of beams changes (no widgets, no per-frame Lua). A client without the patch logs once and draws nothing.

local LB = LootBeamsLogic

local TICK_MS = 300
local ANIM_MS = 50

local settings = LB.defaults()
local state = LB.newState()
local drawn = {}          -- posKey -> {sig, pos}: what the engine draws
local dirty = true
local lastKey = ''        -- filter + settings + ground version + player position: re-chosen when it changes
local engineOk = nil
local widgetsOk = nil
local entries = {}        -- posKey -> {w, pos, tile, group, rich, t0, frame, fit}: the widget beams (O569)
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

-- the client can put a widget over a tile and the beam pictures are in the module (O569)
local function hasWidgets()
  if widgetsOk == nil then
    widgetsOk = type(Tile) == 'table' and Tile.addOverlayWidget ~= nil and Tile.hasOverlayWidget ~= nil
      and Tile.removeOverlayWidget ~= nil and type(g_ui) ~= 'nil' and type(g_map) ~= 'nil' and g_map.getTile ~= nil
    if widgetsOk and g_resources and g_resources.fileExists then
      widgetsOk = g_resources.fileExists(LB.artPath('a', 'white')) and true or false
    end
    if not widgetsOk then
      g_logger.info('[lootbeams] no tile overlay widgets or no beam pictures: the older beams are drawn')
    end
  end
  return widgetsOk
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

-- the size of an effect of the pair in tiles (w, h), cached; nil when it cannot be read
local sizes = {}
local function effectSize(id)
  local c = sizes[id]
  if c == nil then
    c = false
    local ok, w, h = pcall(function()
      local t = g_things.getThingType(id, ThingCategoryEffect)
      return t:getWidth(), t:getHeight()
    end)
    if ok and tonumber(w) and tonumber(h) then c = { w = tonumber(w), h = tonumber(h) } end
    sizes[id] = c
  end
  return c or nil
end

-- the beam at full size (pair 65) is added one tile south-east of its tile, the old 1 x 2 one on the tile (see
-- LB.effectPos)
local function addEffect(pos, id)
  local e = Effect.create()
  e:setId(id)
  local size = effectSize(id)
  g_map.addThing(e, size and LB.effectPos(pos, size.w, size.h) or pos, -1)
end

-- ---------------------------------------------------------------- settings
local function loadSettings()
  settings = LB.normalize(g_settings.getNode('lootBeams'))
end

local function saveSettings()
  g_settings.setNode('lootBeams', settings)
end

-- ---------------------------------------------------------------- widget beams (O569)
local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

local function nowMs()
  return g_clock.millis()
end

-- the size of a tile on screen (the map panel's size over its visible tiles; zoom and window size change it)
local function tileSize()
  local gi = modules.game_interface
  local panel = gi and gi.getMapPanel and gi.getMapPanel()
  local vd = panel and panel:getVisibleDimension()
  local r = panel and panel:getRect()
  if not vd or not r or vd.width <= 0 or vd.height <= 0 then return 64, 64 end
  local w, h = r.width / vd.width, r.height / vd.height
  if panel:isKeepAspectRatioEnabled() then
    local m = math.min(w, h)
    return m, m
  end
  return w, h
end

local function fitWidget(e, tw, th)
  local fit = table.concat({ math.floor(tw + 0.5), math.floor(th + 0.5), settings.height }, ',')
  if e.fit == fit then return end
  e.fit = fit
  local width, height, ml, mt = LB.box(tw, th, settings.height)
  e.w:resize(width, height)
  e.w:setMarginLeft(ml)
  e.w:setMarginTop(mt)
end

local function setFrame(e, f)
  if e.frame == f then return end
  e.frame = f
  e.w:setImageClip(LB.clip(f))
end

local function attachWidget(e)
  local tile = g_map.getTile(e.pos)
  if not tile then
    e.tile = nil
    return
  end
  if not tile:hasOverlayWidget(e.w) then tile:addOverlayWidget(e.w) end
  e.tile = tile
end

local function dropWidget(key)
  local e = entries[key]
  if not e then return end
  entries[key] = nil
  if alive(e.w) then
    if e.tile then pcall(e.tile.removeOverlayWidget, e.tile, e.w) end
    e.w:destroy()
  end
end

local function dropAllWidgets()
  for key in pairs(entries) do dropWidget(key) end
end

local function newWidget(b, rich)
  local w = g_ui.createWidget('UIWidget')
  w:setImageSource(LB.artPath(settings.style, b.group))
  w:setImageSmooth(true)
  w:setPhantom(true)
  w:setOpacity(LB.OPACITY[settings.intensity] or 0.85)
  local e = { w = w, pos = b.pos, group = b.group, rich = rich and true or false, t0 = nowMs() }
  e.frame = LB.frame(0, e.rich)
  w:setImageClip(LB.clip(e.frame))
  fitWidget(e, tileSize())
  attachWidget(e)
  return e
end

-- once per tick: the widgets follow zoom (a new size), a tile the server sent again (the engine forgot our widget) and a lost widget
local function maintainWidgets()
  local tw, th = tileSize()
  for key, e in pairs(entries) do
    if not alive(e.w) then
      entries[key] = nil
      drawn[key] = nil -- drawn again at the next change
      dirty = true
    else
      fitWidget(e, tw, th)
      if not e.tile or not e.tile:hasOverlayWidget(e.w) then attachWidget(e) end
    end
  end
end

-- the burst, then the loop, of the beams that animate (about every 50 ms; one clip change per frame step each)
local function animate()
  if not g_game.isOnline() then return end
  local t = nowMs()
  for _, e in pairs(entries) do
    if e.rich and alive(e.w) then setFrame(e, LB.frame(t - e.t0, true)) end
  end
end

-- ---------------------------------------------------------------- engine
local function clearDrawn()
  dropAllWidgets()
  if not hasWidgets() and not hasEffects() and hasEngine() then g_map.clearLootBeams() end
  drawn = {}
end

local function groundVersion()
  local gl = modules.game_groundlabels
  return gl and gl.getRowsVersion and gl.getRowsVersion() or 0
end

local function apply()
  local widgets = hasWidgets()
  local effects = not widgets and hasEffects()
  if not widgets and not effects and not hasEngine() then return end
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
  if widgets then -- the beams of this client are widgets: new ones burst in, the best RICH_CAP animate, the rest stand still
    local rich = LB.richKeys(want, LB.RICH_CAP)
    for _, pos in ipairs(calls.remove) do dropWidget(LB.posKey(pos)) end
    for _, b in ipairs(calls.set) do
      dropWidget(b.key)
      entries[b.key] = newWidget(b, rich[b.key])
    end
    for key, e in pairs(entries) do
      local r = rich[key] and true or false
      if r ~= e.rich then
        e.rich = r
        if r then e.t0 = nowMs() - LB.ART_MS end -- no burst for a beam that was standing still
        setFrame(e, LB.frame(r and (nowMs() - e.t0) or 0, r))
      end
    end
    return
  end
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
  if not g_game.isOnline() or hasWidgets() or not hasEffects() then return end
  for _, p in ipairs(LB.pulse(drawn)) do addEffect(p.pos, p.id) end
end

local function tick()
  if not g_game.isOnline() then return end
  local player = g_game.getLocalPlayer()
  local ppos = player and player:getPosition()
  local key = table.concat({ LB.filterKey(filterSettings()), tostring(groundVersion()),
    ppos and LB.posKey(ppos) or '-' }, '#')
  if next(entries) then maintainWidgets() end
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

local function styleNames()
  return { a = tr('A: Soft light pillar'), b = tr('B: Twisted twin strands'), c = tr('C: Rune column') }
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
  fillCombo(window.styleCombo, LB.STYLE_ORDER, styleNames(), settings.style)
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
  local st = window.styleCombo:getCurrentOption()
  local style = st and LB.styleOf(st.data) or settings.style
  local restyled = style ~= settings.style
  settings.style = style
  saveSettings()
  if restyled then clearDrawn() end -- the pictures change: every beam bursts in again in the new style
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
  local widgetCount = 0
  for _ in pairs(entries) do widgetCount = widgetCount + 1 end
  return { corpses = corpses, drawn = n, widgets = widgetCount, widgetMode = hasWidgets(), style = settings.style,
    engine = hasEngine(), engineCount = hasEngine() and g_map.getLootBeamCount() or 0,
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
    window.styleCombo.onOptionChange = safe('ui', onUiChange)
    safe('legend', buildLegend)()
  else
    g_logger.warning('[lootbeams] settings window not loaded: ' .. tostring(ui))
  end
  connect(g_game, handlers.game)
  events.tick = cycleEvent(handlers.tick, TICK_MS)
  handlers.anim = safe('anim', animate)
  events.anim = cycleEvent(handlers.anim, ANIM_MS)
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
