-- Pets window: the pets the character owns (level, XP, abilities), summon / dismiss / rename, and how to get the
-- others. Server: server/data/scripts/chaos/pets.lua, extended opcode 254 (JSON {action, data}).
--   server -> client  state {open, pets, catalog, active, out, rest, zone, cooldowns, maxLevel, secondAt}  (petsview.lua)
--                     xp {species, level, xp, into, need, pct}                    (a kill while the window is open)
--   client -> server  open | get | close | summon {species} | dismiss | rename {species, name}
-- The top menu (Character > Pets) calls toggle().

local OPCODE = 254
local V = PetsView

local window
local state
local entries = {}
local selected
local rowWidgets = {}
local refreshEvent

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function setOutfit(widget, look)
  if widget and look and look > 0 then
    widget:setOutfit({ type = look })
  end
end

-- ---------------------------------------------------------------- detail
local function showDetail()
  if not window then return end
  local d = window.detail
  local e = V.find(entries, selected)
  d:setVisible(e ~= nil)
  if not e then return end
  setOutfit(d.creature, e.look)
  d.nameLabel:setText(V.titleText(e))
  d.speciesLabel:setText(e.owned and (e.speciesName .. ((e.pet and e.pet.element) and ('  -  ' .. e.pet.element) or ''))
    or tr('Not owned yet'))
  d.xpBar:setVisible(e.owned)
  if e.owned and e.pet then
    d.xpBar:setPercent(tonumber(e.pet.pct) or 0)
    d.xpBar:setText(V.xpText(e.pet))
  end
  d.abilities:destroyChildren()
  for _, line in ipairs(V.abilityLines(e, state and state.secondAt)) do
    local w = g_ui.createWidget('PetAbility', d.abilities)
    w.title:setText(line.title)
    w.text:setText(line.lockText and (line.text .. '  ' .. line.lockText) or line.text)
    if line.locked then
      w.title:setColor('#8c8070')
      w.text:setColor('#6b6258')
    end
  end
  d.howLabel:setText(e.owned and '' or (tr('How to get it:') .. ' ' .. e.how))
  local b = V.buttons(e, state)
  d.summonButton:setEnabled(b.summon)
  d.dismissButton:setEnabled(b.dismiss)
  d.renameButton:setEnabled(b.rename)
  d.nameEdit:setEnabled(b.rename)
  d.nameEdit:setVisible(b.rename)
  d.renameButton:setVisible(b.rename)
end

local function selectEntry(key)
  if window and key ~= selected then window.detail.nameEdit:setText('') end
  selected = key
  for k, w in pairs(rowWidgets) do
    if k == key then w:focus() end
  end
  showDetail()
end

-- the order of the rows; the list is only rebuilt when it changes (a refresh keeps the scroll position)
local function signature(list)
  local keys = {}
  for _, e in ipairs(list) do keys[#keys + 1] = e.key .. (e.owned and '+' or '-') end
  return table.concat(keys, ',')
end
local shownSignature

-- ---------------------------------------------------------------- list
local function showList()
  if not window then return end
  entries = V.entries(state)
  local wanted = V.pick(entries, selected, state and state.active)
  if signature(entries) == shownSignature then
    for _, e in ipairs(entries) do
      local row = rowWidgets[e.key]
      if row then
        row.name:setText(V.rowText(e))
        row.sub:setText(V.rowSub(e, state))
      end
    end
    window.statusLabel:setText(V.statusText(state))
    selectEntry(wanted)
    return
  end
  shownSignature = signature(entries)
  window.petList:destroyChildren()
  rowWidgets = {}
  for _, e in ipairs(entries) do
    local row = g_ui.createWidget('PetRow', window.petList)
    setOutfit(row.creature, e.look)
    row.name:setText(V.rowText(e))
    row.sub:setText(V.rowSub(e, state))
    if not e.owned then
      row.name:setColor('#8c8070')
      row.creature:setOpacity(0.45)
    end
    local key = e.key
    row.onClick = function() selectEntry(key) end
    rowWidgets[key] = row
  end
  window.statusLabel:setText(V.statusText(state))
  selectEntry(wanted)
end

-- ---------------------------------------------------------------- actions (buttons in pets.otui)
function summonSelected()
  if selected then send('summon', { species = selected }) end
end

function dismiss()
  send('dismiss')
end

function renameSelected()
  if not window or not selected then return end
  local name = V.cleanName(window.detail.nameEdit:getText())
  if name then send('rename', { species = selected, name = name }) end
end

-- ---------------------------------------------------------------- protocol
local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[pets] invalid JSON: ' .. tostring(msg))
    return
  end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    state = data
    showList()
    if data.open then show() end
  elseif msg.action == 'xp' then
    if state and V.applyXp(state, data) then
      local e = V.find(V.entries(state), data.species)
      local row = rowWidgets[data.species]
      if row and e then row.sub:setText(V.rowSub(e, state)) end
      if selected == data.species then
        entries = V.entries(state)
        showDetail()
      end
    end
  end
end

-- cooldowns count down on the server; while the window is open ask for a fresh state now and then
local function scheduleRefresh()
  if refreshEvent then removeEvent(refreshEvent) end
  refreshEvent = scheduleEvent(function()
    refreshEvent = nil
    if window and window:isVisible() then
      send('get')
      scheduleRefresh()
    end
  end, 3000)
end

-- ---------------------------------------------------------------- window
function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  scheduleRefresh()
end

function hide()
  if window and window:isVisible() then
    window:hide()
    send('close')
  end
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
    return
  end
  send('open')
end

local function onGameEnd()
  if window then window:hide() end
  state, entries, selected, rowWidgets, shownSignature = nil, {}, nil, {}, nil
  if window then window.petList:destroyChildren() end
end

function init()
  window = g_ui.displayUI('pets')
  window:hide()
  window.detail.nameEdit.onKeyPress = function(widget, keyCode)
    if keyCode == KeyEnter then
      renameSelected()
      return true
    end
    return false
  end
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if refreshEvent then removeEvent(refreshEvent) end
  refreshEvent = nil
  if window then
    window:destroy()
    window = nil
  end
  state, entries, rowWidgets, shownSignature = nil, {}, {}, nil
end
