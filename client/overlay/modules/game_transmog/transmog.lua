-- Transmog (server data/scripts/chaos/transmog.lua, extended opcode 212, JSON {action, data}; long answers in parts
-- joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | looks {kind} | apply {slot, look} | remove {slot} | close
--   server -> client  state {open, money, fee, slots, kinds, total, sets}   looks {kind, rows}   result {ok, text}
-- The look itself reaches every item drawing through the item's custom attribute 8 (client base patch 0030); this
-- window only picks it. Previews use item:setAppearanceId on the window's own items. Menu: Character > Transmog, or
-- right-click an equipped item > Transmog.

local OPCODE = 212
local V = TransmogView

local window
local state
local selectedSlot
local selectedLook -- a wardrobe row {id, cid, name, set}
local looksByKind = {}
local requested = {}
local page = 'wardrobe'
local slotWidgets = {}
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[transmog] ' .. name .. ': ' .. tostring(res))
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

-- a window item: its own client id, drawn with a look (client id) when given
local function showItem(widget, cid, lookCid)
  widget:setItemId(tonumber(cid) or 0)
  local item = widget:getItem()
  if item and lookCid and lookCid > 0 then
    pcall(function() item:setAppearanceId(lookCid) end)
  end
end

local function setStatus(text, ok)
  if not window then return end
  window.statusLabel:setText(text or '')
  window.statusLabel:setColor(ok == false and '#ff7a5c' or (ok and '#8fd16a' or '#a89c86'))
end

local function selectedRow()
  return state and V.slotRow(state.slots, selectedSlot) or nil
end

-- ---------------------------------------------------------------- detail (middle)
local function refreshDetail()
  if not window then return end
  local d = window.detail
  local row = selectedRow()
  local item = row and row.item
  if item then
    showItem(d.ownItem, item.cid)
    local lookCid = selectedLook and selectedLook.cid or (item.look and item.look.cid) or nil
    showItem(d.previewItem, item.cid, lookCid)
    d.itemName:setText(item.name or '')
    local lookText = selectedLook and ('Preview: ' .. selectedLook.name)
      or (item.look and ('Looks like: ' .. item.look.name) or 'Shows its own look')
    d.lookName:setText(lookText)
    d.kindLabel:setText(item.kind and (item.kindName or item.kind) or '')
  else
    showItem(d.ownItem, 0)
    showItem(d.previewItem, 0)
    d.itemName:setText(row and row.name or '')
    d.lookName:setText('')
    d.kindLabel:setText('')
  end
  local info = V.detail(row, selectedLook, state and state.money)
  d.feeLabel:setText(info.fee)
  d.hintLabel:setText(info.hint)
  d.applyButton:setEnabled(info.apply)
  d.removeButton:setEnabled(info.remove)
end

-- ---------------------------------------------------------------- wardrobe (right)
local function refreshLooks()
  if not window then return end
  local p = window.wardrobePanel
  p.lookList:destroyChildren()
  local row = selectedRow()
  local kind = row and row.item and row.item.kind
  local kindInfo
  for _, k in ipairs(state and state.kinds or {}) do
    if k.key == kind then kindInfo = k end
  end
  if not kind then
    p.kindTitle:setText(tr('Wardrobe'))
    p.emptyLabel:setText(tr('Select an equipped helmet, armor, legs, boots, weapon or shield.'))
    p.emptyLabel:show()
    return
  end
  p.kindTitle:setText(string.format('%s  %s', kindInfo and kindInfo.name or kind,
    kindInfo and V.progressText(kindInfo.unlocked, kindInfo.total) or ''))
  local rows = looksByKind[kind]
  if not rows then
    p.emptyLabel:setText(tr('Loading...'))
    p.emptyLabel:show()
    if not requested[kind] then
      requested[kind] = true
      send('looks', { kind = kind })
    end
    return
  end
  rows = V.filter(rows, p.searchEdit:getText())
  p.emptyLabel:setVisible(#rows == 0)
  p.emptyLabel:setText(#looksByKind[kind] == 0
    and tr('No appearance of this kind unlocked yet. Carry or equip an item once to add its look to your wardrobe.')
    or tr('Nothing matches the search.'))
  for _, r in ipairs(rows) do
    local w = g_ui.createWidget('TransmogLook', p.lookList)
    w:setItemId(tonumber(r.cid) or 0)
    w:setTooltip(r.name .. (r.set and ('\n' .. r.set .. ' set') or ''))
    w.look = r
    w.onClick = function()
      selectedLook = r
      refreshDetail()
    end
    if selectedLook and selectedLook.id == r.id then p.lookList:focusChild(w) end
  end
end

-- ---------------------------------------------------------------- collection page
local function refreshCollection()
  if not window or not state then return end
  local list = window.collectionPanel.collectionList
  list:destroyChildren()
  local head = g_ui.createWidget('ChaosTitle', list)
  head:setText(tr('Appearances by kind'))
  head:setTextAlign(AlignLeft)
  head:setHeight(22)
  for _, k in ipairs(state.kinds or {}) do
    local w = g_ui.createWidget('TransmogKindRow', list)
    w.name:setText(k.name)
    w.bar:setPercent(V.percent(k.unlocked, k.total))
    w.bar:setText(V.progressText(k.unlocked, k.total))
  end
  local head2 = g_ui.createWidget('ChaosTitle', list)
  head2:setText(tr('Appearance sets'))
  head2:setTextAlign(AlignLeft)
  head2:setHeight(26)
  for _, s in ipairs(V.sortSets(state.sets)) do
    local w = g_ui.createWidget('TransmogSetRow', list)
    w.name:setText(s.name)
    w.how:setText(V.setLine(s))
    w.how:setColor(s.owned and '#8fd16a' or (V.SOURCE_COLORS[s.source] or '#a89c86'))
    w:setTooltip(s.desc or '')
    for _, l in ipairs(s.looks or {}) do
      local it = g_ui.createWidget('TransmogSetLook', w.looks)
      it:setItemId(tonumber(l.cid) or 0)
      it:setTooltip(l.name or '')
      if not s.owned then it:setOpacity(0.45) end
    end
  end
end

-- ---------------------------------------------------------------- equipment (left)
local function refreshSlots()
  if not window or not state then return end
  local frame = window.gearFrame
  frame:destroyChildren()
  slotWidgets = {}
  for _, s in ipairs(state.slots or {}) do
    local w = g_ui.createWidget('TransmogSlotRow', frame)
    local item = s.item
    if item then
      showItem(w.item, item.cid, item.look and item.look.cid)
      w.name:setText(item.name)
    else
      showItem(w.item, 0)
      w.name:setText(s.name)
      w.name:setColor('#8c8070')
    end
    w.sub:setText(V.slotSub(s))
    w.slot = s.slot
    w.onFocusChange = function(self, focused)
      if focused and selectedSlot ~= self.slot then
        selectedSlot = self.slot
        selectedLook = nil
        refreshDetail()
        refreshLooks()
      end
    end
    slotWidgets[s.slot] = w
  end
  local pick = V.pickSlot(state.slots, selectedSlot)
  selectedSlot = pick
  if pick and slotWidgets[pick] then frame:focusChild(slotWidgets[pick]) end
end

local function refreshAll()
  if not window or not state then return end
  refreshSlots()
  refreshDetail()
  refreshLooks()
  refreshCollection()
  local t = state.total or {}
  window.progressBar:setPercent(V.percent(t.unlocked, t.total))
  window.progressBar:setText(V.progressText(t.unlocked, t.total))
  window.goldLabel:setText(tr('Gold') .. ': ' .. V.gold(state.money))
end

function showPage(name)
  if not window then return end
  page = name == 'collection' and 'collection' or 'wardrobe'
  window.wardrobePanel:setVisible(page == 'wardrobe')
  window.collectionPanel:setVisible(page == 'collection')
  window.wardrobeTab:setChecked(page == 'wardrobe')
  window.collectionTab:setChecked(page == 'collection')
end

-- ---------------------------------------------------------------- actions
function applySelected()
  local row = selectedRow()
  if not row or not row.item or not selectedLook then return end
  send('apply', { slot = row.slot, look = selectedLook.id })
end

function removeSelected()
  local row = selectedRow()
  if not row or not row.item then return end
  send('remove', { slot = row.slot })
end

function show()
  send('open')
end

function hide()
  if window then window:hide() end
  selectedLook = nil
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

-- for other modules and tests
function getState()
  return { state = state, slot = selectedSlot, look = selectedLook, page = page,
    visible = window and window:isVisible() or false }
end

-- ---------------------------------------------------------------- protocol
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    state = data
    -- the wardrobe may have grown (open scans the equipment, sets sync): ask again for the kinds when shown
    looksByKind, requested = {}, {}
    if selectedLook then
      -- keep the preview only while the slot still holds an item of that kind
      local row = selectedRow()
      if not row or not row.item then selectedLook = nil end
    end
    refreshAll()
    if data.open and window then
      showPage(page)
      window:show()
      window:raise()
      window:focus()
    end
  elseif msg.action == 'looks' then
    if type(data.kind) == 'string' then
      looksByKind[data.kind] = type(data.rows) == 'table' and data.rows or {}
      refreshLooks()
    end
  elseif msg.action == 'result' then
    setStatus(data.text, data.ok)
    if data.ok then selectedLook = nil end
  end
end

-- right-click an equipped item: Transmog
local function hookMenu()
  local gi = modules.game_interface
  if not gi or not gi.addMenuHook then return end
  gi.addMenuHook('chaosTransmog', tr('Transmog'), safe('menu', function() show() end),
    safe('menuCondition', function(_, lookThing, useThing)
      local thing = useThing or lookThing
      if not thing or not thing.isItem or not thing:isItem() then return false end
      local pos = thing:getPosition()
      return pos and pos.x == 65535 and pos.y >= 1 and pos.y <= 10 and pos.y ~= 2 and pos.y ~= 3 and pos.y ~= 9 and pos.y ~= 10
    end))
end

local function onGameStart()
  state = nil
  looksByKind, requested = {}, {}
  hookMenu()
end

local function onGameEnd()
  hide()
  state = nil
end

function init()
  local ok, ui = pcall(g_ui.displayUI, 'transmog')
  if ok and ui then
    window = ui
    window:hide()
    window.wardrobePanel.searchEdit.onTextChange = safe('search', function() refreshLooks() end)
    showPage('wardrobe')
  else
    g_logger.warning('[transmog] window not loaded: ' .. tostring(ui))
  end
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, safe('opcode', onMessage))
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  local gi = modules.game_interface
  if gi and gi.removeMenuHook then pcall(gi.removeMenuHook, 'chaosTransmog') end
  if window then window:destroy() window = nil end
  slotWidgets = {}
end
