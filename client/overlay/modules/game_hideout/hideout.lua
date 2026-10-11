-- Hideout (server: server/data/scripts/chaos/hideout.lua, extended opcode 192, JSON {action, data}).
--   client -> server  open | get | enter | leave | visit {guid} | place {key, x, y, r} | move {id, x, y, r} |
--                     remove {id} | clear | theme {key} | perm {level} | kick | visits | like {owner}
--   server -> client  state {open, me, hideout, inside, layout, themes, catalogue, placed, permissions, categories}
--                     visits {friends, showcase = {likes, visits}, recent}     result {ok, text}
-- The window (Character > Hideout): Decorate (the catalogue with filters and lock reasons, what is placed, move /
-- remove), Hideout (theme, who may visit, enter / leave, like), Visit (friends, party, guild, the showcase, recent).
-- Placing: the window steps aside and the hovered map tile shows the decoration (green: it fits, red: it does not,
-- HideoutLogic.check); left click places it, the mouse wheel or Rotate turns it, right click or Done ends.

local OPCODE = 192
local HL = HideoutLogic

local window
local state
local visits
local tabButtons = {}
local currentTab = 'decorate'
local filter = { cat = 'all', source = 'all', ownedOnly = false, search = '' }
local selectedKey
local selectedPlaced
local rowWidgets = {}
local placedWidgets = {}
local showBy = 'likes'

-- placement mode
local placing -- {row, rot, moveId}
local ghosts = {} -- {tile, widget}
local bar
local mapPanel
local mapHooks
local lastHover

local function safe(name, fn)
  local reported = false
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported then
        reported = true
        g_logger.warning('[hideout] ' .. name .. ': ' .. tostring(res))
      end
      return false
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

local function status(text, good)
  if not window then return end
  window.statusLabel:setText(tostring(text or ''))
  window.statusLabel:setColor(good == nil and '#a89c86' or (good and '#8cd08c' or '#e07060'))
end

local function rowOf(key)
  for _, r in ipairs(state and state.catalogue or {}) do
    if r.key == key then return r end
  end
  return nil
end

local function placedOf(id)
  for _, p in ipairs(state and state.placed or {}) do
    if p.id == id then return p end
  end
  return nil
end

-- ---------------------------------------------------------------- Decorate tab
local function showDetail()
  if not window then return end
  local d = window.decorate.detail
  local r = rowOf(selectedKey)
  d:setVisible(r ~= nil)
  if not r then return end
  if r.item then d.item:setItemId(r.item) end
  d.item:setOpacity(r.owned and 1 or 0.45)
  d.nameLabel:setText(r.name)
  d.howLabel:setText(r.owned and (tr('Unlocked') .. ' - ' .. tostring(r.how)) or (tr('Locked') .. ' - ' .. tostring(r.how)))
  d.countLabel:setText(string.format('%d / %d %s%s', r.placed or 0, r.max or 0, tr('placed'),
    r.block and ('  -  ' .. tr('blocks the way')) or ''))
  local can, why = HL.canPlace(r, state.hideout, state.inside)
  d.placeButton:setEnabled(can)
  d.reasonLabel:setText(can and (r.layer == 'wall' and tr('Hangs on the north or the west wall.') or
    (r.layer == 'floor' and tr('A rug: objects may stand on it.') or '')) or tostring(why or ''))
  d.storeButton:setVisible(r.source == 'store' and not r.owned)
end

local function pick(key)
  selectedKey = key
  for k, w in pairs(rowWidgets) do
    if k == key then w:focus() end
  end
  showDetail()
end

local function showList()
  if not window or not state then return end
  local p = window.decorate
  p.list:destroyChildren()
  rowWidgets = {}
  local rows = HL.filter(state.catalogue, filter)
  for _, r in ipairs(rows) do
    local row = g_ui.createWidget('HideoutRow', p.list)
    if r.item then row.item:setItemId(r.item) end
    row.name:setText(r.name)
    row.sub:setText(HL.subText(r))
    if not r.owned then
      row.name:setColor('#8c8070')
      row.item:setOpacity(0.45)
    end
    local key = r.key
    row.onClick = function() pick(key) end
    rowWidgets[key] = row
  end
  if not rowOf(selectedKey) or not rowWidgets[selectedKey] then
    selectedKey = rows[1] and rows[1].key or nil
  end
  pick(selectedKey)
end

local function pickPlaced(id)
  selectedPlaced = id
  for k, w in pairs(placedWidgets) do
    if k == id then w:focus() end
  end
  local has = placedOf(id) ~= nil
  local owner = state and state.inside and state.inside.isOwner
  window.decorate.moveButton:setEnabled(has and owner == true)
  window.decorate.removeButton:setEnabled(has)
end

local function showPlaced()
  if not window or not state then return end
  local p = window.decorate
  p.placedList:destroyChildren()
  placedWidgets = {}
  for _, pl in ipairs(state.placed or {}) do
    local r = rowOf(pl.key)
    local row = g_ui.createWidget('HideoutSmallRow', p.placedList)
    if r and r.item then row.item:setItemId(r.item) end
    row.name:setText(string.format('%s  (%d, %d)', r and r.name or pl.key, pl.x, pl.y))
    local id = pl.id
    row.onClick = function() pickPlaced(id) end
    placedWidgets[id] = row
  end
  p.clearButton:setEnabled(#(state.placed or {}) > 0)
  pickPlaced(placedOf(selectedPlaced) and selectedPlaced or nil)
end

-- ---------------------------------------------------------------- Hideout tab
local permChecks = {}

local function showSettings()
  if not window or not state then return end
  local p = window.settings
  p.themeList:destroyChildren()
  for _, t in ipairs(state.themes or {}) do
    local row = g_ui.createWidget('HideoutRow', p.themeList)
    if t.item then row.item:setItemId(t.item) end
    row.name:setText(t.name .. (t.selected and ('  (' .. tr('yours') .. ')') or ''))
    row.sub:setText(t.owned and string.format('%s  %d %s', tostring(t.desc or ''), t.maxDecor or 0, tr('decorations'))
      or (tr('Locked') .. ' - ' .. tostring(t.how)))
    if not t.owned then
      row.name:setColor('#8c8070')
      row.item:setOpacity(0.45)
    end
    local key, owned = t.key, t.owned
    row.onClick = function()
      if owned then send('theme', { key = key }) else status(tr('Locked') .. ': ' .. tostring(t.how), false) end
    end
  end
  p.permFrame:destroyChildren()
  permChecks = {}
  for _, perm in ipairs(state.permissions or {}) do
    local c = g_ui.createWidget('ChaosCheckBox', p.permFrame)
    c:setText(perm.name .. ' - ' .. perm.desc)
    c:setChecked(state.hideout and state.hideout.perm == perm.id)
    local id = perm.id
    c.onCheckChange = function(widget, checked)
      if checked and state.hideout.perm ~= id then
        send('perm', { level = id })
      elseif not checked and state.hideout.perm == id then
        widget:setChecked(true)
      end
    end
    permChecks[id] = c
  end
  local h = state.hideout or {}
  p.statsLabel:setText(string.format('%s: %d   %s: %d', tr('Likes'), h.likes or 0, tr('Visits'), h.visits or 0) ..
    (state.inside and ('\n' .. tr('You are in the hideout of') .. ' ' .. tostring(state.inside.ownerName)) or ''))
  p.enterButton:setEnabled(not (state.inside and state.inside.isOwner))
  p.leaveButton:setEnabled(state.inside ~= nil)
  p.kickButton:setEnabled(state.inside ~= nil and state.inside.isOwner == true)
  p.likeButton:setVisible(state.inside ~= nil and not state.inside.isOwner)
end

-- ---------------------------------------------------------------- Visit tab
local function fillVisitList(list, rows, withButton)
  list:destroyChildren()
  for _, v in ipairs(rows or {}) do
    local row = g_ui.createWidget('HideoutVisitRow', list)
    row.name:setText(HL.visitLine(v))
    if v.online then row.name:setColor('#8cd08c') end
    local guid = v.guid
    row.go.onClick = function() send('visit', { guid = guid }) end
    row.go:setVisible(withButton ~= false)
  end
end

local function showVisits()
  if not window then return end
  local p = window.visit
  p.byLikes:setChecked(showBy == 'likes')
  p.byVisits:setChecked(showBy == 'visits')
  if not visits then return end
  fillVisitList(p.friendsList, visits.friends)
  fillVisitList(p.recentList, visits.recent)
  fillVisitList(p.showList, visits.showcase and visits.showcase[showBy] or {})
end

function showcaseBy(by)
  showBy = by == 'visits' and 'visits' or 'likes'
  showVisits()
end

-- ---------------------------------------------------------------- tabs and the window
local TABS = { { key = 'decorate', name = 'Decorate' }, { key = 'settings', name = 'Hideout' }, { key = 'visit', name = 'Visit' } }

function selectTab(key)
  currentTab = key
  for k, b in pairs(tabButtons) do b:setChecked(k == key) end
  window.decorate:setVisible(key == 'decorate')
  window.settings:setVisible(key == 'settings')
  window.visit:setVisible(key == 'visit')
  if key == 'visit' then send('visits') end
end

local function refresh()
  if not window or not state then return end
  window.counter:setText(HL.countText(state.hideout))
  showList()
  showPlaced()
  showSettings()
end

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
  elseif g_game.isOnline() then
    send('open')
  end
end

function enter() send('enter') end
function leave() send('leave') end
function kick() send('kick') end
function like()
  if state and state.inside then send('like', { owner = state.inside.owner }) end
end
function clearAll()
  if not state or #(state.placed or {}) == 0 then return end
  local box
  box = displayGeneralBox(tr('Put all away'), tr('Put every decoration of your hideout away? They stay unlocked.'),
    { { text = tr('Yes'), callback = function() box:destroy(); send('clear') end },
      { text = tr('No'), callback = function() box:destroy() end } })
end
function removeCurrent()
  if selectedPlaced then send('remove', { id = selectedPlaced }) end
end
function openStore()
  local shop = modules.game_shop
  if shop and type(shop.toggle) == 'function' then shop.toggle() end
end

-- ---------------------------------------------------------------- placement mode
local function tileSize()
  local vd = mapPanel and mapPanel:getVisibleDimension()
  local r = mapPanel and mapPanel:getRect()
  if not vd or not r or vd.width <= 0 or vd.height <= 0 then return 32, 32 end
  local w, h = r.width / vd.width, r.height / vd.height
  if mapPanel:isKeepAspectRatioEnabled() then
    local s = math.min(w, h)
    return s, s
  end
  return w, h
end

local function clearGhosts()
  for _, g in ipairs(ghosts) do
    if g.tile then
      local w = g.tile:getWidget()
      if w and w == g.widget then g.tile:removeWidget() end
    end
    if g.widget and not g.widget:isDestroyed() then g.widget:destroy() end
  end
  ghosts = {}
end

local function drawGhost(pos)
  clearGhosts()
  lastHover = pos
  if not placing or not state or not state.inside or not pos then return end
  local L = state.layout
  local gx, gy = HL.toGrid(state.inside.origin, L, pos)
  if not gx then
    if bar then bar.hint:setText(tr('Point at a tile of your hideout.')) end
    return
  end
  local r = placing.row
  local side = r.layer == 'wall' and HL.wallSide(L, gx, gy) or nil
  local fits, why = HL.check(state, r, gx, gy, placing.rot, placing.moveId)
  local tw, th = tileSize()
  for _, part in ipairs(HL.parts(r, placing.rot, side)) do
    local tile = g_map.getTile(HL.toWorld(state.inside.origin, gx + part[1], gy + part[2]))
    if tile then
      local w = g_ui.createWidget('HideoutGhost')
      w:setItemId(part[3])
      w:resize(math.floor(tw), math.floor(th))
      w:setBorderColor(fits and '#40e060' or '#e04040')
      tile:setWidget(w)
      ghosts[#ghosts + 1] = { tile = tile, widget = w }
    end
  end
  if bar then
    bar.hint:setText(fits and (string.format('(%d, %d) ', gx, gy) .. tr('Click: place. Wheel: rotate.'))
      or tostring(why))
    bar.hint:setColor(fits and '#8cd08c' or '#e07060')
  end
  return fits, gx, gy
end

local function confirmAt(pos)
  if not placing or not state or not state.inside then return end
  local fits, gx, gy = drawGhost(pos)
  if not fits then return end
  clearGhosts()
  if placing.moveId then
    send('move', { id = placing.moveId, x = gx, y = gy, r = placing.rot })
    stopPlacing()
  else
    send('place', { key = placing.row.key, x = gx, y = gy, r = placing.rot })
  end
end

local function onMouseMove(widget, mousePos)
  if not placing then return false end
  local pos = mapPanel:getPosition(mousePos)
  if pos and (not lastHover or pos.x ~= lastHover.x or pos.y ~= lastHover.y or pos.z ~= lastHover.z) then
    drawGhost(pos)
  end
  return false
end

local function onMousePress(widget, mousePos, button)
  if not placing then return false end
  return button == MouseLeftButton or button == MouseRightButton
end

local function onMouseRelease(widget, mousePos, button)
  if not placing then return false end
  if button == MouseRightButton then
    stopPlacing()
    return true
  end
  if button == MouseLeftButton then
    confirmAt(mapPanel:getPosition(mousePos))
    return true
  end
  return false
end

local function onMouseWheel(widget, mousePos, direction)
  if not placing then return false end
  rotate(direction == MouseWheelDown and -1 or 1)
  return true
end

function rotate(step)
  if not placing then return end
  placing.rot = HL.nextRot(placing.row, placing.rot, step or 1)
  if bar then
    local parts = HL.parts(placing.row, placing.rot)
    if parts[1] then bar.item:setItemId(parts[1][3]) end
  end
  drawGhost(lastHover)
end

local function hookMap()
  mapPanel = modules.game_interface and modules.game_interface.getMapPanel()
  if not mapPanel or mapHooks then return end
  mapHooks = { onMouseMove = safe('hover', onMouseMove), onMousePress = safe('press', onMousePress),
    onMouseRelease = safe('release', onMouseRelease), onMouseWheel = safe('wheel', onMouseWheel) }
  connect(mapPanel, mapHooks, true)
end

local function unhookMap()
  if mapPanel and mapHooks then disconnect(mapPanel, mapHooks) end
  mapHooks = nil
end

local function startPlacing(row, rot, moveId)
  if not state or not state.inside or not state.inside.isOwner then
    status(tr('Enter your hideout to decorate it.'), false)
    return
  end
  placing = { row = row, rot = rot or 1, moveId = moveId }
  hookMap()
  if not mapPanel then return end
  if not bar then
    bar = g_ui.createWidget('HideoutPlaceBar', rootWidget)
  end
  local mr = mapPanel:getRect()
  -- the map panel may reach above the screen (a zoomed layout): keep the bar below the top menu
  bar:setPosition({ x = math.max(0, mr.x + math.floor((mr.width - bar:getWidth()) / 2)), y = math.max(mr.y + 8, 44) })
  bar:show()
  bar:raise()
  local parts = HL.parts(row, placing.rot)
  if parts[1] then bar.item:setItemId(parts[1][3]) end
  bar.name:setText((moveId and tr('Moving') or tr('Placing')) .. ': ' .. row.name)
  bar.hint:setText(tr('Point at a tile of your hideout.'))
  bar.rotate:setEnabled(HL.rotCount(row) > 1)
  hide()
end

function stopPlacing()
  placing = nil
  clearGhosts()
  lastHover = nil
  unhookMap()
  if bar then bar:hide() end
  if g_game.isOnline() then send('open') end
end

function placeCurrent()
  local r = rowOf(selectedKey)
  local can, why = HL.canPlace(r, state and state.hideout, state and state.inside)
  if not can then
    status(why, false)
    return
  end
  startPlacing(r, 1)
end

function moveCurrent()
  local p = placedOf(selectedPlaced)
  local r = p and rowOf(p.key)
  if r then startPlacing(r, p.r or 1, p.id) end
end

-- ---------------------------------------------------------------- protocol
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    state = data
    refresh()
    if placing then
      -- keep placing after a placement while the decoration may still go in
      local r = rowOf(placing.row.key)
      if r then placing.row = r end
      local can = placing.moveId or HL.canPlace(placing.row, state.hideout, state.inside)
      if not can or not state.inside or not state.inside.isOwner then
        stopPlacing()
      else
        drawGhost(lastHover)
      end
    elseif data.open then
      show()
    end
  elseif msg.action == 'visits' then
    visits = data
    showVisits()
  elseif msg.action == 'result' then
    status(data.text, data.ok == true)
    if bar and placing and data.text then
      bar.hint:setText(tostring(data.text))
      bar.hint:setColor(data.ok and '#8cd08c' or '#e07060')
    end
  end
end

local function onGameEnd()
  if placing then
    placing = nil
    clearGhosts()
    unhookMap()
    if bar then bar:hide() end
  end
  hide()
  state, visits, selectedKey, selectedPlaced = nil, nil, nil, nil
end

function init()
  window = g_ui.displayUI('hideout')
  window:hide()
  for _, t in ipairs(TABS) do
    local b = g_ui.createWidget('ChaosTabButton', window.tabs)
    b:setText(tr(t.name))
    b:setWidth(110)
    local key = t.key
    b.onClick = function() selectTab(key) end
    tabButtons[key] = b
  end
  local p = window.decorate
  p.catCombo:addOption(tr('Every kind'), 'all')
  for _, c in ipairs({ { 'furniture', 'Furniture' }, { 'light', 'Lights' }, { 'statue', 'Statues' }, { 'nature', 'Nature' },
      { 'macabre', 'Bones' }, { 'banner', 'Banners' }, { 'wall', 'Wall' }, { 'rug', 'Rugs' }, { 'trophy', 'Trophies' } }) do
    p.catCombo:addOption(tr(c[2]), c[1])
  end
  p.catCombo.onOptionChange = function(_, _, value) filter.cat = value or 'all'; showList() end
  for _, s in ipairs(HL.SOURCES) do p.srcCombo:addOption(tr(s.name), s.key) end
  p.srcCombo.onOptionChange = function(_, _, value) filter.source = value or 'all'; showList() end
  p.ownedCheck.onCheckChange = function(_, checked) filter.ownedOnly = checked; showList() end
  p.search.onTextChange = function(_, text) filter.search = text or ''; showList() end
  selectTab('decorate')
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, safe('opcode', onMessage))
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if placing then
    placing = nil
    clearGhosts()
    unhookMap()
  end
  if bar then bar:destroy() end
  bar = nil
  if window then window:destroy() end
  window = nil
end
