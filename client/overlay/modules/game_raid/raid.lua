-- The Ashen Sepulchre (the weekly raid): the raid window (this week's lockouts and saved raids, the boss journal, the
-- vendor), the in-raid HUD under the character plate and the mechanic call-outs over the map.
-- Server: server/data/scripts/chaos/raid.lua, extended opcode 213 (JSON {action, data}, chunked by Chaos.sendChunked and
-- joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | start | continue {id} | join {id} | leave | buy {key} | journal | query
--   server -> client  info, journal, hud, alert {text, kind}, loot {boss, eligible, lines}, end {text}, msg {text, ok},
--                     closeInfo (shapes in raidview.lua)
-- Pure helpers: raidview.lua (raidview_test.lua). The buff bar shows the boss debuffs (Sundered, Hexed, Withering Hex).

local OPCODE = 213
local V = RaidView

local window, hud, callout
local info, journal
local tab = 'lock'
local bossTab = 1
local data -- the last hud data
local receivedAt = 0
local tickEvent, hideEvent, calloutEvent
local handlers = {}
local reported = {}

local function now() return g_clock.seconds() end

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[raid] ' .. name .. ': ' .. tostring(res))
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

-- ---------------------------------------------------------------- the window
local function addLabel(parent, style, text, color)
  local l = g_ui.createWidget(style, parent)
  l:setText(text)
  if color then l:setColor(color) end
  return l
end

local function addRow(list, title, sub, state, button, onClick, enabled)
  local row = g_ui.createWidget('RaidRow', list)
  row:getChildById('title'):setText(title)
  row:getChildById('sub'):setText(sub or '')
  row:setTooltip(sub or '')
  row:getChildById('state'):setText(state or '')
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

local function renderLock(list)
  addLabel(list, 'RaidHead', tr('Loot lockouts'), '#e8b84a')
  addLabel(list, 'RaidWrap', V.lockSummary(info), '#b8ab92')
  for _, r in ipairs(V.lockRows(info)) do
    local row = addRow(list, r.text, r.looted and tr('You can still help others: no loot until the reset.') or
      tr('Kill it this week for personal loot.'), r.state)
    row:getChildById('state'):setColor(r.color)
  end
  addLabel(list, 'RaidHead', tr('Raids of this week'), '#e8b84a')
  local saved = {} -- the saved raids; an entry that is no table is left out
  for _, s in ipairs(type(info.saved) == 'table' and info.saved or {}) do
    if type(s) == 'table' then saved[#saved + 1] = s end
  end
  if #saved == 0 then
    addLabel(list, 'RaidWrap', tr('No raid of yours this week. Open a new one alone or with a party of up to 15.'), '#8c8070')
  end
  for _, s in ipairs(saved) do
    local r = V.savedRow(s)
    local id = s.id
    local action = r.action
    local row = addRow(list, r.title, r.progress, r.next, action and V.actionText(action) or nil, function()
      if action == 'continue' then send('continue', { id = id }) elseif action == 'join' then send('join', { id = id }) end
    end, action == 'continue' or action == 'join')
    row:getChildById('title'):setColor(r.color)
  end
end

local function renderJournal(list)
  if type(journal) ~= 'table' then
    addLabel(list, 'RaidWrap', tr('Loading the journal...'), '#8c8070')
    send('journal')
    return
  end
  local bar = g_ui.createWidget('UIWidget', list)
  bar:setHeight(24)
  bar:setLayout(UIHorizontalLayout.create(bar))
  for i, b in ipairs(journal) do
    local t = g_ui.createWidget('RaidBossTab', bar)
    t:setText(tostring(i))
    t:setWidth(32)
    t:setTooltip(tostring(b.n or ''))
    t:setChecked(i == bossTab)
    t.onClick = function()
      bossTab = i
      modules.game_raid.render()
    end
  end
  local j = V.journalBoss(journal[bossTab] or journal[1], bossTab)
  addLabel(list, 'RaidHead', j.title, '#ff9a3c')
  addLabel(list, 'RaidWrap', j.intro, '#b8ab92')
  addLabel(list, 'RaidWrap', j.roles, '#9fd8ff')
  addLabel(list, 'RaidWrap', j.phases, '#d6c9ae')
  addLabel(list, 'RaidHead', tr('Mechanics'), '#e8b84a')
  for _, m in ipairs(j.mech) do addLabel(list, 'RaidWrap', m) end
  addLabel(list, 'RaidHead', tr('Personal loot (once a week per character)'), '#e8b84a')
  for _, l in ipairs(j.loot) do addLabel(list, 'RaidWrap', '- ' .. l, '#c8bca2') end
end

local function renderVendor(list)
  local v = type(info.vendor) == 'table' and info.vendor or {}
  addLabel(list, 'RaidHead', tr('Sepulchre Marks: %s', V.number(v.marks)), '#ff9a3c')
  addLabel(list, 'RaidWrap', tr('The stock changes with the weekly reset. Gear is fixed: these modifiers at these tiers.'),
    '#8c8070')
  for _, e in ipairs(type(v.stock) == 'table' and v.stock or {}) do
    local r = V.vendorRow(e, v.marks)
    local key = e.k
    addRow(list, r.name, r.sub, r.limit, r.button, function() send('buy', { key = key }) end, r.can)
  end
end

function render()
  if not window or not info then return end
  local list = child(window, 'list')
  list:destroyChildren()
  for name, id in pairs({ lock = 'tabLock', journal = 'tabJournal', vendor = 'tabVendor' }) do
    child(window, id):setChecked(name == tab)
  end
  child(window, 'record'):setText(V.recordLine(info))
  if tab == 'journal' then
    renderJournal(list)
  elseif tab == 'vendor' then
    renderVendor(list)
  else
    renderLock(list)
  end
  local st = V.startState(info)
  local start = child(window, 'startButton')
  start:setText(st.text)
  start:setEnabled(st.can)
  start:setTooltip(st.why or '')
  child(window, 'leaveButton'):setVisible(info.inRaid == true)
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

function start()
  send('start')
end

function leave()
  send('leave')
end

local function onInfo(d)
  info = d
  if not window then return end
  if not window:isVisible() then child(window, 'message'):setText('') end
  render()
  window:show()
  window:raise()
  window:focus()
end

-- ---------------------------------------------------------------- HUD
local function place()
  local mapPanel = hud and hud:getParent()
  local plate = rootWidget:recursiveGetChildById('chaosHud')
  if not mapPanel or not plate or not plate:isVisible() then return end
  local r = plate:getRect()
  local bottom = r.y + r.height
  local buffs = rootWidget:recursiveGetChildById('buffBar')
  if buffs and buffs:isVisible() then
    local b = buffs:getRect()
    bottom = math.max(bottom, b.y + b.height)
  end
  local top = bottom + 8 - mapPanel:getY()
  if hud:getMarginTop() ~= top then hud:setMarginTop(top) end
end

local function updateClock()
  if not hud or not data then return end
  local left = V.left(data.enrage, receivedAt, now())
  local text, color = V.enrageText(data, left)
  local clock = child(hud, 'clock')
  clock:setText(text)
  clock:setColor(color)
  clock:setVisible(text ~= '')
end

local function stopTick()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

local function tick()
  tickEvent = nil
  updateClock()
  place()
  if data then tickEvent = scheduleEvent(tick, 500) end
end

local function renderHud()
  if not hud or not data then return end
  child(hud, 'title'):setText(V.hudTitle(data))
  child(hud, 'boss'):setText(V.bossLine(data))
  local bar = child(hud, 'bossBar')
  bar:setVisible(data.state == 'fight')
  bar:setPercent(tonumber(data.hp) or 100)
  bar:setText(string.format('%d%%', tonumber(data.hp) or 100))
  bar:setBackgroundColor(data.enraged and '#c01010' or '#8a1010')
  local phase = V.phaseLine(data)
  child(hud, 'phase'):setText(phase)
  child(hud, 'phase'):setVisible(phase ~= '')
  local prog = child(hud, 'progress')
  prog:setPercent(V.progress(data))
  prog:setText(tr('%d / %d bosses slain', tonumber(data.done) or 0, tonumber(data.total) or 0))
  prog:setBackgroundColor('#8a3a10')
  child(hud, 'counts'):setText(V.countsLine(data))
  local stacks = V.stacksLine(data)
  child(hud, 'stacks'):setText(stacks)
  child(hud, 'stacks'):setVisible(stacks ~= '')
  local alerts = child(hud, 'alerts')
  alerts:destroyChildren()
  for _, a in ipairs(type(data.alerts) == 'table' and data.alerts or {}) do
    g_ui.createWidget('RaidAlertLabel', alerts):setText(tostring(a))
  end
  updateClock()
end

local function hideHud()
  stopTick()
  if hideEvent then removeEvent(hideEvent) hideEvent = nil end
  if hud then hud:hide() end
  data = nil
end

local function onHud(d)
  local fresh = not data
  data = d
  receivedAt = now()
  if hideEvent then removeEvent(hideEvent) hideEvent = nil end
  if fresh or not hud:isVisible() then
    place()
    hud:show()
    hud:raise()
  end
  renderHud()
  stopTick()
  tick()
end

local function showCallout(text, kind)
  if not callout then return end
  callout:setText(tostring(text or ''))
  callout:setColor(V.alertColor(kind))
  callout:show()
  callout:raise()
  if calloutEvent then removeEvent(calloutEvent) end
  calloutEvent = scheduleEvent(function()
    calloutEvent = nil
    if callout then callout:hide() end
  end, V.alertSeconds(kind) * 1000)
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
  if a == 'info' then
    onInfo(d)
  elseif a == 'journal' then
    journal = type(d.bosses) == 'table' and d.bosses or {}
    if window and window:isVisible() and tab == 'journal' then render() end
  elseif a == 'hud' then
    onHud(d)
  elseif a == 'alert' then
    showCallout(d.text, d.kind)
  elseif a == 'loot' then
    showCallout(V.lootSummary(d), d.eligible and 'kill' or 'fall')
  elseif a == 'end' then
    showCallout(d.text, 'door')
    hideHud()
  elseif a == 'msg' then
    message(d.text, d.ok)
  elseif a == 'closeInfo' then
    hide()
  end
end

-- offline rendering and tests: feed a server message as if it came on the opcode
function receive(msg)
  onMessage(nil, OPCODE, type(msg) == 'string' and json.decode(msg) or msg)
end

function getState()
  return { window = window and window:isVisible() or false, hud = hud and hud:isVisible() or false, tab = tab,
    boss = data and data.boss or nil, callout = callout and callout:isVisible() and callout:getText() or nil }
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'adventure',
      { text = 'Raid: Ashen Sepulchre', icon = 'infinitytower', modules = { 'game_raid' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  addMenu()
  send('query')
end

local function onGameEnd()
  hide()
  hideHud()
  if callout then callout:hide() end
  info, journal = nil, nil
end

function init()
  g_ui.importStyle('raid')
  handlers.opcode = safe('opcode', onMessage)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  local function make(style, parent)
    local ok, w = pcall(g_ui.createWidget, style, parent)
    if ok and w then
      w:hide()
      return w
    end
    g_logger.warning('[raid] ' .. style .. ' not loaded: ' .. tostring(w))
    return nil
  end
  local map = modules.game_interface.getMapPanel()
  hud = make('RaidHud', map)
  callout = make('RaidCallout', map)
  window = make('RaidWindow', rootWidget)
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game or {})
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  stopTick()
  if hideEvent then removeEvent(hideEvent) hideEvent = nil end
  if calloutEvent then removeEvent(calloutEvent) calloutEvent = nil end
  for _, w in ipairs({ hud, callout, window }) do
    if w then w:destroy() end
  end
  hud, callout, window, data, info, journal = nil, nil, nil, nil, nil, nil
  handlers = {}
end
