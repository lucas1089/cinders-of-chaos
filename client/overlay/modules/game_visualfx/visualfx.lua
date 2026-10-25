-- game_visualfx: the dark-fantasy look of the map, one switch per effect (Options > Graphics, client_settings dataset.lua
-- hitFlash, screenShake, creatureShadow, screenGrade; client/MANIFEST.md "Visual effects"). The numbers and rules are in
-- visualfx_logic.lua.
--   hit flash      g_map.onImpactText (base patch 0100) tells which creature took a damage number; the creature draws with the
--                  outfit shader chaos_hit_white / chaos_hit_red for about 80 ms (Creature:flashHit, base patch 0126). The same
--                  option also switches the engine's soft white tint on a falling health percent (Creature.setHitTint, base
--                  patch 0142, O224): 120 ms ease-out, no Lua per hit.
--   screen shake   the local player's big or critical hits move the picture a few pixels for 180 ms (UIMap.setShake, base
--                  patch 0126); one 16 ms timer runs only while it shakes.
--   soft shadow    Creature.setSoftShadow (base patch 0126) draws the ellipse under creatures.
--   grade          the map shader chaos_map_grade (vignette, a light grade) set on the game map panel; costs one extra texture
--                  read per pixel of the map picture.
--   spell light    a magic effect that plays lights the tiles around it for ~320 ms in a colour that matches it (O205, base patch
--                  0127): this file sends the colour table and the limits to g_map.setSpellLight*, the engine keeps at most 12
--                  live lights and adds them to the map light view (nothing shows in full light).
--   weather        the rain game_chaosweather draws when the server says it rains (O208, base patch 0130): this file passes the
--                  option on (modules.game_chaosweather.setEnabled); nothing is drawn here.
--   ambient        slow embers, motes or dust over the game window by the mood of the place (O226, base patch 0144 has the
--                  checkbox): this file passes the option on (modules.game_chaosweather.setAmbientEnabled); nothing is drawn here.
--   soft glow      a halo around very bright light only (O210, base patch 0132): this file creates the two shaders
--                  chaos_bloom_extract / chaos_bloom_blur and calls g_app.setMapBloom; the engine does the passes (a quarter-size
--                  buffer, one blur each way, one screen-blend composite) and nothing at all while the option is off. Off by default.
--   liquids        water and lava ground sprites shimmer (O206, base patch 0128): this file creates the two shaders
--                  chaos_liquid_water / chaos_liquid_lava and sends the ground id table to Item.addLiquidId once; the engine draws
--                  those grounds with the shader while the option is on (no per-tile Lua).
--   numbers        floating damage and heal numbers pop, rise with an ease-out, fade smoothly and spread sideways (O215, base patch
--                  0134): this file only calls AnimatedText.setSoftMotion; the maths is in the engine (chaostextmotion.h). The random
--                  shift and speed of game_damagescatter are a separate layer and stay as they are.
--   outlines       the creature the player attacks gets a soft red silhouette outline with a gentle pulse, the one followed a green one,
--                  and (option hoverOutline) the one under the mouse a faint white one (O216): Creature:setOutline of base patch 0038,
--                  nothing new in the engine. Event driven: the attack and follow events and the map's mouse move (at most every
--                  33 ms, and the engine call only when the creature under the mouse changed); no per-frame Lua. A creature that
--                  wears a bought cosmetic outline (game_cosmeticfx) keeps it: game_cosmeticfx.setHighlight(id, true) makes it leave
--                  that creature alone while ours is up, and setHighlight(id, false) puts it back. The stock target square stays.
--   scene fade     a short dip to black that eases out when the player changes floor or is moved four tiles or more in one step
--                  (O219, base patch 0138 has the checkbox): Lua and OTUI only. One black widget on the map panel, hidden unless
--                  a fade runs; one 33 ms timer runs only while it fades; the position hook is connected only while the option is on.
--   death fade    a creature that dies fades out over about 350 ms (O221, base patch 0139): this file only calls
--                  Creature.setDeathFade; the engine keeps a copy of the last frame (at most 32, none for the local player) and
--                  draws it with falling alpha. The corpse and the game are not delayed.
--   smooth bars    the health and mana bars over creatures ease to a new value in 150 ms and a hit leaves a pale chip that holds 250
--                  ms and slides down in 300 ms (O229, base patch 0146): this file only calls Creature.setSmoothBars; the maths is
--                  in the engine (chaosbars.h), computed from the clock at draw time. The character plate does the same in Lua
--                  (game_chaoshud, hudbars_logic.lua), told by the settings option's apply.
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

-- ---------------------------------------------------------------- living water and lava
local liquidTableSent = false
local liquidShadersMade = false

local function createLiquidShaders()
  if liquidShadersMade then return end
  liquidShadersMade = true
  for _, name in ipairs({ L.LIQUID.waterShader, L.LIQUID.lavaShader }) do
    local ok, err = pcall(g_shaders.createShader, name, '/shaders/chaos_liquid_vertex', '/shaders/' .. name)
    if not ok then g_logger.warning('[visualfx] ' .. name .. ': ' .. tostring(err)) end
  end
end

local function applyLiquid()
  if not (Item and Item.setLiquidShimmer) then return end
  local on = optionValue('liquidShimmer')
  if on and not liquidTableSent and Item.addLiquidId then
    if Item.clearLiquidIds then Item.clearLiquidIds() end
    for _, e in ipairs(L.liquidList()) do pcall(Item.addLiquidId, e.id, e.kind) end
    liquidTableSent = true
  end
  if on then createLiquidShaders() end
  pcall(Item.setLiquidShimmer, on)
end

-- ---------------------------------------------------------------- weather
-- the rain of game_chaosweather (O208, base patch 0130 has the checkbox): this file only passes the option on
local function applyWeather()
  local m = modules.game_chaosweather
  if m and m.setEnabled then pcall(m.setEnabled, optionValue('weather')) end
end

-- the ambient particles of game_chaosweather (O226, base patch 0144 has the checkbox): this file only passes the option on
local function applyAmbient()
  local m = modules.game_chaosweather
  if m and m.setAmbientEnabled then pcall(m.setAmbientEnabled, optionValue('ambientParticles')) end
end

-- ---------------------------------------------------------------- soft glow
local bloomShadersMade = false

local function createBloomShaders()
  if bloomShadersMade then return true end
  local B = L.BLOOM
  for _, name in ipairs({ B.extractShader, B.blurShader }) do
    local ok, err = pcall(g_shaders.createShader, name, B.vertex, '/shaders/' .. name)
    if not ok then
      g_logger.warning('[visualfx] ' .. name .. ': ' .. tostring(err))
      return false
    end
  end
  bloomShadersMade = true
  return true
end

local function applyBloom()
  if not (g_app and g_app.setMapBloom) then return end -- a client without base patch 0132
  local on = optionValue('bloom')
  if on and not createBloomShaders() then on = false end
  pcall(g_app.setMapBloom, on, L.bloomStrength(on))
end

-- ---------------------------------------------------------------- floating numbers
local function applyNumberMotion()
  if AnimatedText and AnimatedText.setSoftMotion then pcall(AnimatedText.setSoftMotion, optionValue('numberMotion')) end
end

-- ---------------------------------------------------------------- death fade (O221)
local function applyDeathFade()
  if Creature and Creature.setDeathFade then pcall(Creature.setDeathFade, optionValue('deathFade')) end
end

-- ---------------------------------------------------------------- missile trails and arcs (O230)
local arcIdsSent = false

local function applyMissileTrails()
  if not (Missile and Missile.setTrails) then return end
  local on = optionValue('missileTrails')
  if on and not arcIdsSent and Missile.addArcId then
    if Missile.clearArcIds then pcall(Missile.clearArcIds) end
    for _, id in ipairs(L.ARC_MISSILES) do pcall(Missile.addArcId, id) end
    arcIdsSent = true
  end
  pcall(Missile.setTrails, on)
end

-- ---------------------------------------------------------------- hit flash tint (O224)
local function applyHitTint()
  if Creature and Creature.setHitTint then pcall(Creature.setHitTint, optionValue('hitFlash')) end
end

-- ---------------------------------------------------------------- smooth health bars (O229)
local function applySmoothBars()
  if Creature and Creature.setSmoothBars then pcall(Creature.setSmoothBars, optionValue('smoothBars')) end
end

-- ---------------------------------------------------------------- light flicker (O228)
local function applyLightFlicker()
  if g_map and g_map.setLightFlicker then pcall(g_map.setLightFlicker, optionValue('lightFlicker') and true or false) end
end

-- ---------------------------------------------------------------- target, follow and hover outline (O216)
local hl = { applied = {}, target = nil, follow = nil, hover = nil, panel = nil, mouseOn = false, gate = {}, sweep = nil }

local function alive(c)
  if c == nil then return false end
  local ok, removed = pcall(c.isRemoved, c)
  return ok and not removed
end

-- tells game_cosmeticfx to leave this creature's outline alone (on) or to put the bought one back (off)
local function cosmeticHold(id, on)
  local m = modules.game_cosmeticfx
  if m and m.setHighlight then pcall(m.setHighlight, id, on) end
end

local function outlineApply(creature, kind)
  local a = L.outlineArgs(kind)
  if not a or not creature.setOutline then return false end
  pcall(creature.clearOutline, creature) -- a cosmetic gradient must not stay under our colour
  pcall(creature.setOutline, creature, a[1], a[2], a[3], a[4], a[5], a[6])
  return true
end

local function outlineSweep()
  local id = next(hl.applied)
  if not id then
    if hl.sweep then removeEvent(hl.sweep); hl.sweep = nil end
    return
  end
  local changed = false
  for cid, a in pairs(hl.applied) do
    if not alive(a.creature) then
      hl.applied[cid] = nil
      cosmeticHold(cid, false)
      if hl.target == a.creature then hl.target = nil end
      if hl.follow == a.creature then hl.follow = nil end
      if hl.hover == a.creature then hl.hover = nil end
      changed = true
    elseif a.creature.hasOutline and not a.creature:hasOutline() then
      outlineApply(a.creature, a.kind) -- something cleared it
    end
  end
  if changed and not next(hl.applied) and hl.sweep then removeEvent(hl.sweep); hl.sweep = nil end
end

-- brings the engine in line with the target / follow / hover creatures and the two options; calls only for what changed
local function outlineRefresh()
  local opts = { target = optionValue('targetOutline'), hover = optionValue('hoverOutline') }
  if not next(hl.applied) and not opts.target and not opts.hover then return end
  local me = g_game.getLocalPlayer()
  local byId, st = {}, { meId = me and me:getId() or nil }
  for _, k in ipairs({ 'target', 'follow', 'hover' }) do
    local c = hl[k]
    if c and alive(c) then
      local id = c:getId()
      byId[id] = c
      st[k .. 'Id'] = id
    end
  end
  local kinds = {}
  for id, a in pairs(hl.applied) do kinds[id] = a.kind end
  for _, op in ipairs(L.outlineDiff(kinds, L.outlineWanted(st, opts))) do
    if op.op == 'clear' then
      local a = hl.applied[op.id]
      hl.applied[op.id] = nil
      if a and alive(a.creature) and a.creature.clearOutline then pcall(a.creature.clearOutline, a.creature) end
      cosmeticHold(op.id, false)
    else
      local c = byId[op.id]
      if c then
        cosmeticHold(op.id, true)
        if outlineApply(c, op.kind) then
          hl.applied[op.id] = { kind = op.kind, creature = c }
        else
          cosmeticHold(op.id, false)
        end
      end
    end
  end
  if next(hl.applied) and not hl.sweep then hl.sweep = cycleEvent(outlineSweep, L.OUTLINE.sweepMs) end
end

local function outlineClearAll()
  hl.target, hl.follow, hl.hover = nil, nil, nil
  outlineRefresh()
  if hl.sweep then removeEvent(hl.sweep); hl.sweep = nil end
end

local function onMapMouseMove(widget, mousePos)
  if not L.mouseGate(hl.gate, now()) then return end
  local c = nil
  if widget.getCreatureAt then
    local ok, res = pcall(widget.getCreatureAt, widget, mousePos)
    if ok then c = res end
  end
  if c == hl.hover then return end -- the usual case: still the same creature (or still none)
  hl.hover = c
  outlineRefresh()
end

local function onMapHoverChange(widget, hovered)
  if not hovered and hl.hover then
    hl.hover = nil
    outlineRefresh()
  end
end

local mouseHooks = { onMouseMove = onMapMouseMove, onHoverChange = onMapHoverChange }

local function unhookMouse()
  if hl.mouseOn and hl.panel then pcall(disconnect, hl.panel, mouseHooks) end
  hl.mouseOn = false
end

local function applyOutlines()
  if optionValue('hoverOutline') then
    if not hl.mouseOn then
      local panel = mapPanel()
      if panel then
        hl.panel = panel
        connect(panel, mouseHooks)
        hl.mouseOn = true
      end
    end
  else
    unhookMouse()
    hl.hover = nil
  end
  outlineRefresh()
end

local function onAttackingChange(creature)
  hl.target = creature
  outlineRefresh()
end

local function onFollowingChange(creature)
  hl.follow = creature
  outlineRefresh()
end

-- ---------------------------------------------------------------- scene fade (O219)
local SF = SceneFadeLogic
local sf = { state = SF.new(), widget = nil, event = nil, hooked = false }
local sfHooks = {}

local function sfAlive(w)
  if w == nil then return false end
  local ok, destroyed = pcall(w.isDestroyed, w)
  return ok and not destroyed
end

-- the black layer on the game map panel, made on the first fade; nil when the panel is not there
local function sfWidget()
  if sfAlive(sf.widget) then return sf.widget end
  local panel = mapPanel()
  if not panel then return nil end
  local ok, w = pcall(g_ui.createWidget, 'ChaosSceneFade')
  if not ok or not w then return nil end
  pcall(panel.insertChild, panel, 1, w)
  pcall(w.fill, w, 'parent')
  pcall(w.setOpacity, w, 0)
  sf.widget = w
  return w
end

local function sfHide()
  if sfAlive(sf.widget) then
    pcall(sf.widget.setOpacity, sf.widget, 0)
    pcall(sf.widget.setVisible, sf.widget, false)
  end
end

local function sfStop()
  if sf.event then
    removeEvent(sf.event)
    sf.event = nil
  end
  sf.state.from = 0
  sf.state.shown = 0
  sfHide()
end

local function sfStep()
  local level, changed, over = SF.step(sf.state, now())
  local w = sf.widget
  if sfAlive(w) then
    if changed and not over then
      pcall(w.setOpacity, w, level)
      pcall(w.setVisible, w, true)
    end
  end
  if over then sfStop() end
end

local function onPlayerPosition(player, newPos, oldPos)
  local kind = SF.classify(newPos, oldPos)
  if not kind then return end -- the usual case: a walking step
  if not SF.trigger(sf.state, now(), kind) then return end
  if not sfWidget() then return end
  if not sf.event then sf.event = cycleEvent(sfStep, SF.CFG.tickMs) end
  sfStep() -- the first dark frame is this one, with the new picture
end

local function applySceneFade()
  local on = optionValue('sceneFade')
  if on and not sf.hooked then
    sfHooks = { onPositionChange = onPlayerPosition }
    connect(LocalPlayer, sfHooks)
    sf.hooked = true
  elseif not on and sf.hooked then
    pcall(disconnect, LocalPlayer, sfHooks)
    sf.hooked = false
  end
  if not on then sfStop() end
end

local function sceneFadeStart()
  SF.reset(sf.state, now())
  sfStop()
end

local function sceneFadeEnd()
  sfStop()
  if sfAlive(sf.widget) then sf.widget:destroy() end
  sf.widget = nil
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
  elseif name == 'liquidShimmer' then
    applyLiquid()
  elseif name == 'weather' then
    applyWeather()
  elseif name == 'ambientParticles' then
    applyAmbient()
  elseif name == 'bloom' then
    applyBloom()
  elseif name == 'numberMotion' then
    applyNumberMotion()
  elseif name == 'targetOutline' or name == 'hoverOutline' then
    applyOutlines()
  elseif name == 'sceneFade' then
    applySceneFade()
  elseif name == 'deathFade' then
    applyDeathFade()
  elseif name == 'missileTrails' then
    applyMissileTrails()
  elseif name == 'hitFlash' then
    applyHitTint()
  elseif name == 'smoothBars' then
    applySmoothBars()
  elseif name == 'lightFlicker' then
    applyLightFlicker()
  elseif name == 'screenShake' and value == false then
    stopShake()
  end
end

function reapply()
  applyShadow()
  applyGrade()
  applySpellLight()
  applyLiquid()
  applyWeather()
  applyAmbient()
  applyBloom()
  applyNumberMotion()
  applyOutlines()
  applySceneFade()
  applyDeathFade()
  applyHitTint()
  applySmoothBars()
  applyMissileTrails()
  applyLightFlicker()
end

-- ---------------------------------------------------------------- lifecycle
local function onGameStart()
  flasher = L.newFlasher()
  stopShake()
  sceneFadeStart()
  hl.target = g_game.getAttackingCreature and g_game.getAttackingCreature() or nil
  hl.follow = g_game.getFollowingCreature and g_game.getFollowingCreature() or nil
  reapply()
end

local function onGameEnd()
  stopShake()
  sceneFadeEnd()
  outlineClearAll()
  unhookMouse()
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
  g_ui.importStyle('scenefade')
  createFlashShaders()
  handlers.game = { onGameStart = onGameStart, onGameEnd = onGameEnd,
                    onAttackingCreatureChange = onAttackingChange, onFollowingCreatureChange = onFollowingChange }
  connect(g_game, handlers.game)
  handlers.map = { onImpactText = onImpactText }
  connect(g_map, handlers.map)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  if handlers.game then disconnect(g_game, handlers.game) end
  if handlers.map then disconnect(g_map, handlers.map) end
  stopShake()
  sceneFadeEnd()
  if sf.hooked then pcall(disconnect, LocalPlayer, sfHooks); sf.hooked = false end
  outlineClearAll()
  unhookMouse()
  if Creature and Creature.setSoftShadow then pcall(Creature.setSoftShadow, false) end
  if g_map and g_map.setSpellLightConfig then pcall(g_map.setSpellLightConfig, false, 0, 0, 0, 0, 0) end
  if g_map and g_map.setLightFlicker then pcall(g_map.setLightFlicker, false) end
  if Item and Item.setLiquidShimmer then pcall(Item.setLiquidShimmer, false) end
  if g_app and g_app.setMapBloom then pcall(g_app.setMapBloom, false, 0) end
  if AnimatedText and AnimatedText.setSoftMotion then pcall(AnimatedText.setSoftMotion, false) end
  if Creature and Creature.setDeathFade then pcall(Creature.setDeathFade, false) end
  if Missile and Missile.setTrails then pcall(Missile.setTrails, false) end
  if Creature and Creature.setHitTint then pcall(Creature.setHitTint, false) end
  if Creature and Creature.setSmoothBars then pcall(Creature.setSmoothBars, false) end
  local panel = mapPanel()
  if panel and panel.getShader and panel:getShader() == GRADE then panel:setShader('') end
  handlers = {}
end
