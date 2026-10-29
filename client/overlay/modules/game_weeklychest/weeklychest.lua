-- Weekly Chest window (server weeklychest.lua): the six activities of the week with what is done, the number the chest
-- asks (fewer when a system is not unlocked yet), the chest's reward and the bonus roll. Opened from the menu,
-- Adventure > Weekly Chest (ChaosTopBar.addEntry). The server talks on extended opcode 117 (JSON, joined by
-- registerExtendedJSONOpcode):
--   client -> server  open | close | get
--   server -> client  state {open?, endsIn, acts, got, need, bonusNeed, open, chests, chest, bonus} (weeklyview.lua)
-- Rewards are given by the server when the chest or the bonus roll is reached (a toast tells); the window only shows.
-- Pure parts: weeklyview.lua (weeklyview_test.lua).

local OPCODE = 117

local window
local state
local handlers = {}

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function safe(what, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then g_logger.warning('[weeklychest] ' .. what .. ': ' .. tostring(err)) end
  end
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

-- a view text {pattern, args...} through tr(); a pattern without letters is a value, not a key
local function text(t)
  if type(t) ~= 'table' then return '' end
  if type(t[1]) ~= 'string' or not t[1]:find('%a%a') then return WeeklyView.plain(t) end
  local args = {}
  for i = 2, #t do
    args[#args + 1] = type(t[i]) == 'table' and text(t[i]) or t[i]
  end
  return tr(t[1], (table.unpack or unpack)(args))
end

local function render()
  if not alive(window) then return end
  local v = WeeklyView.build(state)
  window.head:setText(text(v.head))
  window.ends:setText(text(v.ends))
  window.acts:destroyChildren()
  for _, r in ipairs(v.rows) do
    local row = g_ui.createWidget('WeeklyActRow', window.acts)
    row.name:setText(text(r.name))
    row.status:setText(text(r.status))
    row.status:setColor(r.color)
    row.what:setText(text(r.what))
  end
  window.chest:setText(text(v.chest))
  window.chest:setColor(v.chestColor)
  window.reward:setText(text(v.reward))
  window.bonus:setText(text(v.bonus))
  window.bonus:setColor(v.bonusColor)
  window.chests:setText(text(v.chests))
end

function show()
  if not alive(window) then return end
  window:show()
  window:raise()
  window:focus()
  send('open')
end

function hide()
  if alive(window) and window:isVisible() then
    window:hide()
    send('close')
  end
end

function toggle()
  if not alive(window) then return end
  if window:isVisible() then
    hide()
  else
    show()
  end
end

local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' or type(msg.data) ~= 'table' or msg.action ~= 'state' then return end
  state = msg.data
  render()
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if not api or not api.addEntry or handlers.menu then return end
  local ok, shown = pcall(api.available)
  for _, entry in ipairs(ok and type(shown) == 'table' and shown.adventure or {}) do
    if entry == 'Weekly Chest' then
      handlers.menu = true
      return
    end
  end
  handlers.menu = pcall(api.addEntry, 'adventure',
    { text = 'Weekly Chest', icon = 'daily', modules = { 'game_weeklychest' }, fns = { 'toggle' } })
end

local function onGameStart()
  state = nil
  addMenu()
end

local function onGameEnd()
  if alive(window) then window:hide() end
  state = nil
end

function init()
  local ok, ui = pcall(g_ui.displayUI, 'weeklychest')
  if ok and ui then
    window = ui
    window:hide()
    pcall(function() modules.game_howitworks.attach(window, 'weeklychest') end) -- game_howitworks: the ? button
  else
    g_logger.warning('[weeklychest] window not loaded: ' .. tostring(ui))
  end
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  connect(g_game, handlers.game)
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, safe('opcode', onMessage))
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  if handlers.game then disconnect(g_game, handlers.game) end
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if alive(window) then window:destroy() end
  window, state = nil, nil
  handlers = {}
end
