-- game_chestaura (O315; client/MANIFEST.md "Chest and Templar auras (O315)"): Lua only, no engine patch of its own.
--   chest auras    a looping picture on the floor under a chest, found by its client item id (ChestAuraLogic.CHESTS): the reward
--                  chest 38758 (gold, a sigil ring), the cursed chest 38642 (dark smoke), the Sealed Coffer 38657 (the big gold
--                  chest, golden smoke, 128 px, centred on its 2 x 2 footprint). A floor widget (Tile:setFloorWidget, base patch
--                  0078: under the chest, creatures and walls); the 12 frames switch by image-clip on one timer. There is no
--                  message: the client finds the chests itself.
--   foot aura      the Templar line's sigil under the feet of every Templar-line player the server names (a creature bottom widget,
--                  Creature:addBottomWidget: drawn under the outfit, follows the walk); 24 frames at 250 ms, a slow turn, in the
--                  line's tint.
--   range frame    a faint square on the floor over the aura's range (the Chebyshev square of radius `r` round the Templar, (2r + 1)
--                  tiles across): ONE floor widget per Templar, a nine-slice picture (image-border) sized to the square, hosted on the
--                  Templar's tile (or the nearest free tile when that one carries a footprint or a stain; the margins centre it), only
--                  while the Templar is in a party, seen by the Templar and its party members. The server decides who sees it (flag
--                  `p` of the message). It moves with the Templar by changing margins, a new widget only when the host changes.
-- The server (templar_combat.lua) sends extended opcode 118, JSON {action = 'sync', data = {t = [{i = creature id, l = line 1..3,
-- r = radius, p = 1 when the viewer is that Templar or shares its party and the Templar is in one}]}}, only when the list changed.
--
--   cursed monsters  (O341) the chest's own smoke ('cursed_smoke', 12 frames, 200 ms) under every monster of a Cursed Chest event the
--                  server names: a creature bottom widget like the foot aura, scaled to the outfit's width (Creature:getExactSize when the
--                  engine has it, else one tile). The server sends extended opcode 118, JSON {action = 'cursed', data = {c = [creature id]}}:
--                  the whole list the viewer sees, only when it changed, empty when the event ends. Gone with the creature, a floor change,
--                  the option off and the end of the game. The same option covers it.
-- How chests are found: the engine calls Tile.onAddThing / onRemoveThing (g_game.enableTileThingLuaCallback, shared with
-- game_tileoverlays and game_chaossound); the handler is one table lookup for an item and returns for everything else. A chest
-- is remembered by its position (a few entries), its widget exists only while it is inside the visible tiles of the player's
-- floor (plus one tile). Once a second the module checks the remembered chests (still there? still in view? widget alive?),
-- switches the callback on again if another module switched it off, and, when the engine has no such callback, scans the visible
-- tiles. Widgets go with the chest, a floor change, a window without focus, the option off and the end of the game.
-- Option: Options > Graphics "Auras on chests and Templars" (chestAuras, default on, base patch 0162 -> onOption).
-- Pictures: client/tools/gen_aura_art.py. Rules: chestaura_logic.lua (chestaura_test.lua). Not run in a client.

local L = ChestAuraLogic

local enabled = false         -- the option is on and a game is running
local hooked = false
local chests = {}             -- tile key -> {pos, id, def, widget, tile, shown}
local feet = {}               -- creature id -> {widget, creature, line, shown}
local frames = {}             -- templar id -> {widget, tile, host, line, radius}: the range frame of a Templar
local server = {}             -- the last list of the server: creature id -> {id, line, radius, party}
local cursed = {}             -- creature ids the server named as Cursed Chest monsters (O341): id -> true
local smoke = {}              -- creature id -> {widget, creature, shown}: the chest's smoke under a cursed monster
local animEvent, maintainEvent
local lastFloor
local myId
local ticks = 0
local handlers = {}
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[chestaura] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function now()
  return g_clock.millis()
end

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

local function spriteSize()
  local ok, s = pcall(function() return g_sprites.spriteSize() end)
  return ok and tonumber(s) or L.SPRITE
end

local function mapPanel()
  local gi = modules.game_interface
  return gi and gi.getMapPanel and gi.getMapPanel() or nil
end

local function hidden()
  return g_window ~= nil and g_window.isVisible ~= nil and not g_window.isVisible()
end

local function localPos()
  local me = g_game.getLocalPlayer()
  return me and me:getPosition() or nil
end

local function visibleDim()
  local panel = mapPanel()
  local vd = panel and panel:getVisibleDimension()
  if vd and vd.width > 0 and vd.height > 0 then return vd.width, vd.height end
  return 15, 11
end

local function floorApi()
  return Tile ~= nil and type(Tile.setFloorWidget) == 'function'
end

-- remove a floor widget the module put on a tile (the engine destroys it; a widget that is not on the tile any more is destroyed)
local function dropFloorWidget(w, tile)
  if not alive(w) then return end
  if tile and tile.getFloorWidget and tile:getFloorWidget() == w then
    tile:removeFloorWidget()
  else
    w:destroy()
  end
end

-- ---------------------------------------------------------------- the animation timer
local function stopAnim()
  if animEvent then
    removeEvent(animEvent)
    animEvent = nil
  end
end

local function animate()
  if hidden() then return end -- minimized: nothing is drawn, so nothing is updated
  local t = now()
  local cf = L.frameIndex(t, L.CHEST_FRAME_MS, L.CHEST_FRAMES)
  local ff = L.frameIndex(t, L.FOOT_FRAME_MS, L.FOOT_FRAMES)
  local any = false
  for _, c in pairs(chests) do
    if alive(c.widget) then
      any = true
      if c.shown ~= cf then
        c.widget:setImageClip(L.clip(cf, c.def.px))
        c.shown = cf
      end
    end
  end
  for id, f in pairs(smoke) do
    if alive(f.widget) then
      any = true
      if f.shown ~= cf then
        f.widget:setImageClip(L.clip(cf, L.FOOT_PX))
        f.shown = cf
      end
    else
      smoke[id] = nil
    end
  end
  for id, f in pairs(feet) do
    if alive(f.widget) then
      any = true
      if f.shown ~= ff then
        f.widget:setImageClip(L.clip(ff, L.FOOT_PX))
        f.shown = ff
      end
    else
      feet[id] = nil -- the engine cleared the creature's widgets (it left the screen)
    end
  end
  if not any then stopAnim() end
end

local function startAnim()
  if not animEvent then animEvent = cycleEvent(safe('anim', animate), 50) end
end

-- ---------------------------------------------------------------- range frame
local function dropFrame(tid)
  local f = frames[tid]
  frames[tid] = nil
  if f then dropFloorWidget(f.widget, f.tile) end
end

local function frameCount()
  local n = 0
  for _ in pairs(frames) do n = n + 1 end
  return n
end

-- one Templar's frame: made, moved or taken back (entry nil: take it back)
local function syncFrame(tid, entry, creature)
  local f = frames[tid]
  local mine = localPos()
  local tpos = entry and creature and not creature:isRemoved() and creature:getPosition() or nil
  if not (tpos and mine and floorApi() and L.showFrame(enabled, entry, tpos, mine)) then
    if f then dropFrame(tid) end
    return
  end
  local spr = spriteSize()
  local vw, vh = visibleDim()
  if f and (f.line ~= entry.line or f.radius ~= entry.radius or not alive(f.widget)) then
    dropFrame(tid)
    f = nil
  end
  if f then
    -- the host still carries our widget, is in view and is near the Templar: only the margins move (no new widget)
    local tile = g_map.getTile(f.host)
    if tile and tile:getFloorWidget() == f.widget and L.onScreen(f.host, mine, vw, vh, 0) and L.hostNear(f.host, tpos) then
      local _, ml, mt = L.frameBox(spr, entry.radius, tpos.x - f.host.x, tpos.y - f.host.y)
      f.widget:setMarginLeft(ml)
      f.widget:setMarginTop(mt)
      return
    end
    dropFrame(tid)
    f = nil
  end
  if frameCount() >= L.MAX_FRAMES then return end -- a crowd of Templars in one party: the frames already up stay, no more are begun
  local host = L.pickHost(tpos, function(p)
    if chests[L.tileKey(p)] then return false end -- a chest's own tile is kept for its aura
    local t = g_map.getTile(p)
    return t ~= nil and t:getFloorWidget() == nil and L.onScreen(p, mine, vw, vh, 0)
  end)
  if not host then return end
  local tile = g_map.getTile(host)
  local size, ml, mt = L.frameBox(spr, entry.radius, tpos.x - host.x, tpos.y - host.y)
  local w = g_ui.createWidget('UIWidget')
  w:setImageSource(L.framePath(entry.line))
  pcall(function() w:setImageBorder(L.FRAME_BORDER) end) -- a nine-slice: the corners stay, the edges stretch
  w:setImageSmooth(true)
  w:resize(size, size)
  w:setMarginLeft(ml)
  w:setMarginTop(mt)
  w:setPhantom(true)
  tile:setFloorWidget(w)
  frames[tid] = { widget = w, tile = tile, host = host, line = entry.line, radius = entry.radius }
end

-- ---------------------------------------------------------------- foot aura
local function dropFoot(id)
  local f = feet[id]
  feet[id] = nil
  if not f or not alive(f.widget) then return end
  local c = f.creature
  local mine = c and not c:isRemoved() and c:getBottomWidgets() or {}
  if c and #mine == 1 and mine[1] == f.widget then
    c:clearBottomWidgets() -- the only bottom widget is ours (removeBottomWidget of this engine is unsafe)
  else
    f.widget:setOpacity(0)
    f.widget:setImageSource('')
  end
end

local function ensureFoot(creature, entry)
  local id = entry.id
  local f = feet[id]
  if f and f.creature == creature and f.line == entry.line and alive(f.widget) then return end
  if f then dropFoot(id) end
  local size, dy = L.footBox(spriteSize())
  local w = g_ui.createWidget('UIWidget')
  w:setImageSource(L.footPath(entry.line))
  w:setImageClip(L.clip(L.frameIndex(now(), L.FOOT_FRAME_MS, L.FOOT_FRAMES), L.FOOT_PX))
  w:setImageSmooth(true)
  w:resize(size, size)
  pcall(function() w:setMarginTop(dy) end)
  w:setPhantom(true)
  creature:addBottomWidget(w)
  feet[id] = { widget = w, creature = creature, line = entry.line, shown = nil }
  startAnim()
end

-- ---------------------------------------------------------------- cursed chest monsters (O341)
local function dropSmoke(id)
  local f = smoke[id]
  smoke[id] = nil
  if not f or not alive(f.widget) then return end
  local c = f.creature
  local mine = c and not c:isRemoved() and c:getBottomWidgets() or {}
  if c and #mine == 1 and mine[1] == f.widget then
    c:clearBottomWidgets()
  else
    f.widget:setOpacity(0)
    f.widget:setImageSource('')
  end
end

-- tiles across of a creature, from the engine when it can tell (a pixel width), else one
local function creatureTiles(creature, spr)
  local ok, px = pcall(function() return creature:getExactSize() end)
  return L.cursedTiles(ok and px or nil, spr)
end

local function ensureSmoke(creature, id)
  local f = smoke[id]
  if f and f.creature == creature and alive(f.widget) then return end
  if f then dropSmoke(id) end
  local spr = spriteSize()
  local size, ml, mt = L.cursedBox(spr, creatureTiles(creature, spr))
  local w = g_ui.createWidget('UIWidget')
  w:setImageSource(L.chestPath(L.CURSED_ART))
  w:setImageClip(L.clip(L.frameIndex(now(), L.CHEST_FRAME_MS, L.CHEST_FRAMES), L.FOOT_PX))
  w:setImageSmooth(true)
  w:resize(size, size)
  pcall(function() w:setMarginLeft(ml) end)
  pcall(function() w:setMarginTop(mt) end)
  w:setPhantom(true)
  creature:addBottomWidget(w)
  smoke[id] = { widget = w, creature = creature, shown = nil }
  startAnim()
end

local function refreshCursed(id)
  local creature = cursed[id] and g_map.getCreatureById(id) or nil
  local visible = creature ~= nil and not creature:isRemoved()
  if L.showCursed(enabled, id, cursed, visible) then ensureSmoke(creature, id) else dropSmoke(id) end
end

-- the foot aura and the frame of one Templar-line player the server named
local function refreshTempar(id)
  local entry = server[id]
  local creature = entry and g_map.getCreatureById(id) or nil
  local visible = creature ~= nil and not creature:isRemoved()
  if L.showSigil(enabled, entry, visible) then ensureFoot(creature, entry) else dropFoot(id) end
  syncFrame(id, enabled and entry or nil, visible and creature or nil)
end

-- ---------------------------------------------------------------- chests
local function tileHasChest(tile, clientId)
  for _, item in ipairs(tile:getItems() or {}) do
    if item:getId() == clientId then return true end
  end
  return false
end

local function dropChestWidget(c)
  local w, tile = c.widget, c.tile
  c.widget, c.tile, c.shown = nil, nil, nil
  dropFloorWidget(w, tile)
end

local function placeChest(c)
  if alive(c.widget) then return end
  c.widget = nil
  if not floorApi() then return end
  local tile = g_map.getTile(c.pos)
  if not tile then return end
  if tile:getFloorWidget() ~= nil then return end -- a footprint, a stain or a range frame: tried again at the next check
  local size, ml, mt = L.chestBox(c.def, spriteSize())
  local w = g_ui.createWidget('UIWidget')
  w:setImageSource(L.chestPath(c.def.art))
  w:setImageClip(L.clip(L.frameIndex(now(), L.CHEST_FRAME_MS, L.CHEST_FRAMES), c.def.px))
  w:setImageSmooth(true)
  w:resize(size, size)
  w:setMarginLeft(ml)
  w:setMarginTop(mt)
  w:setPhantom(true)
  tile:setFloorWidget(w)
  c.widget, c.tile, c.shown = w, tile, nil
  startAnim()
end

local function rememberChest(pos, clientId)
  local def = L.chestOf(clientId)
  if not def then return nil end
  local key = L.tileKey(pos)
  local c = chests[key]
  if not c or c.id ~= clientId then
    if c then dropChestWidget(c) end
    c = { pos = { x = pos.x, y = pos.y, z = pos.z }, id = clientId, def = def }
    chests[key] = c
  end
  return c
end

local function onAddThing(tile, thing)
  if not enabled or not thing or not thing:isItem() then return end
  if not L.chestOf(thing:getId()) then return end
  local pos = tile:getPosition()
  local c = rememberChest(pos, thing:getId())
  local mine = localPos()
  if c and mine then
    local vw, vh = visibleDim()
    if L.onScreen(c.pos, mine, vw, vh) then placeChest(c) end
  end
end

local function onRemoveThing(tile, thing)
  if not thing or not thing:isItem() then return end
  if not L.chestOf(thing:getId()) then return end
  local key = L.tileKey(tile:getPosition())
  local c = chests[key]
  if c and c.id == thing:getId() then
    dropChestWidget(c)
    chests[key] = nil
  end
end

-- the chests among the tiles in view (at start, after a floor change, and every second when the engine has no tile callback)
local function scanView()
  local mine = localPos()
  if not mine then return end
  local vw, vh = visibleDim()
  local rx, ry = math.floor(vw / 2) + L.VIEW_MARGIN, math.floor(vh / 2) + L.VIEW_MARGIN
  for dy = -ry, ry do
    for dx = -rx, rx do
      local tile = g_map.getTile({ x = mine.x + dx, y = mine.y + dy, z = mine.z })
      if tile then
        for _, item in ipairs(tile:getItems() or {}) do
          if L.chestOf(item:getId()) then rememberChest(tile:getPosition(), item:getId()) end
        end
      end
    end
  end
end

local function maintainChests()
  local mine = localPos()
  if not mine then return end
  local vw, vh = visibleDim()
  for key, c in pairs(chests) do
    local tile = g_map.getTile(c.pos)
    if not tile or not tileHasChest(tile, c.id) then
      dropChestWidget(c)
      chests[key] = nil
    elseif L.onScreen(c.pos, mine, vw, vh) then
      placeChest(c)
    else
      dropChestWidget(c)
    end
  end
end

-- ---------------------------------------------------------------- the check, once a second
-- true while the engine reports tile things to Lua (without the getter: whenever the engine has the switch at all)
local function callbackOn()
  if g_game.isTileThingLuaCallbackEnabled then return g_game.isTileThingLuaCallbackEnabled() == true end
  return g_game.enableTileThingLuaCallback ~= nil
end

local function enableCallback()
  if not g_game.enableTileThingLuaCallback then return false end
  if not g_game.isTileThingLuaCallbackEnabled or not callbackOn() then g_game.enableTileThingLuaCallback(true) end
  return true
end

local function maintain()
  if not enabled or not g_game.isOnline() or hidden() then return end
  ticks = ticks + 1
  -- another module may have switched the shared tile callback off: switch it on again and catch up by scanning once
  if not enableCallback() or not callbackOn() then
    scanView()
  elseif ticks % 15 == 0 then
    scanView() -- a slow safety net for a thing the callback missed
  end
  maintainChests()
  for id in pairs(server) do refreshTempar(id) end
  for id in pairs(frames) do
    if not server[id] then dropFrame(id) end
  end
  for id in pairs(cursed) do refreshCursed(id) end
  for id in pairs(smoke) do
    if not cursed[id] then dropSmoke(id) end
  end
end

-- ---------------------------------------------------------------- all at once
local function dropAll()
  stopAnim()
  for key, c in pairs(chests) do dropChestWidget(c) end
  for id in pairs(feet) do dropFoot(id) end
  for id in pairs(frames) do dropFrame(id) end
  for id in pairs(smoke) do dropSmoke(id) end
end

local function forgetAll()
  dropAll()
  chests = {}
  server = {}
  cursed = {}
  lastFloor = nil
  myId = nil
end

-- ---------------------------------------------------------------- hooks
local function onAppear(creature)
  local id = creature:getId()
  if enabled and server[id] then refreshTempar(id) end
  if enabled and cursed[id] then refreshCursed(id) end
end

local function onDisappear(creature)
  local id = creature:getId()
  if feet[id] or frames[id] then
    dropFoot(id)
    dropFrame(id)
  end
  if smoke[id] then dropSmoke(id) end
end

local function onPositionChange(creature, newPos, oldPos)
  if not enabled or not newPos then return end
  local id = creature:getId()
  if id == myId then
    if lastFloor ~= nil and newPos.z ~= lastFloor then
      -- another floor: the widgets of the old one are gone with their tiles; the new floor's chests are found at once
      dropAll()
      scanView()
      maintainChests()
      for tid in pairs(server) do refreshTempar(tid) end
      for cid in pairs(cursed) do refreshCursed(cid) end
    else
      maintainChests()
      for tid, e in pairs(server) do
        if e.party then refreshTempar(tid) end -- the frame is only for the floor of the viewer
      end
    end
    lastFloor = newPos.z
    return
  end
  local e = server[id]
  if e and e.party then syncFrame(id, e, creature) end -- the frame follows its Templar
end

local function onCursed(list)
  local old = cursed
  cursed = list
  if not enabled then return end
  for id in pairs(old) do
    if not list[id] then dropSmoke(id) end
  end
  for id in pairs(list) do refreshCursed(id) end
end

local function onSync(_, _, msg)
  local cl = L.parseCursed(msg)
  if cl then return onCursed(cl) end
  local list = L.parseSync(msg)
  if not list then return end
  local diff = L.syncDiff(server, list)
  server = list
  if not enabled then return end
  for _, id in ipairs(diff.removed) do
    dropFoot(id)
    dropFrame(id)
  end
  for _, id in ipairs(diff.added) do refreshTempar(id) end
  for _, id in ipairs(diff.changed) do refreshTempar(id) end
end

local function hook()
  if hooked then return end
  hooked = true
  connect(Tile, handlers.tile)
  connect(Creature, handlers.creature)
end

local function unhook()
  if not hooked then return end
  hooked = false
  disconnect(Tile, handlers.tile)
  disconnect(Creature, handlers.creature)
end

-- ---------------------------------------------------------------- option
local function optionValue()
  local cs = modules.client_settings
  local ok, v = pcall(function() return cs and cs.getOption and cs.getOption('chestAuras') end)
  return L.optionOn(ok and v or nil)
end

local function start()
  if enabled or not g_game.isOnline() then return end
  enabled = true
  hook()
  enableCallback()
  local mine = localPos()
  local me = g_game.getLocalPlayer()
  myId = me and me:getId() or nil
  lastFloor = mine and mine.z or nil
  scanView()
  maintainChests()
  for id in pairs(server) do refreshTempar(id) end
  for id in pairs(cursed) do refreshCursed(id) end
  if not maintainEvent then maintainEvent = cycleEvent(safe('maintain', maintain), 1000) end
end

local function stop()
  enabled = false
  if maintainEvent then
    removeEvent(maintainEvent)
    maintainEvent = nil
  end
  unhook()
  dropAll()
  chests = {}
end

-- from the options' apply (client_settings dataset.lua, base patch 0162)
function onOption(name, value)
  if name ~= 'chestAuras' then return end
  if L.optionOn(value) then start() else stop() end
end

local function onGameStart()
  forgetAll()
  enabled = false
  if optionValue() then start() end
end

local function onGameEnd()
  stop()
  forgetAll()
end

function getStats()
  local nc, nf, ns, nm = 0, 0, 0, 0
  for _ in pairs(chests) do nc = nc + 1 end
  for _ in pairs(feet) do nf = nf + 1 end
  for _ in pairs(server) do ns = ns + 1 end
  for _ in pairs(smoke) do nm = nm + 1 end
  return { enabled = enabled, chests = nc, feet = nf, frames = frameCount(), templars = ns, smoke = nm, floorApi = floorApi(), callback = callbackOn() }
end

function init()
  handlers.tile = { onAddThing = safe('add', onAddThing), onRemoveThing = safe('remove', onRemoveThing) }
  handlers.creature = { onAppear = safe('appear', onAppear), onDisappear = safe('disappear', onDisappear),
    onPositionChange = safe('position', onPositionChange) }
  ProtocolGame.registerExtendedJSONOpcode(L.OPCODE, safe('opcode', onSync))
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, L.OPCODE)
  stop()
  forgetAll()
  handlers = {}
end
