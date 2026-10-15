-- Loadouts / Armory (server data/scripts/chaos/loadouts.lua, extended opcode 206, JSON {action, data}; the state comes
-- through Chaos.sendChunked and is joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | save {slot, name, icon} | load {slot} | rename {slot, name, icon} | delete {slot} | cancel
--   server -> client  state {...} | result {ok, text, lines} | cast {ms, slot} | castEnd {result}
-- The server decides everything (it reads the build itself; this window never sends nodes or items). Client-side only:
-- the action bar profile remembered per character and slot (g_settings node 'loadouts'), switched to after a load.
-- Menu: Character > Loadouts (ChaosTopBar.addEntry); a Loadouts button is added at runtime to the passive tree window
-- (next to its Trials button) without changing game_passivetree.

local OPCODE = 206
local V = LoadoutsView
local SETTINGS = 'loadouts'

local window
local state, stateAt
local selected
local iconChoice
local pending -- {action, slot} of the last save / load sent
local confirmDelete
local handlers = {}
local reported = {}
local tickEvent, treeEvent

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[loadouts] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function elapsed()
  if not stateAt then return 0 end
  return (g_clock.millis() - stateAt) / 1000
end

local function setStatus(text, color)
  if window then
    window.status:setText(text or '')
    window.status:setColor(color or V.COLORS.dim)
  end
end

local function slotOf(n)
  for _, slot in ipairs(state and state.slots or {}) do
    if slot.slot == n then return slot end
  end
end

-- ---------------------------------------------------------------- action bar profile (client-side)
local function profiles()
  local ok, node = pcall(g_settings.getNode, SETTINGS)
  return (ok and type(node) == 'table') and node or {}
end

local function profileOf(slot)
  return profiles()[V.profileKey(g_game.getCharacterName(), slot)]
end

local function rememberProfile(slot)
  local O = rawget(_G, 'Options') or Options
  local name = O and O.currentHotkeySetName
  if not name or name == '' then return end
  local node = profiles()
  node[V.profileKey(g_game.getCharacterName(), slot)] = name
  pcall(g_settings.setNode, SETTINGS, node)
end

local function applyProfile(slot)
  local name = profileOf(slot)
  local O = rawget(_G, 'Options') or Options
  if not name or not O or O.currentHotkeySetName == name then return end
  if O.profileExist and not O.profileExist(name) then return end
  local settings = modules.client_settings
  local change = settings and rawget(settings, 'changeActiveHotkeyProfile')
  if type(change) == 'function' then
    pcall(change, name)
  elseif O.changeHotkeyProfile then
    pcall(O.changeHotkeyProfile, name)
  end
end

-- ---------------------------------------------------------------- drawing
local function refreshButtons()
  if not window then return end
  local slot = slotOf(selected)
  local b = V.buttons(state, slot, elapsed())
  window.buttons.saveButton:setEnabled(b.save)
  window.buttons.saveButton:setText(b.saveText or tr('Save'))
  window.buttons.loadButton:setEnabled(b.load)
  window.buttons.renameButton:setEnabled(b.rename)
  window.buttons.deleteButton:setEnabled(b.delete)
  window.buttons.deleteButton:setText(confirmDelete == selected and tr('Confirm') or tr('Delete'))
  local hint, color = V.switchHint(state, elapsed())
  window.hint:setText(hint)
  window.hint:setColor(color)
end

local function refreshDetail()
  if not window then return end
  local slot = slotOf(selected)
  local row = V.slotRow(state, slot)
  window.detailPlate.detailName:setText(row.title)
  window.detailPlate.detailIcon:setImageSource(row.icon)
  local list = window.detail.summary
  list:destroyChildren()
  for _, line in ipairs(V.summary(state, slot, slot and not slot.empty and profileOf(slot.slot) or nil)) do
    local w = g_ui.createWidget('LoadoutLine', list)
    w:setText(line.text)
    w:setColor(line.color)
  end
  window.nameEdit:setText(slot and not slot.empty and slot.name or '')
  iconChoice = slot and not slot.empty and slot.icon or (state and state.icons and state.icons[1]) or 'skills'
  window.iconButton:setImageSource(V.iconPath(iconChoice))
  refreshButtons()
end

-- the selected row gets a gold border
local function highlight()
  if not window then return end
  for _, w in ipairs(window.slotList:getChildren()) do
    local on = w.slotNumber == selected
    w:setBorderWidth(on and 1 or 0)
    w:setBorderColor(on and V.COLORS.gold or '#00000000')
  end
end

local function selectRow(n)
  if selected ~= n then confirmDelete = nil end
  selected = n
  highlight()
  refreshDetail()
end

local function refreshList()
  if not window then return end
  local list = window.slotList
  list:destroyChildren()
  selected = V.pickSelection(state, selected)
  for _, slot in ipairs(state and state.slots or {}) do
    local row = V.slotRow(state, slot)
    local w = g_ui.createWidget('LoadoutRow', list)
    w.icon:setImageSource(row.icon)
    w.icon:setOpacity(row.dim and 0.45 or 1)
    w.title:setText(row.title)
    w.title:setColor(row.dim and V.COLORS.dim or V.COLORS.gold)
    w.sub:setText(row.sub)
    w.tag:setText(row.tag)
    w.tag:setColor(row.tagColor)
    local n = slot.slot
    w.slotNumber = n
    w.onClick = function() selectRow(n) end
  end
  highlight()
  refreshDetail()
end

-- ---------------------------------------------------------------- server messages
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    state, stateAt = data, g_clock.millis()
    refreshList()
  elseif msg.action == 'result' then
    setStatus(V.resultText(data), data.ok and V.COLORS.good or V.COLORS.bad)
    if data.ok and pending then
      if pending.action == 'save' then
        rememberProfile(pending.slot)
      elseif pending.action == 'load' then
        applyProfile(pending.slot)
      end
    end
    pending = nil
  elseif msg.action == 'cast' then
    setStatus(tr('Switching loadout... stand still.'), V.COLORS.active)
  elseif msg.action == 'castEnd' then
    if data.result ~= 'done' then pending = nil end
  end
end

-- ---------------------------------------------------------------- buttons
function saveSelected()
  if not window or not selected then return end
  pending = { action = 'save', slot = selected }
  send('save', { slot = selected, name = window.nameEdit:getText(), icon = iconChoice })
end

function loadSelected()
  if not selected then return end
  pending = { action = 'load', slot = selected }
  send('load', { slot = selected })
end

function renameSelected()
  if not window or not selected then return end
  send('rename', { slot = selected, name = window.nameEdit:getText(), icon = iconChoice })
end

function deleteSelected()
  if not selected then return end
  if confirmDelete ~= selected then
    confirmDelete = selected
    local slot = slotOf(selected)
    setStatus(string.format(tr('Click Confirm to delete %s.'), slot and slot.name or ''), V.COLORS.warn)
    refreshButtons()
    return
  end
  confirmDelete = nil
  send('delete', { slot = selected })
end

function cycleIcon()
  if not window then return end
  iconChoice = V.nextIcon(state and state.icons, iconChoice)
  window.iconButton:setImageSource(V.iconPath(iconChoice))
end

function show()
  if not window then return end
  send('open')
  window:show()
  window:raise()
  window:focus()
  removeEvent(tickEvent)
  tickEvent = cycleEvent(safe('tick', refreshButtons), 1000)
end

function hide()
  removeEvent(tickEvent)
  tickEvent = nil
  confirmDelete = nil
  if window then window:hide() end
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

-- for other modules and tests
function getState()
  return { state = state, selected = selected, visible = window and window:isVisible() or false }
end

function selectSlot(n)
  selectRow(n)
end

-- ---------------------------------------------------------------- menu and the passive tree button
local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'character',
      { text = 'Loadouts', icon = 'inventory', modules = { 'game_loadouts' }, fns = { 'toggle' } })
  end
end

-- a Loadouts button in the passive tree window, made here at runtime (game_passivetree is not changed)
local function addTreeButton()
  local tree = modules.game_passivetree
  local getWindow = tree and rawget(tree, 'getTreeWindow')
  local treeWindow = type(getWindow) == 'function' and getWindow() or nil
  if not treeWindow or treeWindow:getChildById('loadoutsButton') then return end
  local ok, button = pcall(g_ui.createWidget, 'TreeButton', treeWindow)
  if not ok or not button then
    ok, button = pcall(g_ui.createWidget, 'ChaosButton', treeWindow)
  end
  if not ok or not button then return end
  button:setId('loadoutsButton')
  button:setText(tr('Loadouts'))
  button:setTooltip(tr('Save and switch whole builds (free between saved loadouts)'))
  button:setWidth(110)
  local after = treeWindow:getChildById('trialsButton') or treeWindow:getChildById('buildShareButton')
  if after then
    button:addAnchor(AnchorTop, after:getId(), AnchorTop)
    button:addAnchor(AnchorLeft, after:getId(), AnchorRight)
    button:setMarginLeft(5)
  else
    button:addAnchor(AnchorTop, 'parent', AnchorTop)
    button:addAnchor(AnchorRight, 'parent', AnchorRight)
    button:setMarginTop(40)
    button:setMarginRight(10)
  end
  button.onClick = function() toggle() end
end

local function onGameStart()
  state, selected, pending, confirmDelete = nil, nil, nil, nil
  addMenu()
  removeEvent(treeEvent)
  treeEvent = cycleEvent(safe('treeButton', addTreeButton), 2000)
end

local function onGameEnd()
  hide()
  removeEvent(treeEvent)
  treeEvent = nil
  state = nil
end

function init()
  g_ui.importStyle('loadouts')
  local ok, ui = pcall(g_ui.createWidget, 'LoadoutsWindow', rootWidget)
  if ok and ui then
    window = ui
    window:hide()
  else
    g_logger.warning('[loadouts] window not loaded: ' .. tostring(ui))
  end
  handlers.opcode = safe('opcode', onMessage)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  addMenu()
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game)
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  removeEvent(tickEvent)
  removeEvent(treeEvent)
  local tree = modules.game_passivetree
  local getWindow = tree and rawget(tree, 'getTreeWindow')
  local treeWindow = type(getWindow) == 'function' and getWindow() or nil
  local button = treeWindow and treeWindow:getChildById('loadoutsButton')
  if button then button:destroy() end
  if window then window:destroy() window = nil end
  handlers = {}
end
