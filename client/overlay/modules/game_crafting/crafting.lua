-- Crafting bench: put an item (or a Rift Key) from the backpack on the bench, see its rarity and modifiers and what
-- each orb would do, apply an orb. The bench is optional: every orb also works by "Use with" on the item.
-- Server: server/data/scripts/chaos/crafting.lua and data/lib/chaos_crafting.lua, extended opcode 232 (JSON).
--   server -> client  info {orbs = [{key, id, clientId, name, text, keyText}], reasons = {code -> text}} (when the bench opens;
--                            the engine drops a message above 8192 bytes, so the texts that never change come once)
--                     state {open, counts = {orb key -> count}, item = {path, clientId,
--                            name, kind, rarity, rarityName, level, maxTier, mods = [{group, text, tier, side, lo,
--                            hi}] (prefixes first), prefixes = {n, max}, suffixes = {n, max}, maxMods, rewards, unique,
--                            orbs = {key -> ""|reason code}, preview = {key -> text},
--                            sockets = {count, max, list = [{index, id, clientId, name, text, color, cost}]}, sig} | nil,
--                            items = [{path, id, clientId, name, rarity, rarityName, unique, key}],
--                            history = [{time, orb, item, text}]}
--                     result {ok, orb, text}
--   client -> server  open | select {path, id} | select {pos, clientId} | apply {orb, path, id, sig, mod} |
--                     gem {op = "remove"|"shatter", socket, path, id, sig} | clear
-- Modifier rows (item.mods[i] = {key, text, tier, side, lo, hi, bound, power, group}) are clickable: the orbs that are aimed
-- at one modifier (item.pick = {orb key -> [modifier keys]}: Binding, Excision, Reforging) are enabled once you picked
-- one of those, and send it as `mod`. A right-click on a modifier row opens its page in the Codex (game_codex). item.quality / qualityCap fill the quality bar, item.ruined and item.binds show in
-- the header.
-- Sockets (gems, server data/lib/chaos_gems.lua) are listed under the modifiers: a gem can be taken out for gold
-- (Remove, it comes back) or destroyed (Shatter); socketing and combining are done by Use with on the gem.
-- Salvage tab (server data/scripts/chaos/salvage.lua, same opcode): state.salvage = {installed, shardClientId,
-- shardName, shards, rarityNames, recipes = [{key, name, clientId, cost, count}], bags = [{path, name}], batch = {bag,
-- maxRarity, count, shards, orbs, capped, cap, skipped, sig, paths}, mode}; state.items[i].locked, state.item.locked,
-- state.item.salvage = {ok, why, shards, orbChance}. Client -> server: salvage {path, id, sig} | lock {path, id, on} |
-- salvageScope {bag, maxRarity, mode} | salvageBatch {bag, maxRarity, sig} | combine {key, count}.
-- The server checks everything (orb owned, item in the backpack, orb fits the item, no uniques); the buttons here only
-- mirror its answer. The top menu (Economy > Crafting Bench, Economy > Salvage) calls toggle() and openSalvage().
-- Long texts are never cut at the window edge: they wrap (crafting.otui CraftWrapLabel) and the row or box around them
-- takes the height (followHeight); the lists scroll; tooltips are broken into lines (tipText, SupportsText.wrap of
-- game_spellsupports/supportstext.lua); only the status line has a cap (RESULT_LINES, the rest in its tooltip).

local OPCODE = 232

-- rarity 1..15 (names from the server): text colours from grey to red, like the loot messages
local RARITY_COLOR = {
  '#c4cebc', '#5fd35f', '#4a8cff', '#b070ff', '#f6cf72', '#ff9c3a', '#d860ff', '#e03a1e', '#7fe6ff',
  '#ffe680', '#c0a0ff', '#9fe0ff', '#ff70c0', '#ff4040', '#ffffff'
}
local GROUP_COLOR = { absorb = '#7fa8ff', skill = '#9fdc7f', special = '#f6cf72', element = '#ff8a5a',
  chaos = '#ff70c0', rift = '#c0a0ff' }
local POWER_COLOR = '#ff9a3c' -- legendary powers
local SELECT_BG = '#f6cf7236'
local updateOrbs
local KEY_COLOR = '#c0a0ff' -- Rift Keys

local window
local state        -- last state from the server
local info         -- the orbs and the reason texts (server "info")
local orbRows = {} -- orb key -> row widget
local mode = 'orbs' -- 'orbs' | 'salvage' (the tabs)
local updatingUi = false -- filling the salvage combo boxes: no requests
local selectedMod -- the modifier key picked on the bench (aims Binding, Excision, Reforging), nil = none
local confirmBox -- the "salvage all" confirmation
local batchPaths -- path -> true for the items the "salvage all" preview takes
local expanded = {} -- orb key -> true: the row shows the orb's full description (a click on the row toggles it)
local RESULT_LINES = 4 -- the status line wraps over at most this many lines

-- the text helpers of the spell supports window (shorten at a word, wrap at spaces); plain text without them
local okText, Text = pcall(dofile, '/modules/game_spellsupports/supportstext.lua')
if not okText or type(Text) ~= 'table' then Text = nil end

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

-- tooltips do not wrap: long lines are broken here
local TIP_CHARS = 64
local function tipText(text)
  text = tostring(text or '')
  if not Text then return text end
  local out = {}
  for line in (text .. '\n'):gmatch('(.-)\n') do
    local lead = line:match('^%s*')
    out[#out + 1] = lead .. Text.wrap(line, TIP_CHARS - #lead, lead .. '  ')
  end
  return table.concat(out, '\n')
end

local function setTip(widget, text)
  if text and text ~= '' then
    widget:setTooltip(tipText(text))
  else
    widget:removeTooltip()
  end
end

-- the box (a row, a panel) ends `bottom` pixels below its child, at least `minHeight` high; the child is a wrapping
-- label or a stack of them that changes its height with its text and width
local function followHeight(box, child, bottom, minHeight)
  local function fit()
    if box:isDestroyed() or child:isDestroyed() then return end
    local h = child:getY() + child:getHeight() - box:getY() + (bottom or 0)
    h = math.max(minHeight or 0, h)
    if h ~= box:getHeight() then box:setHeight(h) end
  end
  connect(child, { onGeometryChange = fit })
  fit()
end

-- a one-line label in a fixed cell: the text, shortened at a word with "..." when it is wider than the label (the
-- caller puts the whole text in a tooltip); refitted when the label is resized
local function fitText(label, text)
  label.fitText = tostring(text or '')
  local function refit()
    if label:isDestroyed() then return end
    local full = label.fitText or ''
    local width = label:getWidth() - label:getPaddingLeft() - label:getPaddingRight()
    if not Text or width <= 1 then
      label:setText(full)
      return
    end
    label:setText((Text.shorten(full, function(candidate)
      label:setText(candidate)
      return label:getTextSize().width <= width
    end)))
  end
  if not label.fitHooked then
    label.fitHooked = true
    connect(label, { onGeometryChange = refit })
  end
  refit()
end

-- the status line: wrapped, at most RESULT_LINES lines; a longer text ends with "..." and is whole in the tooltip
local function fitResult()
  local label = window and window.resultLabel
  if not label then return end
  local full = label.fullText or ''
  label.fitWidth = label:getWidth()
  if label:getWidth() <= 1 then
    label:setText(full)
    return
  end
  label:setText('Ag')
  local maxHeight = label:getTextSize().height * RESULT_LINES
  local text, cut = full, false
  if Text then
    text, cut = Text.shorten(full, function(candidate)
      label:setText(candidate)
      return label:getTextSize().height <= maxHeight
    end)
  end
  label:setText(text)
  label:setHeight(math.max(22, label:getTextSize().height + 2))
  setTip(label, cut and full or '')
end

local function setResult(text, ok)
  if not window then return end
  window.resultLabel.fullText = text or ''
  window.resultLabel:setColor(ok == false and '#e03a1e' or '#9fdc7f')
  fitResult()
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
      setTip(w, tr('%s\n%s', row.name or '', row.text or ''))
      w.removeButton:setText(gold(row.cost))
      setTip(w.removeButton, tr('Take the gem out for %d gold (bank first, then the backpack). It comes back to you.', tonumber(row.cost) or 0))
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
    followHeight(w, w.text, 2, 30)
  end
end

-- ---------------------------------------------------------------- item panel
local function modByKey(item, key)
  if not item or not key then return nil end
  for _, m in ipairs(list(item.mods)) do
    if m.key == key then return m end
  end
  return nil
end

local function showQuality(item)
  local bar = window.qualityBar
  local q = item and tonumber(item.quality) or 0
  local cap = item and tonumber(item.qualityCap) or 0
  if not item or cap <= 0 then
    bar:setVisible(false)
    return
  end
  bar:setVisible(true)
  bar:setPercent(math.floor(100 * q / cap))
  bar:setText(tr('Quality +%d%% / %d%%', q, cap))
  setTip(bar, tr('Item quality: every modifier value is multiplied by it. A Whetstone adds 1%% (up to %d%%).', cap))
end

local function showItem(item)
  window.modList:destroyChildren()
  window.lockButton:setVisible(item ~= nil)
  if item and selectedMod and not modByKey(item, selectedMod) then selectedMod = nil end
  if not item then selectedMod = nil end
  showQuality(item)
  if item then
    window.lockButton:setText(item.locked and tr('Unlock') or tr('Lock'))
    setTip(window.lockButton, item.locked and tr('Locked: it cannot be sold, salvaged or thrown away. Click to unlock.')
      or tr('Lock the item: it cannot be sold, salvaged or thrown away.'))
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
  window.itemRarity:removeTooltip()
  if item.kind == 'riftkey' then
    window.itemName:setColor(KEY_COLOR)
    window.itemRarity:setText(tr('Rift Key, tier %d (level %d+)', tonumber(item.tier) or 0, tonumber(item.level) or 0))
    window.itemRarity:setColor(KEY_COLOR)
    setTip(window.itemRarity, item.rewards and tr('Rewards: %s', item.rewards) or '')
  elseif item.unique then
    window.itemRarity:setText(tr('Unique item: orbs cannot change it'))
    window.itemRarity:setColor('#e8582a')
  elseif rarity > 0 then
    window.itemRarity:setText(tr('%s, item level %d', item.rarityName or '?', tonumber(item.level) or 0)
      .. (item.maxTier and tr(' (up to T%d)', tonumber(item.maxTier) or 0) or '')
      .. (item.ruined and tr('  RUINED') or ''))
    window.itemRarity:setColor(item.ruined and '#e03a1e' or rarityColor(rarity))
  else
    window.itemRarity:setText(tr('Normal item'))
    window.itemRarity:setColor('#d6c9ae')
  end
  local mods = list(item.mods)
  local pre, suf = item.prefixes, item.suffixes
  if rarity > 0 and type(pre) == 'table' and type(suf) == 'table' then
    local binds = type(item.binds) == 'table' and item.binds or nil
    window.itemSlots:setText(tr('Modifiers %d/%d (prefixes %d/%d, suffixes %d/%d', #mods, tonumber(item.maxMods) or 0,
      tonumber(pre[1]) or 0, tonumber(pre[2]) or 0, tonumber(suf[1]) or 0, tonumber(suf[2]) or 0)
      .. (binds and tr(', bound %d/%d', tonumber(binds[1]) or 0, tonumber(binds[2]) or 0) or '') .. ')')
    setTip(window.itemSlots, tr('Modifiers on the item / the most it can have; prefixes, suffixes and bound modifiers the same way.'))
  elseif rarity > 0 or item.kind == 'riftkey' then
    window.itemSlots:removeTooltip()
    window.itemSlots:setText(tr('Modifiers: %d / %d', #mods, tonumber(item.maxMods) or 0))
  else
    window.itemSlots:removeTooltip()
    window.itemSlots:setText(#mods > 0 and tr('Modifiers: %d', #mods) or tr('No modifiers'))
  end
  local side
  for _, m in ipairs(mods) do
    if m.side and m.side ~= side then
      side = m.side
      local head = g_ui.createWidget('CraftModLabel', window.modList)
      head:setText(side == 'prefix' and tr('Prefixes') or tr('Suffixes'))
      head:setColor('#8c8070')
    end
    local row = g_ui.createWidget('CraftModRow', window.modList)
    local text = m.short or m.text or ''
    if m.tier then
      text = string.format('T%d  %s', tonumber(m.tier) or 0, text)
      if m.lo and m.hi then
        text = text .. (m.lo == m.hi and string.format('  [%d]', m.lo) or string.format('  [%d-%d]', m.lo, m.hi))
      end
    end
    row.text:setText(text)
    row.text:setColor(m.power and POWER_COLOR or GROUP_COLOR[m.group] or '#d6c9ae')
    row.mark:setText(m.bound and tr('bound') or '')
    row.modKey = m.key
    local codexTip = (modules.game_codex and modules.game_codex.openModifier) and tr('Right-click: its page in the Codex.') or nil
    if m.power then
      setTip(row, (m.text or '') .. '\n' .. tr('Legendary power: it changes what your character does.') .. (codexTip and '\n' .. codexTip or ''))
    elseif m.bound then
      setTip(row, tr('Bound: the orbs that change modifiers leave it alone. Only an Orb of Erasure frees it.') .. (codexTip and '\n' .. codexTip or ''))
    elseif codexTip then
      setTip(row, codexTip)
    end
    followHeight(row, row.text, 2, 17)
    if m.key and m.key == selectedMod then row:setBackgroundColor(SELECT_BG) end
    row.modGroup = m.group
    row.onMouseRelease = function(self, mousePos, button)
      -- right-click: the modifier's page in the Codex (game_codex)
      if button == MouseRightButton and self:containsPoint(mousePos) and self.modKey then
        local codex = modules.game_codex
        return codex and codex.openModifier and codex.openModifier(self.modKey, self.modGroup) or false
      end
      if button ~= MouseLeftButton or not self:containsPoint(mousePos) or not self.modKey then return false end
      selectedMod = (selectedMod ~= self.modKey) and self.modKey or nil
      for _, child in ipairs(window.modList:getChildren()) do
        child:setBackgroundColor((child.modKey and child.modKey == selectedMod) and SELECT_BG or '#00000000')
      end
      updateOrbs()
      return true
    end
  end
  if item.kind == 'riftkey' and item.rewards then
    local label = g_ui.createWidget('CraftModLabel', window.modList)
    label:setText(tr('Rewards: %s', item.rewards))
    label:setColor('#9fdc7f')
  end
  showSockets(item)
end

-- ---------------------------------------------------------------- orbs
-- one orb row: "name  xCount", then what the orb would do to the item on the bench (green), why it cannot be used, or
-- (empty bench) what it does; the full description under it when the row is expanded. Every line wraps.
function updateOrbs()
  local item = state and state.item
  for _, orb in ipairs(list(state and state.orbs)) do
    local row = orbRows[orb.key]
    if row then
      local body = row.body
      local count = tonumber(orb.count) or 0
      local name = orb.name or orb.key
      row.icon:setItemId(tonumber(orb.clientId) or 0)
      row.icon:setItemCount(math.max(1, math.min(count, 100)))
      body.name:setColoredText({ name, '#e8b84a', '  x' .. short(count), count > 0 and '#8c8070' or '#6b6258' })
      local why = ''
      if count <= 0 then
        why = tr('You have no %s.', name)
      elseif not item then
        why = tr('Put an item on the bench first.')
      elseif type(item.orbs) == 'table' and item.orbs[orb.key] and item.orbs[orb.key] ~= '' then
        local code = item.orbs[orb.key]
        why = info and type(info.reasons) == 'table' and info.reasons[code] or code
      end
      -- an orb that is aimed at one modifier needs one picked from the modifiers it may act on
      local aimed = why == '' and item and type(item.pick) == 'table' and type(item.pick[orb.key]) == 'table'
        and #item.pick[orb.key] > 0 and orb.key
      if aimed then
        local ok = false
        for _, k in ipairs(item.pick[orb.key]) do
          if k == selectedMod then ok = true end
        end
        if not ok then
          why = selectedMod and tr('That modifier cannot be chosen for this orb.') or tr('Click a modifier of the item first.')
        end
      end
      -- what the orb would do to the item on the bench (the server's preview)
      local preview = why == '' and item and type(item.preview) == 'table' and item.preview[orb.key] or ''
      local text = (item and item.kind == 'riftkey' and orb.keyText) or orb.text or ''
      local line, color, isText = why, '#a89074', false
      if preview ~= '' then
        line, color = preview, '#9fdc7f'
      elseif why == '' then
        line, color, isText = text, '#8c8070', true
      elseif not item and count > 0 then
        line, color, isText = text, '#8c8070', true -- nothing on the bench: what the orb does
      end
      body.text:setText(line)
      body.text:setColor(color)
      local showDesc = expanded[orb.key] and not isText and text ~= ''
      body.desc:setText(showDesc and text or '')
      body.desc:setVisible(showDesc and true or false)
      row.use:setEnabled(why == '')
      setTip(row.use, why)
      setTip(row, name .. '\n' .. text .. (preview ~= '' and ('\n' .. tr('Preview: %s', preview)) or '')
        .. (why ~= '' and ('\n' .. why) or '') .. (isText and '' or ('\n' .. (expanded[orb.key]
        and tr('Click: hide the description.') or tr('Click: show the description in the row.')))))
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
    row.orbKey = key
    row.use.onClick = function()
      local item = state and state.item
      if not item then return end
      row.use:setEnabled(false) -- the next state enables it again
      local picks = type(item.pick) == 'table' and type(item.pick[key]) == 'table' and #item.pick[key] > 0
      send('apply', { orb = key, path = item.path, id = item.id, sig = item.sig, mod = picks and selectedMod or nil })
    end
    row.onMouseRelease = function(self, mousePos, button)
      if button ~= MouseLeftButton or not self:containsPoint(mousePos) then return false end
      expanded[key] = not expanded[key] or nil
      updateOrbs()
      return true
    end
    followHeight(row, row.body, 6 + 3, 44) -- the panel's padding below the text
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
    setTip(slot, tip)
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
  window.historyList:destroyChildren()
  local rows = list(state and state.history)
  if #rows == 0 then
    local label = g_ui.createWidget('CraftHistoryLabel', window.historyList)
    label:setText(tr('Nothing crafted yet.'))
    label:setColor('#8c8070')
    return
  end
  for _, h in ipairs(rows) do
    local label = g_ui.createWidget('CraftHistoryLabel', window.historyList)
    local when = tonumber(h.time) and os.date('%d.%m %H:%M', tonumber(h.time)) or ''
    label:setText(string.format('%s  %s: %s', when, h.orb or '?', h.text or ''))
    setTip(label, string.format('%s\n%s: %s', h.item or '', h.orb or '?', h.text or ''))
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
    -- the full name is in the tooltip; a name too long for the cell is shortened at a word
    fitText(row.name, ((r.name or r.key):gsub('^Orb of ', '')))
    fitText(row.cost, tr('%d shards', cost))
    row.cost:setColor(shards >= cost and '#c0a0ff' or '#6b6258')
    setTip(row, tr('%d %s -> 1 %s (you have %d).\nCtrl+click: as many as you can, up to %d.', cost,
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
  panel.shardRow.shardHint:setText(sv.installed == false and tr('Salvage is not installed on this server.')
    or tr('Salvage gear into shards, shards into orbs.'))
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
  -- the orbs: what the server told once (info) with the counts of this state
  local orbs = {}
  for _, o in ipairs(list(info and info.orbs)) do
    local row = {}
    for k, v in pairs(o) do row[k] = v end
    row.count = type(data.counts) == 'table' and tonumber(data.counts[o.key]) or 0
    orbs[#orbs + 1] = row
  end
  data.orbs = orbs
  local orbsChanged = not state or #list(state.orbs) ~= #list(data.orbs)
  if state and state.item and data.item and state.item.path ~= data.item.path then selectedMod = nil end
  state = data
  -- opened in the Salvage tab (the menu's Salvage entry, a shard used): follow the server's mode
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
  if msg.action == 'info' then
    info = data
  elseif msg.action == 'state' then
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

-- the menu's Salvage entry: the bench in its Salvage tab
function openSalvage()
  if not window then return end
  send('salvageScope', { mode = 'salvage' })
  send('open')
end

local function onGameEnd()
  hide()
  state = nil
  mode = 'orbs'
  selectedMod = nil
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
  -- wrapped texts: the boxes around them grow with them
  local sp = window.salvagePanel
  followHeight(sp.shardRow, sp.shardRow.shardHint, 4, 36)
  followHeight(sp.itemBox, sp.itemBox.itemText, 6, 50)
  followHeight(sp.batchBox, sp.batchBox.batchButton, 6, 60)
  -- the item header: the separator goes below the slot or the header, whichever ends lower
  local function placeSeparator()
    local slot, last = window.itemSlot, window.itemSlots
    local bottom = math.max(slot:getY() + slot:getHeight(), last:getY() + last:getHeight())
    local margin = bottom - window.itemPanel:getY() + 6
    if margin ~= window.itemSep:getMarginTop() then window.itemSep:setMarginTop(margin) end
  end
  connect(window.itemSlots, { onGeometryChange = placeSeparator })
  connect(window.resultLabel, { onGeometryChange = function(self)
    if self:getWidth() ~= self.fitWidth then fitResult() end
  end })
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
  state, orbRows, expanded = nil, {}, {}
end
