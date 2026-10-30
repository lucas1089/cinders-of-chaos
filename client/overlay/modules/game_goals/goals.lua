-- Next Goals (server/data/scripts/chaos/goals.lua, extended opcode 178): the window with the goals of the character's
-- level band, the gear path and hunts of the band and the next unlocks, and a compact tracker on screen. The pure
-- parts: goalsview.lua (GoalsView, tested by goalsview_test.lua). Menu: Adventure > Next Goals and Adventure > Goal
-- Tracker (added with ChaosTopBar.addEntry). The "where" buttons open a window or put a mark on the minimap.
--   client -> server  open | close | tracker
--   server -> client  goals {...} (chunked) | tracker {rows} | ascension {rows} | spellquest {rows} | done {text}

local OPCODE = 178
local V = GoalsView
local SETTING_TRACKER = 'chaos_goals_tracker'
local SETTING_FOLDED = 'chaos_goals_tracker_folded'

local window, tracker
local scheduleAnchor
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
      local hw = modules.game_howitworks
      if hw and hw.hasGoal and hw.hasGoal(r.key) then -- game_howitworks: click for the card
        w:setColor('#9ab8ff')
        w:setTooltip(tr('Click: How it works'))
        w.onClick = function() hw.showForGoal(r.key) end
      end
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
    pcall(function() modules.game_howitworks.attachGoal(row, r.key) end) -- game_howitworks: the ? button
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

-- the tracker's text area is 208 px wide (220 - padding): about 28 characters of verdana 11 per line, 14 px a line.
-- Phone: 150 px wide, verdana 9, 3 rows at most and a "+N more" line, header click folds it, header drag moves it.
local TRACKER_DESKTOP = { chars = 28, line = 14, width = 220, rowGap = 12, font = 'verdana-11px-antialised', title = 'verdana-11px-rounded', titleH = 16, maxRows = nil }
local TRACKER_PHONE = { chars = 24, line = 11, width = 150, rowGap = 8, font = 'verdana-9px', title = 'verdana-9px-rounded', titleH = 20, maxRows = 3 }

local function isPhone()
  local ok, m = pcall(function() return g_app.isMobile() end)
  return ok and m and true or false
end

local function trackerLook()
  return isPhone() and TRACKER_PHONE or TRACKER_DESKTOP
end

local function addTrackerRow(parent, text, look, color, pct)
  local w = g_ui.createWidget('GoalTrackerRow', parent)
  local wrapped, lines = V.wrapLine(text, look.chars)
  w.label:setFont(look.font)
  w.label:setText(wrapped)
  if color then w.label:setColor(color) end
  w.label:setHeight(lines * look.line)
  w:setHeight(lines * look.line + look.rowGap)
  w.bar:setPercent(pct)
  w.bar:setBackgroundColor(pct >= 100 and '#3f6e24' or '#a3844b')
  if isPhone() then w.bar:setHeight(4) end
  w.onClick = function() show() end
  return w
end

local function renderTracker()
  if not tracker then return end
  local shown = trackerEnabled() and (#st.tracker > 0 or #st.ascension > 0 or #st.spellquest > 0) and g_game.isOnline()
  tracker:setVisible(shown)
  if not shown then return end
  local look = trackerLook()
  tracker:setWidth(look.width)
  tracker.title:setFont(look.title)
  tracker.title:setHeight(look.titleH)
  tracker.ascTitle:setFont(look.title)
  tracker.sqTitle:setFont(look.title)
  local folded = g_settings.getBoolean(SETTING_FOLDED, false)
  local hasGoals, hasAsc, hasSq = #st.tracker > 0, #st.ascension > 0, #st.spellquest > 0
  if hasGoals then
    tracker.title:setText(folded and tr('Next Goals (%d) +', #st.tracker) or tr('Next Goals'))
  elseif hasAsc then
    tracker.title:setText(folded and tr('Ascension (%d) +', #st.ascension) or tr('Ascension'))
  else
    tracker.title:setText(folded and tr('Spell Quest (%d) +', #st.spellquest) or tr('Spell Quest'))
  end
  tracker.rows:destroyChildren()
  tracker.ascRows:destroyChildren()
  tracker.sqRows:destroyChildren()
  if tracker.moreLine then tracker.moreLine:destroy() tracker.moreLine = nil end
  local take, hidden = V.budget({ #st.tracker, #st.ascension, #st.spellquest }, look.maxRows)
  tracker.rows:setVisible(not folded)
  tracker.ascTitle:setVisible(hasAsc and hasGoals and not folded and take[2] > 0)
  tracker.ascRows:setVisible(not folded)
  tracker.sqTitle:setVisible(hasSq and (hasGoals or hasAsc) and not folded and take[3] > 0)
  tracker.sqRows:setVisible(not folded)
  if folded then
    tracker.rows:setHeight(0)
    tracker.ascRows:setHeight(0)
    tracker.sqRows:setHeight(0)
    scheduleAnchor()
    return
  end
  for i, r in ipairs(st.spellquest) do
    if i <= take[3] then
      local text, pct, color = V.ascensionLine(r)
      addTrackerRow(tracker.sqRows, text, look, color, pct)
    end
  end
  for i, r in ipairs(st.ascension) do
    if i <= take[2] then
      local text, pct, color = V.ascensionLine(r)
      addTrackerRow(tracker.ascRows, text, look, color, pct)
    end
  end
  for i, r in ipairs(st.tracker) do
    if i <= take[1] then
      local text, pct = V.trackerLine(r)
      addTrackerRow(tracker.rows, text, look, nil, pct)
    end
  end
  if hidden > 0 then
    local l = g_ui.createWidget('UILabel', tracker)
    l:setFont(look.font)
    l:setColor('#8c8070')
    l:setHeight(look.line + 2)
    l:setText(V.hiddenLine(hidden))
    l.onClick = function() show() end
    l:setPhantom(false)
    tracker.moreLine = l
  end
  scheduleAnchor()
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
  elseif msg.action == 'ascension' then
    V.onAscension(st, msg.data)
    renderTracker()
  elseif msg.action == 'spellquest' then
    V.onSpellQuest(st, msg.data)
    renderTracker()
  elseif msg.action == 'done' then
    status(V.doneText(msg.data))
    local cs = modules.game_chaossound -- O238: the goal sound
    if cs and cs.onGoalDone then pcall(cs.onGoalDone) end
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
  scheduleAnchor() -- the dragged place is per character
end

local function onGameEnd()
  if window then window:hide() end
  st = V.new()
  renderTracker()
end

local EDGES = { left = AnchorLeft, right = AnchorRight, top = AnchorTop, verticalCenter = AnchorVerticalCenter }
local anchorEvent

local SETTING_POS = 'chaosGoalsTracker' -- g_settings node {[character name] = {x, y}}: where the player dragged the tracker
local dragOffset, dragStart, dragMoved

local function charName()
  local ok, p = pcall(function() return g_game.getLocalPlayer() end)
  local name = ok and p and p:getName() or ''
  return name
end

local function savedPos()
  local ok, node = pcall(g_settings.getNode, SETTING_POS)
  return V.savedPosition(ok and node or nil, charName())
end

local function savePos(x, y)
  local ok, node = pcall(g_settings.getNode, SETTING_POS)
  node = (ok and type(node) == 'table') and node or {}
  node[charName()] = { x = x, y = y }
  pcall(g_settings.setNode, SETTING_POS, node)
  pcall(g_settings.save)
end

local function setPos(root, x, y)
  tracker:breakAnchors()
  tracker:addAnchor(AnchorTop, 'parent', AnchorTop)
  tracker:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  x, y = V.clampPosition(x, y, tracker:getWidth(), tracker:getHeight(), root:getWidth(), root:getHeight())
  tracker:setMarginLeft(x)
  tracker:setMarginTop(y)
  return x, y
end

-- The tracker sits at the left edge of the map, half way down until the player drags it. Anchors are dropped and set
-- again, so after the side panels changed (Options > Interface > Show Left Horizontal Panel adds a left panel, hiding
-- it leaves one) an undragged tracker is back at its corner. A dragged place is kept per character (top left corner in
-- the root panel) and clamped inside the screen.
local function anchorTracker()
  if not tracker or tracker:isDestroyed() or dragOffset then return end
  local root = modules.game_interface.getRootPanel()
  if not root then return end
  local x, y = savedPos()
  if x then
    setPos(root, x, y)
    return
  end
  tracker:breakAnchors()
  for _, a in ipairs(V.trackerAnchors(root:getChildById('gameLeftPanels') ~= nil)) do
    tracker:addAnchor(EDGES[a[1]], a[2], EDGES[a[3]])
  end
  tracker:setMarginLeft(10)
  tracker:setMarginTop(0)
end

-- called on every geometry change of the panels it hangs on, one pass per frame at most
function scheduleAnchor()
  if anchorEvent then return end
  anchorEvent = addEvent(function()
    anchorEvent = nil
    anchorTracker()
  end)
end

local function watchGeometry(connectIt)
  local root = modules.game_interface.getRootPanel()
  for _, id in ipairs({ 'gameLeftPanels', 'gameMapPanel', 'horizontalLeftPanel' }) do
    local w = root and root:recursiveGetChildById(id)
    if w then
      if connectIt then
        if w.insertLuaCall then w:insertLuaCall('onGeometryChange') end
        connect(w, { onGeometryChange = scheduleAnchor })
      else
        disconnect(w, { onGeometryChange = scheduleAnchor })
      end
    end
  end
end

-- the title is the handle: a click folds, a drag moves (the position is saved per character)
local function onTitlePress(w, pos, button)
  if button ~= MouseLeftButton then return false end
  dragStart = { x = pos.x, y = pos.y }
  dragOffset = { x = pos.x - tracker:getX(), y = pos.y - tracker:getY() }
  dragMoved = false
  w:grabMouse()
  return true
end

local function onTitleMove(w, pos)
  if not dragOffset then return false end
  if not dragMoved and not V.isDrag(pos.x - dragStart.x, pos.y - dragStart.y) then return true end
  dragMoved = true
  local root = tracker:getParent()
  local keep = dragOffset
  dragOffset = nil -- setPos re-anchors; the guard is for anchorTracker only
  setPos(root, pos.x - keep.x - root:getX(), pos.y - keep.y - root:getY())
  dragOffset = keep
  return true
end

local function onTitleRelease(w)
  if not dragOffset then return false end
  w:ungrabMouse()
  local moved = dragMoved
  dragOffset, dragStart, dragMoved = nil, nil, false
  if moved then
    local root = tracker:getParent()
    savePos(tracker:getX() - root:getX(), tracker:getY() - root:getY())
    scheduleAnchor()
  else
    foldTracker()
  end
  return true
end

function init()
  window = g_ui.displayUI('goals')
  pcall(function() modules.game_howitworks.attach(window, 'goals') end) -- game_howitworks: the ? button
  window:hide()
  window.trackerBox:setChecked(trackerEnabled())

  -- the map panel runs under the side panels and the chat: anchor to what is really visible
  local root = modules.game_interface.getRootPanel()
  tracker = g_ui.loadUI('tracker', root)
  tracker:hide()
  tracker.title.onMousePress = onTitlePress
  tracker.title.onMouseMove = onTitleMove
  tracker.title.onMouseRelease = onTitleRelease
  anchorTracker()
  watchGeometry(true)

  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  if anchorEvent then removeEvent(anchorEvent); anchorEvent = nil end
  pcall(watchGeometry, false)
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
