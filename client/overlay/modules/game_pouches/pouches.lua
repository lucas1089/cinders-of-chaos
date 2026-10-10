-- Store pouches (server data/scripts/chaos/pouches.lua, extended opcode 226, JSON {action, data}).
--   client -> server  open | sync | set {rules}
--   server -> client  settings {rules, ids = {loot, orbs, keys} (client ids), titles, owned (on open), rarities, open}
-- The pouches themselves are ordinary containers (use = open). This module is the Loot Pouch rules window, opened by
-- right-clicking the Loot Pouch ("Pouch settings") or the Loot Filter's "Loot Pouch" button.

local OPCODE = 226
local V = PouchesView

local window
local rules = V.normalize(nil)
local ids, titles, owned, rarities = {}, {}, nil, {}
local updating = false
local handlers = {}
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[pouches] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function refreshWindow()
  if not window then return end
  updating = true
  for _, k in ipairs(V.FLAGS) do
    if window[k] then window[k]:setChecked(rules[k] == true) end
  end
  local combo = window.rarityCombo
  combo:clearOptions()
  for i, name in ipairs(V.rarityOptions(rarities)) do combo:addOption(name, i) end
  combo:setCurrentIndex(rules.minRarity)
  combo:setEnabled(rules.gear == true)
  window.status:setText(V.statusText(owned, titles.loot))
  window.storeButton:setVisible(type(owned) == 'table' and not owned.loot)
  window:setText(titles.loot or tr('Loot Pouch'))
  updating = false
end

local function onUiChange()
  if updating or not window then return end
  local r = {}
  for _, k in ipairs(V.FLAGS) do r[k] = window[k]:isChecked() end
  local opt = window.rarityCombo:getCurrentOption()
  r.minRarity = opt and tonumber(opt.data) or rules.minRarity
  rules = V.normalize(r)
  window.rarityCombo:setEnabled(rules.gear)
  send('set', { rules = rules })
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' or msg.action ~= 'settings' or type(msg.data) ~= 'table' then return end
  local d = msg.data
  rules = V.normalize(d.rules)
  if type(d.ids) == 'table' then ids = d.ids end
  if type(d.titles) == 'table' then titles = d.titles end
  if type(d.rarities) == 'table' then rarities = d.rarities end
  if type(d.owned) == 'table' then owned = d.owned end
  refreshWindow()
  if d.open and window then
    window:show()
    window:raise()
    window:focus()
  end
end

function showSettings()
  send('open')
end

function hideSettings()
  if window then window:hide() end
end

function toggleSettings()
  if window and window:isVisible() then hideSettings() else showSettings() end
end

function openStore()
  if modules.game_shop and modules.game_shop.toggle then modules.game_shop.toggle() end
end

-- for other modules and tests
function getState()
  return { rules = rules, ids = ids, owned = owned, visible = window and window:isVisible() or false }
end

local function lockFlag(item)
  local ok, v = pcall(function() return item:getCustomAttribute(3) end) -- ChaosItemAttr.LOCKED
  return ok and tonumber(v) or 0
end

local function hookMenu()
  local gi = modules.game_interface
  if not gi or not gi.addMenuHook then return end
  gi.addMenuHook('chaosPouch', tr('Pouch settings'), safe('menu', function() showSettings() end),
    safe('menuCondition', function(_, lookThing, useThing)
      local thing = useThing or lookThing
      if not thing or not thing.isItem or not thing:isItem() then return false end
      return V.isLootPouch(thing:getId(), lockFlag(thing), ids)
    end))
end

local function onGameStart()
  owned = nil
  hookMenu()
  send('sync')
end

local function onGameEnd()
  hideSettings()
end

function init()
  g_ui.importStyle('pouches')
  handlers.opcode = safe('opcode', onExtendedOpcode)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  local ok, ui = pcall(g_ui.createWidget, 'PouchesWindow', rootWidget)
  if ok and ui then
    window = ui
    window:hide()
    for _, k in ipairs(V.FLAGS) do
      window[k].onCheckChange = safe('ui', onUiChange)
    end
    window.rarityCombo.onOptionChange = safe('ui', onUiChange)
  else
    g_logger.warning('[pouches] window not loaded: ' .. tostring(ui))
  end
  ProtocolGame.registerExtendedOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game)
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  local gi = modules.game_interface
  if gi and gi.removeMenuHook then pcall(gi.removeMenuHook, 'chaosPouch') end
  if window then window:destroy() window = nil end
  handlers = {}
end
