-- The waystone device window (the glue; the rules are waystonelogic.lua, tested there). The base server's waystone
-- system sends "show" on extended opcode 202 when the device is used (or a Waystone Tier is used on it, or in the own
-- hideout: server/tools/patch_waystone_hideout.py part 2); this window lists the six tiers with the count the player
-- carries, opens the portals of the picked one and sets the portal look. Protocol: waystonelogic.lua.
local W = ChaosWaystone

local window
local rows = {}
local rowWidgets = {}
local selected = 1
local looks = {}
local building = false

local function send(msg)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(W.OPCODE, json.encode(msg))
  end
end

local function setStatus(text)
  if window then window.statusLabel:setText(text or '') end
end

local function refreshButtons()
  if not window then return end
  local row = rows[selected]
  window.openButton:setEnabled(W.teleportRequest(row) ~= nil)
end

local function pick(i)
  selected = i
  local w = rowWidgets[i]
  if w then w:focus() end
  refreshButtons()
end

local function showRows()
  if not window then return end
  window.tierList:destroyChildren()
  rowWidgets = {}
  for i, r in ipairs(rows) do
    local w = g_ui.createWidget('WaystoneTierRow', window.tierList)
    w.item:setItemId(r.look)
    w.name:setText(tr('Waystone Tier %s', r.roman))
    w.count:setText(W.countText(r, tr))
    w:setOpacity(r.usable and 1 or 0.55)
    w.onFocusChange = function(self, focused)
      if focused then
        selected = i
        refreshButtons()
      end
    end
    rowWidgets[i] = w
  end
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
end

function hide()
  if window then window:hide() end
end

function openPortals()
  local req = W.teleportRequest(rows[selected])
  if not req then
    setStatus(tr('You carry no waystone of this tier.'))
    return
  end
  setStatus(tr('Opening the portals...'))
  send(req)
end

function askLooks()
  send({ action = 'choice' })
end

local function showLooks(list)
  if not window then return end
  looks = list
  local box = window.lookBox
  building = true
  box:clearOptions()
  for _, c in ipairs(list) do
    box:addOption(c.text, c.id)
  end
  building = false
  box:setVisible(#list > 0)
  setStatus(#list > 1 and tr('Pick a portal look.') or tr('Only the default look is unlocked.'))
end

local function onLookChange(box, text, data)
  if building or data == nil then return end
  send({ action = 'choice_apply', choiceId = tonumber(data) })
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local okDecode, msg = pcall(json.decode, buffer)
  if not okDecode then return end
  local kind, text = W.classify(msg, tr)
  if kind == 'show' then
    rows = W.rows(msg)
    showRows()
    window.lookBox:setVisible(false)
    setStatus('')
    show()
    pick(W.firstRow(rows, msg.pick))
  elseif kind == 'close' then
    hide()
    if text and modules.game_textmessage and modules.game_textmessage.displayGameMessage then
      modules.game_textmessage.displayGameMessage(text)
    end
  elseif kind == 'choices' then
    showLooks(W.choices(msg))
  elseif kind == 'status' then
    setStatus(text)
  end
end

local function onGameEnd()
  hide()
  rows, rowWidgets, looks = {}, {}, {}
end

function init()
  window = g_ui.displayUI('waystone')
  window:hide()
  window.lookBox.onOptionChange = onLookChange
  ProtocolGame.registerExtendedOpcode(W.OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(W.OPCODE)
  if window then window:destroy() end
  window = nil
end
