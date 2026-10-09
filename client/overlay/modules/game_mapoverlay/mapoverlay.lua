-- Map overlay: the client's explored map (the same data as the minimap) drawn see-through over the game view,
-- centred on the character, with icons for points of interest.
--
-- * Toggle: hotkey "Minimap: Map Overlay" (default Tab; rebind it in Options > Hotkeys). The first time a hotkey set
--   is seen, Tab is given to the overlay; if the set had Tab on "Next Channel" that moves to Ctrl+Tab
--   (MapOverlayMath.assignDefaultKey). Also the "Map Overlay" entries of the top menu (Hunt).
-- * While open: mouse wheel over the game view or +/- zoom (1..16 px per tile), the settings window has opacity,
--   zoom, position mode (centred on the character over the whole view / a box in the top right corner that follows
--   the character) and which marks to show. Settings are kept in g_settings node 'mapOverlay'.
-- * Marks come from the server (extended opcode 245, server/data/scripts/chaos/map_marks.lua) once per second while
--   the overlay is open: party members, temple, depots, NPCs, rift entrance / guardian / chest / coffer, treasure
--   goblins, world boss, invasion target and boss, dungeon bosses. Without the server script the map still works.
-- * Rifts: their rooms are rebuilt for every run, so when a run starts the server sends its square once and the
--   overlay forgets the old map there (g_minimap.clearArea, client base patch 0024) - the rift shows as explored.
-- The map itself is a UIMinimap with widget opacity; the marks sit in a sibling layer so they stay fully opaque.

local OPCODE = 245
local ICONS = '/images/chaos/mapoverlay/'
local TICK_MS = 100

local overlay, mapWidget, marksLayer, settingsWindow
local settings
local shown = false
local marks = {}            -- last list from the server
local markWidgets = {}      -- pool
local selfMark
local tickEvent
local riftTokens = {}
local wheelHooked, keysBound = false, {}

local function S() return MapOverlayMath end

local function loadSettings()
  local node = g_settings.getNode('mapOverlay') or {}
  settings = S().sanitize(node.view)
  riftTokens = type(node.rifts) == 'table' and node.rifts or {}
end

local function saveSettings()
  local node = g_settings.getNode('mapOverlay') or {}
  node.view = settings
  -- keep the last few rift tokens only
  local n, keep = 0, {}
  for k in pairs(riftTokens) do
    n = n + 1
    if n <= 20 then keep[k] = true end
  end
  riftTokens = keep
  node.rifts = keep
  g_settings.setNode('mapOverlay', node)
end

local function sendWatch(on)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = 'watch', data = { on = on } }))
  end
end

-- ---------------------------------------------------------------- layout and drawing
local function applyStyle()
  if not overlay then return end
  if settings.mode == 'corner' then
    overlay:setBackgroundColor('#0d0b0e99')
    overlay:setBorderWidth(1)
  else
    overlay:setBackgroundColor('alpha')
    overlay:setBorderWidth(0)
  end
  mapWidget:setOpacity(settings.opacity)
  mapWidget:setZoom(settings.zoom)
end

-- puts the overlay on the drawn map (or a corner box of it) and centres the minimap on the character's tile
local function applyGeometry(pos)
  local panel = overlay:getParent()
  local geo = S().viewGeometry(panel:getRect(), function(x, y)
    local p = panel:getPosition({ x = x, y = y })
    if p and p.x and p.x > 0 and p.x < 65535 then return p end
    return nil
  end, pos)
  if not geo then return false end
  if settings.mode == 'corner' then
    local w, h = S().cornerRect(geo.width, geo.height)
    overlay:setRect({ x = geo.x + geo.width - w - 8, y = geo.y + 30, width = w, height = h })
    mapWidget:setRect(overlay:getRect())
  else
    overlay:setRect({ x = geo.x, y = geo.y, width = geo.width, height = geo.height })
    local hw = math.max(geo.cx - geo.x, geo.x + geo.width - geo.cx) + 2
    local hh = math.max(geo.cy - geo.y, geo.y + geo.height - geo.cy) + 2
    local rect = { x = geo.cx - hw, y = geo.cy - hh, width = hw * 2, height = hh * 2 }
    mapWidget:setRect(rect)
    -- the minimap rounds its centre to whole tiles: shift it so the character's tile lands on its game view tile
    local tp = mapWidget:getTilePoint(pos)
    if tp and (tp.x ~= geo.cx or tp.y ~= geo.cy) then
      rect.x, rect.y = rect.x + geo.cx - tp.x, rect.y + geo.cy - tp.y
      mapWidget:setRect(rect)
    end
  end
  return true
end

local function markWidget(i)
  local w = markWidgets[i]
  if not w then
    w = g_ui.createWidget('MapOverlayMark', marksLayer)
    markWidgets[i] = w
  end
  return w
end

local function placeMark(w, pos, icon, size)
  local pt = mapWidget:getTilePoint(pos)
  local rect = overlay:getRect()
  if not pt or pt.x < rect.x or pt.y < rect.y or pt.x > rect.x + rect.width or pt.y > rect.y + rect.height then
    w:hide()
    return
  end
  w:setImageSource(ICONS .. icon)
  w:setSize({ width = size, height = size })
  w:setPosition({ x = pt.x - math.floor(size / 2), y = pt.y - math.floor(size / 2) })
  w:show()
end

local function refresh()
  if not shown or not overlay then return end
  local player = g_game.getLocalPlayer()
  if not player then return end
  local pos = player:getPosition()
  if not pos then return end
  mapWidget:setCameraPosition(pos)
  if not applyGeometry(pos) then overlay:hide() return end
  overlay:show()
  local size = settings.zoom >= 3 and 16 or 14
  local list = S().visibleMarks(marks, pos.z, settings)
  for i, m in ipairs(list) do
    local w = markWidget(i)
    placeMark(w, { x = m.x, y = m.y, z = m.z }, m.k, m.k == 'npc' and size - 2 or size)
  end
  for i = #list + 1, #markWidgets do markWidgets[i]:hide() end
  if not selfMark then selfMark = g_ui.createWidget('MapOverlayMark', marksLayer) end
  placeMark(selfMark, pos, 'self', size)
  selfMark:raise()
end

local function stopTick()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

local function startTick()
  stopTick()
  tickEvent = cycleEvent(refresh, TICK_MS)
end

-- ---------------------------------------------------------------- input while open
local function onWheel(widget, mousePos, direction)
  if not shown then return false end
  zoom(direction == MouseWheelUp and 1 or -1)
  return true
end

local function bindZoomKeys()
  for _, k in ipairs({ '+', '-' }) do
    if not (KeyBinds and KeyBinds.hotkeyIsUsed and KeyBinds:hotkeyIsUsed(k)) then
      local fn = function() if canPerformAction and not canPerformAction() then return end zoom(k == '+' and 1 or -1) end
      g_keyboard.bindKeyDown(k, fn)
      keysBound[k] = fn
    end
  end
end

local function unbindZoomKeys()
  for k, fn in pairs(keysBound) do g_keyboard.unbindKeyDown(k, fn) end
  keysBound = {}
end

-- ---------------------------------------------------------------- settings window
local function keyText()
  local kb = KeyBinds and KeyBinds.Hotkeys and KeyBinds.Hotkeys['Minimap'] and KeyBinds.Hotkeys['Minimap']['Map Overlay']
  local key = kb and kb.firstKey or ''
  if key == nil or key == '' then
    return tr('No key set. Options > Hotkeys > "Minimap: Map Overlay".')
  end
  return tr('Key: %s (change it in Options > Hotkeys > "Minimap: Map Overlay"). While open: mouse wheel or +/- to zoom.', key)
end

local function updateSettingsWindow()
  if not settingsWindow then return end
  settingsWindow.showBox:setChecked(shown, true)
  settingsWindow.opacityRow.value:setText(S().percent(settings.opacity))
  settingsWindow.zoomRow.value:setText(S().zoomLabel(settings.zoom))
  settingsWindow.modeRow.mode:setCurrentOptionByData(settings.mode, true)
  settingsWindow.partyBox:setChecked(settings.party, true)
  settingsWindow.townBox:setChecked(settings.town, true)
  settingsWindow.eventsBox:setChecked(settings.events, true)
  settingsWindow.keyLabel:setText(keyText())
end

function showSettings()
  if not settingsWindow then
    settingsWindow = g_ui.createWidget('MapOverlaySettings', rootWidget)
    local combo = settingsWindow.modeRow.mode
    combo:addOption(tr('Centre on character'), 'center')
    combo:addOption(tr('Corner, follows'), 'corner')
    combo.onOptionChange = function(_, _, data)
      if data and data ~= settings.mode then
        settings.mode = data
        saveSettings()
        applyStyle()
        refresh()
      end
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

-- ---------------------------------------------------------------- public
function setShown(on)
  on = on and g_game.isOnline() and overlay ~= nil
  if on == shown then updateSettingsWindow() return end
  shown = on
  if shown then
    applyStyle()
    overlay:show()
    overlay:raise()
    refresh()
    startTick()
    bindZoomKeys()
    sendWatch(true)
  else
    stopTick()
    unbindZoomKeys()
    if overlay then overlay:hide() end
    sendWatch(false)
  end
  updateSettingsWindow()
end

function toggle()
  setShown(not shown)
end

function isShown()
  return shown
end

function zoom(delta)
  local z = S().clampZoom(settings.zoom + (delta or 0))
  if z == settings.zoom then return end
  settings.zoom = z
  if mapWidget then mapWidget:setZoom(z) end
  saveSettings()
  updateSettingsWindow()
  refresh()
end

function stepOpacity(delta)
  settings.opacity = S().stepOpacity(settings.opacity, delta)
  if mapWidget then mapWidget:setOpacity(settings.opacity) end
  saveSettings()
  updateSettingsWindow()
end

function setFilter(name, on)
  if settings[name] == nil then return end
  settings[name] = on and true or false
  saveSettings()
  refresh()
end

-- ---------------------------------------------------------------- server data
local function onRiftArea(area)
  if not S().shouldClearRift(riftTokens, area) then return end
  riftTokens[tostring(area.id)] = true
  if g_minimap.clearArea then
    g_minimap.clearArea({ x = area.x1, y = area.y1, z = area.z }, { x = area.x2, y = area.y2, z = area.z })
  end
  saveSettings()
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then return end
  local d = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'marks' then
    marks = type(d.marks) == 'table' and d.marks or {}
    refresh()
  elseif msg.action == 'rift' then
    onRiftArea(d)
  end
end

-- ---------------------------------------------------------------- hotkey
local function registerHotkey()
  if not (KeyBinds and KeyBinds.Hotkeys) then return end
  KeyBinds.Hotkeys['Minimap'] = KeyBinds.Hotkeys['Minimap'] or {}
  local entry = KeyBinds.Hotkeys['Minimap']['Map Overlay'] or {}
  entry.jsonName = S().ACTION
  entry.bindKeyDown = function()
    if canPerformAction and not canPerformAction() then return end
    toggle()
  end
  KeyBinds.Hotkeys['Minimap']['Map Overlay'] = entry
end

-- the first time a hotkey set is seen, give the overlay its default key (see MapOverlayMath.assignDefaultKey)
local function assignDefaultKeys()
  if not (Options and Options.array and Options.array.hotkeyOptions) then return end
  local sets = Options.array.hotkeyOptions.hotkeySets
  if type(sets) ~= 'table' then return end
  local node = g_settings.getNode('mapOverlay') or {}
  local done = type(node.keySets) == 'table' and node.keySets or {}
  local changed = false
  for name, set in pairs(sets) do
    if type(set) == 'table' and not done[name] then
      for _, chatType in ipairs({ 'chatOn', 'chatOff' }) do
        if S().assignDefaultKey(set[chatType]) and name == Options.currentHotkeySetName then changed = true end
      end
      done[name] = true
    end
  end
  node.keySets = done
  g_settings.setNode('mapOverlay', node)
  if changed and KeyBinds.setupAndReset then
    KeyBinds:setupAndReset(Options.currentHotkeySetName, Options.isChatOnEnabled and 'chatOn' or 'chatOff')
  end
end

-- ---------------------------------------------------------------- lifecycle
local function onGameStart()
  marks = {}
  scheduleEvent(function() pcall(assignDefaultKeys) end, 1500)
end

local function onGameEnd()
  setShown(false)
  hideSettings()
  marks = {}
end

function init()
  loadSettings()
  g_ui.importStyle('mapoverlay')
  local mapPanel = modules.game_interface.getMapPanel()
  overlay = g_ui.createWidget('MapOverlay', mapPanel)
  mapWidget = overlay:getChildById('map')
  marksLayer = overlay:getChildById('marks')
  if mapWidget.disableAutoWalk then mapWidget:disableAutoWalk() end
  if mapWidget.setMinZoom then mapWidget:setMinZoom(S().MIN_ZOOM) end
  if mapWidget.setMaxZoom then mapWidget:setMaxZoom(S().MAX_ZOOM) end
  overlay:hide()
  connect(mapPanel, { onMouseWheel = onWheel }, true)
  wheelHooked = mapPanel
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  registerHotkey()
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  setShown(false)
  stopTick()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if wheelHooked then disconnect(wheelHooked, { onMouseWheel = onWheel }) wheelHooked = false end
  if KeyBinds and KeyBinds.Hotkeys and KeyBinds.Hotkeys['Minimap'] then
    local kb = KeyBind and KeyBind.getKeyBind and KeyBind:getKeyBind('Minimap', 'Map Overlay')
    if kb and kb.deactive then pcall(function() kb:deactive() end) end
  end
  if settingsWindow then settingsWindow:destroy() settingsWindow = nil end
  if overlay then overlay:destroy() overlay = nil end
  markWidgets, selfMark, mapWidget, marksLayer = {}, nil, nil, nil
end
