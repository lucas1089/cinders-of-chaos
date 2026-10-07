-- game_monsterbar: top-of-map health bar for the creature you are attacking.
-- The tier comes from the server (monster_tiers.lua, opcode 125); until the answer arrives the
-- bar looks like a normal monster's.

local OPCODE = 125
local TIERS = {
  normal    = { label = '',          color = '#a8a0a0', text = '#d6c9ae' },
  magic     = { label = 'Magic ',    color = '#3c78e6', text = '#7fb0ff' },
  rare      = { label = 'Rare ',     color = '#ebbe32', text = '#f6cf72' },
  legendary = { label = 'Legendary ', color = '#f06e1e', text = '#ff9a4a' },
  boss      = { label = '',          color = '#be1410', text = '#e03a1e' }
}

local window, current
local tierOf = {}
local modsOf = {}

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function paint(creature, tier, label, mods)
  if not window or creature ~= current then
    return
  end
  local t = TIERS[tier] or TIERS.normal
  window:getChildById('frame'):setImageSource('/images/chaos/monsterbar/frame_' .. (TIERS[tier] and tier or 'normal'))
  window:getChildById('bar'):setBackgroundColor(t.color)
  local name = window:getChildById('name')
  name:setText((label and label ~= '' and (label .. ' ') or t.label) .. creature:getName())
  name:setColor(t.text)
  window:getChildById('mods'):setText(mods and #mods > 0 and table.concat(mods, '  -  ') or '')
end

local function updateHealth(creature, percent)
  if not window or creature ~= current then
    return
  end
  window:getChildById('bar'):setPercent(percent)
  window:getChildById('percent'):setText(percent .. '%')
  if percent <= 0 then
    window:hide()
  end
end

local function onAttackingCreatureChange(creature)
  current = nil
  if not window then
    return
  end
  if not creature or not creature:isMonster() then
    window:hide()
    return
  end
  current = creature
  paint(creature, tierOf[creature:getId()] or 'normal', nil, modsOf[creature:getId()])
  updateHealth(creature, creature:getHealthPercent())
  window:show()
  if not tierOf[creature:getId()] then
    send('query', { cid = creature:getId() })
  end
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' or msg.action ~= 'info' or type(msg.data) ~= 'table' then
    return
  end
  tierOf[msg.data.cid] = msg.data.tier
  modsOf[msg.data.cid] = msg.data.mods
  if current and current:getId() == msg.data.cid then
    paint(current, msg.data.tier, msg.data.label, msg.data.mods)
  end
end

local function onDisappear(creature)
  tierOf[creature:getId()] = nil
  modsOf[creature:getId()] = nil
  if creature == current then
    current = nil
    if window then
      window:hide()
    end
  end
end

local function onGameEnd()
  tierOf = {}
  modsOf = {}
  current = nil
  if window then
    window:hide()
  end
end

function init()
  window = g_ui.loadUI('monsterbar', modules.game_interface.getMapPanel())
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onAttackingCreatureChange = onAttackingCreatureChange, onGameEnd = onGameEnd })
  connect(Creature, { onHealthPercentChange = updateHealth, onDisappear = onDisappear })
end

function terminate()
  disconnect(g_game, { onAttackingCreatureChange = onAttackingCreatureChange, onGameEnd = onGameEnd })
  disconnect(Creature, { onHealthPercentChange = updateHealth, onDisappear = onDisappear })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if window then
    window:destroy()
    window = nil
  end
end
