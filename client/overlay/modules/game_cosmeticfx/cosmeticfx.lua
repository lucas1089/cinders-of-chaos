-- Footprints and outlines (server cosmetics.lua kinds footprint / outline). Every client draws them itself from the
-- "looks" the server sends (who wears which art; game_cosmetics forwards them with setLooks), so the server does no
-- work per step and a viewer can hide other players' footprints / outlines (settings, Character > Cosmetics).
--   footprints  a print on the tile a player just left (Tile:setWidget, like game_groundlabels), turned to the step's
--               direction, fading out in CF.PRINT_LIFE_MS; never on a tile that carries another module's widget; no
--               new prints while the local player stands in a protection zone (temples and depots are crowded)
--   outlines    a soft glow behind the player (a creature bottom widget, drawn under the outfit, so it stacks with
--               outfit shaders, wings and auras); pulsing ones breathe. Other modules' bottom widgets (game_levelwings)
--               are left alone: ours is cleared only when it is the creature's only one (the engine's
--               removeBottomWidget walks the wrong list), else blanked
-- The pictures: client/tools/gen_cosmeticfx_art.py. Rules: cosmeticfxlogic.lua (cosmeticfxlogic_test.lua).

local CF = CosmeticFxLogic

local SETTINGS_NODE = 'chaosCosmeticFx'
local TICK_MS = 100       -- fading and pulsing
local SWEEP_MS = 400      -- outlines follow who is on screen

local settings = { othersFootprints = true, othersOutlines = true }
local looks = {}          -- character name -> {f, o, p}
local preview             -- {look, untilMs}: the local player's store / window preview
local prints = {}         -- oldest first: {widget, tile, owner, born}
local glows = {}          -- creature id -> {widget, art, pulse, creature}
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
local function dropPrint(p)
  if p.tile and p.widget and not p.widget:isDestroyed() then
    local w = p.tile:getWidget()
    if w == p.widget then
      p.tile:removeWidget()
      return
    end
  end
  if p.widget and not p.widget:isDestroyed() then p.widget:destroy() end
end

local function clearPrints()
  for _, p in ipairs(prints) do dropPrint(p) end
  prints = {}
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

local function putPrint(pos, rotation, art, owner)
  local tile = g_map.getTile(pos)
  if not tile or tile:getWidget() then return end -- ground labels, hideout marks: their tile stays theirs
  for _, i in ipairs(CF.evictions(prints, owner)) do dropPrint(prints[i]) end
  local keep = {}
  for _, p in ipairs(prints) do
    if p.widget and not p.widget:isDestroyed() then keep[#keep + 1] = p end
  end
  prints = keep
  local tw, th = tileSize()
  local size, ml, mt = CF.printBox(tw, th, spriteSize())
  local w = g_ui.createWidget('UIWidget')
  w:setImageSource(CF.printPath(art))
  w:setImageSmooth(true)
  w:resize(size, size)
  w:setMarginLeft(ml)
  w:setMarginTop(mt)
  w:setRotation(rotation)
  w:setOpacity(CF.PRINT_START)
  w:setPhantom(true)
  tile:setWidget(w)
  prints[#prints + 1] = { widget = w, tile = tile, owner = owner, born = now() }
end

local function onStep(creature, newPos, oldPos)
  if not creature or not creature:isPlayer() or not g_game.isOnline() then return end
  local me = g_game.getLocalPlayer()
  local isLocal = me ~= nil and creature:getId() == me:getId()
  local look = CF.lookOf(looks, creature:getName(), isLocal, preview, now())
  if not look or not look.f or not CF.allowed('footprint', settings, isLocal) then return end
  local rotation = CF.stepRotation(oldPos, newPos)
  if not rotation or inPz() then return end
  local pos = { x = oldPos.x, y = oldPos.y, z = oldPos.z }
  local art, owner = look.f, creature:getId()
  -- put down once the walker has left the tile (it would be drawn over the walker's feet before)
  local delay = math.max(0, math.min(600, (creature:getStepDuration() or 300) - 50))
  scheduleEvent(safe('print', function() putPrint(pos, rotation, art, owner) end), delay)
end

-- ---------------------------------------------------------------- outlines
local function dropGlow(cid)
  local g = glows[cid]
  glows[cid] = nil
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

local function setGlow(creature, look)
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
  local t = now()
  local keep = {}
  for _, p in ipairs(prints) do
    local a = p.widget and not p.widget:isDestroyed() and CF.printOpacity(t - p.born)
    if a then
      p.widget:setOpacity(a)
      keep[#keep + 1] = p
    else
      dropPrint(p)
    end
  end
  prints = keep
  local pulse = CF.pulseOpacity(t)
  for cid, g in pairs(glows) do
    if not g.widget or g.widget:isDestroyed() then
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

-- a preview on the local player: kind 'footprint' | 'outline', art, pulse (the store's SHOW, the window's Preview)
function showPreview(kind, art, pulse)
  if not CF.validArt(art) then return end
  local look = kind == 'footprint' and { f = art } or { o = art, p = pulse and true or nil }
  preview = { look = look, untilMs = now() + CF.PREVIEW_MS }
  if handlers.sweepSafe then handlers.sweepSafe() end
end

function getLooks()
  return looks
end

local function onGameStart()
  mapPanel = modules.game_interface.getMapPanel()
end

local function onGameEnd()
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
  clearPrints()
  clearGlows()
end
