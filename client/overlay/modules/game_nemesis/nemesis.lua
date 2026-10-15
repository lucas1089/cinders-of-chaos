-- Nemesis: the monster that hunts this character (server nemesis.lua). A small window with its name and epithet, its
-- type, level, kills, traits and when it was last seen; opened from a "Nemesis" tab added to the Bestiary window
-- (game_bestiary is not edited: the tab is put into its tab row at runtime) and from the menu, Hunt > Nemesis
-- (ChaosTopBar.addEntry). The server talks on extended opcode 163 (JSON, joined by registerExtendedJSONOpcode):
--   client -> server  get
--   server -> client  state {has, name, shown, monster, level, kills, traits, lastSeen, created, expiresIn, avenged,
--                     hunted}
-- Pure parts: nemesisview.lua (nemesisview_test.lua).

local OPCODE = 163

local window
local state
local handlers = {}
local bestiaryTab

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function safe(what, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then g_logger.warning('[nemesis] ' .. what .. ': ' .. tostring(err)) end
  end
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

-- ---------------------------------------------------------------- render
-- a view text {pattern, args...} through tr(); a pattern of '%s' or '%d' alone is a value, not a key
local function text(t)
  if type(t) ~= 'table' then return '' end
  if t[1] == '%s' or t[1] == '%d' then return NemesisView.plain(t) end
  return tr(t[1], (table.unpack or unpack)(t, 2))
end

local function render()
  if not alive(window) then return end
  local v = NemesisView.build(state, os.time())
  window.title:setText(text(v.title))
  window.sub:setText(text(v.sub))
  window.rows:destroyChildren()
  for i, r in ipairs(v.rows) do
    local row = g_ui.createWidget('NemesisRow', window.rows)
    if i % 2 == 0 then row:setBackgroundColor('#141014') end
    row.label:setText(text(r[1]))
    row.value:setText(text(r[2]))
  end
  window.traits:destroyChildren()
  for _, t in ipairs(v.traits) do
    local line = g_ui.createWidget('NemesisTrait', window.traits)
    line.name:setText(t.name)
    line.name:setColor(t.color)
    line.desc:setText(t.desc)
  end
  window.traitsTitle:setVisible(#v.traits > 0)
  window.empty:setText(text(v.empty))
  window.empty:setVisible(not v.has)
  window.footer:setText(text(v.footer))
end

function show()
  if not alive(window) then return end
  window:show()
  window:raise()
  window:focus()
  send('get')
end

function hide()
  if alive(window) then window:hide() end
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
  if type(msg) ~= 'table' or msg.action ~= 'state' then return end
  state = type(msg.data) == 'table' and msg.data or nil
  render()
end

-- ---------------------------------------------------------------- the Bestiary window's tab
local function addBestiaryTab()
  if alive(bestiaryTab) then return end
  local root = g_ui.getRootWidget()
  local bw = root and root:getChildById('bestiaryWindow')
  local tabs = bw and bw:getChildById('tabs')
  if not tabs then return end
  bestiaryTab = g_ui.createWidget('ChaosTabButton', tabs)
  bestiaryTab:setId('nemesisTab')
  bestiaryTab:setText(tr('Nemesis'))
  bestiaryTab:setWidth(90)
  bestiaryTab:setHeight(24)
  bestiaryTab:setTooltip(tr('The monster that hunts you'))
  bestiaryTab.onClick = function() show() end
  -- room for the third tab
  tabs:setWidth(tabs:getWidth() + 94)
end

-- ---------------------------------------------------------------- menu
local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if not api or not api.addEntry or handlers.menu then return end
  local ok, shown = pcall(api.available)
  for _, text in ipairs(ok and type(shown) == 'table' and shown.hunt or {}) do
    if text == 'Nemesis' then
      handlers.menu = true
      return
    end
  end
  handlers.menu = pcall(api.addEntry, 'hunt',
    { text = 'Nemesis', icon = 'battlelist', modules = { 'game_nemesis' }, fns = { 'toggle' } })
end

-- ---------------------------------------------------------------- lifecycle
local function onGameStart()
  state = nil
  addMenu()
  addBestiaryTab()
end

local function onGameEnd()
  hide()
  state = nil
end

function init()
  local ok, ui = pcall(g_ui.displayUI, 'nemesis')
  if ok and ui then
    window = ui
    window:hide()
  else
    g_logger.warning('[nemesis] window not loaded: ' .. tostring(ui))
  end
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  connect(g_game, handlers.game)
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, safe('opcode', onMessage))
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  if handlers.game then disconnect(g_game, handlers.game) end
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if alive(bestiaryTab) then
    local tabs = bestiaryTab:getParent()
    bestiaryTab:destroy()
    if tabs then pcall(function() tabs:setWidth(tabs:getWidth() - 94) end) end
  end
  if alive(window) then window:destroy() end
  window, state, bestiaryTab = nil, nil, nil
  handlers = {}
end
