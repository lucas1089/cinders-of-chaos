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
  local modsLabel = window:getChildById('mods')
  local hasMods = mods and #mods > 0
  modsLabel:setText(hasMods and table.concat(mods, '  -  ') or '')
  modsLabel:setColor(t.text)
  modsLabel:setVisible(hasMods and true or false)
end

-- bosses are drawn this much bigger than ordinary monsters (needs base patch 0020, Creature:setDrawScale)
local BOSS_SCALE = 1.5

-- in-world label: modifiers on a line above the name, name coloured by tier
local function labelCreature(creature, tier, mods)
  if not creature then
    return
  end
  if creature.setDrawScale then
    creature:setDrawScale(tier == 'boss' and BOSS_SCALE or 1)
  end
  local t = TIERS[tier]
  if not t or tier == 'normal' then
    return
  end
  creature:setInformationColor(t.text)
  if mods and #mods > 0 then
    -- two modifiers per line keeps the label about as wide as the monster's name
    local lines = {}
    for i = 1, #mods, 2 do
      lines[#lines + 1] = mods[i + 1] and (mods[i] .. ' - ' .. mods[i + 1]) or mods[i]
    end
    creature:setTitle(table.concat(lines, '\n'), 'verdana-11px-antialised', t.text)
  end
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
  labelCreature(g_map.getCreatureById(msg.data.cid), msg.data.tier, msg.data.mods)
  if current and current:getId() == msg.data.cid then
    paint(current, msg.data.tier, msg.data.label, msg.data.mods)
  end
end

local function onAppear(creature)
  local id = creature:getId()
  if tierOf[id] then
    labelCreature(creature, tierOf[id], modsOf[id])
  end
end

local function onDisappear(creature)
  -- tier info stays cached (a monster that walks out of view and back keeps its label)
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
  connect(Creature, { onHealthPercentChange = updateHealth, onAppear = onAppear, onDisappear = onDisappear })
end

function terminate()
  disconnect(g_game, { onAttackingCreatureChange = onAttackingCreatureChange, onGameEnd = onGameEnd })
  disconnect(Creature, { onHealthPercentChange = updateHealth, onAppear = onAppear, onDisappear = onDisappear })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if window then
    window:destroy()
    window = nil
  end
end
