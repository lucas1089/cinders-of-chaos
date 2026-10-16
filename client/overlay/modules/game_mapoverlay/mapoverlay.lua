-- Map overlay: the client's explored map (the same data as the minimap) drawn see-through over the game view,
-- centred on the character, with icons for points of interest.
--
-- * Toggle: hotkey "Minimap: Map Overlay" (default Tab; rebind it in Options > Hotkeys). The first time a hotkey set
--   is seen, Tab is given to the overlay; if the set had Tab on "Next Channel" that moves to Ctrl+Tab
--   (MapOverlayMath.assignDefaultKey). Also the "Map Overlay" entries of the top menu (Hunt).
-- * Click-through: every plain click, drag, hover and wheel turn reaches the game map under the overlay (walk, attack,
--   use, look); all overlay widgets but the control strip are phantom (mapoverlay_layout_test.lua checks the .otui).
-- * While open: Shift + wheel over the game view, the wheel over the strip, or +/- zoom (1..16 px per tile; with the
--   map panned it zooms toward the cursor, otherwise around the character), Ctrl + wheel changes the opacity (10%
--   steps, 20-100%), Shift + middle-drag pans the map (Shift + arrow keys too; Ctrl+Shift+arrows when chat is on), the
--   hotkey "Minimap: Map Overlay Centre" (Home, Ctrl+Home with chat on) or the strip's Centre button snaps back to the
--   character. A small control strip in the bottom right corner
--   of the game view has opacity -/+, zoom -/+, Centre and Close; it is the only part of the overlay that takes the
--   mouse. The pan is kept in memory only: it resets when the overlay closes, on logout and when a new rift run
--   starts. The settings window has opacity, zoom, position mode (centred on the character over the whole view / a
--   box in the top right corner that follows the character), the strip and which marks to show. Settings are kept
--   in g_settings node 'mapOverlay'.
-- * Marks come from the server (extended opcode 245, server/data/scripts/chaos/map_marks.lua) once per second while
--   the overlay is open: party members, temple, depots, NPCs, rift entrance / guardian / chest / coffer, treasure
--   goblins, world boss, invasion target and boss, dungeon bosses. Without the server script the map still works.
-- * Rifts: their rooms are rebuilt for every run, so when a run starts the server sends its square once and the
--   overlay forgets the old map there (g_minimap.clearArea, client base patch 0024) - the rift shows as explored.
-- The map itself is a UIMinimap with widget opacity; the marks sit in a sibling layer so they stay fully opaque.

local OPCODE = 245
local ICONS = '/images/chaos/mapoverlay/'
local TICK_MS = 100        -- refresh while the character stands still
local FRAME_MS = 16        -- refresh while it walks or the view changes: the map follows every frame

local STRIP_MARGIN = 8
local MSG_MS = 1600
local PAN_KEYS = { Up = { 0, -1 }, Down = { 0, 1 }, Left = { -1, 0 }, Right = { 1, 0 } }

local overlay, mapWidget, marksLayer, settingsWindow, strip
local youLabel
local settings
local panX, panY = 0, 0     -- pan from the character in tiles (0, 0 = centred); never saved
local anchor                -- screen point that shows the character plus the pan (its sprite while centred)
local walkX, walkY = 0, 0   -- the character's sprite from its tile while a step lasts, in tiles
local lastRefresh, lastPos = 0, nil
local geoCache              -- the measured game view: {key, x, y, width, height, ts, sx, sy}; see locate()
local overlayBox            -- the overlay's rect as last set
local shownMarks = {}       -- the marks of the last full refresh (positions follow every frame)
local MAX_STEP_MARKS = 48   -- marks moved per frame during a step; the rest catch up on the next full refresh
local camPoint, camPos      -- the screen point of the minimap camera's tile, and that tile (see pointOf)
local fixCache, fixCount = {}, 0   -- the minimap's whole-tile rounding per widget size and zoom
local viewRect              -- the drawn game view {x, y, width, height}
local freeRect              -- the part of it the player sees (no panels over it)
local drag                  -- {mx, my, px, py} while the middle button pans
local dragEvent
local msgText, msgUntil = nil, 0
local stripTexts = {}
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

-- the part of the game view that is not under the window edge or a side / bottom panel
local function visibleArea(view)
  local win = rootWidget:getSize()
  local insets = { top = view.y < 0 and 40 or 0 }
  local gi = modules.game_interface
  local function panelRect(getter)
    local w = getter and getter()
    if w and w:isVisible() then return w:getRect() end
  end
  -- the side panels (the left one may be the same widget as the right one when it is not used)
  for _, getter in ipairs({ gi.getRightPanel, gi.getLeftPanel }) do
    local r = panelRect(getter)
    if r and r.width > 0 then
      if r.x >= win.width / 2 then
        insets.right = math.max(insets.right or 0, win.width - r.x)
      elseif r.x + r.width <= win.width / 2 then
        insets.left = math.max(insets.left or 0, r.x + r.width)
      end
    end
  end
  local r
  for _, getter in ipairs({ gi.getBottomPanel, gi.getBottomActionPanel }) do
    r = panelRect(getter)
    if r and r.height > 0 then insets.bottom = math.max(insets.bottom or 0, win.height - r.y) end
  end
  return S().freeArea(view, win, insets)
end

-- puts the overlay on the drawn map (or a corner box of it) and centres the minimap on the character plus the pan.
-- The character is where its sprite is drawn, not its tile: during a step the game view scrolls smoothly and the
-- tile is already the next one (MapOverlayMath.follow), so the walk offset is added to the pan. The camera moves in
-- whole tiles; the rest shifts the minimap widget by a few pixels.
--
-- Cost: measuring the drawn map takes about 70 screen -> tile lookups, so it is done only when the map panel's rect
-- or visible dimension (game_chaosview zoom) changed; every other frame finds the character's tile near the cached
-- centre with about 15 lookups (MapOverlayMath.tileCentreNear).
local function locate(pos)
  local panel = overlay:getParent()
  local r = panel:getRect()
  local vd = panel.getVisibleDimension and panel:getVisibleDimension()
  local key = string.format('%d,%d,%d,%d,%d,%d', r.x, r.y, r.width, r.height, vd and vd.width or 0, vd and vd.height or 0)
  local probe = function(x, y)
    local p = panel:getPosition({ x = x, y = y })
    if p and p.x and p.x > 0 and p.x < 65535 then return p end
    return nil
  end
  local c = geoCache
  if c and c.key == key then
    local cx, cy = S().tileCentreNear(probe, c.sx, c.sy, c.ts, pos)
    if cx then
      c.cx, c.cy = cx, cy
      return c, false
    end
  end
  local geo = S().viewGeometry(r, probe, pos)
  if not geo then geoCache = nil return nil end
  geo.key = key
  geo.sx, geo.sy = math.floor(geo.x + geo.width / 2), math.floor(geo.y + geo.height / 2)
  geoCache = geo
  return geo, true
end

local function sameRect(a, b)
  return a and b and a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height
end

-- full = also re-measure the free area (panels) and place the box; a step frame only moves the minimap
local function applyGeometry(pos, full)
  local geo, measured = locate(pos)
  if not geo then return false end
  local sx, sy
  sx, sy, walkX, walkY = S().follow(geo)
  if measured or full or not freeRect then
    viewRect = { x = geo.x, y = geo.y, width = geo.width, height = geo.height }
    freeRect = visibleArea(viewRect)
  end
  local box, ax, ay
  if settings.mode == 'corner' then
    local w, h = S().cornerRect(freeRect.width, freeRect.height)
    box = { x = freeRect.x + freeRect.width - w - 8, y = freeRect.y + 8, width = w, height = h }
    ax, ay = box.x + math.floor(w / 2), box.y + math.floor(h / 2)
  else
    box = viewRect
    ax, ay = sx, sy
  end
  if not sameRect(box, overlayBox) then
    overlay:setRect(box)
    overlayBox = box
  end
  anchor = { x = ax, y = ay }
  local cox, coy, rx, ry = S().splitPan(panX + walkX, panY + walkY, settings.zoom)
  local cam = { x = pos.x + cox, y = pos.y + coy, z = pos.z }
  mapWidget:setCameraPosition(cam)
  local dx, dy = ax + rx, ay + ry   -- where the camera tile sits
  local hw = math.max(dx - box.x, box.x + box.width - dx) + 2
  local hh = math.max(dy - box.y, box.y + box.height - dy) + 2
  local rect = { x = dx - hw, y = dy - hh, width = hw * 2, height = hh * 2 }
  -- the minimap rounds its centre to whole tiles: shift it so the camera tile lands on its wanted point. The shift
  -- depends only on the widget's size and the zoom, so it is asked once per size
  local fixKey = hw * 4096 + hh * 8 + settings.zoom
  local fix = fixCache[fixKey]
  if fix then rect.x, rect.y = rect.x + fix.x, rect.y + fix.y end
  mapWidget:setRect(rect)
  if not fix then
    local tp = mapWidget:getTilePoint(cam)
    fix = { x = tp and tp.x >= 0 and dx - tp.x or 0, y = tp and tp.y >= 0 and dy - tp.y or 0 }
    if fixCount > 256 then fixCache, fixCount = {}, 0 end
    fixCache[fixKey], fixCount = fix, fixCount + 1
    if fix.x ~= 0 or fix.y ~= 0 then
      rect.x, rect.y = rect.x + fix.x, rect.y + fix.y
      mapWidget:setRect(rect)
    end
  end
  camPoint, camPos = { x = dx, y = dy }, cam
  return true
end

-- the screen point of a tile on the minimap (its centre), worked out here: the minimap is linear around the camera
-- tile, which sits on camPoint (the same as mapWidget:getTilePoint, without a call per mark and frame)
local function pointOf(pos)
  if not camPos or pos.z ~= camPos.z then return nil end
  local ppt = S().pixelsPerTile(settings.zoom)
  return { x = camPoint.x + (pos.x - camPos.x) * ppt, y = camPoint.y + (pos.y - camPos.y) * ppt }
end

local function markWidget(i)
  local w = markWidgets[i]
  if not w then
    w = g_ui.createWidget('MapOverlayMark', marksLayer)
    markWidgets[i] = w
  end
  return w
end

-- the minimap point of the character: its tile plus the walk offset
local function selfPoint(pos)
  local pt = pointOf(pos)
  if not pt then return nil end
  local ox, oy = S().walkPixels(walkX, walkY, settings.zoom)
  return { x = pt.x + ox, y = pt.y + oy }
end

local function placeMark(w, pos, icon, size, point)
  local pt = point or pointOf(pos)
  local rect = overlayBox or overlay:getRect()
  if not pt or pt.x < rect.x or pt.y < rect.y or pt.x > rect.x + rect.width or pt.y > rect.y + rect.height then
    if w.chaosShown ~= false then w:hide() w.chaosShown = false end
    return
  end
  if w.chaosIcon ~= icon then   -- the image and size only when they change: setImageSource is not free
    w.chaosIcon = icon
    w:setImageSource(ICONS .. icon)
  end
  if w.chaosSize ~= size then
    w.chaosSize = size
    w:setSize({ width = size, height = size })
  end
  local x, y = pt.x - math.floor(size / 2), pt.y - math.floor(size / 2)
  if w.chaosX ~= x or w.chaosY ~= y then
    w.chaosX, w.chaosY = x, y
    w:setPosition({ x = x, y = y })
  end
  if w.chaosShown ~= true then w:show() w.chaosShown = true end
end

-- ---------------------------------------------------------------- control strip
local function flash(text)
  msgText, msgUntil = text, g_clock.millis() + MSG_MS
end

local function setStripText(widget, text)
  if stripTexts[widget] ~= text then
    stripTexts[widget] = text
    widget:setText(text)
  end
end

local function updateStrip()
  if not strip then return end
  setStripText(strip.opValue, S().percent(settings.opacity))
  setStripText(strip.zValue, S().zoomLabel(settings.zoom))
  local status = strip.status
  if msgText and g_clock.millis() < msgUntil then
    setStripText(status, msgText)
    status:setColor('#f6cf72')
  elseif S().isPanned(panX, panY) then
    setStripText(status, tr('Panned - Centre button or Home to return'))
    status:setColor('#e8b84a')
  else
    msgText = nil
    setStripText(status, tr('Shift+wheel: zoom  Ctrl+wheel: opacity  Shift+mid-drag: pan'))
    status:setColor('#8c8070')
  end
end

local function placeStrip()
  if not strip then return end
  if shown and settings.strip and freeRect then
    local sz = strip:getSize()
    strip:setPosition({ x = freeRect.x + freeRect.width - sz.width - STRIP_MARGIN,
      y = freeRect.y + freeRect.height - sz.height - STRIP_MARGIN })
    updateStrip()
    strip:show()
    strip:raise()
  else
    strip:hide()
  end
end

local function inStrip(pos)
  return strip ~= nil and strip:isVisible() and pos ~= nil and strip:containsPoint(pos)
end

-- the "You" label next to the character's own icon while panned; on the view's edge, with an arrow, when the
-- character is outside the overlay
local function placeYou(pos, panned)
  if not youLabel then youLabel = g_ui.createWidget('MapOverlayYou', marksLayer) end
  local pt = panned and selfPoint(pos)
  if not pt and not youLabel:isVisible() then return end
  if not pt then youLabel:hide() return end
  local rect = (settings.mode ~= 'corner' and freeRect) or overlay:getRect()
  local ex, ey, arrow = S().edgeMarker(pt.x - rect.x, pt.y - rect.y, rect.width, rect.height, 24)
  local text, x, y
  if ex then
    text = arrow == '<' and '< ' .. tr('You') or arrow == '>' and tr('You') .. ' >' or arrow .. ' ' .. tr('You')
    x, y = rect.x + ex, rect.y + ey
  else
    text = tr('You')
    x, y = pt.x + 12, pt.y
  end
  youLabel:setText(text)
  local sz = youLabel:getSize()
  local lx = math.max(rect.x, math.min(x - (ex and math.floor(sz.width / 2) or 0), rect.x + rect.width - sz.width))
  local ly = math.max(rect.y, math.min(y - math.floor(sz.height / 2), rect.y + rect.height - sz.height))
  if ex and strip and strip:isVisible() then   -- keep the edge marker clear of the strip
    local sr = strip:getRect()
    if lx < sr.x + sr.width and lx + sz.width > sr.x and ly < sr.y + sr.height and ly + sz.height > sr.y then
      ly = sr.y - sz.height - 4
    end
  end
  youLabel:setPosition({ x = lx, y = ly })
  youLabel:show()
  youLabel:raise()
end

-- full (default): marks rebuilt from the server list, the free area and the strip; step = false: a frame of a
-- step, only the minimap offset and the positions of the marks already shown
local function refresh(step)
  if not shown or not overlay then return end
  local full = not step
  if full then lastRefresh = g_clock.millis() end
  local player = g_game.getLocalPlayer()
  if not player then return end
  local pos = player:getPosition()
  if not pos then return end
  if not applyGeometry(pos, full) then
    overlayBox = nil
    overlay:hide()
    if strip then strip:hide() end
    return
  end
  if not overlay:isVisible() then overlay:show() end
  local size = settings.zoom >= 3 and 16 or 14
  if full then shownMarks = S().visibleMarks(marks, pos.z, settings) end
  local n = full and #shownMarks or math.min(#shownMarks, MAX_STEP_MARKS)
  for i = 1, n do
    local m = shownMarks[i]
    placeMark(markWidget(i), { x = m.x, y = m.y, z = m.z }, m.k, m.k == 'npc' and size - 2 or size)
  end
  if full then
    for i = #shownMarks + 1, #markWidgets do
      local w = markWidgets[i]
      if w.chaosShown ~= false then w:hide() w.chaosShown = false end
    end
  end
  if not selfMark then selfMark = g_ui.createWidget('MapOverlayMark', marksLayer) end
  local panned = S().isPanned(panX, panY)
  placeMark(selfMark, pos, 'self', panned and size + 4 or size, selfPoint(pos) or { x = -1, y = -1 })
  if full then selfMark:raise() end
  if panned or full then placeYou(pos, panned) end
  if full then placeStrip() end
end

local function stopTick()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

-- every frame: while the character walks (and the frame after, to land on the tile) only the offset moves
-- (refresh(true)); a new tile (a step's start, a teleport, a floor change) and every TICK_MS do the full refresh.
-- A resize or a game_chaosview zoom is caught by locate() re-measuring the view.
local function frameTick()
  if not shown or not overlay then return end
  local player = g_game.getLocalPlayer()
  if not player then return end
  local pos = player:getPosition()
  local newTile = pos and not (lastPos and pos.x == lastPos.x and pos.y == lastPos.y and pos.z == lastPos.z)
  lastPos = pos
  if newTile or g_clock.millis() - lastRefresh >= TICK_MS then
    refresh()
  elseif player:isWalking() or walkX ~= 0 or walkY ~= 0 then
    refresh(true)
  end
end

local function startTick()
  stopTick()
  lastPos, geoCache, overlayBox = nil, nil, nil
  tickEvent = cycleEvent(frameTick, FRAME_MS)
end

-- ---------------------------------------------------------------- input while open
local function setPan(x, y)
  panX, panY = S().clampPan(x, y)
end

local function stopDrag()
  drag = nil
  if dragEvent then removeEvent(dragEvent) dragEvent = nil end
end

-- the map follows the mouse while the middle button is held (polled, so it keeps working outside the game view)
local function dragTick()
  if not drag or not shown then stopDrag() return end
  if not g_mouse.isPressed(MouseMidButton) then stopDrag() return end
  local m = g_window.getMousePosition()
  local x, y = S().dragPan(drag.px, drag.py, m.x - drag.mx, m.y - drag.my, settings.zoom)
  if x ~= panX or y ~= panY then
    panX, panY = x, y
    refresh(true)
  end
end

local function startDrag(pos)
  stopDrag()
  drag = { mx = pos.x, my = pos.y, px = panX, py = panY }
  dragEvent = cycleEvent(dragTick, 16)
end

local function onMousePress(widget, mousePos, button)
  if not shown or not S().startsPan(button == MouseMidButton, g_keyboard.isShiftPressed(), inStrip(mousePos)) then
    return false
  end
  if not (overlay and overlay:isVisible() and overlay:containsPoint(mousePos)) then return false end
  startDrag(mousePos)
  return true
end

local function onMouseRelease(widget, mousePos, button)
  if drag and button == MouseMidButton then stopDrag() return true end
  return false
end

local function onWheel(widget, mousePos, direction)
  if not shown then return false end
  local up = direction == MouseWheelUp
  local over = inStrip(mousePos)
  local action = S().wheelAction(g_keyboard.isCtrlPressed(), g_keyboard.isShiftPressed(), over)
  if not action then return false end   -- a plain wheel turn belongs to the game map
  if action == 'opacity' then
    stepOpacity(up and 0.1 or -0.1)
    return true
  end
  local cursor
  if not over and overlay:containsPoint(mousePos) then cursor = mousePos end
  zoom(up and 1 or -1, cursor)
  return true
end

local function panKey(dir)
  if canPerformAction and not canPerformAction() then return end
  setPan(S().keyPan(panX, panY, dir[1], dir[2], settings.zoom, 48))
  refresh()
end

local function bindKeys()
  local function free(k) return not (KeyBinds and KeyBinds.hotkeyIsUsed and KeyBinds:hotkeyIsUsed(k)) end
  for _, k in ipairs({ '+', '-' }) do
    if free(k) then
      local fn = function() if canPerformAction and not canPerformAction() then return end zoom(k == '+' and 1 or -1) end
      g_keyboard.bindKeyDown(k, fn)
      keysBound[k] = { fn = fn, press = false }
    end
  end
  -- the chat input eats Shift+Left / Shift+Right while chat is on: Ctrl+Shift+arrows always get through
  for name, dir in pairs(PAN_KEYS) do
    for _, prefix in ipairs({ 'Shift+', 'Ctrl+Shift+' }) do
      local k = prefix .. name
      if free(k) then
        local fn = function() panKey(dir) end
        g_keyboard.bindKeyPress(k, fn)
        keysBound[k] = { fn = fn, press = true }
      end
    end
  end
end

local function unbindKeys()
  for k, b in pairs(keysBound) do
    if b.press then g_keyboard.unbindKeyPress(k, b.fn) else g_keyboard.unbindKeyDown(k, b.fn) end
  end
  keysBound = {}
end

-- ---------------------------------------------------------------- settings window
local function keyText()
  local kb = KeyBinds and KeyBinds.Hotkeys and KeyBinds.Hotkeys['Minimap'] and KeyBinds.Hotkeys['Minimap']['Map Overlay']
  local key = kb and kb.firstKey or ''
  if key == nil or key == '' then
    return tr('No key set. Options > Hotkeys > "Minimap: Map Overlay".')
  end
  return tr('Key: %s (change it in Options > Hotkeys > Minimap). While open: Shift+wheel or +/- zoom, Ctrl+wheel opacity, Shift+middle-drag or Shift+arrows pan, Home centres (with chat on: Ctrl+Home and Ctrl+Shift+arrows). Plain clicks and the wheel reach the game map.', key)
end

local function updateSettingsWindow()
  if not settingsWindow then return end
  settingsWindow.showBox:setChecked(shown, true)
  settingsWindow.opacityRow.value:setText(S().percent(settings.opacity))
  settingsWindow.zoomRow.value:setText(S().zoomLabel(settings.zoom))
  settingsWindow.modeRow.mode:setCurrentOptionByData(settings.mode, true)
  settingsWindow.stripBox:setChecked(settings.strip, true)
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
    panX, panY = 0, 0
    applyStyle()
    overlay:show()
    overlay:raise()
    refresh()
    startTick()
    bindKeys()
    sendWatch(true)
  else
    stopTick()
    stopDrag()
    unbindKeys()
    panX, panY = 0, 0
    msgText = nil
    if overlay then overlay:hide() end
    if strip then strip:hide() end
    if youLabel then youLabel:hide() end
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

-- delta in zoom steps; cursor = screen point to zoom toward (only used while the map is panned)
function zoom(delta, cursor)
  local old = settings.zoom
  local z = S().clampZoom(old + (delta or 0))
  if z == old then
    flash(tr('Zoom %s', S().zoomLabel(z)))
    updateStrip()
    return
  end
  if cursor and anchor and S().isPanned(panX, panY) then
    setPan(S().zoomToward(panX, panY, old, z, cursor.x - anchor.x, cursor.y - anchor.y))
  end
  if drag then
    local m = g_window.getMousePosition()
    drag = { mx = m.x, my = m.y, px = panX, py = panY }
  end
  settings.zoom = z
  if mapWidget then mapWidget:setZoom(z) end
  saveSettings()
  updateSettingsWindow()
  flash(tr('Zoom %s', S().zoomLabel(z)))
  refresh()
end

function stepOpacity(delta)
  settings.opacity = S().stepOpacity(settings.opacity, delta)
  if mapWidget then mapWidget:setOpacity(settings.opacity) end
  saveSettings()
  updateSettingsWindow()
  flash(tr('Opacity %s', S().percent(settings.opacity)))
  updateStrip()
end

-- snaps the view back to the character
function centre()
  stopDrag()
  panX, panY = 0, 0
  if shown then
    flash(tr('Centred on your character'))
    refresh()
  end
end

function isPanned()
  return S().isPanned(panX, panY)
end

function setStrip(on)
  settings.strip = on and true or false
  saveSettings()
  updateSettingsWindow()
  placeStrip()
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
  panX, panY = 0, 0     -- a new run starts centred on the character
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
  local centreEntry = KeyBinds.Hotkeys['Minimap']['Map Overlay Centre'] or {}
  centreEntry.jsonName = S().CENTRE_ACTION
  centreEntry.bindKeyDown = function()
    if canPerformAction and not canPerformAction() then return end
    if shown then centre() end
  end
  KeyBinds.Hotkeys['Minimap']['Map Overlay Centre'] = centreEntry
end

-- the first time a hotkey set is seen, give the overlay its default key (see MapOverlayMath.assignDefaultKey)
local function assignDefaultKeys()
  if not (Options and Options.array and Options.array.hotkeyOptions) then return end
  local sets = Options.array.hotkeyOptions.hotkeySets
  if type(sets) ~= 'table' then return end
  local node = g_settings.getNode('mapOverlay') or {}
  local done = type(node.keySets) == 'table' and node.keySets or {}
  local doneCentre = type(node.centreSets) == 'table' and node.centreSets or {}
  local changed = false
  for name, set in pairs(sets) do
    if type(set) == 'table' and not done[name] then
      for _, chatType in ipairs({ 'chatOn', 'chatOff' }) do
        if S().assignDefaultKey(set[chatType]) and name == Options.currentHotkeySetName then changed = true end
      end
      done[name] = true
    end
    if type(set) == 'table' and not doneCentre[name] then
      for _, chatType in ipairs({ 'chatOn', 'chatOff' }) do
        local key = chatType == 'chatOn' and S().CENTRE_KEY_CHAT or S().CENTRE_KEY
        if S().assignKey(set[chatType], S().CENTRE_ACTION, key) and name == Options.currentHotkeySetName then
          changed = true
        end
      end
      doneCentre[name] = true
    end
  end
  node.keySets = done
  node.centreSets = doneCentre
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
  panX, panY = 0, 0
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
  -- made at load, not on the first open (the hotkey's callback)
  selfMark = g_ui.createWidget('MapOverlayMark', marksLayer)
  selfMark:hide()
  youLabel = g_ui.createWidget('MapOverlayYou', marksLayer)
  youLabel:hide()
  strip = g_ui.createWidget('MapOverlayStrip', mapPanel)
  strip.onMousePress = function() return true end      -- the strip takes the mouse, nothing reaches the game under it
  strip.onMouseRelease = function() return true end
  strip:hide()
  connect(mapPanel, { onMouseWheel = onWheel, onMousePress = onMousePress, onMouseRelease = onMouseRelease }, true)
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
  stopDrag()
  if wheelHooked then
    disconnect(wheelHooked, { onMouseWheel = onWheel, onMousePress = onMousePress, onMouseRelease = onMouseRelease })
    wheelHooked = false
  end
  if KeyBinds and KeyBinds.Hotkeys and KeyBinds.Hotkeys['Minimap'] then
    for _, name in ipairs({ 'Map Overlay', 'Map Overlay Centre' }) do
      local kb = KeyBind and KeyBind.getKeyBind and KeyBind:getKeyBind('Minimap', name)
      if kb and kb.deactive then pcall(function() kb:deactive() end) end
    end
  end
  if settingsWindow then settingsWindow:destroy() settingsWindow = nil end
  if strip then strip:destroy() strip = nil end
  if overlay then overlay:destroy() overlay = nil end
  markWidgets, selfMark, mapWidget, marksLayer, youLabel, stripTexts = {}, nil, nil, nil, nil, {}
  geoCache, overlayBox, shownMarks, lastPos = nil, nil, {}, nil
end
