-- Bestiary and kill tasks window, and the task tracker HUD.
-- Server: server/data/scripts/chaos/bestiary.lua, extended opcode 253 (JSON {action, data}).
--   server -> client  summary {open, total, known, completed, percent, points, rank, cats, stages, tasks}
--                     list {first, last, rows = [[id, name, cat, diff, level, kills, stage, lookType]]}
--                     entry {id, name, stage, kills, th, next, ... what the stage reveals, task}
--                     kill {id, kills, stage, next}
--                     board {offers, tasks, active, maxActive, doneDay, dailyLimit, doneWeek, weeklyLimit, nextIn}
--                     tracker {rows = [{k = task|bounty, key, label, p, r}]}
--                     show {tab}
--   client -> server  open | list | summary | entry {id} | board | take {id} | accept {key} | abandon {key} | reroll | query
--   board.rerolls: kill task board rerolls held (bought with Candlemarks): the Reroll board button shows while above 0
-- The top menu (Hunt -> Bestiary / Task Tracker) calls toggle() and
-- toggleTracker().

local OPCODE = 253
local PAGE_SIZE = 60
local SETTING_TRACKER = 'chaos-bestiary-tracker'
local SETTING_FOLDED = 'chaos-bestiary-tracker-folded'
local V = BestiaryView

local window, tracker
local summary          -- last summary
local rows = {}        -- every list row (V.row)
local byId = {}
local listComplete = false
local listAsked = false
local listRetryEvent = nil   -- asks for the list again while it has not arrived complete (a lost packet stuck the window on "Loading")
local LIST_RETRY_MS = 4000
local LIST_RETRIES = 3
local selectedCat = V.ALL
local currentPage = 1
local selectedId
local detail           -- last entry data
local board, boardAt = nil, 0
local trackerRows = {}
local tab = 'bestiary'
local catButtons = {}
local rowWidgets = {}  -- id -> row widget on the page shown
local tickEvent

-- ---------------------------------------------------------------- helpers
local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

-- the rows of a server list (an entry that is no table is left out) and the plain values of one (strings and numbers);
-- a wrong shape cannot stop a window half drawn (game_chaosguard/opcode_fuzz_test.lua)
local function list(value)
  local out = {}
  if type(value) == 'table' then
    for _, v in ipairs(value) do
      if type(v) == 'table' then out[#out + 1] = v end
    end
  end
  return out
end

local function values(value)
  local out = {}
  if type(value) == 'table' then
    for _, v in ipairs(value) do
      if type(v) == 'string' or type(v) == 'number' then out[#out + 1] = v end
    end
  end
  return out
end

local function num(x) return tonumber(x) or 0 end

local function comma(n)
  if comma_value then return comma_value(num(n)) end
  return tostring(num(n))
end

local function catName(key)
  for _, c in ipairs(list(summary and summary.cats)) do
    if c.key == key then return c.name end
  end
  return tostring(key or '')
end

local function diffName(key)
  for _, d in ipairs(list(summary and summary.diffs)) do
    if d.key == key then return d.name end
  end
  return tostring(key or '')
end

-- ---------------------------------------------------------------- header and categories
local function updateHeader()
  if not window or not summary then return end
  local rank = type(summary.rank) == 'table' and summary.rank or {}
  window.summaryLabel:setText(tr('Known %d / %d   Completed %d (%s)   Points %d   Rank: %s', num(summary.known),
    num(summary.total), num(summary.completed), V.pctText(summary.percent), num(summary.points), tostring(rank.name or '')))
  local tip = tr('Bestiary points: %d from stages, %d from kill tasks.', num(summary.stagePoints), num(summary.taskPoints))
  if num(rank.exp) > 0 then
    tip = tip .. '\n' .. tr('Rank bonus: +%s experience from every monster.', V.pctText(rank.exp))
  end
  if rank.next then
    tip = tip .. '\n' .. tr('Next rank: %s at %d points.', tostring(rank.nextName), num(rank.next))
  end
  window.summaryLabel:setTooltip(tip)
end

local renderList

local function selectCategory(key)
  selectedCat = key
  currentPage = 1
  for k, b in pairs(catButtons) do b:setChecked(k == key) end
  renderList()
end

local function buildCategories()
  if not window or not summary then return end
  window.bestiaryPanel.categoryList:destroyChildren()
  catButtons = {}
  local all = g_ui.createWidget('BestiaryCategory', window.bestiaryPanel.categoryList)
  all:setText(tr('All (%d / %d)', num(summary.known), num(summary.total)))
  all.onClick = function() selectCategory(V.ALL) end
  catButtons[V.ALL] = all
  for _, c in ipairs(list(summary.cats)) do
    local b = g_ui.createWidget('BestiaryCategory', window.bestiaryPanel.categoryList)
    b:setText(string.format('%s (%d / %d)', tostring(c.name), num(c.known), num(c.total)))
    b:setTooltip(tr('%d discovered, %d completed of %d', num(c.known), num(c.completed), num(c.total)))
    local key = c.key
    b.onClick = function() selectCategory(key) end
    if key ~= nil then catButtons[key] = b end
  end
  if not catButtons[selectedCat] then selectedCat = V.ALL end
  for k, b in pairs(catButtons) do b:setChecked(k == selectedCat) end
end

-- ---------------------------------------------------------------- list
local function updateRowWidget(w, r)
  w.dot:setBackgroundColor(V.STAGE_COLORS[r.stage] or '#6b6258')
  w.dot:setTooltip(V.stageName(r.stage, summary and summary.stages))
  w.name:setText(r.name)
  w.name:setColor(r.stage >= 1 and '#d6c9ae' or '#6b6258')
  w.level:setText(tr('lv %d', r.level))
  w.kills:setText(r.kills > 0 and comma(r.kills) or '-')
  w:setTooltip(string.format('%s - %s, %s', r.name, catName(r.cat), diffName(r.diff)))
end

renderList = function()
  if not window then return end
  local panel = window.bestiaryPanel
  panel.entryList:destroyChildren()
  rowWidgets = {}
  if not listComplete then
    panel.emptyText:setText(tr('Loading the bestiary...'))
    panel.emptyText:setVisible(true)
    panel.pageLabel:setText('')
    return
  end
  local filtered = V.filter(rows, selectedCat, panel.searchEdit:getText(), panel.knownBox:isChecked())
  local part, page, pages = V.page(filtered, currentPage, PAGE_SIZE)
  currentPage = page
  for _, r in ipairs(part) do
    local w = g_ui.createWidget('BestiaryRow', panel.entryList)
    updateRowWidget(w, r)
    local id = r.id
    w.onClick = function() selectEntry(id) end
    rowWidgets[id] = w
    if id == selectedId then w:focus() end
  end
  panel.emptyText:setText(tr('No monster matches.'))
  panel.emptyText:setVisible(#part == 0)
  panel.pageLabel:setText(tr('Page %d / %d  (%d)', page, pages, #filtered))
  panel.prevButton:setEnabled(page > 1)
  panel.nextButton:setEnabled(page < pages)
end

-- ---------------------------------------------------------------- detail
local function addHeader(text)
  local l = g_ui.createWidget('BestiaryInfoHeader', window.bestiaryPanel.detailPanel.info)
  l:setText(text)
  return l
end

local function addLine(text, color)
  local l = g_ui.createWidget('BestiaryInfoLabel', window.bestiaryPanel.detailPanel.info)
  l:setText(text)
  if color then l:setColor(color) end
  return l
end

local function addItems(items, withChance)
  local grid = g_ui.createWidget('BestiaryLootGrid', window.bestiaryPanel.detailPanel.info)
  for _, it in ipairs(items) do
    local w = g_ui.createWidget('BestiaryLootItem', grid)
    w:setItemId(num(it.cid))
    local tip = tostring(it.name)
    if withChance then
      tip = tip .. ' - ' .. V.chanceText(it.chance)
      if num(it.max) > 1 then tip = tip .. tr(', up to %d', num(it.max)) end
    end
    if it.bossOnly then tip = tip .. tr(' (boss kills only)') end
    w:setTooltip(tip)
  end
end

local function renderDetail()
  if not window then return end
  local d = window.bestiaryPanel.detailPanel
  d.info:destroyChildren()
  if not detail then
    d.creature:setVisible(false)
    d.name:setText(tr('Select a monster'))
    d.stage:setText('')
    d.stageBar:setVisible(false)
    d.taskLabel:setText('')
    d.taskButton:setVisible(false)
    return
  end
  local e = detail
  local stage = num(e.stage)
  local stages = summary and summary.stages
  if stage >= 1 and type(e.outfit) == 'table' then
    d.creature:setOutfit(e.outfit)
    d.creature:setVisible(true)
  else
    d.creature:setVisible(false)
  end
  d.name:setText(e.name)
  d.stage:setText(string.format('%s - %s', V.stageName(stage, stages), V.killText(e.kills, e.next)))
  d.stage:setColor(V.STAGE_COLORS[stage] or '#d6c9ae')
  d.stageBar:setVisible(true)
  d.stageBar:setPercent(V.stagePercent(e.kills, values(e.th)))
  d.stageBar:setBackgroundColor(stage >= 4 and '#2f7a2a' or '#8a1010')
  local th = values(e.th)
  d.stageBar:setText(e.next and tr('Next: %s at %d', V.stageName(stage + 1, stages), num(e.next)) or tr('Completed'))
  d.stageBar:setTooltip(tr('Stages at %s kills', table.concat(th, ' / ')))

  addHeader(tr('%s - %s', catName(e.cat), tostring(e.diffName or diffName(e.diff))))
  if stage < 1 then
    addLine(tr('Not discovered yet: kill one to discover it.'), '#8c8070')
    addLine(tr('Hunting level about %d.', num(e.level)))
    if not e.spawns then addLine(tr('It does not live anywhere on the map.'), '#8c8070') end
  else
    if num(e.minLevel) > 0 then
      addLine(tr('Level %d-%d (scales with the area)', num(e.minLevel), num(e.maxLevel)))
    else
      addLine(tr('Hunting level about %d', num(e.level)))
    end
    addLine(tr('Health %s   Experience %s', comma(e.health), comma(e.exp)))
  end
  local pts = values(e.points)
  if #pts > 0 then
    addLine(tr('Bestiary points per stage: %s', table.concat(pts, ' / ')), '#8c8070')
  end

  if stage >= 2 then
    addHeader(tr('Damage taken'))
    local els = V.elementsText(e.elements)
    addLine(els ~= '' and els or tr('No strength or weakness.'))
    local imm = values(e.immunities)
    if #imm > 0 then addLine(tr('Immune to %s', table.concat(imm, ', '))) end
    addHeader(tr('Where it lives'))
    local areas = list(e.areas)
    if #areas == 0 then addLine(tr('Nowhere on the map.'), '#8c8070') end
    for _, a in ipairs(areas) do
      addLine(string.format('- %s', tostring(a.text)))
    end
  end
  local loot = list(e.loot)
  if stage >= 2 and #loot > 0 then
    addHeader(stage >= 3 and tr('Loot') or tr('Loot highlights (rarest)'))
    addItems(loot, true)
  elseif stage < 2 then
    addHeader(tr('More at stage 2'))
    addLine(tr('Elements, where it lives and the rarest loot unlock at %s.', V.stageName(2, stages)), '#8c8070')
  end
  local uniques = list(e.uniques)
  if #uniques > 0 then
    addHeader(tr('Chaos uniques it can drop'))
    addItems(uniques, false)
  end
  local bonus = type(e.bonus) == 'table' and e.bonus or {}
  addHeader(tr('Completion bonus'))
  addLine(tr('+%d%% damage and +%d%% experience against it', num(bonus.damage), num(bonus.exp)),
    stage >= 4 and '#7fd07f' or '#8c8070')
  if stage < 4 then addLine(tr('(active once the entry is completed)'), '#8c8070') end

  local t = type(e.task) == 'table' and e.task or {}
  d.taskButton:setVisible(true)
  if t.active then
    d.taskLabel:setText(tr('You hold a kill task for it.'))
    d.taskButton:setEnabled(false)
  elseif t.can then
    d.taskLabel:setText(tr('Task: %d kills. %s', num(t.required), V.rewardText(t.reward)))
    d.taskButton:setEnabled(true)
  else
    d.taskLabel:setText(tostring(t.text or ''))
    d.taskButton:setEnabled(false)
  end
  local id = e.id
  d.taskButton.onClick = function() send('take', { id = id }) end
end

function selectEntry(id)
  selectedId = id
  send('entry', { id = id })
end

-- ---------------------------------------------------------------- tasks tab
local function createTaskRow(parent, t, state)
  local row = g_ui.createWidget('BestiaryTaskRow', parent)
  local outfit = type(t.outfit) == 'table' and t.outfit or nil
  if outfit and num(outfit.type) > 0 then
    row.creature:setOutfit(outfit)
  else
    row.creature:setVisible(false)
  end
  row.kind:setText(V.KIND_TEXT[t.kind] or tostring(t.kind))
  row.kind:setColor(t.kind == 'family' and '#b070ff' or '#8c8070')
  row.name:setText(t.kind == 'family' and tr('%s family', tostring(t.label)) or tostring(t.label))
  row.task:setText(V.taskText(t))
  row.reward:setText(V.rewardShort(t.reward))
  row.reward:setTooltip(tr('Reward: %s (gold to your bank)', V.rewardText(t.reward)))
  local progress = num(t.progress)
  row.progress:setPercent(math.floor(progress * 100 / math.max(1, num(t.required))))
  row.progress:setText(string.format('%d / %d', progress, num(t.required)))
  row.progress:setVisible(state == 'active')
  local action = row.action
  if state == 'active' then
    action:setText(tr('Abandon'))
    action:setTooltip(tr('Drop this task (its progress is lost).'))
    action.onClick = function() send('abandon', { key = t.key }) end
  elseif state == 'open' then
    action:setText(tr('Accept'))
    action.onClick = function() send('accept', { key = t.key }) end
    local why = V.acceptBlock(board)
    action:setEnabled(why == nil)
    action:setTooltip(why or '')
  elseif state == 'done' then
    action:setText(tr('Done today'))
    action:setEnabled(false)
  else
    action:setText(tr('Taken'))
    action:setEnabled(false)
  end
  return row
end

local function renderBoard()
  if not window or not board then return end
  local p = window.tasksPanel
  p.limitsLabel:setText(V.limitsText(board))
  p.limitsLabel:setTooltip(tr('Tasks you hold, tasks completed today and this week (a task day starts at 06:00).'))
  local rerolls = num(board.rerolls)
  if p.rerollButton then
    p.rerollButton:setVisible(rerolls > 0)
    p.rerollButton:setText(tr('Reroll board (%d)', rerolls))
    p.rerollButton:setTooltip(tr("Draw today's offers again (tasks you hold stay)."))
    p.rerollButton.onClick = function() send('reroll') end
  end
  p.boardList:destroyChildren()
  local offers = list(board.offers)
  for _, o in ipairs(offers) do
    createTaskRow(p.boardList, o, o.state)
  end
  p.boardEmpty:setVisible(#offers == 0)
  p.activeList:destroyChildren()
  local tasks = list(board.tasks)
  for _, t in ipairs(tasks) do
    createTaskRow(p.activeList, t, 'active')
  end
  p.activeEmpty:setVisible(#tasks == 0)
end

local function tick()
  tickEvent = nil
  if not window or not board then return end
  local left = num(board.nextIn) - (g_clock.seconds() - boardAt)
  window.tasksPanel.timerLabel:setText(tr('New board in %s', V.clock(left)))
  if window:isVisible() then tickEvent = scheduleEvent(tick, 30000) end
end

-- ---------------------------------------------------------------- tabs
local function setTab(name)
  tab = name
  if not window then return end
  window.bestiaryPanel:setVisible(name == 'bestiary')
  window.tasksPanel:setVisible(name == 'tasks')
  window.tabs.bestiaryTab:setChecked(name == 'bestiary')
  window.tabs.tasksTab:setChecked(name == 'tasks')
  if name == 'tasks' then send('board') end
end

-- ---------------------------------------------------------------- tracker
local function trackerEnabled()
  return g_settings.getBoolean(SETTING_TRACKER, true)
end

local trackerOpened = false -- the menu turned it on this session: shown even without a task, with a hint

local function renderTracker()
  if not tracker then return end
  -- an empty tracker stays out of the way, unless the player just opened it from the menu (it looked as if it did not
  -- open: beta 2026-10-20)
  local show = trackerEnabled() and (#trackerRows > 0 or trackerOpened)
  tracker:setVisible(show)
  if not show then return end
  local folded = g_settings.getBoolean(SETTING_FOLDED, false)
  tracker.title:setText(folded and tr('Tasks (%d) +', #trackerRows) or tr('Tasks'))
  tracker.rows:destroyChildren()
  tracker.rows:setVisible(not folded)
  if folded then
    tracker.rows:setHeight(0)
    return
  end
  if #trackerRows == 0 then
    local w = g_ui.createWidget('BestiaryTrackerRow', tracker.rows)
    w.kind:setText('')
    w.label:setText(tr('No task yet: Hunt > Kill Tasks or Adventure > Bounty Board.'))
    w.label:setColor('#8c8070')
    w.bar:setVisible(false)
    return
  end
  for _, r in ipairs(trackerRows) do
    local w = g_ui.createWidget('BestiaryTrackerRow', tracker.rows)
    local text, pct, done = V.trackerLine(r)
    w.kind:setText(r.k == 'bounty' and 'B' or 'T')
    w.kind:setColor(r.k == 'bounty' and '#e03a1e' or '#e8b84a')
    w.label:setText(text)
    w.label:setColor(done and '#7fd07f' or '#e8dcc2')
    w.bar:setPercent(pct)
    w.bar:setBackgroundColor(r.k == 'bounty' and '#8a1010' or '#a3844b')
  end
end

function setTrackerEnabled(on)
  g_settings.set(SETTING_TRACKER, on and true or false)
  if window then window.trackerBox:setChecked(on and true or false) end
  renderTracker()
end

-- the menu entry: it opens the tracker (it is on by default, so the first click used to turn it off and nothing
-- showed); shown and opened, a second click hides it
function toggleTracker()
  local visible = tracker and tracker:isVisible()
  if visible then
    trackerOpened = false
    setTrackerEnabled(false)
    pcall(function() modules.game_textmessage.displayStatusMessage(tr('Task tracker off.')) end)
  else
    trackerOpened = true
    setTrackerEnabled(true)
  end
end

function foldTracker()
  g_settings.set(SETTING_FOLDED, not g_settings.getBoolean(SETTING_FOLDED, false))
  renderTracker()
end

-- ---------------------------------------------------------------- protocol
-- the list comes in chunks, one packet per server tick: when it is not complete after LIST_RETRY_MS the request is
-- sent again (the server answers with a fresh first chunk, which resets the rows), at most LIST_RETRIES times
function askListAgain(left)
  if listRetryEvent then removeEvent(listRetryEvent) end
  listRetryEvent = scheduleEvent(function()
    listRetryEvent = nil
    if listComplete or left <= 0 then return end
    send('list')
    askListAgain(left - 1)
  end, LIST_RETRY_MS)
end

local function onSummary(data)
  summary = data
  updateHeader()
  buildCategories()
  if data.open then
    show()
    if tab ~= 'bestiary' then setTab('bestiary') end
  end
  if (not listComplete or #rows ~= num(data.count)) and not listAsked then
    listAsked = true
    send('list')
    askListAgain(LIST_RETRIES)
  end
end

local function onList(data)
  if data.first then
    rows, byId, listComplete = {}, {}, false
  end
  for _, raw in ipairs(list(data.rows)) do
    local r = V.row(raw)
    rows[#rows + 1] = r
    byId[r.id] = r
  end
  if data.last then
    listComplete, listAsked = true, false
    renderList()
    if not selectedId then
      for _, r in ipairs(rows) do
        if r.stage >= 1 then selectEntry(r.id) break end
      end
    end
  end
end

local function onEntry(data)
  detail = data
  selectedId = data.id
  local r = byId[num(data.id)]
  if r then
    r.kills, r.stage = num(data.kills), num(data.stage)
    if rowWidgets[r.id] then updateRowWidget(rowWidgets[r.id], r) end
  end
  if window and not window:isVisible() then
    show()
    setTab('bestiary')
  end
  renderDetail()
end

local function onKill(data)
  local id = num(data.id)
  local r = byId[id]
  local stageChanged = false
  if r then
    stageChanged = r.stage ~= num(data.stage)
    r.kills, r.stage = num(data.kills), num(data.stage)
    if rowWidgets[id] then updateRowWidget(rowWidgets[id], r) end
  end
  if window and window:isVisible() then
    if detail and num(detail.id) == id then
      if stageChanged then
        send('entry', { id = id })
      else
        detail.kills, detail.next = num(data.kills), data.next
        local d = window.bestiaryPanel.detailPanel
        d.stage:setText(string.format('%s - %s', V.stageName(num(data.stage), summary and summary.stages),
          V.killText(data.kills, data.next)))
        d.stageBar:setPercent(V.stagePercent(data.kills, detail.th))
      end
    end
    if stageChanged then send('summary') end
  end
end

local function onBoard(data)
  board = data
  boardAt = g_clock.seconds()
  renderBoard()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  tick()
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[bestiary] invalid JSON: ' .. tostring(msg))
    return
  end
  local data = type(msg.data) == 'table' and msg.data or {}
  local a = msg.action
  if a == 'summary' then
    onSummary(data)
  elseif a == 'list' then
    onList(data)
  elseif a == 'entry' then
    onEntry(data)
  elseif a == 'kill' then
    onKill(data)
  elseif a == 'board' then
    onBoard(data)
  elseif a == 'tracker' then
    trackerRows = list(data.rows)
    renderTracker()
  elseif a == 'show' then
    show()
    setTab(data.tab == 'tasks' and 'tasks' or 'bestiary')
  end
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
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
    return
  end
  send('open') -- the server answers with the summary, which shows the window
end

function showTasks()
  send('board')
  show()
  setTab('tasks')
end

local function onGameStart()
  send('query') -- the tracker
end

local function onGameEnd()
  hide()
  if listRetryEvent then removeEvent(listRetryEvent) listRetryEvent = nil end
  summary, rows, byId, listComplete, listAsked = nil, {}, {}, false, false
  selectedId, detail, board, trackerRows = nil, nil, nil, {}
  renderTracker()
end

function init()
  window = g_ui.displayUI('bestiary')
  window:hide()
  local bestiaryTab = g_ui.createWidget('BestiaryTab', window.tabs)
  bestiaryTab:setId('bestiaryTab')
  bestiaryTab:setText(tr('Bestiary'))
  bestiaryTab.onClick = function() setTab('bestiary') end
  local tasksTab = g_ui.createWidget('BestiaryTab', window.tabs)
  tasksTab:setId('tasksTab')
  tasksTab:setText(tr('Kill Tasks'))
  tasksTab.onClick = function() setTab('tasks') end
  local panel = window.bestiaryPanel
  panel.searchEdit.onTextChange = function() currentPage = 1 renderList() end
  panel.knownBox.onCheckChange = function() currentPage = 1 renderList() end
  panel.prevButton.onClick = function() currentPage = currentPage - 1 renderList() end
  panel.nextButton.onClick = function() currentPage = currentPage + 1 renderList() end
  window.trackerBox:setChecked(trackerEnabled())
  setTab('bestiary')
  renderDetail()

  -- the map panel runs under the side panels and the chat: anchor to what is really visible
  local root = modules.game_interface.getRootPanel()
  tracker = g_ui.loadUI('tracker', root)
  tracker:hide()
  local right = root:getChildById('gameRightPanels')
  local bottom = root:getChildById('bottomSplitter')
  if right then
    tracker:addAnchor(AnchorRight, 'gameRightPanels', AnchorLeft)
  else
    tracker:addAnchor(AnchorRight, 'gameMapPanel', AnchorRight)
  end
  if bottom then
    tracker:addAnchor(AnchorBottom, 'bottomSplitter', AnchorTop)
  else
    tracker:addAnchor(AnchorBottom, 'gameMapPanel', AnchorBottom)
  end
  tracker:setMarginRight(10)
  tracker:setMarginBottom(10)

  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  if window then
    window:destroy()
    window = nil
  end
  if tracker then
    tracker:destroy()
    tracker = nil
  end
end
