-- Invasion HUD over the map and the upcoming events window.
-- Server: server/data/scripts/chaos/invasion.lua and worldevents.lua, extended opcode 251 (JSON {action, data}).
--   server -> client  hud {phase = running|occupied, area, faction, color, target, wave, waves, left, progress, breach,
--                          time, next, boss, bossHp, top = [{name, share}], you = {rank, share, kills}}   every 2 s
--                     end {result = win|breach|time|liberated|withdrawn, text}
--                     hide {}
--                     calendar {open, list = [{kind, when, inSeconds, name}]}
--   client -> server  query (after a reload: the HUD if an invasion runs) | calendar {open}
-- The toasts (30 / 10 / 1 minutes before, start, waves, end) come through game_chaosnotify ("invasion").

local OPCODE = 251

local hud
local window
local data
local receivedAt = 0
local folded = false
local tickEvent, hideEvent

local function now() return g_clock.seconds() end

local function send(action, d)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = d or {} }))
  end
end

local function stopTick()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

local function updateClock()
  if not hud or not data then return end
  local left = InvasionMath.left(data.time, receivedAt, now())
  hud.clockRow.clock:setText(InvasionMath.clock(left))
  hud.clockRow.clock:setColor(left <= 60 and '#ff4030' or '#f4d27a')
  if (tonumber(data.wave) or 0) == 0 and data.phase == 'running' then
    hud.clockRow.wave:setText(InvasionMath.waveLine({ wave = 0, waves = data.waves,
      next = InvasionMath.left(data.next, receivedAt, now()) }))
  end
end

local function tick()
  tickEvent = nil
  updateClock()
  if data and not data.ended then tickEvent = scheduleEvent(tick, 500) end
end

-- beside the rift HUD (same spot) while a rift runs
local function place()
  local mapPanel = modules.game_interface.getMapPanel()
  local rift = mapPanel and mapPanel:recursiveGetChildById('riftHud')
  hud:setMarginLeft((rift and rift:isVisible()) and (40 + rift:getWidth() + 8) or 40)
end

local function render()
  if not hud or not data then return end
  place()
  hud.title:setText(InvasionMath.title(data))
  hud.title:setColor(data.color or '#e8b84a')
  hud.subtitle:setText(InvasionMath.subtitle(data))
  hud.clockRow.wave:setText(InvasionMath.waveLine(data))
  local progress = tonumber(data.progress) or 0
  hud.progress:setPercent(progress)
  hud.progress:setText(data.phase == 'occupied' and tr('Occupied') or tr('Horde slain: %d%%', progress))
  local breach = tonumber(data.breach) or 0
  hud.breach:setPercent(breach)
  hud.breach:setBackgroundColor(InvasionMath.breachColor(breach))
  hud.breach:setText(tr('Breach: %d%%', breach))
  hud.breach:setVisible(data.phase ~= 'occupied')
  if data.boss then
    hud.boss:setText(tr('%s - %d%%', data.boss, tonumber(data.bossHp) or 100))
    hud.boss:setVisible(true)
  else
    hud.boss:setVisible(false)
  end
  hud.top:destroyChildren()
  if not folded then
    for _, line in ipairs(InvasionMath.topLines(data.top)) do
      local l = g_ui.createWidget('InvasionTopLabel', hud.top)
      l:setText(line)
    end
  end
  hud.top:setVisible(not folded)
  hud.you:setText(InvasionMath.youLine(data.you))
  hud.you:setVisible(not folded)
  updateClock()
end

local function hideHud()
  stopTick()
  if hideEvent then removeEvent(hideEvent) hideEvent = nil end
  if hud then hud:setVisible(false) end
  data = nil
end

local function onHud(d)
  if hideEvent then removeEvent(hideEvent) hideEvent = nil end
  data = d
  receivedAt = now()
  if d.phase ~= 'occupied' then hud.result:setVisible(false) end -- a lost invasion keeps "X has fallen" up
  hud:setVisible(true)
  render()
  stopTick()
  tick()
end

local function onEnd(d)
  if not hud then return end
  if not data then data = { phase = 'running', wave = 0, waves = 0 } end
  data.ended = true
  data.time = 0
  stopTick()
  render()
  hud:setVisible(true)
  hud.result:setText(tostring(d.text or ''))
  hud.result:setColor(InvasionMath.resultColor(d.result))
  hud.result:setVisible(true)
end

-- ---------------------------------------------------------------- window
function hideWindow()
  if window then window:hide() end
end

local function showCalendar(d)
  if not window then return end
  window.list:destroyChildren()
  local list = type(d.list) == 'table' and d.list or {}
  if #list == 0 then
    local row = g_ui.createWidget('InvasionEventRow', window.list)
    row.when:setText('-')
    row.name:setText(tr('Nothing planned yet.'))
  end
  for _, e in ipairs(list) do
    local row = g_ui.createWidget('InvasionEventRow', window.list)
    row.when:setText(tostring(e.when or ''))
    row.name:setText(tostring(e.name or ''))
    row.name:setColor(InvasionMath.kindColor(e.kind))
    if (tonumber(e.inSeconds) or 0) > 0 then
      row:setTooltip(InvasionMath.countdown(e.inSeconds))
      row:setPhantom(false)
    end
  end
  if d.open then
    window:show()
    window:raise()
    window:focus()
  end
end

function toggle()
  if window and window:isVisible() then hideWindow() return end
  send('calendar', { open = true })
end

-- ---------------------------------------------------------------- protocol
local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[invasion] invalid JSON: ' .. tostring(msg))
    return
  end
  local d = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'hud' then
    onHud(d)
  elseif msg.action == 'end' then
    onEnd(d)
  elseif msg.action == 'hide' then
    hideHud()
  elseif msg.action == 'calendar' then
    showCalendar(d)
  end
end

local function onGameStart()
  send('query')
end

local function onGameEnd()
  hideHud()
  hideWindow()
end

function init()
  window = g_ui.displayUI('invasion')
  window:hide()
  hud = g_ui.loadUI('invasionhud', modules.game_interface.getMapPanel())
  if hud then
    hud:setVisible(false)
    hud.onClick = function()
      folded = not folded
      render()
      return true
    end
  end
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  stopTick()
  if hideEvent then removeEvent(hideEvent) hideEvent = nil end
  if hud then hud:destroy() hud = nil end
  if window then window:destroy() window = nil end
  data = nil
end
