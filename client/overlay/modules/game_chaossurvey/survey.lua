-- game_chaossurvey: the new player survey (server server/data/scripts/chaos/survey.lua, extended opcode 122, JSON
-- {action, data}; server/README.md "New player funnel and survey (O374)").
--   server -> client  open {s, max} | done {s}
--   client -> server  answer {s, fun, rec, text} | skip {s}
-- At level 20 and 50 (once per account) the server opens a small window: "What confused you so far?" (free text),
-- "How fun is it?" 1-5, "Would you recommend it?". Send, Skip or Escape; the server never asks that account again
-- after either. Closing the client before both asks again at the next login. Pure logic: surveylogic.lua.

local OPCODE = 122
local L = SurveyLogic

local window
local current -- {stage, max}
local fun, rec
local closeEvent
local reported = {}

local COLORS = { good = '#8fd18f', bad = '#e07a6a', dim = '#a89c86' }

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[survey] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function sendMsg(msg)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode(msg))
    return true
  end
  return false
end

local function cancel(ev)
  if ev then removeEvent(ev) end
  return nil
end

local function setStatus(text, color)
  if not window then return end
  window.status:setText(text or '')
  window.status:setColor(color or COLORS.dim)
end

local function refresh()
  if not window then return end
  for i = 1, 5 do
    local b = window.funRow:getChildById('fun' .. i)
    if b then b:setChecked(fun == i) end
  end
  window.yesButton:setChecked(rec == true)
  window.noButton:setChecked(rec == false)
  local text = window.textEdit:getText()
  window.counter:setText(L.counter(text, current and current.max))
  window.sendButton:setEnabled(current ~= nil and L.canSend(fun, rec, text))
end

local function hide()
  closeEvent = cancel(closeEvent)
  current, fun, rec = nil, nil, nil
  if window then window:hide() end
end

function chooseFun(i)
  if not current then return end
  fun = (fun == i) and nil or i
  refresh()
end

function chooseRec(v)
  if not current then return end
  if rec == v then rec = nil else rec = v end
  refresh()
end

function send()
  if not current or not window then return end
  local text = window.textEdit:getText()
  if not L.canSend(fun, rec, text) then return end
  if sendMsg(L.answer(current.stage, fun, rec, text, current.max)) then
    window.sendButton:setEnabled(false)
    window.skipButton:setEnabled(false)
    setStatus(tr('Sending...'))
  end
end

function skip()
  if not current then
    hide()
    return
  end
  sendMsg(L.skip(current.stage))
  hide()
end

local function onOpen(data)
  local o = L.parseOpen(data)
  if not o or not window then return end
  closeEvent = cancel(closeEvent)
  current, fun, rec = o, nil, nil
  window:setText(tr('A quick survey: level %d', o.stage))
  window.textEdit:setMaxLength(o.max)
  window.textEdit:setText('')
  window.skipButton:setEnabled(true)
  setStatus('')
  refresh()
  window:show()
  window:raise()
end

local function onDone(data)
  if not window or not current then return end
  current = nil
  window.sendButton:setEnabled(false)
  window.skipButton:setEnabled(true)
  setStatus(tr('Thank you! Your answer helps us make the game better.'), COLORS.good)
  closeEvent = cancel(closeEvent)
  closeEvent = scheduleEvent(hide, 2500)
end

local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  if msg.action == 'open' then onOpen(msg.data)
  elseif msg.action == 'done' then onDone(msg.data) end
end

local function onGameEnd()
  hide()
end

function init()
  g_ui.importStyle('survey')
  window = g_ui.createWidget('SurveyWindow', rootWidget)
  window:hide()
  for i = 1, 5 do
    local b = g_ui.createWidget('SurveyChoice', window.funRow)
    b:setId('fun' .. i)
    b:setText(tostring(i))
    b.onClick = function() chooseFun(i) return true end
  end
  window.textEdit.onTextChange = safe('text', refresh)
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, safe('opcode', onMessage))
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  closeEvent = cancel(closeEvent)
  if window then window:destroy() window = nil end
  current = nil
end

-- for tests and screenshots: show the window as the server would
function debugShow(stage)
  onOpen({ s = stage or 20, max = L.TEXT_MAX })
end
