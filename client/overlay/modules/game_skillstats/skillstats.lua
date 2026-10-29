-- The combat stat rows of the Skills window (rules: skillstatsview.lua; server: data/scripts/chaos/combat_stats.lua,
-- extended opcode 119; server/README.md "Combat stat rows of the Skills window"). The base module game_skills owns the
-- rows (damageHealing, attackValue, defenseValue, armorValue, mantraValue, mitigationValue) but fills them only from a
-- newer protocol's packet, so they stayed 0. This module:
--   * shows "-" in the five rows until the server's numbers arrive (an older server never sends them),
--   * fills them from the `stats` message, hides Damage/Healing and Attack Value when it carries none (a wand, bare hands),
--   * hides the Mantra row for good (the game has no such stat),
--   * asks the server for the numbers when the game starts (`get`), the server also pushes them on every change.
-- terminate shows the rows again.

local OPCODE = 119

local V = ChaosSkillStatsView
local ROW = {
  damage = { id = 'damageHealing', value = 'damageHealingLabel' },
  attack = { id = 'attackValue', value = 'value' },
  defense = { id = 'defenseValue', value = 'value' },
  armor = { id = 'armorValue', value = 'value' },
  mitigation = { id = 'mitigationValue', value = 'value' },
  mantra = { id = 'mantraValue', value = 'value' },
}

local state     -- the last stats message's data, nil until one came
local handlers = {}

local function window()
  local skills = modules.game_skills
  return skills and rawget(skills, 'skillsWindow') or nil
end

local function rowWidget(name)
  local w = window()
  return w and w:recursiveGetChildById(ROW[name].id) or nil
end

local function tooltipOf(name)
  if name == 'damage' then
    return tr('Average hit of your weapon\'s auto attack, with the bonuses of your passive tree. Wands, rods and fists have no attack hit.')
  elseif name == 'attack' then
    return tr('Attack of the weapon in your hands, with the roll of the item. The Damage/Healing row shows what it hits for.')
  elseif name == 'defense' then
    return tr('How much of a hit your shield blocks (your weapon without one): (skill / 4 + 2.23) x defence x 0.15, with shielding or the weapon\'s skill.')
  elseif name == 'armor' then
    return tr('The armour of all the pieces you wear. It takes a share of every physical hit; each point adds less than the one before.')
  elseif name == 'mitigation' then
    return tr('The share of a physical hit from a monster that never lands: your armour, your physical resist from gear and the passive tree, and Damage Taken from Monsters.')
  end
  return ''
end

local function fitWindow()
  local skills = modules.game_skills
  local w = window()
  if w and skills and type(rawget(skills, 'getContentPanelHeight')) == 'function' then
    w:setContentMaximumHeight(math.max(125, skills.getContentPanelHeight() + 6))
  end
end

local function render()
  if not window() then return end
  local view = V.build(state, formatShortNumber)
  for name, spec in pairs(ROW) do
    local row = rowWidget(name)
    local v = view[name]
    if row and v then
      if row:isExplicitlyVisible() ~= v.visible then
        row:setVisible(v.visible)
      end
      local label = row:recursiveGetChildById(spec.value)
      if label then
        label:setText(v.text)
        label:setColor(v.color)
      end
      if name ~= 'mantra' then
        row:setTooltip(tooltipOf(name))
      end
    end
  end
  fitWindow()
end

local function onStats(protocol, opcode, data)
  if type(data) ~= 'table' or data.action ~= 'stats' or type(data.data) ~= 'table' then return end
  state = data.data
  render()
end

local function send(action)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = {} }))
  end
end

local function onGameStart()
  state = nil
  scheduleEvent(function()
    render()
    send('get')
  end, 150) -- after the base module has built the window
end

local function onGameEnd()
  state = nil
end

function init()
  handlers.game = { onGameStart = onGameStart, onGameEnd = onGameEnd }
  connect(g_game, handlers.game)
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, onStats)
  if g_game.isOnline() then
    onGameStart()
  end
end

function terminate()
  if handlers.game then
    disconnect(g_game, handlers.game)
    handlers.game = nil
  end
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  for name in pairs(ROW) do
    local row = rowWidget(name)
    if row then
      row:setVisible(true)
    end
  end
  fitWindow()
end
