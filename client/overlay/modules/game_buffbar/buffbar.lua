-- Buff / debuff bar: the character's buffs on a row of small icons with a countdown and a stack count, its debuffs
-- (red border) on a row below. Everything comes from the server (extended opcode 234, server buffbar.lua and
-- data/lib/chaos_buffs.lua: engine conditions, class buffs, world buffs, the Victory buff, world events, trial stacks ...);
-- the client draws them, counts the time down from the milliseconds it was sent, and asks for a full list again when it
-- starts or is shown. Hover an icon for its name, effect and time left.
-- Movable (grab the strip above the icons), scale, icons per row, lock, show / hide, countdown and hide-when-empty are in
-- the gear window; they are saved in g_settings node 'chaosBuffBar'. The pure parts are buffmath.lua (buffmath_test.lua).
-- Menu: Character > Buff Bar (toggle).

local OPCODE = 234
local NODE = 'chaosBuffBar'
local DEFAULT_X, DEFAULT_Y = 335, 124 -- the margins of the style: right of the character plate
local GAP, HEADER, PAD = 2, 10, 3
local BUFF_BORDER, DEBUFF_BORDER = '#b8923a', '#c9301f'

local bar, settingsWindow
local state = { buffs = {}, seq = 0 }
local settings = BuffMath.sanitize(nil)
local widgets = {}       -- key -> icon widget
local iconCache = {}     -- icon spec -> { src, clip }
local tickEvent
local dragOffset
local layoutKey = ''     -- what the last layout was made for
local watching = false

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
  pcall(g_settings.setNode, NODE, settings)
  pcall(g_settings.save) -- a client that crashes or is killed keeps the position too
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
-- the image of an icon spec ("spell:<words>", "cond:<NN>", "buff:<name>"); `key` names the fallback. Also used by the
-- party frames (modules.game_buffbar.iconFor).
function iconFor(spec, key)
  spec = tostring(spec or '')
  key = key or 'spellbuff'
  local hit = iconCache[spec .. '|' .. key]
  if hit then return hit end
  local kind, arg = BuffMath.parseIcon(spec)
  local found
  if kind == 'spell' and Spells and Spells.getSpellIcon then
    local ok, folder, clip = pcall(Spells.getSpellIcon, arg)
    if ok and folder and clip then found = { src = folder, clip = clip } end
  elseif kind == 'cond' then
    local path = BuffMath.condPath(arg)
    if path and g_resources.fileExists(path .. '.png') then found = { src = path } end
  elseif kind == 'buff' then
    local path = BuffMath.ownPath(arg)
    if path then found = { src = path } end
  end
  if not found then found = { src = BuffMath.ownPath(key) or '/images/game/buffs/spellbuff' } end
  iconCache[spec .. '|' .. key] = found
  return found
end

local function applyIcon(widget, entry)
  local icon = iconFor(entry.icon, entry.key)
  widget:setImageSource(icon.src)
  if icon.clip then widget:setImageClip(icon.clip) else widget:setImageClip('0 0 32 32') end
end

-- ---------------------------------------------------------------- layout
local function iconWidget(entry)
  local w = widgets[entry.key]
  if not alive(w) then
    w = g_ui.createWidget('BuffBarIcon', bar)
    w:setId('buff_' .. entry.key)
    widgets[entry.key] = w
  end
  return w
end

local function refreshWidget(w, entry, t)
  local size = BuffMath.iconSize(settings.scale)
  w:setSize({ width = size, height = size })
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

local function place(w, x, y)
  w:addAnchor(AnchorTop, 'parent', AnchorTop)
  w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  w:setMarginLeft(x)
  w:setMarginTop(y)
end

local function relayout()
  if not alive(bar) then return end
  local t = now()
  local buffs, debuffs = BuffMath.rows(state)
  local size = BuffMath.iconSize(settings.scale)
  local keep = {}
  local y0 = HEADER + PAD
  local cells, w1, h1 = BuffMath.grid(#buffs, settings.perRow, size, GAP, PAD, y0)
  local rowGap = (#buffs > 0 and #debuffs > 0) and 3 or 0
  local cells2, w2, h2 = BuffMath.grid(#debuffs, settings.perRow, size, GAP, PAD, y0 + (h1 > 0 and h1 + GAP or 0) + rowGap)
  for i, e in ipairs(buffs) do
    local w = iconWidget(e)
    keep[e.key] = true
    refreshWidget(w, e, t)
    applyIcon(w, e)
    place(w, cells[i].x, cells[i].y)
  end
  for i, e in ipairs(debuffs) do
    local w = iconWidget(e)
    keep[e.key] = true
    refreshWidget(w, e, t)
    applyIcon(w, e)
    place(w, cells2[i].x, cells2[i].y)
  end
  for key, w in pairs(widgets) do
    if not keep[key] then
      if alive(w) then w:destroy() end
      widgets[key] = nil
    end
  end
  local empty = BuffMath.count(state) == 0
  local emptyLabel = bar:getChildById('empty')
  emptyLabel:setVisible(empty)
  local width = math.max(w1, w2, empty and 96 or 0, 58) + PAD * 2
  local height = y0 + (h1 > 0 and h1 or 0) + ((h2 > 0) and (h2 + (h1 > 0 and GAP + rowGap or 0)) or 0) + PAD
  if empty then height = y0 + 14 + PAD end
  bar:setSize({ width = width, height = height })
  layoutKey = ''
  for _, e in ipairs(buffs) do layoutKey = layoutKey .. e.key .. ',' end
  layoutKey = layoutKey .. '|'
  for _, e in ipairs(debuffs) do layoutKey = layoutKey .. e.key .. ',' end
end

local function updateVisibility()
  if not alive(bar) then return end
  local empty = BuffMath.count(state) == 0
  local previewing = alive(settingsWindow) and settingsWindow:isVisible()
  local show = g_game.isOnline() and settings.shown and (not (empty and settings.hideEmpty) or previewing)
  bar:setVisible(show)
end

-- keeps the bar inside the game panel (the window may have been made smaller)
local function clampBar()
  if not alive(bar) then return end
  if dragOffset then return end -- the hand is moving it
  local parent = bar:getParent()
  if not parent then return end
  local x = settings.x or DEFAULT_X
  local y = settings.y or DEFAULT_Y
  x, y = BuffMath.clampPosition(x, y, bar:getWidth(), bar:getHeight(), parent:getWidth(), parent:getHeight())
  bar:setMarginLeft(x)
  bar:setMarginTop(y)
end

local function tick()
  if not alive(bar) then return end
  if not g_game.isOnline() then return end
  local t = now()
  local pruned = BuffMath.prune(state, t)
  local buffs, debuffs = BuffMath.rows(state)
  local key = ''
  for _, e in ipairs(buffs) do key = key .. e.key .. ',' end
  key = key .. '|'
  for _, e in ipairs(debuffs) do key = key .. e.key .. ',' end
  if pruned > 0 or key ~= layoutKey then
    relayout()
  else
    for _, list in ipairs({ buffs, debuffs }) do
      for _, e in ipairs(list) do
        local w = widgets[e.key]
        if alive(w) then refreshWidget(w, e, t) end
      end
    end
  end
  updateVisibility()
  clampBar()
end

-- ---------------------------------------------------------------- opcode
local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then return end
  if BuffMath.apply(state, msg.action, msg.data, now()) then
    relayout()
    updateVisibility()
  end
end

-- ---------------------------------------------------------------- settings window
local function syncSettingsWindow()
  if not alive(settingsWindow) then return end
  settingsWindow:recursiveGetChildById('scaleValue'):setText(settings.scale .. '%')
  settingsWindow:recursiveGetChildById('rowValue'):setText(tostring(settings.perRow))
  settingsWindow:recursiveGetChildById('shownBox'):setChecked(settings.shown)
  settingsWindow:recursiveGetChildById('lockBox'):setChecked(settings.locked)
  settingsWindow:recursiveGetChildById('timersBox'):setChecked(settings.timers)
  settingsWindow:recursiveGetChildById('hideBox'):setChecked(settings.hideEmpty)
end

function toggleSettings()
  if not alive(settingsWindow) then
    settingsWindow = g_ui.createWidget('BuffBarSettings', g_ui.getRootWidget())
    settingsWindow.onVisibilityChange = function() updateVisibility() end
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
  updateVisibility()
end

function stepScale(dir)
  settings.scale = BuffMath.stepScale(settings.scale, dir)
  saveSettings()
  syncSettingsWindow()
  relayout()
  clampBar()
end

function stepPerRow(dir)
  settings.perRow = math.max(BuffMath.PER_ROW_MIN, math.min(BuffMath.PER_ROW_MAX, settings.perRow + dir))
  saveSettings()
  syncSettingsWindow()
  relayout()
  clampBar()
end

function setOption(name, value)
  if settings[name] == nil or settings[name] == value then return end
  settings[name] = value
  saveSettings()
  if name == 'shown' then
    if value then startWatching() else stopWatching() BuffMath.clear(state) relayout() end
  end
  updateVisibility()
  relayout()
end

function resetPosition()
  settings.x, settings.y = nil, nil
  saveSettings()
  if alive(bar) then
    bar:setMarginLeft(DEFAULT_X)
    bar:setMarginTop(DEFAULT_Y)
  end
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

-- ---------------------------------------------------------------- dragging
local function onHeaderPress(w, pos, button)
  if button ~= MouseLeftButton or settings.locked then return false end
  dragOffset = { x = pos.x - bar:getX(), y = pos.y - bar:getY() }
  w:grabMouse()
  return true
end

local function onHeaderMove(w, pos, moved)
  if not dragOffset then return false end
  local parent = bar:getParent()
  local x = pos.x - dragOffset.x - parent:getX()
  local y = pos.y - dragOffset.y - parent:getY()
  x, y = BuffMath.clampPosition(x, y, bar:getWidth(), bar:getHeight(), parent:getWidth(), parent:getHeight())
  bar:setMarginLeft(x)
  bar:setMarginTop(y)
  return true
end

local function onHeaderRelease(w, pos, button)
  if not dragOffset then return false end
  dragOffset = nil
  w:ungrabMouse()
  local parent = bar:getParent()
  settings.x = bar:getX() - parent:getX()
  settings.y = bar:getY() - parent:getY()
  saveSettings()
  return true
end

-- ---------------------------------------------------------------- lifecycle
local function onGameStart()
  BuffMath.clear(state)
  watching = false
  relayout()
  clampBar()
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
  local parent = modules.game_interface.getMapPanel()
  bar = g_ui.createWidget('BuffBar', parent)
  local header = bar:getChildById('header')
  header.onMousePress = onHeaderPress
  header.onMouseMove = onHeaderMove
  header.onMouseRelease = onHeaderRelease
  bar:hide()
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
  for _, w in pairs(widgets) do if alive(w) then w:destroy() end end
  widgets = {}
  if alive(settingsWindow) then settingsWindow:destroy() end
  if alive(bar) then bar:destroy() end
  bar, settingsWindow = nil, nil
end
