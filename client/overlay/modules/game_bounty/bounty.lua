-- Bounty board window: today's contracts per level band, accept/abandon, progress and the time to the next roll.
-- Server: server/data/scripts/chaos/bounty.lua, extended opcode 223 (JSON {action, data}).
--   server -> client  board {day, nextIn, open, band, active, maxActive, week = {done, need, claimed},
--                            bands = [{index, label, own, contracts = [{key, type, name, count, tier, level, look,
--                            outfit, reward = {gold, chaos, divine, exp}, state = open|active|done, progress}]}]}
--                     progress {key, progress, count, state}
--   client -> server  open | accept {key} | abandon {key}
-- !bounty opens it from the chat; the top menu (Chaos -> Bounty Board) calls toggle().

local OPCODE = 223

local KIND_TEXT = { hunt = 'HUNT', elite = 'ELITE', boss = 'BOSS' }
local KIND_COLOR = { hunt = '#8c8070', elite = '#b070ff', boss = '#e03a1e' }
local TIER_COLOR = { magic = '#5a8fff', rare = '#f6cf72', legendary = '#e8582a' }

local window
local board            -- last board received
local boardAt = 0      -- g_clock.seconds() when it arrived
local selectedBand     -- band index of the tab shown
local rows = {}        -- key -> row widget of the tab shown
local tabs = {}
local tickEvent
local refreshAsked = false

-- ---------------------------------------------------------------- helpers
local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function short(n)
  n = tonumber(n) or 0
  if formatShortNumber then return formatShortNumber(n) end
  return tostring(n)
end

local function plural(name, count)
  if count == 1 then return name end
  local lower = name:lower()
  if lower:match('s$') then return name end
  if lower:match('[^aeiou]y$') then return name:sub(1, -2) .. 'ies' end
  if lower:match('x$') or lower:match('ch$') or lower:match('sh$') then return name .. 'es' end
  if lower:match('man$') then return name:sub(1, -3) .. 'en' end
  return name .. 's'
end

local function capitalize(s)
  s = tostring(s or '')
  return (s:gsub('^%l', string.upper))
end

local function formatTime(seconds)
  seconds = math.max(0, math.floor(seconds))
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  return string.format('%dh %02dm %02ds', h, m, s)
end

local function taskText(c)
  if c.type == 'boss' then
    return c.count > 1 and tr('Slay the boss %d times.', c.count) or tr('Slay the boss once.')
  elseif c.type == 'elite' then
    return tr('Kill %d %s or stronger %s.', c.count, c.tier or 'magic', plural(c.name, c.count))
  end
  return tr('Kill %d %s.', c.count, plural(c.name, c.count))
end

local function rewardText(r)
  r = type(r) == 'table' and r or {}
  local parts, exact = {}, {}
  if (tonumber(r.gold) or 0) > 0 then
    parts[#parts + 1] = short(r.gold) .. ' gold'
    exact[#exact + 1] = (comma_value and comma_value(r.gold) or tostring(r.gold)) .. ' gold to your bank'
  end
  if (tonumber(r.chaos) or 0) > 0 then
    local t = r.chaos .. ' Chaos Orb' .. (r.chaos > 1 and 's' or '')
    parts[#parts + 1] = t
    exact[#exact + 1] = t
  end
  if (tonumber(r.divine) or 0) > 0 then
    local t = r.divine .. ' Divine Orb' .. (r.divine > 1 and 's' or '')
    parts[#parts + 1] = t
    exact[#exact + 1] = t
  end
  if (tonumber(r.exp) or 0) > 0 then
    parts[#parts + 1] = short(r.exp) .. ' exp'
    exact[#exact + 1] = (comma_value and comma_value(r.exp) or tostring(r.exp)) .. ' experience'
  end
  return table.concat(parts, ', '), tr('Reward:') .. '\n' .. table.concat(exact, '\n')
end

local function list(value)
  local out = {}
  if type(value) == 'table' then
    for _, v in ipairs(value) do out[#out + 1] = v end
  end
  return out
end

-- ---------------------------------------------------------------- rows
local function activeCount()
  return board and tonumber(board.active) or 0
end

local function updateRow(row, c)
  local count = tonumber(c.count) or 1
  local progress = tonumber(c.progress) or 0
  local state = c.state or 'open'
  row.progress:setPercent(math.floor(progress * 100 / math.max(1, count)))
  row.progress:setText(string.format('%s / %s', short(progress), short(count)))
  row.progress:setVisible(state ~= 'open')
  row.progress:setBackgroundColor(state == 'done' and '#2f7a2a' or '#8a1010')
  local action = row.action
  action:setEnabled(true)
  if state == 'open' then
    action:setText(tr('Accept'))
    local full = activeCount() >= (tonumber(board.maxActive) or 3)
    action:setEnabled(not full)
    action:setTooltip(full and tr('You already hold %d contracts.', tonumber(board.maxActive) or 3) or '')
  elseif state == 'active' then
    action:setText(tr('Abandon'))
    action:setTooltip(tr('Drop this contract (its progress is lost).'))
  else
    action:setText(tr('Completed'))
    action:setEnabled(false)
    action:setTooltip('')
  end
  action.onClick = function()
    if state == 'open' then
      send('accept', { key = c.key })
    elseif state == 'active' then
      send('abandon', { key = c.key })
    end
  end
end

local function createRow(c)
  local row = g_ui.createWidget('BountyRow', window.contractList)
  local outfit = type(c.outfit) == 'table' and c.outfit or { type = tonumber(c.look) or 0 }
  if (tonumber(outfit.type) or 0) > 0 then
    row.creature:setOutfit(outfit)
  else
    row.creature:setVisible(false)
  end
  row.kind:setText(KIND_TEXT[c.type] or capitalize(c.type))
  row.kind:setColor(KIND_COLOR[c.type] or '#8c8070')
  row.name:setText(c.name or '?')
  if c.type == 'elite' and TIER_COLOR[c.tier] then row.name:setColor(TIER_COLOR[c.tier]) end
  if tonumber(c.level) then row.name:setTooltip(tr('Hunting level about %d', tonumber(c.level))) end
  row.task:setText(taskText(c))
  local text, exact = rewardText(c.reward)
  row.reward:setText(text)
  row.reward:setTooltip(exact)
  updateRow(row, c)
  return row
end

local function currentBand()
  if not board then return nil end
  for _, band in ipairs(list(board.bands)) do
    if band.index == selectedBand then return band end
  end
  return nil
end

local function showBand(index)
  selectedBand = index
  for i, tab in pairs(tabs) do tab:setChecked(i == index) end
  window.contractList:destroyChildren()
  rows = {}
  local band = currentBand()
  local contracts = band and list(band.contracts) or {}
  for _, c in ipairs(contracts) do
    rows[c.key] = createRow(c)
  end
  window.emptyText:setVisible(#contracts == 0)
end

local function updateHeader()
  if not window or not board then return end
  window.activeLabel:setText(tr('Active contracts: %d / %d', activeCount(), tonumber(board.maxActive) or 3))
  local week = type(board.week) == 'table' and board.week or {}
  local done, need = tonumber(week.done) or 0, tonumber(week.need) or 7
  if week.claimed then
    window.weekLabel:setText(tr('Weekly chest: collected'))
  else
    window.weekLabel:setText(tr('Weekly chest: %d / %d', math.min(done, need), need))
  end
  window.weekLabel:setTooltip(tr('Complete %d contracts in a week (Monday to Monday) for a chest of orbs.', need))
end

local function tick()
  tickEvent = nil
  if not window or not board then return end
  local left = (tonumber(board.nextIn) or 0) - (g_clock.seconds() - boardAt)
  window.timerLabel:setText(tr('New contracts in %s', formatTime(left)))
  if left <= 0 and not refreshAsked and window:isVisible() then
    refreshAsked = true
    scheduleEvent(function() send('open') end, 3000)
  end
  tickEvent = scheduleEvent(tick, 1000)
end

local function buildTabs()
  window.tabs:destroyChildren()
  tabs = {}
  local keep
  for _, band in ipairs(list(board.bands)) do
    local tab = g_ui.createWidget('BountyTab', window.tabs)
    tab:setText(band.label or ('Band ' .. tostring(band.index)))
    if band.own then tab:setTooltip(tr('Your level')) end
    local index = band.index
    tab.onClick = function() showBand(index) end
    tabs[index] = tab
    if index == selectedBand then keep = index end
  end
  if not keep then keep = tonumber(board.band) end
  if not tabs[keep] then
    local first = list(board.bands)[1]
    keep = first and first.index
  end
  showBand(keep)
end

-- ---------------------------------------------------------------- protocol
local function onBoard(data)
  board = data
  boardAt = g_clock.seconds()
  refreshAsked = false
  buildTabs()
  updateHeader()
  if tickEvent then removeEvent(tickEvent) end
  tick()
  if data.open then show() end
end

local function onProgress(data)
  if not board then return end
  for _, band in ipairs(list(board.bands)) do
    for _, c in ipairs(list(band.contracts)) do
      if c.key == data.key then
        c.progress = tonumber(data.progress) or c.progress
        c.state = data.state or c.state
        if rows[c.key] and band.index == selectedBand then updateRow(rows[c.key], c) end
      end
    end
  end
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[bounty] invalid JSON: ' .. tostring(msg))
    return
  end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'board' then
    -- open = false: a refresh after a kill or an accept; it never pops the window up by itself
    onBoard(data)
  elseif msg.action == 'progress' then
    onProgress(data)
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
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
    return
  end
  send('open') -- the server answers with the board, which shows the window
end

local function onGameEnd()
  hide()
  board, rows, tabs, selectedBand = nil, {}, {}, nil
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

function init()
  window = g_ui.displayUI('bounty')
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
  board, rows, tabs = nil, {}, {}
end
