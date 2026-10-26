-- The level-gated top menu, the client side (O259; the rules are in topbarunlockslogic.lua, the server's in unlocks.lua):
-- listens on extended opcode 115 for the server's `state` (which entries are unlocked, the next one, which were opened)
-- and `new` (an entry just unlocked: a big text on the screen, a "New" badge on the entry and a small window with a Go
-- button), and tells the server `hello` (at the start of a game) and `seen {key}` (the player opened an entry).
-- chaos_topbar.lua asks this file how to draw each entry (status, isNew, blockedMessage) and hands it the three calls it
-- needs (host.parent, host.run, host.refresh). The player's option "Show the whole menu" (System > Options, base patch 0154)
-- comes in through setShowAll. Every engine call is guarded: a failure here never breaks the menu.

ChaosTopBarUnlocks = {}
local U = ChaosTopBarUnlocks
local L = ChaosTopBarUnlocksLogic

local OPCODE = 115 -- ChaosOpcodes.unlocks
local state = L.newState()
local host
local textLabel, window
local textEvent, fadeEvent, windowEvent, helloEvent

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data }))
  end
end

local function cancel(event)
  if event then pcall(removeEvent, event) end
  return nil
end

-- ---------------------------------------------------------------- what the menu asks
function U.status(menu) return L.status(state, menu) end
function U.isNew(menu) return L.isNew(state, menu) end

-- the player opened the entry: its badge goes, the server remembers
function U.markOpened(menu)
  local key = L.markSeen(state, menu)
  if key then
    pcall(send, 'seen', { key = key })
    if host and host.refresh then host.refresh() end
  end
end

-- a hotkey of a locked entry says when it opens; true when the key was handled that way
function U.blockedMessage(menu)
  local level = L.blockedLevel(state, menu)
  if not level then return false end
  local text = L.unlocksAt(level, tr)
  local tm = modules.game_textmessage
  if tm and tm.displayFailureMessage then pcall(tm.displayFailureMessage, text) end
  return true
end

function U.setShowAll(on)
  state.showAll = on and true or false
  if host and host.refresh then host.refresh() end
end

-- ---------------------------------------------------------------- the screen text and the window
local function hideText()
  textEvent, fadeEvent = cancel(textEvent), cancel(fadeEvent)
  if alive(textLabel) then textLabel:destroy() end
  textLabel = nil
end

local function showText(text)
  hideText()
  local parent = host and host.parent and host.parent()
  if not alive(parent) then return end
  textLabel = g_ui.createWidget('ChaosUnlockText', parent)
  textLabel:setText(text)
  textLabel:raise()
  local label = textLabel
  textEvent = scheduleEvent(function()
    textEvent = nil
    if g_effects and g_effects.fadeOut and alive(label) then pcall(g_effects.fadeOut, label, 800) end
    fadeEvent = scheduleEvent(function()
      fadeEvent = nil
      if label == textLabel then hideText() end
    end, 900)
  end, L.TEXT_MS)
end

function U.hideWindow()
  windowEvent = cancel(windowEvent)
  if alive(window) then window:destroy() end
  window = nil
end

local function showWindow(a)
  U.hideWindow()
  local parent = host and host.parent and host.parent()
  if not alive(parent) then return end
  window = g_ui.createWidget('ChaosUnlockWindow', parent)
  window:getChildById('title'):setText(a.title)
  window:getChildById('line1'):setText(a.line1)
  window:getChildById('line2'):setText(a.line2)
  local go = window:getChildById('go')
  go:setText(tr('Go'))
  go.onClick = function()
    U.hideWindow()
    if a.menu and host and host.run then host.run(a.menu) end
  end
  local close = window:getChildById('close')
  close:setText(tr('Close'))
  close.onClick = function() U.hideWindow() end
  window:raise()
  windowEvent = scheduleEvent(function()
    windowEvent = nil
    U.hideWindow()
  end, L.WINDOW_SECONDS * 1000)
end

-- ---------------------------------------------------------------- the server's messages
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    L.apply(state, data)
    if host and host.refresh then host.refresh() end
  elseif msg.action == 'new' then
    local a = L.announcement(data)
    if not a then return end
    L.markUnlocked(state, a.key)
    if host and host.refresh then host.refresh() end
    showText(L.screenText(a.title, tr))
    showWindow(a)
  end
end

local function guarded(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then g_logger.warning('[chaos_menu] unlocks ' .. name .. ': ' .. tostring(err)) end
  end
end

local handlers = {}

local function onGameStart()
  -- the server also sends the state by itself after the login; this is for a client that was not listening yet
  helloEvent = cancel(helloEvent)
  helloEvent = scheduleEvent(function()
    helloEvent = nil
    pcall(send, 'hello')
  end, 1800)
end

local function onGameEnd()
  helloEvent = cancel(helloEvent)
  hideText()
  U.hideWindow()
  local showAll = state.showAll
  state = L.newState()
  state.showAll = showAll
end

-- host: {parent = function() -> the game root panel, run = function(menuText), refresh = function()}
function U.init(h, showAll)
  host = h
  state.showAll = showAll and true or false
  handlers.opcode = guarded('opcode', onMessage)
  handlers.start = guarded('start', onGameStart)
  handlers.stop = guarded('stop', onGameEnd)
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, handlers.opcode)
  connect(g_game, { onGameStart = handlers.start, onGameEnd = handlers.stop })
  if g_game.isOnline() then onGameStart() end
end

function U.terminate()
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if handlers.start then pcall(disconnect, g_game, { onGameStart = handlers.start, onGameEnd = handlers.stop }) end
  helloEvent = cancel(helloEvent)
  hideText()
  U.hideWindow()
  handlers, host = {}, nil
  state = L.newState()
end
