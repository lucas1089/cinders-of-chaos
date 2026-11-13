-- game_minimapdots: the minimap radar. The server (radar.lua) sends the monsters, NPCs and party members within the radius of
-- the player as an action `radar` of extended opcode 153 (game_mapmarkers owns the opcode and passes the message on to
-- onRadar); this module draws a dot for each on the minimap widget, at every zoom: red for a monster, a bigger one with a gold
-- ring for a boss, blue for an NPC, green for a party member, white for you. At 1 px per tile a dot is 2 x 2 px so a pack does
-- not hide the map; from 2 px per tile up it grows with the zoom (MinimapDotsLogic.style).
-- The option "Monsters on the minimap" (Options > Graphics, dataset `minimapRadar`, default on) switches it; the client asks the
-- server for the list only while the option is on, the minimap window is shown and the player is online, and tells the server
-- when that changes. The dots follow the smooth scroll of the map (base patch 0197) while the player walks.
-- Protocol: server/data/scripts/chaos/radar.lua. Nothing is drawn without a list from the server.
local L = MinimapDotsLogic

local minimap, layer
local pool = {}
local state            -- the last list: {z, r, dots, at}
local optionOn = true
local sentOn = false
local checkEvent, walkEvent, attachEvent
local handlers = {}

local function alive(w)
  return w and not w:isDestroyed()
end

local function setting()
  local cs = modules.client_settings
  if not (cs and cs.getOption) then return nil end
  local ok, value = pcall(cs.getOption, L.OPTION)
  if ok then return value end
  return nil
end

local function send(on)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(L.OPCODE, json.encode({ action = 'radar', data = { on = on } }))
    sentOn = on
  end
end

local function windowVisible()
  if not alive(minimap) then return false end
  local window = modules.game_minimap and modules.game_minimap.minimapWindow
  if window and not window:isDestroyed() and not window:isVisible() then return false end
  return minimap:isVisible()
end

-- ---------------------------------------------------------------- drawing
local function dotWidget(i)
  local w = pool[i]
  if not alive(w) then
    w = g_ui.createWidget('MinimapDot', layer)
    pool[i] = w
  end
  return w
end

local function hideFrom(i)
  for k = i, #pool do
    if alive(pool[k]) then pool[k]:hide() end
  end
end

local function style(w, kind, scale)
  local st = L.style(kind, scale)
  local key = kind .. ':' .. st.size
  if w.styleKey ~= key then
    w:setSize({ width = st.size, height = st.size })
    w:setBackgroundColor(st.fill)
    w:setBorderWidth(st.ring)
    w:setBorderColor(st.edge)
    w.styleKey = key
  end
  return st
end

local function place()
  if not alive(minimap) or not alive(layer) then return end
  local cam = minimap:getCameraPosition()
  if not optionOn or not g_game.isOnline() or not windowVisible() or not cam then
    hideFrom(1)
    return
  end
  local scale = minimap:getScale()
  local rect = minimap.getPaddingRect and minimap:getPaddingRect() or minimap:getRect()
  local shown = 0
  local function put(kind, x, y)
    local pt = minimap:getTilePoint({ x = x, y = y, z = cam.z })
    if not pt or (pt.x == -1 and pt.y == -1) then return end
    if kind == 'self' and minimap.getSubTileX then
      -- the map glides through a step (base patch 0197) and so does your sprite: your dot stays where the camera is
      pt = { x = pt.x + math.floor(minimap:getSubTileX() * scale + 0.5), y = pt.y + math.floor(minimap:getSubTileY() * scale + 0.5) }
    end
    if not L.inside(pt.x, pt.y, rect, 6) then return end
    shown = shown + 1
    local w = dotWidget(shown)
    local st = style(w, kind, scale)
    local cx, cy = L.corner(pt.x, pt.y, st.size)
    w:setPosition({ x = cx, y = cy })
    w:show()
  end
  local fresh = L.fresh(state, cam.z, g_clock.millis())
  for _, kind in ipairs(L.DRAW_ORDER) do
    if kind == 'self' then
      local me = g_game.getLocalPlayer()
      local p = me and me:getPosition()
      if p then put('self', p.x, p.y) end
    elseif fresh and L.shows(kind, nil) then
      for _, d in ipairs(state.dots) do
        if d.kind == kind then put(kind, d.x, d.y) end
      end
    end
  end
  hideFrom(shown + 1)
end

local function clear()
  state = nil
  hideFrom(1)
end

-- ---------------------------------------------------------------- server
-- called by game_mapmarkers for the action `radar`
function onRadar(data)
  local list = L.decode(data)
  if not list then return end
  list.at = g_clock.millis()
  state = list
  place()
end

-- the radar should be on when the option, the window and the connection say so; tell the server when that changes
local function check()
  local want = L.wantRadar(optionOn, windowVisible(), g_game.isOnline())
  if want ~= sentOn then
    send(want)
    if not want then clear() end
  end
  place()
end

-- the settings module calls this when the value is applied (dataset.lua, base patch 0197)
function onOption(value)
  optionOn = L.isOn(value)
  check()
end

-- ---------------------------------------------------------------- attaching
local function onView()
  place()
end

local function detach()
  if alive(minimap) then
    disconnect(minimap, { onCameraPositionChange = onView, onZoomChange = onView, onGeometryChange = onView })
  end
  if alive(layer) then layer:destroy() end
  layer, minimap, pool = nil, nil, {}
end

local function attach()
  local mm = modules.game_minimap and modules.game_minimap.minimapWidget
  if not mm or mm:isDestroyed() then return false end
  if mm == minimap and alive(layer) then return true end
  detach()
  minimap = mm
  layer = g_ui.createWidget('MinimapDotLayer')
  minimap:insertChild(1, layer)
  layer:fill('parent')
  connect(minimap, { onCameraPositionChange = onView, onZoomChange = onView, onGeometryChange = onView })
  place()
  return true
end

local function ensureAttached()
  if attachEvent then removeEvent(attachEvent) attachEvent = nil end
  if attach() then return end
  local tries = 0
  attachEvent = cycleEvent(function()
    tries = tries + 1
    if attach() or tries >= 30 then
      removeEvent(attachEvent)
      attachEvent = nil
    end
  end, 500)
end

local function safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then g_logger.warning('[minimapdots] ' .. name .. ': ' .. tostring(err)) end
  end
end

local function onGameStart()
  sentOn = false
  state = nil
  ensureAttached()
  if checkEvent then removeEvent(checkEvent) end
  checkEvent = cycleEvent(safe('check', check), L.CHECK_MS)
  if walkEvent then removeEvent(walkEvent) end
  -- while the player walks the map scrolls smoothly: the dots follow it
  walkEvent = cycleEvent(safe('walk', function()
    local me = g_game.getLocalPlayer()
    if me and me:isWalking() then place() end
  end), L.WALK_MS)
  scheduleEvent(safe('first', check), 800)
end

local function onGameEnd()
  if checkEvent then removeEvent(checkEvent) checkEvent = nil end
  if walkEvent then removeEvent(walkEvent) walkEvent = nil end
  sentOn = false
  clear()
end

function init()
  optionOn = L.isOn(setting())
  g_ui.importStyle('minimapdots')
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  handlers.player = { onPositionChange = safe('move', place) }
  connect(g_game, handlers.game)
  connect(LocalPlayer, handlers.player)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game or {})
  disconnect(LocalPlayer, handlers.player or {})
  if g_game.isOnline() and sentOn then send(false) end
  if checkEvent then removeEvent(checkEvent) checkEvent = nil end
  if walkEvent then removeEvent(walkEvent) walkEvent = nil end
  if attachEvent then removeEvent(attachEvent) attachEvent = nil end
  detach()
  handlers, state = {}, nil
end
