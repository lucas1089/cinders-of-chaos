-- Loot burst: the animation of the Loot Explosion (O677; client/MANIFEST.md "Loot burst (O677)"). The server sends ONE message per kill on
-- opcode 230 (action "explode", game_groundlabels hands it to onExplode): the death tile and every flight (item, count, landing tile,
-- start delay, flight time, beam group). The real item lands on its tile exactly when its flight ends, so this module draws, on the
-- same clock:
--   * a flash on the death tile (a soft burst, as big and as coloured as the best item of the kill; a unique's own launch adds the
--     strongest one)
--   * each item as a UIItem widget (the real sprite, setItemId / setItemCount) over the death tile, moved by its margins along an arc:
--     ease-out along the ground, gravity upwards, a pop of size; rarer items fly higher; plain items quick and low
--   * a soft shadow on the ground under it that shrinks at the apex (a widget over the LANDING tile, moved back by the remaining way)
--   * for Legendary, Divine, set and unique items a trail of a few fading glows in the group's colour (also over the landing tile)
--   * at the landing a small hop, a dust puff and, for those groups, a ring flash in the group's colour; the item's widget goes
--     HOLD_MS (60 ms) after the flight ends, when the real item is there
-- All of them are Tile:addOverlayWidget widgets (base patch 0041: centred on a tile, moved by their margins, they follow walking,
-- scrolling and zoom). The pure rules are in lootburstlogic.lua. A burst steps every ~30 ms while it lasts and nothing runs when there is
-- none; at most 14 flights; whatever happens (logout, a floor change, a stuck timer) every widget is removed and destroyed.
-- The option "Loot burst animation" is in the Ground Labels window (game_groundlabels hands it to setEnabled); the server hears of it
-- with opcode 230 `burst {on = 1 | 0}` (at login and when it changes): while it is 1 the server leaves out its stock distance effects,
-- landing sparkles and poff for this player; off, they come back.

local LBL = LootBurstLogic

local enabled = true
local widgetsOk = nil
local bursts = {}        -- list of {t0, data, runs = {...}, fx = {...}, flash = {...}, counts = {tileKey -> n}, deadline}
local tickEvent
local startEvent
local handlers = {}
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[lootburst] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function nowMs()
  return g_clock.millis()
end

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

-- the client can put widgets over tiles and the pictures are in the module
local function hasWidgets()
  if widgetsOk == nil then
    widgetsOk = type(Tile) == 'table' and Tile.addOverlayWidget ~= nil and Tile.hasOverlayWidget ~= nil
      and Tile.removeOverlayWidget ~= nil and type(g_ui) ~= 'nil' and type(g_map) ~= 'nil' and g_map.getTile ~= nil
    if widgetsOk and g_resources and g_resources.fileExists then
      for _, kind in ipairs(LBL.ART_ORDER) do
        if not g_resources.fileExists(LBL.artPath(kind)) then widgetsOk = false end
      end
    end
    if not widgetsOk then
      g_logger.info('[lootburst] no tile overlay widgets or no pictures: the stock loot effects stay (the server is told)')
    end
  end
  return widgetsOk
end

-- ---------------------------------------------------------------- the server hears whether this client draws the burst
local function sendCapability()
  if not g_game.isOnline() then return end
  local gl = modules.game_groundlabels
  if gl and gl.sendAction then gl.sendAction('burst', LBL.capability(enabled, hasWidgets())) end
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

-- ---------------------------------------------------------------- widgets
-- a widget over a tile: w = the widget, pos = the tile's position, tile = the tile object it is on (re-attached when the engine
-- forgot it), key = the tile's counter key
local function tileOf(pos)
  return g_map.getTile(pos)
end

local function attach(e)
  local tile = tileOf(e.pos)
  if not tile then
    e.tile = nil
    return false
  end
  if not tile:hasOverlayWidget(e.w) then tile:addOverlayWidget(e.w) end
  e.tile = tile
  return true
end

local function detach(e)
  if not e then return end
  if alive(e.w) then
    if e.tile then pcall(e.tile.removeOverlayWidget, e.tile, e.w) end
    e.w:destroy()
  end
  e.w = nil
  e.tile = nil
end

local function imageWidget(kind, tint)
  local w = g_ui.createWidget('UIWidget')
  w:setImageSource(LBL.artPath(kind))
  w:setImageSmooth(true)
  w:setPhantom(true)
  if tint then w:setImageColor(tint) end
  return w
end

-- places a widget: its picture `kind` at `scale`, its centre at (ox, oy) tiles from the centre of its tile (the size is kept so
-- a widget that did not change size is not resized)
local function place(e, tw, th, scale, ox, oy)
  local width, height = LBL.size(e.kind, scale, tw, th)
  if e.sw ~= width or e.sh ~= height then
    e.sw, e.sh = width, height
    e.w:resize(width, height)
  end
  local ml, mt = LBL.margins(tw, th, ox, oy)
  if e.ml ~= ml then e.ml = ml e.w:setMarginLeft(ml) end
  if e.mt ~= mt then e.mt = mt e.w:setMarginTop(mt) end
end

local function newImage(burst, kind, pos, tint)
  local key = LBL.posKey(pos)
  burst.counts[key] = (burst.counts[key] or 0) + 1
  return { w = imageWidget(kind, tint), kind = kind, pos = pos, key = key }
end

local function release(burst, e)
  if e and e.key and burst.counts[e.key] then burst.counts[e.key] = math.max(0, burst.counts[e.key] - 1) end
  detach(e)
end

-- ---------------------------------------------------------------- a burst
local function dropBurst(b)
  for _, run in ipairs(b.runs) do
    release(b, run.item)
    release(b, run.shadow)
    for _, g in ipairs(run.trail) do release(b, g) end
  end
  for _, e in ipairs(b.fx) do release(b, e) end
  b.runs, b.fx = {}, {}
end

local function clearAll()
  for _, b in ipairs(bursts) do dropBurst(b) end
  bursts = {}
  if tickEvent then
    removeEvent(tickEvent)
    tickEvent = nil
  end
end

-- a one-shot effect (flash, dust, ring) that plays its strip once from `at` ms of the burst's clock
local function addEffect(b, kind, pos, at, ox, oy, scale, tint, opacity)
  if not LBL.canAdd(b.counts, LBL.posKey(pos), true) then return end
  local e = newImage(b, kind, pos, tint)
  e.at, e.ox, e.oy, e.scale = at, ox or 0, oy or 0, scale or 1
  if opacity then e.w:setOpacity(opacity) end
  e.w:setImageClip(LBL.clip(kind, 0))
  b.fx[#b.fx + 1] = e
  local tw, th = tileSize()
  place(e, tw, th, e.scale, e.ox, e.oy)
  attach(e)
end

local function startRun(b, f)
  local run = { f = f, trail = {}, started = true }
  local item = { pos = b.data.origin, key = LBL.posKey(b.data.origin), kind = 'item' }
  local w = g_ui.createWidget('UIItem')
  w:setVirtual(true)
  w:setPhantom(true)
  w:setItemId(f.id)
  w:setItemCount(f.count)
  if w.setShowCount then w:setShowCount(false) end
  item.w = w
  b.counts[item.key] = (b.counts[item.key] or 0) + 1
  run.item = item
  -- the shadow and the trail lie over the landing tile (the death tile holds the items of a whole burst; the engine keeps 16 per tile)
  if LBL.canAdd(b.counts, LBL.posKey(f.to), false) then run.shadow = newImage(b, 'shadow', f.to) end
  b.runs[#b.runs + 1] = run
  return run
end

local function placeItem(run, tw, th, pose)
  local e = run.item
  local width, height = tw * pose.scale, th * pose.scale
  width, height = math.floor(width + 0.5), math.floor(height + 0.5)
  if e.sw ~= width or e.sh ~= height then
    e.sw, e.sh = width, height
    e.w:resize(width, height)
  end
  local ml, mt = LBL.margins(tw, th, pose.x, pose.y)
  if e.ml ~= ml then e.ml = ml e.w:setMarginLeft(ml) end
  if e.mt ~= mt then e.mt = mt e.w:setMarginTop(mt) end
  if not e.tile or not e.tile:hasOverlayWidget(e.w) then attach(e) end
end

-- the shadow lies on the ground under the item, 0.3 tile below its centre (the item's feet), over the landing tile
local function placeShadow(run, tw, th, pose)
  local e = run.shadow
  if not e or not alive(e.w) then return end
  local f = run.f
  e.w:setOpacity(math.max(0, math.min(1, pose.shadow.alpha / 0.62)))
  place(e, tw, th, pose.shadow.scale, pose.gx - f.dx, pose.gy - f.dy + 0.3)
  if not e.tile or not e.tile:hasOverlayWidget(e.w) then attach(e) end
end

-- the glows behind a flying item (a few widgets over the landing tile, created once and moved)
local function placeTrail(b, run, tw, th, age)
  local f = run.f
  local points = LBL.trail(f, age)
  local color = LBL.COLORS[f.group]
  for i, p in ipairs(points) do
    local g = run.trail[i]
    if not g then
      if not LBL.canAdd(b.counts, LBL.posKey(f.to), true) then break end
      g = newImage(b, 'glow', f.to, color)
      run.trail[i] = g
    end
    if alive(g.w) then
      g.w:setOpacity(math.max(0, math.min(1, p.alpha)))
      place(g, tw, th, p.size, p.x - f.dx, p.y - f.dy)
      if not g.tile or not g.tile:hasOverlayWidget(g.w) then attach(g) end
    end
  end
  for i = #points + 1, #run.trail do
    local g = run.trail[i]
    if g and alive(g.w) then g.w:setOpacity(0) end
  end
end

local function finishRun(b, run)
  release(b, run.item)
  release(b, run.shadow)
  for _, g in ipairs(run.trail) do release(b, g) end
  run.trail = {}
  run.item, run.shadow = nil, nil
  run.done = true
end

-- the landing: a dust puff on the landing tile and, for a group item, a ring in its colour
local function land(b, run, age)
  local f = run.f
  local l = LBL.landing(f)
  addEffect(b, 'dust', f.to, f.landAt, 0, 0.12, l.dust)
  if l.ring then addEffect(b, 'ring', f.to, f.landAt, 0, 0.28, l.ring.size, l.ring.color) end
  run.landed = true
end

local function stepBurst(b, now, tw, th)
  local age = now - b.t0
  -- the flashes
  for _, fl in ipairs(b.flashPlan) do
    if not fl.fired and age >= fl.at then
      fl.fired = true
      addEffect(b, 'flash', b.data.origin, age, 0, 0, fl.size, fl.tint)
    end
  end
  -- the flights
  for _, f in ipairs(b.data.flights) do
    local run = b.byFlight[f]
    if not run and age >= f.d and age < f.endAt then run = startRun(b, f) b.byFlight[f] = run end
    if run and not run.done then
      local pose = LBL.pose(f, age)
      if pose.phase == 'done' then
        finishRun(b, run)
      else
        if alive(run.item.w) then
          placeItem(run, tw, th, pose)
          placeShadow(run, tw, th, pose)
          if pose.phase == 'fly' then placeTrail(b, run, tw, th, age) end
        end
        if age >= f.landAt and not run.landed then land(b, run, age) end
      end
    end
  end
  -- the one-shot effects: the frame by age, gone when played out
  for i = #b.fx, 1, -1 do
    local e = b.fx[i]
    local frame = LBL.frame(e.kind, age - e.at)
    if frame == nil or not alive(e.w) then
      release(b, e)
      table.remove(b.fx, i)
    else
      if e.frame ~= frame then
        e.frame = frame
        e.w:setImageClip(LBL.clip(e.kind, frame))
      end
      place(e, tw, th, e.scale, e.ox, e.oy)
      if not e.tile or not e.tile:hasOverlayWidget(e.w) then attach(e) end
    end
  end
  -- on while a flight or an effect may still come (endMs is the last flight's end and the grace of its landing effects)
  return age < b.data.endMs or #b.fx > 0
end

local function tick()
  tickEvent = nil
  local player = g_game.isOnline() and g_game.getLocalPlayer()
  local ppos = player and player:getPosition()
  if not ppos then
    clearAll()
    return
  end
  local now = nowMs()
  local tw, th = tileSize()
  for i = #bursts, 1, -1 do
    local b = bursts[i]
    local keep = true
    if ppos.z ~= b.data.origin.z or now - b.t0 > b.data.endMs + LBL.SAFETY_MS then
      keep = false -- another floor, or a burst that should have ended long ago
    else
      local ok, more = pcall(stepBurst, b, now, tw, th)
      if not ok then
        if not reported.step then
          reported.step = true
          g_logger.warning('[lootburst] step: ' .. tostring(more))
        end
        keep = false
      else
        keep = more
      end
    end
    if not keep then
      dropBurst(b)
      table.remove(bursts, i)
    end
  end
  if #bursts > 0 then tickEvent = scheduleEvent(safe('tick', tick), LBL.TICK_MS) end
end

local function schedule()
  if not tickEvent then tickEvent = scheduleEvent(safe('tick', tick), LBL.TICK_MS) end
end

-- the server's "explode" message (game_groundlabels forwards it)
function onExplode(data)
  if not enabled or not hasWidgets() or not g_game.isOnline() then return end
  local parsed = LBL.parse(data)
  if not parsed then return end
  local player = g_game.getLocalPlayer()
  local ppos = player and player:getPosition()
  if not ppos or ppos.z ~= parsed.origin.z then return end
  while #bursts >= 4 do -- a big pull: the oldest bursts end at once (their items are on the ground by now or about to be)
    dropBurst(bursts[1])
    table.remove(bursts, 1)
  end
  bursts[#bursts + 1] = {
    t0 = nowMs(), data = parsed, runs = {}, fx = {}, counts = {}, byFlight = {}, flashPlan = LBL.flashes(parsed),
  }
  local tw, th = tileSize()
  local b = bursts[#bursts]
  pcall(stepBurst, b, b.t0, tw, th) -- the first flash and the first item at once, not 30 ms later
  schedule()
end

-- ---------------------------------------------------------------- settings (the checkbox is in the Ground Labels window)
function setEnabled(on)
  on = on and true or false
  if on == enabled then return end
  enabled = on
  if not enabled then clearAll() end
  sendCapability()
end

function isEnabled()
  return enabled
end

-- for the terminal and the tests: how many bursts and widgets are on
function getStats()
  local widgets, fx = 0, 0
  for _, b in ipairs(bursts) do
    for _, run in ipairs(b.runs) do
      if run.item and alive(run.item.w) then widgets = widgets + 1 end
      if run.shadow and alive(run.shadow.w) then widgets = widgets + 1 end
      for _, g in ipairs(run.trail) do if alive(g.w) then widgets = widgets + 1 end end
    end
    for _, e in ipairs(b.fx) do if alive(e.w) then fx = fx + 1 end end
  end
  return { bursts = #bursts, widgets = widgets, effects = fx, enabled = enabled, capable = hasWidgets(), running = tickEvent ~= nil }
end

-- ---------------------------------------------------------------- init
local function onGameStart()
  clearAll()
  if startEvent then removeEvent(startEvent) end
  -- the protocol takes a moment to accept extended opcodes after the game starts
  startEvent = scheduleEvent(safe('capability', function()
    startEvent = nil
    sendCapability()
  end), 800)
end

local function onGameEnd()
  clearAll()
end

local function onPositionChange(_, newPos, oldPos)
  if newPos and oldPos and newPos.z ~= oldPos.z then clearAll() end
end

function init()
  local gl = modules.game_groundlabels
  if gl and gl.getBurstSetting then enabled = gl.getBurstSetting() and true or false end
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  handlers.player = { onPositionChange = safe('move', onPositionChange) }
  connect(g_game, handlers.game)
  connect(LocalPlayer, handlers.player)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  clearAll()
  if startEvent then
    removeEvent(startEvent)
    startEvent = nil
  end
  disconnect(g_game, handlers.game)
  disconnect(LocalPlayer, handlers.player)
  -- the server gets its stock effects back
  if g_game.isOnline() then
    local gl = modules.game_groundlabels
    if gl and gl.sendAction then pcall(gl.sendAction, 'burst', { on = 0 }) end
  end
  handlers = {}
end
