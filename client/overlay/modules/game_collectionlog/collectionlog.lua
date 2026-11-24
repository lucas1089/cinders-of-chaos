-- Collection log window (O753): every unique, set piece, raid unique and card by source, owned / seen / not yet, how many
-- dropped and the first drop date, and the pity counts of the long chases ("Rift chest: set piece  37 / 114"). Menu:
-- Hunt > Records > Collection Log (ChaosTopBar.addEntry). Server: server/data/scripts/chaos/collection_log.lua and
-- chase_pity.lua, extended opcode 170 (JSON {action, data}, joined from parts by registerExtendedJSONOpcode):
--   client -> server  sync
--   server -> client  state {rows, groups, pity, owned, seen, total}
-- Pure parts: collectionlogic.lua (collectionlogic_test.lua).

local L = CollectionLogLogic
local OPCODE = L.OPCODE

local window
local state
local status = 'all'
local search = ''
local statusOptions = {}
local handlers = {}

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function safe(what, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then g_logger.warning('[collectionlog] ' .. what .. ': ' .. tostring(err)) end
  end
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

-- a {pattern, args...} text through tr()
local function text(t)
  if type(t) ~= 'table' then return '' end
  return tr(t[1], (table.unpack or unpack)(t, 2))
end

local function labelText(label, arg)
  if arg ~= nil then return tr(label, arg) end
  return tr(label)
end

-- ---------------------------------------------------------------- render
local function renderPity()
  local list = window.pityPanel.pityList
  list:destroyChildren()
  for _, p in ipairs(L.pityLines(state)) do
    local row = g_ui.createWidget('CollectionPityRow', list)
    row.label:setText(labelText(p.label, p.arg))
    row.value:setText(p.text)
    row.bar:setPercent(math.floor(p.ratio * 100 + 0.5))
  end
  window.pityPanel.emptyPity:setVisible(#L.pityLines(state) == 0)
end

local function render()
  if not alive(window) then return end
  window.summaryLabel:setText(text(L.summary(state)))
  local list = window.listPanel.itemList
  list:destroyChildren()
  local lines = L.lines(state, status, search)
  for _, line in ipairs(lines) do
    if line.kind == 'header' then
      local h = g_ui.createWidget('CollectionHeader', list)
      h.label:setText(labelText(line.label, line.arg))
      h.value:setText(tr('%d of %d', line.owned, line.total))
    else
      local r = line.row
      local w = g_ui.createWidget('CollectionRow', list)
      w.icon:setItemId(r.cid)
      w.icon:setOpacity(r.state == 2 and 1 or 0.4)
      w.name:setText(r.name)
      w.name:setColor(r.state == 2 and '#e8dcc4' or '#a89c86')
      w.detail:setText(text(L.itemDetail(r)))
      w.detail:setColor(L.STATE_COLOR[r.state] or '#8a7f6e')
    end
  end
  window.listPanel.emptyLabel:setVisible(#lines == 0)
  renderPity()
end

-- ---------------------------------------------------------------- window
function show()
  if not alive(window) then return end
  window:show()
  window:raise()
  window:focus()
  send('sync')
end

function hide()
  if alive(window) then window:hide() end
end

function toggle()
  if not alive(window) then return end
  if window:isVisible() then hide() else show() end
end

local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' or msg.action ~= 'state' then return end
  state = L.clean(msg.data)
  render()
end

local function setupFilters()
  local combo = window.statusCombo
  statusOptions = {}
  combo:clearOptions()
  for _, o in ipairs(L.STATUS) do
    local label = tr(o[2])
    statusOptions[#statusOptions + 1] = { o[1], o[2], label }
    combo:addOption(label)
  end
  combo.onOptionChange = function(_, t) status = L.valueOf(statusOptions, t); render() end
  window.searchEdit.onTextChange = function(_, t) search = t or ''; render() end
end

-- ---------------------------------------------------------------- menu
local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if not api or not api.addEntry or handlers.menu then return end
  local ok, shown = pcall(api.available)
  for _, t in ipairs(ok and type(shown) == 'table' and shown.hunt or {}) do
    if t == 'Collection Log' then
      handlers.menu = true
      return
    end
  end
  handlers.menu = pcall(api.addEntry, 'hunt',
    { text = 'Collection Log', icon = 'ranking', modules = { 'game_collectionlog' }, fns = { 'toggle' } })
end

-- ---------------------------------------------------------------- lifecycle
local function onGameStart()
  state = nil
  addMenu()
end

local function onGameEnd()
  hide()
  state = nil
end

function init()
  local ok, ui = pcall(g_ui.displayUI, 'collectionlog')
  if ok and ui then
    window = ui
    window:hide()
    setupFilters()
  else
    g_logger.warning('[collectionlog] window not loaded: ' .. tostring(ui))
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
