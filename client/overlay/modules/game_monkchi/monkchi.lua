-- Monk chi HUD: five pips over the map that fill as the Monk builds chi with its strikes and empty when a finisher
-- spends it. Server: server/data/scripts/chaos/monk_combat.lua and monk_chi_core.lua (ChaosMonk.sendChi), extended
-- opcode 247, plain text "chi:<chi>:<max>:<decaySec>" (max 0 hides the HUD). Chi the server drops after decaySec
-- without a change is emptied here at the same time. Only the Monk line (server ids 17-19) sees it.

local OPCODE = 247
local FULL, EMPTY = '#f2b640', '#1a1418cc'
local hud
local state, receivedAt = nil, 0
local fadeEvent

local function now()
  return g_clock.seconds()
end

local function pipsPanel()
  return hud and hud:getChildById('pips')
end

local function ensurePips(max)
  local panel = pipsPanel()
  if not panel then return end
  while panel:getChildCount() < max do
    g_ui.createWidget('ChiPip', panel)
  end
  hud:setWidth(math.max(60, 12 + max * 22))
end

local function stopFade()
  if fadeEvent then removeEvent(fadeEvent) fadeEvent = nil end
end

local function render()
  if not hud then return end
  if not state or state.max <= 0 then
    hud:hide()
    return
  end
  ensurePips(state.max)
  local chi = ChiMath.shown(state, receivedAt, now())
  local panel = pipsPanel()
  for i, pip in ipairs(panel:getChildren()) do
    local look = ChiMath.pip(i, chi, state.max)
    pip:setVisible(look ~= 'hidden')
    pip:setBackgroundColor(look == 'full' and FULL or EMPTY)
  end
  hud:setTooltip(tr('Chi %d / %d: your strikes build it, finishers spend it.', chi, state.max))
  hud:show()
  stopFade()
  local left = ChiMath.fadeIn(state, receivedAt, now())
  if left and chi > 0 then
    fadeEvent = scheduleEvent(function() fadeEvent = nil render() end, math.ceil(left * 1000) + 50)
  end
end

local function hide()
  stopFade()
  state = nil
  if hud then hud:hide() end
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local s = ChiMath.parse(buffer)
  if not s then return end
  local player = g_game.getLocalPlayer()
  if s.max > 0 and player and not ChiMath.isMonk(player:getVocation()) then
    s.max = 0
  end
  state, receivedAt = s, now()
  render()
end

function init()
  hud = g_ui.loadUI('monkchi', modules.game_interface.getMapPanel())
  hud:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = hide })
end

function terminate()
  disconnect(g_game, { onGameEnd = hide })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  hide()
  if hud then
    hud:destroy()
    hud = nil
  end
end
