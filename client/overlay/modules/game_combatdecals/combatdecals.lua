-- game_combatdecals (O231; client/MANIFEST.md "Combat decals"): stains on the ground after combat, Lua only.
--   blood      where a creature dies (Creature.onHealthPercentChange to 0); red for all, creatures whose name says they
--              bleed none (skeletons, ghosts, golems, elementals ...) get no stain; never the local player
--   scorch / frost / green stain   under a fire / ice / poison or earth hit (g_map.onImpactText, base patch 0100): the
--              damage number has no element, its colour does (CombatDecalsLogic.kindOfColor)
-- Each lies on the floor of its tile (Tile:setFloorWidget, base patch 0078: under creatures, items and walls, the way
-- game_cosmeticfx puts footprints down) and fades out over 20-30 s. A tile whose floor widget another module holds (a
-- footprint, a ground label, a hideout mark) gets none. At most CD.MAX are alive, only on the screen, only on the
-- player's floor. The fade timer runs only while a decal exists and does nothing while the window is minimized (its
-- clock goes on, so decals that ran out meanwhile are dropped at the restore). Everything goes at logout, on a floor
-- change, on a jump of more than a screen (teleport, map change) and when the option `combatDecals` is turned off
-- (Options > Graphics "Stains on the ground", default on, base patch 0148). The pictures: client/tools/gen_decal_art.py.
-- Rules: combatdecals_logic.lua (combatdecals_test.lua).

local CD = CombatDecalsLogic

local state = CD.newState()
local enabled = true
local timer                 -- the cycleEvent, only while decals exist
local hooked = false
local lastPos               -- the local player's last position (floor change / jump detection)
local tw, th = 64, 64       -- tile size the widgets were made for
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[combatdecals] ' .. name .. ': ' .. tostring(res))
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

local function mapPanel()
  local gi = modules.game_interface
  return gi and gi.getMapPanel and gi.getMapPanel() or nil
end

local function hidden()
  return g_window ~= nil and g_window.isVisible ~= nil and not g_window.isVisible()
end

local function measureTile()
  local panel = mapPanel()
  if not panel then return end
  local vd, r = panel:getVisibleDimension(), panel:getRect()
  tw, th = CD.tileSize(r.width, r.height, vd.width, vd.height, panel:isKeepAspectRatioEnabled())
end

-- ---------------------------------------------------------------- widgets
local function dropWidget(d)
  local w = d.widget
  d.widget = nil
  if not w or w:isDestroyed() then return end
  local tile = d.tile
  if tile and tile.getFloorWidget and tile:getFloorWidget() == w then
    tile:removeFloorWidget()
  else
    w:destroy()
  end
end

local function stopTimer()
  if timer then
    removeEvent(timer)
    timer = nil
  end
end

local function clearAll()
  for _, d in ipairs(state.decals) do dropWidget(d) end
  state = CD.newState()
  stopTimer()
end

local tick

local function startTimer()
  if not timer then timer = cycleEvent(tick, CD.TICK_MS) end
end

tick = safe('tick', function()
  if #state.decals == 0 then
    stopTimer()
    return
  end
  if hidden() then return end -- minimized: nothing is drawn, so nothing is updated
  if not g_game.isOnline() then
    clearAll()
    return
  end
  local t = now()
  local alive, gone = CD.step(state, t)
  for _, d in ipairs(gone) do dropWidget(d) end
  local keep = {}
  local oldW, oldH = tw, th
  measureTile()
  local resize = oldW ~= tw or oldH ~= th
  local size, ml, mt
  if resize then size, ml, mt = CD.box(tw, th, spriteSize()) end
  for _, d in ipairs(alive) do
    local w = d.widget
    if w and not w:isDestroyed() then
      if math.abs((d.shown or 2) - d.alpha) >= 0.02 then
        w:setOpacity(d.alpha)
        d.shown = d.alpha
      end
      if resize then
        w:resize(size, size)
        w:setMarginLeft(ml)
        w:setMarginTop(mt)
      end
      keep[#keep + 1] = d
    end
  end
  state.decals = keep
  if #keep == 0 then stopTimer() end
end)

-- ---------------------------------------------------------------- putting one down
local function tileFree(pos)
  local tile = g_map.getTile(pos)
  return tile ~= nil and tile:getFloorWidget() == nil
end

local function put(kind, pos, spread)
  if not enabled or not g_game.isOnline() then return end
  if not Tile or type(Tile.setFloorWidget) ~= 'function' then return end
  local me = g_game.getLocalPlayer()
  local panel = mapPanel()
  if not me or not panel then return end
  local t = now()
  if not CD.mayAdd(state, kind, t) then return end
  local vd = panel:getVisibleDimension()
  if not CD.onScreen(pos, me:getPosition(), vd.width, vd.height) then return end
  local target = CD.pickTile(pos, tileFree, spread, math.random)
  if not target then return end
  local tile = g_map.getTile(target)
  if not tile then return end
  for _, i in ipairs(CD.evictions(state)) do dropWidget(state.decals[i]) end
  local keep = {}
  for _, d in ipairs(state.decals) do
    if d.widget then keep[#keep + 1] = d end
  end
  state.decals = keep
  while #state.decals >= CD.MAX do
    dropWidget(table.remove(state.decals, 1))
  end
  measureTile()
  local size, ml, mt = CD.box(tw, th, spriteSize())
  local w = g_ui.createWidget('UIWidget')
  w:setImageSource(CD.path(kind, math.random(CD.VARIANTS)))
  w:setImageSmooth(true)
  w:resize(size, size)
  w:setMarginLeft(ml)
  w:setMarginTop(mt)
  w:setRotation(CD.rotation(math.random()))
  w:setOpacity(CD.START)
  w:setPhantom(true)
  tile:setFloorWidget(w)
  CD.add(state, { kind = kind, widget = w, tile = tile, born = t, life = CD.lifeFor(math.random()), shown = CD.START })
  startTimer()
end

-- ---------------------------------------------------------------- triggers
-- g_map.onImpactText (base patch 0100): a stain under a fire / ice / poison hit. Never drops the number.
local function onImpactText(animated, _, mode, typeId, value, _, _, pos)
  if not enabled or not pos then return false end
  local ok, color = pcall(function() return animated:getColor() end)
  if not ok then return false end
  local kind = CD.hitKind(mode, typeId, value, color)
  if kind then put(kind, pos, 0) end
  return false
end

-- Creature.onHealthPercentChange: 0 health is a death (game_visualfx's death fade relies on the same)
local function onHealth(creature, percent)
  if not enabled or percent == nil or percent > 0 then return end
  if not creature or creature:isLocalPlayer() or not creature:isMonster() then return end
  if not CD.bleeds(creature:getName()) then return end
  local pos = creature:getPosition()
  if pos then put('blood', pos, CD.SPREAD) end
end

-- the local player changed floor or jumped more than a screen: the old stains are not on this map any more
local function onPosition(creature, newPos, oldPos)
  if not newPos or #state.decals == 0 then
    lastPos = newPos or lastPos
    return
  end
  local panel = mapPanel()
  local vd = panel and panel:getVisibleDimension() or { width = 15, height = 11 }
  local far = math.max(vd.width, vd.height)
  if oldPos and (newPos.z ~= oldPos.z or math.abs(newPos.x - oldPos.x) > far or math.abs(newPos.y - oldPos.y) > far) then
    clearAll()
  end
  lastPos = newPos
end

-- ---------------------------------------------------------------- hooks and option
local handlers = {}

local function hook()
  if hooked then return end
  hooked = true
  connect(g_map, handlers.map)
  connect(Creature, handlers.creature)
  connect(LocalPlayer, handlers.player)
end

local function unhook()
  if not hooked then return end
  hooked = false
  disconnect(g_map, handlers.map)
  disconnect(Creature, handlers.creature)
  disconnect(LocalPlayer, handlers.player)
end

local function optionValue()
  local cs = modules.client_settings
  local ok, v = pcall(function() return cs and cs.getOption and cs.getOption('combatDecals') end)
  return CD.optionOn(ok and v or nil)
end

local function apply()
  enabled = optionValue()
  if enabled then
    hook()
  else
    clearAll()
    unhook()
  end
end

-- from the options' apply (client_settings dataset.lua, base patch 0148)
function onOption(name, value)
  if name ~= 'combatDecals' then return end
  enabled = CD.optionOn(value)
  if enabled then
    hook()
  else
    clearAll()
    unhook()
  end
end

local function onGameStart()
  lastPos = nil
  clearAll()
  apply()
end

local function onGameEnd()
  clearAll()
end

function init()
  handlers.map = { onImpactText = safe('impact', onImpactText) }
  handlers.creature = { onHealthPercentChange = safe('health', onHealth) }
  handlers.player = { onPositionChange = safe('position', onPosition) }
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() else enabled = optionValue() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  unhook()
  clearAll()
  handlers = {}
end
