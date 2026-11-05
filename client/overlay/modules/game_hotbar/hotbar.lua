-- game_hotbar: the central hotbar of the action bar layout (client/MANIFEST.md "Floating chat and central hotbar (O414)";
-- rules in hotbar_logic.lua, tested by hotbar_test.lua, art from tools/gen_hotbar_art.py).
-- * The first bottom action bar of game_actionbar is adopted, not rewritten: its widget moves into the bar's frame, its
--   buttons are resized, their order changed with moveChildToIndex (nothing leaves its parent), and the part of the row
--   that is not shown is clipped. Hotkeys, spells, items, assign, drag and cooldowns stay the base module's own.
--   Slots 1..count are the main row (6, 8, 10 or 12); slots 13 and 14 sit in the round sockets (Q potion, E utility).
-- * Each slot gets our frame under it (green when it holds something that is ready), a big cooldown number over it
--   and a key label box under it. A line above the bar shows the last loot or level event for 5 seconds.
-- * The health and mana globes of game_shaderfx dock into the bar's end caps (option, default on); off: closed caps.
-- * Scale 75-125%, slot count, globes and place are kept per character (node chaos_hotbar). A window too small for
--   the wanted bar gets a smaller bar (HotbarLogic.fit). The bar is moved by its handle; double-click: the centre.
-- Only runs in the action bar layout (ChaosLayoutMode, decided at login); phones never.
ChaosHotbar = ChaosHotbar or {}
local M = ChaosHotbar
local L = HotbarLogic

local TICK_MS = 100
local ADOPT_RETRY_MS, ADOPT_TRIES = 300, 70

local frame
local active = false
local settings = L.settingsFor(nil, nil)
local character
local fitted, metrics, placed
local bar, slotParent, buttons, plan
local parts = {}              -- widgets made per layout: slot frames, key boxes, cooldown labels
local cells = {}              -- { kind = 'slot' | 'potion' | 'utility', button, frame, key, cd, readyShown, keyText, cdText }
local tickEvent, adoptEvent
local eventLine = {}
local drag
local lastRoot = nil
local chatListener

local function now() return g_clock.millis() end
local function alive(w) return w ~= nil and not w:isDestroyed() end

local function root()
  local gi = modules.game_interface
  return gi and gi.getRootPanel and gi.getRootPanel() or nil
end

-- the game area between the side panels
local function region()
  local r = root()
  local rect = r:getRect()
  local left, right = rect.x, rect.x + rect.width
  local lp, rp = r:getChildById('gameLeftPanels'), r:getChildById('gameRightPanels')
  if lp and lp:isVisible() and lp:getWidth() > 0 then left = math.max(left, lp:getX() + lp:getWidth()) end
  if rp and rp:isVisible() and rp:getWidth() > 0 then right = math.min(right, rp:getX()) end
  return left, right, rect
end

-- ---------------------------------------------------------------- finding the base bar
local function slotsOf(w, out)
  for _, child in ipairs(w:getChildren()) do
    local ok, cd = pcall(function() return child.cooldown end)
    if ok and cd ~= nil then out[#out + 1] = child else slotsOf(child, out) end
  end
  return out
end

-- the first bottom action bar: the child of gameBottomActionPanel that holds at least 6 slot buttons
local function findBar()
  local r = root()
  local panel = r and r:getChildById('gameBottomActionPanel')
  if not panel then return nil end
  for _, child in ipairs(panel:getChildren()) do
    if child:isVisible() then
      local list = slotsOf(child, {})
      if #list >= 6 then return child, list end
    end
  end
end

local function hotkeyOf(b)
  local ok, v = pcall(function()
    if type(b.hotkey) == 'string' then return b.hotkey end
    local label = b:getChildById('text') or b:getChildById('hotkey') or b.hotkeyLabel
    if label and label.getText then
      if label.isVisible and label:isVisible() and label.setVisible then label:setVisible(false) end -- our key box shows it
      return label:getText()
    end
    return ''
  end)
  return ok and tostring(v or '') or ''
end

local function hasAction(b)
  local ok, v = pcall(function()
    return b.words ~= nil or b.spellId ~= nil or b.itemId ~= nil or b.actionType ~= nil
      or (b.getItemId and b:getItemId() or 0) > 0
  end)
  return ok and v == true
end

local function cooldownOf(b)
  local ok, d, e = pcall(function() return b.cooldown:getDuration(), b.cooldown:getTimeElapsed() end)
  if ok then return d, e end
  return 0, 0
end

-- ---------------------------------------------------------------- the layout
local function clearParts()
  for _, w in ipairs(parts) do if alive(w) then w:destroy() end end
  parts, cells = {}, {}
end

local function part(style, parent, x, y, w, h)
  local widget = g_ui.createWidget(style, parent or frame)
  widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  widget:addAnchor(AnchorTop, 'parent', AnchorTop)
  widget:setMarginLeft(x)
  widget:setMarginTop(y)
  if w then widget:setSize({ width = w, height = h or w }) end
  parts[#parts + 1] = widget
  return widget
end

-- the base row restyled for the current metrics: sizes, margins, spacing and the order [potion][1..count][utility][rest]
local function styleRow()
  local m = metrics
  local pad = math.floor((m.slot - m.button) / 2)
  local extra = math.max(0, m.socketGap - m.gap)
  plan = L.slotPlan(#buttons, m.count)
  local layout = slotParent.getLayout and slotParent:getLayout()
  if layout and layout.setSpacing then pcall(layout.setSpacing, layout, m.gap) end
  local order, used = {}, {}
  local function add(i)
    if i and buttons[i] and not used[i] then order[#order + 1] = buttons[i] used[i] = true end
  end
  add(plan.potion)
  for _, i in ipairs(plan.shown) do add(i) end
  add(plan.utility)
  for i = 1, #buttons do add(i) end
  for index, b in ipairs(order) do
    pcall(slotParent.moveChildToIndex, slotParent, b, index)
    b:setSize({ width = m.button, height = m.button })
    b:setMarginLeft(pad)
    b:setMarginRight(pad)
    b:setMarginTop(0)
    b:setMarginBottom(0)
  end
  if plan.potion then buttons[plan.potion]:setMarginRight(pad + extra) end
  if plan.utility then buttons[plan.utility]:setMarginLeft(pad + extra) end
  return order
end

local function adopt()
  local found, list = findBar()
  if not found then return false end
  bar, buttons = found, list
  slotParent = buttons[1]:getParent()
  return true
end

local function buildParts()
  clearParts()
  local m = metrics
  local order = styleRow()
  -- frames first (under the base row), then the row, then the numbers and key boxes over it
  local frames = {}
  local function cellFrame(kind, x, art)
    local f = part('ChaosHotbarPart', frame, x, m.slotY, m.slot, m.slot)
    f:setImageSource(art)
    frames[#frames + 1] = f
    return f
  end
  local layout = {}
  if plan.potion then layout[#layout + 1] = { kind = 'potion', x = m.socketLX, art = '/modules/game_hotbar/images/hotbar_socket', index = plan.potion } end
  for n, i in ipairs(plan.shown) do
    layout[#layout + 1] = { kind = 'slot', x = m.slotsX + (n - 1) * m.pitch, art = '/modules/game_hotbar/images/hotbar_slot', index = i }
  end
  if plan.utility then layout[#layout + 1] = { kind = 'utility', x = m.socketRX, art = '/modules/game_hotbar/images/hotbar_socket', index = plan.utility } end
  for _, c in ipairs(layout) do c.frame = cellFrame(c.kind, c.x, c.art) end
  -- the base bar over the frames (a rebuild makes new frames after it: raise it again)
  if bar:getParent() ~= frame then bar:setParent(frame) end
  bar:raise()
  bar:breakAnchors()
  bar:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  bar:addAnchor(AnchorTop, 'parent', AnchorTop)
  local rowLeft = plan.potion and m.socketLX or m.slotsX
  local rowRight = plan.utility and (m.socketRX + m.socket) or (m.slotsX + m.cellsW)
  bar:setMarginLeft(rowLeft)
  bar:setMarginTop(m.slotY + math.floor((m.slot - m.button) / 2))
  bar:setSize({ width = rowRight - rowLeft, height = m.button })
  pcall(bar.setClipping, bar, true)
  if slotParent ~= bar then
    slotParent:breakAnchors()
    slotParent:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    slotParent:addAnchor(AnchorTop, 'parent', AnchorTop)
    slotParent:setMarginLeft(0)
    slotParent:setMarginTop(0)
    slotParent:setHeight(m.button)
    for _, child in ipairs(bar:getChildren()) do -- the lock column, tabs and arrows of the base bar are not part of the look
      if child ~= slotParent then child:setVisible(false) end
    end
  end
  for _, c in ipairs(layout) do
    c.button = buttons[c.index]
    c.key = part('ChaosHotbarKey', frame, c.x + math.floor((m.slot - m.keyW) / 2), m.keyY, m.keyW, m.keyH)
    c.cd = part('ChaosHotbarCooldown', frame, c.x, m.slotY, m.slot, m.slot)
    cells[#cells + 1] = c
  end
  return true
end

-- the pieces of the frame that do not depend on the slots
local function layoutFrame()
  local m = metrics
  local cap = function(id, closedArt, openArt)
    local w = frame:getChildById(id)
    w:setSize({ width = m.capW, height = m.bodyH })
    w:setImageSource(m.globes and openArt or closedArt)
    w:setVisible(true)
  end
  cap('capL', '/modules/game_hotbar/images/hotbar_cap_closed_l', '/modules/game_hotbar/images/hotbar_cap_open_l')
  cap('capR', '/modules/game_hotbar/images/hotbar_cap_closed_r', '/modules/game_hotbar/images/hotbar_cap_open_r')
  -- with globes the cap is as wide as the globe: its open bracket art is the narrow inner side only
  if m.globes then
    for _, id in ipairs({ 'capL', 'capR' }) do
      local w = frame:getChildById(id)
      w:setWidth(math.floor(L.CAP_OPEN_W * m.scale / 100 + 0.5))
      w:setMarginLeft(id == 'capL' and (m.capW - w:getWidth()) or 0)
      w:setMarginRight(id == 'capR' and (m.capW - w:getWidth()) or 0)
    end
  else
    frame:getChildById('capL'):setMarginLeft(0)
    frame:getChildById('capR'):setMarginRight(0)
  end
  local body = frame:getChildById('body')
  body:setHeight(m.bodyH)
  frame:getChildById('socketL'):setVisible(false) -- the sockets are the slot frames of buildParts
  frame:getChildById('socketR'):setVisible(false)
  local line = frame:getChildById('line')
  line:setMarginBottom(2)
  local chat = frame:getChildById('chatButton')
  local gear = frame:getChildById('gearButton')
  for i, b in ipairs({ chat, gear }) do
    b:breakAnchors()
    b:addAnchor(AnchorRight, 'parent', AnchorRight)
    b:addAnchor(AnchorTop, 'parent', AnchorTop)
    b:setMarginRight(m.capW + m.pad + (i == 1 and 26 or 0))
    b:setMarginTop(m.bodyTop - 8)
    b:raise()
  end
  local dot = frame:getChildById('chatDot')
  dot:breakAnchors()
  dot:addAnchor(AnchorRight, 'chatButton', AnchorRight)
  dot:addAnchor(AnchorTop, 'chatButton', AnchorTop)
  dot:setMarginRight(-2)
  dot:setMarginTop(-2)
  dot:raise()
  frame:getChildById('handle'):raise()
end

local function applyOrbs()
  local fx = modules.game_shaderfx
  if not fx or type(fx.setOrbDock) ~= 'function' then return end
  if metrics.globes then pcall(fx.setOrbDock, metrics.orb, false) else pcall(fx.setOrbDock, nil, true) end
end

local function placeFrame()
  if not alive(frame) then return end
  local left, right, rect = region()
  placed = L.place({ regionLeft = left, regionRight = right, width = metrics.width, height = metrics.height,
                     x = settings.x and (settings.x) or nil, lift = settings.lift, windowHeight = rect.y + rect.height })
  frame:setSize({ width = metrics.width, height = metrics.height })
  frame:setMarginLeft(placed.left - rect.x)
  frame:setMarginBottom(placed.bottom)
end

-- the bottom area of the classic layout makes way: the map takes the height
local function collapseBottom()
  local r = root()
  if not r then return end
  local s = r:getChildById('bottomSplitter')
  if s then
    s:setMarginBottom(0)
    pcall(s.setHeight, s, 1)
    pcall(s.setPhantom, s, true)
  end
  local bottom = r:getChildById('gameBottomPanel')
  if bottom then bottom:setVisible(false) end -- the console moved into game_floatchat
  local ab = r:getChildById('gameBottomActionPanel')
  if ab then
    local others = false
    for _, child in ipairs(ab:getChildren()) do
      if child ~= bar and child:isVisible() and #slotsOf(child, {}) >= 1 then others = true end
    end
    if others then -- more bottom bars are on: they sit just above the hotbar
      ab:breakAnchors()
      ab:addAnchor(AnchorBottom, 'chaosHotbar', AnchorTop)
      ab:addAnchor(AnchorHorizontalCenter, 'chaosHotbar', AnchorHorizontalCenter)
      ab:setMarginBottom(4)
    else
      ab:setVisible(false)
    end
  end
end

-- (re)build everything for the current settings and window
function M.relayout()
  if not active or not alive(frame) or not bar then return end
  local left, right = region()
  local opts, _, m = L.fit({ count = settings.count, scale = settings.scale, globes = settings.globes }, right - left - 16)
  fitted, metrics = opts, m
  frame:setSize({ width = m.width, height = m.height })
  layoutFrame()
  buildParts()
  placeFrame()
  applyOrbs()
  for _, c in ipairs(cells) do c.readyShown, c.keyText, c.cdText = nil, nil, nil end
end

-- ---------------------------------------------------------------- the tick
local function tick()
  tickEvent = nil
  if not active or not alive(frame) then return end
  for _, c in ipairs(cells) do
    if alive(c.button) then
      local d, e = cooldownOf(c.button)
      local text = L.cooldown(d, e)
      if text ~= c.cdText then
        c.cdText = text
        c.cd:setText(text)
        c.cd:setVisible(text ~= '')
      end
      local ready = c.kind == 'slot' and text == '' and hasAction(c.button)
      if ready ~= c.readyShown and c.kind == 'slot' then
        c.readyShown = ready
        c.frame:setImageSource('/modules/game_hotbar/images/' .. (ready and 'hotbar_slot_ready' or 'hotbar_slot'))
      end
      local key = L.keyLabel(hotkeyOf(c.button), c.kind ~= 'slot' and c.kind or nil)
      if key ~= c.keyText then
        c.keyText = key
        c.key:getChildById('text'):setText(key)
        c.key:setVisible(key ~= '')
      end
    end
  end
  local line = frame:getChildById('line')
  local text, alpha = L.eventLine(eventLine, now())
  line:setVisible(text ~= '')
  if text ~= '' then
    line:setText(text)
    line:setOpacity(alpha)
  end
  local fc = rawget(_G, 'ChaosFloatChat')
  local dot = frame:getChildById('chatDot')
  local unread = fc and fc.isHidden and fc.isHidden() and fc.getUnread and fc.getUnread() or 0
  dot:setVisible(unread > 0)
  tickEvent = scheduleEvent(tick, TICK_MS)
end

local function onTextMessage(mode, text)
  local e = L.eventFromMessage(text)
  if e then eventLine = L.pushEvent(eventLine, e, now()) end
end

-- ---------------------------------------------------------------- settings
local function save()
  if not character then return end
  local node = g_settings.getNode(L.NODE) or {}
  pcall(g_settings.setNode, L.NODE, L.store(node, character, settings))
  pcall(g_settings.save)
end

function M.getSettings()
  return { count = settings.count, scale = settings.scale, globes = settings.globes }
end

function M.isActive() return active end
function M.getWidget() return alive(frame) and active and frame:isVisible() and frame or nil end
function M.getRect()
  if not active or not alive(frame) or not frame:isVisible() then return nil end
  return frame:getRect()
end

-- key: count, scale, globes (the layout options window and the right-click menu)
function M.setOption(key, value)
  if key == 'count' then settings.count = L.clampCount(value)
  elseif key == 'scale' then settings.scale = L.clampScale(value)
  elseif key == 'globes' then settings.globes = value == true
  else return end
  save()
  M.relayout()
end

function M.resetPlace()
  settings.x, settings.lift = nil, 0
  placeFrame()
  save()
end

-- ---------------------------------------------------------------- the handle and the right-click menu
local function showMenu()
  local menu = g_ui.createWidget('PopupMenu')
  local fc = rawget(_G, 'ChaosFloatChat')
  if fc and fc.toggle then
    menu:addOption(fc.isHidden and fc.isHidden() and tr('Show the chat') or tr('Hide the chat'), function() fc.toggle() end)
  end
  menu:addOption(settings.globes and tr('Hide the health and mana globes') or tr('Show the health and mana globes'),
    function() M.setOption('globes', not settings.globes) end)
  menu:addSeparator()
  for _, c in ipairs(L.COUNTS) do
    menu:addOption((settings.count == c and '> ' or '') .. tr('%d slots', c), function() M.setOption('count', c) end)
  end
  menu:addSeparator()
  menu:addOption(tr('Bigger bar'), function() M.setOption('scale', settings.scale + L.SCALE_STEP) end)
  menu:addOption(tr('Smaller bar'), function() M.setOption('scale', settings.scale - L.SCALE_STEP) end)
  menu:addOption(tr('Back to the centre'), function() M.resetPlace() end)
  menu:addSeparator()
  menu:addOption(tr('Layout options...'), function() local o = rawget(_G, 'ChaosLayoutOptions') if o then o.open() end end)
  menu:display(g_window.getMousePosition())
end

local function wireFrame()
  local handle = frame:getChildById('handle')
  handle.onMousePress = function(_, pos, button)
    if button ~= MouseLeftButton then return false end
    drag = { start = { left = placed.left, lift = placed.lift, mouseX = pos.x, mouseY = pos.y } }
    return true
  end
  handle.onMouseMove = function(_, pos)
    if not drag then return false end
    local left = region()
    local x, lift = L.dragPlace(drag.start, pos.x, pos.y, left)
    settings.x, settings.lift = x, lift
    placeFrame()
    return true
  end
  handle.onMouseRelease = function()
    if drag then
      drag = nil
      settings.x, settings.lift = L.snap(placed)
      placeFrame()
      save()
    end
    return true
  end
  handle.onDoubleClick = function() M.resetPlace() return true end
  frame.onMouseRelease = function(_, pos, button)
    if button == MouseRightButton then showMenu() return true end
    return false
  end
  frame:getChildById('chatButton').onClick = function()
    local fc = rawget(_G, 'ChaosFloatChat')
    if fc and fc.toggle then fc.toggle() end
  end
  frame:getChildById('gearButton').onClick = function()
    local o = rawget(_G, 'ChaosLayoutOptions')
    if o and o.open then o.open() end
  end
end

-- ---------------------------------------------------------------- start and stop
local function tryAdopt(tries)
  adoptEvent = nil
  if not active then return end
  if adopt() then
    collapseBottom()
    M.relayout()
    collapseBottom()
    tick()
    return
  end
  if tries < ADOPT_TRIES then
    adoptEvent = scheduleEvent(function() tryAdopt(tries + 1) end, ADOPT_RETRY_MS)
  else
    g_logger.warning('[hotbar] no action bar found: the central hotbar stays off')
  end
end

local function enable()
  if active then return end
  local r = root()
  if not r or not g_game.isOnline() then return end
  g_ui.importStyle('hotbar')
  local player = g_game.getLocalPlayer()
  character = player and player:getName() or nil
  settings = L.settingsFor(g_settings.getNode(L.NODE), character)
  frame = g_ui.createWidget('ChaosHotbar', r)
  frame:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  frame:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  frame:setSize({ width = 200, height = 100 })
  wireFrame()
  active = true
  eventLine = {}
  connect(g_game, { onTextMessage = onTextMessage })
  tryAdopt(0)
end

local function disable()
  if not active and not frame then return end
  if active then save() end
  active = false
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  if adoptEvent then removeEvent(adoptEvent) adoptEvent = nil end
  pcall(disconnect, g_game, { onTextMessage = onTextMessage })
  local fx = modules.game_shaderfx
  if fx and type(fx.setOrbDock) == 'function' then pcall(fx.setOrbDock, nil, false) end
  -- the base bar goes back to its panel (the next login lays it out again)
  if bar and alive(bar) and alive(frame) then
    local r = root()
    local panel = r and r:getChildById('gameBottomActionPanel')
    if panel then
      pcall(bar.setParent, bar, panel)
      pcall(bar.fill, bar, 'parent')
      pcall(bar.setClipping, bar, false)
    end
  end
  clearParts()
  if alive(frame) then frame:destroy() end
  frame, bar, slotParent, buttons, plan, drag = nil, nil, nil, nil, nil, nil
end

local function onMode(mode)
  if mode == 'action' then
    addEvent(function()
      -- the floating chat takes the console first; then the bar
      enable()
    end)
  else
    disable()
  end
end

local function onGeometry()
  if active and not drag and alive(frame) then M.relayout() end
end

function M.init()
  if g_app.isMobile() then return end
  if ChaosLayoutOptions and ChaosLayoutOptions.init then ChaosLayoutOptions.init() end -- hotbar_options.lua
  if ChaosLayoutMode and ChaosLayoutMode.subscribe then ChaosLayoutMode.subscribe(onMode) end
  local r = root()
  if r then
    lastRoot = r
    for _, id in ipairs({ false, 'gameLeftPanels', 'gameRightPanels' }) do
      local w = id and r:getChildById(id) or r
      if w then connect(w, { onGeometryChange = onGeometry }) end
    end
  end
end

function M.terminate()
  if ChaosLayoutOptions and ChaosLayoutOptions.terminate then ChaosLayoutOptions.terminate() end
  if ChaosLayoutMode and ChaosLayoutMode.unsubscribe then ChaosLayoutMode.unsubscribe(onMode) end
  local r = lastRoot
  if alive(r) then
    for _, id in ipairs({ false, 'gameLeftPanels', 'gameRightPanels' }) do
      local w = id and r:getChildById(id) or r
      if w then pcall(disconnect, w, { onGeometryChange = onGeometry }) end
    end
  end
  disable()
end

function M.closeOptions()
  local o = rawget(_G, 'ChaosLayoutOptions')
  if o and o.close then o.close() end
end
