-- Rift run HUD: time left, monsters killed / left, the guardian, the modifiers and the reward bonuses of the rift
-- the player is in. Server: server/data/scripts/chaos/rift.lua, extended opcode 228 (JSON {action, data}).
--   server -> client  start / update {tier, theme, left, limit, total, killed, bossAt, boss = waiting|alive|dead,
--                                     state, bossName, mods = [{name, text, boon}], bonus = {quantity, rarity, experience},
--                                     notes = [text] (live lines: sealed coffer, goblin, twin guardians)}
--                     end {result = success|failed, text, exitIn}
--   client -> server  query (after a module reload: the server answers with start when the player is in a rift)
-- !rift (server talkaction) shows the keys the player carries and the run status.

local OPCODE = 228
local hud
local data          -- last start/update data
local receivedAt = 0
local tickEvent, hideEvent

local function child(id)
  return hud and hud:recursiveGetChildById(id)
end

local function now()
  return g_clock.seconds()
end

local function short(n)
  n = tonumber(n) or 0
  if formatShortNumber then return formatShortNumber(n) end
  return tostring(n)
end

local function stopTick()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

local function updateClock()
  if not hud or not data then return end
  local clock = child('clock')
  if data.state == 'running' then
    local left = RiftMath.left(data.left, receivedAt, now())
    clock:setText(RiftMath.clock(left))
    clock:setColor(RiftMath.clockColor(left))
  elseif data.state == 'success' then
    clock:setText(tr('Sealed'))
    clock:setColor('#7fd07f')
  elseif data.state == 'left' then
    clock:setText(tr('Left'))
    clock:setColor('#8c8070')
  else
    clock:setText(tr('Collapsed'))
    clock:setColor('#ff4030')
  end
end

local function tick()
  tickEvent = nil
  updateClock()
  if data and data.state == 'running' then
    tickEvent = scheduleEvent(tick, 500)
  end
end

local function render()
  if not hud or not data then return end
  child('title'):setText(tr('Rift - Tier %d', tonumber(data.tier) or 1))
  child('theme'):setText(tostring(data.theme or ''))
  local total, killed = tonumber(data.total) or 0, tonumber(data.killed) or 0
  local bar = child('progress')
  bar:setPercent(RiftMath.bossPercent(killed, data.bossAt, data.boss))
  bar:setText(tr('%s / %s slain, %s left', short(killed), short(total), short(math.max(0, total - killed))))
  bar:setBackgroundColor(data.boss == 'waiting' and '#6a2ab0' or '#8a1010')
  child('boss'):setText(RiftMath.bossLine(data))
  local mods = child('mods')
  mods:destroyChildren()
  local list = type(data.mods) == 'table' and data.mods or {}
  for _, m in ipairs(list) do
    local label = g_ui.createWidget('RiftModLabel', mods)
    label:setText('- ' .. RiftMath.modLine(m))
    if m.boon then label:setColor('#e8c060') end -- a pure reward modifier (coffer, goblin, echoing spoils)
  end
  local notes = child('notes')
  notes:destroyChildren()
  for _, text in ipairs(type(data.notes) == 'table' and data.notes or {}) do
    g_ui.createWidget('RiftNoteLabel', notes):setText(tostring(text))
  end
  child('modsHeader'):setText(#list > 0 and tr('Modifiers') or tr('No modifiers'))
  local bonus = RiftMath.bonusLine(data.bonus)
  child('bonus'):setText(bonus ~= '' and tr('Rewards: %s', bonus) or '')
  child('bonus'):setVisible(bonus ~= '')
  updateClock()
end

local function show()
  if not hud then return end
  if hideEvent then removeEvent(hideEvent) hideEvent = nil end
  child('result'):setVisible(false)
  hud:show()
  hud:raise()
end

local function hide()
  stopTick()
  if hideEvent then removeEvent(hideEvent) hideEvent = nil end
  if hud then hud:hide() end
  data = nil
end

local function onData(d, isStart)
  data = d
  receivedAt = now()
  if isStart or not hud:isVisible() then show() end
  render()
  stopTick()
  tick()
end

local function onEnd(d)
  if not hud then return end
  if data then
    data.state = (d.result == 'success' or d.result == 'left') and d.result or 'failed'
    if d.result == 'success' then data.boss = 'dead' end
    render()
  else
    show()
  end
  stopTick()
  local result = child('result')
  result:setText(tostring(d.text or ''))
  result:setColor(d.result == 'success' and '#7fd07f' or '#ff6040')
  result:setVisible(true)
  if hideEvent then removeEvent(hideEvent) end
  -- a success keeps the HUD up while the chest can be opened; the final "end" on leaving hides it after a moment
  local delay = (tonumber(d.exitIn) or 0) > 0 and (tonumber(d.exitIn) + 2) * 1000 or 8000
  hideEvent = scheduleEvent(hide, delay)
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[rift] invalid JSON: ' .. tostring(msg))
    return
  end
  local d = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'start' then
    onData(d, true)
  elseif msg.action == 'update' then
    onData(d, false)
  elseif msg.action == 'end' then
    onEnd(d)
  end
end

local function onGameStart()
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = 'query', data = {} }))
  end
end

function init()
  hud = g_ui.loadUI('rift', modules.game_interface.getMapPanel())
  hud:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = hide })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = hide })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  hide()
  if hud then
    hud:destroy()
    hud = nil
  end
end
