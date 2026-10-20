-- Level-up wings: when a character on screen gains a level, a pair of golden wings opens behind it and fades out
-- (about 1.8 s). The server (server/data/scripts/chaos/levelwings.lua) sends extended opcode 191, JSON
-- {action = 'play', data = {id = creature id, lv = new level, n = levels gained}}, to every player who sees the
-- character; the stock level-up text and effect are untouched.
--
-- Drawing: the engine's creature widgets (Creature:addBottomWidget / addTopWidget). The engine draws them centred on
-- a 32 px sprite's middle (the tile centre moved by the look's displacement), so the image is moved onto the body's
-- shoulders by LevelWingsMath.offsetFor; bottom widgets before its outfit (behind), top widgets after it (in front), on the map and in its
-- walk, so the wings follow the character and nothing in the .dat / .spr pair changes. The frames are
-- images/wings_01..12.png, the front pair, and wings_east_ / wings_west_01..12.png, the side pair
-- (client/tools/gen_levelwings_art.py); the timing is in levelwingsmath.lua.
-- The wings follow the character's facing (LevelWingsMath.viewFor, read every tick, so a turn mid-animation switches
-- the set without a restart): the front pair facing south or north, the side pair facing east or west, placed on the
-- back. They sit behind the character, or in front while it faces north (its back to the viewer).
--
-- Settings (Options > Effects, client base patch 0036): "Level-up wings on my character" (levelWingsOwn) and
-- "Level-up wings on other characters" (levelWingsOthers), both on by default. Without them (an older settings
-- module) both count as on.

local OPCODE = 191
local TICK_MS = 33

local active = {}   -- creature id -> {creature, bottom, top, start}
local tickEvent
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[levelwings] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

-- a settings value, or nil when the settings module or the option is not there
local function option(key)
  local s = modules.client_settings
  local opts = s and s.GameOptions
  if not opts or not opts.getDataSet then return nil end
  local ok, data = pcall(opts.getDataSet, opts, key)
  if not ok or type(data) ~= 'table' then return nil end
  return data.value
end

-- the look's place (LevelWingsMath.offsetFor): the character select's outfit anchors of the pair (the same table,
-- client_chaos_charselect/outfit_anchors.lua, loaded once here) and the look's displacement from the dat
local anchorsLoaded = false
local function anchorsTable()
  if not anchorsLoaded then
    anchorsLoaded = true
    if CharSelectAnchors == nil then
      pcall(dofile, '/modules/client_chaos_charselect/outfit_anchors.lua')
    end
  end
  return CharSelectAnchors
end

local function lookOffset(c, k, view)
  local ok, outfit = pcall(c.getOutfit, c)
  local look = ok and type(outfit) == 'table' and outfit.type or nil
  local anchors = anchorsTable()
  local anchor = look and type(anchors) == 'table' and anchors[look] or nil
  local dx, dy = 0, 0
  if look and g_things and g_things.getThingType then
    local ok2, tt = pcall(g_things.getThingType, look, ThingCategoryCreature)
    if ok2 and tt then
      dx, dy = tt:getDisplacementX() or 0, tt:getDisplacementY() or 0
    end
  end
  return LevelWingsMath.offsetFor(anchor, dx, dy, k, view)
end

local function newWidget()
  local w = g_ui.createWidget('UIWidget')
  w:setPhantom(true)
  w:setFocusable(false)
  w:setImageSmooth(true)
  return w
end

-- take our widgets off the creature. Removing one bottom widget is broken in the engine (Creature::removeBottomWidget
-- walks the wrong list), so the bottom one is cleared only when it is the creature's only bottom widget; otherwise it
-- is left blank (no image draws nothing) and reused by the next play on that creature.
local function detach(entry)
  local c = entry.creature
  if entry.top then
    pcall(c.removeTopWidget, c, entry.top)
    entry.top = nil
  end
  if entry.bottom then
    local ok, list = pcall(c.getBottomWidgets, c)
    if ok and type(list) == 'table' and #list == 1 and list[1] == entry.bottom then
      pcall(c.clearBottomWidgets, c)
    else
      entry.bottom:setImageSource('')
      entry.bottom:setOpacity(0)
      c.levelWingsBottom = entry.bottom
    end
    entry.bottom = nil
  end
end

local function stopTick()
  if tickEvent then
    removeEvent(tickEvent)
    tickEvent = nil
  end
end

local function finish(id)
  local entry = active[id]
  if not entry then return end
  active[id] = nil
  detach(entry)
  if next(active) == nil then stopTick() end
end

local function draw(entry, now)
  local c = entry.creature
  if c:isRemoved() then return false end
  local frame, opacity, done = LevelWingsMath.at(now - entry.start)
  if done then return false end
  local scale = c.getDrawScale and c:getDrawScale() or 1
  local w, h = LevelWingsMath.sizeFor(g_sprites.spriteSize(), scale)
  -- the direction is read every tick: a turn mid-animation switches the frame set (and the place and layer), the
  -- timing goes on
  local direction = c:getDirection()
  local view = LevelWingsMath.viewFor(direction)
  local ox, oy = lookOffset(c, (g_sprites.spriteSize() / 32) * (tonumber(scale) or 1), view)
  local layer = LevelWingsMath.layerFor(direction)
  local show, blank = entry.bottom, entry.top
  if layer == 'top' then
    if not entry.top then
      entry.top = newWidget()
      c:addTopWidget(entry.top)
    end
    show, blank = entry.top, entry.bottom
  end
  if blank then
    blank:setImageSource('')
    blank:setOpacity(0)
  end
  show:setSize({ width = w, height = h })
  -- the engine centres the widget on a 32 px sprite's middle; the image moves to the body's shoulders
  show:setImageRect({ x = ox, y = oy, width = w, height = h })
  show:setImageSource(LevelWingsMath.framePath(frame, view))
  show:setOpacity(opacity)
  return true
end

local function tick()
  local now = g_clock.millis()
  local over = {}
  for id, entry in pairs(active) do
    local ok, alive = pcall(draw, entry, now)
    if not ok or not alive then over[#over + 1] = id end
  end
  for _, id in ipairs(over) do finish(id) end
end

local function startTick()
  if not tickEvent then
    tickEvent = cycleEvent(safe('tick', tick), TICK_MS)
  end
end

-- play the wings on a creature now (also used by hand from the terminal: modules.game_levelwings.play(id))
function play(id)
  local c = g_map.getCreatureById(id)
  if not c then return false end
  local isLocal = c:isLocalPlayer()
  if not LevelWingsMath.wanted(isLocal, option('levelWingsOwn'), option('levelWingsOthers')) then
    return false
  end
  local now = g_clock.millis()
  local entry = active[id]
  if entry and entry.creature ~= c then
    finish(id)
    entry = nil
  end
  if entry then
    -- already playing: start over (one pair of wings per creature)
    entry.start = now
  else
    local gone = LevelWingsMath.evict(active, now)
    if gone then finish(gone) end
    local bottom = c.levelWingsBottom
    c.levelWingsBottom = nil
    if not bottom then
      bottom = newWidget()
      c:addBottomWidget(bottom)
    end
    entry = { creature = c, bottom = bottom, start = now }
    active[id] = entry
  end
  draw(entry, now)
  startTick()
  return true
end

local function onMessage(protocol, opcode, msg)
  local id = LevelWingsMath.playId(msg)
  if id then play(id) end
end

local function clearAll()
  for id in pairs(active) do finish(id) end
  active = {}
  stopTick()
end

function init()
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, safe('opcode', onMessage))
  connect(g_game, { onGameEnd = clearAll })
end

function terminate()
  disconnect(g_game, { onGameEnd = clearAll })
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  clearAll()
end
