-- Professions (server data/scripts/chaos/professions.lua, extended opcode 195, JSON {action, data}; the state comes through
-- Chaos.sendChunked and is joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | close | sell {id, n} | sellAll
--   server -> client  state {...} (see professionsview.lua) | result {ok, text} | levelup {k, lv} | npc {} (a Material
--                     Broker opens the window)
-- Left: the four gathering professions (level, experience bar, the tier they gather) and where to gather (areas with the
-- nodes that are ready for you). Right: the Material Broker's board of the week (price x demand, sold today, carried) with
-- Sell per material and Sell All; selling works next to a broker only, the server checks it.
-- Menu: Economy > Professions (ChaosTopBar.addEntry).

local OPCODE = 195
local V = ProfessionsView

local window
local state
local handlers = {}
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[professions] ' .. name .. ': ' .. tostring(res))
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
  if window then
    window.status:setText(text or '')
    window.status:setColor(color or V.COLORS.dim)
  end
end

-- the look of a profession's current material (its highest tier)
local function lookOf(key, tier)
  for _, d in ipairs(state and state.demand or {}) do
    if d.p == key and tonumber(d.t) == tonumber(tier) then return tonumber(d.c) or 0 end
  end
  return 0
end

local function drawProfessions()
  local list = window.profList
  list:destroyChildren()
  for _, r in ipairs(V.profRows(state)) do
    local w = g_ui.createWidget('ProfessionRow', list)
    local p
    for _, x in ipairs(state.profs or {}) do if x.k == r.key then p = x end end
    local cid = lookOf(r.key, p and p.tier or 1)
    if cid > 0 then w.item:setItemId(cid) end
    w.name:setText(r.name)
    w.level:setText(tr('Level %d', r.level))
    w.tier:setText(r.tierText)
    w.tier:setColor(r.tierColor)
    w.bar:setPercent(r.pct)
    w.bar:setText(r.xpText)
    w:setTooltip(tr('%s\nTool: %s\n%s gathered in total', r.desc, r.tool, V.fmtNum(r.gathered)))
  end
end

local function drawAreas()
  local list = window.areaFrame.areaList
  list:destroyChildren()
  for _, a in ipairs(V.areaLines(state)) do
    local w = g_ui.createWidget('AreaRow', list)
    w.title:setText(a.title)
    w.title:setColor(a.color)
    w.text:setText(a.text)
    w:setTooltip(a.tip)
  end
end

local function drawBoard()
  local list = window.boardFrame.boardList
  list:destroyChildren()
  for _, r in ipairs(V.demandRows(state)) do
    local w = g_ui.createWidget('MaterialRow', list)
    if r.clientId > 0 then w.item:setItemId(r.clientId) end
    w.name:setText((r.name:gsub('^%l', string.upper)))
    w.name:setColor(r.tierColor or V.COLORS.text)
    w.info:setText(tr('%s tier %d, %s', V.profName(state, r.prof), r.tier, r.haveText))
    w.price:setText(r.priceText)
    w.mult:setText(r.multText)
    w.mult:setColor(r.multColor)
    w.sold:setText(r.soldText)
    w.sell:setEnabled(r.canSell)
    w.sell:setTooltip(r.canSell and tr('Sell %d for %s gold', r.units, V.fmtNum(r.worth))
      or (state.broker and tr('Nothing to sell, or the daily limit is reached') or tr('Stand next to a Material Broker')))
    local id = r.id
    w.sell.onClick = function() send('sell', { id = id }) end
  end
end

local function redraw()
  if not window or not state then return end
  window.header:setText(V.bonusText(state))
  drawProfessions()
  drawAreas()
  drawBoard()
  local est = V.sellAllEstimate(state)
  window.brokerState:setText(state.broker and tr('You are at a Material Broker: sell here.')
    or tr('Sell at a Material Broker (next to every temple; in Cinderhold and Mirewake in the Hall of Services).'))
  window.brokerState:setColor(state.broker and V.COLORS.good or V.COLORS.warn)
  window.sellAllButton:setEnabled(state.broker and est.units > 0)
  window.sellAllButton:setText(est.units > 0 and tr('Sell All (%s gold)', V.fmtNum(est.gold)) or tr('Sell All'))
  window.footer:setText(V.footer(state))
end

-- ---------------------------------------------------------------- server messages
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    state = data
    redraw()
  elseif msg.action == 'result' then
    setStatus(data.text or '', data.ok and V.COLORS.good or V.COLORS.bad)
  elseif msg.action == 'levelup' then
    setStatus(tr('%s level %d!', V.profName(state, data.k), tonumber(data.lv) or 0), V.COLORS.gold)
  elseif msg.action == 'npc' then
    show()
  end
end

-- ---------------------------------------------------------------- buttons
function sellAll()
  send('sellAll')
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
end

function hide()
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
function setState(s) state = s redraw() end

-- ---------------------------------------------------------------- menu
local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    -- once: after a reload of this module the entry is still there (it calls the module by name)
    local ok, avail = pcall(function() return api.available and api.available() or {} end)
    for _, text in ipairs(ok and avail.economy or {}) do
      if text == 'Professions' then handlers.menu = true return end
    end
    handlers.menu = pcall(api.addEntry, 'economy',
      { text = 'Professions', icon = 'skills', modules = { 'game_professions' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  state = nil
  addMenu()
end

local function onGameEnd()
  if window then window:hide() end
  state = nil
end

function init()
  g_ui.importStyle('professions')
  local ok, ui = pcall(g_ui.createWidget, 'ProfessionsWindow', rootWidget)
  if ok and ui then
    window = ui
    window:hide()
  else
    g_logger.warning('[professions] window not loaded: ' .. tostring(ui))
  end
  handlers.opcode = safe('opcode', onMessage)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  addMenu()
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game)
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if window then window:destroy() window = nil end
  handlers = {}
end
