-- Map markers: the other party members and the points of interest on the minimap and on the full map (the same
-- minimap widget, Ctrl+Shift+M).
--
-- * Party members (server partymarkers.lua): a pin in the member's party colour; an up / down triangle when the member
--   is on another floor than the one shown; outside the shown part of the map the pin becomes an arrow on the edge,
--   pointing toward the member. Hover: name, health, floor and distance. The server sends a list when something
--   changed (about once a second at most); the pins glide to their new place in MapMarkerMath.ANIM_MS.
-- * Points of interest (server poi.lua): temples, depots, banks, the Chaos NPCs, shops, travel, crafting, the guild
--   hall, entrances and portals, dungeons, boss places, hunting areas. Some are always known, the others appear once
--   the character came near them ("Discovered on your map: ..."). Hover: the name.
-- * Game view (settings.game): a party member on this floor outside the visible game area gets a coloured arrow on the
--   edge of the game map panel with the name and the distance in tiles (MapMarkerMath.gameIndicator). Nothing for a
--   member in view or on another floor. Refreshed on a party update and on the player's step, every 150 ms at most.
-- * Settings (g_settings node 'mapMarkers'; window from the top menu, "Map Markers"): party members on / off, arrows on the game view on / off, points of
--   interest on / off, one check box per category. Turning a kind off on the client also tells the server, which then
--   stops sending it.
-- The markers sit in one layer inside the minimap widget and never take the mouse: clicks, drags and the wheel stay the
-- minimap's own. The hover text comes from a hit test in the minimap's mouse move (MapMarkerMath.hit).
-- Protocol: extended opcode 153, JSON {action, data}; see the server scripts.

local M = MapMarkerMath
local ICONS = M.ICONS
local POI_SIZE, PIN_SIZE = 14, 12
local MAX_POI = 160
local ANIM_TICK_MS = 40

local settings
local minimap, layer
local party = {}       -- member id -> {e = entry, anim, widget, slot}
local slots = {}
local pois, floors = {}, {}
local poiPool = {}
local hitList = {}
local hoverText
local animEvent, attachEvent
local settingsWindow
local mapPanel, gameLayer, gamePool = nil, nil, {}
local gameLast, gameEvent = 0, nil
local handlers = {}

-- ---------------------------------------------------------------- settings and server
local function loadSettings()
  settings = M.sanitize(g_settings.getNode('mapMarkers'))
end

local function saveSettings()
  g_settings.setNode('mapMarkers', settings)
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(M.OPCODE, json.encode({ action = action, data = data }))
  end
end

local function myPosition()
  local p = g_game.getLocalPlayer()
  return p and p:getPosition() or nil
end

local function myId()
  local p = g_game.getLocalPlayer()
  return p and p:getId() or 0
end

-- ---------------------------------------------------------------- drawing
local function alive(w)
  return w and not w:isDestroyed()
end

local function minimapRect()
  if minimap.getPaddingRect then return minimap:getPaddingRect() end
  return minimap:getRect()
end

local function poiWidget(i)
  local w = poiPool[i]
  if not w then
    w = g_ui.createWidget('MapMarkerPoi', layer)
    w:lower() -- under the party members
    poiPool[i] = w
  end
  return w
end

-- the minimap window's own controls over the map (not in the full map view)
local function controlRects()
  local out = {}
  local parent = minimap:getParent()
  if not parent or parent:getId() ~= 'minimapWindow' then return out end
  for _, c in ipairs(parent:getChildren()) do
    if c ~= minimap and c:isVisible() then out[#out + 1] = c:getRect() end
  end
  return out
end

local function placeParty(cam, rect, scale)
  local edgeRect = M.clampRect(rect, controlRects())
  local now = g_clock.millis()
  local me = myPosition()
  local animating = false
  for _, pm in pairs(party) do
    local w = pm.widget
    if alive(w) then
      local x, y, done = M.glide(pm.anim, now)
      if not done then animating = true end
      local tx, ty = math.floor(x), math.floor(y)
      local pt = minimap:getTilePoint({ x = tx, y = ty, z = cam.z })
      if not settings.party or not pt or (pt.x == -1 and pt.y == -1) then
        w:hide()
      else
        local px = pt.x + (x - tx) * scale
        local py = pt.y + (y - ty) * scale
        local inside, ex, ey, dir = M.edge(px, py, edgeRect, M.EDGE_MARGIN)
        local image = inside and 'party_pin' or ('party_arrow_' .. (dir or 'n'))
        if w.image ~= image then
          w:setImageSource(ICONS .. image)
          w.image = image
        end
        local half = math.floor(PIN_SIZE / 2)
        w:setPosition({ x = math.floor(ex - half + 0.5), y = math.floor(ey - half + 0.5) })
        local arrow = M.floorArrow(pm.e.z, cam.z)
        if w.floor ~= arrow then
          w.floor = arrow
          if arrow then
            w.floorIcon:setImageSource(ICONS .. 'floor_' .. arrow)
            w.floorIcon:show()
          else
            w.floorIcon:hide()
          end
        end
        w:show()
        local r = w:getRect()
        hitList[#hitList + 1] = { rect = { x = r.x - 1, y = r.y - 1, width = r.width + 2, height = r.height + 2 },
                                  text = M.memberText(pm.e, me) }
      end
    end
  end
  if animating and not animEvent then
    animEvent = scheduleEvent(function()
      animEvent = nil
      handlers.place()
    end, ANIM_TICK_MS)
  end
end

local function place()
  hitList = {}
  if not alive(minimap) or not alive(layer) then return end
  local cam = minimap:getCameraPosition()
  if not cam or not cam.z then return end
  local rect = minimapRect()
  local scale = minimap:getScale()
  local shown = 0
  if settings.poi and next(floors) then
    local bounds = M.viewBounds(cam, rect.width, rect.height, scale, 1)
    for _, m in ipairs(M.visiblePoi(floors, bounds, settings.cats, MAX_POI)) do
      local pt = minimap:getTilePoint({ x = m.x, y = m.y, z = cam.z })
      if pt and pt.x >= rect.x and pt.y >= rect.y and pt.x < rect.x + rect.width and pt.y < rect.y + rect.height then
        shown = shown + 1
        local w = poiWidget(shown)
        if w.kind ~= m.k then
          w:setImageSource(ICONS .. 'poi_' .. m.k)
          w.kind = m.k
        end
        local x, y = pt.x - math.floor(POI_SIZE / 2), pt.y - math.floor(POI_SIZE / 2)
        w:setPosition({ x = x, y = y })
        w:show()
        hitList[#hitList + 1] = { rect = { x = x, y = y, width = POI_SIZE, height = POI_SIZE }, text = m.n }
      end
    end
  end
  for i = shown + 1, #poiPool do
    poiPool[i]:hide()
  end
  -- party members last: drawn over the points of interest and first in the hover test
  placeParty(cam, rect, scale)
end
handlers.place = place

-- ---------------------------------------------------------------- game view arrows
-- A party member on the same floor but outside the visible game area: an arrow on the edge of the map panel toward
-- them, in their party colour, with the name and the distance in tiles next to it. Refreshed on a party update and on
-- the player's own step, at most every M.GAME_MIN_MS; the widgets are pooled.
local function gameWidgets(i)
  local g = gamePool[i]
  if not g or not alive(g.arrow) then
    g = { arrow = g_ui.createWidget('MapMarkerGameArrow', gameLayer), label = g_ui.createWidget('MapMarkerGameLabel', gameLayer) }
    gamePool[i] = g
  end
  return g
end

local function hideGame(from)
  for i = from, #gamePool do
    local g = gamePool[i]
    if g and alive(g.arrow) then g.arrow:hide() g.label:hide() end
  end
end

local function updateGame()
  gameLast = g_clock.millis()
  if not alive(gameLayer) or not alive(mapPanel) then return end
  local me = myPosition()
  local vd = mapPanel:getVisibleDimension()
  if not settings.game or not settings.party or not me or not g_game.isOnline() or not vd or vd.width <= 0 then
    hideGame(1)
    return
  end
  local rect = mapPanel:getRect()
  local keep = mapPanel:isKeepAspectRatioEnabled()
  local shown = 0
  for _, pm in pairs(party) do
    local r = M.gameIndicator(me, pm.e, vd, rect, keep)
    if r then
      shown = shown + 1
      local g = gameWidgets(shown)
      local color = M.color(pm.slot)
      local image = 'party_arrow_' .. (r.dir or 'n')
      if g.image ~= image then
        g.arrow:setImageSource(ICONS .. image)
        g.image = image
      end
      g.arrow:setImageColor(color)
      g.arrow:setPosition({ x = r.x - 6, y = r.y - 6 })
      g.arrow:show()
      local text = M.gameText(pm.e.n, r.dist)
      if g.text ~= text then
        g.label:setText(text)
        g.text = text
      end
      g.label:setColor(color)
      g.label:show()
      local lw, lh = g.label:getWidth(), g.label:getHeight()
      local lx = (r.side == 'left') and (r.x - 8 - lw) or (r.x + 8)
      g.label:setPosition({ x = lx, y = r.y - math.floor(lh / 2) })
    end
  end
  hideGame(shown + 1)
end

-- throttled: now when the last refresh is old enough, else one trailing refresh
local function requestGame()
  if gameEvent then return end
  local wait = M.GAME_MIN_MS - (g_clock.millis() - gameLast)
  if wait <= 0 then
    updateGame()
  else
    gameEvent = scheduleEvent(function()
      gameEvent = nil
      updateGame()
    end, wait)
  end
end
handlers.requestGame = requestGame

local function attachGame()
  local gi = modules.game_interface
  local panel = gi and gi.getMapPanel and gi.getMapPanel()
  if not panel or panel:isDestroyed() then return end
  if panel == mapPanel and alive(gameLayer) then return end
  mapPanel = panel
  gameLayer = g_ui.createWidget('MapMarkerGameLayer', mapPanel)
  gameLayer:fill('parent')
  gamePool = {}
end

local function detachGame()
  if gameEvent then removeEvent(gameEvent) gameEvent = nil end
  if alive(gameLayer) then gameLayer:destroy() end
  gameLayer, mapPanel, gamePool = nil, nil, {}
end

-- ---------------------------------------------------------------- hover
local hoverWatch
local function hideHover()
  if hoverWatch then
    removeEvent(hoverWatch)
    hoverWatch = nil
  end
  if hoverText then
    g_tooltip.hide()
    hoverText = nil
  end
end

-- the minimap does not always say when the mouse left it: while a hover text shows, look every 150 ms
local function watchHover()
  if hoverWatch then return end
  hoverWatch = cycleEvent(function()
    if not alive(minimap) or not minimap:isVisible() or not minimap:containsPoint(g_window.getMousePosition()) then
      hideHover()
    end
  end, 150)
end

local function onHover(self, mousePos)
  local h = M.hit(hitList, mousePos.x, mousePos.y)
  if h then
    if hoverText ~= h.text then
      g_tooltip.displayText(h.text)
      hoverText = h.text
      watchHover()
    end
  else
    hideHover()
  end
  return false
end

local function onHoverChange(self, hovered)
  if not hovered then hideHover() end
end

local function onView()
  place()
end

-- ---------------------------------------------------------------- the minimap widget
local function detach()
  if alive(minimap) then
    disconnect(minimap, { onCameraPositionChange = onView, onZoomChange = onView, onGeometryChange = onView,
                          onMouseMove = onHover, onHoverChange = onHoverChange })
  end
  for _, pm in pairs(party) do
    if alive(pm.widget) then pm.widget:destroy() end
    pm.widget = nil
  end
  if alive(layer) then layer:destroy() end
  layer, minimap, poiPool, hitList = nil, nil, {}, {}
  hideHover()
end

local function partyWidget(pm)
  if not alive(pm.widget) and alive(layer) then
    pm.widget = g_ui.createWidget('MapMarkerParty', layer)
    pm.widget:raise()
    pm.widget.floorIcon = pm.widget:getChildById('floor')
  end
  if alive(pm.widget) then
    pm.widget:setImageColor(M.color(pm.slot))
  end
end

-- the minimap module may load after this one or be reloaded: attach to whatever widget it has now
local function attach()
  local mm = modules.game_minimap and modules.game_minimap.minimapWidget
  if not mm or mm:isDestroyed() then return false end
  if mm == minimap and alive(layer) then return true end
  detach()
  minimap = mm
  layer = g_ui.createWidget('MapMarkerLayer')
  minimap:insertChild(1, layer)
  layer:fill('parent')
  connect(minimap, { onCameraPositionChange = onView, onZoomChange = onView, onGeometryChange = onView,
                     onMouseMove = onHover, onHoverChange = onHoverChange })
  for _, pm in pairs(party) do partyWidget(pm) end
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
  end, 1000)
end

-- ---------------------------------------------------------------- data
local function clearParty()
  for _, pm in pairs(party) do
    if alive(pm.widget) then pm.widget:destroy() end
  end
  party, slots = {}, {}
  hideGame(1)
end

local function onParty(data)
  local list = M.others(data.m, myId())
  local ids, now = {}, g_clock.millis()
  for _, e in ipairs(list) do ids[#ids + 1] = e.i end
  M.assignColors(slots, ids)
  local present = {}
  for _, e in ipairs(list) do
    present[e.i] = true
    local pm = party[e.i]
    if not pm then
      pm = {}
      party[e.i] = pm
    end
    pm.anim = M.retarget(pm.anim, e.x, e.y, e.z, now)
    pm.e = e
    pm.slot = slots[e.i]
    partyWidget(pm)
  end
  for id, pm in pairs(party) do
    if not present[id] then
      if alive(pm.widget) then pm.widget:destroy() end
      party[id] = nil
    end
  end
  place()
  requestGame()
end

local function onPoi(data)
  pois = type(data.marks) == 'table' and data.marks or {}
  floors = M.byFloor(pois)
  place()
end

local function onReveal(data)
  if M.addMarks(pois, data.marks) > 0 then
    floors = M.byFloor(pois)
    place()
  end
end

local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local d = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'party' then
    if settings.party then onParty(d) end
  elseif msg.action == 'poi' then
    if settings.poi then onPoi(d) end
  elseif msg.action == 'reveal' then
    if settings.poi then onReveal(d) end
  end
end

local function safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then g_logger.warning('[mapmarkers] ' .. name .. ': ' .. tostring(err)) end
  end
end

local function onGameStart()
  ensureAttached()
  attachGame()
  send('hello', { party = settings.party, poi = settings.poi })
end

local function onGameEnd()
  clearParty()
  detachGame()
  pois, floors = {}, {}
  place()
end

-- ---------------------------------------------------------------- settings window and API
local function updateSettingsWindow()
  if not settingsWindow then return end
  settingsWindow.partyBox:setChecked(settings.party, true)
  settingsWindow.poiBox:setChecked(settings.poi, true)
  settingsWindow.gameBox:setChecked(settings.game, true)
  settingsWindow.gameBox:setEnabled(settings.party)
  for _, c in ipairs(M.CATEGORIES) do
    local box = settingsWindow.categories:getChildById(c)
    if box then
      box:setChecked(settings.cats[c], true)
      box:setEnabled(settings.poi)
    end
  end
end

function setParty(on)
  on = on == true
  if settings.party == on then return end
  settings.party = on
  saveSettings()
  if not on then clearParty() end
  send('set', { party = on })
  updateGame()
  place()
  updateSettingsWindow()
end

function setGame(on)
  on = on == true
  if settings.game == on then return end
  settings.game = on
  saveSettings()
  updateGame()
  updateSettingsWindow()
end

function setPoi(on)
  on = on == true
  if settings.poi == on then return end
  settings.poi = on
  saveSettings()
  if not on then pois, floors = {}, {} end
  send('set', { poi = on })
  place()
  updateSettingsWindow()
end

function setCategory(cat, on)
  if settings.cats[cat] == nil then return end
  settings.cats[cat] = on == true
  saveSettings()
  place()
end

function showSettings()
  if not settingsWindow then
    settingsWindow = g_ui.createWidget('MapMarkerSettings', rootWidget)
    for _, c in ipairs(M.CATEGORIES) do
      local box = g_ui.createWidget('MapMarkerCategory', settingsWindow.categories)
      box:setId(c)
      box:setText(tr(M.CATEGORY_LABEL[c]))
      box:setIcon(ICONS .. 'poi_' .. ({ town = 'temple', npc = 'npc', shop = 'shop', craft = 'craft', guild = 'guild',
        portal = 'portal', dungeon = 'dungeon', boss = 'boss', hunt = 'hunt' })[c])
      box.onCheckChange = function(self) setCategory(c, self:isChecked()) end
    end
  end
  updateSettingsWindow()
  settingsWindow:show()
  settingsWindow:raise()
  settingsWindow:focus()
end

function hideSettings()
  if settingsWindow then settingsWindow:hide() end
end

function toggleSettings()
  if settingsWindow and settingsWindow:isVisible() then hideSettings() else showSettings() end
end

-- for tests and the live check: what is shown now
function debugState()
  local n, names = 0, {}
  for _, pm in pairs(party) do
    n = n + 1
    names[#names + 1] = string.format('%s@%d,%d,%d', tostring(pm.e.n), pm.e.x, pm.e.y, pm.e.z)
  end
  table.sort(names)
  local shown = 0
  for _, w in ipairs(poiPool) do if w:isVisible() then shown = shown + 1 end end
  local kinds = {}
  for _, m in ipairs(pois) do kinds[m.k] = (kinds[m.k] or 0) + 1 end
  local kt = {}
  for k, c in pairs(kinds) do kt[#kt + 1] = k .. '=' .. c end
  table.sort(kt)
  return { party = n, names = table.concat(names, ' '), pois = #pois, shownPois = shown, hits = #hitList,
           attached = alive(layer), kinds = table.concat(kt, ' ') }
end

function init()
  loadSettings()
  g_ui.importStyle('mapmarkers')
  handlers.opcode = safe('opcode', onMessage)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  handlers.player = { onPositionChange = safe('move', requestGame) }
  ProtocolGame.registerExtendedJSONOpcode(M.OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  connect(LocalPlayer, handlers.player)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game or {})
  disconnect(LocalPlayer, handlers.player or {})
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, M.OPCODE)
  if animEvent then removeEvent(animEvent) animEvent = nil end
  if attachEvent then removeEvent(attachEvent) attachEvent = nil end
  clearParty()
  detach()
  detachGame()
  if settingsWindow then settingsWindow:destroy() settingsWindow = nil end
  pois, floors = {}, {}
  handlers = {}
end
