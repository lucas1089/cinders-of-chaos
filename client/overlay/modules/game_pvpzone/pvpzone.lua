-- The Scorched Marches, the open-world PvP zone: the window (rules, the shrine, the faction pledge, the embers vendor),
-- the entry confirmation (the rules and the risk, "I understand", Hardcore refused) and the HUD (embers carried, the
-- shrine contest timer, the holding faction, protection and the exit channel).
-- Server: server/data/scripts/chaos/pvpzone.lua, extended opcode 193 (JSON {action, data}, chunked by Chaos.sendChunked
-- and joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | query | enter {accept, hcAccept} | pledge {faction} | buy {key}
--   server -> client  state {...} (open, confirm) | hud {...} | hide {why} | enter {} | msg {text, ok}
-- Pure helpers: pvpzoneview.lua (pvpzoneview_test.lua). The top menu: Adventure > Scorched Marches.

local OPCODE = 193
local V = PvpZoneView

local window, confirm, hud
local state
local hudData, hudAt = nil, 0
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
        g_logger.warning('[pvpzone] ' .. name .. ': ' .. tostring(res))
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

local function addRow(list, icon, title, sub, button, onClick, enabled, tooltip)
  local row = g_ui.createWidget('PzRow', list)
  local ic = row:getChildById('icon')
  if type(icon) == 'number' then
    local item = g_ui.createWidget('UIItem', ic)
    item:fill('parent')
    item:setItemId(icon)
    item:setVirtual(true)
    item:setPhantom(true)
  end
  row:getChildById('title'):setText(title)
  row:getChildById('sub'):setText(sub or '')
  row:setTooltip(tooltip or sub or '')
  local b = row:getChildById('button')
  b:setText(button)
  b:setEnabled(enabled ~= false)
  b.onClick = onClick
  return row
end

-- ---------------------------------------------------------------- the window
local function render()
  if not window or not state then return end
  local list = child(window, 'list')
  list:destroyChildren()
  local s = state
  addLabel(list, 'PzHead', tr('Open PvP, risk and reward'), '#ff7a2a')
  addLabel(list, 'PzWrap', tr('Level %d+. Everyone in the Marches can attack you, whatever the world\'s rules. Nobody dies: a ' ..
    'defeat throws you out and drops the embers you carry; your killer may take them. Bank them by standing %ds in a safe exit ' ..
    'circle. Monsters have x%.1f health, x%.2f damage and give x%.1f experience and x%.1f loot. No equipment or experience ' ..
    'is ever lost here.', s.minLevel or 150, s.exitSeconds or 5, s.monsters and s.monsters.hp or 1, s.monsters and s.monsters.damage or 1,
    s.monsters and s.monsters.exp or 1, s.monsters and s.monsters.loot or 1), '#b8ab92')
  if s.hc and s.hc.isHc then
    addLabel(list, 'PzWrap', s.hc.allow and tr('Hardcore: a defeat here may end your Hardcore run.') or
      tr('Hardcore characters cannot enter the Marches: a Hardcore life is not staked in open PvP.'), '#ff5a5a')
  end
  addLabel(list, 'PzHead', tr('The Cinder Shrine'), '#e8b84a')
  local line, col = V.contestLine(s.contest)
  addLabel(list, 'PzText', line, col)
  line, col = V.holderLine(s.contest)
  addLabel(list, 'PzText', line, col)
  addLabel(list, 'PzWrap', tr('Every %s the Shrine Warden rises. Slay it, then hold the circle with your faction: the holder\'s ' ..
    'faction gets +%d%% experience and +%d%% loot everywhere for %d minutes.', V.span((s.everyMinutes or 120) * 60),
    s.buff and s.buff.exp or 0, s.buff and s.buff.loot or 0, s.holdMinutes or 60), '#8c8070')
  addLabel(list, 'PzHead', tr('Your pledge'), '#e8b84a')
  addLabel(list, 'PzWrap', tr('Defeating a player pledged to another faction gives %d reputation (the sworn rival full, the others half), ' ..
    'at most %d a day (today %d). Unpledged players earn no reputation and cannot take the shrine.', s.repPerKill or 0,
    s.repDailyCap or 0, s.repToday or 0), '#8c8070')
  for _, f in ipairs(s.factions or {}) do
    local name, btn, enabled, tip = V.factionRow(f, s)
    local key = f.key
    local row = addRow(list, nil, name, tip, btn, function() send('pledge', { faction = key }) end, enabled, tip)
    row:getChildById('title'):setColor(f.color or '#e8b84a')
  end
  addLabel(list, 'PzHead', tr('Embers vendor'), '#e8b84a')
  addLabel(list, 'PzText', tr('Banked: %s embers   Carried: %s / %s', V.number(s.banked), V.number(s.carried), V.number(s.carryMax)),
    '#f6cf72')
  for _, o in ipairs(s.vendor or {}) do
    local sub, btn, enabled = V.vendorRow(o, s.banked)
    local key = o.key
    addRow(list, o.kind == 'item' and o.id or nil, o.name, sub, btn, function() send('buy', { key = key }) end, enabled, o.why)
  end
  addLabel(list, 'PzHead', tr('Record'), '#e8b84a')
  addLabel(list, 'PzWrap', V.recordLine(s), '#8c8070')
  local text, enabled, tip = V.enterButton(s)
  local b = child(window, 'enterButton')
  b:setText(tr(text))
  b:setEnabled(enabled)
  b:setTooltip(tip)
  if not enabled and tip and tip ~= '' and not s.inside then
    child(window, 'message'):setText(tip)
  end
end

function hide()
  if window then window:hide() end
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
end

function toggle()
  if window and window:isVisible() then
    hide()
    return
  end
  send('open')
end

-- ---------------------------------------------------------------- the confirmation
local function updateConfirm()
  if not confirm or not state then return end
  local ok = V.canConfirm(state, child(confirm, 'accept'):isChecked(), child(confirm, 'hcAccept'):isChecked())
  child(confirm, 'confirmButton'):setEnabled(ok and state.canEnter ~= false)
end

function askEnter()
  if not confirm or not state then return end
  child(confirm, 'risk'):setText(V.riskText(state))
  child(confirm, 'accept'):setChecked(false)
  local hc = child(confirm, 'hcAccept')
  hc:setChecked(false)
  hc:setVisible(state.hc and state.hc.isHc and state.hc.allow or false)
  updateConfirm()
  confirm:show()
  confirm:raise()
  confirm:focus()
end

function hideConfirm()
  if confirm then confirm:hide() end
end

function confirmEnter()
  if not confirm or not state then return end
  local accepted, hcAccepted = child(confirm, 'accept'):isChecked(), child(confirm, 'hcAccept'):isChecked()
  if not V.canConfirm(state, accepted, hcAccepted) then return end
  send('enter', { accept = true, hcAccept = hcAccepted or nil })
  hideConfirm()
end

-- ---------------------------------------------------------------- the HUD
local function renderHud()
  if not hud or not hudData then return end
  local d = hudData
  local elapsed = math.max(0, math.floor(now() - hudAt))
  local bar = child(hud, 'embers')
  local pct, col = V.carryPercent(d)
  bar:setPercent(pct)
  bar:setBackgroundColor(col)
  bar:setText(V.embersLine(d))
  local text, color = V.pledgeLine(d.pledge)
  child(hud, 'pledge'):setText(text)
  child(hud, 'pledge'):setColor(color)
  local c = {}
  for k, v in pairs(d.contest or {}) do c[k] = v end
  c.left = math.max(0, (tonumber(c.left) or 0) - elapsed)
  text, color = V.contestLine(c)
  child(hud, 'contest'):setText(text)
  child(hud, 'contest'):setColor(color)
  text, color = V.holderLine(d.contest)
  child(hud, 'holder'):setText(text)
  child(hud, 'holder'):setColor(color)
  local st = {}
  for k, v in pairs(d) do st[k] = v end
  if st.protect then st.protect = math.max(0, st.protect - elapsed) end
  text, color = V.statusLine(st)
  child(hud, 'status'):setText(text)
  child(hud, 'status'):setColor(color)
end

local function stopTick()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

local function tick()
  tickEvent = nil
  safe('tick', renderHud)()
  if hud and hud:isVisible() then tickEvent = scheduleEvent(tick, 500) end
end

local function hideHud()
  stopTick()
  if hud then hud:hide() end
  hudData = nil
end

-- in the zone: secure mode off (open PvP); back on when leaving if it was on
local function secureOff()
  if g_game.isSafeFight and secureBefore == nil then
    secureBefore = g_game.isSafeFight()
    if secureBefore then g_game.setSafeFight(false) end
  end
end

local function secureRestore()
  if secureBefore and g_game.setSafeFight then g_game.setSafeFight(true) end
  secureBefore = nil
end

local function onHud(d)
  hudData, hudAt = d, now()
  if hud then
    hud:show()
    hud:raise()
  end
  secureOff()
  renderHud()
  if not tickEvent then tick() end
end

-- ---------------------------------------------------------------- protocol
local function message(text, ok)
  if window and window:isVisible() then
    local m = child(window, 'message')
    m:setText(tostring(text or ''))
    m:setColor(ok and '#9fd89f' or '#f6cf72')
  elseif modules.game_textmessage and text then
    modules.game_textmessage.displayFailureMessage(tostring(text))
  end
end

local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local d = type(msg.data) == 'table' and msg.data or {}
  local a = msg.action
  if a == 'state' then
    state = d
    if window and (d.open or d.confirm or window:isVisible()) then
      render()
      if d.open or d.confirm then show() end
    end
    if d.confirm then askEnter() end
    if confirm and confirm:isVisible() then updateConfirm() end
  elseif a == 'hud' then
    onHud(d)
  elseif a == 'enter' then
    secureOff()
    hide()
  elseif a == 'hide' then
    hideHud()
    secureRestore()
  elseif a == 'msg' then
    message(d.text, d.ok)
  end
end

-- offline rendering and tests: feed a server message as if it came on the opcode
function receive(msg)
  onMessage(nil, OPCODE, type(msg) == 'string' and json.decode(msg) or msg)
end

function getState()
  return { window = window and window:isVisible() or false, confirm = confirm and confirm:isVisible() or false,
    hud = hud and hud:isVisible() or false }
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'adventure',
      { text = 'Scorched Marches', icon = 'pvp', modules = { 'game_pvpzone' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  addMenu()
  send('query')
end

local function onGameEnd()
  hide()
  hideConfirm()
  hideHud()
  state, secureBefore = nil, nil
end

function init()
  g_ui.importStyle('pvpzone')
  handlers.opcode = safe('opcode', onMessage)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  local function make(style, parent)
    local ok, w = pcall(g_ui.createWidget, style, parent)
    if ok and w then
      w:hide()
      return w
    end
    g_logger.warning('[pvpzone] ' .. style .. ' not loaded: ' .. tostring(w))
    return nil
  end
  hud = make('PzHud', modules.game_interface.getRootPanel())
  window = make('PzWindow', rootWidget)
  confirm = make('PzConfirm', rootWidget)
  if confirm then
    for _, id in ipairs({ 'accept', 'hcAccept' }) do
      child(confirm, id).onCheckChange = function() updateConfirm() end
    end
  end
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game or {})
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  stopTick()
  for _, w in ipairs({ hud, window, confirm }) do
    if w then w:destroy() end
  end
  hud, window, confirm, state, hudData = nil, nil, nil, nil, nil
  handlers = {}
end
