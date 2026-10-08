-- Leaderboards window: weekly boards (World Boss, Bounty Hunter, Rifts) with last week's title holders, the all-time
-- class ladder, the player's own rank and the time to the weekly reset.
-- Server: server/data/scripts/chaos/leaderboard.lua, extended opcode 229 (JSON {action, data}).
--   server -> client  meta {open, boards = [{key, name, weekly, value, count, title, info}], groups = [{key, name}], ownGroup}
--                     board {key, group, week, resetIn, rows = [{rank, name, value, count, level, vocation, title}],
--                            own = {rank, value, count} | nil, champions = [{rank, rankName, name, value, title}], total}
--   client -> server  open | get {board, group}
-- !leaderboard opens it from the chat; the top menu (Chaos -> Leaderboards) calls toggle().

local OPCODE = 229
local RANK_COLOR = { '#e8b84a', '#a8b4c8', '#c87a3a' }

local window
local meta             -- last meta received
local current          -- last board received
local boardAt = 0      -- g_clock.seconds() when it arrived
local selected         -- board key shown
local selectedGroup    -- class group shown on the ladder
local tabs, groupTabs = {}, {}
local tickEvent
local refreshAsked = false

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

local function boardMeta(key)
  for _, b in ipairs(list(meta and meta.boards)) do
    if b.key == key then return b end
  end
  return nil
end

local function groupName(key)
  for _, g in ipairs(list(meta and meta.groups)) do
    if g.key == key then return g.name end
  end
  return '?'
end

local function ordinal(n)
  local s = ({ 'st', 'nd', 'rd' })[n] or 'th'
  return tostring(n) .. s
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
  if b.weekly then
    row.value:setText(short(r.value))
    row.value:setTooltip(exact(r.value) .. ' ' .. (b.value or ''):lower())
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
  if not window or not current then return end
  local left = (tonumber(current.resetIn) or 0) - (g_clock.seconds() - boardAt)
  window.timerLabel:setText(tr('Weekly reset in %s', formatTime(left)))
  window.timerLabel:setTooltip(tr('The weekly boards reset every Monday at 06:00 server time.'))
  if left <= 0 and not refreshAsked and window:isVisible() then
    refreshAsked = true
    scheduleEvent(function() send('get', { board = selected, group = selectedGroup }) end, 5000)
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
  local rows = list(current.rows)
  for _, r in ipairs(rows) do createRow(r, b, ownName) end

  window.infoLabel:setText(b.info or '')
  window.header.value:setText(b.value or tr('Value'))
  window.header.extra:setText(b.weekly and (b.count or '') or tr('Class'))

  -- last week's title holders (weekly boards) / the class shown (ladder)
  if b.weekly then
    local champions = list(current.champions)
    window.championPanel.championTitle:setText(tr('%s: the title holders this week (last week\'s top 3)', b.title or ''))
    if #champions == 0 then
      window.championPanel.championNames:setText(tr('Nobody yet: the top 3 of this week get the title on Monday.'))
      window.championPanel.championNames:setTooltip('')
    else
      local parts, exacts = {}, {}
      for _, c in ipairs(champions) do
        local place = c.rankName or ordinal(tonumber(c.rank) or 0)
        parts[#parts + 1] = place .. ' ' .. (c.name or '?')
        exacts[#exacts + 1] = string.format('%s %s: %s %s', place, c.name or '?', exact(c.value), (b.value or ''):lower())
      end
      window.championPanel.championNames:setText(table.concat(parts, '    '))
      window.championPanel.championNames:setTooltip(table.concat(exacts, '\n'))
    end
  else
    window.championPanel.championNames:setTooltip('')
    window.championPanel.championTitle:setText(tr('%s: highest level, all time', groupName(current.group)))
    window.championPanel.championNames:setText(tr('Every class of the %s line counts. Updated every few minutes.', groupName(current.group)))
  end

  window.emptyText:setText(b.weekly and tr('No scores on this board yet this week.') or tr('No characters of this class yet.'))
  window.emptyText:setVisible(#rows == 0)

  local own = type(current.own) == 'table' and current.own or nil
  if own then
    local text
    if b.weekly then
      text = tr('Your rank: #%d of %d   -   %s: %s', tonumber(own.rank) or 0, tonumber(current.total) or 0,
        b.value or tr('Score'), exact(own.value))
      if b.count then text = text .. string.format('   -   %s: %s', b.count, exact(own.count)) end
    else
      text = tr('Your rank in the %s line: #%d   -   level %d', groupName(current.group), tonumber(own.rank) or 0,
        tonumber(own.value) or 0)
    end
    window.ownPanel.ownLabel:setText(text)
  else
    window.ownPanel.ownLabel:setText(b.weekly and tr('You have no score on this board this week.')
      or tr('Your class is not on this ladder.'))
  end

  if b.weekly then
    window.hintLabel:setText(tr('Top 3 on Monday: the title %s for a week, orbs to the inbox.', b.title or ''))
  else
    window.hintLabel:setText(tr('Levels are read from the saved characters.'))
  end
  updateTimer()
end

local function buildGroupTabs()
  window.groupTabs:destroyChildren()
  groupTabs = {}
  local ladder = selected and boardMeta(selected)
  local visible = ladder and not ladder.weekly
  window.groupTabs:setVisible(visible and true or false)
  window.groupTabs:setHeight(visible and 22 or 0)
  window.groupTabs:setMarginTop(visible and 4 or 0)
  if not visible then return end
  for _, g in ipairs(list(meta.groups)) do
    local tab = g_ui.createWidget('LeaderboardGroupTab', window.groupTabs)
    tab:setText(g.name or '?')
    local key = g.key
    tab:setChecked(key == selectedGroup)
    tab.onClick = function()
      selectedGroup = key
      for k, t in pairs(groupTabs) do t:setChecked(k == key) end
      send('get', { board = selected, group = key })
    end
    groupTabs[key] = tab
  end
end

local function selectBoard(key)
  selected = key
  for k, tab in pairs(tabs) do tab:setChecked(k == key) end
  local b = boardMeta(key)
  if b and not b.weekly and not selectedGroup then selectedGroup = meta.ownGroup end
  buildGroupTabs()
  send('get', { board = key, group = selectedGroup })
end

local function buildTabs()
  window.tabs:destroyChildren()
  tabs = {}
  for _, b in ipairs(list(meta.boards)) do
    local tab = g_ui.createWidget('LeaderboardTab', window.tabs)
    tab:setText(b.name or b.key)
    tab:setTooltip(b.weekly and tr('Weekly: %s', b.info or '') or (b.info or ''))
    local key = b.key
    tab.onClick = function() selectBoard(key) end
    tabs[key] = tab
  end
end

-- ---------------------------------------------------------------- protocol
local function onMeta(data)
  meta = data
  if not selectedGroup then selectedGroup = data.ownGroup end
  buildTabs()
  if data.open then show() end
end

local function onBoardData(data)
  current = data
  boardAt = g_clock.seconds()
  refreshAsked = false
  if selected ~= data.key then
    selected = data.key
    buildGroupTabs()
  end
  if data.group then
    selectedGroup = data.group
    for k, t in pairs(groupTabs) do t:setChecked(k == data.group) end
  end
  for k, tab in pairs(tabs) do tab:setChecked(k == data.key) end
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
  end
end

-- ---------------------------------------------------------------- window
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
  send('open', { board = selected }) -- the server answers with meta (open) and the board, which shows the window
end

local function onGameEnd()
  hide()
  meta, current, selected, selectedGroup = nil, nil, nil, nil
  tabs, groupTabs = {}, {}
end

function init()
  window = g_ui.displayUI('leaderboard')
  window:hide()
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
  meta, current, tabs, groupTabs = nil, nil, {}, {}
end
