-- Community window: the community goal's bar with its four stages (and the buff each one lights), your contribution
-- with today's sources, the top contributors and the week's world modifiers; and the Brazier dialog.
-- Server: server/data/scripts/chaos/community.lua, extended opcode 203 (JSON {action, data}; the state goes out with
-- Chaos.sendChunked and is joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | close | donate {gold}
--   server -> client  state {...} (communityview.lua has the shape) | msg {text, ok} | brazier {} (the Brazier was used)
-- Menu: Adventure > Community (added with ChaosTopBar.addEntry). Icons: /images/game/buffs/community_<stage> and
-- wmod_<modifier> (client/tools/gen_community_icons.py). Countdowns run on the client between two states.

local OPCODE = 203
local V = CommunityView

local window
local dialog
local data
local arrived = 0
local handlers = {}
local reported = {}
local msgEvent
local tickEvent

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[community] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function send(action, d)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = d or {} }))
  end
end

local function elapsed()
  return math.max(0, g_clock.seconds() - arrived)
end

-- ---------------------------------------------------------------- the goal
local function renderMarkers()
  local area = window.barArea
  for _, child in ipairs(area:getChildren()) do
    if child:getId() ~= 'goalBar' then child:destroy() end
  end
  local width = area:getWidth()
  for _, s in ipairs(type(data.stages) == 'table' and data.stages or {}) do
    if (tonumber(s.pct) or 0) < 100 then
      local m = g_ui.createWidget('CommunityMarker', area)
      m:addAnchor(AnchorTop, 'parent', AnchorTop)
      m:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      m:setMarginLeft(V.markerX(s.pct, width, 2))
      m:setHeight(area:getHeight())
    end
  end
end

local function renderStages()
  local panel = window.stagePanel
  panel:destroyChildren()
  local stages = type(data.stages) == 'table' and data.stages or {}
  for i, s in ipairs(stages) do
    local chip = g_ui.createWidget('CommunityStageChip', panel)
    chip.icon:setImageSource(V.stageIcon(s.key))
    chip.name:setText(tostring(s.n or ''))
    chip.pct:setText(V.stageShort(s))
    local line, color = V.stageLine(s, elapsed())
    chip.line:setText(line)
    chip.line:setColor(color)
    local state = V.stageState(s, elapsed())
    chip.icon:setOpacity(state == 'todo' and 0.45 or 1)
    if state == 'open' then
      chip:setImageSource('/images/chaos/panel_highlight')
      chip:setImageBorder(8)
    end
    if i == #stages then chip:setMarginRight(0) end
    chip:setTooltip(V.stageTooltip(s))
  end
end

local function renderMine()
  local f = window.mineFrame
  f.mineLabel:setText(V.mineText(data))
  f.todayLabel:setText(V.todayText(data))
  f.rewardLabel:setText(V.rewardText(data))
  f.sourceList:destroyChildren()
  for _, r in ipairs(V.sourceRows(data)) do
    local row = g_ui.createWidget('CommunitySourceRow', f.sourceList)
    row.name:setText(r.name)
    row.value:setText(r.text)
    row.value:setColor(r.pct >= 100 and '#e05a3a' or '#d6c9ae')
    row:setTooltip(r.pct >= 100 and tr('Daily cap reached for this source.') or '')
  end
end

local function renderTop()
  local f = window.topFrame
  f.topList:destroyChildren()
  local rows = V.topRows(data)
  for _, r in ipairs(rows) do
    local row = g_ui.createWidget('CommunityTopRow', f.topList)
    row.place:setText(r.place .. '.')
    row.name:setText(r.name)
    row.value:setText(r.text)
  end
  f.topEmpty:setVisible(#rows == 0)
end

local function renderWeek()
  window.weekTitle:setText(V.weekText(data, elapsed()))
  local list = window.weekFrame.modList
  list:destroyChildren()
  local mods = data.week and type(data.week.mods) == 'table' and data.week.mods or {}
  for _, m in ipairs(mods) do
    local row = g_ui.createWidget('CommunityModRow', list)
    row.icon:setImageSource(V.modIcon(m.k))
    row.name:setText(tostring(m.n or m.k))
    row.text:setText(tostring(m.d or ''))
    row:setTooltip(tostring(m.d or ''))
  end
end

local function renderTimes()
  if not window or not data then return end
  window.timeLabel:setText(V.goalTimeText(data, elapsed()))
  window.weekTitle:setText(V.weekText(data, elapsed()))
  for i, chip in ipairs(window.stagePanel:getChildren()) do
    local s = data.stages and data.stages[i]
    if s then
      local line, color = V.stageLine(s, elapsed())
      chip.line:setText(line)
      chip.line:setColor(color)
    end
  end
end

-- ---------------------------------------------------------------- the Brazier dialog
local function renderDialog()
  if not dialog or not data then return end
  local b = data.brazier or {}
  dialog.goldLabel:setText(tr('You carry %s gold (backpack and bank). The Brazier takes up to %s more from you today.',
    V.fmt(b.gold), V.fmt(b.room)))
  local text, ok, color = V.donateState(data, dialog.amountEdit:getText())
  dialog.previewLabel:setText(text)
  dialog.previewLabel:setColor(color)
  dialog.donateButton:setEnabled(ok)
end

local function buildQuick()
  if not dialog then return end
  dialog.quickRow:destroyChildren()
  for _, g in ipairs(V.quickAmounts(data)) do
    local btn = g_ui.createWidget('ChaosButton', dialog.quickRow)
    btn:setWidth(64)
    btn:setText(V.short(g))
    btn.onClick = function()
      local cur = V.parseGold(dialog.amountEdit:getText()) or 0
      dialog.amountEdit:setText(tostring(cur + g))
      return true
    end
  end
end

function render()
  if not data then return end
  if window and window:isVisible() then
    local g = data.goal or {}
    window.goalName:setText(tostring(g.n or '') .. (g.rn and (' - ' .. g.rn) or ''))
    window.goalText:setText(tostring(g.d or ''))
    local bar = window.barArea.goalBar
    bar:setPercent(V.barPercent(data))
    bar:setText(V.barText(data))
    bar:setBackgroundColor(V.barPercent(data) >= 100 and V.COLORS.barDone or V.COLORS.bar)
    renderMarkers()
    renderStages()
    renderMine()
    renderTop()
    renderWeek()
    renderTimes()
  end
  renderDialog()
end

-- ---------------------------------------------------------------- messages
local function showMessage(text, ok)
  local label = window and window.msgLabel
  if label then
    label:setText(tostring(text or ''))
    label:setColor(ok and '#6fd86f' or '#e05a3a')
  end
  if dialog and dialog:isVisible() then
    dialog.previewLabel:setText(tostring(text or ''))
    dialog.previewLabel:setColor(ok and '#6fd86f' or '#e05a3a')
  end
  if msgEvent then removeEvent(msgEvent) end
  msgEvent = scheduleEvent(function()
    msgEvent = nil
    if window then window.msgLabel:setText('') end
  end, 6000)
end

local function tick()
  tickEvent = nil
  if (window and window:isVisible()) or (dialog and dialog:isVisible()) then
    renderTimes()
    tickEvent = scheduleEvent(tick, 1000)
  end
end

local function startTick()
  if not tickEvent then tickEvent = scheduleEvent(tick, 1000) end
end

local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local d = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    data = d
    arrived = g_clock.seconds()
    render()
  elseif msg.action == 'msg' then
    showMessage(d.text, d.ok)
  elseif msg.action == 'brazier' then
    showBrazier()
  end
end

-- ---------------------------------------------------------------- windows
function hide()
  if window and window:isVisible() then
    window:hide()
    if not (dialog and dialog:isVisible()) then send('close') end
  end
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  send('open')
  render()
  startTick()
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

function showBrazier()
  if not dialog then return end
  dialog:show()
  dialog:raise()
  dialog:focus()
  dialog.amountEdit:focus()
  buildQuick()
  send('open')
  renderDialog()
  startTick()
end

function hideBrazier()
  if dialog and dialog:isVisible() then
    dialog:hide()
    if not (window and window:isVisible()) then send('close') end
  end
end

function donate()
  if not dialog or not data then return end
  local take = V.donation(data, V.parseGold(dialog.amountEdit:getText()))
  if take and take > 0 then
    send('donate', { gold = take })
    dialog.amountEdit:setText('')
  end
end

-- for other modules and tests: load a payload as if the server had sent it
function setData(d)
  data = d
  arrived = g_clock.seconds()
  render()
end

function getState()
  return { visible = window and window:isVisible() or false, dialog = dialog and dialog:isVisible() or false,
    stages = data and #(data.stages or {}) or 0, mods = data and data.week and #(data.week.mods or {}) or 0 }
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'adventure',
      { text = 'Community', icon = 'events', modules = { 'game_community' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  data = nil
  addMenu()
end

local function onGameEnd()
  if window then window:hide() end
  if dialog then dialog:hide() end
  data = nil
end

function init()
  local ok, ui = pcall(g_ui.displayUI, 'community')
  if ok and ui then
    window = ui
    window:hide()
  else
    g_logger.warning('[community] window not loaded: ' .. tostring(ui))
  end
  local ok2, dlg = pcall(g_ui.displayUI, 'brazier')
  if ok2 and dlg then
    dialog = dlg
    dialog:hide()
    dialog.amountEdit.onTextChange = safe('amount', function() renderDialog() end)
    dialog.amountEdit.onEnter = safe('enter', donate)
  else
    g_logger.warning('[community] brazier dialog not loaded: ' .. tostring(dlg))
  end
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, safe('opcode', onMessage))
  connect(g_game, handlers.game)
  addMenu()
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game)
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if msgEvent then removeEvent(msgEvent) msgEvent = nil end
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  if window then window:destroy() window = nil end
  if dialog then dialog:destroy() dialog = nil end
  data, handlers = nil, {}
end
