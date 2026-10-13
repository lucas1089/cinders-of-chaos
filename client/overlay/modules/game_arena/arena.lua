-- Ranked PvP arena: queue window, match HUD and the result toast.
-- Server: server/data/scripts/chaos/arena.lua, extended opcode 236 (JSON {action, data}).
--   server -> client  state {open, ratings = {['1v1'] = {rating, wins, losses, draws, best}, ...}, modes, queueCount,
--                            season = {id, brackets = {['1v1'] = {rating, tierName, color, placed, placementLeft, ...}}} | nil,
--                            queue = {mode, waited, window, rating} | nil, match = {mode, phase} | nil,
--                            rules = {minLevel, levelLow, levelHigh, countdown, fight}, firstWinDone,
--                            recent = [{mode, result, before, after, opponents, partner, reason, at}], now}
--                     start {mode, team, countdown, fight}          (match found: HUD on, secure mode off)
--                     hud {phase, mode, left, team, sides = [[{name, hp, defeated, cid}], [...]]}   (every second)
--                     end {mode, result, before, after, delta, reason, reward, firstWin, rated, opponents,
--                          season = {before, after, delta, tierName, placed, placementLeft} | nil}
--   client -> server  open | queue {mode} | leave
-- The top menu (Adventure > Arena) calls toggle().

local OPCODE = 236
local T = ArenaText

local window
local hudPanel
local state           -- last state received
local stateAt = 0     -- g_clock.seconds() when it arrived
local tickEvent
local resultEvent
local secureBefore    -- secure mode before the match (restored after it)
local myTeam

-- ---------------------------------------------------------------- helpers
local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

-- the rows of a server list (matches, players); an entry that is no table is left out
local function list(value)
  local out = {}
  if type(value) == 'table' then
    for _, v in ipairs(value) do
      if type(v) == 'table' then out[#out + 1] = v end
    end
  end
  return out
end

-- ---------------------------------------------------------------- window
local function updateCards()
  local ratings = type(state.ratings) == 'table' and state.ratings or {}
  local inQueue = type(state.queue) == 'table'
  local inMatch = type(state.match) == 'table'
  local season = type(state.season) == 'table' and type(state.season.brackets) == 'table' and state.season.brackets or {}
  for _, mode in ipairs({ '1v1', '2v2', '3v3' }) do
    local card = window['card' .. mode]
    local r = type(ratings[mode]) == 'table' and ratings[mode] or {}
    card.title:setText(T.MODE_TITLE[mode] or mode)
    local line, color, tip = T.seasonLine(season[mode], type(state.season) == 'table' and state.season.id or nil)
    card.season:setText(line)
    card.season:setColor(color)
    card.season:setTooltip(tip)
    card.rating:setText(tostring(tonumber(r.rating) or 1000))
    card.record:setText(tr('W-L-D %s   best %d', T.record(r), tonumber(r.best) or tonumber(r.rating) or 1000))
    card.record:setTooltip(tr('%d wins, %d losses, %d draws', tonumber(r.wins) or 0, tonumber(r.losses) or 0, tonumber(r.draws) or 0))
    local waiting = (type(state.queueCount) == 'table' and tonumber(state.queueCount[mode])) or 0
    card.queue:setText(tr('Queue %s', mode))
    card.queue:setEnabled(not inQueue and not inMatch)
    if mode == '1v1' then
      card.queue:setTooltip(tr('%d player(s) waiting.', waiting))
    else
      card.queue:setTooltip(tr('Party of exactly %s; everyone must be in a protection zone. %d team(s) waiting.',
        mode == '2v2' and tr('two') or tr('three'), waiting))
    end
    card.queue.onClick = function() send('queue', { mode = mode }) end
  end
end

local function updateStatus()
  local inQueue = type(state.queue) == 'table'
  local text
  if type(state.match) == 'table' then
    text = tr('You are in a %s match.', state.match.mode or '')
  elseif inQueue then
    local waited = (tonumber(state.queue.waited) or 0) + (g_clock.seconds() - stateAt)
    local w = tonumber(state.queue.window) or 100
    text = tr('In the %s queue: %s (rating %d, window +/-%d)', state.queue.mode or '', T.clock(waited),
      tonumber(state.queue.rating) or 0, w)
  else
    text = tr('Not in a queue.')
  end
  window.statusLabel:setText(text)
  window.leaveButton:setEnabled(inQueue)
  local rules = type(state.rules) == 'table' and state.rules or {}
  window.infoLabel:setText(tr('Opponent levels %d - %d.  First-win bonus: %s', tonumber(rules.levelLow) or 0,
    tonumber(rules.levelHigh) or 0, state.firstWinDone and tr('taken') or tr('ready')))
  window.infoLabel:setTooltip(tr('Level %d+. Countdown %ds, then %s to win; on time-out the side with more health (share) wins.',
    tonumber(rules.minLevel) or 50, tonumber(rules.countdown) or 10, T.clock(tonumber(rules.fight) or 300)))
end

local function updateRecent()
  window.matchList:destroyChildren()
  local rows = list(state.recent)
  local now = tonumber(state.now) or os.time()
  for _, m in ipairs(rows) do
    local row = g_ui.createWidget('ArenaMatchRow', window.matchList)
    row.mode:setText(m.mode or '')
    local text, color = T.result(m.result)
    row.result:setText(text)
    row.result:setColor(color)
    local before, after = tonumber(m.before) or 0, tonumber(m.after) or 0
    row.change:setText(string.format('%d -> %d (%s)', before, after, T.delta(after - before)))
    local vs = tr('vs %s', m.opponents or '?')
    if m.partner and m.partner ~= '' then vs = vs .. tr(' (with %s)', m.partner) end
    row.opponents:setText(vs)
    row.when:setText(T.ago(now - (tonumber(m.at) or now)))
    row:setTooltip(tr('Ended: %s', T.reason(m.reason)))
  end
  window.emptyText:setVisible(#rows == 0)
end

local function tick()
  tickEvent = nil
  if not window or not state or not window:isVisible() then return end
  updateStatus()
  tickEvent = scheduleEvent(tick, 1000)
end

local function onState(data)
  state = data
  stateAt = g_clock.seconds()
  if not window then return end
  updateCards()
  updateStatus()
  updateRecent()
  if data.open then show() end
  if tickEvent then removeEvent(tickEvent) end
  tick()
end

-- ---------------------------------------------------------------- HUD
local function hideResult()
  resultEvent = nil
  if hudPanel then
    hudPanel.result:hide()
    hudPanel:hide()
  end
end

local function fillSide(panel, side, own)
  panel:destroyChildren()
  for _, p in ipairs(list(side)) do
    local row = g_ui.createWidget('ArenaHudRow', panel)
    row.name:setText(p.name or '?')
    row.name:setColor(own and '#f6cf72' or '#e03a1e')
    local hp = tonumber(p.hp) or 0
    if p.defeated then
      row.bar:setPercent(0)
      row.bar:setText(tr('defeated'))
      row.name:setColor('#6b6258')
    else
      row.bar:setPercent(hp)
      row.bar:setText(hp .. '%')
      row.bar:setBackgroundColor(T.hpColor(hp))
    end
  end
end

local function onHud(data)
  if not hudPanel then return end
  if resultEvent then return end -- the result is on screen
  myTeam = tonumber(data.team) or myTeam or 1
  local sides = list(data.sides)
  -- your side always on the left
  local mine, theirs = sides[myTeam] or {}, sides[3 - myTeam] or {}
  fillSide(hudPanel.left, mine, true)
  fillSide(hudPanel.right, theirs, false)
  hudPanel.mode:setText(tr('Arena %s', data.mode or ''))
  local big, small = T.hudCenter(data.phase, data.left)
  hudPanel.clock:setText(big)
  hudPanel.clock:setColor(data.phase == 'countdown' and '#e03a1e' or '#f6cf72')
  hudPanel.phase:setText(tr(small))
  hudPanel.result:hide()
  hudPanel:show()
  hudPanel:raise()
end

local function onStart(data)
  myTeam = tonumber(data.team) or 1
  -- the base PvP rules: nobody can hit a player who has secure mode on, so it is off for the match
  if g_game.isSafeFight then
    secureBefore = g_game.isSafeFight()
    if secureBefore then g_game.setSafeFight(false) end
  end
  if window then hide() end
  if resultEvent then removeEvent(resultEvent) resultEvent = nil end
  if hudPanel then
    hudPanel.result:hide()
    hudPanel:show()
  end
end

local function onEnd(data)
  g_game.cancelAttack()
  if secureBefore and g_game.setSafeFight then
    g_game.setSafeFight(true)
  end
  secureBefore = nil
  if not hudPanel then return end
  local title, color = T.result(data.result)
  local r = hudPanel.result
  r.title:setText(title)
  r.title:setColor(color)
  if data.rated == false then
    r.rating:setText(tr('Not rated'))
  else
    r.rating:setText(T.ratingLine(data.before, data.after, data.delta))
  end
  local reward = data.reward and data.reward ~= '' and (tr('Reward: %s', data.reward) .. (data.firstWin and tr(' (first win today)') or '')) or ''
  local se = type(data.season) == 'table' and data.season or nil
  if se and data.rated ~= false then
    reward = (reward ~= '' and (reward .. '   ') or '') .. T.seasonDelta(se)
  end
  r.reward:setText(reward)
  r:show()
  r:raise()
  hudPanel:show()
  if resultEvent then removeEvent(resultEvent) end
  resultEvent = scheduleEvent(hideResult, 8000)
end

-- ---------------------------------------------------------------- protocol
local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[arena] invalid JSON: ' .. tostring(msg))
    return
  end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    onState(data)
  elseif msg.action == 'start' then
    onStart(data)
  elseif msg.action == 'hud' then
    onHud(data)
  elseif msg.action == 'end' then
    onEnd(data)
  end
end

-- ---------------------------------------------------------------- public
function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  if not tickEvent then tick() end
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
  send('open') -- the server answers with the state, which shows the window
end

function leaveQueue()
  send('leave')
end

local function onGameEnd()
  hide()
  if hudPanel then
    hudPanel.result:hide()
    hudPanel:hide()
  end
  state, myTeam, secureBefore = nil, nil, nil
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  if resultEvent then removeEvent(resultEvent) resultEvent = nil end
end

function init()
  window = g_ui.displayUI('arena')
  window:hide()
  hudPanel = g_ui.loadUI('arenahud', modules.game_interface.getRootPanel())
  if hudPanel then hudPanel:hide() end
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  if resultEvent then removeEvent(resultEvent) resultEvent = nil end
  if window then window:destroy() window = nil end
  if hudPanel then hudPanel:destroy() hudPanel = nil end
  state = nil
end
