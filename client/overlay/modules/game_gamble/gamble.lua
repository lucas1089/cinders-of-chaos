-- The Gambler (server data/scripts/chaos/gamble.lua, extended opcode 199, JSON {action, data}; the state comes through
-- Chaos.sendChunked and is joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | close | buy {i, w, id} | reroll {w}
--   server -> client  state {...} (see gambleview.lua) | result {ok, text, reveal} | npc {} (the Gambler opens the window)
-- A grid of sealed crates (the look, the slot, the item level and the price; the rarity hidden), the countdown to the
-- next stock, the early refresh, the odds and the reveal of the last purchase. Buying works next to the Gambler only, the
-- server checks it. Menu: Economy > The Gambler (ChaosTopBar.addEntry).
-- One purchase at a time: a Buy click disables every Buy button until the result or the state comes (BUY_WAIT_MS at
-- most). A state with the same crates fills the cells in place; only another stock builds new cells. Every widget call
-- checks that the window is still there: answers can come after Close or after the module was unloaded.

local OPCODE = 199
local V = GambleView

local window
local state
local receivedAt = 0
local tickEvent
local refreshAsked = false
local handlers = {}
local reported = {}
local cells = {}       -- the cell widgets of the grid, in the order of shownCells
local shownCells = {}  -- GambleView.cells of the last draw
local buying = false   -- a purchase is on its way: every Buy button waits for the server's answer
local buyTimeout       -- gives the buttons back when no answer comes (a request the server's rate limit dropped)
local BUY_WAIT_MS = 4000

-- a widget that is still there (the window can be gone after a module reload; a cell after a rebuild)
local function alive(w)
  return w ~= nil and w ~= false and not w:isDestroyed()
end

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
  if alive(window) and alive(window.status) then
    window.status:setText(text or '')
    window.status:setColor(color or V.COLORS.dim)
  end
end

-- the reveal (a result, or the last purchase in a state): it may come while the window is closed or after a reload
local function showReveal(last)
  if not alive(window) then return end
  local panel = window.revealPanel
  if not (alive(panel) and alive(panel.text) and alive(panel.item) and alive(panel.frame)) then return end
  local text, color = V.reveal(last)
  panel.text:setText(text ~= '' and text or tr('Pick a crate. Its rarity shows when the seal breaks.'))
  panel.text:setColor(text ~= '' and color or V.COLORS.dim)
  local cid = V.revealItem(last)
  if cid ~= panel.shownId then
    -- a new engine item for every look: Item::setId on the old one keeps the old look's animator when the new look
    -- has none, and a look id the client does not know gives an item with no look (cid 0 here: nothing is set)
    panel.item:setItemId(0)
    if cid > 0 then panel.item:setItemId(cid) end
    panel.shownId = cid
  end
  if cid > 0 then
    panel.item:setVisible(true)
    panel.frame:setBorderColor(color)
  else
    panel.item:setVisible(false)
    panel.frame:setBorderColor('#3a2c22')
  end
end

local buy

local function fillCell(w, c)
  if not (alive(w) and alive(w.item) and alive(w.buy)) then return end
  if w.shownId ~= c.clientId then
    w.item:setItemId(0)
    if c.clientId > 0 then w.item:setItemId(c.clientId) end
    w.shownId = c.clientId
  end
  w.name:setText(c.name)
  w.slot:setText(c.slotText)
  w.level:setText(c.levelText)
  w.price:setText(c.priceText)
  w.price:setColor(c.priceColor)
  w.buy:setText(c.buyText)
  w.buy:setEnabled(c.canBuy and not buying)
  w:setTooltip(c.tip)
  w.buy:setTooltip(c.tip)
  w.seal:setVisible(not c.sold)
  w:setOpacity(c.sold and 0.55 or 1)
  local i, id = c.i, c.id
  w.buy.onClick = function() buy(i, id) end
end

-- the same crates as on screen (a purchase, the gold, the countdown): the cells are filled again in place; another
-- stock: new cells. Never destroys a cell from inside its own Buy click (buy() only sends and disables).
local function drawGrid()
  local list = alive(window) and alive(window.gridFrame) and window.gridFrame.grid or nil
  if not alive(list) then return end
  local new = V.cells(state)
  local keep = V.sameCells(new, shownCells) and #cells == #new
  for _, w in ipairs(cells) do
    if not alive(w) then keep = false end
  end
  if not keep then
    list:destroyChildren()
    cells = {}
    for k = 1, #new do
      cells[k] = g_ui.createWidget('GambleCell', list)
    end
  end
  for k, c in ipairs(new) do
    fillCell(cells[k], c)
  end
  shownCells = new
end

local function setBuyButtons(enabled)
  for k, w in ipairs(cells) do
    local c = shownCells[k]
    if alive(w) and alive(w.buy) then
      w.buy:setEnabled(enabled == true and c ~= nil and c.canBuy == true)
    end
  end
end

local function buyDone()
  buying = false
  if buyTimeout then
    removeEvent(buyTimeout)
    buyTimeout = nil
  end
end

-- one purchase at a time: quick clicks on several crates send one request, the next one waits for the answer
buy = function(i, id)
  if not state or buying then return end
  buying = true
  setStatus(tr('Breaking the seal...'), V.COLORS.dim)
  send('buy', { i = i, w = state.w, id = id })
  setBuyButtons(false)
  buyTimeout = scheduleEvent(function()
    buyTimeout = nil
    buying = false
    setBuyButtons(true)
  end, BUY_WAIT_MS)
end

local function updateClock()
  if not alive(window) or not state then return end
  local elapsed = now() - receivedAt
  local label = alive(window.gridPlate) and window.gridPlate.refreshLabel or nil
  if not alive(label) then return end
  label:setText(V.refreshText(state, elapsed))
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
  if alive(window) and window:isVisible() then
    tickEvent = scheduleEvent(tick, 1000)
  end
end

local function redraw()
  if not alive(window) or not state then return end
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
    buyDone()
    redraw()
  elseif msg.action == 'result' then
    buyDone()
    setBuyButtons(true)
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
  if not alive(window) then return end
  send('open')
  window:show()
  window:raise()
  window:focus()
  stopTick()
  tick()
end

function hide()
  stopTick()
  if alive(window) and window:isVisible() then
    window:hide()
    send('close')
  end
end

function toggle()
  if alive(window) and window:isVisible() then hide() else show() end
end

-- for other modules and tests
function getState() return { state = state, visible = alive(window) and window:isVisible() or false, buying = buying } end
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
  buyDone()
  if alive(window) then window:hide() end
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
  buyDone()
  disconnect(g_game, handlers.game)
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if alive(window) then window:destroy() end
  window = nil
  cells, shownCells = {}, {}
  handlers = {}
end
