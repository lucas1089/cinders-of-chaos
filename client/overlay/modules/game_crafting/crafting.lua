-- Crafting bench: put an item (or a Rift Key) from the backpack on the bench, see its rarity and modifiers and what
-- each orb would do, apply an orb. The bench is optional: every orb also works by "Use with" on the item.
-- Server: server/data/scripts/chaos/crafting.lua and data/lib/chaos_crafting.lua, extended opcode 232 (JSON).
--   server -> client  state {open, orbs = [{key, id, clientId, name, text, keyText, count}], item = {path, clientId,
--                            name, kind, rarity, rarityName, level, mods = [{group, text}], maxMods, rewards, unique,
--                            orbs = {key -> ""|why}, preview = {key -> text},
--                            sockets = {count, max, list = [{index, id, clientId, name, text, color, cost}]}, sig} | nil,
--                            items = [{path, id, clientId, name, rarity, rarityName, unique, key}],
--                            history = [{time, orb, item, text}]}
--                     result {ok, orb, text}
--   client -> server  open | select {path, id} | select {pos, clientId} | apply {orb, path, id, sig} |
--                     gem {op = "remove"|"shatter", socket, path, id, sig} | clear
-- Sockets (gems, server data/lib/chaos_gems.lua) are listed under the modifiers: a gem can be taken out for gold
-- (Remove, it comes back) or destroyed (Shatter); socketing and combining are done by Use with on the gem.
-- Salvage tab (server data/scripts/chaos/salvage.lua, same opcode): state.salvage = {installed, shardClientId,
-- shardName, shards, rarityNames, recipes = [{key, name, clientId, cost, count}], bags = [{path, name}], batch = {bag,
-- maxRarity, count, shards, orbs, capped, cap, skipped, sig, paths}, mode}; state.items[i].locked, state.item.locked,
-- state.item.salvage = {ok, why, shards, orbChance}. Client -> server: salvage {path, id, sig} | lock {path, id, on} |
-- salvageScope {bag, maxRarity, mode} | salvageBatch {bag, maxRarity, sig} | combine {key, count}.
-- The server checks everything (orb owned, item in the backpack, orb fits the item, no uniques); the buttons here only
-- mirror its answer. !craft opens it from the chat; the top menu (Chaos -> Crafting Bench) calls toggle().

local OPCODE = 232

-- rarity 1..15 (names from the server): text colours from grey to red, like the loot messages
local RARITY_COLOR = {
  '#c4cebc', '#5fd35f', '#4a8cff', '#b070ff', '#f6cf72', '#ff9c3a', '#d860ff', '#e03a1e', '#7fe6ff',
  '#ffe680', '#c0a0ff', '#9fe0ff', '#ff70c0', '#ff4040', '#ffffff'
}
local GROUP_COLOR = { absorb = '#7fa8ff', skill = '#9fdc7f', special = '#f6cf72', element = '#ff8a5a',
  chaos = '#ff70c0', rift = '#c0a0ff' }
local KEY_COLOR = '#c0a0ff' -- Rift Keys

local window
local state        -- last state from the server
local orbRows = {} -- orb key -> row widget
local mode = 'orbs' -- 'orbs' | 'salvage' (the tabs)
local updatingUi = false -- filling the salvage combo boxes: no requests
local confirmBox -- the "salvage all" confirmation
local batchPaths -- path -> true for the items the "salvage all" preview takes

-- ---------------------------------------------------------------- helpers
local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function list(value)
  local out = {}
  if type(value) == 'table' then
    for _, v in ipairs(value) do out[#out + 1] = v end
  end
  return out
end

local function rarityColor(r)
  return RARITY_COLOR[tonumber(r) or 0] or '#d6c9ae'
end

local function short(n)
  n = tonumber(n) or 0
  if formatShortNumber then return formatShortNumber(n) end
  return tostring(n)
end

local function setResult(text, ok)
  if not window then return end
  window.resultLabel:setText(text or '')
  window.resultLabel:setColor(ok == false and '#e03a1e' or '#9fdc7f')
end

-- ---------------------------------------------------------------- sockets
local function gold(n)
  n = tonumber(n) or 0
  if n >= 1000000 then return string.format('%.1fM', n / 1000000) end
  if n >= 1000 then return string.format('%dk', math.floor(n / 1000)) end
  return tostring(n)
end

local function showSockets(item)
  local s = type(item.sockets) == 'table' and item.sockets or nil
  local count = s and tonumber(s.count) or 0
  if not s or (count == 0 and (tonumber(s.max) or 0) == 0) then return end
  local filled = 0
  for _, row in ipairs(list(s.list)) do
    if (tonumber(row.id) or 0) > 0 then filled = filled + 1 end
  end
  local head = g_ui.createWidget('CraftModLabel', window.modList)
  head:setColor('#e8b84a')
  if count == 0 then
    head:setText(tr('No sockets (an Orb of Sockets gives up to %d)', tonumber(s.max) or 0))
    return
  end
  head:setText(tr('Sockets: %d / %d', filled, count))
  for _, row in ipairs(list(s.list)) do
    local w = g_ui.createWidget('CraftSocketRow', window.modList)
    local id = tonumber(row.id) or 0
    local index = row.index
    if id > 0 then
      w.icon:setItemId(tonumber(row.clientId) or 0)
      w.name:setText(row.name or '?')
      w.name:setColor(row.color or '#d6c9ae')
      w.text:setText(row.text or '')
      w:setTooltip(tr('%s\n%s', row.name or '', row.text or ''))
      w.removeButton:setText(gold(row.cost))
      w.removeButton:setTooltip(tr('Take the gem out for %d gold (bank first, then the backpack). It comes back to you.', tonumber(row.cost) or 0))
      w.shatterButton:setTooltip(tr('Take the gem out for free: it is destroyed.'))
      w.removeButton.onClick = function()
        w.removeButton:setEnabled(false)
        send('gem', { op = 'remove', socket = index, path = item.path, id = item.id, sig = item.sig })
      end
      w.shatterButton.onClick = function()
        w.shatterButton:setEnabled(false)
        send('gem', { op = 'shatter', socket = index, path = item.path, id = item.id, sig = item.sig })
      end
    else
      w.icon:setVisible(false)
      w.name:setText(tr('Empty socket'))
      w.name:setColor('#8c8070')
      w.text:setText(tr('Use a gem with the item to fill it'))
      w.text:setColor('#6b6258')
      w.removeButton:setVisible(false)
      w.shatterButton:setVisible(false)
    end
  end
end

-- ---------------------------------------------------------------- item panel
local function showItem(item)
  window.modList:destroyChildren()
  window.lockButton:setVisible(item ~= nil)
  if item then
    window.lockButton:setText(item.locked and tr('Unlock') or tr('Lock'))
    window.lockButton:setTooltip(item.locked and tr('Locked: salvage and the auto seller skip this item. Click to unlock.')
      or tr('Lock the item: salvage and the auto seller will skip it.'))
  end
  if not item then
    window.itemSlot:setItemId(0)
    window.itemName:setText(tr('Empty bench'))
    window.itemName:setColor('#e8b84a')
    window.itemRarity:setText('')
    window.itemSlots:setText('')
    window.emptyHint:setVisible(true)
    return
  end
  window.emptyHint:setVisible(false)
  window.itemSlot:setItemId(tonumber(item.clientId) or 0)
  window.itemName:setText(item.name or '?')
  local rarity = tonumber(item.rarity) or 0
  window.itemName:setColor(rarity > 0 and rarityColor(rarity) or '#d6c9ae')
  window.itemRarity:setTooltip('')
  if item.kind == 'riftkey' then
    window.itemName:setColor(KEY_COLOR)
    window.itemRarity:setText(tr('Rift Key, tier %d (level %d+)', tonumber(item.tier) or 0, tonumber(item.level) or 0))
    window.itemRarity:setColor(KEY_COLOR)
    window.itemRarity:setTooltip(item.rewards and tr('Rewards: %s', item.rewards) or '')
  elseif item.unique then
    window.itemRarity:setText(tr('Unique item: orbs cannot change it'))
    window.itemRarity:setColor('#e8582a')
  elseif rarity > 0 then
    window.itemRarity:setText(tr('%s, item level %d', item.rarityName or '?', tonumber(item.level) or 0))
    window.itemRarity:setColor(rarityColor(rarity))
  else
    window.itemRarity:setText(tr('Normal item'))
    window.itemRarity:setColor('#d6c9ae')
  end
  local mods = list(item.mods)
  if rarity > 0 or item.kind == 'riftkey' then
    window.itemSlots:setText(tr('Modifiers: %d / %d', #mods, tonumber(item.maxMods) or 0))
  else
    window.itemSlots:setText(#mods > 0 and tr('Modifiers: %d', #mods) or tr('No modifiers'))
  end
  for _, m in ipairs(mods) do
    local label = g_ui.createWidget('CraftModLabel', window.modList)
    label:setText(m.text or '')
    label:setColor(GROUP_COLOR[m.group] or '#d6c9ae')
  end
  if item.kind == 'riftkey' and item.rewards then
    local label = g_ui.createWidget('CraftModLabel', window.modList)
    label:setText(tr('Rewards: %s', item.rewards))
    label:setColor('#9fdc7f')
  end
  showSockets(item)
end

-- ---------------------------------------------------------------- orbs
local function updateOrbs()
  local item = state and state.item
  for _, orb in ipairs(list(state and state.orbs)) do
    local row = orbRows[orb.key]
    if row then
      local count = tonumber(orb.count) or 0
      row.icon:setItemId(tonumber(orb.clientId) or 0)
      row.icon:setItemCount(math.max(1, math.min(count, 100)))
      row.name:setText(orb.name or orb.key)
      row.count:setText(tr('You have %s', short(count)))
      row.count:setColor(count > 0 and '#8c8070' or '#6b6258')
      local why = ''
      if count <= 0 then
        why = tr('You have no %s.', orb.name or 'orb')
      elseif not item then
        why = tr('Put an item on the bench first.')
      elseif type(item.orbs) == 'table' and item.orbs[orb.key] and item.orbs[orb.key] ~= '' then
        why = item.orbs[orb.key]
      end
      -- what the orb would do to the item on the bench (the server's preview)
      local preview = why == '' and item and type(item.preview) == 'table' and item.preview[orb.key] or ''
      if preview ~= '' then
        row.count:setText(tr('You have %s', short(count)) .. '  |  ' .. preview)
        row.count:setColor('#9fdc7f')
      end
      local text = (item and item.kind == 'riftkey' and orb.keyText) or orb.text or ''
      row.use:setEnabled(why == '')
      row.use:setTooltip(why)
      row:setTooltip(text .. (preview ~= '' and ('\n' .. tr('Preview: %s', preview)) or '')
        .. (why ~= '' and ('\n' .. why) or ''))
      row:setOpacity(why == '' and 1.0 or 0.75)
    end
  end
end

local function buildOrbs()
  window.orbList:destroyChildren()
  orbRows = {}
  for _, orb in ipairs(list(state and state.orbs)) do
    local row = g_ui.createWidget('CraftOrbRow', window.orbList)
    local key = orb.key
    row.use.onClick = function()
      local item = state and state.item
      if not item then return end
      row.use:setEnabled(false) -- the next state enables it again
      send('apply', { orb = key, path = item.path, id = item.id, sig = item.sig })
    end
    orbRows[key] = row
  end
  updateOrbs()
end

-- ---------------------------------------------------------------- gear grid
local function buildGear()
  window.gearList:destroyChildren()
  local items = list(state and state.items)
  local current = state and state.item
  for _, it in ipairs(items) do
    local slot = g_ui.createWidget('CraftGearSlot', window.gearList)
    slot:setItemId(tonumber(it.clientId) or 0)
    local rarity = tonumber(it.rarity) or 0
    local tip = it.name or ''
    if it.unique then
      tip = tip .. '\n' .. tr('Unique')
    elseif it.key then
      tip = tip .. '\n' .. tr('Rift Key')
    elseif rarity > 0 then
      tip = tip .. '\n' .. (it.rarityName or tr('Rarity %d', rarity))
    end
    slot:setTooltip(tip)
    if rarity > 0 or it.unique or it.key then
      slot:setBorderWidth(1)
      slot:setBorderColor(it.unique and '#e8582a' or it.key and KEY_COLOR or rarityColor(rarity))
    end
    if it.locked then
      tip = tip .. '\n' .. tr('Locked')
      slot:setOpacity(0.55)
    end
    if mode == 'salvage' and batchPaths and batchPaths[it.path] then
      slot:setBorderWidth(2)
      slot:setBorderColor('#e03a1e') -- "salvage all" takes it
      tip = tip .. '\n' .. tr('In the salvage batch')
    end
    slot:setTooltip(tip)
    if current and current.path == it.path then
      slot:setBorderWidth(1)
      slot:setBorderColor('#ffffff') -- the item on the bench
      slot:setBackgroundColor('#f6cf7240')
    end
    local path, id = it.path, it.id
    slot.onMouseRelease = function(self, mousePos, button)
      if button == MouseLeftButton and self:containsPoint(mousePos) then
        setResult('')
        send('select', { path = path, id = id })
        return true
      end
      return false
    end
    slot.onDragEnter = function() return false end -- the grid is a picker, not a container
  end
  window.gearEmpty:setVisible(#items == 0)
end

-- ---------------------------------------------------------------- history
local function buildHistory()
  window.historyPanel:destroyChildren()
  local rows = list(state and state.history)
  if #rows == 0 then
    local label = g_ui.createWidget('CraftHistoryLabel', window.historyPanel)
    label:setText(tr('Nothing crafted yet.'))
    label:setColor('#8c8070')
    return
  end
  for _, h in ipairs(rows) do
    local label = g_ui.createWidget('CraftHistoryLabel', window.historyPanel)
    local when = tonumber(h.time) and os.date('%d.%m %H:%M', tonumber(h.time)) or ''
    label:setText(string.format('%s  %s: %s', when, h.orb or '?', h.text or ''))
    label:setTooltip(string.format('%s\n%s: %s', h.item or '', h.orb or '?', h.text or ''))
  end
end

-- ---------------------------------------------------------------- salvage tab
local SKIP_TEXT = { locked = 'locked', unique = 'unique', gems = 'with gems', above = 'above the rarity',
  cap = 'over the limit of %d', notBackpack = 'not in the backpack' }

local function shardWord(sv, n)
  if tonumber(n) == 1 then return sv.shardSingular or 'shard' end
  return sv.shardName or 'shards'
end

local function salvageView()
  return state and type(state.salvage) == 'table' and state.salvage or nil
end

local function showMode()
  if not window then return end
  window.orbsTab:setChecked(mode == 'orbs')
  window.salvageTab:setChecked(mode == 'salvage')
  window.orbList:setVisible(mode == 'orbs')
  window.salvagePanel:setVisible(mode == 'salvage')
end

function setMode(m)
  if m ~= 'orbs' and m ~= 'salvage' then return end
  mode = m
  showMode()
  send('salvageScope', { mode = m }) -- the answer (a state) brings the "salvage all" preview
end

local function fillCombos(sv)
  local batch = type(sv.batch) == 'table' and sv.batch or {}
  updatingUi = true
  local bags = list(sv.bags)
  local bagCombo = window.salvagePanel.batchBox.bagCombo
  bagCombo:clearOptions()
  local current = 1
  for i, b in ipairs(bags) do
    bagCombo:addOption(b.name or '?', b.path or '')
    if (b.path or '') == (batch.bag or '') then current = i end
  end
  if #bags > 0 then bagCombo:setCurrentIndex(current) end
  local rarityCombo = window.salvagePanel.batchBox.rarityCombo
  rarityCombo:clearOptions()
  for i, name in ipairs(list(sv.rarityNames)) do
    rarityCombo:addOption(name, i)
  end
  local r = tonumber(batch.maxRarity) or 1
  if #list(sv.rarityNames) >= r then rarityCombo:setCurrentIndex(r) end
  updatingUi = false
end

local function onScopeChange()
  if updatingUi or not window then return end
  local box = window.salvagePanel.batchBox
  local bag = box.bagCombo:getCurrentOption()
  local rarity = box.rarityCombo:getCurrentOption()
  send('salvageScope', { bag = bag and bag.data or '', maxRarity = rarity and tonumber(rarity.data) or 1 })
end

local function updateRecipes(sv)
  local panel = window.salvagePanel.recipeList
  panel:destroyChildren()
  local shards = tonumber(sv.shards) or 0
  for _, r in ipairs(list(sv.recipes)) do
    local row = g_ui.createWidget('CraftRecipeRow', panel)
    local cost = tonumber(r.cost) or 0
    row.icon:setItemId(tonumber(r.clientId) or 0)
    row.name:setText(((r.name or r.key):gsub('^Orb of ', ''))) -- the full name is in the tooltip
    row.cost:setText(tr('%d shards', cost))
    row.cost:setColor(shards >= cost and '#c0a0ff' or '#6b6258')
    row:setTooltip(tr('%d %s -> 1 %s (you have %d).\nCtrl+click: as many as you can, up to %d.', cost,
      sv.shardName or 'shards', r.name or r.key, tonumber(r.count) or 0, tonumber(sv.maxCombine) or 1))
    row.make:setEnabled(sv.installed ~= false and shards >= cost)
    local key = r.key
    row.make.onClick = function()
      local n = 1
      if g_keyboard and g_keyboard.isCtrlPressed and g_keyboard.isCtrlPressed() and cost > 0 then
        n = math.max(1, math.min(tonumber(sv.maxCombine) or 1, math.floor(shards / cost)))
      end
      row.make:setEnabled(false)
      send('combine', { key = key, count = n })
    end
  end
end

local function updateSalvage()
  local sv = salvageView()
  batchPaths = nil
  if not window or not sv then return end
  if mode ~= 'salvage' then return end
  local panel = window.salvagePanel
  panel.shardRow.shardIcon:setItemId(tonumber(sv.shardClientId) or 0)
  panel.shardRow.shardCount:setText(tr('Rune shards: %s', short(sv.shards)))
  if sv.installed == false then
    panel.shardRow.shardHint:setText(tr('Salvage is not installed on this server.'))
  end
  -- the item on the bench
  local item = state.item
  local box = panel.itemBox
  if not item then
    box.itemText:setText(tr('Put an item on the bench, or salvage a whole bag below.'))
    box.itemText:setColor('#8c8070')
    box.salvageButton:setEnabled(false)
  else
    local s = type(item.salvage) == 'table' and item.salvage or {}
    if s.ok then
      box.itemText:setText(tr('%s: %d %s, %s%% chance of an orb.', item.name or '?', tonumber(s.shards) or 0,
        shardWord(sv, s.shards), tostring(s.orbChance or 0)))
      box.itemText:setColor('#9fdc7f')
    else
      box.itemText:setText(tr('%s: %s', item.name or '?', s.why or tr('cannot be salvaged.')))
      box.itemText:setColor('#e8582a')
    end
    box.salvageButton:setEnabled(s.ok == true)
  end
  -- salvage all
  fillCombos(sv)
  local batch = type(sv.batch) == 'table' and sv.batch or nil
  local bbox = panel.batchBox
  if batch then
    batchPaths = {}
    for _, p in ipairs(list(batch.paths)) do batchPaths[p] = true end
    local count = tonumber(batch.count) or 0
    local lines = {}
    if count > 0 then
      lines[#lines + 1] = tr('%d %s -> %d %s, %s%% orb chance in total.', count, count == 1 and tr('item') or tr('items'),
        tonumber(batch.shards) or 0, shardWord(sv, batch.shards), tostring(batch.orbs or 0))
    else
      lines[#lines + 1] = tr('Nothing to salvage there.')
    end
    local skipped = {}
    for key, n in pairs(type(batch.skipped) == 'table' and batch.skipped or {}) do
      local text = SKIP_TEXT[key] or key
      skipped[#skipped + 1] = string.format('%d %s', tonumber(n) or 0, text:format(tonumber(batch.cap) or 50))
    end
    table.sort(skipped)
    if #skipped > 0 then lines[#lines + 1] = tr('Skipped: %s.', table.concat(skipped, ', ')) end
    bbox.batchText:setText(table.concat(lines, '\n'))
    bbox.batchButton:setText(count > 1 and tr('Salvage %d items', count) or count == 1 and tr('Salvage 1 item')
      or tr('Salvage all'))
    bbox.batchButton:setEnabled(sv.installed ~= false and count > 0)
  else
    bbox.batchText:setText('')
    bbox.batchButton:setEnabled(false)
  end
  updateRecipes(sv)
end

function salvageItem()
  local item = state and state.item
  if not item then return end
  window.salvagePanel.itemBox.salvageButton:setEnabled(false)
  send('salvage', { path = item.path, id = item.id, sig = item.sig })
end

function toggleLock()
  local item = state and state.item
  if not item then return end
  send('lock', { path = item.path, id = item.id, on = not item.locked })
end

function salvageAll()
  local sv = salvageView()
  local batch = sv and type(sv.batch) == 'table' and sv.batch or nil
  if not batch or (tonumber(batch.count) or 0) <= 0 then return end
  if confirmBox then confirmBox:destroy() confirmBox = nil end
  local request = { bag = batch.bag or '', maxRarity = batch.maxRarity, sig = batch.sig }
  local function yes()
    if confirmBox then confirmBox:destroy() confirmBox = nil end
    send('salvageBatch', request)
  end
  local function no()
    if confirmBox then confirmBox:destroy() confirmBox = nil end
  end
  local names = list(sv.rarityNames)
  local text = tr('Salvage %d item(s) (rarity up to %s) into %d %s?\nLocked items, uniques and items with gems are kept.\nThis cannot be undone.',
    tonumber(batch.count) or 0, names[tonumber(batch.maxRarity) or 1] or '?', tonumber(batch.shards) or 0,
    sv.shardName or 'shards')
  if displayGeneralBox then
    confirmBox = displayGeneralBox(tr('Salvage all'), text,
      { { text = tr('Salvage'), callback = yes }, { text = tr('Cancel'), callback = no }, anchor = AnchorHorizontalCenter }, yes, no)
  else
    yes()
  end
end

-- ---------------------------------------------------------------- protocol
local function onState(data)
  local orbsChanged = not state or #list(state.orbs) ~= #list(data.orbs)
  state = data
  -- opened in the Salvage tab (!salvage, a shard used): follow the server's mode
  if data.open and type(data.salvage) == 'table' and (data.salvage.mode == 'salvage' or data.salvage.mode == 'orbs') then
    mode = data.salvage.mode
  end
  showMode()
  if orbsChanged then buildOrbs() end
  showItem(data.item)
  updateOrbs()
  updateSalvage()
  buildGear()
  buildHistory()
  if data.open then
    if not window:isVisible() then setResult('') end
    show()
  end
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[crafting] invalid JSON: ' .. tostring(msg))
    return
  end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    onState(data)
  elseif msg.action == 'result' then
    setResult(data.text, data.ok)
  end
end

-- an item dragged from a container onto the bench slot
local function onSlotDrop(self, widget, mousePos)
  local item = widget and widget.currentDragThing
  if not item or not item.isItem or not item:isItem() then return false end
  local pos = item:getPosition()
  if not pos or pos.x ~= 65535 then
    setResult(tr('Only items from your backpack can go on the bench.'), false)
    return true
  end
  setResult('')
  send('select', { pos = { x = pos.x, y = pos.y, z = pos.z }, clientId = item:getId() })
  return true
end

-- ---------------------------------------------------------------- window
function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
end

function hide()
  if window then window:hide() end
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
    return
  end
  send('open') -- the server answers with the state, which shows the window
end

local function onGameEnd()
  hide()
  state = nil
  mode = 'orbs'
  if confirmBox then confirmBox:destroy() confirmBox = nil end
  if window then setResult('') end
end

function init()
  window = g_ui.displayUI('crafting')
  window:hide()
  window.itemSlot.onDrop = onSlotDrop
  window.itemSlot.onMouseRelease = function(self, mousePos, button)
    if button == MouseRightButton and state and state.item then
      send('clear')
      return true
    end
    return false
  end
  window.salvagePanel.batchBox.bagCombo.onOptionChange = onScopeChange
  window.salvagePanel.batchBox.rarityCombo.onOptionChange = onScopeChange
  showMode()
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if window then
    window:destroy()
    window = nil
  end
  if confirmBox then confirmBox:destroy() confirmBox = nil end
  state, orbRows = nil, {}
end
