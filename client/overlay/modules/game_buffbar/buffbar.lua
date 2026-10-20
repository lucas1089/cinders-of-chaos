-- Buff / debuff bar: the character's buffs and debuffs (red border) as small icons with a countdown and a stack count,
-- in a bar fixed under the character plate (game_chaoshud). Everything comes from the server (extended opcode 234,
-- server buffbar.lua and data/lib/chaos_buffs.lua: engine conditions, class buffs, world buffs, the Victory buff, world
-- events, trial stacks ...); the client draws them, counts the time down from the milliseconds it was sent, and asks for
-- a full list again when it starts or is shown. Hover an icon for its name, effect and time left; right click one for
-- the settings (countdown, show / hide).
-- Layout: anchored to the plate (left-aligned with its drawn edge, just below it), so it follows the plate wherever it
-- goes; not movable or resizable on its own. Icons flow left to right in rows as wide as the plate, buffs first, then
-- debuffs; a full row starts a new one below. No icons: hidden (no space, no clicks). Plate hidden: hidden too. No
-- plate module: the plate's own spot at the top-left of the game view. Settings in g_settings node 'chaosBuffBar'.
-- The pure parts are buffmath.lua (buffmath_test.lua). Menu: Character > Buff Bar (toggle).

local OPCODE = 234
local NODE = 'chaosBuffBar'
local PLATE_ID = 'chaosHud'
local BUFF_BORDER, DEBUFF_BORDER = '#b8923a', '#c9301f'

local bar, settingsWindow
local state = { buffs = {}, seq = 0 }
local settings = BuffMath.sanitize(nil)
local widgets = {}       -- key -> icon widget
local iconCache = {}     -- icon spec -> { src, clip }
local tickEvent
local layoutKey = ''     -- what the last layout was made for
local watching = false
local plate              -- the character plate the bar is anchored to (nil: no plate module)
local plateShown = true
local rowWidth = BuffMath.FALLBACK.width - BuffMath.PLATE.left - BuffMath.PLATE.right

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function now() return g_clock.seconds() end

-- ---------------------------------------------------------------- settings
local function loadSettings()
  local ok, node = pcall(g_settings.getNode, NODE)
  settings = BuffMath.sanitize(ok and node or nil)
end

local function saveSettings()
  pcall(g_settings.setNode, NODE, settings) -- only the known keys: an old saved position, size or lock is dropped
  pcall(g_settings.save)
end

-- ---------------------------------------------------------------- server
local function send(action)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = {} }))
  end
end

local function startWatching()
  if settings.shown and not watching and g_game.isOnline() then
    watching = true
    send('sync')
  end
end

local function stopWatching()
  if watching then
    watching = false
    send('off')
  end
end

-- ---------------------------------------------------------------- icons
-- the image of an icon spec: always our own 26 px icon (/images/game/buffs/<name>, BuffMath.ownName: "buff:<name>",
-- else the key's own icon; with "Painted icons" on, the painted one of that name when there is one); `key` names the
-- fallback. Also used by the party frames (modules.game_buffbar.iconFor), so the clip is always given.
local function paintedOn()
  local ok, v = pcall(g_settings.getBoolean, BuffMath.PAINTED_SETTING)
  return ok and v == true
end

local function fileExists(file)
  local ok, v = pcall(g_resources.fileExists, file)
  return ok and v == true
end

function iconFor(spec, key)
  spec = tostring(spec or '')
  key = key or 'spellbuff'
  local hit = iconCache[spec .. '|' .. key]
  if hit then return hit end
  local found = { src = BuffMath.iconPath(BuffMath.ownName(spec, key), paintedOn(), fileExists), clip = BuffMath.OWN_CLIP }
  iconCache[spec .. '|' .. key] = found
  return found
end

local function applyIcon(widget, entry)
  local icon = iconFor(entry.icon, entry.key)
  widget:setImageSource(icon.src)
  widget:setImageClip(icon.clip or BuffMath.OWN_CLIP)
end

-- the "Painted icons" setting (buff bar, spellbook, passive tree; g_settings, off by default). The bar redraws now;
-- the spellbook and the passive tree pick it up the next time they draw their icons.
function isPainted() return paintedOn() end

function setPainted(value)
  if paintedOn() == (value == true) then return end
  pcall(g_settings.set, BuffMath.PAINTED_SETTING, value == true)
  pcall(g_settings.save)
  iconCache = {}
  for key, w in pairs(widgets) do
    if alive(w) and state.buffs[key] then applyIcon(w, state.buffs[key]) end
  end
end

-- ---------------------------------------------------------------- layout
local relayout

local function iconWidget(entry)
  local w = widgets[entry.key]
  if not alive(w) then
    w = g_ui.createWidget('BuffBarIcon', bar)
    w:setId('buff_' .. entry.key)
    w.onMouseRelease = function(self, pos, button)
      if button == MouseRightButton then toggleSettings() return true end
      return false
    end
    widgets[entry.key] = w
  end
  return w
end

local function refreshWidget(w, entry, t)
  w:setBorderColor(entry.debuff and DEBUFF_BORDER or BUFF_BORDER)
  local timeLabel, countLabel = w:getChildById('time'), w:getChildById('count')
  local left = BuffMath.remaining(entry, t)
  if settings.timers and left then
    timeLabel:setText(BuffMath.format(left))
    timeLabel:setColor(left <= 5 and '#ff7a5a' or '#f2e8d0')
    timeLabel:setVisible(true)
  else
    timeLabel:setVisible(false)
  end
  if entry.stacks and entry.stacks > 0 then
    countLabel:setText(tostring(math.floor(entry.stacks)))
    countLabel:setVisible(true)
  else
    countLabel:setVisible(false)
  end
  w.tooltip = BuffMath.tooltip(entry, t)
end

local function updateVisibility()
  if not alive(bar) then return end
  local show = g_game.isOnline() and settings.shown and plateShown and BuffMath.count(state) > 0
  if bar:isExplicitlyVisible() ~= show then bar:setVisible(show) end
end

local function onPlateGeometry(widget, oldRect, newRect)
  if not alive(bar) or widget ~= plate then return end
  -- the anchors follow a plate moved by its margins; one moved by setPosition (anchors broken) needs a new layout pass
  local parent = bar:getParent()
  if parent then parent:updateLayout() end
  if newRect and oldRect and newRect.width ~= oldRect.width then relayout() end
end

local function onPlateVisibility(widget, visible)
  if widget ~= plate then return end
  plateShown = widget:isExplicitlyVisible()
  updateVisibility()
end

local function release()
  if alive(plate) then
    disconnect(plate, { onGeometryChange = onPlateGeometry, onVisibilityChange = onPlateVisibility })
  end
  plate = nil
end

-- anchors the bar to the plate (or to the plate's spot when there is none); again when the plate widget is replaced
local function attach()
  if not alive(bar) then return end
  local parent = bar:getParent()
  local found = parent and parent:getChildById(PLATE_ID)
  if found and found == plate and alive(plate) then return end
  release()
  bar:breakAnchors()
  if found then
    plate = found
    local r = plate:getRect()
    local spot = BuffMath.attach({ x = r.x, y = r.y, width = plate:getWidth(), height = plate:getHeight(),
      visible = plate:isExplicitlyVisible() })
    bar:addAnchor(AnchorTop, PLATE_ID, AnchorTop)
    bar:addAnchor(AnchorLeft, PLATE_ID, AnchorLeft)
    bar:setMarginTop(spot.y - r.y)
    bar:setMarginLeft(spot.x - r.x)
    rowWidth, plateShown = spot.width, spot.shown
    connect(plate, { onGeometryChange = onPlateGeometry, onVisibilityChange = onPlateVisibility })
  else
    local spot = BuffMath.attach(nil, { x = 0, y = 0 })
    bar:addAnchor(AnchorTop, 'parent', AnchorTop)
    bar:addAnchor(AnchorLeft, parent and parent:getChildById('gameMapPanel') and 'gameMapPanel' or 'parent', AnchorLeft)
    bar:setMarginTop(spot.y)
    bar:setMarginLeft(spot.x)
    rowWidth, plateShown = spot.width, spot.shown
  end
  layoutKey = nil
end

relayout = function()
  if not alive(bar) then return end
  attach()
  local t = now()
  local list = BuffMath.ordered(state)
  local size, gap = BuffMath.ICON_SIZE, BuffMath.GAP
  if alive(plate) then rowWidth = BuffMath.attach({ x = 0, y = 0, width = plate:getWidth(), height = 0 }).width end
  local cells, rows, height = BuffMath.flow(#list, rowWidth, size, gap)
  local keep = {}
  for i, e in ipairs(list) do
    local w = iconWidget(e)
    keep[e.key] = true
    refreshWidget(w, e, t)
    applyIcon(w, e)
    w:setMarginLeft(cells[i].x)
    w:setMarginTop(cells[i].y)
  end
  for key, w in pairs(widgets) do
    if not keep[key] then
      if alive(w) then w:destroy() end
      widgets[key] = nil
    end
  end
  bar:setSize({ width = rowWidth, height = math.max(1, height) })
  layoutKey = BuffMath.orderKey(list) .. '|' .. rowWidth
  updateVisibility()
end

local function tick()
  if not alive(bar) then return end
  if not g_game.isOnline() then return end
  attach() -- the plate module may have been reloaded
  local t = now()
  local pruned = BuffMath.prune(state, t)
  local list = BuffMath.ordered(state)
  if pruned > 0 or BuffMath.orderKey(list) .. '|' .. rowWidth ~= layoutKey then
    relayout()
  else
    for _, e in ipairs(list) do
      local w = widgets[e.key]
      if alive(w) then refreshWidget(w, e, t) end
    end
  end
  updateVisibility()
end

-- ---------------------------------------------------------------- opcode
local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then return end
  if BuffMath.apply(state, msg.action, msg.data, now()) then
    relayout()
  end
end

-- ---------------------------------------------------------------- settings window
local function syncSettingsWindow()
  if not alive(settingsWindow) then return end
  settingsWindow:recursiveGetChildById('shownBox'):setChecked(settings.shown)
  settingsWindow:recursiveGetChildById('timersBox'):setChecked(settings.timers)
  settingsWindow:recursiveGetChildById('paintedBox'):setChecked(paintedOn())
end

function toggleSettings()
  if not alive(settingsWindow) then
    settingsWindow = g_ui.createWidget('BuffBarSettings', g_ui.getRootWidget())
    settingsWindow:hide()
  end
  if settingsWindow:isVisible() then
    settingsWindow:hide()
  else
    syncSettingsWindow()
    settingsWindow:show()
    settingsWindow:raise()
    settingsWindow:focus()
  end
end

function setOption(name, value)
  if settings[name] == nil or settings[name] == value then return end
  settings[name] = value
  saveSettings()
  if name == 'shown' then
    if value then startWatching() else stopWatching() BuffMath.clear(state) end
  end
  relayout()
end

-- menu entry: shows / hides the bar (it also hides by itself while there is nothing to show, so say what happened)
function toggle()
  setOption('shown', not settings.shown)
  syncSettingsWindow()
  local tm = modules.game_textmessage
  if tm and type(tm.displayStatusMessage) == 'function' then
    pcall(tm.displayStatusMessage, settings.shown and tr('Buff bar on.') or tr('Buff bar off.'))
  end
end

function isShown() return settings.shown end

-- the names (lowercase) of the buffs on the character, or nil when the server's list has not come (bar hidden): for the
-- helper's Support spells (game_helpersupport)
function activeBuffs() return BuffMath.activeNames(state, now()) end

-- ---------------------------------------------------------------- lifecycle
local function onGameStart()
  BuffMath.clear(state)
  watching = false
  relayout()
  scheduleEvent(function() startWatching() end, 300)
end

local function onGameEnd()
  watching = false
  BuffMath.clear(state)
  relayout()
  if alive(bar) then bar:hide() end
end

function init()
  g_ui.importStyle('buffbar')
  loadSettings()
  saveSettings() -- drops an old saved position, size, icons per row and lock
  -- next to the plate in the game root panel, so it can be anchored to it
  bar = g_ui.createWidget('BuffBar', modules.game_interface.getRootPanel())
  bar:hide()
  attach()
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  tickEvent = cycleEvent(tick, 250)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  stopWatching()
  release()
  for _, w in pairs(widgets) do if alive(w) then w:destroy() end end
  widgets = {}
  if alive(settingsWindow) then settingsWindow:destroy() end
  if alive(bar) then bar:destroy() end
  bar, settingsWindow = nil, nil
end
