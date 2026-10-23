-- Candlemarks (server data/scripts/chaos/candlemarks.lua, extended opcode 176, JSON {action, data}; the state comes
-- through Chaos.sendChunked and is joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | buy {k}
--   server -> client  hud {b, p, n, e, w} (every minute) | state (candlemarksview.lua) | result {ok, text} | npc {}
-- A small counter next to the Chaos menu bar (balance and minutes to the next coin; a click opens the shop) and the
-- shop window: one row per offer (look, name, text, price, this week's use of its limit, Buy). Menu: Economy >
-- Candlemarks (ChaosTopBar.addEntry); Osric the Chandler opens the window too. The server checks every purchase.
-- Pure parts: candlemarksview.lua (candlemarksview_test.lua).

local OPCODE = 176
local V = CandlemarksView

local window
local counter
local hud, hudAt = nil, 0
local state, stateAt = nil, 0
local handlers = {}
local reported = {}
local tickEvent
local buying = false

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[candlemarks] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function now() return g_clock.seconds() end

local function text(t)
  if type(t) ~= 'table' then return '' end
  if t[1] == '%s' or t[1] == '' then return V.plain(t) end
  return tr(t[1], (table.unpack or unpack)(t, 2))
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

-- ---------------------------------------------------------------- the counter
local function drawCounter()
  if not alive(counter) then return end
  if type(hud) ~= 'table' then
    counter:hide()
    return
  end
  local c = V.counter(hud, now() - hudAt)
  counter:setText(text(V.counterText(c)))
  counter:setTooltip(text(V.counterTooltip(c)))
  counter:setColor(c.earning and V.COLORS.gold or V.COLORS.dim)
  counter:show()
end

local function placeCounter()
  if alive(counter) then return end
  local gi = modules.game_interface
  local parent = gi and gi.getRootPanel and gi.getRootPanel() or g_ui.getRootWidget()
  if not parent then return end
  counter = g_ui.createWidget('CandlemarkCounter', parent)
  local bar = parent:getChildById('chaosMenuBar')
  if bar then
    counter:addAnchor(AnchorLeft, 'chaosMenuBar', AnchorRight)
    counter:addAnchor(AnchorVerticalCenter, 'chaosMenuBar', AnchorVerticalCenter)
    counter:setMarginLeft(6)
  else
    counter:addAnchor(AnchorTop, 'parent', AnchorTop)
    counter:addAnchor(AnchorRight, 'parent', AnchorRight)
    counter:setMarginTop(6)
    counter:setMarginRight(8)
  end
  counter.onClick = function() show() end
  counter:hide()
end

-- ---------------------------------------------------------------- the window
local function setStatus(t, color)
  if alive(window) and alive(window.status) then
    window.status:setText(text(t))
    window.status:setColor(color or V.COLORS.dim)
  end
end

local function render()
  if not alive(window) then return end
  local since = now() - stateAt
  local h = V.header(state, since)
  window.balance:setText(text(h.balance))
  window.next:setText(text(h.next))
  window.week:setText(text(h.week))
  window.shop:setText(text(h.shop))
  window.shop:setColor(state and state.near == false and V.COLORS.bad or V.COLORS.good)
  local list = window.listFrame.list
  list:destroyChildren()
  for i, r in ipairs(V.offers(state)) do
    local row = g_ui.createWidget('CandlemarkRow', list)
    if i % 2 == 0 then row:setBackgroundColor('#141014') end
    if r.cid > 0 then row.item:setItemId(r.cid) end
    local lines = V.offerLines(r)
    row.name:setText(text(lines.title))
    row.desc:setText(r.desc)
    row.price:setText(text(lines.price))
    row.limit:setText(text(lines.limit))
    row.buy:setEnabled(r.canBuy and not buying)
    if r.why then
      row.buy:setTooltip(text(r.why))
    end
    local key = r.key
    row.buy.onClick = function()
      if buying then return end
      buying = true
      setStatus({ 'Buying...' })
      send('buy', { k = key })
      scheduleEvent(function() buying = false end, 3000)
    end
  end
end

function show()
  if not alive(window) then return end
  window:show()
  window:raise()
  window:focus()
  send('open')
end

function hide()
  if alive(window) then window:hide() end
end

function toggle()
  if not alive(window) then return end
  if window:isVisible() then hide() else show() end
end

-- ---------------------------------------------------------------- the server
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' or type(msg.action) ~= 'string' then return end
  local d = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'hud' then
    hud, hudAt = d, now()
    drawCounter()
  elseif msg.action == 'state' then
    state, stateAt = d, now()
    hud, hudAt = d, now()
    drawCounter()
    render()
  elseif msg.action == 'result' then
    buying = false
    setStatus({ '%s', type(d.text) == 'string' and d.text:sub(1, 160) or '' }, d.ok == true and V.COLORS.good or V.COLORS.bad)
  elseif msg.action == 'npc' then
    show()
  end
end

-- ---------------------------------------------------------------- menu and lifecycle
local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if not api or not api.addEntry or handlers.menu then return end
  local ok, shown = pcall(api.available)
  for _, t in ipairs(ok and type(shown) == 'table' and shown.economy or {}) do
    if t == 'Candlemarks' then
      handlers.menu = true
      return
    end
  end
  handlers.menu = pcall(api.addEntry, 'economy',
    { text = 'Candlemarks', icon = 'market', modules = { 'game_candlemarks' }, fns = { 'toggle' } })
end

local function tick()
  drawCounter()
  tickEvent = scheduleEvent(safe('tick', tick), 15000)
end

local function onGameStart()
  hud, state, buying = nil, nil, false
  addMenu()
  placeCounter()
  drawCounter()
end

local function onGameEnd()
  hide()
  hud, state = nil, nil
  drawCounter()
end

function init()
  g_ui.importStyle('candlemarks')
  local ok, ui = pcall(g_ui.createWidget, 'CandlemarkWindow', rootWidget)
  if ok and ui then
    window = ui
    window:hide()
  else
    g_logger.warning('[candlemarks] window not loaded: ' .. tostring(ui))
  end
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  connect(g_game, handlers.game)
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, safe('opcode', onMessage))
  tickEvent = scheduleEvent(safe('tick', tick), 15000)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  if handlers.game then disconnect(g_game, handlers.game) end
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if tickEvent then removeEvent(tickEvent) end
  if alive(counter) then counter:destroy() end
  if alive(window) then window:destroy() end
  window, counter, hud, state, tickEvent = nil, nil, nil, nil, nil
  handlers = {}
end
