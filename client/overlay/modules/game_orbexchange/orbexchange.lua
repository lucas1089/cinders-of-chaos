-- Orb Exchange window: the order book of the crafting orbs (orb for orb, orb for gold).
-- Server: server/data/scripts/chaos/orbexchange.lua, extended opcode 209 (JSON {action, data}, sent with
-- Chaos.sendChunked and joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | book {base, quote, seq} | place {give, giveQty, want, wantQty, days} | cancel {id} | mine | wallet
--   server -> client  meta {orbs, fees, min, max, durations, defaultDuration, maxOpen, realmName, gold, have} |
--                     book {base, quote, asks, bids, last, open, high, low, change, vol, volQuote, points, trades, mine} |
--                     mine {open, closed, fills, owed, max} | wallet {gold, have} | done {what, text} | error {text}
-- The logic without client API is in orbexchangeview.lua (OrbExchangeView, tested by orbexchangeview_test.lua).
-- Menu: Economy > Orb Exchange (ChaosTopBar.addEntry); the Market window gets an "Orb Exchange" button.

local OPCODE = 209
local V = OrbExchangeView
local REFRESH = 5 -- seconds between two book requests while the Book tab is open

local window
local meta
local base, quote = nil, 'gold'
local side = 'buy'
local tab = 1
local tabs = {}
local orbWidgets = {}
local lastBook
local seq = 0
local refreshEvent
local handlers = {}
local marketButton
local updating = false
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[orbexchange] ' .. name .. ': ' .. tostring(res))
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

local function status(text, color)
  if not window then return end
  window.statusLabel:setText(text or '')
  window.statusLabel:setColor(color or '#d6c9ae')
end

local function stopRefresh()
  if refreshEvent then removeEvent(refreshEvent) refreshEvent = nil end
end

local function requestBook()
  if not base then return end
  seq = seq + 1
  send('book', { base = base, quote = quote, seq = seq })
end

local function scheduleRefresh()
  stopRefresh()
  refreshEvent = scheduleEvent(function()
    refreshEvent = nil
    if window and window:isVisible() and tab == 1 then
      requestBook()
      scheduleRefresh()
    end
  end, REFRESH * 1000)
end

local function orbItem(key)
  if key == V.GOLD then return 3031 end -- the gold coin's client id
  for _, o in ipairs(meta and meta.orbs or {}) do
    if o.k == key then return tonumber(o.item) or 0 end
  end
  return 0
end

-- an orb, or gold as a pile of coins (no count drawn)
local function setIcon(widget, key)
  widget:setItemId(orbItem(key))
  if key == V.GOLD then
    pcall(function() widget:setItemCount(100) widget:setShowCount(false) end)
  end
end

-- ---------------------------------------------------------------- wallet and the form
local function updateWallet()
  if not window or not meta then return end
  window.walletLabel:setText(string.format('%s exchange   Bank: %s gold', meta.realmName or 'Standard', V.money(meta.gold or 0)))
  for _, w in ipairs(orbWidgets) do
    local n = meta.have and meta.have[w.key] or 0
    w:setTooltip(string.format('%s\nYou carry %s.', V.assetName(meta, w.key), V.money(n)))
  end
  if base then
    local f = window.bookPanel.formFrame
    if side == 'sell' then
      f.haveLabel:setText(string.format('You carry %s %s', V.money(meta.have and meta.have[base] or 0), V.shortName(meta, base)))
    elseif quote == V.GOLD then
      f.haveLabel:setText(string.format('Bank: %s gold', V.money(meta.gold or 0)))
    else
      f.haveLabel:setText(string.format('You carry %s %s', V.money(meta.have and meta.have[quote] or 0), V.shortName(meta, quote)))
    end
  end
end

local function formData()
  local f = window.bookPanel.formFrame
  local opt = f.daysCombo:getCurrentOption()
  return { side = side, qty = f.qtyEdit:getText(), price = f.priceEdit:getText(), days = opt and opt.data or nil }
end

local function updatePreview()
  if not window or not meta or not base then return end
  local f = window.bookPanel.formFrame
  local req, prev = V.form(formData(), base, quote, meta)
  if req then
    f.previewLabel:setText(V.previewText(req, prev, side, base, quote, meta))
    f.previewLabel:setColor('#d6c9ae')
    f.placeButton:setEnabled(true)
  else
    f.previewLabel:setText(prev or '')
    f.previewLabel:setColor('#8c8070')
    f.placeButton:setEnabled(false)
  end
end

function setSide(s)
  side = s == 'sell' and 'sell' or 'buy'
  if not window then return end
  local f = window.bookPanel.formFrame
  f.buyButton:setChecked(side == 'buy')
  f.sellButton:setChecked(side == 'sell')
  f.placeButton:setText(side == 'buy' and tr('Place buy order') or tr('Place sell order'))
  updateWallet()
  updatePreview()
end

-- ---------------------------------------------------------------- the book
local function renderChart(points, hours)
  local chart = window.bookPanel.statsFrame.chart
  chart:destroyChildren()
  local w, h = chart:getWidth() - 4, chart:getHeight() - 4
  local rects = V.chart(points or {}, hours or 24, w, h)
  for _, r in ipairs(rects) do
    local rw = g_ui.createWidget('OrbxRect', chart)
    rw:setMarginLeft(r.x + 2)
    rw:setMarginTop(r.y + 2)
    rw:setSize({ width = r.w, height = r.h })
    rw:setBackgroundColor(r.kind == 'line' and '#e8b84a' or '#3a3339')
  end
  window.bookPanel.statsFrame.chartEmpty:setVisible(#rects == 0)
end

local function renderBook(b)
  lastBook = b
  local p = window.bookPanel
  local list = p.bookFrame.bookList
  list:destroyChildren()
  -- as many rows per side as fit: the list height in 18 px rows, one for the spread
  local rowsPerSide = math.max(3, math.floor((list:getHeight() / 18 - 1) / 2))
  for _, r in ipairs(V.bookRows(b, rowsPerSide)) do
    local w = g_ui.createWidget('OrbxBookRow', list)
    w.price:setText(r.price)
    w.qty:setText(r.qty)
    w.orders:setText(r.kind == 'spread' and '' or r.orders)
    w.total:setText(r.kind == 'spread' and '' or r.total)
    if r.kind == 'spread' then
      w.price:setColor('#8c8070')
      w.qty:setColor('#8c8070')
      w.price:setWidth(180)
      w:setBackgroundColor('#1a151a')
    else
      w.price:setColor(r.kind == 'ask' and V.COLORS.ask or V.COLORS.bid)
      w.bar:setWidth(math.floor((list:getWidth() - 4) * (r.bar or 0)))
      w.bar:setBackgroundColor(r.kind == 'ask' and '#5a0a0a66' or '#1a4a1a66')
      w:setTooltip(r.kind == 'ask' and tr('Click to buy at this price') or tr('Click to sell at this price'))
      local row = r
      w.onClick = function()
        local fill = V.fromRow(row)
        if not fill then return true end
        updating = true
        local f = window.bookPanel.formFrame
        f.qtyEdit:setText(fill.qty)
        f.priceEdit:setText(fill.price)
        updating = false
        setSide(fill.side)
        return true
      end
    end
  end
  local s = p.statsFrame
  local unit = V.assetName(meta, quote)
  s.lastCaption:setText(tr('Last price per %s', V.shortName(meta, base)))
  s.lastValue:setText(b.last and (V.priceText(b.last) .. ' ' .. unit) or tr('No trades yet'))
  local ct, cc = V.changeText(b.change)
  s.changeValue:setText(tr('24h change: %s', ct))
  s.changeValue:setColor(cc)
  s.rangeValue:setText(b.high and tr('High %s  Low %s', V.priceText(b.high), V.priceText(b.low)) or tr('High -  Low -'))
  s.volValue:setText(tr('24h volume: %s %s', V.money(b.vol or 0), V.shortName(meta, base)))
  s.volQuoteValue:setText(tr('24h turnover: %s %s', V.compact(b.volQuote or 0), V.shortName(meta, quote)))
  s.chartLabel:setText(tr('Average price per hour, last %d hours', b.hours or 24))
  renderChart(b.points, b.hours)
  local tl = p.tradesFrame.tradeList
  tl:destroyChildren()
  local maxRows = math.max(1, math.floor(tl:getHeight() / 16))
  for i, t in ipairs(b.trades or {}) do
    if i > maxRows then break end
    local w = g_ui.createWidget('OrbxTradeRow', tl)
    w.price:setText(V.priceText(t.p) .. ' ' .. V.shortName(meta, quote))
    w.price:setColor(t.side == 'buy' and V.COLORS.bid or V.COLORS.ask)
    w.qty:setText(V.money(t.q) .. ' ' .. V.shortName(meta, base))
    w.ago:setText(V.ago(t.ago))
  end
  p.tradesFrame.tradesHead:setText(#(b.trades or {}) > 0 and tr('Last trades') or tr('Last trades: none yet'))
  p.pairLabel:setText(string.format('%s / %s%s', V.assetName(meta, base), V.assetName(meta, quote),
    (b.mine or 0) > 0 and tr('  (%d of yours on the book)', b.mine) or ''))
end

local function fillQuotes()
  local combo = window.bookPanel.quoteCombo
  updating = true
  combo:clearOptions()
  for _, k in ipairs(V.quotes(meta, base)) do
    combo:addOption(k == V.GOLD and tr('Gold') or V.assetName(meta, k), k)
  end
  if quote ~= V.GOLD and quote == base then quote = V.GOLD end
  combo:setCurrentOption(quote == V.GOLD and tr('Gold') or V.assetName(meta, quote))
  updating = false
  setIcon(window.bookPanel.quoteIcon, quote)
end

local function selectBase(key)
  base = key
  for _, w in ipairs(orbWidgets) do w:setChecked(w.key == key) end
  fillQuotes()
  local f = window.bookPanel.formFrame
  f.qtyUnit:setText(V.shortName(meta, base))
  f.priceUnit:setText(V.shortName(meta, quote) .. ' ' .. tr('each'))
  window.bookPanel.pairLabel:setText(string.format('%s / %s', V.assetName(meta, base), V.assetName(meta, quote)))
  updateWallet()
  updatePreview()
  requestBook()
end

local function buildStrip()
  local strip = window.bookPanel.orbStrip
  strip:destroyChildren()
  orbWidgets = {}
  for _, o in ipairs(meta.orbs or {}) do
    local w = g_ui.createWidget('OrbxOrb', strip)
    w:setItemId(tonumber(o.item) or 0)
    w.key = o.k
    w.onClick = function() selectBase(o.k) return true end
    orbWidgets[#orbWidgets + 1] = w
  end
  local days = window.bookPanel.formFrame.daysCombo
  days:clearOptions()
  for _, d in ipairs(meta.durations or { 7 }) do
    days:addOption((d == 1 and tr('%d day', d) or tr('%d days', d)), d)
  end
  local def = meta.defaultDuration or 7
  days:setCurrentOption((def == 1 and tr('%d day', def) or tr('%d days', def)))
end

-- ---------------------------------------------------------------- my orders
local function renderMine(d)
  local m = window.minePanel
  m.openHead:setText(tr('Open orders (%d / %d)', #(d.open or {}), d.max or (meta and meta.maxOpen) or 20)
    .. ((d.owed or 0) > 0 and tr('   %d deliveries waiting', d.owed) or ''))
  m.openList:destroyChildren()
  for _, o in ipairs(d.open or {}) do
    local w = g_ui.createWidget('OrbxOrderRow', m.openList)
    setIcon(w.giveIcon, o.give)
    setIcon(w.wantIcon, o.want)
    w.title:setText(V.orderTitle(o, meta))
    w.sub:setText(V.orderSub(o, meta))
    w.bar:setPercent(math.floor(V.progress(o) * 100))
    w.bar:setText(string.format('%d%%', math.floor(V.progress(o) * 100)))
    local id = o.id
    w.action:setEnabled(o.state == 'active')
    w.action.onClick = function()
      send('cancel', { id = id })
      return true
    end
  end
  m.openEmpty:setVisible(#(d.open or {}) == 0)
  m.fillList:destroyChildren()
  for _, f in ipairs(d.fills or {}) do
    local w = g_ui.createWidget('OrbxFillRow', m.fillList)
    w:setText(V.fillText(f, meta))
    w:setColor(f.role == 'maker' and '#d6c9ae' or '#f6cf72')
  end
  if #(d.fills or {}) == 0 then
    local w = g_ui.createWidget('OrbxFillRow', m.fillList)
    w:setText(tr('No fills yet.'))
    w:setColor('#8c8070')
  end
  m.closedList:destroyChildren()
  for _, o in ipairs(d.closed or {}) do
    local w = g_ui.createWidget('OrbxOrderRow', m.closedList)
    setIcon(w.giveIcon, o.give)
    setIcon(w.wantIcon, o.want)
    w.title:setText(V.orderTitle(o, meta))
    w.sub:setText(V.orderSub(o, meta))
    -- closed: no bar, no button; the state is in the line under the title
    w.bar:setVisible(false)
    w.bar:setWidth(0)
    w.action:setVisible(false)
    w.action:setWidth(0)
  end
end

-- ---------------------------------------------------------------- tabs
local function showTab(i)
  tab = i
  for j, b in ipairs(tabs) do b:setChecked(j == i) end
  window.bookPanel:setVisible(i == 1)
  window.minePanel:setVisible(i == 2)
  if i == 1 then
    requestBook()
    scheduleRefresh()
  else
    stopRefresh()
    send('mine')
  end
end

-- ---------------------------------------------------------------- server messages
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' or not window then return end
  local d = type(msg.data) == 'table' and msg.data or {}
  local a = msg.action
  if a == 'meta' then
    meta = d
    buildStrip()
    local first = base or (meta.orbs and meta.orbs[1] and meta.orbs[1].k)
    if first then selectBase(first) end
    updateWallet()
  elseif a == 'book' then
    if meta and d.base == base and d.quote == quote then renderBook(d) end
  elseif a == 'mine' then
    renderMine(d)
  elseif a == 'wallet' then
    if meta then
      meta.gold, meta.have = d.gold, d.have
      updateWallet()
    end
  elseif a == 'done' then
    status(d.text, '#6cc46c')
    if d.what == 'place' then
      local f = window.bookPanel.formFrame
      updating = true
      f.qtyEdit:setText('')
      updating = false
      updatePreview()
    end
    if tab == 1 then requestBook() else send('mine') end
  elseif a == 'error' then
    status(d.text, '#e05a4a')
  end
end

-- ---------------------------------------------------------------- actions
function place()
  if not meta or not base then return end
  local req, why = V.form(formData(), base, quote, meta)
  if not req then
    status(why, '#e05a4a')
    return
  end
  send('place', req)
end

function refresh()
  if tab == 1 then requestBook() else send('mine') end
  send('wallet')
end

function hide()
  stopRefresh()
  if window then window:hide() end
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  status('')
  send('open')
  showTab(tab)
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

-- for other modules and tests
function getState()
  return { visible = window and window:isVisible() or false, base = base, quote = quote, side = side, tab = tab,
    asks = lastBook and #(lastBook.asks or {}) or 0, bids = lastBook and #(lastBook.bids or {}) or 0, orbs = #orbWidgets }
end

function selectPair(b, q)
  quote = q or quote
  if b then selectBase(b) end
end

function setForm(qty, price)
  if not window then return end
  local f = window.bookPanel.formFrame
  f.qtyEdit:setText(tostring(qty or ''))
  f.priceEdit:setText(tostring(price or ''))
  updatePreview()
end

function openTab(i)
  showTab(i)
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'economy',
      { text = 'Orb Exchange', icon = 'market', modules = { 'game_orbexchange' }, fns = { 'toggle' } })
  end
end

-- a button in the Market window (game_market): next to its Close button
local function addMarketButton()
  if marketButton then return end
  local mw = rootWidget and rootWidget:recursiveGetChildById('chaosMarketWindow')
  if not mw or not mw.closeButton then return end
  marketButton = g_ui.createWidget('ChaosButton', mw)
  marketButton:setId('orbExchangeButton')
  marketButton:setText(tr('Orb Exchange'))
  marketButton:setSize({ width = 110, height = 24 })
  marketButton:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  marketButton:addAnchor(AnchorRight, 'closeButton', AnchorLeft)
  marketButton:setMarginRight(8)
  marketButton:setTooltip(tr('Trade crafting orbs for orbs or gold on the order book'))
  marketButton.onClick = function()
    show()
    return true
  end
end

local function onGameStart()
  meta, lastBook = nil, nil
  addMenu()
  addMarketButton()
end

local function onGameEnd()
  hide()
  meta, lastBook = nil, nil
end

function init()
  local ok, ui = pcall(g_ui.displayUI, 'orbexchange')
  if not ok or not ui then
    g_logger.warning('[orbexchange] window not loaded: ' .. tostring(ui))
    return
  end
  window = ui
  window:hide()
  for i, name in ipairs({ tr('Book'), tr('My Orders') }) do
    local b = g_ui.createWidget('ChaosTabButton', window.tabBar)
    b:setText(name)
    b:setWidth(math.max(80, b:getTextSize().width + 24))
    b.onClick = function() showTab(i) end
    tabs[i] = b
  end
  tabs[1]:setChecked(true)
  local p = window.bookPanel
  p.quoteCombo.onOptionChange = safe('quote', function(w, text, data)
    if updating or not data then return end
    quote = data
    setIcon(p.quoteIcon, quote)
    p.formFrame.priceUnit:setText(V.shortName(meta, quote) .. ' ' .. tr('each'))
    updateWallet()
    updatePreview()
    requestBook()
  end)
  local f = p.formFrame
  f.qtyEdit.onTextChange = safe('qty', function() if not updating then updatePreview() end end)
  f.priceEdit.onTextChange = safe('price', function() if not updating then updatePreview() end end)
  f.daysCombo.onOptionChange = safe('days', function() if not updating then updatePreview() end end)
  setSide('buy')
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, safe('opcode', onMessage))
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  connect(g_game, handlers.game)
  addMenu()
  addMarketButton()
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  if handlers.game then disconnect(g_game, handlers.game) end
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  stopRefresh()
  if marketButton then marketButton:destroy() marketButton = nil end
  if window then window:destroy() window = nil end
  tabs, orbWidgets, handlers = {}, {}, {}
  meta, lastBook = nil, nil
end
