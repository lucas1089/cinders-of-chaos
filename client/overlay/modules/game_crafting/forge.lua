-- The forge window (O481, owner request 2026-11-11): the crafting bench as "place the item, pick an action, check the
-- change, forge". It shares extended opcode 232 with the classic bench (crafting.lua forwards every message here);
-- forgeview.lua decides what it shows, the server (crafting.lua, chaos_crafting.lua C.explain) says what will happen.
-- Messages and fields: see the head of forgeview.lua. The window asks for the additive fields with open {forge = 1}.
-- A "Classic" button switches to the classic window (crafting.lua) and back; the choice is remembered per character
-- (g_settings node chaosForge). The Salvage tab opens the classic window in its Salvage tab, the Guide tab the Guide.
-- Nothing is computed here: counts, words, tags and costs come from the server through forgeview.lua; the window sends
-- "apply" only for an action the server has explained for this very item (forgeview.lua V.request).

local OPCODE = 232
local SELECT_BG = '#2a2114'
local SELECT_BORDER = '#e8b84a'
local BASE_BORDER = '#4a3d2c'
local STEP_DONE, STEP_NOW, STEP_LATER = '#7fe0a0', '#e8b84a', '#6b6258'

CraftingForge = CraftingForge or {}
local F = CraftingForge
local V = CraftingForgeView

local fw                 -- the window
local info               -- the orbs and the reason texts (server "info")
local forgeInfo          -- {orbs = {key -> {kind, safety}}} (server "forgeinfo")
local state              -- last state
local lastExplain        -- last "explain" answer
local requested          -- the question asked last (orb|mod|sig): the same one is not asked twice
local sel = { orb = nil, mod = nil, tab = 'mod' }
local mode = 'forge'     -- 'forge' | 'classic' (remembered per character)
local pending = false    -- an apply was sent, the next state has not come yet
local resultText, resultOk = '', true
local confirmBox
F.classicOnce = false    -- the classic window is wanted once (the menu's Salvage entry, the Salvage tab)

local okText, Text = pcall(dofile, '/modules/game_spellsupports/supportstext.lua')
if not okText or type(Text) ~= 'table' then Text = nil end
-- the item tooltip's tier colours (V.tierColor reads ItemTooltipLogic when it is loaded)
pcall(dofile, '/modules/game_itemtooltip/tooltiplogic.lua')

-- ---------------------------------------------------------------- helpers
local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function w(id) return fw and fw:recursiveGetChildById(id) or nil end

local function rows(value)
  local out = {}
  if type(value) == 'table' then
    for _, v in ipairs(value) do
      if type(v) == 'table' then out[#out + 1] = v end
    end
  end
  return out
end

local function setTip(widget, text)
  if text and text ~= '' then
    local out = {}
    for line in (tostring(text) .. '\n'):gmatch('(.-)\n') do
      out[#out + 1] = Text and Text.wrap(line, 64, '  ') or line
    end
    widget:setTooltip(table.concat(out, '\n'))
  else
    widget:removeTooltip()
  end
end

local function ctx()
  return { info = info, forge = forgeInfo, state = state or {}, sel = sel, explain = lastExplain, mod = sel.mod }
end

local function characterName()
  local ok, name = pcall(function() return g_game.getCharacterName() end)
  return ok and name or nil
end

local function settingsNode()
  local ok, node = pcall(g_settings.getNode, V.SETTINGS)
  return (ok and type(node) == 'table') and node or {}
end

local function loadMode()
  mode = V.savedMode(settingsNode(), characterName())
end

local function saveMode(m)
  mode = m
  pcall(g_settings.setNode, V.SETTINGS, V.rememberMode(settingsNode(), characterName(), m))
  pcall(g_settings.save)
end

-- ---------------------------------------------------------------- answers
local function ask()
  local item = state and state.item
  if not item or not sel.orb then return end
  local a = V.find(V.actions(ctx()), sel.orb)
  if not a or not a.itemOk then return end
  if a.kind == 'mod' then
    if not sel.mod then return end
    if not V.contains(type(item.pick) == 'table' and item.pick[a.key] or nil, sel.mod) then return end
  end
  local key = table.concat({ sel.orb, sel.mod or '', tostring(item.sig or '') }, '|')
  if key == requested then return end
  requested = key
  send('explain', { orb = sel.orb, path = item.path, id = item.id, sig = item.sig, mod = sel.mod })
end

-- ---------------------------------------------------------------- drawing
local render

local function renderSteps()
  local cur, done = V.step(ctx())
  for i = 1, 4 do
    local label = w('step' .. i)
    label:setText(string.format('%d %s', i, V.stepLabel(i)))
    label:setColor(done[i] and STEP_DONE or (i == cur and STEP_NOW or STEP_LATER))
  end
  for i = 1, 3 do w('arrow' .. i):setText('>') end
end

local function renderMaterials()
  local list = w('matsList')
  list:destroyChildren()
  for _, m in ipairs(V.materials(ctx())) do
    local cell = g_ui.createWidget('ForgeMaterial', list)
    cell.icon:setItemId(m.clientId)
    cell.text:setText(string.format('%s %s', m.name, tostring(m.count)))
    cell.text:setColor(m.dim and STEP_LATER or '#d6c9ae')
    cell:setOpacity(m.dim and 0.5 or 1.0)
    setTip(cell, m.tip)
  end
end

local function renderItem()
  local item = state and state.item
  local h = V.header(item)
  w('itemName'):setText(h.name)
  w('itemName'):setColor(h.color)
  w('itemLine'):setText(h.line)
  w('itemFree'):setText(h.free)
  local slot = w('itemSlot')
  slot:setItemId(item and tonumber(item.clientId) or 0)
  w('lockButton'):setVisible(item ~= nil and item.kind ~= 'riftkey')
  w('lockButton'):setText(item and item.locked and tr('Unlock') or tr('Lock'))
  w('changeButton'):setVisible(item ~= nil)
end

local TAB_ID = { mod = 'tabMod', add = 'tabAdd', whole = 'tabWhole', sockets = 'tabSockets', salvage = 'tabSalvage', guide = 'tabGuide' }

local function renderTabs(actions)
  local item = state and state.item
  local shown = {}
  for _, t in ipairs(V.tabs(actions, item)) do
    shown[t.id] = true
    local b = w(TAB_ID[t.id])
    b:setText(V.tabText(t))
    b:setVisible(true)
    b:setChecked(t.id == sel.tab)
  end
  for id, widget in pairs(TAB_ID) do
    if not shown[id] then w(widget):setVisible(false) end
  end
  if not shown[sel.tab] then sel.tab = 'mod' end
end

local function renderMods(item)
  local list = w('modList')
  list:destroyChildren()
  local groups = V.groupList(item)
  if #groups == 0 then
    local note = g_ui.createWidget('ForgeNoteLabel', list)
    note:setText(tr('This item has no modifiers.'))
  end
  for _, g in ipairs(groups) do
    local head = g_ui.createWidget('ForgeGroupLabel', list)
    head:setText(g.label)
    head:setColor(g.side == 'implicit' and '#d04040' or '#8c8070')
    for _, r in ipairs(g.rows) do
      local row = g_ui.createWidget('ForgeModRow', list)
      row.tier:setText(r.tierText)
      row.tier:setColor(r.color)
      row.text:setText(r.range and (r.text .. '  ' .. r.range) or r.text)
      row.text:setColor(r.implicit and '#d04040' or (r.power and '#ff9a3c' or '#e4d8c0'))
      row.mark:setText(r.mark)
      if r.bound then
        setTip(row, tr('Bound: the orbs that change modifiers leave it alone. Only an Orb of Erasure frees it.'))
      end
      local key = r.key
      local chosen = key ~= nil and key == sel.mod
      row:setBackgroundColor(chosen and SELECT_BG or '#00000000')
      row:setBorderWidth(1)
      row:setBorderColor(chosen and SELECT_BORDER or '#00000000')
      row.onMouseRelease = function(self, mousePos, button)
        if button ~= MouseLeftButton or not self:containsPoint(mousePos) or not key then return false end
        sel.mod = (sel.mod ~= key) and key or nil
        requested, lastExplain = nil, nil
        ask()
        render()
        return true
      end
    end
  end
  if item and item.veil == 1 then
    local note = g_ui.createWidget('ForgeNoteLabel', list)
    note:setText(tr('This item has a veiled modifier: an Orb of Unveiling reveals it.'))
    note:setColor('#c070ff')
  elseif item and item.rewards then
    local note = g_ui.createWidget('ForgeNoteLabel', list)
    note:setText(tr('Rewards: %s', item.rewards))
    note:setColor('#9fdc7f')
  end
end

local function renderSockets(item)
  local list = w('modList')
  list:destroyChildren()
  local s = type(item.sockets) == 'table' and item.sockets or {}
  local count = tonumber(s.count) or 0
  local head = g_ui.createWidget('ForgeGroupLabel', list)
  head:setColor('#e8b84a')
  if count == 0 then
    head:setText(tr('No sockets (an Orb of Sockets gives up to %d)', tonumber(s.max) or 0))
    return
  end
  local filled = 0
  for _, row in ipairs(rows(s.list)) do
    if (tonumber(row.id) or 0) > 0 then filled = filled + 1 end
  end
  head:setText(tr('Sockets: %d / %d', filled, count))
  for _, row in ipairs(rows(s.list)) do
    local widget = g_ui.createWidget('ForgeSocketRow', list)
    local id, index = tonumber(row.id) or 0, row.index
    if id > 0 then
      widget.icon:setItemId(tonumber(row.clientId) or 0)
      widget.name:setText(row.name or '?')
      widget.name:setColor(row.color or '#d6c9ae')
      widget.text:setText(row.text or '')
      widget.removeButton:setText(tostring(tonumber(row.cost) or 0))
      setTip(widget.removeButton, tr('Take the gem out for %d gold (bank first, then the backpack). It comes back to you.', tonumber(row.cost) or 0))
      widget.shatterButton:setTooltip(tr('Take the gem out for free: it is destroyed.'))
      widget.removeButton.onClick = function()
        widget.removeButton:setEnabled(false)
        send('gem', { op = 'remove', socket = index, path = item.path, id = item.id, sig = item.sig })
      end
      widget.shatterButton.onClick = function()
        widget.shatterButton:setEnabled(false)
        send('gem', { op = 'shatter', socket = index, path = item.path, id = item.id, sig = item.sig })
      end
    else
      widget.icon:setVisible(false)
      widget.name:setText(tr('Empty socket'))
      widget.name:setColor('#8c8070')
      widget.text:setText(tr('Use a gem with the item to fill it'))
      widget.text:setColor(STEP_LATER)
      widget.removeButton:setVisible(false)
      widget.shatterButton:setVisible(false)
    end
  end
end

local function actionsTitle()
  if sel.tab == 'mod' then return tr('SHAPE THIS MODIFIER')
  elseif sel.tab == 'add' then return tr('ADD A MODIFIER')
  elseif sel.tab == 'whole' then return tr('CHANGE THE WHOLE ITEM')
  elseif sel.tab == 'sockets' then return tr('SOCKETS')
  end
  return ''
end

local function renderActions(actions)
  local list = w('actionList')
  list:destroyChildren()
  w('actionsLabel'):setText(actionsTitle())
  for _, a in ipairs(V.ofKind(actions, sel.tab)) do
    local b = g_ui.createWidget('ForgeActionButton', list)
    b.icon:setItemId(a.clientId)
    b.verb:setText(a.verb)
    b.count:setText('x' .. tostring(a.total))
    local chosen = sel.orb == a.key
    b:setBorderColor(chosen and SELECT_BORDER or BASE_BORDER)
    b:setBackgroundColor(chosen and '#3a2e1e' or '#241d16')
    b:setEnabled(a.can)
    b:setOpacity(a.can and 1.0 or 0.45)
    local tip = a.name .. '\n' .. a.text
    if not a.can then tip = tip .. '\n' .. a.why end
    setTip(b, tip)
    local key = a.key
    b.onMouseRelease = function(self, mousePos, button)
      if button ~= MouseLeftButton or not self:containsPoint(mousePos) or not self:isEnabled() then return false end
      sel.orb = (sel.orb ~= key) and key or nil
      requested, lastExplain = nil, nil
      ask()
      render()
      return true
    end
  end
end

local function renderWhat(actions)
  local title, tag, text, cost = w('whatTitle'), w('whatTag'), w('whatText'), w('whatCost')
  local item = state and state.item
  local a = sel.orb and V.find(actions, sel.orb) or nil
  if not item then
    title:setText(tr('Put an item on the bench first.'))
    tag:setText('')
    text:setText('')
    cost:setText('')
    return
  end
  if not a then
    title:setText(tr('What happens'))
    tag:setText('')
    text:setText(tr('Pick an action on the right. The server tells you here what it will do before you forge.'))
    text:setColor('#8c8070')
    cost:setText('')
    return
  end
  title:setText(a.verb)
  tag:setText(V.tagLabel(a.tag))
  tag:setColor(V.tagColor(a.tag))
  cost:setText(V.costLine(a))
  if not a.can then
    text:setText(a.why)
    text:setColor('#e8582a')
  elseif V.answered(ctx()) then
    text:setText(V.explainText(lastExplain))
    text:setColor(lastExplain.ok == false and '#e8582a' or '#f2e6cc')
  else
    text:setText(tr('Asking the server...'))
    text:setColor('#8c8070')
  end
end

local function renderBar()
  local bar = V.bar(ctx())
  w('barSummary'):setText(bar.summary)
  w('barDetail'):setText(bar.detail)
  w('barCost'):setText(bar.cost)
  local b = w('forgeButton')
  b:setEnabled(bar.can and not pending)
  setTip(b, bar.can and '' or bar.why)
end

local function renderResult()
  local label = w('resultLabel')
  label:setText(resultText)
  label:setColor(resultOk and '#9fdc7f' or '#e03a1e')
  setTip(label, resultText)
end

local function renderGear()
  local list = w('gearList')
  list:destroyChildren()
  local items = rows(state and state.items)
  for _, it in ipairs(items) do
    local slot = g_ui.createWidget('ForgeGearSlot', list)
    slot:setItemId(tonumber(it.clientId) or 0)
    local rarity = tonumber(it.rarity) or 0
    local tip = it.name or ''
    if it.unique then tip = tip .. '\n' .. tr('Unique')
    elseif it.key then tip = tip .. '\n' .. tr('Rift Key')
    elseif rarity > 0 then tip = tip .. '\n' .. (it.rarityName or tr('Rarity %d', rarity)) end
    if rarity > 0 or it.unique or it.key then
      slot:setBorderWidth(1)
      slot:setBorderColor(it.unique and '#e8582a' or it.key and V.KEY_COLOR or V.rarityColor(rarity))
    end
    if it.locked then
      tip = tip .. '\n' .. tr('Locked')
      slot:setOpacity(0.55)
    end
    setTip(slot, tip)
    local path, id = it.path, it.id
    slot.onMouseRelease = function(self, mousePos, button)
      if button == MouseLeftButton and self:containsPoint(mousePos) then
        resultText = ''
        send('select', { path = path, id = id })
        return true
      end
      return false
    end
    slot.onDragEnter = function() return false end -- the grid is a picker, not a container
  end
  w('gearHint'):setText(tr('No gear or Rift Key in your backpack.'))
  w('gearHint'):setVisible(#items == 0)
end

function render()
  if not fw or not fw:isVisible() then return end
  local item = state and state.item
  local actions = V.actions(ctx())
  renderSteps()
  renderMaterials()
  renderItem()
  renderTabs(actions)
  local hasItem = item ~= nil
  w('gearPanel'):setVisible(not hasItem)
  w('leftPanel'):setVisible(hasItem)
  w('actionsLabel'):setVisible(hasItem)
  w('actionList'):setVisible(hasItem)
  w('actionScroll'):setVisible(hasItem)
  w('whatBox'):setVisible(hasItem)
  if hasItem then
    if sel.tab == 'sockets' then renderSockets(item) else renderMods(item) end
    renderActions(actions)
  else
    renderGear()
  end
  renderWhat(actions)
  renderBar()
  renderResult()
end

-- ---------------------------------------------------------------- protocol
local function onState(data)
  if type(data.item) ~= 'table' then data.item = nil end
  local before = state and state.item
  state = data
  pending = false
  local item = data.item
  if not item then
    sel.orb, sel.mod = nil, nil
  elseif before and before.path ~= item.path then
    sel.orb, sel.mod = nil, nil
  else
    sel.mod = V.keepSelection(item, sel.mod) -- the selection stays on the same modifier while it exists
  end
  requested, lastExplain = nil, nil
  if sel.orb then
    local a = V.find(V.actions(ctx()), sel.orb)
    if not a then sel.orb = nil end
  end
  ask()
  if data.open and F.wanted() then F.show() end
  render()
end

-- crafting.lua forwards every message of the opcode here
function F.onMessage(action, data)
  if action == 'info' then
    info = data
  elseif action == 'forgeinfo' then
    forgeInfo = data
  elseif action == 'state' then
    onState(data)
  elseif action == 'explain' then
    lastExplain = data
    render()
  elseif action == 'result' then
    resultText, resultOk = V.resultLine(data), data.ok ~= false
    pending = false
    render()
  end
end

-- ---------------------------------------------------------------- the window
function F.wanted()
  return fw ~= nil and mode == 'forge' and not F.classicOnce
end

function F.show()
  if not fw then return end
  fw:show()
  fw:raise()
  fw:focus()
  render()
end

function F.hide()
  if fw then fw:hide() end
end

function F.isVisible()
  return fw ~= nil and fw:isVisible()
end

function F.open()
  send('open', { forge = 1 })
end

function F.toggle()
  if not fw then return end
  if fw:isVisible() then
    F.hide()
    return
  end
  F.open()
end

function F.forge()
  if not fw or not fw:isVisible() or pending then return end
  local req, why = V.request(ctx())
  if not req then
    if why and why ~= '' then
      resultText, resultOk = why, false
      renderResult()
    end
    return
  end
  local bar = V.bar(ctx())
  local function go()
    if confirmBox then confirmBox:destroy() confirmBox = nil end
    pending = true
    resultText = ''
    renderBar()
    send('apply', req)
  end
  if bar.confirm and displayGeneralBox then
    if confirmBox then confirmBox:destroy() confirmBox = nil end
    local function no()
      if confirmBox then confirmBox:destroy() confirmBox = nil end
    end
    confirmBox = displayGeneralBox(tr('Forge'), bar.confirm,
      { { text = tr('Forge'), callback = go }, { text = tr('Cancel'), callback = no }, anchor = AnchorHorizontalCenter }, go, no)
  else
    go()
  end
end

function F.classic()
  saveMode('classic')
  F.classicOnce = false
  F.hide()
  send('open') -- no forge flag: the classic window answers
end

-- the Forge button of the classic window
function F.switchTo()
  saveMode('forge')
  F.classicOnce = false
  if hide then hide() end -- the classic window (crafting.lua)
  F.open()
end

function F.tab(id)
  if id == 'salvage' then
    F.classicOnce = true
    F.hide()
    if openSalvage then openSalvage() end
    return
  elseif id == 'guide' then
    if showGuide then showGuide() end
    return
  end
  if sel.tab ~= id then
    sel.tab = id
    local a = sel.orb and V.find(V.actions(ctx()), sel.orb)
    if a and a.kind ~= id then sel.orb = nil end
    requested, lastExplain = nil, nil
  end
  render()
end

function F.lock()
  local item = state and state.item
  if not item then return end
  send('lock', { path = item.path, id = item.id, on = not item.locked })
end

function F.change()
  send('clear')
end

-- an item dragged from a container onto the slot
local function onSlotDrop(self, widget, mousePos)
  local item = widget and widget.currentDragThing
  if not item or not item.isItem or not item:isItem() then return false end
  local pos = item:getPosition()
  if not pos or pos.x ~= 65535 then
    resultText, resultOk = tr('Only items from your backpack can go on the bench.'), false
    renderResult()
    return true
  end
  resultText = ''
  send('select', { pos = { x = pos.x, y = pos.y, z = pos.z }, clientId = item:getId() })
  return true
end

function F.onGameStart()
  loadMode()
end

function F.onGameEnd()
  F.hide()
  state, lastExplain, requested = nil, nil, nil
  sel.orb, sel.mod, sel.tab = nil, nil, 'mod'
  pending, F.classicOnce = false, false
  resultText = ''
  if confirmBox then confirmBox:destroy() confirmBox = nil end
end

function F.init()
  fw = g_ui.displayUI('forge')
  fw:hide()
  pcall(function() modules.game_howitworks.attach(fw, 'crafting') end)
  local slot = fw:recursiveGetChildById('itemSlot')
  slot.onDrop = onSlotDrop
  slot.onMouseRelease = function(self, mousePos, button)
    if button == MouseRightButton and state and state.item then
      send('clear')
      return true
    end
    return false
  end
  connect(g_game, { onGameStart = F.onGameStart, onGameEnd = F.onGameEnd })
  if g_game.isOnline() then F.onGameStart() end
end

function F.terminate()
  disconnect(g_game, { onGameStart = F.onGameStart, onGameEnd = F.onGameEnd })
  if confirmBox then confirmBox:destroy() confirmBox = nil end
  if fw then
    fw:destroy()
    fw = nil
  end
  state, info, forgeInfo, lastExplain = nil, nil, nil, nil
end

-- what forge.otui and crafting.otui call (modules.game_crafting.X)
function forgeHide() F.hide() end
function forgeNow() F.forge() end
function forgeClassic() F.classic() end
function forgeSwitchTo() F.switchTo() end
function forgeLock() F.lock() end
function forgeChange() F.change() end
function forgeTab(id) F.tab(id) end
