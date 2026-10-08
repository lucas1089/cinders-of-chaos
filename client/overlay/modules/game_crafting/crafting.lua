-- Crafting bench: put an item (or a Rift Key) from the backpack on the bench, see its rarity and modifiers and what
-- each orb would do, apply an orb. The bench is optional: every orb also works by "Use with" on the item.
-- Server: server/data/scripts/chaos/crafting.lua and data/lib/chaos_crafting.lua, extended opcode 232 (JSON).
--   server -> client  state {open, orbs = [{key, id, clientId, name, text, keyText, count}], item = {path, clientId,
--                            name, kind, rarity, rarityName, level, mods = [{group, text}], maxMods, rewards, unique,
--                            orbs = {key -> ""|why}, preview = {key -> text}, sig} | nil,
--                            items = [{path, id, clientId, name, rarity, rarityName, unique, key}],
--                            history = [{time, orb, item, text}]}
--                     result {ok, orb, text}
--   client -> server  open | select {path, id} | select {pos, clientId} | apply {orb, path, id, sig} | clear
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

-- ---------------------------------------------------------------- item panel
local function showItem(item)
  window.modList:destroyChildren()
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

-- ---------------------------------------------------------------- protocol
local function onState(data)
  local orbsChanged = not state or #list(state.orbs) ~= #list(data.orbs)
  state = data
  if orbsChanged then buildOrbs() end
  showItem(data.item)
  updateOrbs()
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
  state, orbRows = nil, {}
end
