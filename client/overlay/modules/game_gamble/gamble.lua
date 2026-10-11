-- The Gambler (server data/scripts/chaos/gamble.lua, extended opcode 199, JSON {action, data}; the state comes through
-- Chaos.sendChunked and is joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | close | buy {i, w, id} | reroll {w}
--   server -> client  state {...} (see gambleview.lua) | result {ok, text, reveal} | npc {} (the Gambler opens the window)
-- A grid of sealed crates (the look, the slot, the item level and the price; the rarity hidden), the countdown to the
-- next stock, the early refresh, the odds and the reveal of the last purchase. Buying works next to the Gambler only, the
-- server checks it. Menu: Economy > The Gambler (ChaosTopBar.addEntry).

local OPCODE = 199
local V = GambleView

local window
local state
local receivedAt = 0
local tickEvent
local refreshAsked = false
local handlers = {}
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[gamble] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function now() return g_clock.seconds() end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function setStatus(text, color)
  if window then
    window.status:setText(text or '')
    window.status:setColor(color or V.COLORS.dim)
  end
end

local function showReveal(last)
  if not window then return end
  local text, color = V.reveal(last)
  window.revealPanel.text:setText(text ~= '' and text or tr('Pick a crate. Its rarity shows when the seal breaks.'))
  window.revealPanel.text:setColor(text ~= '' and color or V.COLORS.dim)
  if last and tonumber(last.c) and tonumber(last.c) > 0 then
    window.revealPanel.item:setItemId(tonumber(last.c))
    window.revealPanel.item:setVisible(true)
    window.revealPanel.frame:setBorderColor(color)
  else
    window.revealPanel.item:setVisible(false)
    window.revealPanel.frame:setBorderColor('#3a2c22')
  end
end

local function drawGrid()
  local list = window.gridFrame.grid
  list:destroyChildren()
  for _, c in ipairs(V.cells(state)) do
    local w = g_ui.createWidget('GambleCell', list)
    if c.clientId > 0 then w.item:setItemId(c.clientId) end
    w.name:setText(c.name)
    w.slot:setText(c.slotText)
    w.level:setText(c.levelText)
    w.price:setText(c.priceText)
    w.price:setColor(c.priceColor)
    w.buy:setText(c.buyText)
    w.buy:setEnabled(c.canBuy)
    w:setTooltip(c.tip)
    w.buy:setTooltip(c.tip)
    w.seal:setVisible(not c.sold)
    w:setOpacity(c.sold and 0.55 or 1)
    local i, id = c.i, c.id
    w.buy.onClick = function()
      if state then
        setStatus(tr('Breaking the seal...'), V.COLORS.dim)
        send('buy', { i = i, w = state.w, id = id })
      end
    end
  end
end

local function updateClock()
  if not window or not state then return end
  local elapsed = now() - receivedAt
  window.gridPlate.refreshLabel:setText(V.refreshText(state, elapsed))
  if V.left(state, elapsed) <= 0 and not refreshAsked then
    refreshAsked = true -- once: the server sends the new stock
    send('open')
  end
end

local function stopTick()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

local function tick()
  tickEvent = nil
  updateClock()
  if window and window:isVisible() then
    tickEvent = scheduleEvent(tick, 1000)
  end
end

local function redraw()
  if not window or not state then return end
  window.header:setText(V.header(state))
  local text, color = V.nearText(state)
  window.nearLabel:setText(text)
  window.nearLabel:setColor(color)
  drawGrid()
  local rt, ok, tip = V.reroll(state)
  window.rerollButton:setText(rt)
  window.rerollButton:setEnabled(ok)
  window.rerollButton:setTooltip(tip)
  window.oddsLabel:setText(V.oddsText(state))
  showReveal(state.last)
  updateClock()
end

-- ---------------------------------------------------------------- server messages
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    state = data
    receivedAt = now()
    refreshAsked = false
    redraw()
  elseif msg.action == 'result' then
    setStatus(data.text or '', data.ok and V.COLORS.good or V.COLORS.bad)
    if data.reveal then
      showReveal(data.reveal)
      local _, color = V.reveal(data.reveal)
      setStatus(data.text or '', color)
    end
  elseif msg.action == 'npc' then
    show()
  end
end

-- ---------------------------------------------------------------- buttons
function reroll()
  if state then send('reroll', { w = state.w }) end
end

function refresh()
  send('open')
end

function show()
  if not window then return end
  send('open')
  window:show()
  window:raise()
  window:focus()
  stopTick()
  tick()
end

function hide()
  stopTick()
  if window and window:isVisible() then
    window:hide()
    send('close')
  end
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

-- for other modules and tests
function getState() return { state = state, visible = window and window:isVisible() or false } end
function getWindow() return window end
function setState(s) state = s receivedAt = now() redraw() end

-- ---------------------------------------------------------------- menu
local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    -- once: after a reload of this module the entry is still there (it calls the module by name)
    local ok, avail = pcall(function() return api.available and api.available() or {} end)
    for _, text in ipairs(ok and avail.economy or {}) do
      if text == 'The Gambler' then handlers.menu = true return end
    end
    handlers.menu = pcall(api.addEntry, 'economy',
      { text = 'The Gambler', icon = 'market', modules = { 'game_gamble' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  state = nil
  addMenu()
end

local function onGameEnd()
  stopTick()
  if window then window:hide() end
  state = nil
end

function init()
  g_ui.importStyle('gamble')
  local ok, ui = pcall(g_ui.createWidget, 'GambleWindow', rootWidget)
  if ok and ui then
    window = ui
    window:hide()
  else
    g_logger.warning('[gamble] window not loaded: ' .. tostring(ui))
  end
  handlers.opcode = safe('opcode', onMessage)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  addMenu()
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  stopTick()
  disconnect(g_game, handlers.game)
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if window then window:destroy() window = nil end
  handlers = {}
end
