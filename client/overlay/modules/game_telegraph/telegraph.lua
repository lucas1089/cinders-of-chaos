-- game_telegraph (O549; client/MANIFEST.md "Floor telegraphs (O549)"): Lua only, no engine patch of its own.
-- Boss attacks mark the floor: every tile of the attack's area gets a flat translucent fill and the outline of the whole area (only the
-- outer edges of the union of the tiles, not the edges between two marked tiles) a bright line, under the creatures. The fill brightens
-- a little in the last 0.4 s before the hit; the mark is gone at the hit, at the server's clear and at a safety expiry.
-- How: one floor widget per tile (Tile:setFloorWidget, base patch 0078: drawn with the ground effects, under creatures, items on top
-- and walls) with a background colour for the fill and a border on the sides that touch an unmarked tile for the line. A widget has
-- no picture, so there is no art to keep. A tile that already carries another module's floor widget (a footprint, a stain, an aura)
-- gives it up for the length of the mark and gets it back at the end (a danger mark is worth more than a stain).
-- Messages: the server (telegraph.lua) sends on the monster bar's opcode 125, which game_monsterbar owns and forwards the actions
-- `floor` and `floorclear` to onMessage() here; this module answers once with `floorhello` (at the game start and when it loads in a
-- game), and only when the engine has the floor widget: the server then leaves the sprite pulses of a telegraph to the players that
-- did not say hello, so a client without this module (or without the engine part) sees today's sprite marks exactly.
-- No option: it replaces marks that were always there. Unload the module to get the sprite marks back.
-- Rules: telegraph_logic.lua (telegraph_test.lua). Not run in a client.

local L = TelegraphLogic

local state = L.newState()
local cells = {}              -- 'x,y' -> {widget, tile, prev, x, y, z, color, mask, step, hitAt, width}
local layoutList = {}         -- the cells of the marks on the player's floor, from L.layout
local dirty = false           -- the marks changed: lay them out again
local animEvent
local sideApi                 -- true: the widget has a border per side; false: one border for all four sides
local lineWidth = nil         -- the line's width now, in map pixels
local lastFloor
local ticks = 0
local handlers = {}
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[telegraph] ' .. name .. ': ' .. tostring(res))
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
  return ok and tonumber(s) or 32
end

local function mapPanel()
  local gi = modules.game_interface
  return gi and gi.getMapPanel and gi.getMapPanel() or nil
end

local function hidden()
  return g_window ~= nil and g_window.isVisible ~= nil and not g_window.isVisible()
end

local function floorApi()
  return Tile ~= nil and type(Tile.setFloorWidget) == 'function' and type(Tile.getFloorWidget) == 'function'
end

local function localFloor()
  local me = g_game.getLocalPlayer()
  local pos = me and me:getPosition()
  return pos and pos.z or nil
end

-- the screen size of one tile: the map panel's width over the tiles it shows (the line's width follows the zoom)
local function tilePx()
  local panel = mapPanel()
  if not panel then return nil end
  local vd = panel:getVisibleDimension()
  local w = panel:getWidth()
  if vd and vd.width and vd.width > 0 and w and w > 0 then return w / vd.width end
  return nil
end

-- ---------------------------------------------------------------- one tile's widget
local function paint(cell)
  local w = cell.widget
  if not alive(w) then return end
  w:setBackgroundColor(L.fillColor(cell.color, cell.alpha))
  local line = L.lineColor(cell.color)
  local lw = cell.width
  local up, right, down, left = L.sides(cell.mask)
  if sideApi == nil then sideApi = type(w.setBorderWidthTop) == 'function' and type(w.setBorderColorTop) == 'function' end
  if sideApi then
    w:setBorderWidthTop(up and lw or 0)
    w:setBorderWidthRight(right and lw or 0)
    w:setBorderWidthBottom(down and lw or 0)
    w:setBorderWidthLeft(left and lw or 0)
    w:setBorderColorTop(line)
    w:setBorderColorRight(line)
    w:setBorderColorBottom(line)
    w:setBorderColorLeft(line)
  else
    -- an engine without a border per side: a line round every tile (the edges between two marked tiles show too)
    w:setBorderWidth(lw)
    w:setBorderColor(line)
  end
end

local function release(cell)
  local w, tile = cell.widget, cell.tile
  cell.widget = nil
  if not alive(w) then return end
  if tile and tile:getFloorWidget() == w then
    if alive(cell.prev) then
      tile:setFloorWidget(cell.prev) -- the footprint or stain that lay here comes back
      w:destroy()
    else
      tile:removeFloorWidget() -- destroys the widget
    end
  else
    w:destroy()
  end
  cell.prev = nil
end

-- the cell of a layout entry: made when it is not there (or its widget was lost: the engine destroys a tile's floor widget when the
-- tile leaves the screen, another module may have put its own), repainted when its mask, colour or the line's width changed
local function ensure(entry, z)
  local key = entry.x .. ',' .. entry.y
  local cell = cells[key]
  local tile = cell and cell.tile
  if cell and alive(cell.widget) and tile and tile:getFloorWidget() == cell.widget then
    if cell.mask ~= entry.mask or cell.color ~= entry.color or cell.width ~= lineWidth then
      cell.mask, cell.color, cell.width = entry.mask, entry.color, lineWidth
      paint(cell)
    end
    cell.hitAt = entry.hitAt
    return cell
  end
  if cell then
    release(cell)
    cells[key] = nil
  end
  tile = g_map.getTile({ x = entry.x, y = entry.y, z = z })
  if not tile then return nil end -- not seen yet: the next pass tries again
  local spr, ml, mt = L.box(spriteSize())
  local w = g_ui.createWidget('UIWidget')
  w:resize(spr, spr)
  w:setMarginLeft(ml)
  w:setMarginTop(mt)
  w:setPhantom(true)
  local prev = tile:getFloorWidget()
  cell = { widget = w, tile = tile, prev = (alive(prev) and prev) or nil, x = entry.x, y = entry.y, z = z, color = entry.color,
    mask = entry.mask, hitAt = entry.hitAt, width = lineWidth, alpha = L.FILL_ALPHA, step = L.alphaStep(L.FILL_ALPHA) }
  paint(cell)
  tile:setFloorWidget(w)
  cells[key] = cell
  return cell
end

local function releaseAll()
  for key, cell in pairs(cells) do
    release(cell)
    cells[key] = nil
  end
end

-- the widgets of the marks on the player's floor: every layout tile has one, the others are given back
local function sync()
  local z = localFloor()
  if not z or not floorApi() or hidden() then return end
  if dirty or z ~= lastFloor then
    layoutList = L.layout(state, z)
    dirty = false
    lastFloor = z
  end
  local px = tilePx()
  lineWidth = L.lineWidth(px, spriteSize())
  local want = {}
  for _, entry in ipairs(layoutList) do
    want[entry.x .. ',' .. entry.y] = true
    ensure(entry, z)
  end
  for key, cell in pairs(cells) do
    if not want[key] then
      release(cell)
      cells[key] = nil
    end
  end
end

-- ---------------------------------------------------------------- the timer
local function stopAnim()
  if animEvent then
    removeEvent(animEvent)
    animEvent = nil
  end
end

local function animate()
  local t = now()
  local gone = L.step(state, t)
  if #gone > 0 then dirty = true end
  ticks = ticks + 1
  -- the widgets are checked about every 300 ms (tiles that were not in view, widgets the engine took, the zoom); a change at once
  if dirty or ticks % 6 == 0 then sync() end
  for _, cell in pairs(cells) do
    local alpha = L.fillAlpha(cell.hitAt, t)
    local step = L.alphaStep(alpha)
    if step ~= cell.step and alive(cell.widget) then
      cell.step, cell.alpha = step, alpha
      cell.widget:setBackgroundColor(L.fillColor(cell.color, alpha))
    end
  end
  if L.count(state) == 0 then
    releaseAll()
    stopAnim()
  end
end

local function startAnim()
  if not animEvent then animEvent = cycleEvent(safe('anim', animate), 50) end
end

-- ---------------------------------------------------------------- the server's messages
local function onFloor(data)
  local area, why = L.parse(data, now())
  if not area then
    if not reported['parse'] then
      reported['parse'] = true
      g_logger.warning('[telegraph] a floor message was refused: ' .. tostring(why))
    end
    return
  end
  L.add(state, area)
  dirty = true
  sync()
  startAnim()
end

local function onClear(data)
  local id = L.parseClear(data)
  if not id then return end
  local gone = L.clear(state, id)
  if #gone > 0 then
    dirty = true
    sync()
    if L.count(state) == 0 then
      releaseAll()
      stopAnim()
    end
  end
end

-- game_monsterbar hands over the actions of its opcode that it does not know
local function onMessage(msg)
  if type(msg) ~= 'table' then return end
  if msg.action == 'floor' then
    onFloor(msg.data)
  elseif msg.action == 'floorclear' then
    onClear(msg.data)
  end
end

local function sendHello()
  if not floorApi() then
    if not reported['api'] then
      reported['api'] = true
      g_logger.warning('[telegraph] the client has no Tile:setFloorWidget (base patch 0078): no floor marks, the server keeps the sprite marks')
    end
    return
  end
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(L.OPCODE, json.encode(L.hello()))
  end
end

local function forgetAll()
  L.clear(state, 'all')
  dirty = true
  releaseAll()
  layoutList = {}
  stopAnim()
end

local function onGameStart()
  forgetAll()
  lastFloor = nil
  addEvent(safe('hello', sendHello))
end

local function onGameEnd()
  forgetAll()
end

-- the player changed floor or jumped: the marks of the old floor are not drawn (they stay in the state until their hit)
local function onPositionChange(creature, newPos, oldPos)
  if not creature or not creature:isLocalPlayer() then return end
  if newPos and oldPos and newPos.z ~= oldPos.z and L.count(state) > 0 then
    dirty = true
    sync()
  end
end

-- the same call a `floor` message makes, from the console: a circle of radius 2 and a cone round the local player for 3 s
-- (previewTelegraph() in the terminal; no server needed)
local function preview()
  local me = g_game.getLocalPlayer()
  local pos = me and me:getPosition()
  if not pos then return end
  local circle, cone = {}, {}
  for dx = -2, 2 do
    for dy = -2, 2 do
      if dx * dx + dy * dy <= 5 then circle[#circle + 1] = { dx + 2, dy + 2 } end
    end
  end
  for dx = 0, 4 do
    for dy = -math.floor(dx / 2), math.floor(dx / 2) do
      cone[#cone + 1] = { dx, dy + 2 }
    end
  end
  onMessage({ action = 'floor', data = { id = 'preview:circle', z = pos.z, x0 = pos.x - 5, y0 = pos.y - 2, t = circle, c = 'orange', ms = 3000 } })
  onMessage({ action = 'floor', data = { id = 'preview:cone', z = pos.z, x0 = pos.x + 1, y0 = pos.y - 2, t = cone, c = 'orange', ms = 3000 } })
end

local function getStats()
  local n = 0
  for _ in pairs(cells) do n = n + 1 end
  return { marks = L.count(state), widgets = n, floorApi = floorApi(), sideBorders = sideApi, lineWidth = lineWidth }
end

function init()
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  handlers.player = { onPositionChange = safe('move', onPositionChange) }
  connect(g_game, handlers.game)
  connect(LocalPlayer, handlers.player)
  _G.ChaosTelegraphClient = { onMessage = safe('message', onMessage), preview = safe('preview', preview), getStats = getStats }
  if g_game.isOnline() then addEvent(safe('hello', sendHello)) end
end

function terminate()
  disconnect(g_game, handlers.game)
  disconnect(LocalPlayer, handlers.player)
  forgetAll()
  if rawget(_G, 'ChaosTelegraphClient') then _G.ChaosTelegraphClient = nil end
  handlers = {}
end
