-- Footprints and outlines (server cosmetics.lua kinds footprint / outline). Every client draws them itself from the
-- "looks" the server sends (who wears which art; game_cosmetics forwards them with setLooks), so the server does no
-- work per step and a viewer can hide other players' footprints / outlines (settings, Character > Cosmetics).
--   footprints  (O499) one mark under each foot, two per step, put down as the feet land (CF.MODES[CF.MODE].at, a share
--               of the step time) on the tile the foot is over, at the foot's place (foot_marks.lua: where each look's
--               feet stand, per direction; a mount's when mounted), turned to the step's direction (45 degrees on a
--               diagonal), the newest strongest, fading out. A floor widget (Tile:setFloorWidget, base patch 0078: lies
--               under creatures, items and walls; Tile:setWidget without it) holds one widget per tile, so it is a plain
--               container (the host) and the marks are its children: walkers that cross share it. Floor widgets are drawn
--               in map pixels (scaled by the zoom), the fallback in screen pixels: CF.hostBox / markSize / markMargins
--               take the unit. Never on a tile that carries another module's widget; no new marks while the local player
--               stands in a protection zone (temples and depots are crowded)
--   outlines    a line around the player's silhouette (Creature:setOutline, base patch 0038: the engine draws it
--               under the outfit's parts, so it follows body, addons, mount and the walking frame and stacks with
--               outfit shaders, wings and auras); colours per art in CF.OUTLINES, pulsing ones breathe (engine side).
--               An engine without the patch gets the old soft glow picture instead (a creature bottom widget; other
--               modules' bottom widgets, game_levelwings, are left alone: ours is cleared only when it is the
--               creature's only one, the engine's removeBottomWidget walks the wrong list, else blanked)
--   effect footprints (O649, client pair 75) a footprint look that carries `e` = {id, dx, dy, ms} is drawn by playing that effect
--               of the pair once on the tile the walker left (Effect.create + g_map.addThing, as game_levelwings and game_lootbeams
--               play theirs), one a step, CF.FX_AT of the step time in; at most CF.FX_MAX_PER_CREATURE alive per walker and CF.FX_MAX
--               on screen; the same viewer setting, protection zone rule and step rules as the pictures. The ids are registered as
--               ground effects (base patch 0055) so they lie under the creatures
-- The pictures (prints; glows for old engines): client/tools/gen_cosmeticfx_art.py. Rules: cosmeticfxlogic.lua
-- (cosmeticfxlogic_test.lua).

local CF = CosmeticFxLogic

local SETTINGS_NODE = 'chaosCosmeticFx'
local TICK_MS = 100       -- fading and pulsing
local SWEEP_MS = 400      -- outlines follow who is on screen

local settings = { othersFootprints = true, othersOutlines = true }
local looks = {}          -- character name -> {f, o, p}
local preview             -- {look, untilMs}: the local player's store / window preview
local prints = {}         -- oldest first: {widget, tile, owner, born}
local glows = {}          -- creature id -> {art, pulse, creature, line = true | widget}
local held = {}            -- creature id -> true: game_visualfx draws its target / follow / hover outline there (setHighlight)
local engineLine          -- nil: not checked yet; true: Creature:setOutline exists (base patch 0038)
local events = {}
local handlers = {}
local mapPanel
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[cosmeticfx] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function now()
  return g_clock.millis()
end

local function spriteSize()
  local ok, s = pcall(function() return g_sprites.spriteSize() end)
  return ok and tonumber(s) or 32
end

-- ---------------------------------------------------------------- settings
local function loadSettings()
  local node = g_settings.getNode(SETTINGS_NODE)
  if type(node) == 'table' then
    settings.othersFootprints = node.othersFootprints ~= false and node.othersFootprints ~= 'false'
    settings.othersOutlines = node.othersOutlines ~= false and node.othersOutlines ~= 'false'
  end
end

function getSettings()
  return { othersFootprints = settings.othersFootprints, othersOutlines = settings.othersOutlines }
end

-- key 'othersFootprints' | 'othersOutlines' (Character > Cosmetics)
function setSetting(key, value)
  if key ~= 'othersFootprints' and key ~= 'othersOutlines' then return end
  settings[key] = value and true or false
  g_settings.setNode(SETTINGS_NODE, { othersFootprints = settings.othersFootprints, othersOutlines = settings.othersOutlines })
  if handlers.sweepSafe then handlers.sweepSafe() end
end

-- ---------------------------------------------------------------- footprints
local fxLive = {}         -- effect footprints alive: {owner, untilMs} (CF.fxAdmit)
local fxChecked = {}      -- effect id -> true | false: the client pair has it (a pair older than 75 does not)
local fxGround = {}       -- effect id -> true: registered as a ground effect (drawn under the creatures)
local hosts = {}          -- 'x,y,z' -> {widget, tile, n}: the container on a tile and how many marks it holds
local parity = {}         -- creature id -> which foot comes next (0 left, 1 right)
local lastStep = {}       -- creature id -> {ox, oy, nx, ny, z, t}: the same step is not marked twice

local function posKey(pos)
  return pos.x .. ',' .. pos.y .. ',' .. pos.z
end

local function dropHost(h, key)
  if hosts[key] == h then hosts[key] = nil end
  if not h.widget or h.widget:isDestroyed() then return end
  if h.tile and h.tile.getFloorWidget and h.tile:getFloorWidget() == h.widget then
    h.tile:removeFloorWidget()
  elseif h.tile and h.tile:getWidget() == h.widget then
    h.tile:removeWidget()
  else
    h.widget:destroy()
  end
end

local function dropPrint(p)
  local h = p.host
  if p.widget and not p.widget:isDestroyed() then p.widget:destroy() end
  if h then
    h.n = h.n - 1
    if h.n <= 0 then dropHost(h, p.key) end
  end
end

local function clearPrints()
  for _, p in ipairs(prints) do dropPrint(p) end
  for key, h in pairs(hosts) do dropHost(h, key) end
  prints = {}
  hosts = {}
  parity = {}
  lastStep = {}
  fxLive = {}
end

local function inPz()
  local me = g_game.getLocalPlayer()
  return me ~= nil and CF.hasFlag(me:getStates(), CF.PZ_FLAG)
end

local function tileSize()
  if not mapPanel then return 64, 64 end
  local vd, r = mapPanel:getVisibleDimension(), mapPanel:getRect()
  return CF.tileSize(r.width, r.height, vd.width, vd.height, mapPanel:isKeepAspectRatioEnabled())
end

-- the host of a tile: the container that carries its marks (nil when another module holds the tile's widget)
local function hostOf(tile, pos, onFloor, U, spr)
  local key = posKey(pos)
  local h = hosts[key]
  if h and h.widget and not h.widget:isDestroyed() then
    local held = onFloor and tile:getFloorWidget() or tile:getWidget()
    if held == h.widget then return h, key end
  end
  if h then
    hosts[key] = nil
    -- the engine cleaned the tile: its marks are gone with the container
  end
  if onFloor then
    if tile:getFloorWidget() then return nil end
  elseif tile:getWidget() then
    return nil
  end
  local size, ml, mt = CF.hostBox(U, spr)
  local w = g_ui.createWidget('UIWidget')
  w:resize(size, size)
  w:setMarginLeft(ml)
  w:setMarginTop(mt)
  w:setPhantom(true)
  if onFloor then tile:setFloorWidget(w) else tile:setWidget(w) end
  h = { widget = w, tile = tile, n = 0 }
  hosts[key] = h
  return h, key
end

-- one mark: mk = a CF.stepMarks entry, old = the step's old tile position
local function putMark(old, mk, rotation, art, owner, mode)
  local pos = { x = old.x + mk.tx, y = old.y + mk.ty, z = old.z }
  local tile = g_map.getTile(pos)
  if not tile then return end
  local onFloor = type(tile.setFloorWidget) == 'function'
  local spr = spriteSize()
  local U = spr
  if not onFloor then
    local tw, th = tileSize()
    U = math.min(tw, th)
  end
  for _, i in ipairs(CF.evictions(prints, owner, 1, mode.maxPer)) do dropPrint(prints[i]) end
  local keep = {}
  for _, p in ipairs(prints) do
    if p.widget and not p.widget:isDestroyed() then keep[#keep + 1] = p end
  end
  prints = keep
  local h, key = hostOf(tile, pos, onFloor, U, spr)
  if not h then return end
  local size = CF.markSize(U, mode.kind)
  local ml, mt = CF.markMargins(U, mk.px, mk.py, size)
  local w = g_ui.createWidget('UIWidget', h.widget)
  w:setImageSource(mode.kind == 'pair' and CF.printPath(art) or CF.markPath(art, mk.side))
  w:setImageSmooth(true)
  if mode.tint then w:setImageColor(mode.tint) end
  w:resize(size, size)
  w:addAnchor(AnchorTop, 'parent', AnchorTop)
  w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  w:setMarginLeft(ml)
  w:setMarginTop(mt)
  w:setRotation(rotation)
  w:setOpacity(mode.alpha)
  w:setPhantom(true)
  h.n = h.n + 1
  prints[#prints + 1] = { widget = w, host = h, key = key, owner = owner, born = now(), alpha = mode.alpha }
end

-- ---------------------------------------------------------------- effect footprints (O649)
-- the pair has this effect and the client can add one to a tile (checked once per id)
local function hasEffect(id)
  local c = fxChecked[id]
  if c == nil then
    c = false
    if type(Effect) == 'table' and Effect.create and g_map and g_map.addThing and g_things then
      local ok, valid = pcall(function()
        if g_things.isValidDatId then return g_things.isValidDatId(id, ThingCategoryEffect) end
        return g_things.getThingType(id, ThingCategoryEffect) ~= nil
      end)
      c = ok and valid and true or false
    end
    fxChecked[id] = c
    if not c then g_logger.info('[cosmeticfx] the client pair has no effect ' .. tostring(id) .. ' (pair 75): no effect footprint') end
  end
  return c
end

-- the effect lies under the creatures (base patch 0055, the same call game_groundfx makes for its ids)
local function setGround(id)
  if fxGround[id] ~= nil then return end
  fxGround[id] = false
  if g_map and type(g_map.setGroundEffect) == 'function' then
    fxGround[id] = pcall(g_map.setGroundEffect, id, true) and true or false
  end
end

local function playEffect(old, e, owner)
  if not hasEffect(e.id) then return end
  local ok, live = CF.fxAdmit(fxLive, owner, now())
  fxLive = live
  if not ok then return end
  local plan = CF.fxPlan(old, e, 0)
  setGround(e.id)
  local eff = Effect.create()
  eff:setId(e.id)
  g_map.addThing(eff, plan.pos, -1)
  fxLive[#fxLive + 1] = { owner = owner, untilMs = now() + CF.fxLife(e) }
end

local function onStep(creature, newPos, oldPos)
  if not preview and next(looks) == nil then return end -- no cosmetic is active: every creature step ends here
  if not creature or not creature:isPlayer() or not g_game.isOnline() then return end
  local me = g_game.getLocalPlayer()
  local isLocal = me ~= nil and creature:getId() == me:getId()
  local look = CF.lookOf(looks, creature:getName(), isLocal, preview, now())
  if not look or not look.f or not CF.allowed('footprint', settings, isLocal) then return end
  local rotation = CF.stepRotation(oldPos, newPos)
  if not rotation or inPz() then return end
  local owner = creature:getId()
  local stepMs = CF.stepTime(creature:getStepDuration())
  if CF.sameStep(lastStep[owner], oldPos, newPos, now(), stepMs) then return end
  lastStep[owner] = { ox = oldPos.x, oy = oldPos.y, nx = newPos.x, ny = newPos.y, z = newPos.z, t = now() }
  if look.e then
    -- an effect footprint: one effect on the tile left, as the walker leaves it (nothing if the walker stopped or was moved)
    local old = { x = oldPos.x, y = oldPos.y, z = oldPos.z }
    local goal = { x = newPos.x, y = newPos.y, z = newPos.z }
    local plan = CF.fxPlan(old, look.e, stepMs)
    scheduleEvent(safe('effect', function()
      if creature:isRemoved() or not CF.stillWalking(creature:getPosition(), goal) then return end
      playEffect(old, look.e, owner)
    end), plan.delay)
    return
  end
  local mode = CF.MODES[CF.MODE]
  local dx, dy = newPos.x - oldPos.x, newPos.y - oldPos.y
  local ok, outfit = pcall(function() return creature:getOutfit() end)
  local fx, fy = CF.feetOf(CosmeticFootMarks, ok and CF.footThing(outfit) or nil, CF.facing(dx, dy))
  local list, nextParity = CF.stepMarks(dx, dy, fx, fy, parity[owner] or 0, mode)
  parity[owner] = nextParity
  local old = { x = oldPos.x, y = oldPos.y, z = oldPos.z }
  local goal = { x = newPos.x, y = newPos.y, z = newPos.z }
  local art = look.f
  for _, mk in ipairs(list) do
    -- put down as the foot lands, not later: a walker that stopped, was moved or left the screen leaves nothing behind
    scheduleEvent(safe('mark', function()
      if creature:isRemoved() or not CF.stillWalking(creature:getPosition(), goal) then return end
      putMark(old, mk, rotation, art, owner, mode)
    end), math.floor(mk.at * stepMs))
  end
end

-- ---------------------------------------------------------------- outlines
local function dropGlow(cid)
  local g = glows[cid]
  glows[cid] = nil
  if g and g.line then
    if held[cid] then return end -- the highlight owns the engine line now and clears it itself
    pcall(function() g.creature:clearOutline() end)
    return
  end
  if not g or not g.widget or g.widget:isDestroyed() then return end
  local c = g.creature
  local mine = c and not c:isRemoved() and c:getBottomWidgets() or {}
  if c and #mine == 1 and mine[1] == g.widget then
    c:clearBottomWidgets() -- the only bottom widget is ours (removeBottomWidget of this engine is unsafe)
  else
    g.widget:setOpacity(0)
    g.widget:setImageSource('')
  end
end

-- the engine line (base patch 0038)
local function setLine(creature, look)
  local cid = creature:getId()
  if held[cid] then return end -- a highlight is up: nothing is recorded, so the line comes back when it ends
  local g = glows[cid]
  if g and g.line and g.art == look.o and g.pulse == look.p and g.creature == creature then return end
  if g and not g.line then dropGlow(cid) end
  local args = CF.outlineArgs(look.o, look.p)
  if not args then
    if g then dropGlow(cid) end
    return
  end
  creature:setOutline(args[1], args[2], args[3], args[4], args[5], args[6])
  if args.top then
    creature:setOutlineGradient(args.top[1], args.top[2], args.top[3], args.top[4])
  end
  glows[cid] = { line = true, art = look.o, pulse = look.p, creature = creature }
end

-- old engines: the glow picture behind the character
local function setGlow(creature, look)
  if engineLine == nil then engineLine = CF.hasEngineOutline(creature) end
  if engineLine then return setLine(creature, look) end
  local cid = creature:getId()
  local g = glows[cid]
  if g and g.widget and not g.widget:isDestroyed() and g.art == look.o then
    g.pulse = look.p
    return
  end
  if g and g.widget and not g.widget:isDestroyed() then
    g.widget:setImageSource(CF.glowPath(look.o))
    g.widget:setOpacity(1)
    g.art, g.pulse = look.o, look.p
    return
  end
  local size = CF.glowSize(spriteSize())
  local w = g_ui.createWidget('UIWidget')
  w:setImageSource(CF.glowPath(look.o))
  w:setImageSmooth(true)
  w:resize(size, size)
  w:setPhantom(true)
  creature:addBottomWidget(w)
  glows[cid] = { widget = w, art = look.o, pulse = look.p, creature = creature }
end

handlers.sweep = function()
  if not preview and next(looks) == nil and next(glows) == nil then return end -- nothing to draw or to drop
  if not g_game.isOnline() then return end
  local me = g_game.getLocalPlayer()
  if not me then return end
  local seen = {}
  local t = now()
  for _, c in ipairs(g_map.getSpectators(me:getPosition(), false) or {}) do
    if c:isPlayer() then
      local isLocal = c:getId() == me:getId()
      local look = CF.lookOf(looks, c:getName(), isLocal, preview, t)
      if look and look.o and CF.allowed('outline', settings, isLocal) then
        setGlow(c, look)
        seen[c:getId()] = true
      end
    end
  end
  for cid in pairs(glows) do
    if not seen[cid] then dropGlow(cid) end
  end
end

handlers.tick = function()
  if not preview and #prints == 0 and next(glows) == nil then return end
  local t = now()
  local keep = {}
  local mode = CF.MODES[CF.MODE]
  local ranks = CF.ranks(prints)
  for i, p in ipairs(prints) do
    local a = p.widget and not p.widget:isDestroyed() and CF.markOpacity(t - p.born, ranks[i], mode)
    if a then
      if math.abs(a - (p.shown or -1)) >= 0.02 then
        p.widget:setOpacity(a)
        p.shown = a
      end
      keep[#keep + 1] = p
    else
      dropPrint(p)
    end
  end
  prints = keep
  local pulse = CF.pulseOpacity(t)
  for cid, g in pairs(glows) do
    if g.line then
      -- the engine pulses its own line
    elseif not g.widget or g.widget:isDestroyed() then
      glows[cid] = nil -- the engine cleared the creature's widgets (it left the screen)
    elseif g.pulse then
      g.widget:setOpacity(pulse)
    end
  end
  if preview and t >= preview.untilMs then
    preview = nil
    handlers.sweep()
  end
end

local function clearGlows()
  for cid in pairs(glows) do dropGlow(cid) end
  glows = {}
end

-- ---------------------------------------------------------------- API (game_cosmetics)
-- msg = the server's "looks" data {names, full}
function setLooks(msg)
  looks = CF.mergeLooks(looks, msg)
  if handlers.sweepSafe then handlers.sweepSafe() end
end

-- a preview on the local player: kind 'footprint' | 'outline', art, pulse (the store's SHOW, the window's Preview); e = the
-- effect of an effect footprint ({id, dx, dy, ms}, O649), else nil
function showPreview(kind, art, pulse, e)
  if not CF.validArt(art) then return end
  local look = kind == 'footprint' and { f = art } or { o = art, p = pulse and true or nil }
  if kind == 'footprint' and e ~= nil then
    look.e = CF.cleanEffect(e)
    if not look.e then return end
  end
  preview = { look = look, untilMs = now() + CF.PREVIEW_MS }
  if handlers.sweepSafe then handlers.sweepSafe() end
end

-- game_visualfx (O216): its target / follow / hover outline wins on a creature while it is up. on = true: leave this
-- creature's line alone; on = false: the highlight has cleared its line, forget ours and draw the bought one again if
-- the creature still wears it (the sweep runs at once, not in 400 ms)
function setHighlight(creatureId, on)
  if not creatureId then return end
  if on then
    held[creatureId] = true
    return
  end
  if not held[creatureId] then return end
  held[creatureId] = nil
  local g = glows[creatureId]
  if g and g.line then glows[creatureId] = nil end
  if handlers.sweepSafe then handlers.sweepSafe() end
end

function getLooks()
  return looks
end

-- game_cosmetics (the window): lay an effect of a footprint row under the creatures before it is drawn (a no-op without the patch)
function registerGround(id)
  id = tonumber(id)
  if id and id >= 1 then setGround(id) end
end

-- an outline on any creature (game_cosmetics: the window's sample, a widget's own creature); false when this engine
-- has no outline pass (base patch 0038) or the art is unknown, then the caller shows the glow picture
function applyOutline(creature, art, pulse)
  if not CF.hasEngineOutline(creature) then return false end
  local args = CF.outlineArgs(art, pulse)
  if not args then return false end
  creature:setOutline(args[1], args[2], args[3], args[4], args[5], args[6])
  if args.top then
    creature:setOutlineGradient(args.top[1], args.top[2], args.top[3], args.top[4])
  end
  return true
end

local function onGameStart()
  mapPanel = modules.game_interface.getMapPanel()
end

local function onGameEnd()
  held = {}
  clearPrints()
  clearGlows()
  looks, preview = {}, nil
end

function init()
  loadSettings()
  handlers.step = safe('step', onStep)
  handlers.sweepSafe = safe('sweep', handlers.sweep)
  handlers.tickSafe = safe('tick', handlers.tick)
  connect(Creature, { onPositionChange = handlers.step })
  connect(LocalPlayer, { onPositionChange = handlers.step })
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  events.tick = cycleEvent(handlers.tickSafe, TICK_MS)
  events.sweep = cycleEvent(handlers.sweepSafe, SWEEP_MS)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(Creature, { onPositionChange = handlers.step })
  disconnect(LocalPlayer, { onPositionChange = handlers.step })
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  for _, e in pairs(events) do removeEvent(e) end
  events = {}
  held = {}
  clearPrints()
  clearGlows()
  for id, on in pairs(fxGround) do
    if on and g_map and type(g_map.setGroundEffect) == 'function' then pcall(g_map.setGroundEffect, id, false) end
  end
  fxGround = {}
end
