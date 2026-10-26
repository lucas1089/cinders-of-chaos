-- Leaderboards window: weekly boards (World Boss, Bounty Hunter, Rifts) with last week's title holders, the all-time
-- class ladder, the player's own rank and the time to the weekly reset.
-- Server: server/data/scripts/chaos/leaderboard.lua, extended opcode 229 (JSON {action, data}).
--   server -> client  meta {open, boards = [{key, name, weekly, value, count, title, info, byClass, format}], groups = [{key, name}], ownGroup}
--                     (byClass: class tabs on a weekly board, "All classes" first; format "time": values in seconds, shown m:ss)
--                     board {key, group, week, resetIn, rows = [{rank, name, value, count, level, vocation, title}],
--                            own = {rank, value, count} | nil, champions = [{rank, rankName, name, value, title}], total}
--   client -> server  open | get {board, group}
-- Records view (server records.lua, the same opcode; recordsview.lua holds the pure parts):
--   server -> client  rcat {cat, boards} (parts of the meta), rmeta {categories, periods, groups, parts, season, badge},
--                     rboard {board, variant, size, period, group, rows, own, total, record, resetIn, seasonName},
--                     rfirsts {season, seasonName, rows = [{target, board, name, members, at, value, format}]}
--                     rmine {rows = [{key, name, value}]}   the own personal records (O260), the tab "My Records"
--   client -> server  rmeta | rget {board, variant, size, period, group} | rfirsts | rmine
-- The top menu (Social > Leaderboards) calls toggle().
-- The weekly boards are a dropdown sorted by the name shown (boardpick.lua); the board chosen is kept per character in
-- g_settings (node BoardPick.SETTINGS) and asked for when the window opens (World Boss when none is kept).

local OPCODE = 229
local RANK_COLOR = { '#e8b84a', '#a8b4c8', '#c87a3a' }

local window
local meta             -- last meta received
local current          -- last board received
local boardAt = 0      -- g_clock.seconds() when it arrived
local selected         -- board key shown
local selectedGroup    -- class group shown on the ladder
local classGroup       -- class tab of the boards with class tabs (byClass); nil = every class
local tabs, groupTabs = {}, {} -- tabs: the Records view's category tabs
local boardOptions = {}        -- the dropdown's options (BoardPick.options)
local comboFilling = false     -- true while the dropdown is set from code (no request, nothing saved)
local COMBO_GAP = 8
local tickEvent
local refreshAsked = false
local seasonView = false -- the Season toggle (server season.lua): only the running season's characters
local seasonMode = 'all' -- its mode tab (server season_modes.lua): all | standard | ssf | hc | hcssf | fallen
local modeTabs = {}
-- Records view
local recordsMode = false
local rparts            -- meta parts received (RecordsView.addPart)
local rmeta             -- the joined meta (RecordsView.finish)
local rcat              -- category shown
local rboard            -- board key shown
local rsel = {}         -- filters: period, variant, size, group
local rcurrent          -- last rboard / rfirsts received
local rAt = 0

-- ---------------------------------------------------------------- helpers
local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if action == 'get' and seasonView then
    data = data or {}
    data.season = true
    if seasonMode ~= 'all' then data.mode = seasonMode end
  end
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

-- the rows of a server list; an entry that is no table is left out (game_chaosguard/opcode_fuzz_test.lua)
local function rowsOf(value)
  local out = {}
  if type(value) == 'table' then
    for _, v in ipairs(value) do
      if type(v) == 'table' then out[#out + 1] = v end
    end
  end
  return out
end

local function short(n)
  n = tonumber(n) or 0
  if formatShortNumber then return formatShortNumber(n) end
  return tostring(n)
end

local function exact(n)
  n = tonumber(n) or 0
  return comma_value and comma_value(n) or tostring(n)
end

local function formatTime(seconds)
  seconds = math.max(0, math.floor(seconds))
  local d = math.floor(seconds / 86400)
  local h = math.floor((seconds % 86400) / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if d > 0 then return string.format('%dd %02dh %02dm', d, h, m) end
  return string.format('%dh %02dm %02ds', h, m, s)
end

-- a board value as shown: m:ss for the time boards, else short (or exact) numbers
local function valueText(v, b, exactly)
  local t = TabRows and TabRows.valueText and TabRows.valueText(v, b and b.format)
  if t then return t end
  return exactly and exact(v) or short(v)
end

local function boardMeta(key)
  for _, b in ipairs(rowsOf(meta and meta.boards)) do
    if b.key == key then return b end
  end
  return nil
end

-- the group to ask for with the board shown: the class tab of a byClass board, else the ladder's class
local function currentGroup()
  local b = selected and boardMeta(selected)
  if b and b.weekly and b.byClass then return classGroup end
  return selectedGroup
end

local function groupName(key)
  for _, g in ipairs(rowsOf(meta and meta.groups)) do
    if g.key == key then return g.name end
  end
  return '?'
end

local function ordinal(n)
  local s = ({ 'st', 'nd', 'rd' })[n] or 'th'
  return tostring(n) .. s
end

-- ---------------------------------------------------------------- the board kept per character
local function characterName()
  local ok, name = pcall(function() return g_game.getCharacterName() end)
  return ok and name or nil
end

local function settingsNode()
  local ok, node = pcall(g_settings.getNode, BoardPick.SETTINGS)
  return (ok and type(node) == 'table') and node or {}
end

local function savedBoard()
  return BoardPick.saved(settingsNode(), characterName())
end

local function rememberBoard(key)
  local name = characterName()
  if not name or key == nil then return end
  pcall(g_settings.setNode, BoardPick.SETTINGS, BoardPick.remember(settingsNode(), name, key))
end

-- ---------------------------------------------------------------- rows
local function createRow(r, b, ownName)
  local row = g_ui.createWidget('LeaderboardRow', window.rowList)
  local rank = tonumber(r.rank) or 0
  row.rank:setText('#' .. rank)
  if RANK_COLOR[rank] then row.rank:setColor(RANK_COLOR[rank]) end
  row.name:setText(r.name or '?')
  if r.title then
    row.title:setText(r.title)
  else
    row.title:setText('')
  end
  -- a fallen Hardcore character: the skull, the fall in the tooltip
  local fallen = type(r.fallen) == 'table' and r.fallen or nil
  row.fallen:setVisible(fallen ~= nil)
  row.fallen:setWidth(fallen and 14 or 0)
  row.fallen:setMarginLeft(fallen and 4 or 0)
  if fallen then
    local tip = tr('Fallen in Hardcore at level %d (%s).', tonumber(fallen.level) or 0, tostring(fallen.cause or ''))
    row.fallen:setTooltip(tip)
    row:setTooltip(tip)
    row.name:setColor('#a09080')
  end
  if b.weekly then
    row.value:setText(valueText(r.value, b))
    row.value:setTooltip(valueText(r.value, b, true) .. ' ' .. (b.value or ''):lower())
    row.extra:setText(b.count and exact(r.count) or '')
  else
    row.value:setText(tostring(r.level or r.value or 0))
    row.value:setTooltip('')
    row.extra:setText(r.vocation or '')
  end
  if ownName and r.name == ownName then
    row:setBackgroundColor('#3a2410')
    row.name:setColor('#f6cf72')
  elseif rank % 2 == 0 then
    row:setBackgroundColor('#141014')
  end
  return row
end

local function updateTimer()
  if not window then return end
  if recordsMode then
    local left = rcurrent and tonumber(rcurrent.resetIn)
    window.timerLabel:setText(left and tr('Weekly reset in %s', formatTime(left - (g_clock.seconds() - rAt))) or '')
    return
  end
  if not current then return end
  local left = (tonumber(current.resetIn) or 0) - (g_clock.seconds() - boardAt)
  window.timerLabel:setText(tr('Weekly reset in %s', formatTime(left)))
  window.timerLabel:setTooltip(tr('The weekly boards reset every Monday at 06:00 server time.'))
  if left <= 0 and not refreshAsked and window:isVisible() then
    refreshAsked = true
    scheduleEvent(function() send('get', { board = selected, group = currentGroup() }) end, 5000)
  end
end

local function tick()
  tickEvent = nil
  if not window then return end
  updateTimer()
  tickEvent = scheduleEvent(tick, 1000)
end

local function showBoard()
  if not window or not current then return end
  local b = boardMeta(current.key) or { key = current.key, name = current.key, weekly = true }
  window.rowList:destroyChildren()
  local player = g_game.getLocalPlayer()
  local ownName = player and player:getName() or nil
  local rows = rowsOf(current.rows)
  for _, r in ipairs(rows) do createRow(r, b, ownName) end

  window.infoLabel:setText(b.info or '')
  window.header.value:setText(b.value or tr('Value'))
  window.header.extra:setText(b.weekly and (b.count or '') or tr('Class'))

  -- last week's title holders (weekly boards) / the class shown (ladder)
  if b.weekly then
    local champions = rowsOf(current.champions)
    window.championPanel.championTitle:setText(tr('%s: the title holders this week (last week\'s top 3)', b.title or ''))
    if #champions == 0 then
      window.championPanel.championNames:setText(tr('Nobody yet: the top 3 of this week get the title on Monday.'))
      window.championPanel.championNames:setTooltip('')
    else
      local parts, exacts = {}, {}
      for _, c in ipairs(champions) do
        local place = c.rankName or ordinal(tonumber(c.rank) or 0)
        parts[#parts + 1] = place .. ' ' .. (c.name or '?')
        exacts[#exacts + 1] = string.format('%s %s: %s %s', place, c.name or '?', valueText(c.value, b, true), (b.value or ''):lower())
      end
      window.championPanel.championNames:setText(table.concat(parts, '    '))
      window.championPanel.championNames:setTooltip(table.concat(exacts, '\n'))
    end
  else
    window.championPanel.championNames:setTooltip('')
    window.championPanel.championTitle:setText(tr('%s: highest level, all time', groupName(current.group)))
    window.championPanel.championNames:setText(tr('Every class of the %s line counts. Updated every few minutes.', groupName(current.group)))
  end

  local season = type(current.season) == 'table' and current.season or nil
  if season then
    window.championPanel.championNames:setTooltip('')
    window.championPanel.championTitle:setText(season.modeName and tr('%s %s: %s', season.name or '', season.tag or '', season.modeName)
      or tr('%s %s: season characters only', season.name or '', season.tag or ''))
    window.championPanel.championNames:setText(b.weekly and tr('This week\'s scores of the season\'s characters. Titles are won on the normal boards.')
      or tr('Highest level of the season\'s characters in the %s line.', groupName(current.group)))
    if season.mode == 'fallen' then
      window.championPanel.championNames:setText(tr('Hardcore characters that died, highest level first, with what killed them.'))
    end
  end

  window.emptyText:setText(b.weekly and tr('No scores on this board yet this week.') or tr('No characters of this class yet.'))
  window.emptyText:setVisible(#rows == 0)

  local own = type(current.own) == 'table' and current.own or nil
  if own then
    local text
    if b.weekly then
      text = tr('Your rank: #%d of %d   -   %s: %s', tonumber(own.rank) or 0, tonumber(current.total) or 0,
        b.value or tr('Score'), valueText(own.value, b, true))
      if b.count then text = text .. string.format('   -   %s: %s', b.count, exact(own.count)) end
    else
      text = tr('Your rank in the %s line: #%d   -   level %d', groupName(current.group), tonumber(own.rank) or 0,
        tonumber(own.value) or 0)
    end
    window.ownPanel.ownLabel:setText(text)
  else
    local tab = type(current.season) == 'table' and current.season.mode or nil
    window.ownPanel.ownLabel:setText(tab and tr('This character is not on this tab.')
      or (b.weekly and tr('You have no score on this board this week.') or tr('Your class is not on this ladder.')))
  end

  if b.weekly then
    window.hintLabel:setText(tr('Top 3 on Monday: the title %s for a week, orbs to the inbox.', b.title or ''))
  else
    window.hintLabel:setText(tr('Levels are read from the saved characters.'))
  end
  updateTimer()
end

-- the tabs of `items` ({text, tooltip, onClick, checked}) in rows inside container (tabrows.lua), each as wide as its
-- label in the tab's font; returns the tab widgets in order and sets the container's height
local TAB_GAP, ROW_GAP = 4, 3

local function buildTabRows(container, style, items, maxWidth)
  container:destroyChildren()
  local avail = container:getWidth()
  if avail <= 0 then avail = window:getWidth() - window:getPaddingLeft() - window:getPaddingRight() end
  local probe = g_ui.createWidget(style, container)
  local rowHeight = probe:getHeight()
  local pad = probe:getPaddingLeft() + probe:getPaddingRight() + 8
  local widths = {}
  for i, item in ipairs(items) do
    probe:setText(item.text)
    widths[i] = probe:getTextSize().width + pad
  end
  probe:destroy()
  local out = {}
  local rows = TabRows.layout(widths, avail, TAB_GAP, maxWidth)
  for _, cells in ipairs(rows) do
    local row = g_ui.createWidget('LeaderboardTabRow', container)
    row:setHeight(rowHeight)
    for k, cell in ipairs(cells) do
      local item = items[cell.index]
      local tab = g_ui.createWidget(style, row)
      tab:setWidth(cell.width)
      tab:setHeight(rowHeight)
      tab:setMarginRight(k < #cells and TAB_GAP or 0)
      tab:setText(item.text)
      if item.tooltip then tab:setTooltip(item.tooltip) end
      tab:setChecked(item.checked and true or false)
      tab.onClick = item.onClick
      out[cell.index] = tab
    end
  end
  container:setHeight(math.max(1, #rows) * rowHeight + math.max(0, #rows - 1) * ROW_GAP)
  return out
end

local function buildGroupTabs()
  window.groupTabs:destroyChildren()
  groupTabs = {}
  local ladder = selected and boardMeta(selected)
  local byClass = ladder and ladder.weekly and ladder.byClass
  local visible = ladder and (not ladder.weekly or byClass)
  window.groupTabs:setVisible(visible and true or false)
  window.groupTabs:setHeight(visible and 22 or 0)
  window.groupTabs:setMarginTop(visible and 4 or 0)
  if not visible then return end
  local groups, items = rowsOf(meta.groups), {}
  if byClass then
    -- a weekly board with class tabs: "All classes" first (key 'all' = no filter)
    table.insert(groups, 1, { key = 'all', name = tr('All classes') })
  end
  for i, g in ipairs(groups) do
    local key = g.key
    local checked = byClass and (key == (classGroup or 'all')) or (not byClass and key == selectedGroup)
    items[i] = { text = g.name or '?', checked = checked, onClick = function()
      if byClass then
        classGroup = key ~= 'all' and key or nil
      else
        selectedGroup = key
      end
      for k, t in pairs(groupTabs) do t:setChecked(k == key) end
      send('get', { board = selected, group = byClass and classGroup or key })
    end }
  end
  for i, tab in pairs(buildTabRows(window.groupTabs, 'LeaderboardGroupTab', items, 124)) do
    groupTabs[groups[i].key] = tab
  end
end

-- the mode tabs of the Season view (meta.season.modes), shown while the Season toggle is on
local function buildModeTabs()
  window.modeTabs:destroyChildren()
  modeTabs = {}
  local season = meta and type(meta.season) == 'table' and meta.season or nil
  local modes = season and list(season.modes) or {}
  local visible = seasonView and #modes > 0
  window.modeTabs:setVisible(visible)
  window.modeTabs:setHeight(visible and 20 or 0)
  window.modeTabs:setMarginTop(visible and 4 or 0)
  if not visible then return end
  local items = {}
  for i, m in ipairs(modes) do
    local key = m.key
    items[i] = { text = tostring(m.name or key), checked = key == seasonMode, onClick = function()
      seasonMode = key
      for k, t in pairs(modeTabs) do t:setChecked(k == key) end
      send('get', { board = selected, group = currentGroup() })
    end }
  end
  for i, tab in pairs(buildTabRows(window.modeTabs, 'LeaderboardModeTab', items, 124)) do
    modeTabs[modes[i].key] = tab
  end
end

-- the dropdown shows key (no onOptionChange), its tooltip the board's description
local function syncCombo(key)
  if not window or key == nil then return end
  local combo = window.boardCombo
  local b = boardMeta(key)
  comboFilling = true
  pcall(function() combo:setCurrentOptionByData(key, true) end)
  comboFilling = false
  combo:setTooltip(b and (b.weekly and tr('Weekly: %s', b.info or '') or (b.info or '')) or '')
end

-- the weekly boards (dropdown) or the Records view (category tabs) on the top rows
local function setView(records)
  window.boardCombo:setVisible(not records)
  window.infoLabel:setMarginLeft(records and 0 or (window.boardCombo:getWidth() + COMBO_GAP))
  window.tabs:setVisible(records)
  if not records then
    window.tabs:destroyChildren()
    window.tabs:setHeight(0)
    tabs = {}
  end
end

local function selectBoard(key)
  selected = key
  syncCombo(key)
  local b = boardMeta(key)
  if b and not b.weekly and not selectedGroup then selectedGroup = meta.ownGroup end
  buildGroupTabs()
  send('get', { board = key, group = (b and b.weekly and b.byClass) and classGroup or selectedGroup })
end

-- the weekly boards in the dropdown, sorted by the name shown (tr: the pt-BR names sort in pt-BR)
local function buildBoardCombo()
  local combo = window.boardCombo
  boardOptions = BoardPick.options(rowsOf(meta and meta.boards), function(name) return tr(name) end)
  comboFilling = true
  combo:clearOptions()
  for _, o in ipairs(boardOptions) do combo:addOption(o.text, o.key) end
  comboFilling = false
  syncCombo(BoardPick.resolve(boardOptions, selected or savedBoard()))
end

-- a board chosen in the dropdown: kept for this character, then asked for
local function onBoardChosen(_, _, key)
  if comboFilling or recordsMode or not meta or key == nil then return end
  rememberBoard(key)
  if key ~= selected then selectBoard(key) end
end

-- ---------------------------------------------------------------- Records view
local function rBoardMeta()
  return rmeta and rboard and RecordsView.board(rmeta, rboard) or nil
end

local function requestRecord()
  if rcat == 'firsts' then
    send('rfirsts', {})
    return
  end
  if rcat == 'mine' then
    send('rmine', {})
    return
  end
  local b = rBoardMeta()
  if not b then return end
  rsel = RecordsView.normalize(b, rsel, rmeta.periods)
  send('rget', RecordsView.request(b, rsel))
end

local function createRecordRow(rank, name, title, value, extra, tooltip, ownName)
  local row = g_ui.createWidget('LeaderboardRow', window.rowList)
  row.rank:setText('#' .. rank)
  if RANK_COLOR[rank] then row.rank:setColor(RANK_COLOR[rank]) end
  row.name:setText(name or '?')
  row.title:setText(title or '')
  row.fallen:setVisible(false)
  row.fallen:setWidth(0)
  row.fallen:setMarginLeft(0)
  row.value:setText(value or '')
  row.value:setTooltip('')
  row.extra:setText(extra or '')
  if tooltip then row:setTooltip(tooltip) end
  if ownName and name == ownName then
    row:setBackgroundColor('#3a2410')
    row.name:setColor('#f6cf72')
  elseif rank % 2 == 0 then
    row:setBackgroundColor('#141014')
  end
  return row
end

-- the filter rows of the board shown: period, then its variants, sizes and the class tabs
local function buildRecordFilters()
  window.recordFilters:destroyChildren()
  local b = rBoardMeta()
  local visible = recordsMode and b ~= nil and rcat ~= 'firsts' and rcat ~= 'mine'
  window.recordFilters:setVisible(visible)
  if not visible then
    window.recordFilters:setHeight(0)
    window.recordFilters:setMarginTop(0)
    return
  end
  rsel = RecordsView.normalize(b, rsel, rmeta.periods)
  local function row(list, field, tip)
    local box = g_ui.createWidget('LeaderboardFilterBox', window.recordFilters)
    local items = {}
    for i, x in ipairs(list) do
      local key = x.key
      items[i] = { text = tostring(x.name or key), tooltip = tip, checked = rsel[field] == key, onClick = function()
        rsel[field] = key
        buildRecordFilters()
        requestRecord()
      end }
    end
    buildTabRows(box, 'LeaderboardModeTab', items, 150)
    return box:getHeight()
  end
  local h = row(rmeta.periods, 'period', tr('This week resets on Monday 06:00; the season and all time stay.'))
  if #(b.variants or {}) > 0 then h = h + 3 + row(b.variants, 'variant') end
  if #(b.sizes or {}) > 0 then h = h + 3 + row(b.sizes, 'size', tr('Party size of the run.')) end
  if b.byClass then
    local groups = { { key = false, name = tr('All classes') } }
    for _, g in ipairs(rmeta.groups) do groups[#groups + 1] = g end
    local box = g_ui.createWidget('LeaderboardFilterBox', window.recordFilters)
    local items = {}
    for i, g in ipairs(groups) do
      local key = g.key or nil
      items[i] = { text = tostring(g.name), checked = rsel.group == key, onClick = function()
        rsel.group = key
        buildRecordFilters()
        requestRecord()
      end }
    end
    buildTabRows(box, 'LeaderboardModeTab', items, 124)
    h = h + 3 + box:getHeight()
  end
  window.recordFilters:setHeight(h)
  window.recordFilters:setMarginTop(4)
end

local function selectRecordBoard(key)
  rboard = key
  for k, t in pairs(groupTabs) do t:setChecked(k == key) end
  buildRecordFilters()
  requestRecord()
end

local function selectRecordCategory(key)
  rcat = key
  for k, t in pairs(tabs) do t:setChecked(k == key) end
  -- the boards of the category as the second tab row
  window.groupTabs:destroyChildren()
  groupTabs = {}
  local c = RecordsView.category(rmeta, key)
  local boards = c and c.boards or {}
  local visible = #boards > 1
  window.groupTabs:setVisible(visible)
  window.groupTabs:setHeight(visible and 22 or 0)
  window.groupTabs:setMarginTop(visible and 4 or 0)
  if visible then
    local items = {}
    for i, b in ipairs(boards) do
      local bk = b.key
      items[i] = { text = tostring(b.name or bk), checked = false, onClick = function() selectRecordBoard(bk) end }
    end
    for i, tab in pairs(buildTabRows(window.groupTabs, 'LeaderboardGroupTab', items, 160)) do groupTabs[boards[i].key] = tab end
  end
  window.infoLabel:setText(c and c.info or '')
  if boards[1] then
    local keep = false
    for _, b in ipairs(boards) do keep = keep or b.key == rboard end
    selectRecordBoard(keep and rboard or boards[1].key)
  else
    rboard = nil
    buildRecordFilters()
    requestRecord()
  end
end

local function buildRecordTabs()
  setView(true)
  tabs = {}
  local items = {}
  for i, c in ipairs(rmeta.categories) do
    local key = c.key
    items[i] = { text = c.name, checked = key == rcat, tooltip = c.info, onClick = function() selectRecordCategory(key) end }
  end
  for i, tab in pairs(buildTabRows(window.tabs, 'LeaderboardTab', items)) do tabs[rmeta.categories[i].key] = tab end
  window.modeTabs:setVisible(false)
  window.modeTabs:setHeight(0)
  window.seasonToggle:setVisible(false)
  selectRecordCategory(RecordsView.category(rmeta, rcat or '') and rcat or (rmeta.categories[1] and rmeta.categories[1].key))
end

local function showRecords(data)
  if not window or not recordsMode then return end
  rcurrent = data
  rAt = g_clock.seconds()
  window.rowList:destroyChildren()
  local player = g_game.getLocalPlayer()
  local ownName = player and player:getName() or nil
  local rows = rowsOf(data.rows)
  local c = RecordsView.category(rmeta, rcat)
  if data.isMine then
    window.header.value:setText(tr('Best'))
    window.header.extra:setText('')
    for i, r in ipairs(rows) do
      createRecordRow(i, tostring(r.name or ''), '', tostring(r.value or ''), '', nil)
    end
    window.championPanel.championTitle:setText(tr('My Records'))
    window.championPanel.championNames:setText(tr('Your best drop, Tower floor, rift tier and boss times. A new best shows "New record" in the game.'))
    window.ownPanel.ownLabel:setText('')
    window.emptyText:setText(tr('No records yet.'))
  elseif data.isFirsts then
    window.header.value:setText(tr('Date'))
    window.header.extra:setText(tr('Time'))
    for i, r in ipairs(rows) do
      createRecordRow(i, tostring(r.members or '?'), tostring(r.name or r.board or ''),
        RecordsView.dateText(r.at), (tonumber(r.value) and r.format == 'time') and RecordsView.valueText(r.value, 'time') or '',
        tr('%s: realm first of %s.', tostring(r.board or ''), tostring(data.seasonName or '')))
    end
    window.championPanel.championTitle:setText(tr('Realm firsts of %s', tostring(data.seasonName or '')))
    window.championPanel.championNames:setText(tr('The first player or party to defeat each boss this season holds a title for it.'))
    window.ownPanel.ownLabel:setText(tr('A realm first title stays for the whole season.'))
    window.emptyText:setText(tr('No boss has fallen yet this season.'))
  else
    local b = rBoardMeta() or { name = '?' }
    window.header.value:setText(b.value or tr('Best'))
    window.header.extra:setText(tr('Date'))
    for _, r in ipairs(rows) do
      local rank = tonumber(r.rank) or 0
      local party = tonumber(r.party) or 1
      createRecordRow(rank, r.name, party > 1 and tr('party of %d', party) or (r.vocation or ''),
        RecordsView.valueText(r.value, b.format), RecordsView.dateText(r.at),
        party > 1 and tostring(r.members or '') or nil, ownName)
    end
    local period
    for _, p in ipairs(rmeta.periods) do if p.key == data.period then period = p.name end end
    if data.period == 'season' then period = tostring(data.seasonName or period) end
    window.championPanel.championTitle:setText(tr('%s  -  %s', b.name or '', period or ''))
    window.championPanel.championNames:setText(RecordsView.recordText(b, data))
    window.ownPanel.ownLabel:setText(RecordsView.ownText(b, data))
    window.emptyText:setText(tr('No result on this board in this view yet.'))
  end
  window.emptyText:setVisible(#rows == 0)
  window.hintLabel:setText(tr('Weekly top 3 of every board: the %s title and the %s name plate badge for a week. Ties go to the earlier time.',
    tostring(c and c.title or tr('category')), tostring(rmeta.badge or '')))
  updateTimer()
end

function toggleRecords()
  if not window then return end
  recordsMode = not recordsMode
  window.recordsToggle:setChecked(recordsMode)
  if recordsMode then
    setView(true)
    if rmeta and rmeta.complete then
      buildRecordTabs()
    else
      rparts = nil
      send('rmeta', {})
    end
  else
    window.recordFilters:setVisible(false)
    window.recordFilters:setHeight(0)
    window.recordFilters:setMarginTop(0)
    setView(false)
    if meta then
      onMetaRebuild()
      if selected then selectBoard(selected) end
    end
  end
end

-- ---------------------------------------------------------------- protocol
local function onMeta(data)
  meta = data
  if recordsMode and data.open then
    -- the window was opened again from the menu: back to the weekly boards
    recordsMode = false
    window.recordsToggle:setChecked(false)
    window.recordFilters:setVisible(false)
    window.recordFilters:setHeight(0)
  end
  if data.open then seasonView = false seasonMode = 'all' end
  local season = type(data.season) == 'table' and data.season or nil
  if not season then seasonView = false seasonMode = 'all' end
  window.seasonToggle:setVisible(season ~= nil)
  window.seasonToggle:setText(season and tr('%s only', season.tag or tr('Season')) or '')
  window.seasonToggle:setTooltip(season and tr('Show only the characters of %s.', season.name or '') or '')
  window.seasonToggle:setChecked(seasonView)
  if not selectedGroup then selectedGroup = data.ownGroup end
  if not recordsMode then
    setView(false)
    buildBoardCombo()
  end
  buildModeTabs()
  if data.open then show() end
end

-- the weekly boards' tabs again (leaving the Records view)
function onMetaRebuild()
  local season = meta and type(meta.season) == 'table' and meta.season or nil
  window.seasonToggle:setVisible(season ~= nil)
  setView(false)
  buildBoardCombo()
  buildModeTabs()
end

-- a board or group key as the server sent it: a string or a finite number, else nothing (it is sent back in "get")
local function boardKey(v)
  if type(v) == 'string' or (type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge) then return v end
  return nil
end

local function onBoardData(data)
  data.key, data.group = boardKey(data.key), boardKey(data.group)
  current = data
  if recordsMode then return end
  boardAt = g_clock.seconds()
  refreshAsked = false
  if selected ~= data.key then
    selected = data.key
    buildGroupTabs()
  end
  local db = boardMeta(data.key)
  if db and db.weekly and db.byClass then
    classGroup = data.group
    for k, t in pairs(groupTabs) do t:setChecked(k == (data.group or 'all')) end
  elseif data.group then
    selectedGroup = data.group
    for k, t in pairs(groupTabs) do t:setChecked(k == data.group) end
  end
  syncCombo(data.key)
  showBoard()
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[leaderboard] invalid JSON: ' .. tostring(msg))
    return
  end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'meta' then
    onMeta(data)
  elseif msg.action == 'board' then
    onBoardData(data)
  elseif msg.action == 'rcat' then
    rparts = RecordsView.addPart(rparts, data)
  elseif msg.action == 'rmeta' then
    rmeta = RecordsView.finish(rparts, data)
    rparts = nil
    if recordsMode then buildRecordTabs() end
  elseif msg.action == 'rboard' then
    if data.board == rboard then showRecords(data) end
  elseif msg.action == 'rfirsts' then
    if rcat == 'firsts' then
      data.isFirsts = true
      showRecords(data)
    end
  elseif msg.action == 'rmine' then
    if rcat == 'mine' then
      data.isMine = true
      showRecords(data)
    end
  end
end

-- ---------------------------------------------------------------- window
function toggleSeason()
  seasonView = not seasonView
  if not seasonView then seasonMode = 'all' end
  if window then
    window.seasonToggle:setChecked(seasonView)
    buildModeTabs()
  end
  send('get', { board = selected, group = currentGroup() })
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  if not tickEvent then tick() end
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
  -- the server answers with meta (open) and the board, which shows the window; the first open of a character asks for
  -- the board it chose last (an unknown key gets the World Boss board)
  send('open', { board = selected or savedBoard() })
end

local function onGameEnd()
  hide()
  recordsMode, rparts, rmeta, rcat, rboard, rsel, rcurrent = false, nil, nil, nil, nil, {}, nil
  if window then
    window.recordsToggle:setChecked(false)
    window.recordFilters:setVisible(false)
    window.recordFilters:setHeight(0)
  end
  meta, current, selected, selectedGroup = nil, nil, nil, nil
  tabs, groupTabs, modeTabs, seasonMode = {}, {}, {}, 'all'
  boardOptions = {}
  if window then
    window.boardCombo:clearOptions()
    setView(false)
  end
end

function init()
  window = g_ui.displayUI('leaderboard')
  window:hide()
  window.boardCombo.onOptionChange = onBoardChosen
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  if window then
    window:destroy()
    window = nil
  end
  meta, current, tabs, groupTabs, boardOptions = nil, nil, {}, {}, {}
end
