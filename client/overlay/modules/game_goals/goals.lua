-- Next Goals (server/data/scripts/chaos/goals.lua, extended opcode 178): the window with the goals of the character's
-- level band, the gear path and hunts of the band and the next unlocks, and a compact tracker on screen. The pure
-- parts: goalsview.lua (GoalsView, tested by goalsview_test.lua). Menu: Adventure > Next Goals and Adventure > Goal
-- Tracker (added with ChaosTopBar.addEntry). The "where" buttons open a window or put a mark on the minimap.
--   client -> server  open | close | tracker
--   server -> client  goals {...} (chunked) | tracker {rows} | done {text}

local OPCODE = 178
local V = GoalsView
local SETTING_TRACKER = 'chaos_goals_tracker'
local SETTING_FOLDED = 'chaos_goals_tracker_folded'

local window, tracker
local st = V.new()
local menuAdded = false
local buffer = ''

local function send(action)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = {} }))
  end
end

local function status(text)
  pcall(function() modules.game_textmessage.displayStatusMessage(text) end)
end

-- ---------------------------------------------------------------- where: windows and map marks
local function callPath(path, args)
  local mod, fn = path:match('^([%w_]+)%.(.+)$')
  local m = mod and modules[mod]
  local f = type(m) == 'table' and rawget(m, fn) or nil
  if type(f) ~= 'function' then
    return false
  end
  local ok = pcall(f, unpack(args or {}))
  return ok
end

local function markOnMap(pos, label)
  local mm = modules.game_minimap
  local widget = mm and rawget(mm, 'minimapWidget')
  if widget then
    pcall(function() widget:addFlag(pos, 0, label) end)
    pcall(function() widget:setCameraPosition(pos) end)
  end
  status(tr('Marked on your map: %s', label ~= '' and label or string.format('%d, %d, %d', pos.x, pos.y, pos.z)))
end

function runWhere(where)
  local a = V.action(where)
  if not a then return end
  if a.call then
    if not callPath(a.call, a.args) then
      status(tr('That window is not available.'))
    end
  elseif a.map then
    markOnMap(a.map, a.label)
  end
end

-- ---------------------------------------------------------------- the window
local function addSide(style, text, where)
  local w = g_ui.createWidget(style, window.sideList)
  w:setText(text)
  if where and V.action(where) then
    w:setColor('#9ab8ff')
    w:setTooltip(tr('Click: %s', V.whereButton(where) or tr('Open')))
    w.onClick = function() runWhere(where) end
  end
  return w
end

local function drawSide()
  window.sideList:destroyChildren()
  addSide('GoalSideTitle', tr('Gear path'))
  for _, g in ipairs(st.gear) do
    addSide('GoalSideLine', '- ' .. tostring(g.text or ''), g.where)
  end
  addSide('GoalSideTitle', tr('Where to hunt'))
  if #st.hunts > 0 then
    for _, h in ipairs(st.hunts) do
      addSide('GoalSideLine', '- ' .. V.huntLine(h), h.where)
    end
  else
    addSide('GoalSideLine', tr('- The hunting grounds near your temple (Bestiary: where each creature lives).'), st.here)
  end
  if #st.upcoming > 0 then
    addSide('GoalSideTitle', tr('Next unlocks'))
    for _, r in ipairs(st.upcoming) do
      local w = addSide('GoalSideLine', '- ' .. V.upcomingLine(r))
      w:setColor('#8c8070')
    end
  end
end

local function drawGoals()
  window.goalList:destroyChildren()
  for _, r in ipairs(st.goals) do
    local row = g_ui.createWidget('GoalRow', window.goalList)
    local v = V.goalRow(r)
    row.title:setText(v.title)
    row.title:setColor(v.color)
    row.why:setText(v.why)
    row.effort:setText(v.effort ~= '' and tr('Effort: %s', v.effort) or '')
    row.reward:setText(v.reward)
    row.bar:setPercent(v.percent)
    row.bar:setText(v.label)
    row.bar:setBackgroundColor(v.state == 'done' and '#3f6e24' or '#8a5410')
    if v.button then
      row.goButton:setText(v.button)
      row.goButton:setVisible(true)
      local where = r.where
      row.goButton.onClick = function() runWhere(where) end
    end
  end
  local more = V.moreLine(st.header)
  if more ~= '' then
    local w = g_ui.createWidget('GoalSideLine', window.goalList)
    w:setText(more)
    w:setColor('#8c8070')
  end
end

function draw()
  if not window then return end
  local h = st.header
  window.bandLabel:setText(V.headerLine(h))
  window.bandText:setText(h and h.band and tostring(h.band.text or '') or '')
  window.bandBar:setPercent(V.bandPercent(h))
  window.bandBar:setText(h and h.band and tr('Band %d of %d', tonumber(h.band.index) or 1, tonumber(h.band.count) or 1) or '')
  window.summaryLabel:setText(V.summaryLine(h))
  window.journeyButton:setVisible(h ~= nil and h.season ~= nil)
  window.waitLabel:setVisible(h == nil)
  drawGoals()
  drawSide()
end

function openJourney()
  local season = modules.game_season
  if not season then return end
  -- the season window opens when the server answers its "open" (game_season season.lua toggle)
  pcall(season.toggle)
  scheduleEvent(function() pcall(season.showTab, 'journey') end, 600)
end

-- ---------------------------------------------------------------- the tracker
local function trackerEnabled()
  return g_settings.getBoolean(SETTING_TRACKER, true)
end

local function renderTracker()
  if not tracker then return end
  local shown = trackerEnabled() and #st.tracker > 0 and g_game.isOnline()
  tracker:setVisible(shown)
  if not shown then return end
  local folded = g_settings.getBoolean(SETTING_FOLDED, false)
  tracker.title:setText(folded and tr('Next Goals (%d) +', #st.tracker) or tr('Next Goals'))
  tracker.rows:destroyChildren()
  tracker.rows:setVisible(not folded)
  if folded then
    tracker.rows:setHeight(0)
    return
  end
  for _, r in ipairs(st.tracker) do
    local w = g_ui.createWidget('GoalTrackerRow', tracker.rows)
    local text, pct = V.trackerLine(r)
    w.label:setText(text)
    w.bar:setPercent(pct)
    w.onClick = function() show() end
  end
end

function setTrackerEnabled(on)
  g_settings.set(SETTING_TRACKER, on and true or false)
  if window and window.trackerBox:isChecked() ~= (on and true or false) then
    window.trackerBox:setChecked(on and true or false)
  end
  if on and #st.tracker == 0 and g_game.isOnline() then send('tracker') end
  renderTracker()
end

function toggleTracker()
  setTrackerEnabled(not trackerEnabled())
end

function foldTracker()
  g_settings.set(SETTING_FOLDED, not g_settings.getBoolean(SETTING_FOLDED, false))
  renderTracker()
end

-- ---------------------------------------------------------------- window visibility
function show()
  if not window or not g_game.isOnline() then return end
  window:show()
  window:raise()
  window:focus()
  draw()
  send('open')
end

function hide()
  if window and window:isVisible() then
    window:hide()
    if g_game.isOnline() then send('close') end
  end
end

function toggle()
  if not window then return end
  if window:isVisible() then hide() else show() end
end

-- ---------------------------------------------------------------- protocol
local function onMessage(msg)
  if type(msg) ~= 'table' then return end
  if msg.action == 'goals' then
    V.onGoals(st, msg.data)
    if window and window:isVisible() then draw() end
  elseif msg.action == 'tracker' then
    V.onTracker(st, msg.data)
    renderTracker()
  elseif msg.action == 'done' then
    status(V.doneText(msg.data))
  end
end

-- the panel comes through Chaos.sendChunked: "S" first part, "P" a middle part, "E" the last; a single message is plain JSON
local function onExtendedOpcode(protocol, opcode, data)
  if type(data) ~= 'string' or data == '' then return end
  local head = data:sub(1, 1)
  if head == 'S' then
    buffer = data:sub(2)
    return
  elseif head == 'P' then
    buffer = buffer .. data:sub(2)
    return
  elseif head == 'E' then
    data = buffer .. data:sub(2)
    buffer = ''
  end
  local ok, msg = pcall(json.decode, data)
  if ok then onMessage(msg) end
end

local function addMenu()
  if menuAdded then return end
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry then
    local ok1 = pcall(api.addEntry, 'adventure',
      { text = 'Next Goals', icon = 'quests', modules = { 'game_goals' }, fns = { 'toggle' } })
    pcall(api.addEntry, 'adventure',
      { text = 'Goal Tracker', icon = 'quests', modules = { 'game_goals' }, fns = { 'toggleTracker' } })
    menuAdded = ok1
  end
end

local function onGameStart()
  st = V.new()
  buffer = ''
  addMenu()
  renderTracker()
end

local function onGameEnd()
  if window then window:hide() end
  st = V.new()
  renderTracker()
end

function init()
  window = g_ui.displayUI('goals')
  window:hide()
  window.trackerBox:setChecked(trackerEnabled())

  -- the map panel runs under the side panels and the chat: anchor to what is really visible
  local root = modules.game_interface.getRootPanel()
  tracker = g_ui.loadUI('tracker', root)
  tracker:hide()
  if root:getChildById('gameLeftPanels') then
    tracker:addAnchor(AnchorLeft, 'gameLeftPanels', AnchorRight)
  else
    tracker:addAnchor(AnchorLeft, 'gameMapPanel', AnchorLeft)
  end
  tracker:addAnchor(AnchorVerticalCenter, 'gameMapPanel', AnchorVerticalCenter)
  tracker:setMarginLeft(10)

  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if window then
    window:destroy()
    window = nil
  end
  if tracker then
    tracker:destroy()
    tracker = nil
  end
end
