-- Energy shield bar: a light blue-violet bar above the health bar of the character plate (game_chaoshud) with the
-- numbers like the health bar. The engine (server src-patches/0015-energy-shield.patch) sends extended opcode 224, plain
-- text "es:<current>:<max>", when the shield changes (at most every 200 ms) and once a second while it recharges; max 0
-- hides the bar. A drop (a hit) shows at once, a rise (the recharge) eases over the next second so the bar fills
-- smoothly. Server side: server/data/lib/chaos_energy_shield.lua (the item modifiers), README "Energy shield".

local OPCODE = 224
local EASE_MS = 900
local BAR_W = 166
local bar
local state = { current = 0, max = 0 }
local shown, easeFrom, easeStart = 0, 0, 0
local easeEvent

local function stopEase()
  if easeEvent then removeEvent(easeEvent) easeEvent = nil end
end

local function draw(value)
  if not bar then return end
  local fill = bar:getChildById('fill')
  local px = ShieldMath.fillWidth(value, state.max, BAR_W)
  fill:setVisible(px > 0)
  bar:getChildById('shine'):setVisible(px > 0)
  if px > 0 then fill:setWidth(px) end
  bar:getChildById('text'):setText(ShieldMath.pair(value, state.max))
end

local function render()
  if not bar then return end
  if state.max <= 0 then
    stopEase()
    shown = 0
    bar:hide()
    return
  end
  bar:setTooltip(tr('Energy Shield %d / %d\nTakes damage before your health. Recharges 2 s after the last hit you take.',
    state.current, state.max))
  bar:show()
  if state.current <= shown then
    stopEase()
    shown = state.current
    draw(shown)
    return
  end
  -- rising: ease from what is on screen
  easeFrom, easeStart = shown, g_clock.millis()
  if not easeEvent then
    easeEvent = cycleEvent(function()
      local v = ShieldMath.ease(easeFrom, state.current, g_clock.millis() - easeStart, EASE_MS)
      shown = v
      draw(v)
      if v >= state.current then stopEase() end
    end, 40)
  end
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local s = ShieldMath.parse(buffer)
  if not s then return end
  state = s
  render()
end

local function reset()
  stopEase()
  state = { current = 0, max = 0 }
  shown = 0
  if bar then bar:hide() end
end

local function parentPanel()
  local root = modules.game_interface.getRootPanel()
  local plate = root and root:recursiveGetChildById('chaosHud')
  return plate or modules.game_interface.getMapPanel()
end

function init()
  bar = g_ui.loadUI('energyshield', parentPanel())
  bar:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = reset })
end

function terminate()
  disconnect(g_game, { onGameEnd = reset })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  reset()
  if bar then
    bar:destroy()
    bar = nil
  end
end
