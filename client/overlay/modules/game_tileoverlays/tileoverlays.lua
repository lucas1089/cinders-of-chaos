-- Tile overlays: seconds left over magic walls, wild growth and the other timed fields, and the progress bars the
-- server puts over map positions. The rules are in tileoverlayslogic.lua; the field table is fielddata.lua
-- (client/tools/gen_field_timers.py); the server side of the bars is data/scripts/chaos/tilebars.lua (extended opcode
-- 156, JSON {action, data}):
--   server -> client  bars {s = [{i, p = [x, y, z], n, c, v | l + t}], d = [ids]}     clear {}
--   client -> server  hello {}  (at every game start and when this module loads in game: send me everything again)
--
-- How it is drawn: every timer and every bar is a widget the engine draws over its tile (Tile:addOverlayWidget, client
-- base patch 0041), so it follows walking, map scrolling, zoom and floor changes like the ground loot labels, and it
-- takes no mouse input (tile widgets are not in the UI tree). Without the patch a tile's single widget slot
-- (Tile:setWidget) is used when it is free.
--
-- How a field timer starts: the engine calls Tile.onAddThing / onRemoveThing (g_game.enableTileThingLuaCallback, on
-- while the option is on). A field added on a tile that was already in view (judged from where the player stood
-- before the step that brought the tile in) appeared just now: its timer starts. One that came into view with its
-- tile shows "~". Option: Options > Interface "Field timers over magic walls and fields" (fieldTimers, base patch 0041).
local TL = TileOverlaysLogic
local FIELDS = TileOverlayFields or {}
local OPCODE = TL.OPCODE
local TICK_MS = 250

local fields = TL.newFields()
local bars = {}          -- bar id -> bar (tileoverlayslogic parseBar)
local entries = {}       -- 'f:' .. record key | 'b:' .. bar id -> {w, pos, tile, text, kind}
local lastMove           -- {at, old}: the local player's last step
local fieldsOn = true
local overlayApi = false -- the engine has Tile:addOverlayWidget (base patch 0041)
local seq = 0
local events, handlers = {}, {}
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[tileoverlays] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function nowMs()
  return g_clock.millis()
end

local function range()
  local s = g_map.getAwareRange and g_map.getAwareRange()
  return TL.rangeFromSize(s and s.width, s and s.height)
end

-- the size of a tile on screen (the map panel's size over its visible tiles; zoom and window size change it)
local function tileSize()
  local panel = modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
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

-- a widget's place over its tile: centred on the tile, lifted by `lift` px
local function place(e, lift, tw, th)
  local cx, cy = TL.centre(tw, th)
  local key = cx .. ',' .. (cy - lift)
  if e.place ~= key then
    e.place = key
    e.w:setMarginLeft(cx)
    e.w:setMarginTop(cy - lift)
  end
end

local function playerPos()
  local player = g_game.getLocalPlayer()
  return player and player:getPosition()
end

-- ---------------------------------------------------------------- widgets on tiles
local function attach(e)
  local tile = g_map.getTile(e.pos)
  if not tile then
    e.tile = nil
    return
  end
  if overlayApi then
    if not tile:hasOverlayWidget(e.w) then tile:addOverlayWidget(e.w) end
    e.tile = tile
  else
    local cur = tile:getWidget()
    if not cur then
      tile:setWidget(e.w)
      e.tile = tile
    elseif cur:getId() == e.w:getId() then
      e.tile = tile
    else
      e.tile = nil -- the slot holds another module's widget (a ground loot label): not drawn here
    end
  end
end

local function dropEntry(key)
  local e = entries[key]
  if not e then return end
  entries[key] = nil
  if e.tile then
    if overlayApi then
      pcall(e.tile.removeOverlayWidget, e.tile, e.w)
    else
      local cur = e.tile:getWidget()
      if cur and cur:getId() == e.w:getId() then
        e.tile:setWidget(nil)
      end
    end
  end
  if not e.w:isDestroyed() then e.w:destroy() end
end

local function newEntry(key, style, pos, kind)
  dropEntry(key)
  seq = seq + 1
  local w = g_ui.createWidget(style)
  w:setId('tileOverlay' .. seq)
  local e = { w = w, pos = { x = pos.x, y = pos.y, z = pos.z }, kind = kind }
  entries[key] = e
  return e
end

-- ---------------------------------------------------------------- field timers
local function drawField(rec, t, tw, th)
  local key = 'f:' .. rec.key
  local e = entries[key]
  if not e then
    e = newEntry(key, 'TileOverlayTimer', rec.pos, 'field')
  end
  local text = TL.fieldText(rec, t)
  if e.text ~= text then
    e.text = text
    e.w:setText(text)
    e.w:setColor(TL.fieldColor(rec, t))
    local size = e.w:getTextSize()
    e.w:resize(math.max(16, size.width + 6), 14)
  elseif text ~= TL.UNKNOWN then
    e.w:setColor(TL.fieldColor(rec, t))
  end
  if not tw then tw, th = tileSize() end
  place(e, 0, tw, th)
  attach(e)
end

local function dropField(rec)
  dropEntry('f:' .. rec.key)
end

local function clearFields()
  for key in pairs(entries) do
    if key:sub(1, 2) == 'f:' then dropEntry(key) end
  end
  fields = TL.newFields()
end

local function onAddThing(tile, thing)
  if not fieldsOn or not thing or not thing:isItem() then return end
  local id = thing:getId()
  if not FIELDS[id] then return end
  local pos = tile:getPosition()
  local t = nowMs()
  local ref = TL.refPos(playerPos(), lastMove, t)
  local rec = TL.fieldAdd(fields, pos, id, t, g_game.isOnline() and TL.isKnown(pos, ref, range()), FIELDS)
  if rec then drawField(rec, t) end
end

local function onRemoveThing(tile, thing)
  if not thing or not thing:isItem() then return end
  local id = thing:getId()
  if not FIELDS[id] then return end
  local rec = TL.fieldRemove(fields, tile:getPosition(), id, nowMs())
  if rec then dropField(rec) end
end

-- the fields already in view when the option is turned on: their start is unknown
local function scanView()
  local ppos = playerPos()
  if not ppos or not g_game.isOnline() then return end
  local r = range()
  local t = nowMs()
  for dy = -r.top, r.bottom do
    for dx = -r.left, r.right do
      local pos = { x = ppos.x + dx, y = ppos.y + dy, z = ppos.z }
      local tile = g_map.getTile(pos)
      if tile then
        for _, item in ipairs(tile:getItems() or {}) do
          local rec = TL.fieldAdd(fields, pos, item:getId(), t, false, FIELDS)
          if rec then drawField(rec, t) end
        end
      end
    end
  end
end

local function setFieldsOn(on)
  on = TL.isOn(on)
  fieldsOn = on
  if g_game.enableTileThingLuaCallback then g_game.enableTileThingLuaCallback(on) end
  clearFields()
  if on then scanView() end
end

-- ---------------------------------------------------------------- server bars
local function drawBar(bar, t, index, tw, th)
  local key = 'b:' .. bar.id
  local e = entries[key]
  if not e or TL.posKey(e.pos) ~= TL.posKey(bar.pos) then
    e = newEntry(key, 'TileOverlayBar', bar.pos, 'bar')
    e.label = e.w:getChildById('label')
    e.fill = e.w:recursiveGetChildById('fill')
  end
  if e.color ~= bar.color then
    e.color = bar.color
    e.fill:setBackgroundColor(bar.color)
  end
  if not tw then tw, th = tileSize() end
  place(e, TL.barLift(th, index), tw, th)
  local text = TL.barText(bar, t)
  if e.text ~= text then
    e.text = text
    e.label:setText(text)
    -- digits measured as 0s, so a countdown does not change the width every second
    local probe = text:gsub('%d', '0')
    e.label:setText(probe)
    local width = TL.barWidth(e.label:getTextSize().width)
    e.label:setText(text)
    if e.w:getWidth() ~= width then
      e.w:setWidth(width)
      e.fillW = nil
    end
  end
  local fw = TL.fillWidth(TL.barProgress(bar, t), e.w:getWidth() - 2)
  if e.fillW ~= fw then
    e.fillW = fw
    e.fill:setWidth(fw)
    e.fill:setVisible(fw > 0)
  end
  attach(e)
end

local function relayoutBarsAt(pos, t, tw, th)
  for _, s in ipairs(TL.stack(bars, pos)) do
    drawBar(bars[s.id], t, s.index, tw, th)
  end
end

local function clearBars()
  for key in pairs(entries) do
    if key:sub(1, 2) == 'b:' then dropEntry(key) end
  end
  bars = {}
end

local function onBars(data)
  local t = nowMs()
  local before = {}
  for _, id in ipairs(type(data) == 'table' and type(data.d) == 'table' and data.d or {}) do
    if type(id) == 'string' and bars[id] then before[#before + 1] = bars[id].pos end
  end
  local set, del = TL.applyBars(bars, data, t)
  for _, id in ipairs(del) do dropEntry('b:' .. id) end
  local touched = {}
  for _, pos in ipairs(before) do touched[TL.posKey(pos)] = pos end
  for _, id in ipairs(set) do touched[TL.posKey(bars[id].pos)] = bars[id].pos end
  for _, pos in pairs(touched) do relayoutBarsAt(pos, t) end
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then return end
  if msg.action == 'bars' then
    onBars(msg.data)
  elseif msg.action == 'clear' then
    clearBars()
  end
end

local function sendHello()
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, json.encode(TL.hello()))
  end
end

-- ---------------------------------------------------------------- the loop
local function tick()
  if not g_game.isOnline() then return end
  local t = nowMs()
  local ppos = playerPos()
  local tw, th = tileSize()
  if fieldsOn and ppos then
    for _, rec in ipairs(TL.fieldSweep(fields, t, ppos, range())) do dropField(rec) end
    for _, rec in pairs(fields.recs) do drawField(rec, t, tw, th) end
  end
  for _, id in ipairs(TL.expiredBars(bars, t)) do
    local pos = bars[id].pos
    bars[id] = nil
    dropEntry('b:' .. id)
    relayoutBarsAt(pos, t, tw, th)
  end
  local done = {}
  for _, bar in pairs(bars) do
    local k = TL.posKey(bar.pos)
    if not done[k] then
      done[k] = true
      relayoutBarsAt(bar.pos, t, tw, th)
    end
  end
end

local function option()
  local s = modules.client_settings
  local opts = s and s.GameOptions
  if not opts or not opts.getDataSet then return nil end
  local ok, data = pcall(opts.getDataSet, opts, TL.OPTION)
  if not ok or type(data) ~= 'table' then return nil end
  return data.value
end

-- called by the settings module (dataset.lua, base patch 0041) when "Field timers" changes
function onOptionChange(value)
  safe('option', setFieldsOn)(value)
end

local function onGameStart()
  clearFields()
  clearBars()
  lastMove = nil
  setFieldsOn(option())
  sendHello()
end

local function onGameEnd()
  clearFields()
  clearBars()
  lastMove = nil
end

local function onPositionChange(creature, newPos, oldPos)
  lastMove = { at = nowMs(), old = oldPos }
end

-- for other modules and the terminal: what is drawn {kind, pos, text}
function getOverlays()
  local out = {}
  for key, e in pairs(entries) do
    out[#out + 1] = { key = key, kind = e.kind, pos = e.pos, text = e.text, attached = e.tile ~= nil }
  end
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end

function getStats()
  local nf, nb = 0, 0
  for _ in pairs(fields.recs) do nf = nf + 1 end
  for _ in pairs(bars) do nb = nb + 1 end
  return { fields = nf, bars = nb, fieldsOn = fieldsOn, overlayApi = overlayApi,
    callback = g_game.isTileThingLuaCallbackEnabled and g_game.isTileThingLuaCallbackEnabled() or false }
end

function init()
  g_ui.importStyle('tileoverlays')
  overlayApi = type(Tile) == 'table' and Tile.addOverlayWidget ~= nil and Tile.hasOverlayWidget ~= nil
  if not overlayApi then
    g_logger.warning('[tileoverlays] the client has no Tile:addOverlayWidget (base patch 0041): using the tile widget slot')
  end
  handlers.tile = { onAddThing = safe('add', onAddThing), onRemoveThing = safe('remove', onRemoveThing) }
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  handlers.player = { onPositionChange = safe('move', onPositionChange) }
  handlers.opcode = safe('opcode', onExtendedOpcode)
  connect(Tile, handlers.tile)
  connect(g_game, handlers.game)
  connect(LocalPlayer, handlers.player)
  ProtocolGame.registerExtendedOpcode(OPCODE, handlers.opcode)
  events.tick = cycleEvent(safe('tick', tick), TICK_MS)
  setFieldsOn(option())
  if g_game.isOnline() then addEvent(sendHello) end
end

function terminate()
  for k, e in pairs(events) do
    removeEvent(e)
    events[k] = nil
  end
  disconnect(Tile, handlers.tile)
  disconnect(g_game, handlers.game)
  disconnect(LocalPlayer, handlers.player)
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  if g_game.enableTileThingLuaCallback then g_game.enableTileThingLuaCallback(false) end
  clearFields()
  clearBars()
  handlers = {}
end
