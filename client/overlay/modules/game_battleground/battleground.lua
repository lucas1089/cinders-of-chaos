-- Battleground "Ember Wells" and the PvP seasons: the window (queue with role choice and estimated wait, the season
-- ratings and tiers of every bracket with the rewards preview, the honor vendor), the match HUD (both scores, the
-- three braziers, the clock, the respawn wave), the scoreboard and the end summary.
-- Server: server/data/scripts/chaos/battleground.lua and arena_season.lua, extended opcode 200 (JSON {action, data},
-- chunked by Chaos.sendChunked and joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | query | queue {role} | role {role} | leave | board | buy {key}
--   server -> client  state {...}, start {team, size, prep, teams, colors, braziers, win, bracket}, hud {...},
--                     board {rows, teams, score}, alert {text, kind}, end {...}, msg {text, ok}
-- Pure helpers: bgview.lua (bgview_test.lua). The top menu: Adventure > Battleground.

local OPCODE = 200
local V = BgView

local window, hud, board
local state, stateAt = nil, 0
local tab = 'queue'
local hudData, hudAt = nil, 0
local lastBoard, summary
local myTeam = 1
local secureBefore
local tickEvent
local handlers = {}
local reported = {}

local function now() return g_clock.seconds() end

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[battleground] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function send(action, payload)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = payload or {} }))
  end
end

local function child(w, id)
  return w and w:recursiveGetChildById(id)
end

local function addLabel(parent, style, text, color)
  local l = g_ui.createWidget(style, parent)
  l:setText(text)
  if color then l:setColor(color) end
  return l
end

-- ---------------------------------------------------------------- the window
local function addCard(row, view)
  local tiers = state.season and state.season.tiers or {}
  local c = V.bracketCard(view, tiers, state.season and state.season.placement or 5)
  local w = g_ui.createWidget('BgCard', row)
  child(w, 'emblem'):setImageSource(c.image)
  child(w, 'name'):setText(c.name)
  child(w, 'tier'):setText(c.tier)
  child(w, 'tier'):setColor(c.color)
  child(w, 'rating'):setText(c.rating)
  w:setTooltip(c.tooltip .. '\n' .. tr('Record %s', c.record) .. (c.decay and ('\n' .. c.decay) or ''))
  return w
end

local function addCards(list)
  local season = state.season
  if not season then return end
  local row = g_ui.createWidget('BgCardRow', list)
  for _, b in ipairs(season.order or V.BRACKET_ORDER) do
    addCard(row, season.brackets and season.brackets[b] or {})
  end
end

local function addRow(list, icon, title, sub, stateText, button, onClick, enabled)
  local row = g_ui.createWidget('BgRow', list)
  local ic = row:getChildById('icon')
  if type(icon) == 'number' then
    local item = g_ui.createWidget('UIItem', ic)
    item:fill('parent')
    item:setItemId(icon)
    item:setVirtual(true)
    item:setPhantom(true)
  elseif icon then
    ic:setImageSource(icon)
  end
  row:getChildById('title'):setText(title)
  row:getChildById('sub'):setText(sub or '')
  row:setTooltip(sub or '')
  row:getChildById('state'):setText(stateText or '')
  local b = row:getChildById('button')
  if button then
    b:setText(button)
    b:setEnabled(enabled ~= false)
    b.onClick = onClick
  else
    b:setVisible(false)
  end
  return row
end

local function renderQueue(list)
  local rules = state.rules or {}
  addLabel(list, 'BgHead', tr('Ember Wells'), '#ff9a3c')
  addLabel(list, 'BgWrap', tr('%dv%d to %dv%d. Take and hold the three braziers: every held one scores, the first team to %d wins. ' ..
    'Downed players come back with the next wave (every %ds). No item or experience loss. Damage and healing between players ' ..
    'are scaled to your bracket\'s level.', rules.teamMin or 5, rules.teamMin or 5, rules.teamMax or 10, rules.teamMax or 10,
    rules.win or 1000, rules.wave or 15), '#b8ab92')
  local br = state.bracket and (state.bracket.name .. tr(' (stats scaled to level %d)', state.bracket.ref or 0)) or tr('none')
  addLabel(list, 'BgText', tr('Your bracket: %s', br), '#d6c9ae')
  addLabel(list, 'BgHead', tr('Queue as'), '#e8b84a')
  local roleRow = g_ui.createWidget('BgRoleRow', list)
  local inQueue = type(state.queue) == 'table'
  for _, r in ipairs(V.roleOptions(state)) do
    local b = g_ui.createWidget('BgRoleButton', roleRow)
    b:setText(r.text)
    b:setColor(r.color)
    b:setChecked(r.chosen)
    b:setEnabled(not inQueue)
    local key = r.key
    b.onClick = function() send('role', { role = key }) end
  end
  local text, color = V.queueStatus(state, now() - stateAt)
  local status = addLabel(list, 'BgWrap', text, color)
  status:setId('status')
  addLabel(list, 'BgWrap', tr('Solo, or the party leader queues the party (up to %d). Parties stay together; tanks and healers are spread ' ..
    'over both teams.', rules.partyMax or 5), '#8c8070')
  addLabel(list, 'BgHead', tr('Season ratings'), '#e8b84a')
  addCards(list)
  addLabel(list, 'BgText', V.honorLine(state), '#f6cf72')
  addLabel(list, 'BgDim', V.recordLine(state), '#8c8070')
end

local function renderSeason(list)
  local season = state.season
  if not season then
    addLabel(list, 'BgWrap', tr('PvP seasons are not running on this server.'), '#8c8070')
    return
  end
  addLabel(list, 'BgHead', tr('PvP Season %d: ends in %s', season.id or 1, V.span((season.endsIn or 0) - (now() - stateAt))), '#ff9a3c')
  addLabel(list, 'BgWrap', tr('A season lasts %d weeks. Each bracket has its own rating; the first %d rated matches place you. At the ' ..
    'end the best placed bracket decides your tier and rewards, then every rating is pulled halfway back to 1500. Ratings of %d and ' ..
    'more lose %d a week after %d days without a rated match of that bracket (never below %d).', season.weeks or 8, season.placement or 5,
    season.decay and season.decay.from or 2000, season.decay and season.decay.perWeek or 30, season.decay and season.decay.graceDays or 14,
    season.decay and season.decay.from or 2000), '#b8ab92')
  addCards(list)
  addLabel(list, 'BgHead', tr('Season rewards by tier'), '#e8b84a')
  for _, r in ipairs(V.rewardRows(season.tiers, season.id)) do
    local row = addRow(list, r.image, r.name, r.text, r.from)
    row:getChildById('title'):setColor(r.color)
  end
end

local function renderVendor(list)
  addLabel(list, 'BgHead', V.honorLine(state), '#f6cf72')
  addLabel(list, 'BgWrap', tr('Honor comes from battleground matches (win, loss, downs, wells taken, the weekly first win) and the ' ..
    'season rewards. The vendor sells cosmetics and consumables only.'), '#8c8070')
  for _, o in ipairs(type(state.vendor) == 'table' and state.vendor or {}) do
    local r = V.vendorRow(o, state.honor)
    local key = o.key
    local icon = o.kind == 'item' and tonumber(o.item) or '/images/chaos/battleground/honor'
    addRow(list, icon, r.title, r.sub, nil, r.button, function() send('buy', { key = key }) end, r.can)
  end
end

function render()
  if not window or not state then return end
  local list = child(window, 'list')
  list:destroyChildren()
  for name, id in pairs({ queue = 'tabQueue', season = 'tabSeason', vendor = 'tabVendor' }) do
    child(window, id):setChecked(name == tab)
  end
  if tab == 'season' then
    renderSeason(list)
  elseif tab == 'vendor' then
    renderVendor(list)
  else
    renderQueue(list)
  end
  local q = child(window, 'queueButton')
  if type(state.match) == 'table' then
    q:setText(tr('Leave Match'))
    q:setTooltip(tr('Leaving a running match makes you a deserter: a loss, no rewards and no queue for a while.'))
    q:setEnabled(true)
  elseif type(state.queue) == 'table' then
    q:setText(tr('Leave Queue'))
    q:setTooltip('')
    q:setEnabled(true)
  else
    q:setText(tr('Queue'))
    q:setTooltip(tr('Queue in a protection zone, out of combat.'))
    q:setEnabled(state.bracket ~= nil and (tonumber(state.deserter) or 0) <= 0)
  end
end

function showTab(name)
  tab = name
  render()
end

function hide()
  if window then window:hide() end
end

function toggle()
  if window and window:isVisible() then
    hide()
  else
    send('open')
  end
end

function queueOrLeave()
  if not state then return end
  if type(state.match) == 'table' then
    local box
    box = displayGeneralBox(tr('Leave the battleground'), tr('Leave the match now? You become a deserter: a loss, no rewards and no queue for a while.'),
      { { text = tr('Leave'), callback = function() box:destroy(); send('leave') end },
        { text = tr('Stay'), callback = function() box:destroy() end } })
  elseif type(state.queue) == 'table' then
    send('leave')
  else
    send('queue', { role = state.role })
  end
end

function findGroup()
  local pf = modules.game_partyfinder
  if pf and pf.show then
    pf.show()
  elseif pf and pf.toggle then
    pf.toggle()
  end
end

local function updateStatus()
  if not window or not window:isVisible() or not state or tab ~= 'queue' then return end
  local status = child(window, 'status')
  if status then
    local text, color = V.queueStatus(state, now() - stateAt)
    status:setText(text)
    status:setColor(color)
  end
end

local function onState(d)
  state = d
  stateAt = now()
  if not window then return end
  if d.open then
    child(window, 'message'):setText('')
    window:show()
    window:raise()
    window:focus()
  end
  if window:isVisible() then render() end
end

-- ---------------------------------------------------------------- HUD
local function renderHud()
  if not hud or not hudData then return end
  local d = hudData
  myTeam = tonumber(d.team) or myTeam
  local other = 3 - myTeam
  local teams = d.teams or { 'Team 1', 'Team 2' }
  local colors = d.colors or { '#ff9a3c', '#8fb8ff' }
  local score = d.score or { 0, 0 }
  local players = d.players or { 0, 0 }
  local myName, theirName = child(hud, 'myName'), child(hud, 'theirName')
  myName:setText(string.format('%s (%d)', teams[myTeam] or '?', players[myTeam] or 0))
  myName:setColor(colors[myTeam])
  theirName:setText(string.format('%s (%d)', teams[other] or '?', players[other] or 0))
  theirName:setColor(colors[other])
  for id, t in pairs({ myBar = myTeam, theirBar = other }) do
    local bar = child(hud, id)
    bar:setPercent(V.scorePercent(score[t], d.win))
    bar:setText(string.format('%d / %d', score[t] or 0, d.win or 1000))
    bar:setBackgroundColor(colors[t])
  end
  local elapsed = now() - hudAt
  local shown = {}
  for k, v in pairs(d) do shown[k] = v end
  shown.left = math.max(0, (tonumber(d.left) or 0) - elapsed)
  if d.respawn then shown.respawn = math.max(0, d.respawn - elapsed) end
  if d.afk then shown.afk = math.max(0, d.afk - elapsed) end
  local big, small = V.hudCenter(shown)
  child(hud, 'clock'):setText(big)
  child(hud, 'clock'):setColor(d.phase == 'prep' and '#e03a1e' or '#f6cf72')
  child(hud, 'phase'):setText(tr(small))
  local wells = child(hud, 'wells')
  local list = d.braziers or {}
  if wells:getChildCount() ~= #list then
    wells:destroyChildren()
    for _ = 1, #list do g_ui.createWidget('BgWell', wells) end
  end
  for i, b in ipairs(list) do
    local w = wells:getChildByIndex(i)
    local s = V.brazierState(b, teams, colors)
    w:getChildById('icon'):setImageSource(s.image)
    w:getChildById('name'):setText(s.name)
    w:getChildById('state'):setText(s.text)
    w:getChildById('state'):setColor(s.color)
  end
  local text, color = V.hudNotice(shown)
  child(hud, 'notice'):setText(text)
  child(hud, 'notice'):setColor(color)
end

local function stopTick()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

local function tick()
  tickEvent = nil
  updateStatus()
  if hudData and hud and hud:isVisible() then renderHud() end
  tickEvent = scheduleEvent(tick, 1000)
end

local function onHud(d)
  hudData = d
  hudAt = now()
  if hud and not hud:isVisible() then
    hud:show()
    hud:raise()
  end
  renderHud()
end

local function hideHud()
  if hud then hud:hide() end
  hudData = nil
end

-- ---------------------------------------------------------------- scoreboard and summary
local function renderBoard()
  if not board then return end
  local data = summary or lastBoard
  if not data then return end
  local list = child(board, 'list')
  list:destroyChildren()
  local teams = data.teams or { 'Team 1', 'Team 2' }
  local team = tonumber(data.team) or myTeam
  if summary then
    local s = V.summary(summary, myTeam)
    child(board, 'result'):setText(s.title)
    child(board, 'result'):setColor(s.color)
    child(board, 'score'):setText(s.score)
    child(board, 'rating'):setText(s.rating ~= '' and (s.rating .. '   ' .. tr('(%s)', s.reason)) or tr('(%s)', s.reason))
    child(board, 'honor'):setText(s.honor)
    board:setText(tr('Ember Wells: Summary'))
  else
    child(board, 'result'):setText(tr('Scoreboard'))
    child(board, 'result'):setColor('#e8b84a')
    local sc = data.score or { 0, 0 }
    child(board, 'score'):setText(string.format('%s %d  -  %d %s', teams[team] or '?', sc[team] or 0, sc[3 - team] or 0, teams[3 - team] or '?'))
    child(board, 'rating'):setText('')
    child(board, 'honor'):setText('')
    board:setText(tr('Ember Wells: Scoreboard'))
  end
  local sides = V.boardSides(data.rows, team)
  local header = { name = tr('Name'), role = tr('Role'), kills = 'K', assists = 'A', downs = 'D', captures = tr('Wells'),
    damage = tr('Damage'), healing = tr('Healing'), honor = summary and tr('Honor') or '' }
  for side = 1, 2 do
    local head = g_ui.createWidget('BgBoardHead', list)
    local t = side == 1 and team or 3 - team
    head:getChildById('team'):setText(string.format('%s%s', teams[t] or '?', side == 1 and tr(' (your team)') or ''))
    head:getChildById('team'):setColor(side == 1 and '#f6cf72' or '#e03a1e')
    local hr = g_ui.createWidget('BgBoardRow', list)
    for id, text in pairs(header) do
      hr:getChildById(id):setText(text)
      hr:getChildById(id):setColor('#8c8070')
    end
    for _, r in ipairs(sides[side]) do
      local row = g_ui.createWidget('BgBoardRow', list)
      for _, id in ipairs({ 'name', 'kills', 'assists', 'downs', 'captures', 'damage', 'healing', 'honor' }) do
        row:getChildById(id):setText(tostring(r[id]))
      end
      row:getChildById('role'):setText(r.role)
      row:getChildById('role'):setColor(r.roleColor)
      if r.left then row:getChildById('name'):setColor('#6b6258') end
    end
  end
end

function toggleBoard()
  if not board then return end
  if board:isVisible() then
    hideBoard()
    return
  end
  summary = nil
  send('board')
  renderBoard()
  board:show()
  board:raise()
end

function hideBoard()
  if board then board:hide() end
end

local function onStart(d)
  myTeam = tonumber(d.team) or 1
  summary = nil
  if g_game.isSafeFight then
    secureBefore = g_game.isSafeFight()
    if secureBefore then g_game.setSafeFight(false) end
  end
  hide()
  hideBoard()
end

local function onEnd(d)
  g_game.cancelAttack()
  if secureBefore and g_game.setSafeFight then g_game.setSafeFight(true) end
  secureBefore = nil
  summary = d
  if board then
    renderBoard()
    board:show()
    board:raise()
  end
  hideHud()
end

local function message(text, ok)
  if window and window:isVisible() then
    local m = child(window, 'message')
    m:setText(tostring(text or ''))
    m:setColor(ok and '#9fd89f' or '#f6cf72')
  elseif modules.game_textmessage and text then
    modules.game_textmessage.displayFailureMessage(tostring(text))
  end
end

-- ---------------------------------------------------------------- protocol
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local d = type(msg.data) == 'table' and msg.data or {}
  local a = msg.action
  if a == 'state' then
    onState(d)
  elseif a == 'start' then
    onStart(d)
  elseif a == 'hud' then
    onHud(d)
  elseif a == 'board' then
    lastBoard = d
    if board and board:isVisible() and not summary then renderBoard() end
  elseif a == 'alert' then
    if modules.game_textmessage and d.text then
      modules.game_textmessage.displayGameMessage(tostring(d.text))
    end
  elseif a == 'end' then
    onEnd(d)
  elseif a == 'msg' then
    message(d.text, d.ok)
  end
end

-- offline rendering and tests: feed a server message as if it came on the opcode
function receive(msg)
  onMessage(nil, OPCODE, type(msg) == 'string' and json.decode(msg) or msg)
end

function getState()
  return { window = window and window:isVisible() or false, hud = hud and hud:isVisible() or false,
    board = board and board:isVisible() or false, tab = tab, team = myTeam }
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'adventure',
      { text = 'Battleground', icon = 'pvp', modules = { 'game_battleground' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  addMenu()
  send('query')
end

local function onGameEnd()
  hide()
  hideHud()
  hideBoard()
  state, summary, lastBoard, secureBefore = nil, nil, nil, nil
end

function init()
  g_ui.importStyle('battleground')
  handlers.opcode = safe('opcode', onMessage)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  local function make(style, parent)
    local ok, w = pcall(g_ui.createWidget, style, parent)
    if ok and w then
      w:hide()
      return w
    end
    g_logger.warning('[battleground] ' .. style .. ' not loaded: ' .. tostring(w))
    return nil
  end
  hud = make('BgHud', modules.game_interface.getRootPanel())
  window = make('BgWindow', rootWidget)
  board = make('BgBoard', rootWidget)
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  if g_game.isOnline() then onGameStart() end
  tick()
end

function terminate()
  disconnect(g_game, handlers.game or {})
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  stopTick()
  for _, w in ipairs({ hud, window, board }) do
    if w then w:destroy() end
  end
  hud, window, board, state, hudData, summary, lastBoard = nil, nil, nil, nil, nil, nil, nil
  handlers = {}
end
