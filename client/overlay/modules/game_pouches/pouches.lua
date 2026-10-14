-- Store pouches (server data/scripts/chaos/pouches.lua, extended opcode 226, JSON {action, data}).
--   client -> server  open | sync | set {rules}
--                     Auto Seller window (server autosell.lua): as_open | as_sync | sell | asrar {tier, on} |
--                     aslist {op = add|remove|clear, item} | aspause {on}
--   server -> client  settings {rules, ids = {loot, orbs, keys} (client ids), titles, owned (on open), rarities, open}
--                     autoseller {unlocked, needs, paused, tiers, list, slots, cooldown, cooldownMax, last, notice, open}
-- The pouches themselves are ordinary containers (use = open). Two windows: the Loot Bag rules (right-click the Loot
-- Bag > "Pouch settings", or the Loot Filter's "Loot Bag" button) and the Auto Seller (Economy > Auto Seller in the
-- top menu, or the Loot Bag window's Auto Seller button; owner 2026-10-13: "Tire os comandos do autosell e coloque no
-- topmenu"). Logic: pouchesview.lua, autosellerview.lua.

local OPCODE = 226
local V = PouchesView
local AV = AutoSellerView

local window
local asWindow
local asState = AV.normalize(nil)
local asStateAt = 0 -- os.time when the state came (the cooldown counts down from it)
local asTick = nil
local asChecks = {}
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
  window:setText(titles.loot or tr('Loot Bag'))
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

-- ---------------------------------------------------------------- the Auto Seller window
local function asLeft()
  return AV.cooldownLeft(asState.cooldown, os.time() - asStateAt)
end

local function refreshAutoSeller()
  if not asWindow then return end
  updating = true
  local s = asState
  local tip = AV.lockedTooltip(s)
  local left = asLeft()
  asWindow.sellButton:setText(AV.sellText(left))
  asWindow.sellButton:setEnabled(AV.sellEnabled(s, left))
  asWindow.lastSale:setText(AV.lastSaleText(s.last))
  for i, t in ipairs(s.tiers) do
    local cb = asChecks[i]
    if cb then
      cb:setChecked(t.on)
      cb:setEnabled(s.unlocked)
      cb:setTooltip(tip or (t.key == 'legendary' and tr('Legendary and every rarity above it') or ''))
    end
  end
  asWindow.corpseCheck:setChecked(not s.paused)
  asWindow.listPanel.listText:setText(AV.listText(s.list, s.slots)) -- listText sits inside listPanel
  for _, id in ipairs({ 'corpseCheck', 'itemEdit', 'addButton', 'removeButton', 'clearButton', 'sellButton' }) do
    local w = asWindow[id]
    if not s.unlocked then
      w:setEnabled(false)
    elseif id ~= 'sellButton' then
      w:setEnabled(true)
    end
    if id ~= 'sellButton' or tip then w:setTooltip(tip or '') end
  end
  asWindow.notice:setText(s.notice or (tip or ''))
  updating = false
end

local function stopTick()
  if asTick then removeEvent(asTick) asTick = nil end
end

local function tick()
  asTick = nil
  if not asWindow or not asWindow:isVisible() then return end
  refreshAutoSeller()
  if asLeft() > 0 then asTick = scheduleEvent(safe('tick', tick), 1000) end
end

local function onAutoSeller(d)
  asState = AV.normalize(d)
  asStateAt = os.time()
  refreshAutoSeller()
  if asState.open and asWindow then
    asWindow:show()
    asWindow:raise()
    asWindow:focus()
  end
  stopTick()
  tick()
end

function showAutoSeller()
  send('as_open')
end

function hideAutoSeller()
  stopTick()
  if asWindow then asWindow:hide() end
end

function toggleAutoSeller()
  if asWindow and asWindow:isVisible() then hideAutoSeller() else showAutoSeller() end
end

function autoSellerList(op)
  if not asWindow then return end
  local req = AV.listRequest(op, asWindow.itemEdit:getText())
  if req then
    send('aslist', req)
    if op ~= 'clear' then asWindow.itemEdit:setText('') end
  end
end

local function onRarityCheck(widget, checked)
  if updating or not widget.tierKey then return end
  local req = AV.rarityRequest(widget.tierKey, checked)
  if req then send('asrar', req) end
end

local function onCorpseCheck(widget, checked)
  if updating then return end
  send('aspause', { on = checked == true })
end

local function buildAutoSeller()
  local ok, ui = pcall(g_ui.createWidget, 'AutoSellerWindow', rootWidget)
  if not ok or not ui then
    g_logger.warning('[pouches] Auto Seller window not loaded: ' .. tostring(ui))
    return
  end
  asWindow = ui
  asWindow:hide()
  for i, t in ipairs(AV.TIERS) do
    local cb = g_ui.createWidget('AutoSellerRarityCheck', asWindow.rarityRow)
    cb:setId('rarity_' .. t.key)
    cb:setText(tr(t.name))
    cb:setColor(t.color)
    cb.tierKey = t.key
    cb.onCheckChange = safe('rarity', onRarityCheck)
    asChecks[i] = cb
  end
  asWindow.corpseCheck.onCheckChange = safe('corpse', onCorpseCheck)
  refreshAutoSeller()
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' or type(msg.data) ~= 'table' then return end
  if msg.action == 'autoseller' then
    onAutoSeller(msg.data)
    return
  end
  if msg.action ~= 'settings' then return end
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

-- the Auto Seller sells everything in the Loot Bag (server autosell.lua, every 30 s); the server checks the unlock
-- and the cooldown and answers with the window state
function sellAll()
  send('sell')
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
  hideAutoSeller()
  asState = AV.normalize(nil)
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
  g_ui.importStyle('autoseller')
  buildAutoSeller()
  ProtocolGame.registerExtendedOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game)
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  local gi = modules.game_interface
  if gi and gi.removeMenuHook then pcall(gi.removeMenuHook, 'chaosPouch') end
  stopTick()
  if window then window:destroy() window = nil end
  if asWindow then asWindow:destroy() asWindow = nil end
  asChecks = {}
  handlers = {}
end
