-- DPS meter: a compact, movable and resizable panel over the game view with a bar per skill (spell, rune, weapon
-- attack, damage over time, proc, summon) and its total, per second and share; tabs Damage / Healing / Taken /
-- Received; a dropdown for the current fight, the session or one of the last 10 fights (boss fights carry the boss's
-- name); a party mode with every sharing member's DPS / HPS; and a detail window (Combat Log) with hits, crits,
-- average and max per skill and the element split. Export: a summary to the clipboard or one line into the chat input
-- (local only, nothing is sent by itself). Settings (shown, position, size, tab, party mode, sharing, lock) are kept in
-- g_settings node 'chaosDpsMeter'. The server counts and attributes everything (server/data/scripts/chaos/
-- combatlog.lua) and pushes it on extended opcode 204 (JSON, joined by registerExtendedJSONOpcode):
--   server -> client  state {sel, segs, v, live, share, party?}   (combatlog_core.lua CL.state)
--   client -> server  open {seg, party, share} | close | seg {id} | party {on} | share {on} | reset
-- Pure parts: dpsmath.lua (dpsmath_test.lua). Menu: Hunt > DPS Meter, and the Hunt Tracker's Meter button.

local OPCODE = 204
local NODE = 'chaosDpsMeter'

local panel, details
local settings = DpsMath.sanitize(nil)
local state
local segSel = 'c'         -- the segment shown: 'c', 's' or a fight id (only 'c' / 's' are saved)
local watching = false
local tabButtons, detailTabButtons = {}, {}
local panelSegKey, detailSegKey
local dragOffset, resizeFrom

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

-- ---------------------------------------------------------------- settings, server
local function loadSettings()
  local ok, node = pcall(g_settings.getNode, NODE)
  settings = DpsMath.sanitize(ok and node or nil)
  segSel = settings.seg
end

local function saveSettings()
  pcall(g_settings.setNode, NODE, settings)
  pcall(g_settings.save)
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function startWatching()
  if g_game.isOnline() and (settings.shown or (alive(details) and details:isVisible())) then
    watching = true
    send('open', { seg = segSel, party = settings.party, share = settings.share })
  end
end

local function stopWatching()
  if watching then
    watching = false
    send('close')
  end
end

local function status(text)
  local tm = modules.game_textmessage
  if tm and tm.displayStatusMessage then tm.displayStatusMessage(text) end
end

-- ---------------------------------------------------------------- icons
local function setIcon(row, kind, icon)
  local spec = DpsMath.iconSpec(kind, icon)
  if spec.kind == 'item' then
    row.icon:setVisible(false)
    row.item:setItemId(spec.id)
    row.item:setVisible(true)
    return
  end
  row.item:setVisible(false)
  row.icon:setVisible(true)
  if spec.kind == 'spell' then
    if Spells and Spells.getSpellIcon then
      local ok, folder, clip = pcall(Spells.getSpellIcon, spec.words)
      if ok and folder then
        row.icon:setImageSource(folder)
        row.icon:setImageClip(clip)
        return
      end
    end
    row.icon:setImageSource(spec.fallback)
  else
    row.icon:setImageSource(spec.path)
  end
  row.icon:setImageClip('0 0 26 26')
end

-- ---------------------------------------------------------------- segment dropdowns
local function fillCombo(combo, keyRef)
  local options = DpsMath.segmentOptions(state and state.segs)
  local key = DpsMath.segmentKey(options)
  if key ~= keyRef then
    combo:clearOptions()
    for _, o in ipairs(options) do combo:addOption(o.text, o.id, true) end
  end
  local found = false
  for _, o in ipairs(options) do
    if o.id == segSel then found = true end
  end
  pcall(function() combo:setCurrentOptionByData(found and segSel or 'c', true) end)
  return key
end

local function chooseSegment(id)
  if id == nil or id == segSel then return end
  segSel = id
  if id == 'c' or id == 's' then
    settings.seg = id
    saveSettings()
  end
  send('seg', { id = id })
end

-- ---------------------------------------------------------------- the panel
local rowPool = {}

local function rowAt(i)
  local list = panel.rows
  local row = rowPool[i]
  if not alive(row) then
    row = g_ui.createWidget('DpsBarRow', list)
    rowPool[i] = row
  end
  row:setVisible(true)
  return row
end

local function hideRowsFrom(i)
  for k = i, #rowPool do
    if alive(rowPool[k]) then rowPool[k]:setVisible(false) end
  end
end

local function setBar(row, frac, color)
  local width = math.max(1, panel:getWidth() - 8 - 18)
  row.fill:setWidth(math.max(1, math.floor(width * math.max(0, math.min(1, frac)))))
  row.fill:setBackgroundColor(color)
end

function refreshPanel()
  if not alive(panel) or not panel:isVisible() then return end
  local tab = DpsMath.tab(settings.tab)
  for key, b in pairs(tabButtons) do b:setOn(key == settings.tab) end
  panel.header.partyButton:setOn(settings.party)
  panel.header.liveDot:setVisible(state ~= nil and state.live == 1)
  panelSegKey = fillCombo(panel.segCombo, panelSegKey)
  local view = state and state.v
  local wide = panel:getWidth() >= 220
  local n = 0
  if settings.party and state and state.party then
    local rows = DpsMath.partyRows(state.party, tab.idx, segSel == 's')
    for i, r in ipairs(rows) do
      local row = rowAt(i)
      setIcon(row, 'u', 'player')
      row.name:setText(r.name)
      row.name:setColor(r.self and '#f6cf72' or '#f2e8d0')
      row.value:setText(string.format('%s %s', DpsMath.short(r.rate), tab.rate) ..
        (wide and string.format('  (%s)', DpsMath.short(r.value)) or ''))
      row:setTooltip(tr('%s: %s %s, %s in all', r.name, DpsMath.exact(r.rate), tab.rate, DpsMath.exact(r.value)))
      setBar(row, r.frac, r.self and '#a8843a' or '#5a4a6a')
      n = i
    end
    panel.summary:setText(tr('Party, %s: %s', segSel == 's' and tr('session') or tr('current fight'), tr(tab.name)))
    panel.emptyText:setText(tr('No party numbers yet.'))
  else
    local rows, total = DpsMath.rows(view, tab.idx)
    for i, r in ipairs(rows) do
      local row = rowAt(i)
      setIcon(row, r.kind, r.icon)
      row.name:setText(r.name)
      row.name:setColor('#f2e8d0')
      if wide then
        row.value:setText(string.format('%s  %s/s  %s%%', DpsMath.short(r.total), DpsMath.short(r.rate), tostring(r.pct)))
      else
        row.value:setText(string.format('%s  %s%%', DpsMath.short(r.total), tostring(r.pct)))
      end
      row:setTooltip(tr('%s\n%s in all, %s per second, %s%%\n%d hits, %d%% critical, average %s, max %s', r.name,
        DpsMath.exact(r.total), DpsMath.exact(r.rate), tostring(r.pct), r.hits, r.critPct, DpsMath.exact(r.avg),
        DpsMath.exact(r.max)) .. (r.over > 0 and tr('\noverhealing %s', DpsMath.exact(r.over)) or ''))
      setBar(row, r.frac, DpsMath.barColor(r.kind, tab.idx))
      n = i
    end
    if view then
      panel.summary:setText(string.format('%s   %s (%s %s)', DpsMath.title(view), DpsMath.short(total),
        DpsMath.short(DpsMath.perSecond(total, view.dur)), tab.rate))
    else
      panel.summary:setText(DpsMath.title(nil))
    end
    panel.emptyText:setText(state and tr('Nothing in this tab yet.') or tr('Waiting for the server...'))
  end
  hideRowsFrom(n + 1)
  panel.emptyText:setVisible(n == 0)
end

-- ---------------------------------------------------------------- the detail window
local COLUMNS = {
  { key = 'total', name = 'Total', w = 66 }, { key = 'pct', name = '%', w = 44 }, { key = 'rate', name = 'Per s', w = 58 },
  { key = 'hits', name = 'Hits', w = 44 }, { key = 'crit', name = 'Crit', w = 40 }, { key = 'avg', name = 'Avg', w = 56 },
  { key = 'max', name = 'Max', w = 56 }, { key = 'over', name = 'Over', w = 60 },
}
local NAME_W = 150

local function placeCells(parent, style, isHeader)
  local cells = {}
  local x = 22 + NAME_W
  for _, col in ipairs(COLUMNS) do
    local cell = g_ui.createWidget(style, parent)
    cell:setWidth(col.w)
    cell:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    cell:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    cell:setMarginLeft(x)
    if isHeader then cell:setText(col.name == '%' and '%' or tr(col.name)) end
    cells[col.key] = cell
    x = x + col.w
  end
  return cells
end

function refreshDetails()
  if not alive(details) or not details:isVisible() then return end
  local tab = DpsMath.tab(settings.detailTab)
  for key, b in pairs(detailTabButtons) do b:setChecked(key == settings.detailTab) end
  detailSegKey = fillCombo(details.segCombo, detailSegKey)
  local view = state and state.v
  local rows, total = DpsMath.rows(view, tab.idx)
  local healTab = tab.idx == 2 or tab.idx == 4
  if details.headerCells then details.headerCells.over:setVisible(healTab) end
  details.rowList:destroyChildren()
  for i, r in ipairs(rows) do
    local row = g_ui.createWidget('DpsDetailRow', details.rowList)
    if i % 2 == 0 then row:setBackgroundColor('#141014') end
    setIcon(row, r.kind, r.icon)
    row.name:setText(r.name)
    local c = placeCells(row, 'DpsDetailCell')
    c.total:setText(DpsMath.exact(r.total))
    c.total:setColor('#f6cf72')
    c.pct:setText(tostring(r.pct) .. '%')
    c.rate:setText(DpsMath.exact(r.rate))
    c.hits:setText(tostring(r.hits))
    c.crit:setText(r.critPct .. '%')
    c.avg:setText(DpsMath.exact(r.avg))
    c.max:setText(DpsMath.exact(r.max))
    c.over:setText(healTab and DpsMath.exact(r.over) or '')
  end
  details.emptyText:setText(state and tr('Nothing in this tab yet.') or tr('Waiting for the server...'))
  details.emptyText:setVisible(#rows == 0)
  if view then
    details.headPanel.segTitle:setText(DpsMath.title(view) .. (view.boss == 1 and ('   ' .. tr('Boss fight')) or ''))
    local over = view.t and view.t[tab.idx] and tonumber(view.t[tab.idx].ov) or 0
    details.headPanel.segInfo:setText(tr('%s: %s in all, %s %s', tr(tab.name), DpsMath.exact(total),
      DpsMath.exact(DpsMath.perSecond(total, view.dur)), tab.rate) ..
      (healTab and over > 0 and tr(', overhealing %s', DpsMath.exact(over)) or ''))
  else
    details.headPanel.segTitle:setText(DpsMath.title(nil))
    details.headPanel.segInfo:setText('')
  end
  local parts = {}
  for _, e in ipairs(DpsMath.elements(view, tab.idx)) do
    parts[#parts + 1] = string.format('%s %s%%', tr(e.name), tostring(e.pct))
  end
  details.elements:setText(#parts > 0 and (tr('Elements: ') .. table.concat(parts, ', ')) or '')
end

local function refreshAll()
  refreshPanel()
  refreshDetails()
end

-- ---------------------------------------------------------------- protocol
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' or msg.action ~= 'state' or type(msg.data) ~= 'table' then return end
  state = msg.data
  if state.sel ~= nil then segSel = state.sel end
  refreshAll()
end

-- ---------------------------------------------------------------- panel position and size
local function clampPanel()
  if not alive(panel) or dragOffset then return end
  local parent = panel:getParent()
  if not parent then return end
  panel:setSize({ width = settings.w, height = settings.h })
  -- default: the left edge of the screen, under the character plate and the buff bar (screen pixels; the map panel
  -- may start above or left of the screen)
  local x, y = settings.x, settings.y
  if not x or not y then
    x, y = DpsMath.DEFAULT_X - parent:getX(), DpsMath.DEFAULT_Y - parent:getY()
  end
  x, y = DpsMath.clampPosition(x, y, panel:getWidth(), panel:getHeight(), parent:getWidth(), parent:getHeight())
  panel:setMarginLeft(x)
  panel:setMarginTop(y)
end

local function onHeaderPress(w, pos, button)
  if button ~= MouseLeftButton or settings.locked then return false end
  dragOffset = { x = pos.x - panel:getX(), y = pos.y - panel:getY() }
  w:grabMouse()
  return true
end

local function onHeaderMove(w, pos)
  if not dragOffset then return false end
  local parent = panel:getParent()
  local x, y = DpsMath.clampPosition(pos.x - dragOffset.x - parent:getX(), pos.y - dragOffset.y - parent:getY(),
    panel:getWidth(), panel:getHeight(), parent:getWidth(), parent:getHeight())
  panel:setMarginLeft(x)
  panel:setMarginTop(y)
  return true
end

local function onHeaderRelease(w)
  if not dragOffset then return false end
  dragOffset = nil
  w:ungrabMouse()
  local parent = panel:getParent()
  settings.x = panel:getX() - parent:getX()
  settings.y = panel:getY() - parent:getY()
  saveSettings()
  return true
end

local function onGripPress(w, pos, button)
  if button ~= MouseLeftButton or settings.locked then return false end
  resizeFrom = { x = pos.x, y = pos.y, w = panel:getWidth(), h = panel:getHeight() }
  w:grabMouse()
  return true
end

local function onGripMove(w, pos)
  if not resizeFrom then return false end
  local nw, nh = DpsMath.clampSize(resizeFrom.w + pos.x - resizeFrom.x, resizeFrom.h + pos.y - resizeFrom.y)
  panel:setSize({ width = nw, height = nh })
  refreshPanel()
  return true
end

local function onGripRelease(w)
  if not resizeFrom then return false end
  resizeFrom = nil
  w:ungrabMouse()
  settings.w, settings.h = panel:getWidth(), panel:getHeight()
  saveSettings()
  refreshPanel()
  return true
end

-- ---------------------------------------------------------------- public (menu, buttons)
function show()
  if not alive(panel) then return end
  settings.shown = true
  saveSettings()
  panel:show()
  panel:raise()
  clampPanel()
  refreshPanel()
  startWatching()
end

function hide()
  if not alive(panel) then return end
  settings.shown = false
  saveSettings()
  panel:hide()
  if not (alive(details) and details:isVisible()) then stopWatching() end
end

function toggle()
  if alive(panel) and panel:isVisible() then hide() else show() end
end

function toggleDetails()
  if not alive(details) then return end
  if details:isVisible() then
    hideDetails()
    return
  end
  details:show()
  details:raise()
  details:focus()
  if not watching then startWatching() end
  refreshDetails()
end

function hideDetails()
  if alive(details) then details:hide() end
  if not settings.shown then stopWatching() end
end

function toggleParty()
  settings.party = not settings.party
  saveSettings()
  send('party', { on = settings.party })
  refreshPanel()
end

function setShare(on)
  settings.share = on and true or false
  saveSettings()
  send('share', { on = settings.share })
end

function resetMeter()
  local box
  local function yes()
    if box then box:destroy() box = nil end
    send('reset')
  end
  local function no()
    if box then box:destroy() box = nil end
  end
  if displayGeneralBox then
    box = displayGeneralBox(tr('Reset the meter'), tr('Forget every fight and start the session from zero?'),
      { { text = tr('Yes'), callback = yes }, { text = tr('No'), callback = no }, anchor = AnchorHorizontalCenter }, yes, no)
  else
    yes()
  end
end

local function exportTab()
  if alive(details) and details:isVisible() then return DpsMath.tab(settings.detailTab).idx end
  return DpsMath.tab(settings.tab).idx
end

function exportClipboard()
  local view = state and state.v
  if not view then return end
  g_window.setClipboardText(DpsMath.summary(view, exportTab()))
  status(tr('Fight summary copied to the clipboard.'))
end

-- one line into the chat input; the player decides whether to send it
function exportChat()
  local view = state and state.v
  if not view then return end
  local line = DpsMath.chatLine(view, exportTab(), 240)
  local console = modules.game_console
  local edit = console and console.getConsole and console.getConsole()
  if edit then
    if console.enableChat then pcall(console.enableChat, true) end
    edit:setText(line)
    pcall(function() edit:setCursorPos(-1) end)
    pcall(function() edit:focus() end)
    status(tr('Fight summary put into the chat input.'))
  else
    g_window.setClipboardText(line)
    status(tr('Fight summary copied to the clipboard.'))
  end
end

function setLocked(on)
  settings.locked = on and true or false
  saveSettings()
end

function resetPosition()
  settings.x, settings.y = nil, nil
  settings.w, settings.h = DpsMath.DEFAULTS.w, DpsMath.DEFAULTS.h
  saveSettings()
  clampPanel()
  refreshPanel()
end

function showMenu()
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addOption(tr('Copy the summary'), function() exportClipboard() end)
  menu:addOption(tr('Summary into the chat input'), function() exportChat() end)
  menu:addOption(tr('Combat log (details)'), function() toggleDetails() end)
  menu:addSeparator()
  menu:addOption((settings.share and '[x] ' or '[ ] ') .. tr('Share my totals with my party'), function()
    setShare(not settings.share)
  end)
  menu:addOption((settings.locked and '[x] ' or '[ ] ') .. tr('Lock position and size'), function()
    setLocked(not settings.locked)
  end)
  menu:addOption(tr('Reset position and size'), function() resetPosition() end)
  menu:addSeparator()
  menu:addOption(tr('Reset the meter...'), function() resetMeter() end)
  menu:display(g_window.getMousePosition())
end

-- ---------------------------------------------------------------- lifecycle
local function buildTabs()
  panel.tabs:destroyChildren()
  tabButtons = {}
  for _, t in ipairs(DpsMath.TABS) do
    local b = g_ui.createWidget('DpsTabButton', panel.tabs)
    b:setText(tr(t.short))
    b:setTooltip(tr(t.tip))
    local key = t.key
    b.onClick = function()
      settings.tab = key
      saveSettings()
      refreshPanel()
    end
    tabButtons[key] = b
  end
  details.tabs:destroyChildren()
  detailTabButtons = {}
  for _, t in ipairs(DpsMath.TABS) do
    local b = g_ui.createWidget('DpsTab', details.tabs)
    b:setText(tr(t.name))
    b:setTooltip(tr(t.tip))
    local key = t.key
    b.onClick = function()
      settings.detailTab = key
      saveSettings()
      refreshDetails()
    end
    detailTabButtons[key] = b
  end
  details.header:destroyChildren()
  local nameHead = g_ui.createWidget('DpsHeaderCell', details.header)
  nameHead:setText(tr('Source'))
  nameHead:setTextAlign(AlignLeft)
  nameHead:setWidth(NAME_W)
  nameHead:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  nameHead:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  nameHead:setMarginLeft(30)
  details.headerCells = placeCells(details.header, 'DpsHeaderCell', true)
  for _, cell in pairs(details.headerCells) do cell:setMarginLeft(cell:getMarginLeft() + 8) end
end

local function onGameStart()
  state, panelSegKey, detailSegKey = nil, nil, nil
  watching = false
  segSel = settings.seg
  if settings.shown and alive(panel) then
    panel:show()
    clampPanel()
    refreshPanel()
  end
  scheduleEvent(function() startWatching() end, 400)
end

local function onGameEnd()
  watching = false
  state = nil
  if alive(panel) then panel:hide() end
  if alive(details) then details:hide() end
end

function init()
  g_ui.importStyle('dpsmeter')
  loadSettings()
  panel = g_ui.createWidget('DpsMeterPanel', modules.game_interface.getMapPanel())
  panel:hide()
  local header = panel:getChildById('header')
  header.onMousePress = onHeaderPress
  header.onMouseMove = onHeaderMove
  header.onMouseRelease = onHeaderRelease
  panel.grip.onMousePress = onGripPress
  panel.grip.onMouseMove = onGripMove
  panel.grip.onMouseRelease = onGripRelease
  panel.segCombo.onOptionChange = function(combo, text, data) chooseSegment(data) end
  details = g_ui.createWidget('DpsMeterDetails', g_ui.getRootWidget())
  details:hide()
  details.segCombo.onOptionChange = function(combo, text, data) chooseSegment(data) end
  buildTabs()
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, onMessage)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  stopWatching()
  rowPool = {}
  if alive(details) then details:destroy() end
  if alive(panel) then panel:destroy() end
  panel, details, state = nil, nil, nil
end
