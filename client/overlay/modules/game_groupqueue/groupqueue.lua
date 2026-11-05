-- The Group Queue (O407): one window to join the arena (1v1 / 2v2 / 3v3 by party size), the battleground and a dungeon
-- at once, and the ready check popup that every party member gets when a queue pops. The server keeps the queues of
-- each mode (arena.lua, battleground.lua, dungeons.lua); this window only picks.
-- Server: server/data/scripts/chaos/groupqueue.lua, extended opcode 160 (JSON {action, data}).
--   client -> server  open | query | join {arena?, bg?, dungeon? {id, difficulty}} | leave | accept | decline | raid
--   server -> client  state {...}, check {key, label, left, seconds, accepted, total, mine}, checkEnd, msg {text}
-- Pure helpers: gqview.lua (gqview_test.lua). The top menu: Adventure > Group Queue.

local OPCODE = 160
local V = GqView

local window, popup
local state, stateAt = nil, 0
local checkData, checkAt = nil, 0
local sel = { arena = nil, bg = false, dungeon = false, dungeonId = nil, difficulty = 1 }
local filling = false
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
        g_logger.warning('[groupqueue] ' .. name .. ': ' .. tostring(res))
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

local function dungeonById(id)
  for _, d in ipairs(state and type(state.dungeons) == 'table' and state.dungeons or {}) do
    if d.id == id then return d end
  end
  return nil
end

-- ---------------------------------------------------------------- the window
local function fillDifficulties()
  local combo = child(window, 'diffCombo')
  if not combo then return end
  filling = true
  combo:clearOptions()
  local list = V.difficulties(dungeonById(sel.dungeonId))
  local keep = false
  for _, d in ipairs(list) do
    combo:addOption(tr('Difficulty %d', d), d)
    if d == sel.difficulty then keep = true end
  end
  if not keep then sel.difficulty = list[#list] end
  combo:setCurrentOption(tr('Difficulty %d', sel.difficulty))
  filling = false
end

local function fillDungeons()
  local combo = child(window, 'dungeonCombo')
  if not combo then return end
  filling = true
  combo:clearOptions()
  local list = state and type(state.dungeons) == 'table' and state.dungeons or {}
  local current
  for _, d in ipairs(list) do
    local text = tr('%s (level %d)', tostring(d.title), tonumber(d.level) or 1)
    combo:addOption(text, d.id)
    if d.id == sel.dungeonId or not sel.dungeonId then
      sel.dungeonId = d.id
      current = text
    end
  end
  if current then combo:setCurrentOption(current) end
  filling = false
  fillDifficulties()
end

local function renderArena()
  local row = child(window, 'arenaRow')
  if not row then return end
  row:destroyChildren()
  for _, o in ipairs(V.arenaOptions(state, sel)) do
    local b = g_ui.createWidget('GqArenaButton', row)
    b:setText(o.mode)
    b:setTooltip(o.tooltip)
    b:setEnabled(o.enabled)
    b:setChecked(o.checked)
    local mode = o.mode
    b.onClick = function()
      sel.arena = sel.arena ~= mode and mode or nil
      render()
    end
  end
end

local function renderStatus()
  local list = child(window, 'statusList')
  if not list then return end
  list:destroyChildren()
  for _, line in ipairs(V.statusLines(state, now() - stateAt)) do
    local l = g_ui.createWidget('GqWrap', list)
    l:setText(line.text)
    l:setColor(line.color)
  end
end

function render()
  if not window or not state then return end
  -- a size that no longer fits (the party changed) drops the arena pick
  if sel.arena and V.ARENA_SIZE[sel.arena] ~= (tonumber(state.size) or 1) then sel.arena = nil end
  renderArena()
  local edit = V.canEdit(state)
  local bg = child(window, 'bgCheck')
  filling = true
  bg:setChecked(sel.bg)
  bg:setEnabled(edit)
  local dc = child(window, 'dungeonCheck')
  dc:setChecked(sel.dungeon)
  dc:setEnabled(edit and type(state.dungeons) == 'table' and #state.dungeons > 0)
  filling = false
  child(window, 'dungeonCombo'):setEnabled(edit and sel.dungeon)
  child(window, 'diffCombo'):setEnabled(edit and sel.dungeon)
  renderStatus()
  local join = child(window, 'joinButton')
  if V.inGroup(state) then
    join:setText(tr('Leave Queues'))
    join:setTooltip(tr('Leave every queue of the Group Queue (the whole party leaves).'))
    join:setEnabled(true)
  else
    local ok, why = V.joinable(state, sel)
    join:setText(tr('Join Queues'))
    join:setTooltip(why ~= '' and why or tr('Queue in a protection zone, out of combat.'))
    join:setEnabled(ok)
  end
  local raid = child(window, 'raidButton')
  raid:setVisible(state.raid == true)
  raid:setEnabled(state.inParty == true and state.leader == true and not V.inGroup(state))
end

function onChoice()
  if filling or not window then return end
  sel.bg = child(window, 'bgCheck'):isChecked()
  sel.dungeon = child(window, 'dungeonCheck'):isChecked()
  render()
end

local function onDungeonChange(_, _, data)
  if filling then return end
  sel.dungeonId = tonumber(data)
  fillDifficulties()
  render()
end

local function onDifficultyChange(_, _, data)
  if filling then return end
  sel.difficulty = tonumber(data) or 1
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

function show()
  send('open')
end

function joinOrLeave()
  if not state then return end
  if V.inGroup(state) then
    send('leave')
  elseif V.joinable(state, sel) then
    send('join', V.payload(sel))
  end
end

function raidCheck()
  send('raid')
end

function findGroup()
  local pf = modules.game_partyfinder
  if pf and pf.show then
    pf.show()
  elseif pf and pf.toggle then
    pf.toggle()
  end
end

-- ---------------------------------------------------------------- the ready check popup
local function renderCheck()
  if not popup then return end
  local c = V.check(checkData, now() - checkAt, checkData and checkData.seconds)
  if not c then
    popup:hide()
    return
  end
  child(popup, 'checkTitle'):setText(c.title)
  child(popup, 'checkSub'):setText(c.sub)
  local bar = child(popup, 'checkBar')
  bar:setPercent(c.percent)
  bar:setText(c.timer)
  child(popup, 'acceptButton'):setEnabled(not c.answered)
  child(popup, 'declineButton'):setEnabled(not c.answered)
  if c.left <= 0 then popup:hide() end
end

function answer(yes)
  send(yes and 'accept' or 'decline')
  if not yes and popup then popup:hide() end
end

local function stopTick()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

local function tick()
  tickEvent = nil
  if popup and popup:isVisible() then renderCheck() end
  if window and window:isVisible() and state then renderStatus() end
  tickEvent = scheduleEvent(safe('tick', tick), 1000)
end

-- ---------------------------------------------------------------- the server
local function onState(d)
  state = d
  stateAt = now()
  if not window then return end
  if type(d.dungeons) == 'table' then fillDungeons() end
  if d.open then
    child(window, 'message'):setText('')
    window:show()
    window:raise()
    window:focus()
  end
  render()
end

local function onCheck(d)
  checkData, checkAt = d, now()
  if not popup then return end
  if not popup:isVisible() then
    popup:show()
    popup:raise()
    popup:focus()
  end
  renderCheck()
end

local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local d = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    onState(d)
  elseif msg.action == 'check' then
    onCheck(d)
  elseif msg.action == 'checkEnd' then
    checkData = nil
    if popup then popup:hide() end
    send('query')
  elseif msg.action == 'msg' then
    if window then child(window, 'message'):setText(tostring(d.text or '')) end
  end
end

function receive(msg)
  onMessage(nil, OPCODE, type(msg) == 'string' and json.decode(msg) or msg)
end

function getState()
  return { window = window and window:isVisible() or false, popup = popup and popup:isVisible() or false,
    queued = V.inGroup(state) }
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'adventure',
      { text = 'Group Queue', icon = 'pvp', modules = { 'game_groupqueue' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  addMenu()
  send('query')
end

local function onGameEnd()
  hide()
  if popup then popup:hide() end
  state, checkData = nil, nil
  sel = { arena = nil, bg = false, dungeon = false, dungeonId = nil, difficulty = 1 }
end

function init()
  g_ui.importStyle('groupqueue')
  handlers.opcode = safe('opcode', onMessage)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  local function make(style)
    local ok, w = pcall(g_ui.createWidget, style, rootWidget)
    if ok and w then
      w:hide()
      return w
    end
    g_logger.warning('[groupqueue] ' .. style .. ' not loaded: ' .. tostring(w))
    return nil
  end
  window = make('GqWindow')
  popup = make('GqCheckWindow')
  if window then
    child(window, 'dungeonCombo').onOptionChange = safe('dungeon', onDungeonChange)
    child(window, 'diffCombo').onOptionChange = safe('difficulty', onDifficultyChange)
  end
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  if g_game.isOnline() then onGameStart() end
  tick()
end

function terminate()
  disconnect(g_game, handlers.game or {})
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  stopTick()
  for _, w in ipairs({ window, popup }) do
    if w then w:destroy() end
  end
  window, popup, state, checkData = nil, nil, nil, nil
  handlers = {}
end
