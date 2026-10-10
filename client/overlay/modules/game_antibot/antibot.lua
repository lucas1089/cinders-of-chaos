-- game_antibot: the presence check modal and the Report Player dialog (server data/scripts/chaos/antibot.lua and
-- reports.lua, extended opcode 211, JSON {action, data}).
--   server -> client  check {t, w, o = [{k, c}], s, a, r} | checkResult {ok, retry, text} | reportOpen {name, reasons,
--                     noteMax} | reportResult {ok, text}
--   client -> server  answer {t, k} | another {t} | reportOpen {name} | report {name, reason, note}
-- The check shows four item pictures and a word; the client never learns which picture is right (only client ids and
-- random keys arrive). Report Player: right-click a player, or System > Report a Player (ChaosTopBar.addEntry).
-- Pure logic: antibot_logic.lua (antibot_logic_test.lua).

local OPCODE = 211
local L = AntibotLogic

local checkWindow, reportWindow
local current -- the parsed check on screen
local receivedAt, totalSeconds = 0, 75
local tickEvent, closeEvent, reportCloseEvent
local hooked, menuAdded = false, false
local reasons = L.DEFAULT_REASONS
local noteMax = L.NOTE_MAX
local reported = {}

local function now() return g_clock.seconds() end

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[antibot] ' .. name .. ': ' .. tostring(res))
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

local function cancel(ev)
  if ev then removeEvent(ev) end
  return nil
end

-- ---------------------------------------------------------------- presence check
local function secondsLeft()
  if not current then return 0 end
  return math.max(0, current.seconds - (now() - receivedAt))
end

local function setStatus(widget, text, color)
  widget.status:setText(text or '')
  widget.status:setColor(color or L.COLORS.text)
end

local function tick()
  tickEvent = nil
  if not checkWindow or not checkWindow:isVisible() or not current then return end
  local left = secondsLeft()
  local bar = checkWindow.timeBar
  bar:setPercent(L.timePercent(left, totalSeconds))
  bar:setText(L.timeText(left))
  bar:setColor(L.timeColor(left))
  tickEvent = scheduleEvent(safe('tick', tick), 250)
end

local function enableChoices(on)
  for _, child in ipairs(checkWindow.choices:getChildren()) do child:setEnabled(on) end
end

local function choose(key)
  if not current then return end
  enableChoices(false)
  setStatus(checkWindow, 'Checking...', L.COLORS.dim)
  send('answer', L.answer(current, key))
end

local function showCheck(data)
  local c = L.parseCheck(data)
  if not c or not checkWindow then return end
  closeEvent = cancel(closeEvent)
  current = c
  receivedAt = now()
  if c.attempt <= 1 then totalSeconds = math.max(1, c.seconds) end
  checkWindow:recursiveGetChildById('word'):setText(L.prompt(c.word))
  checkWindow.choices:destroyChildren()
  for _, opt in ipairs(c.options) do
    local tile = g_ui.createWidget('AntibotChoice', checkWindow.choices)
    tile.item:setItemId(opt.clientId)
    tile.onClick = function() choose(opt.key) return true end
  end
  checkWindow.retryButton:setText(L.retryText(c.retries))
  checkWindow.retryButton:setEnabled(c.retries > 0)
  setStatus(checkWindow, c.attempt > 1 and 'A new picture. Take your time.' or '', L.COLORS.dim)
  checkWindow:show()
  checkWindow:raise()
  checkWindow:focus()
  tickEvent = cancel(tickEvent)
  tick()
end

local function hideCheck()
  current = nil
  tickEvent = cancel(tickEvent)
  closeEvent = cancel(closeEvent)
  if checkWindow then checkWindow:hide() end
end

local function onCheckResult(d)
  if not checkWindow then return end
  if d.retry then
    setStatus(checkWindow, d.text or 'Try again.', L.COLORS.warn)
    return -- the next picture follows
  end
  setStatus(checkWindow, d.text or '', d.ok and L.COLORS.good or L.COLORS.bad)
  enableChoices(false)
  checkWindow.retryButton:setEnabled(false)
  current = nil
  closeEvent = cancel(closeEvent)
  closeEvent = scheduleEvent(hideCheck, d.ok and 1500 or 3000)
end

function another()
  if current and current.retries > 0 then
    enableChoices(false)
    send('another', { t = current.token })
  end
end

-- ---------------------------------------------------------------- report dialog
local function fillReasons()
  local box = reportWindow.reasonBox
  box:clearOptions()
  box:addOption('Choose a reason', '', true)
  for _, r in ipairs(reasons) do box:addOption(r.n, r.k, true) end
  box:setCurrentIndex(1, true)
end

local function updateCounter()
  if reportWindow then reportWindow.noteCounter:setText(L.noteCounter(reportWindow.noteEdit:getText(), noteMax)) end
end

function showReport(name)
  if not reportWindow then return end
  reportCloseEvent = cancel(reportCloseEvent)
  if type(name) == 'string' then reportWindow.nameEdit:setText(name) end
  reportWindow.noteEdit:setText('')
  setStatus(reportWindow, '')
  reportWindow.sendButton:setEnabled(true)
  updateCounter()
  reportWindow:show()
  reportWindow:raise()
  reportWindow:focus()
  local edit = reportWindow.nameEdit:getText() == '' and reportWindow.nameEdit or reportWindow.noteEdit
  scheduleEvent(function() if reportWindow and reportWindow:isVisible() then edit:focus() end end, 100)
end

function hideReport()
  reportCloseEvent = cancel(reportCloseEvent)
  if reportWindow then reportWindow:hide() end
end

function toggleReport()
  if reportWindow and reportWindow:isVisible() then hideReport() else showReport() end
end

function sendReport()
  if not reportWindow then return end
  local option = reportWindow.reasonBox:getCurrentOption()
  local player = g_game.getLocalPlayer()
  local msg, err = L.reportMessage(reportWindow.nameEdit:getText(), option and option.data or '',
    reportWindow.noteEdit:getText(), player and player:getName(), noteMax)
  if not msg then
    setStatus(reportWindow, err, L.COLORS.bad)
    return
  end
  reportWindow.sendButton:setEnabled(false)
  setStatus(reportWindow, 'Sending...', L.COLORS.dim)
  send('report', msg)
end

local function onReportOpen(d)
  reasons = L.parseReasons(d.reasons)
  noteMax = tonumber(d.noteMax) or L.NOTE_MAX
  fillReasons()
  showReport(d.name or '')
end

local function onReportResult(d)
  if not reportWindow then return end
  reportWindow.sendButton:setEnabled(not d.ok)
  setStatus(reportWindow, d.text or '', d.ok and L.COLORS.good or L.COLORS.bad)
  if d.ok then
    reportCloseEvent = cancel(reportCloseEvent)
    reportCloseEvent = scheduleEvent(hideReport, 2500)
  end
end

-- opens the dialog through the server (it sends the reasons), prefilled with a name
function report(name)
  if reportWindow and reportWindow:isVisible() then
    showReport(name)
  end
  send('reportOpen', { name = name or '' })
end

-- ---------------------------------------------------------------- protocol and menus
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' or type(msg.data) ~= 'table' then return end
  if msg.action == 'check' then showCheck(msg.data)
  elseif msg.action == 'checkResult' then onCheckResult(msg.data)
  elseif msg.action == 'reportOpen' then onReportOpen(msg.data)
  elseif msg.action == 'reportResult' then onReportResult(msg.data) end
end

local function addMenus()
  local gi = modules.game_interface
  if not hooked and gi and gi.addMenuHook then
    gi.addMenuHook('chaosReport', 'Report Player',
      function(menuPosition, lookThing, useThing, creatureThing) report(creatureThing and creatureThing:getName()) end,
      function(menuPosition, lookThing, useThing, creatureThing)
        return creatureThing ~= nil and L.canReport(creatureThing:isPlayer(), creatureThing:isLocalPlayer())
      end)
    hooked = true
  end
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if not menuAdded and api and api.addEntry then
    menuAdded = pcall(api.addEntry, 'system',
      { text = 'Report a Player', icon = 'help', modules = { 'game_antibot' }, fns = { 'report' } })
  end
end

local function onGameStart()
  addMenus()
end

local function onGameEnd()
  hideCheck()
  hideReport()
end

function init()
  g_ui.importStyle('antibot')
  checkWindow = g_ui.createWidget('PresenceCheckWindow', rootWidget)
  checkWindow:hide()
  reportWindow = g_ui.createWidget('ReportWindow', rootWidget)
  reportWindow:hide()
  fillReasons()
  reportWindow.noteEdit.onTextChange = function() updateCounter() end
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, safe('opcode', onMessage))
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  addMenus()
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if hooked and modules.game_interface and modules.game_interface.removeMenuHook then
    modules.game_interface.removeMenuHook('chaosReport')
  end
  hooked = false
  tickEvent = cancel(tickEvent)
  closeEvent = cancel(closeEvent)
  reportCloseEvent = cancel(reportCloseEvent)
  if checkWindow then checkWindow:destroy() checkWindow = nil end
  if reportWindow then reportWindow:destroy() reportWindow = nil end
end

-- for tests and screenshots: show the windows with given payloads
function debugShow(checkData, reportName)
  if checkData then showCheck(checkData) end
  if reportName then onReportOpen({ name = reportName }) end
end
