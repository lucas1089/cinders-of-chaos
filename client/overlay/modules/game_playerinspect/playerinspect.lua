-- Inspect Player window. Opened from the top menu (Social > Inspect Player: type a name) and from the right-click menu
-- of a player on the map (Inspect Player: within 10 tiles). Server: server/data/scripts/chaos/inspect.lua, extended opcode
-- 240 (JSON {action, data}); the logic is in playerplayerinspect_logic.lua.
--   client -> server  inspect {cid} | inspect {name}   privacy {} | privacy {allow}
--   server -> client  result {...}   equip {name, rows}   tree {name, nodes, masteries, cls, line, vocation}
--                     denied {code, text}   privacy {allow}
-- The Passive Tree button opens the inspected character's tree read-only in the passive tree window
-- (game_passivetree viewother.lua showOtherTree); a big tree packet arrives in parts (L.joinPart).
-- The checkbox "Allow others to inspect me" is the character's privacy setting (stored on the server, default on).

local OPCODE = 240
local L = PlayerInspectLogic

local window
local state = L.newState()
local loadingPrivacy = false
local hooked = false
local chunkParts = {}

local function safe(name, fn)
  local reported = false
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok and not reported then
      reported = true
      g_logger.warning('[inspect] ' .. name .. ': ' .. tostring(err))
    end
  end
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function tooltips()
  return modules.game_itemtooltip
end

local function setStatus(text, color)
  if not window then return end
  window.statusLabel:setText(text or '')
  window.statusLabel:setColor(color or L.COLORS.dim)
end

-- ---------------------------------------------------------------- slots
local function slotWidget(slot)
  return window.gearPanel:getChildById('slot' .. slot)
end

local function clearSlot(slot)
  local w = slotWidget(slot)
  if not w then return end
  w:setItemId(0)
  w:setItemCount(1)
  w.tip = nil
  w.frame:setBorderWidth(0)
  w:setTooltip('')
end

local function fillSlot(slot, tip)
  local w = slotWidget(slot)
  if not w then return end
  w:setItemId(tonumber(tip.id) or 0)
  w:setItemCount(tonumber(tip.count) or 1)
  -- a transmog look (server transmog.lua, tip.look; client base patch 0030): the gear is drawn as it looks
  local look = type(tip.look) == 'table' and tonumber(tip.look.cid) or 0
  local item = look > 0 and w:getItem() or nil
  if item then pcall(function() item:setAppearanceId(look) end) end
  w.tip = tip
  local logic = tooltips() and tooltips().ItemTooltipLogic
  local color = logic and logic.titleColor(tip) or nil
  if color and (tip.rarity or 0) > 0 or tip.unique then
    w.frame:setBorderWidth(2)
    w.frame:setBorderColor(color)
  else
    w.frame:setBorderWidth(0)
  end
end

local function onSlotHover(w, hovered)
  local tt = tooltips()
  if not tt or not tt.showTip then return end
  if hovered and w.tip then
    local extra = { { text = (L.SLOTS[w.slotNumber] or {}).name or '', color = L.COLORS.dim, sep = true } }
    tt.showTip(w, L.tipKey(state.data and state.data.name, w.slotNumber, w.tip), w.tip, extra)
  elseif tt.hideTip then
    tt.hideTip(w)
  end
end

local function buildSlots()
  for slot, p in pairs(L.SLOTS) do
    local w = g_ui.createWidget('InspectSlot', window.gearPanel)
    w:setId('slot' .. slot)
    w.slotNumber = slot
    w:setMarginLeft(24 + p.col * 52)
    w:setMarginTop(12 + p.row * 52)
    w.onHoverChange = safe('hover', onSlotHover)
  end
end

local function refreshTreeButton()
  if not window then return end
  local text = L.treeButtonText(state)
  window.treeButton:setEnabled(text ~= nil)
  window.treeButton:setText(text or 'Passive Tree')
end

function openInspectedTree()
  local tree = modules.game_passivetree
  if not state.tree or not tree or not tree.showOtherTree then return end
  hide() -- the tree window takes the screen; the menu opens this window again
  tree.showOtherTree(state.tree)
end

local function clearAll()
  refreshTreeButton()
  for slot = 1, 10 do clearSlot(slot) end
  window.infoPanel.lines:destroyChildren()
  window.infoPanel.charName:setText('')
  window.infoPanel.creature:setOutfit({ type = 0 })
end

-- ---------------------------------------------------------------- showing a result
local function showResult(d)
  L.onResult(state, d)
  for slot = 1, 10 do clearSlot(slot) end
  window.infoPanel.charName:setText(d.name or '')
  window.nameEdit:setText(d.name or '')
  local o = d.outfit or {}
  window.infoPanel.creature:setOutfit({ type = o.type or 0, head = o.head, body = o.body, legs = o.legs, feet = o.feet, addons = o.addons,
    mount = o.mount })
  window.infoPanel.lines:destroyChildren()
  for _, line in ipairs(L.lines(d)) do
    local label = g_ui.createWidget('InspectLine', window.infoPanel.lines)
    label:setText(line.text)
    label:setColor(line.color)
  end
  setStatus(d.self and 'This is you.' or '', L.COLORS.dim)
  refreshTreeButton()
end

local function onEquip(d)
  if not L.onEquip(state, d) then return end
  for slot, tip in pairs(state.tips) do fillSlot(slot, tip) end
end

local function onDenied(d)
  state = L.newState()
  clearAll() -- no stale character next to the refusal
  setStatus(tostring(d.text or 'Nothing to show.'), L.COLORS.red)
end

local function onPrivacy(d)
  loadingPrivacy = true
  window.privacyBox:setChecked(d.allow == true)
  loadingPrivacy = false
end

local function onExtendedOpcode(protocol, opcode, buffer)
  buffer = L.joinPart(chunkParts, buffer)
  if not buffer then return end
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' or type(msg.data) ~= 'table' or not window then return end
  if msg.action == 'result' then
    showResult(msg.data)
    show()
  elseif msg.action == 'equip' then
    onEquip(msg.data)
  elseif msg.action == 'tree' then
    if L.onTree(state, msg.data) then refreshTreeButton() end
  elseif msg.action == 'denied' then
    onDenied(msg.data)
    show()
  elseif msg.action == 'privacy' then
    onPrivacy(msg.data)
  end
end

-- ---------------------------------------------------------------- requests
function inspectName(name)
  local clean = L.cleanName(name)
  if not clean then
    show()
    setStatus('Enter the name of a player.', L.COLORS.red)
    return
  end
  show()
  setStatus('Inspecting ' .. clean .. '...', L.COLORS.dim)
  send('inspect', { name = clean })
end

function inspectTyped()
  if window then inspectName(window.nameEdit:getText()) end
end

function inspectCreature(creature)
  if not creature or not creature:isPlayer() then return end
  show()
  setStatus('Inspecting ' .. creature:getName() .. '...', L.COLORS.dim)
  send('inspect', { cid = creature:getId() })
end

function onPrivacyToggle()
  if loadingPrivacy or not window then return end
  send('privacy', { allow = window.privacyBox:isChecked() })
end

-- ---------------------------------------------------------------- window
function show()
  if not window then return end
  if not window:isVisible() then
    window:show()
    send('privacy', {})
  end
  window:raise()
end

function hide()
  if window then
    window:hide()
    local tt = tooltips()
    if tt and tt.hideTip then tt.hideTip() end
  end
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
    return
  end
  show()
  -- the top menu hands the keyboard back to the game when it closes, after this call: take it again a moment later
  local function focusName()
    if window and window:isVisible() then
      window:focus()
      window.nameEdit:focus()
      window.nameEdit:selectAll()
    end
  end
  focusName()
  scheduleEvent(focusName, 150)
  if state.data == nil then setStatus('Type the name of a player who is online.', L.COLORS.dim) end
end

local function onGameEnd()
  hide()
  state = L.newState()
  if window then clearAll() setStatus('', nil) end
end

local function addMenuEntry()
  local gi = modules.game_interface
  if hooked or not gi or not gi.addMenuHook then return end
  gi.addMenuHook('chaosInspect', 'Inspect Player',
    function(menuPosition, lookThing, useThing, creatureThing) inspectCreature(creatureThing) end,
    function(menuPosition, lookThing, useThing, creatureThing)
      return creatureThing ~= nil and creatureThing:isPlayer()
    end)
  hooked = true
end

function init()
  window = g_ui.displayUI('playerinspect')
  window:hide()
  buildSlots()
  g_keyboard.bindKeyDown('Enter', inspectTyped, window)
  ProtocolGame.registerExtendedOpcode(OPCODE, safe('opcode', onExtendedOpcode))
  connect(g_game, { onGameEnd = onGameEnd })
  addMenuEntry()
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  if hooked and modules.game_interface and modules.game_interface.removeMenuHook then
    modules.game_interface.removeMenuHook('chaosInspect')
  end
  hooked = false
  if window then
    window:destroy()
    window = nil
  end
end
