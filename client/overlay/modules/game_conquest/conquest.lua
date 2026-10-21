-- The Conquest vendor (server data/scripts/chaos/conquest.lua, extended opcode 167, JSON {action, data}; the state comes
-- through Chaos.sendChunked and is joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | close | buy {k}
--   server -> client  state {...} (see conquestview.lua) | result {ok, text} | npc {} (Iselde Varrow opens the window)
-- Tabs: Uniques, Set Pieces, Raid & Ascended, Cinderheart (Omen Keys of a chosen kind, Ascended Shards, conversions),
-- Refine (a worn item one rarity up), Progress (bad-luck protection, today's tokens per source). One purchase at a time:
-- a Buy click disables every Buy button until the answer comes (BUY_WAIT_MS at most). Menu: Economy > Conquest Vendor.

local OPCODE = 167
local V = ConquestView

local window
local state
local tabId = 'uniques'
local handlers = {}
local reported = {}
local tabButtons = {}
local buying = false
local buyTimeout
local BUY_WAIT_MS = 4000

local function alive(w)
  return w ~= nil and w ~= false and not w:isDestroyed()
end

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[conquest] ' .. name .. ': ' .. tostring(res))
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

local function setStatus(text, color)
  if alive(window) and alive(window.status) then
    window.status:setText(text or '')
    window.status:setColor(color or V.COLORS.dim)
  end
end

local buy

local function fillRow(w, r)
  if not (alive(w) and alive(w.item) and alive(w.buy)) then return end
  w.item:setItemId(0)
  if r.clientId > 0 then w.item:setItemId(r.clientId) end
  w.item:setVisible(r.clientId > 0)
  w.name:setText(r.name)
  w.name:setColor(r.color)
  w.sub:setText(r.sub)
  w.price:setText(r.priceText)
  w.price:setColor(r.priceColor)
  w.buy:setText(r.buyText)
  w.buy:setEnabled(r.canBuy and not buying)
  w:setTooltip(r.tip)
  w.buy:setTooltip(r.tip)
  w:setOpacity(r.locked and 0.6 or 1)
  local key = r.key
  w.buy.onClick = function() buy(key) end
end

local function drawList()
  local list = alive(window) and alive(window.listFrame) and window.listFrame.list or nil
  if not alive(list) then return end
  list:destroyChildren()
  if tabId == 'progress' then
    for _, line in ipairs(V.progressLines(state)) do
      local l = g_ui.createWidget('ConquestLine', list)
      l:setText(line)
    end
    return
  end
  local rows = V.rows(state, tabId)
  if #rows == 0 then
    local l = g_ui.createWidget('ConquestLine', list)
    l:setText(V.emptyText(tabId))
    return
  end
  for _, r in ipairs(rows) do
    fillRow(g_ui.createWidget('ConquestRow', list), r)
  end
end

local function redraw()
  if not alive(window) then return end
  window.header:setText(V.header(state))
  local text, color = V.placeText(state)
  window.placeLabel:setText(text)
  window.placeLabel:setColor(color)
  for id, b in pairs(tabButtons) do
    if alive(b) then b:setChecked(id == tabId) end
  end
  drawList()
end

local function buyDone()
  buying = false
  if buyTimeout then
    removeEvent(buyTimeout)
    buyTimeout = nil
  end
end

buy = function(key)
  if not state or buying or type(key) ~= 'string' then return end
  buying = true
  setStatus(tr('Sending your order...'), V.COLORS.dim)
  send('buy', { k = key })
  buyTimeout = scheduleEvent(function()
    buyTimeout = nil
    buying = false
    redraw()
  end, BUY_WAIT_MS)
  -- never rebuild the list from inside a Buy click: only disable the buttons in place
  local list = alive(window) and alive(window.listFrame) and window.listFrame.list or nil
  if alive(list) then
    for _, w in ipairs(list:getChildren()) do
      if alive(w) and w.buy and alive(w.buy) then w.buy:setEnabled(false) end
    end
  end
end

function selectTab(id)
  tabId = V.tab(id).id
  redraw()
end

local function buildTabs()
  local bar = alive(window) and window.tabBar or nil
  if not alive(bar) then return end
  bar:destroyChildren()
  tabButtons = {}
  for _, t in ipairs(V.TABS) do
    local b = g_ui.createWidget('ChaosTabButton', bar)
    b:setText(tr(t.text))
    if t.tip then b:setTooltip(tr(t.tip)) end
    -- an even share of the bar (a fixed 112 px cut "Raid and Ascended"); 112 before the bar has its width
    local n, w = #V.TABS, bar:getWidth()
    b:setWidth(w > 0 and math.floor((w - 3 * (n - 1)) / n) or 112)
    local id = t.id
    b.onClick = function() selectTab(id) end
    tabButtons[id] = b
  end
end

-- ---------------------------------------------------------------- server messages
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    state = data
    buyDone()
    redraw()
  elseif msg.action == 'result' then
    buyDone()
    setStatus(tostring(data.text or ''), data.ok and V.COLORS.good or V.COLORS.bad)
    redraw()
  elseif msg.action == 'npc' then
    show()
  end
end

function show()
  if not alive(window) then return end
  send('open')
  window:show()
  window:raise()
  window:focus()
  redraw()
end

function hide()
  if alive(window) and window:isVisible() then
    window:hide()
    send('close')
  end
end

function toggle()
  if alive(window) and window:isVisible() then hide() else show() end
end

-- for other modules and tests
function getState() return { state = state, tab = tabId, visible = alive(window) and window:isVisible() or false, buying = buying } end
function getWindow() return window end
function setState(s) state = s redraw() end

-- ---------------------------------------------------------------- menu
local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    local ok, avail = pcall(function() return api.available and api.available() or {} end)
    for _, text in ipairs(ok and avail.economy or {}) do
      if text == 'Conquest Vendor' then handlers.menu = true return end
    end
    handlers.menu = pcall(api.addEntry, 'economy',
      { text = 'Conquest Vendor', icon = 'market', modules = { 'game_conquest' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  state = nil
  addMenu()
end

local function onGameEnd()
  buyDone()
  if alive(window) then window:hide() end
  state = nil
end

function init()
  g_ui.importStyle('conquest')
  local ok, ui = pcall(g_ui.createWidget, 'ConquestWindow', rootWidget)
  if ok and ui then
    window = ui
    window:hide()
    buildTabs()
  else
    g_logger.warning('[conquest] window not loaded: ' .. tostring(ui))
  end
  handlers.opcode = safe('opcode', onMessage)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  addMenu()
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  buyDone()
  disconnect(g_game, handlers.game)
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if alive(window) then window:destroy() end
  window = nil
  tabButtons = {}
  handlers = {}
end
