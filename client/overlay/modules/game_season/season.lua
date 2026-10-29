-- Seasons window: the season (name, time left, modifier), this character's status with a Join button when it can
-- join, and the account's reward track (milestones, progress, what is unlocked).
-- Server: server/data/scripts/chaos/season.lua, extended opcode 246 (JSON {action, data}).
--   server -> client  state {open, season = {id, name, tag, status, startsIn, endsIn, modifier = {name, description}},
--                            mine = {realm, seasonal, veteran, eligible, reason, level},
--                            track = [{key, name, stat, value, progress, reward, kind, unlocked, by}], titles = [..]}
--                     confirm {text, seconds, modes = [{key, name, short, ssf, hc, warning}]}   the join terms and the
--                                                modes (season_modes.lua): the join dialog (seasonjoin.otui)
--                     notice {text}              why a join was refused
--   client -> server  open | join {confirm, mode} | beat (a Hardcore character's heartbeat, mine.heartbeat seconds) |
--                     sync (after the game starts: the server answers a Hardcore character with its state)
-- The pure parts of the dialog and the modes: seasonjoin.lua (SeasonJoin, seasonjoin_test.lua).
-- The Journey tab (Seasonal Journey, server season_journey.lua): journey.lua and journeyview.lua; its actions
-- journey / journeyChapter / journeyDone arrive on this opcode and go to SeasonJourneyTab.onMessage.
-- The top menu (Adventure > Season) calls toggle().

local OPCODE = 246

local window
local state         -- last state received
local stateAt = 0   -- g_clock.seconds() when it arrived
local tickEvent
local confirmBox
local joinWindow    -- the join dialog (seasonjoin.otui)
local joinChoices, joinChoice, joinAcked, modeButtons = {}, nil, false, {}
local beatEvent, beatSeconds
local currentTab = 'season'
local OVERVIEW_IDS = { 'nameLabel', 'modifierLabel', 'minePanel', 'trackTitle', 'listFrame', 'trackList', 'listScroll',
  'emptyText', 'titlesLabel', 'hintLabel' }

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

local function formatTime(seconds)
  seconds = math.max(0, math.floor(seconds))
  local d = math.floor(seconds / 86400)
  local h = math.floor((seconds % 86400) / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if d > 0 then return string.format('%dd %02dh %02dm', d, h, m) end
  return string.format('%dh %02dm %02ds', h, m, s)
end

local function updateTimer()
  if not window or not state then return end
  local s = type(state.season) == 'table' and state.season or nil
  local passed = g_clock.seconds() - stateAt
  if not s then
    window.timerLabel:setText('')
  elseif s.status == 'active' then
    window.timerLabel:setText(tr('Ends in %s', formatTime((tonumber(s.endsIn) or 0) - passed)))
  elseif s.status == 'upcoming' then
    window.timerLabel:setText(tr('Starts in %s', formatTime((tonumber(s.startsIn) or 0) - passed)))
  else
    window.timerLabel:setText(tr('Ended'))
  end
end

local function tick()
  tickEvent = nil
  if not window or not window:isVisible() then return end
  updateTimer()
  tickEvent = scheduleEvent(tick, 1000)
end

local function showState()
  if not window or not state then return end
  local s = type(state.season) == 'table' and state.season or nil
  local mine = type(state.mine) == 'table' and state.mine or {}
  window.trackList:destroyChildren()
  window.emptyText:setVisible(s == nil and currentTab == 'season')
  if not s then
    window.nameLabel:setText(tr('Seasons'))
    window.modifierLabel:setText('')
    window.minePanel.mineLabel:setText(tr('No season is configured on this server.'))
    window.minePanel.joinButton:setVisible(false)
    window.titlesLabel:setText('')
    updateTimer()
    return
  end
  window.nameLabel:setText(string.format('%s %s', s.name or '?', s.tag or ''))
  local mod = s.status ~= 'ended' and type(s.modifier) == 'table' and s.modifier or nil
  window.modifierLabel:setText(mod and tr('Season modifier %s: %s', mod.name or '', mod.description or '') or '')

  local text
  if mine.seasonal then
    text = tr('This character is a %s character. Milestones it reaches unlock their rewards for your whole account.', s.name or '')
  elseif mine.veteran then
    text = tr('This character played a season and is a standard character now.')
  elseif mine.eligible then
    text = tr('This character can join %s: it starts over with nothing and plays only with %s characters until the end.', s.name or '', s.name or '')
  elseif s.status == 'active' then
    text = tostring(mine.reason or '')
  elseif s.status == 'upcoming' then
    text = tr('The season has not started yet. Make a fresh character to join it when it starts.')
  else
    text = tr('The season has ended. Its rewards stay on your account.')
  end
  local modeLine = SeasonJoin.modeLine(mine)
  if modeLine then text = text .. " " .. modeLine end
  window.minePanel.mineLabel:setText(text)
  window.minePanel.joinButton:setVisible(mine.eligible == true)

  for _, m in ipairs(list(state.track)) do
    local row = g_ui.createWidget('SeasonTrackRow', window.trackList)
    row.name:setText(m.name or '?')
    row.reward:setText(m.reward or '')
    local goal = math.max(1, tonumber(m.value) or 1)
    local progress = math.min(goal, tonumber(m.progress) or 0)
    if m.unlocked then
      row.mark:setText('*')
      row.mark:setColor('#f6cf72')
      row.name:setColor('#f6cf72')
      row.progress:setPercent(100)
      row.progress:setText(tr('Unlocked'))
      row:setTooltip(m.by and tr('Unlocked by %s', m.by) or '')
    else
      row.mark:setText('-')
      row.progress:setPercent(math.floor(progress * 100 / goal))
      row.progress:setText(string.format('%d / %d', progress, goal))
    end
  end
  local titles = list(state.titles)
  window.titlesLabel:setText(#titles > 0 and tr('Season titles of your account: %s', table.concat(titles, ', ')) or '')
  updateTimer()
end

-- ---------------------------------------------------------------- the join dialog
local function closeJoin()
  if joinWindow then joinWindow:destroy() joinWindow = nil end
  modeButtons, joinChoice, joinAcked = {}, nil, false
  if confirmBox then confirmBox:destroy() confirmBox = nil end
end

local function refreshJoin()
  if not joinWindow then return end
  for key, b in pairs(modeButtons) do b:setChecked(joinChoice ~= nil and key == joinChoice.key) end
  joinWindow.warningPanel.warningLabel:setText(SeasonJoin.warningText(joinChoice))
  local ask = SeasonJoin.needsAck(joinChoice)
  joinWindow.ackBox:setVisible(ask)
  if not ask then joinWindow.ackBox:setChecked(false) end
  joinWindow.warningPanel.warningLabel:setColor(joinChoice and joinChoice.hc and '#ff7a5a' or '#d6c9ae')
  joinWindow.joinButton:setText(SeasonJoin.joinLabel(joinChoice))
  joinWindow.joinButton:setEnabled(SeasonJoin.canJoin(joinChoice, joinAcked))
end

function selectMode(key)
  joinChoice = SeasonJoin.find(joinChoices, key) or joinChoice
  joinAcked = false
  if joinWindow then joinWindow.ackBox:setChecked(false) end
  refreshJoin()
end

function onJoinAck(checked)
  joinAcked = checked == true
  refreshJoin()
end

function confirmJoin()
  local data = SeasonJoin.payload(joinChoice, joinAcked)
  if not data then return end
  closeJoin()
  send('join', data)
end

function cancelJoin()
  closeJoin()
end

local function onConfirm(data)
  closeJoin()
  joinChoices = SeasonJoin.choices(data)
  joinWindow = g_ui.displayUI('seasonjoin')
  if not joinWindow then return end
  joinWindow.termsLabel:setText(tostring(data.text or ''))
  for _, c in ipairs(joinChoices) do
    local b = g_ui.createWidget('SeasonModeButton', joinWindow.modeRow)
    b:setText(c.short)
    b:setTooltip(c.warning)
    local key = c.key
    b.onClick = function() selectMode(key) end
    modeButtons[key] = b
  end
  joinChoice = SeasonJoin.find(joinChoices, SeasonJoin.DEFAULT)
  refreshJoin()
  joinWindow:show()
  joinWindow:raise()
  joinWindow:focus()
end

-- ---------------------------------------------------------------- the Hardcore heartbeat
local function stopBeat()
  if beatEvent then removeEvent(beatEvent) beatEvent = nil end
  beatSeconds = nil
end

local function beat()
  beatEvent = nil
  if not beatSeconds or not g_game.isOnline() then return end
  send('beat')
  beatEvent = scheduleEvent(beat, beatSeconds * 1000)
end

local function updateBeat(mine)
  local s = SeasonJoin.heartbeat(mine)
  if s == beatSeconds then return end
  stopBeat()
  if s then
    beatSeconds = s
    beat()
  end
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[season] invalid JSON: ' .. tostring(msg))
    return
  end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    if (confirmBox or joinWindow) and type(data.mine) == 'table' and not data.mine.eligible then
      closeJoin() -- joined (or no longer eligible): the question is answered
    end
    updateBeat(type(data.mine) == 'table' and data.mine or nil)
    state = data
    stateAt = g_clock.seconds()
    showState()
    if data.open then show() end
  elseif type(msg.action) == 'string' and msg.action:sub(1, 7) == 'journey' then
    SeasonJourneyTab.onMessage(msg.action, data)
  elseif msg.action == 'confirm' then
    onConfirm(data)
  elseif msg.action == 'notice' then
    if window and window:isVisible() and data.text then
      window.minePanel.mineLabel:setText(tostring(data.text))
    end
  end
end

-- ---------------------------------------------------------------- tabs: Season | Journey
function showTab(name)
  if not window then return end
  currentTab = name == 'journey' and 'journey' or 'season'
  local journey = currentTab == 'journey'
  window.overviewTab:setChecked(not journey)
  window.journeyTab:setChecked(journey)
  for _, id in ipairs(OVERVIEW_IDS) do
    local w = window:getChildById(id)
    if w then w:setVisible(not journey) end
  end
  if journey then
    SeasonJourneyTab.open()
  else
    SeasonJourneyTab.close()
    showState()
  end
end

-- ---------------------------------------------------------------- window
function join()
  send('join', { confirm = false })
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  if not tickEvent then tick() end
end

function hide()
  SeasonJourneyTab.close()
  if window then window:hide() end
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  closeJoin()
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
    return
  end
  send('open') -- the server answers with the state (open), which shows the window
end

local function onGameEnd()
  hide()
  stopBeat()
  state = nil
  SeasonJourneyTab.reset()
end

-- the state (and with it the Hardcore heartbeat) also after a reconnect, which brings no login state from the server
local function onGameStart()
  scheduleEvent(function() if g_game.isOnline() then send('sync') end end, 3000)
end

function init()
  window = g_ui.displayUI('season')
  pcall(function() modules.game_howitworks.attach(window, 'season') end) -- game_howitworks: the ? button
  window:hide()
  SeasonJourneyTab.setup(window)
  window.overviewTab:setChecked(true)
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd, onGameStart = onGameStart })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd, onGameStart = onGameStart })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  hide()
  stopBeat()
  SeasonJourneyTab.terminate()
  if window then
    window:destroy()
    window = nil
  end
  state = nil
end
