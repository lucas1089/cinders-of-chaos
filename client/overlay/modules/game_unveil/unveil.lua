-- Unveil window (server: server/data/scripts/chaos/veiled.lua, extended opcode 196, JSON {action, data}).
-- The Orb of Unveiling used on a veiled item ("Use with", or the crafting bench) opens it with three cards: the veiled
-- modifiers the item offers (rolled once on the server and kept on the item, so the window shows the same three every
-- time). Pick a card, then Unveil: the choice is final and takes one orb.
--   server -> client  open {...} | result {ok, text, veil}
--   client -> server  choose {path, id, sig, choice}
-- The logic is in unveilview.lua (tested by unveilview_test.lua).

local OPCODE = 196
local V = UnveilView

local window
local data
local selected
local done = false

local function send(action, payload)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = payload or {} }))
  end
end

local function cardWidget(i)
  return window and window:getChildById('card' .. i)
end

local function refresh()
  if not window or not data then return end
  local cards = V.cards(data)
  for i = 1, 3 do
    local w = cardWidget(i)
    local c = cards[i]
    w:setVisible(c ~= nil)
    if c then
      w.tier:setText(c.tierText)
      w.tier:setColor(c.tierColor)
      w.name:setText(c.name)
      w.text:setText(V.cardText(c))
      w.range:setText(c.rangeText)
      w.hook:setText(c.hookText)
      local chosen = selected == c.i
      w:setBorderWidth(chosen and 2 or 0)
      w:setBorderColor(c.tierColor)
      w:setOpacity((done and not chosen) and 0.45 or 1)
      local idx = c.i
      w.onClick = function()
        if done then return true end
        selected = idx
        refresh()
        return true
      end
    end
  end
  window.statusLabel:setText(V.statusText(data, selected))
  window.statusLabel:setColor(V.COLORS.text)
  window.orbsLabel:setText(V.orbsText(data.orbs))
  window.confirmButton:setEnabled(not done and V.canConfirm(data, selected))
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

function confirm()
  local req = V.request(data, selected)
  if not req or done then return end
  window.confirmButton:setEnabled(false)
  send('choose', req)
end

local function onOpen(d)
  data, selected, done = d, nil, false
  window.icon:setItemId(tonumber(d.clientId) or 0)
  window.header:setText(V.headerText(d))
  refresh()
  show()
end

local function onResult(res)
  if not window then return end
  local text, color = V.resultText(res)
  if res.ok then
    done = true
    if data then data.orbs = math.max(0, (tonumber(data.orbs) or 1) - 1) end
    refresh()
  else
    refresh()
  end
  window.statusLabel:setText(text)
  window.statusLabel:setColor(color)
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then return end
  local d = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'open' then
    onOpen(d)
  elseif msg.action == 'result' then
    onResult(d)
  end
end

local function onGameEnd()
  hide()
  data, selected, done = nil, nil, false
end

function init()
  window = g_ui.displayUI('unveil')
  window:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if window then window:destroy() end
  window = nil
end
