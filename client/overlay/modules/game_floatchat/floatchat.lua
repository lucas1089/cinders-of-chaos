-- game_floatchat: the chat as a floating window over the map, in the action bar layout (client/MANIFEST.md "Floating
-- chat and central hotbar (O414)"; rules in floatchat_logic.lua, tested by floatchat_test.lua).
-- * The base console panel (game_console) is reparented into the window's content area, not rewritten: tabs, channels,
--   private chats, the Loot tab overlay, chat links and the Enter rule keep working. The base tab row sits above the
--   content area's top edge (clipped) and the header's "Channels" and "Private" menus pick the tab instead.
-- * Hidden = the window is parked far outside the screen, still a live widget: the console's key bindings and its text
--   keep working, nothing is drawn or clickable. Ctrl+Shift+C, the X, the button on the hotbar (game_hotbar) toggle it.
-- * Enter shows a hidden chat while the player types and hides it again after the line (option, default on).
-- * Body opacity 40-100% (default 75%), optional fade after N seconds, hover brings it back. Place, size, hidden and
--   opacity are kept per character (node chaos_floatchat).
-- Only runs in the action bar layout (ChaosLayoutMode); the classic layout never touches the console.
ChaosFloatChat = ChaosFloatChat or {}
local M = ChaosFloatChat
local L = FloatChatLogic

local HOTKEY = 'Ctrl+Shift+C'
local PARK = -30000          -- x of a hidden window
local POLL_MS, FADE_MS = 100, 100

local win, content, header
local consolePanel, origParent
local tabBarHeight = 0
local TAB_ROW_MIN = 24       -- the least the tab row is pushed up by, when it cannot be measured (yet)
local settings = L.settingsFor(nil, nil)
local state = L.new(false, 0)
local character
local active = false
local pollEvent, fadeEvent
local lastTyping = false
local drag = L.dragNew()
local endDrag            -- ends the drag (defined with the drag glue below)
local refocusInput       -- keys back to the chat input (defined with the drag glue below)
local listeners = {}
local appliedAlpha = -1

local function now() return g_clock.millis() end

local function alive(w) return w and not w:isDestroyed() end

local function root()
  local gi = modules.game_interface
  return gi and gi.getRootPanel and gi.getRootPanel() or nil
end

-- the game area the window may use, as a rect in screen pixels: the root panel without the side panels and the top menu.
-- `wide`: the area a placed or dragged window may use, which reaches the screen's left edge (x = 0) over the left side
-- panel column: the chat floats over the map, and the old limit (the left panels' right edge) kept it from going all
-- the way left (owner 2026-11-09). The default place (nothing saved) keeps to the map's own area.
local function area(wide)
  local r = root()
  if not r then return { x = 0, y = 0, width = 1024, height = 600 } end
  local rect = r:getRect()
  local left, right, top = rect.x, rect.x + rect.width, rect.y
  local lp, rp = r:getChildById('gameLeftPanels'), r:getChildById('gameRightPanels')
  if not wide and lp and lp:isVisible() and lp:getWidth() > 0 then left = math.max(left, lp:getX() + lp:getWidth()) end
  if rp and rp:isVisible() and rp:getWidth() > 0 then right = math.min(right, rp:getX()) end
  local bar = r:getChildById('chaosMenuBar')
  if bar and bar:isVisible() and bar:getY() < rect.y + 60 then top = math.max(top, bar:getY() + bar:getHeight()) end
  return { x = left, y = top, width = math.max(0, right - left), height = math.max(0, rect.y + rect.height - top) }
end

local function hotbarRect()
  local hb = rawget(_G, 'ChaosHotbar')
  return hb and hb.getRect and hb.getRect() or nil
end

-- ---------------------------------------------------------------- the console panel
local function findConsolePanel()
  local console = modules.game_console
  local p = console and console.consolePanel
  if alive(p) then return p end
  local gi = modules.game_interface
  local bottom = gi and gi.getBottomPanel and gi.getBottomPanel()
  if bottom then return bottom:recursiveGetChildById('consolePanel') end
end

local function textEdit()
  return alive(consolePanel) and consolePanel:recursiveGetChildById('consoleTextEdit') or nil
end

local function tabBar()
  local console = modules.game_console
  local bar = console and console.consoleTabBar
  if alive(bar) then return bar end
  return alive(consolePanel) and consolePanel:recursiveGetChildById('consoleTabBar') or nil
end

-- open tabs of the console as the menus want them: { name, channelId, unread, current, tab }
local function tabs()
  local out = {}
  local bar = tabBar()
  if not bar or not bar.getTabs then return out end
  local current = bar.getCurrentTab and bar:getCurrentTab() or nil
  for _, tab in ipairs(bar:getTabs()) do
    local ok, name = pcall(tab.getText, tab)
    if ok and type(name) == 'string' then
      local isCurrent = tab == current
      local blinking = tab.blinking == true or (tab.isOn and tab:isOn() == true)
      out[#out + 1] = { name = name, channelId = tab.channelId, unread = (blinking and not isCurrent) and 1 or 0,
                        current = isCurrent, tab = tab }
    end
  end
  return out
end

-- ---------------------------------------------------------------- looks
local function applyBody(opacityPercent)
  if not alive(win) then return end
  local alpha = L.bodyAlpha(opacityPercent)
  if alpha ~= appliedAlpha then
    appliedAlpha = alpha
    win:setBackgroundColor(string.format('#0e0a0c%02x', alpha))
  end
end

local function updateBadges()
  if not alive(header) then return end
  local m = L.menus(tabs())
  for id, count in pairs({ channels = m.channelsUnread, private = m.privateUnread }) do
    local tab = header:getChildById(id)
    local badge = tab and tab:getChildById('badge')
    if badge then
      local text = L.badge(count)
      badge:setText(text)
      badge:setVisible(text ~= '')
      badge:setWidth(math.max(16, 7 * #text + 6))
    end
  end
end

local function notifyListeners()
  for _, fn in ipairs(listeners) do pcall(fn, M.isHidden(), state.unread) end
end

-- the window's place on screen (a hidden one is parked outside)
local function place()
  if not alive(win) then return end
  local r = root()
  if not r then return end
  local rect = r:getRect()
  local a = area(settings.x ~= nil)
  if state.hidden then
    win:setMarginLeft(PARK)
    return
  end
  local p = L.place(settings, a, hotbarRect())
  win:setSize({ width = p.width, height = p.height })
  win:setMarginLeft(p.x - rect.x)
  win:setMarginTop(p.y - rect.y)
end

local function save()
  if not character then return end
  local node = g_settings.getNode(L.NODE) or {}
  settings.hidden = state.hidden
  pcall(g_settings.setNode, L.NODE, L.store(node, character, settings))
  pcall(g_settings.save)
end

local function apply()
  place()
  applyBody(settings.opacity)
  updateBadges()
  notifyListeners()
end

local function dispatch(event)
  local was = state.hidden
  state = L.step(state, event, { showOnType = settings.hideOnSend ~= false, hideOnSend = settings.hideOnSend ~= false }, now())
  if event == 'toggle' or event == 'show' or event == 'hide' then settings.hidden = state.hidden end
  if was ~= state.hidden then
    if state.hidden then endDrag() end
    place()
  end
  if event == 'toggle' or event == 'show' or event == 'hide' then save() end
  notifyListeners()
end

-- ---------------------------------------------------------------- public
function M.isHidden() return state.hidden end
function M.getUnread() return state.unread end
function M.getRect()
  if not alive(win) or state.hidden then return nil end
  return win:getRect()
end
function M.subscribe(fn) listeners[#listeners + 1] = fn end
function M.unsubscribe(fn)
  for i = #listeners, 1, -1 do if listeners[i] == fn then table.remove(listeners, i) end end
end
function M.toggle() if active then dispatch('toggle') end end
function M.show() if active then dispatch('show') end end
function M.hide() if active then dispatch('hide') end end

function M.getSettings()
  return { opacity = settings.opacity, fade = settings.fade, fadeSeconds = settings.fadeSeconds,
           hideOnSend = settings.hideOnSend }
end

-- the layout options window changes these
function M.setOption(key, value)
  if key == 'opacity' then settings.opacity = L.clampOpacity(value)
  elseif key == 'fade' then settings.fade = value == true
  elseif key == 'fadeSeconds' then settings.fadeSeconds = L.clampFadeSeconds(value)
  elseif key == 'hideOnSend' then settings.hideOnSend = value ~= false
  else return end
  applyBody(settings.opacity)
  save()
end

function M.resetPlace()
  settings.x, settings.y = nil, nil
  settings.width, settings.height = L.DEFAULT_W, L.DEFAULT_H
  place()
  save()
end

-- ---------------------------------------------------------------- menus
local function selectTab(tab)
  local bar = tabBar()
  if bar and bar.selectTab and tab then pcall(bar.selectTab, bar, tab) end
end

local function showMenu(kind, anchor)
  local menu = g_ui.createWidget('PopupMenu')
  local m = L.menus(tabs())
  local list = kind == 'private' and m.private or m.channels
  local all = tabs()
  if #list == 0 then
    menu:addOption(kind == 'private' and tr('No private chats open') or tr('No channels open'), function() end)
  end
  for _, e in ipairs(list) do
    local label = (e.current and '> ' or '') .. e.name .. (e.unread > 0 and ' (' .. e.unread .. ')' or '')
    menu:addOption(label, function()
      for _, t in ipairs(all) do
        if t.name == e.name then selectTab(t.tab) end
      end
      dispatch('touch')
      -- the menu's own hand-off of the focus runs about 50 ms after it closes: the input takes the keys after that
      scheduleEvent(refocusInput, 90)
    end)
  end
  menu:display({ x = anchor:getX(), y = anchor:getY() + anchor:getHeight() })
end

-- ---------------------------------------------------------------- dragging
-- State machine: FloatChatLogic.drag* (O498). `drag` is its state; it ends on any release, on a move with the left
-- button up, when the client window loses focus, on hide and on logout.
local function mouse(pos) return pos.x, pos.y end

local function dragEnv()
  local down = true
  if g_mouse and g_mouse.isPressed then
    local ok, v = pcall(g_mouse.isPressed, MouseLeftButton)
    if ok then down = v == true end
  end
  local focused = true
  if g_window and g_window.hasFocus then
    local ok, v = pcall(g_window.hasFocus)
    if ok then focused = v ~= false end
  end
  return { leftDown = down, focused = focused, hidden = state.hidden }
end

local function inDrag() return drag ~= nil and drag.active == true end

-- ends the drag (release anywhere, cancel): saves the place when the window moved
endDrag = function()
  local was, moved
  drag, was, moved = L.dragEnd(drag)
  if was and moved then save() end
  return was
end

local function beginDrag(target, pos, button)
  if not alive(win) then return false end
  drag = L.dragPress(drag, target, button == MouseLeftButton, win:getRect(), mouse(pos))
  return inDrag()
end

local function onDragMove(pos)
  if not inDrag() then return false end
  if not alive(win) then endDrag() return false end
  local mx, my = mouse(pos)
  local before, r, ended = drag, nil, false
  drag, r, ended = L.dragMove(drag, mx, my, area(true), dragEnv())
  if ended then
    -- the move ended the drag: the button is up (a release nobody heard), the client lost focus, or it was hidden
    if before.moved then save() end
    return false
  end
  if not r then return false end
  local rect = root():getRect()
  settings.x, settings.y, settings.width, settings.height = r.x, r.y, r.width, r.height
  win:setSize({ width = r.width, height = r.height })
  win:setMarginLeft(r.x - rect.x)
  win:setMarginTop(r.y - rect.y)
  return true
end

-- what a press at pos landed on inside `source`: the place, or 'button' for a child that keeps its own clicks
local function pressTarget(source, place, pos)
  local ok, hit = pcall(function() return source:recursiveGetChildByPos(pos, false) end)
  if ok and hit and hit ~= source then
    local okc, class = pcall(function() return hit:getClassName() end)
    if okc then return L.dragTarget(place, class) end
  end
  return place
end

-- the keys go back to the chat input after a click in the window, when the chat is on (the classic console did)
refocusInput = function()
  local te = textEdit()
  if te and te:isEnabled() == true and not state.hidden then
    pcall(te.recursiveFocus, te, KeyboardFocusReason)
  end
end

local function wireWindow()
  header = win:getChildById('header')
  content = win:getChildById('content')
  local grip = win:getChildById('grip')
  header.onMousePress = function(self, pos, button)
    return beginDrag(pressTarget(self, 'header', pos), pos, button)
  end
  header.onMouseMove = function(_, pos) return onDragMove(pos) end
  header.onMouseRelease = function()
    local was = endDrag()
    refocusInput()
    return was
  end
  header.onDoubleClick = function(self, pos)
    if pressTarget(self, 'header', pos) ~= 'header' then return false end
    drag = L.dragNew()
    M.resetPlace()
    return true
  end
  grip.onMousePress = function(self, pos, button)
    return beginDrag(pressTarget(self, 'grip', pos), pos, button)
  end
  grip.onMouseMove = function(_, pos) return onDragMove(pos) end
  grip.onMouseRelease = function()
    local was = endDrag()
    refocusInput()
    return was
  end
  -- a click anywhere else in the window: the release comes here when no child took it
  win.onMouseRelease = function()
    endDrag()
    refocusInput()
    return false
  end
  header:getChildById('close').onClick = function() M.hide() end
  header:getChildById('options').onClick = function()
    local o = rawget(_G, 'ChaosLayoutOptions')
    if o and o.open then o.open() end
  end
  for _, id in ipairs({ 'channels', 'private' }) do
    local tab = header:getChildById(id)
    tab.onClick = function(self) showMenu(id, self) end
    local icon = tab:getChildById('icon')
    if icon then icon:setImageSource('/modules/game_floatchat/images/chat_' .. id) end
    local label = tab:getChildById('label')
    if label then label:setText(id == 'private' and tr('Private') or tr('Channels')) end
  end
end

-- ---------------------------------------------------------------- reparenting the console
-- How far the console's tab row reaches down from the console panel's top: where its content panel starts (the content
-- panel hangs under the tab row). Measured after a layout, so it is the row's real footprint, margins included. The
-- bar's own height alone was too little (0 before the first layout of the hidden base panel), and the row then stayed
-- in the content area under the header (owner screenshot 2026-11-09: the tabs over "Channels" and "Private").
local function tabRowFootprint()
  if not alive(consolePanel) then return nil end
  local cp = consolePanel:recursiveGetChildById('consoleContentPanel')
  if not cp then return nil end
  local d = cp:getY() - consolePanel:getY()
  if d >= 8 and d <= 120 then return d end
  return nil
end

-- push the tab row up out of the clipped content area (again whenever the measure changes)
local function fitTabRow()
  if not (alive(consolePanel) and alive(content)) then return end
  local bar = tabBar()
  local want = tabRowFootprint() or math.max(bar and bar:getHeight() or 0, TAB_ROW_MIN)
  if want ~= tabBarHeight or consolePanel:getMarginTop() ~= -want then
    tabBarHeight = want
    consolePanel:setMarginTop(-want)
  end
end

local function takeConsole()
  consolePanel = findConsolePanel()
  if not alive(consolePanel) or not alive(content) then return false end
  origParent = consolePanel:getParent()
  consolePanel:setParent(content)
  consolePanel:breakAnchors()
  consolePanel:addAnchor(AnchorTop, 'parent', AnchorTop)
  consolePanel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  consolePanel:addAnchor(AnchorRight, 'parent', AnchorRight)
  consolePanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  -- the base tab row is pushed above the content area (which clips it): our header menus take its place
  tabBarHeight = 0
  fitTabRow()
  pcall(content.setClipping, content, true)
  -- the base console draws its own dark background: the window's own see-through body shows instead
  pcall(consolePanel.setBackgroundColor, consolePanel, '#00000000')
  local cp = consolePanel:getChildById('consoleContentPanel')
  if cp then pcall(cp.setBackgroundColor, cp, '#00000000') end
  consolePanel:setVisible(true)
  header:raise() -- last child: wins the hit test over the clipped tab row and draws over it
  -- The keys reach the chat input only along the chain of focused children from the game root panel down. The base
  -- console focuses its input with recursiveFocus, which skips a widget that is not focusable: with the window
  -- unfocusable the chain stopped at the root panel and nothing typed arrived (O498). Made focusable only now, after the
  -- console is in it: the root panel's focus is moved to the window only when it has no focused child at all.
  pcall(win.setFocusable, win, true)
  return true
end

local function giveBackConsole()
  if alive(consolePanel) and alive(origParent) then
    consolePanel:setParent(origParent)
    consolePanel:breakAnchors()
    consolePanel:fill('parent')
    consolePanel:setMarginTop(0)
  end
  consolePanel, origParent = nil, nil
end

-- ---------------------------------------------------------------- polling: typing and fading
local wasDown = false
local function poll()
  pollEvent = nil
  if not active then return end
  -- a drag whose release nobody heard (the button went up over another widget or outside the client window, the client
  -- window lost focus): dropped here at the latest, and no move of the pointer is needed
  local env = dragEnv()
  if L.dragStale(drag, env) then endDrag() end
  -- a click in the window: the keys go back to the chat input
  local inside = false
  if alive(win) and not state.hidden and g_window and g_window.getMousePosition then
    local ok, v = pcall(function() return win:containsPoint(g_window.getMousePosition()) end)
    inside = ok and v == true
  end
  local te = textEdit()
  if L.refocusAfterClick(wasDown, env.leftDown, inside, te ~= nil and te:isEnabled() == true) then refocusInput() end
  wasDown = env.leftDown
  local typing = te ~= nil and te:isEnabled() == true
  if typing ~= lastTyping then
    lastTyping = typing
    dispatch(typing and 'typing_on' or 'typing_off')
  end
  updateBadges()
  -- the base console panel was destroyed and rebuilt, or taken back into its own panel: take it again
  if alive(content) and (not alive(consolePanel) or consolePanel:getParent() ~= content) then pcall(takeConsole) end
  fitTabRow()
  pollEvent = scheduleEvent(poll, POLL_MS)
end

local function fadeTick()
  fadeEvent = nil
  if not active then return end
  if settings.fade and alive(win) and not state.hidden then
    local mp = g_window.getMousePosition()
    local hovered = win:containsPoint(mp)
    if hovered then state.activity = now() end
    applyBody(L.fadedOpacity(settings.opacity, { fade = true, fadeSeconds = settings.fadeSeconds, hovered = hovered,
      typing = state.typing, hidden = state.hidden, activity = state.activity, now = now() }))
  else
    applyBody(settings.opacity)
  end
  fadeEvent = scheduleEvent(fadeTick, FADE_MS)
end

local function onTalk()
  if active then dispatch('message') end
end

local function onTextMessage()
  if active and not state.hidden then state.activity = now() end
end

-- ---------------------------------------------------------------- start and stop
local function enable()
  if active then return end
  local r = root()
  if not r or not g_game.isOnline() then return end
  g_ui.importStyle('floatchat')
  character = g_game.getLocalPlayer() and g_game.getLocalPlayer():getName() or nil
  settings = L.settingsFor(g_settings.getNode(L.NODE), character)
  win = g_ui.createWidget('ChaosFloatChat', r)
  win:addAnchor(AnchorTop, 'parent', AnchorTop)
  win:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  wireWindow()
  if not takeConsole() then
    win:destroy()
    win = nil
    return
  end
  active = true
  state = L.new(settings.hidden, now())
  lastTyping = textEdit() ~= nil and textEdit():isEnabled() == true
  connect(g_game, { onTalk = onTalk, onTextMessage = onTextMessage })
  g_keyboard.bindKeyDown(HOTKEY, M.toggle)
  apply()
  poll()
  fadeTick()
end

local function disable()
  if not active and not win then return end
  if active then save() end
  active = false
  if pollEvent then removeEvent(pollEvent) pollEvent = nil end
  if fadeEvent then removeEvent(fadeEvent) fadeEvent = nil end
  pcall(g_keyboard.unbindKeyDown, HOTKEY, M.toggle)
  pcall(disconnect, g_game, { onTalk = onTalk, onTextMessage = onTextMessage })
  giveBackConsole()
  if alive(win) then win:destroy() end
  endDrag()
  win, content, header = nil, nil, nil
  state = L.new(false, 0)
  notifyListeners()
end

local function onMode(mode)
  if mode == 'action' then
    -- one frame later: the console and the root panel are laid out
    addEvent(enable)
  else
    disable()
  end
end

local function onGeometry()
  if active and not inDrag() then place() end
end

-- Direct game hooks, besides the layout mode's notice (see game_hotbar): a game end always ends the window, and a few
-- moments after a start it is switched on if the layout mode says action and nothing did.
local ensureEvents = {}
local function cancelEnsure()
  for _, e in ipairs(ensureEvents) do removeEvent(e) end
  ensureEvents = {}
end

local function onGameEnd()
  cancelEnsure()
  disable()
end

local function onGameStart()
  cancelEnsure()
  for _, ms in ipairs({ 700, 2000, 5000 }) do
    ensureEvents[#ensureEvents + 1] = scheduleEvent(function()
      if not active and g_game.isOnline() and ChaosLayoutMode and ChaosLayoutMode.isAction and ChaosLayoutMode.isAction() then
        enable()
      end
    end, ms)
  end
end

function M.init()
  if g_app.isMobile() then return end
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if ChaosLayoutMode and ChaosLayoutMode.subscribe then ChaosLayoutMode.subscribe(onMode) end
  local r = root()
  if r then connect(r, { onGeometryChange = onGeometry }) end
end

function M.terminate()
  pcall(disconnect, g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  cancelEnsure()
  if ChaosLayoutMode and ChaosLayoutMode.unsubscribe then ChaosLayoutMode.unsubscribe(onMode) end
  local r = root()
  if r then pcall(disconnect, r, { onGeometryChange = onGeometry }) end
  disable()
  listeners = {}
end
