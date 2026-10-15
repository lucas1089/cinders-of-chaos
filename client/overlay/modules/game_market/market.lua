-- Market: our own player market for gold and Chaos Coins (Economy > Market in the top menu, Alt+E; the market item
-- of a depot locker opens it too). Server: server/data/scripts/chaos/market.lua, extended opcode 221 (JSON {action,
-- data}, long answers in parts joined by ProtocolGame.registerExtendedJSONOpcode). The logic without client API is
-- marketview.lua (marketview_test.lua).
--   client -> server  open | browse {filter} | tip {id} | buy {id, cur} | sellable | list {ref|pos, sid|cid, iid, count,
--                     gold, coins, days} | cancel {id} | mine | history | wallet
--                     buy orders: orders {q, cur, sort, mine, page} | myOrders | orderFind {q} | orderPost {sid, quantity,
--                     price, cur, days, filter} | orderCancel {id} | fillable {id} | fill {id, ref, sid, iid, count}
--   server -> client  meta | page | tip | sellable | mine | history | wallet | done {what, text} | error {text} | openWindow
--                     | orders | myOrders | orderFind | fillable
-- Tabs: Browse (search, filters, sorting, pages; a collapsible Modifiers section: up to 6 rows of modifier (typeahead
-- over the Codex names) / lowest value / lowest tier, all of them or at least N, sockets, quality, free prefix / suffix,
-- power, bound; hover = the full item tooltip of game_itemtooltip with the modifiers the search matched, Buy with a
-- confirmation), Sell (pick an item from the backpack or drag one in, prices, duration, the fee), My Offers (active,
-- sold, expired, cancelled; Cancel), History (purchases and sales), Buy Orders (the open orders of every buyer with Sell
-- to fill them from the backpack, your own with Cancel; on the right the form to post one: item, how many, price each in
-- gold or Chaos Coins, duration, lowest rarity / item level and the Browse tab's modifier filter).

local OPCODE = 221
local V = MarketView

local window
local meta
local tabs = {}
local tabIndex = 1
local tipCache = {} -- offer id -> tip
local tipAsked = {}
local hoveredRow
local lastFilter = { page = 1 }
local pageInfo = { page = 1, pages = 1, total = 0 }
local sellItems = {}
local selected -- the chosen Sell item: {ref | pos, sid | cid, iid, count, name, stack, rarity, ilvl}
local modCatalog -- V.modCatalog of the Codex data
local modRowWidgets = {}
local modsOpen = false
local updating = false

local okText, Text = pcall(dofile, '/modules/game_spellsupports/supportstext.lua')
if not okText or type(Text) ~= 'table' then Text = nil end

local COLORS = { text = '#d6c9ae', dim = '#8c8070', gold = '#e8b84a', coins = '#7fd0ff', error = '#e03a1e', ok = '#8fd16a' }

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

-- a Browse request; a refusal of it (an invalid filter) is cleared from the status line by the next page
local browseWaiting = false
local function sendBrowse()
  browseWaiting = true
  send('browse', lastFilter)
end

local function tooltips()
  return modules.game_itemtooltip
end

local function tipLogic()
  local tt = tooltips()
  return tt and tt.ItemTooltipLogic
end

local function rarityColor(row)
  local L = tipLogic()
  if L and L.titleColor then
    return L.titleColor({ rarity = row.rarity or 0, unique = row.unique })
  end
  return COLORS.text
end

local function wrapTip(text)
  if Text and Text.wrap then
    local out = {}
    for line in (tostring(text) .. '\n'):gmatch('(.-)\n') do out[#out + 1] = Text.wrap(line, 64, '  ') end
    return table.concat(out, '\n')
  end
  return text
end

local function setStatus(text, color)
  if not window then return end
  window.statusLabel:setText(text or '')
  window.statusLabel:setColor(color or COLORS.dim)
end

-- a one-line label shows the longest start of `text` that fits, cut at a word with "..." (never clipped)
local function fitText(label, text)
  text = tostring(text or '')
  label.fullText = text
  local function apply()
    if label:isDestroyed() then return end
    local w = label:getWidth()
    if w <= 1 then return end
    if not Text or not Text.shorten then
      label:setText(text)
      return
    end
    local s, cut = Text.shorten(text, function(candidate)
      label:setText(candidate)
      return label:getTextSize().width <= w
    end)
    label:setText(s)
    if cut and not label.tipSet then label:setTooltip(wrapTip(text)) end
  end
  label:setText(text)
  if not label.fitConnected then
    label.fitConnected = true
    connect(label, { onGeometryChange = function() apply() end })
  end
  addEvent(apply)
end

local function attr(item, key)
  if getItemAttribute then return getItemAttribute(item, key) end
  local ok, v = pcall(function() return item:getCustomAttribute(key) end)
  return ok and tonumber(v) or 0
end

-- ---------------------------------------------------------------- wallet and combos
local function updateWallet(gold, coins)
  if not window then return end
  if gold then meta = meta or {}; meta.gold = gold end
  if coins then meta = meta or {}; meta.coins = coins end
  local m = meta or {}
  if m.coinsOk == false then
    -- a season market trades for gold only (server season.lua): no coin balance to show
    window.walletLabel:setText(tr('%s market   Bank: %s gold', m.realmName or tr('Standard'), V.money(m.gold or 0)))
  else
    window.walletLabel:setText(tr('%s market  Bank: %s gold  Chaos Coins: %s', m.realmName or tr('Standard'),
      V.money(m.gold or 0), V.money(m.coins or 0)))
  end
end

-- season markets trade for gold only (meta.coinsOk = false): the coin price of the Sell tab is hidden
local function applyCoinRule()
  if not window then return end
  local off = meta and meta.coinsOk == false
  local s = window.sellPanel
  s.coinsLabel:setVisible(not off)
  s.coinsEdit:setVisible(not off)
  if off then s.coinsEdit:setText('') end
end

local function fillCombo(combo, options, current)
  updating = true
  combo:clearOptions()
  local index = 1
  for i, o in ipairs(options) do
    combo:addOption(o[1], o[2])
    if o[2] == current then index = i end
  end
  combo:setCurrentIndex(index)
  updating = false
end

local function comboValue(combo)
  local o = combo:getCurrentOption()
  return o and o.data or ''
end

local function fillFilterCombos()
  local cats = { { 'All items', '' } }
  for _, c in ipairs((meta and meta.categories) or { 'weapon', 'shield', 'helmet', 'armor', 'legs', 'boots', 'jewel', 'other', 'orb', 'gem', 'key', 'misc' }) do
    cats[#cats + 1] = { V.CATEGORY_NAMES[c] or c, c }
  end
  fillCombo(window.browsePanel.catCombo, cats, lastFilter.cat or '')
  local rar = { { 'Any rarity', 0 } }
  for i, name in ipairs(V.RARITIES) do rar[#rar + 1] = { name .. ' +', i } end
  fillCombo(window.browsePanel.rarityCombo, rar, lastFilter.rarity or 0)
  fillCombo(window.browsePanel.curCombo, { { 'Any price', '' }, { 'Gold', 'gold' }, { 'Chaos Coins', 'coins' } }, lastFilter.cur or '')
  local sorts = {}
  for _, s in ipairs((meta and meta.sorts) or { 'new', 'price', 'price_desc', 'ilvl', 'rarity', 'name', 'ending' }) do
    sorts[#sorts + 1] = { V.SORT_NAMES[s] or s, s }
  end
  fillCombo(window.browsePanel.sortCombo, sorts, lastFilter.sort or 'new')
  fillCombo(window.browsePanel.modPanel.modeCombo, { { 'All must match', 'all' }, { 'At least ... match', 'count' } },
    window.browsePanel.modPanel.modeCombo.mode or 'all')
  local days = {}
  for _, d in ipairs((meta and meta.durations) or { 1, 3, 7 }) do days[#days + 1] = { d == 1 and '1 day' or (d .. ' days'), d } end
  fillCombo(window.sellPanel.daysCombo, days, (meta and meta.defaultDuration) or 3)
end

-- ---------------------------------------------------------------- rows
local function clearList(list)
  if hoveredRow and hoveredRow:getParent() == list then
    local tt = tooltips()
    if tt and tt.hideTip then tt.hideTip(hoveredRow) end
    hoveredRow = nil
  end
  list:destroyChildren()
end

local function showRowTip(row)
  local tt = tooltips()
  local tip = tipCache[row.offer.id]
  if not tt or not tt.showTip or not tip then return end
  local extra = { { text = 'Seller: ' .. (row.offer.seller or tip.seller or '?'), color = COLORS.dim, sep = true } }
  for _, p in ipairs(V.priceLines(row.offer)) do
    extra[#extra + 1] = { text = p.text, color = p.cur == 'coins' and COLORS.coins or COLORS.gold }
  end
  local typical = V.rowTypicalText and V.rowTypicalText(row.offer) -- price history (marketpriceview.lua)
  if typical then extra[#extra + 1] = { text = typical, color = COLORS.dim } end
  for i, m in ipairs(V.matchedMods(tip, lastFilter)) do
    extra[#extra + 1] = { text = m.text, color = COLORS.ok, sep = i == 1 or nil }
  end
  tt.showTip(row, 'market:' .. row.offer.id, tip, extra)
end

local function onRowHover(row, hovered)
  if not hovered then
    if hoveredRow == row then
      local tt = tooltips()
      if tt and tt.hideTip then tt.hideTip(row) end
      hoveredRow = nil
    end
    return
  end
  hoveredRow = row
  if tipCache[row.offer.id] then
    showRowTip(row)
  elseif not tipAsked[row.offer.id] or os.time() - tipAsked[row.offer.id] > 3 then
    tipAsked[row.offer.id] = os.time()
    send('tip', { id = row.offer.id })
  end
end

-- the message box's buttons are of a fixed width: widen the ones whose text does not fit, then the box
local function widenButtons(box)
  if not box or box:isDestroyed() then return end
  local holder = box:getChildById('buttonHolder')
  if not holder then return end
  local total = 0
  for _, b in ipairs(holder:getChildren()) do
    local need = b:getTextSize().width + 24
    if need > b:getWidth() then b:setWidth(need) end
    total = total + b:getWidth() + b:getMarginLeft()
  end
  holder:setWidth(total)
  local inner = total + box:getPaddingLeft() + box:getPaddingRight()
  if inner > box:getWidth() then box:setWidth(inner) end
end

local function confirmBuy(offer)
  local lines = V.priceLines(offer)
  local buttons = {}
  local box
  local function close() if box then box:destroy() box = nil end end
  for _, p in ipairs(lines) do
    local cur = p.cur
    buttons[#buttons + 1] = { text = 'Pay ' .. p.text, callback = function()
      close()
      send('buy', { id = offer.id, cur = cur })
    end }
  end
  buttons[#buttons + 1] = { text = tr('Cancel'), callback = close }
  buttons.anchor = AnchorHorizontalCenter
  local what = ((offer.count or 1) > 1 and (offer.count .. 'x ') or '') .. (offer.name or 'item')
  local msg = tr('Buy %s from %s?\nIt goes to your inbox (the depot).', what, offer.seller or '?')
  if displayGeneralBox then
    box = displayGeneralBox(tr('Buy'), msg, buttons, nil, close)
    widenButtons(box)
  elseif #lines == 1 then
    send('buy', { id = offer.id, cur = lines[1].cur })
  end
end

local function confirmCancel(offer)
  local box
  local function close() if box then box:destroy() box = nil end end
  local function yes() close() send('cancel', { id = offer.id }) end
  local msg = tr('Cancel the offer of %s? The item goes back to your inbox; the listing fee is not refunded.', offer.name or 'item')
  if displayGeneralBox then
    box = displayGeneralBox(tr('Cancel offer'), msg, { { text = tr('Yes'), callback = yes }, { text = tr('No'), callback = close },
      anchor = AnchorHorizontalCenter }, yes, close)
  else
    yes()
  end
end

-- a transmog look (server transmog.lua; client base patch 0030): draw the item widget's item as that client id
local function showLook(widget, look)
  look = tonumber(look) or 0
  local item = look > 0 and widget:getItem() or nil
  if item then pcall(function() item:setAppearanceId(look) end) end
end

-- one offer row; mode = 'browse' | 'mine' | 'closed' | 'history'
local function addRow(list, offer, mode)
  local row = g_ui.createWidget('MarketRow', list)
  row.offer = offer
  local icon = row:getChildById('icon')
  icon:setItemId(tonumber(offer.item) or 0)
  showLook(icon, offer.look)
  if modules.game_itemfinder and modules.game_itemfinder.attach then modules.game_itemfinder.attach(row, tonumber(offer.item)) end -- right-click: Where to find
  if (offer.count or 1) > 1 then icon:setItemCount(offer.count) end
  local color = rarityColor(offer)
  if (offer.rarity or 0) > 0 or offer.unique then
    icon:setBorderWidth(2)
    icon:setBorderColor(color)
  end
  local name = row:getChildById('name')
  name:setColor(color)
  fitText(name, ((offer.count or 1) > 1 and (offer.count .. 'x ') or '') .. (offer.name or '?'))
  local sub = row:getChildById('sub')
  local subText
  if mode == 'browse' then
    subText = V.subLine(offer)
  elseif mode == 'history' then
    subText = V.historyLine(offer) .. (offer.order and tr(' (buy order)') or '')
  else
    subText = V.stateLine(offer)
  end
  if mode == 'closed' and offer.state == 'sold' then sub:setColor(COLORS.ok) end
  -- price history: a Browse offer priced well under / over the typical price is marked; a click shows the item's prices
  local mark = mode == 'browse' and V.rowMark and V.rowMark(offer)
  if mark then
    local mw = row:getChildById('mark')
    mw:setText(mark.text)
    mw:setColor(mark.color)
    mw:show()
    sub:setMarginRight(mw:getTextSize().width + 8)
  end
  if mode == 'browse' then row.onClick = function() showPrices(offer) return true end end
  fitText(sub, subText)
  local prices = V.priceLines(offer)
  local prow = row:getChildById('prices')
  if mode == 'history' or (mode == 'closed' and offer.state == 'sold') then
    prow:getChildById('gold'):setText(V.money(offer.paid or 0) .. (offer.cur == 'coins' and tr(' coins') or tr(' gold')))
    prow:getChildById('gold'):setColor(offer.cur == 'coins' and COLORS.coins or COLORS.gold)
    prow:getChildById('coins'):setText('')
  else
    local g, c = prow:getChildById('gold'), prow:getChildById('coins')
    g:setText('')
    c:setText('')
    local slots = { g, c }
    for i, p in ipairs(prices) do
      slots[i]:setText(p.text)
      slots[i]:setColor(p.cur == 'coins' and COLORS.coins or COLORS.gold)
    end
  end
  local button = row:getChildById('buttons'):getChildById('action')
  if mode == 'browse' and not offer.mine then
    button:setText(tr('Buy'))
    button.onClick = function() confirmBuy(offer) end
  elseif (mode == 'browse' and offer.mine) or mode == 'mine' then
    button:setText(tr('Cancel'))
    button.onClick = function() confirmCancel(offer) end
  else
    button:hide()
  end
  row.onHoverChange = onRowHover
  return row
end

local function addHeading(list, text)
  local h = g_ui.createWidget('MarketHeading', list)
  h:setText(text)
  return h
end

-- ---------------------------------------------------------------- Browse: the Modifiers section
local function modLimits()
  return (meta and meta.modFilter) or V.MOD_LIMITS
end

local function catalog()
  if not modCatalog or #modCatalog.list == 0 then
    local codex = modules.game_codex
    modCatalog = V.modCatalog(codex and codex.CodexData or CodexData)
  end
  return modCatalog
end

-- the modifier combo of a row: the choices for its search text; keeps the chosen modifier when it still matches, else
-- takes the first match (a search that matches nothing chooses nothing)
local function fillModCombo(row, keepKey)
  local choices, first = V.modChoices(catalog(), row.search:getText())
  local want = keepKey
  local has = false
  for _, o in ipairs(choices) do if want and want ~= '' and o[2] == want then has = true end end
  if not has then want = row.search:getText() ~= '' and first or '' end
  updating = true
  row.mod:clearOptions()
  local index = 1
  for i, o in ipairs(choices) do
    row.mod:addOption(o[1], o[2], true)
    if want ~= '' and o[2] == want then index = i end
  end
  row.mod:setCurrentIndex(index, true)
  updating = false
end

local function modForm()
  local mp = window.browsePanel.modPanel
  local rows = {}
  for _, w in ipairs(modRowWidgets) do
    rows[#rows + 1] = { key = comboValue(w.mod), min = w.min:getText(), tier = comboValue(w.tier) }
  end
  return { rows = rows, mode = comboValue(mp.modeCombo), need = mp.needEdit:getText(), sockets = mp.socketsEdit:getText(),
    quality = mp.qualityEdit:getText(), freeP = mp.freePCheck:isChecked(), freeS = mp.freeSCheck:isChecked(),
    power = mp.powerCheck:isChecked(), bound = mp.boundCheck:isChecked() }
end

local function updateModToggle(req)
  local p = window.browsePanel
  local n = V.modCount(req or V.modRequest(modForm(), modLimits()) or {})
  p.modToggle:setText((n > 0 and (tr('Modifiers (%s)', n)) or tr('Modifiers')) .. (modsOpen and ' [-]' or ' [+]'))
  local limits = modLimits()
  p.modPanel.addModButton:setEnabled(#modRowWidgets < (limits.maxRows or 6))
  p.modPanel.needEdit:setEnabled(comboValue(p.modPanel.modeCombo) == 'count')
  p.modSummary:setText(not modsOpen and n > 0 and tr('Modifier filters active') or '')
end

-- the section's height follows its rows (the offer list below takes the rest of the window)
local function layoutMods()
  local p = window.browsePanel
  local mp = p.modPanel
  mp.modRows:setHeight(#modRowWidgets * 26)
  if modsOpen then
    local hint = mp.modHint
    local hintH = math.max(22, hint:getHeight())
    mp:setHeight(mp:getPaddingTop() + 22 + 2 + #modRowWidgets * 26 + 6 + hintH + mp:getPaddingBottom())
    mp:setMarginTop(6)
    mp:show()
  else
    mp:setHeight(0)
    mp:setMarginTop(0)
    mp:hide()
  end
  updateModToggle()
end

local function cleanSearch()
  if not window then return end
  search(1)
end

function addModRow(key)
  if not window then return end
  local limits = modLimits()
  if #modRowWidgets >= (limits.maxRows or 6) then
    setStatus(tr('At most %d modifiers per search.', limits.maxRows or 6), COLORS.error)
    return
  end
  local row = g_ui.createWidget('MarketModRow', window.browsePanel.modPanel.modRows)
  modRowWidgets[#modRowWidgets + 1] = row
  fillCombo(row.tier, V.tierOptions(limits.maxTier or 8), 0)
  fillModCombo(row, key)
  row.search.onTextChange = function(w, text)
    row.searchHint:setVisible(text == '')
    local before = comboValue(row.mod)
    fillModCombo(row, before)
    if comboValue(row.mod) ~= before then cleanSearch() end
  end
  row.mod.onOptionChange = function() if not updating then updateModToggle() cleanSearch() end end
  row.tier.onOptionChange = function() if not updating then cleanSearch() end end
  row.min.onTextChange = function() if not updating then cleanSearch() end end
  row.remove.onClick = function()
    for i, w in ipairs(modRowWidgets) do
      if w == row then table.remove(modRowWidgets, i) break end
    end
    row:destroy()
    layoutMods()
    cleanSearch()
  end
  layoutMods()
  return row
end

function toggleMods()
  if not window then return end
  modsOpen = not modsOpen
  if modsOpen and #modRowWidgets == 0 then addModRow() end
  layoutMods()
end

local function clearMods()
  for _, w in ipairs(modRowWidgets) do w:destroy() end
  modRowWidgets = {}
  local mp = window.browsePanel.modPanel
  updating = true
  for _, id in ipairs({ 'needEdit', 'socketsEdit', 'qualityEdit' }) do mp[id]:setText('') end
  for _, id in ipairs({ 'freePCheck', 'freeSCheck', 'powerCheck', 'boundCheck' }) do mp[id]:setChecked(false) end
  mp.modeCombo:setCurrentIndex(1, true)
  mp.modeCombo.mode = 'all'
  updating = false
end

-- ---------------------------------------------------------------- Browse
-- the filter of the window's fields, or nil and why (an invalid Modifiers section; shown in the status line)
local function readFilter(page)
  local p = window.browsePanel
  local f, why = V.filter({ q = p.searchEdit:getText(), cat = comboValue(p.catCombo), rarity = comboValue(p.rarityCombo),
    cur = comboValue(p.curCombo), sort = comboValue(p.sortCombo), ilvlMin = p.ilvlMin:getText(),
    ilvlMax = p.ilvlMax:getText(), priceMin = p.priceMin:getText(), priceMax = p.priceMax:getText(), page = page,
    modForm = modForm(), limits = modLimits() })
  updateModToggle(f)
  return f, why
end

local searchEvent
-- filter changes come in bursts (several combos, typing): one request 250 ms after the last change (the server drops
-- Browse requests closer than market_config.lua rate.browse)
function search(page)
  if not window then return end
  if searchEvent then removeEvent(searchEvent) end
  searchEvent = scheduleEvent(function()
    searchEvent = nil
    if not window then return end
    local f, why = readFilter(page or 1)
    if not f then
      setStatus(why, COLORS.error)
      window.statusLabel.filterError = true
      return
    end
    if window.statusLabel.filterError then setStatus('') end
    window.statusLabel.filterError = nil
    lastFilter = f
    sendBrowse()
  end, 250)
end

function page(delta)
  local target = (pageInfo.page or 1) + delta
  if target < 1 or target > (pageInfo.pages or 1) then return end
  if not window then return end
  local f, why = readFilter(target)
  if not f then
    setStatus(why, COLORS.error)
    return
  end
  lastFilter = f
  sendBrowse()
end

function resetFilters()
  if not window then return end
  local p = window.browsePanel
  for _, id in ipairs({ 'searchEdit', 'ilvlMin', 'ilvlMax', 'priceMin', 'priceMax' }) do p[id]:setText('') end
  lastFilter = { page = 1 }
  clearMods()
  if modsOpen then addModRow() end
  fillFilterCombos()
  layoutMods()
  search(1)
end

local function onPage(data)
  local p = window.browsePanel
  browseWaiting = false
  if window.statusLabel.filterError then
    setStatus('')
    window.statusLabel.filterError = nil
  end
  clearList(p.offerList)
  pageInfo = { page = data.page or 1, pages = data.pages or 1, total = data.total or 0 }
  for _, offer in ipairs(data.rows or {}) do addRow(p.offerList, offer, 'browse') end
  p.emptyLabel:setVisible(#(data.rows or {}) == 0)
  p.pageLabel:setText(V.pageText(pageInfo.page, pageInfo.pages, pageInfo.total))
  p.pagePrev:setEnabled(pageInfo.page > 1)
  p.pageNext:setEnabled(pageInfo.page < pageInfo.pages)
  p.offerScroll:setValue(0)
end

-- ---------------------------------------------------------------- price history (marketpriceview.lua; server market_history.lua)
-- a click on a Browse offer shows the prices of its item key (type, rarity, item level band) with a 30-day chart; the
-- Sell form asks for the chosen item's prices, suggests one and warns when the asking price is far from the typical one
local priceState = { seq = 0 }

local function renderPriceChart(points, days)
  local f = window.priceFrame
  local chart = f.priceChart
  chart:destroyChildren()
  local rects = V.priceChart(points or {}, days or 30, chart:getWidth() - 4, chart:getHeight() - 4)
  for _, r in ipairs(rects) do
    local rw = g_ui.createWidget('MarketChartRect', chart)
    rw:setMarginLeft(r.x + 2)
    rw:setMarginTop(r.y + 2)
    rw:setSize({ width = r.w, height = r.h })
    rw:setBackgroundColor(r.kind == 'line' and V.PRICE_COLORS.line or V.PRICE_COLORS.vol)
  end
  f.priceChartEmpty:setVisible(#rects == 0)
  local sc = V.chartScale(points, days)
  f.priceHigh:setText(sc and sc.high or '')
  f.priceLow:setText(sc and sc.low or '')
  f.priceLow:setMarginBottom(math.floor(chart:getHeight() / 4) + 2) -- the line's bottom (the sales bars are below it)
end

local function renderPrices()
  local d = priceState.detail
  if not window or not d or not d.data then return end
  local f = window.priceFrame
  d.cur = V.priceCurrency(d.data, d.cur)
  local s = d.data[d.cur]
  f.priceStats:destroyChildren()
  for _, l in ipairs(V.priceStatsLines(s, d.cur)) do
    local lab = g_ui.createWidget('MarketText', f.priceStats)
    lab:setHeight(17)
    lab:setText(l.text)
    lab:setColor(l.color)
  end
  local other = d.cur == 'gold' and 'coins' or 'gold'
  local o = d.data[other]
  f.priceCur:setVisible(o ~= nil and ((o.n30 or 0) > 0 or (o.n7 or 0) > 0))
  f.priceCur:setText(other == 'coins' and tr('Coin prices') or tr('Gold prices'))
  renderPriceChart(s and s.points, s and s.days or 30)
end

function showPrices(offer)
  if not window or not offer then return end
  local f = window.priceFrame
  local tt = tooltips()
  if hoveredRow and tt and tt.hideTip then tt.hideTip(hoveredRow) end
  priceState.seq = priceState.seq + 1
  priceState.detail = { offer = offer, seq = priceState.seq }
  f.priceIcon:setItemId(tonumber(offer.item) or 0)
  showLook(f.priceIcon, offer.look)
  local color = rarityColor(offer)
  f.priceIcon:setBorderWidth(((offer.rarity or 0) > 0 or offer.unique) and 2 or 0)
  f.priceIcon:setBorderColor(color)
  f.priceName:setText(tr('Price history') .. ': ' .. (offer.name or '?'))
  f.priceName:setColor(color)
  f.priceKey:setText(tr('Loading...'))
  f.priceStats:destroyChildren()
  f.priceChart:destroyChildren()
  f.priceChartEmpty:setVisible(false)
  f.priceHigh:setText('')
  f.priceLow:setText('')
  f.priceCur:hide()
  f:show()
  f:raise()
  send('prices', { id = offer.id, seq = priceState.seq })
end

function closePrices()
  priceState.detail = nil
  if window then window.priceFrame:hide() end
end

function togglePriceCurrency()
  local d = priceState.detail
  if not d or not d.data then return end
  d.cur = d.cur == 'gold' and 'coins' or 'gold'
  renderPrices()
end

local function updatePriceHint()
  if not window then return end
  local s = window.sellPanel
  local data = priceState.sellFor == selected and priceState.sell or nil
  if not selected or not data then
    s.priceHint:setText('')
    s.priceWarn:setText('')
    s.suggestButton:hide()
    priceState.suggest = nil
    return
  end
  local count = selected.stack and (V.parseAmount(s.countEdit:getText()) or selected.count or 1) or 1
  if count < 1 then count = 1 end
  local g = data.gold
  local key = V.priceKeyText(data.rarity, data.bandText)
  local text = (key ~= '' and (key .. ': ') or '') .. V.typicalLine(g, 'gold').text
  priceState.suggest = g and g.typical and V.suggestPrice(g.typical, count, meta and meta.price and meta.price.gold and meta.price.gold.min) or nil
  if priceState.suggest then
    text = text .. string.format('. Suggested: %s gold%s.', V.money(priceState.suggest), count > 1 and string.format(' for %d', count) or '')
  end
  s.priceHint:setText(text)
  s.suggestButton:setVisible(priceState.suggest ~= nil)
  local warns = {}
  for _, cur in ipairs({ 'gold', 'coins' }) do
    local st = data[cur]
    local edit = cur == 'gold' and s.goldEdit or s.coinsEdit
    local w = st and V.sellWarning(V.parseAmount(edit:getText()) or 0, count, st.typical, data.warn, cur)
    if w then warns[#warns + 1] = w.text end
  end
  s.priceWarn:setText(table.concat(warns, '\n'))
end

local function requestSellPrices()
  priceState.sell, priceState.sellFor = nil, selected
  updatePriceHint()
  if not selected or not selected.sid then return end
  priceState.seq = priceState.seq + 1
  priceState.sellSeq = priceState.seq
  send('prices', { sid = selected.sid, rarity = selected.rarity or 0, ilvl = selected.ilvl or 0, seq = priceState.seq })
end

function useSuggestedPrice()
  if window and priceState.suggest then window.sellPanel.goldEdit:setText(tostring(priceState.suggest)) end
end

local function onPrices(data)
  local d = priceState.detail
  if d and data.seq == d.seq then
    if data.gone then
      window.priceFrame.priceKey:setText(tr('That offer is gone.'))
      return
    end
    d.data = data
    local key = V.priceKeyText(data.rarity, data.bandText)
    window.priceFrame.priceKey:setText((key ~= '' and (key .. '; ') or '') .. tr('sales on your market only'))
    addEvent(renderPrices)
  elseif data.seq and data.seq == priceState.sellSeq then
    priceState.sell = data
    updatePriceHint()
  end
end

-- ---------------------------------------------------------------- Sell
local function updateFee()
  if not window then return end
  local s = window.sellPanel
  local gold = V.parseAmount(s.goldEdit:getText()) or 0
  local coins = V.parseAmount(s.coinsEdit:getText()) or 0
  local days = tonumber(comboValue(s.daysCombo)) or 3
  local parts = {}
  local fee = V.fee(meta, gold, coins)
  parts[#parts + 1] = tr('Listing fee: %s gold from your bank, not refunded.', V.money(fee))
  if gold > 0 then
    local tax, net = V.tax(meta, 'gold', gold)
    parts[#parts + 1] = tr('Sold for gold: tax %s, you receive %s gold in your bank.', V.money(tax), V.money(net))
  end
  if coins > 0 then
    local tax, net = V.tax(meta, 'coins', coins)
    parts[#parts + 1] = tr('Sold for coins: tax %s, you receive %s Chaos Coins on your account.', V.money(tax), V.money(net))
  end
  parts[#parts + 1] = tr('The offer lasts %d day%s; if nothing sells, the item returns to your inbox.', days, days == 1 and '' or 's')
  s.feeText:setText(table.concat(parts, '\n'))
  updatePriceHint()
end

local function showSelected()
  local s = window.sellPanel
  if not selected then
    s.sellSlot:setItemId(0)
    s.sellSlot:setBorderWidth(0)
    s.sellName:setText(tr('No item chosen'))
    s.sellName:setColor(COLORS.gold)
    s.sellSub:setText('')
    s.countEdit:setText('')
    s.countEdit:setEnabled(false)
    s.countMax:setText('')
    s.listButton:setEnabled(false)
    return
  end
  s.sellSlot:setItemId(selected.item or 0)
  showLook(s.sellSlot, selected.look)
  s.sellSlot:setItemCount(selected.count or 1)
  local color = rarityColor(selected)
  if (selected.rarity or 0) > 0 then
    s.sellSlot:setBorderWidth(2)
    s.sellSlot:setBorderColor(color)
  else
    s.sellSlot:setBorderWidth(0)
  end
  s.sellName:setText(selected.name or '?')
  s.sellName:setColor(color)
  local sub = {}
  if (selected.rarity or 0) > 0 then sub[#sub + 1] = V.rarityName(selected.rarity) end
  if (selected.ilvl or 0) > 0 then sub[#sub + 1] = 'iLvl ' .. selected.ilvl end
  s.sellSub:setText(table.concat(sub, ' - '))
  s.countEdit:setEnabled(selected.stack == true)
  s.countEdit:setText(tostring(selected.count or 1))
  s.countMax:setText(selected.stack and (tr('of %s', (selected.count or 1))) or '')
  s.listButton:setEnabled(true)
end

local function choose(entry)
  if entry.why then
    setStatus(entry.why, COLORS.error)
    return
  end
  selected = { ref = entry.ref, sid = entry.sid, iid = entry.iid, count = entry.count, item = entry.item, name = entry.name,
    stack = entry.stack, rarity = entry.rarity, ilvl = entry.ilvl, look = entry.look }
  showSelected()
  requestSellPrices()
  setStatus('')
end

local function onSellable(data)
  local s = window.sellPanel
  s.pickList:destroyChildren()
  sellItems = V.sortSellable(data.items or {})
  for _, entry in ipairs(sellItems) do
    local w = g_ui.createWidget('MarketPick', s.pickList)
    w:setItemId(tonumber(entry.item) or 0)
    showLook(w, entry.look)
    if (entry.count or 1) > 1 then w:setItemCount(entry.count) end
    local tip = (entry.count or 1) > 1 and (entry.count .. 'x ' .. entry.name) or entry.name
    if entry.why then
      w:setOpacity(0.35)
      tip = tip .. '\n' .. entry.why
    end
    if (entry.rarity or 0) > 0 then
      w:setBorderWidth(1)
      w:setBorderColor(rarityColor(entry))
    end
    w:setTooltip(wrapTip(tip))
    w.onClick = function() choose(entry) end
  end
  s.pickHint:setText(#sellItems == 0 and tr('Your backpack is empty: put the items you want to sell in it.')
    or tr('Your backpack: click an item to sell it, or drag one onto the slot on the right.'))
end

-- an item dragged from the backpack (or another open container) onto the slot
local function onDropItem(self, widget, mousePos)
  local item = widget and (widget.currentDragThing or (widget.getItem and widget:getItem()))
  if not item or not item.isItem or not item:isItem() then return false end
  local A = ChaosItemAttr or { ID = 6 }
  local iid = attr(item, A.ID)
  local pos = item:getPosition()
  -- the same item in the picker list (same per-item id, or same look and count)
  for _, e in ipairs(sellItems) do
    if (iid > 0 and tostring(e.iid) == string.format('%.0f', iid)) or (iid <= 0 and e.item == item:getId() and e.count == item:getCount()) then
      choose(e)
      return true
    end
  end
  selected = { pos = { x = pos.x, y = pos.y, z = pos.z }, cid = item:getId(), iid = string.format('%.0f', iid), count = item:getCount(),
    item = item:getId(), name = tr('Dropped item'), stack = item:isStackable(),
    look = item.getAppearanceId and item:getAppearanceId() or nil }
  showSelected()
  return true
end

function listItem()
  if not window or not selected then return end
  local s = window.sellPanel
  local form, why = V.checkSell(meta, { gold = s.goldEdit:getText(), coins = s.coinsEdit:getText(),
    count = selected.stack and s.countEdit:getText() or 1, have = selected.count or 1, days = comboValue(s.daysCombo) })
  if not form then
    setStatus(why, COLORS.error)
    return
  end
  send('list', { ref = selected.ref, pos = selected.pos, sid = selected.sid, cid = selected.cid, iid = selected.iid, count = form.count,
    gold = form.gold, coins = form.coins, days = form.days })
end

-- ---------------------------------------------------------------- My Offers / History
local function onMine(data)
  local list = window.minePanel.mineList
  clearList(list)
  addHeading(list, tr('Active offers (%d; listings used with buy orders: %d / %d)', #(data.active or {}),
    tonumber(data.used) or #(data.active or {}), data.max or 20))
  for _, offer in ipairs(data.active or {}) do addRow(list, offer, 'mine') end
  if #(data.active or {}) == 0 then
    local t = g_ui.createWidget('MarketTextDim', list)
    t:setHeight(18)
    t:setText(tr('No active offers. List items in the Sell tab.'))
  end
  if (data.owed or 0) > 0 then
    local t = g_ui.createWidget('MarketText', list)
    t:setHeight(18)
    t:setColor(COLORS.gold)
    t:setText(tr('%d deliveries are on the way to your inbox / bank.', data.owed))
  end
  addHeading(list, tr('Sold, expired and cancelled'))
  for _, offer in ipairs(data.closed or {}) do addRow(list, offer, 'closed') end
end

local function onHistory(data)
  local list = window.historyPanel.historyList
  clearList(list)
  addHeading(list, tr('Your purchases and sales'))
  for _, offer in ipairs(data.rows or {}) do addRow(list, offer, 'history') end
  if #(data.rows or {}) == 0 then
    local t = g_ui.createWidget('MarketTextDim', list)
    t:setHeight(18)
    t:setText(tr('Nothing bought or sold yet.'))
  end
end

-- ---------------------------------------------------------------- Buy Orders
local orderFilter = { page = 1 }
local orderPageInfo = { page = 1, pages = 1, total = 0 }
local chosenKind     -- {sid, item, name, stack}: the item the order form asks for
local orderMods      -- the modifier part of the order filter (V.modRequest of the Browse tab's Modifiers section)
local fillState      -- {order = row, items = {...}, chosen = item}
local orderSearchEvent

local function modName(key)
  local cat = catalog()
  local m = cat and cat.byKey[key]
  return m and m.name or nil
end

local function fillOrderCombos()
  local p = window.ordersPanel
  fillCombo(p.orderCurCombo, { { 'Any currency', '' }, { 'Gold', 'gold' }, { 'Chaos Coins', 'coins' } }, orderFilter.cur or '')
  local sorts = {}
  for _, s in ipairs((meta and meta.orders and meta.orders.sorts) or { 'new', 'price', 'ending', 'name' }) do
    sorts[#sorts + 1] = { V.ORDER_SORT_NAMES[s] or s, s }
  end
  fillCombo(p.orderSortCombo, sorts, orderFilter.sort or 'new')
  local f = p.postFrame
  local days = {}
  for _, d in ipairs((meta and meta.durations) or { 1, 3, 7 }) do days[#days + 1] = { d == 1 and '1 day' or (d .. ' days'), d } end
  fillCombo(f.orderDaysCombo, days, (meta and meta.defaultDuration) or 3)
  local pay = { { 'Gold', 'gold' } }
  if not (meta and meta.coinsOk == false) then pay[2] = { 'Chaos Coins', 'coins' } end -- season markets: gold only
  local cur = comboValue(f.orderPayCombo)
  fillCombo(f.orderPayCombo, pay, (cur == 'coins' and #pay > 1) and 'coins' or 'gold')
  local rar = { { 'Any rarity', 0 } }
  for i, name in ipairs(V.RARITIES) do rar[#rar + 1] = { name .. ' +', i } end
  fillCombo(f.orderRarityCombo, rar, tonumber(comboValue(f.orderRarityCombo)) or 0)
end

local function sendOrders()
  if orderFilter.mine then
    send('myOrders')
  else
    send('orders', orderFilter)
  end
end

local function readOrderFilter(page)
  local p = window.ordersPanel
  return { q = p.orderSearch:getText(), cur = comboValue(p.orderCurCombo), sort = comboValue(p.orderSortCombo),
    mine = p.orderMineCheck:isChecked() or nil, page = page or 1 }
end

function orderSearch(page)
  if not window then return end
  if orderSearchEvent then removeEvent(orderSearchEvent) end
  orderSearchEvent = scheduleEvent(function()
    orderSearchEvent = nil
    if not window then return end
    orderFilter = readOrderFilter(page)
    sendOrders()
  end, 250)
end

function orderPage(delta)
  local target = (orderPageInfo.page or 1) + delta
  if not window or target < 1 or target > (orderPageInfo.pages or 1) then return end
  orderFilter = readOrderFilter(target)
  sendOrders()
end

local function confirmOrderCancel(row)
  local box
  local function close() if box then box:destroy() box = nil end end
  local function yes() close() send('orderCancel', { id = row.id }) end
  local msg = tr('Cancel your buy order for %s? The %s %s still held come back to you; the listing fee is not refunded.',
    row.name or 'item', V.money(row.escrow or 0), row.cur == 'coins' and tr('Chaos Coins') or 'gold')
  if displayGeneralBox then
    box = displayGeneralBox(tr('Cancel buy order'), msg, { { text = tr('Yes'), callback = yes }, { text = tr('No'), callback = close },
      anchor = AnchorHorizontalCenter }, yes, close)
    widenButtons(box)
  else
    yes()
  end
end

local function addOrderRow(list, row)
  local w = g_ui.createWidget('MarketRow', list)
  w:setId('order' .. tostring(row.id))
  w.order = row
  local icon = w:getChildById('icon')
  icon:setItemId(tonumber(row.item) or 0)
  if modules.game_itemfinder and modules.game_itemfinder.attach then modules.game_itemfinder.attach(w, tonumber(row.item)) end -- right-click: Where to find
  local left = (tonumber(row.qty) or 0) - (tonumber(row.filled) or 0)
  if row.stack and left > 1 then icon:setItemCount(math.min(left, 100)) end
  local f = row.filter or {}
  local color = (tonumber(f.rarity) or 0) > 0 and rarityColor({ rarity = f.rarity }) or COLORS.text
  local name = w:getChildById('name')
  name:setColor(color)
  fitText(name, string.format('Wanted: %s%s', left > 1 and (V.money(left) .. 'x ') or '', row.name or '?'))
  local sub = w:getChildById('sub')
  fitText(sub, V.orderSubLine(row, modName))
  local prow = w:getChildById('prices')
  local slots = { prow:getChildById('gold'), prow:getChildById('coins') }
  for i, pl in ipairs(V.orderPriceLines(row)) do
    slots[i]:setText(pl.text)
    slots[i]:setColor(pl.cur == 'coins' and COLORS.coins or COLORS.gold)
  end
  local button = w:getChildById('buttons'):getChildById('action')
  if row.state ~= 'active' then
    button:hide()
  elseif row.mine then
    button:setText(tr('Cancel'))
    button.onClick = function() confirmOrderCancel(row) end
  else
    button:setText(tr('Sell'))
    button:setTooltip(tr('Sell your items to this order'))
    button.onClick = function() openFill(row) end
  end
  return w
end

local function showOrderPage(rows, info, emptyText)
  local p = window.ordersPanel
  p.orderList:destroyChildren()
  for _, r in ipairs(rows or {}) do addOrderRow(p.orderList, r) end
  orderPageInfo = info
  p.orderEmpty:setText(emptyText)
  p.orderEmpty:setVisible(#(rows or {}) == 0)
  local total = tonumber(info.total) or 0
  p.orderPageLabel:setText(tr('Page %d / %d  (%d order%s)', info.page or 1, math.max(1, info.pages or 1), total, total == 1 and '' or 's'))
  p.orderPrev:setEnabled((info.page or 1) > 1)
  p.orderNext:setEnabled((info.page or 1) < (info.pages or 1))
  p.orderScroll:setValue(0)
end

local function onOrders(data)
  showOrderPage(data.rows, { page = data.page or 1, pages = data.pages or 1, total = data.total or 0 },
    tr('No buy orders match. Post one on the right: sellers fill it from their backpacks.'))
end

local function onMyOrders(data)
  local p = window.ordersPanel
  showOrderPage({}, { page = 1, pages = 1, total = #(data.active or {}) }, '')
  p.orderEmpty:hide()
  addHeading(p.orderList, tr('Your open buy orders (listings used: %d / %d)', tonumber(data.used) or 0, tonumber(data.max) or 20))
  for _, r in ipairs(data.active or {}) do addOrderRow(p.orderList, r) end
  if #(data.active or {}) == 0 then
    local t = g_ui.createWidget('MarketTextDim', p.orderList)
    t:setHeight(18)
    t:setText(tr('No open buy orders.'))
  end
  addHeading(p.orderList, tr('Filled, expired and cancelled'))
  for _, r in ipairs(data.closed or {}) do addOrderRow(p.orderList, r) end
end

-- ---- the post form
local function showChosenKind()
  local f = window.ordersPanel.postFrame
  if not chosenKind then
    f.orderSlot:setItemId(0)
    f.orderItemName:setText(tr('No item chosen: type its name and press Find.'))
    return
  end
  f.orderSlot:setItemId(tonumber(chosenKind.item) or 0)
  f.orderItemName:setText(chosenKind.name or '?')
end

local function orderForm()
  local f = window.ordersPanel.postFrame
  return { sid = chosenKind and chosenKind.sid, quantity = f.qtyEdit:getText(), price = f.priceEdit:getText(),
    cur = comboValue(f.orderPayCombo), days = comboValue(f.orderDaysCombo), rarity = comboValue(f.orderRarityCombo),
    ilvl = f.orderIlvlEdit:getText(), mods = orderMods }
end

function updateOrderCost()
  if not window then return end
  local f = window.ordersPanel.postFrame
  f.orderModsText:setText(orderMods and (tr('Modifiers: %s', V.orderFilterText(orderMods, modName)))
    or tr('Modifiers: any. Set rows in the Browse tab\'s Modifiers section, then press Use Browse modifiers.'))
  local req, total, fee = V.checkOrder(meta, orderForm())
  if req then
    f.orderCostText:setText(V.orderCostText(meta, req, total, fee))
    f.orderCostText:setColor(COLORS.text)
  else
    f.orderCostText:setText(total or '')
    f.orderCostText:setColor(COLORS.dim)
  end
  f.postButton:setEnabled(req ~= nil)
end

local function chooseKind(entry)
  chosenKind = { sid = entry.sid, item = entry.item, name = entry.name, stack = entry.stack }
  showChosenKind()
  updateOrderCost()
end

function orderFind()
  if not window then return end
  local q = window.ordersPanel.postFrame.findEdit:getText()
  if q:gsub('%s', '') == '' then
    setStatus(tr('Type the name of the item you want.'), COLORS.error)
    return
  end
  send('orderFind', { q = q })
end

local function onOrderFind(data)
  local f = window.ordersPanel.postFrame
  f.findList:destroyChildren()
  local items = data.items or {}
  for _, e in ipairs(items) do
    local w = g_ui.createWidget('MarketPick', f.findList)
    w:setItemId(tonumber(e.item) or 0)
    w:setTooltip(e.name or '?')
    w.onClick = function() chooseKind(e) end
  end
  if #items == 1 then chooseKind(items[1]) end
  if #items == 0 then
    setStatus(tr('No item of that name. Try another part of the name, or the exact name.'), COLORS.error)
  else
    setStatus(string.format(tr('%d item kinds found: click the one you want.'), #items))
  end
end

function orderModsFromBrowse()
  if not window then return end
  local req, why = V.modRequest(modForm(), modLimits())
  if not req then
    setStatus(why, COLORS.error)
    return
  end
  if V.modCount(req) == 0 then
    setStatus(tr('The Browse tab\'s Modifiers section is empty: add rows there first.'), COLORS.error)
    return
  end
  orderMods = req
  updateOrderCost()
end

function orderModsClear()
  orderMods = nil
  updateOrderCost()
end

function postOrder()
  if not window then return end
  local req, why = V.checkOrder(meta, orderForm())
  if not req then
    setStatus(why, COLORS.error)
    return
  end
  send('orderPost', req)
end

-- ---- filling an order
local function showFillChoice()
  local f = window.ordersPanel.fillFrame
  local c = fillState and fillState.chosen
  if not c then
    f.fillSlot:setItemId(0)
    f.fillName:setText(tr('Click one of your items'))
    f.fillName:setColor(COLORS.text)
    f.fillCountEdit:setText('')
    f.fillCountEdit:setEnabled(false)
    f.fillPayText:setText('')
    f.fillButton:setEnabled(false)
    return
  end
  f.fillSlot:setItemId(tonumber(c.item) or 0)
  f.fillSlot:setItemCount(c.count or 1)
  f.fillName:setText(((c.count or 1) > 1 and (c.count .. 'x ') or '') .. (c.name or '?'))
  f.fillName:setColor(rarityColor(c))
  f.fillCountEdit:setEnabled(c.stack == true)
  f.fillCountEdit:setText(tostring(c.fill or 1))
  f.fillPayText:setText(V.fillText(meta, fillState.order, c.fill or 1))
  f.fillButton:setEnabled(true)
end

function openFill(row)
  if not window then return end
  local p = window.ordersPanel
  fillState = { order = row, items = {} }
  p.postFrame:hide()
  p.fillFrame:show()
  local f = p.fillFrame
  local left = (tonumber(row.qty) or 0) - (tonumber(row.filled) or 0)
  f.fillHeader:setText(tr('%s wants %s%s at %s %s each', row.buyer or '?', left > 1 and (V.money(left) .. 'x ') or '',
    row.name or '?', V.money(row.price or 0), row.cur == 'coins' and tr('Chaos Coins') or tr('gold')))
  f.fillFilter:setText(tr('Must be: %s', V.orderFilterText(row.filter, modName)))
  f.fillList:destroyChildren()
  showFillChoice()
  send('fillable', { id = row.id })
end

function closeFill()
  if not window then return end
  fillState = nil
  window.ordersPanel.fillFrame:hide()
  window.ordersPanel.postFrame:show()
end

local function onFillable(data)
  if not fillState or fillState.order.id ~= data.id then return end
  if type(data.order) == 'table' then fillState.order = data.order end
  local f = window.ordersPanel.fillFrame
  f.fillList:destroyChildren()
  fillState.items = V.sortFillable(data.items or {})
  fillState.chosen = nil
  showFillChoice()
  for _, e in ipairs(fillState.items) do
    local w = g_ui.createWidget('MarketPick', f.fillList)
    w:setId('fill_' .. tostring(e.ref))
    w:setItemId(tonumber(e.item) or 0)
    showLook(w, e.look)
    if (e.count or 1) > 1 then w:setItemCount(e.count) end
    if (e.rarity or 0) > 0 then
      w:setBorderWidth(1)
      w:setBorderColor(rarityColor(e))
    end
    local tip = ((e.count or 1) > 1 and (e.count .. 'x ') or '') .. (e.name or '?')
    if e.why then
      w:setOpacity(0.35)
      tip = tip .. '\n' .. e.why
    end
    w:setTooltip(wrapTip(tip))
    w.onClick = function()
      if e.why then setStatus(e.why, COLORS.error) return end
      fillState.chosen = e
      showFillChoice()
      setStatus('')
    end
  end
  if #fillState.items == 0 then
    f.fillName:setText(tr('You carry none of this item in your backpack.'))
  else
    local fits
    for _, e in ipairs(fillState.items) do if not e.why then fits = fits or e end end
    if fits then
      fillState.chosen = fits
      showFillChoice()
    end
  end
end

function fillOrder()
  if not window or not fillState or not fillState.chosen then return end
  local c = fillState.chosen
  local n = c.stack and tonumber(window.ordersPanel.fillFrame.fillCountEdit:getText()) or 1
  if not n or n < 1 or n > (c.count or 1) then
    setStatus(tr('How many: from 1 to what the stack holds.'), COLORS.error)
    return
  end
  send('fill', { id = fillState.order.id, ref = c.ref, sid = c.sid, iid = c.iid, count = n })
end

local function initOrders()
  local p = window.ordersPanel
  p.orderSearch.onTextChange = function(w, text)
    p.orderSearchHint:setVisible(text == '')
    if not updating then orderSearch(1) end
  end
  for _, id in ipairs({ 'orderCurCombo', 'orderSortCombo' }) do
    p[id].onOptionChange = function() if not updating then orderSearch(1) end end
  end
  p.orderMineCheck:setWidth(p.orderMineCheck:getTextSize().width + 26)
  p.orderMineCheck.onCheckChange = function() orderSearch(1) end
  local f = p.postFrame
  f.findEdit.onTextChange = function(w, text) f.findHint:setVisible(text == '') end
  f.findEdit.onKeyPress = function(w, keyCode)
    if keyCode == KeyEnter then orderFind() return true end
    return false
  end
  for _, id in ipairs({ 'qtyEdit', 'priceEdit', 'orderIlvlEdit' }) do
    f[id].onTextChange = function() updateOrderCost() end
  end
  for _, id in ipairs({ 'orderDaysCombo', 'orderPayCombo', 'orderRarityCombo' }) do
    f[id].onOptionChange = function() if not updating then updateOrderCost() end end
  end
  p.fillFrame.fillCountEdit.onTextChange = function(w, text)
    if fillState and fillState.chosen then
      p.fillFrame.fillPayText:setText(V.fillText(meta, fillState.order, tonumber(text) or 0))
    end
  end
  fillOrderCombos()
  showChosenKind()
  updateOrderCost()
end

-- ---------------------------------------------------------------- tabs
local PANELS = { 'browsePanel', 'sellPanel', 'minePanel', 'historyPanel', 'ordersPanel' }

local function showTab(i)
  tabIndex = i
  for k, b in ipairs(tabs) do b:setChecked(k == i) end
  for k, id in ipairs(PANELS) do window[id]:setVisible(k == i) end
  closePrices()
  local tt = tooltips()
  if hoveredRow and tt and tt.hideTip then tt.hideTip(hoveredRow) hoveredRow = nil end
  if i == 1 then
    sendBrowse()
  elseif i == 2 then
    send('sellable')
    updateFee()
  elseif i == 3 then
    send('mine')
  elseif i == 4 then
    send('history')
  elseif i == 5 then
    sendOrders()
    updateOrderCost()
  end
end

-- ---------------------------------------------------------------- server messages
-- the shape of what the server sent (game_chaosguard/opcode_fuzz_test.lua): lists keep their tables (rows) or their
-- strings and numbers (categories, sorts, durations), counts are numbers; anything else is left out, so a window is
-- never left half drawn by a bad row
local ROW_LISTS = { 'rows', 'active', 'closed', 'items' }
local VALUE_LISTS = { 'categories', 'sorts', 'durations' }
local NUMBERS = { 'page', 'pages', 'total', 'used', 'max', 'owed', 'maxActive', 'realm', 'defaultDuration' }
local OBJECTS = { 'fee', 'tax', 'price', 'orders', 'modFilter' }
local function shaped(data)
  for _, k in ipairs(OBJECTS) do
    if type(data[k]) ~= 'table' then data[k] = nil end
  end
  for _, k in ipairs(ROW_LISTS) do
    if data[k] ~= nil then
      local out = {}
      for _, r in ipairs(type(data[k]) == 'table' and data[k] or {}) do
        if type(r) == 'table' then out[#out + 1] = r end
      end
      data[k] = out
    end
  end
  for _, k in ipairs(VALUE_LISTS) do
    if data[k] ~= nil then
      local out = {}
      for _, v in ipairs(type(data[k]) == 'table' and data[k] or {}) do
        if type(v) == 'string' or type(v) == 'number' then out[#out + 1] = v end
      end
      data[k] = out
    end
  end
  for _, k in ipairs(NUMBERS) do
    if data[k] ~= nil then data[k] = tonumber(data[k]) end
  end
  return data
end

local function onMessage(protocol, opcode, msg)
  if not window or type(msg) ~= 'table' then return end
  local data = shaped(type(msg.data) == 'table' and msg.data or {})
  local a = msg.action
  if a == 'meta' then
    meta = data
    fillFilterCombos()
    fillOrderCombos()
    applyCoinRule()
    updateWallet()
    local s = window.sellPanel
    s.rulesText:setText(tr('Locked, equipped, store and quest items and bags with something inside cannot be listed. '
      .. 'Bought items and items that come back arrive in your inbox (the depot); gold goes to your bank, Chaos Coins to your '
      .. 'account. Up to %d offers at a time.%s', meta.maxActive or 20,
      (meta.realm or 0) > 0 and (meta.coinsOk == false and tr(' Season characters trade on their own season market, for gold only.')
        or tr(' Season characters trade on their own season market.')) or ''))
    updateFee()
    if not window:isVisible() then return end
    showTab(tabIndex)
  elseif a == 'openWindow' then
    window:show()
    window:raise()
    window:focus()
  elseif a == 'page' then
    onPage(data)
  elseif a == 'tip' then
    if data.id and type(data.tip) == 'table' then
      tipCache[data.id] = data.tip
      if hoveredRow and not hoveredRow:isDestroyed() and hoveredRow.offer.id == data.id then showRowTip(hoveredRow) end
    end
  elseif a == 'sellable' then
    onSellable(data)
  elseif a == 'mine' then
    onMine(data)
  elseif a == 'history' then
    onHistory(data)
  elseif a == 'wallet' then
    updateWallet(data.gold, data.coins)
  elseif a == 'orders' then
    onOrders(data)
  elseif a == 'myOrders' then
    onMyOrders(data)
  elseif a == 'orderFind' then
    onOrderFind(data)
  elseif a == 'fillable' then
    onFillable(data)
  elseif a == 'prices' then
    onPrices(data)
  elseif a == 'done' then
    setStatus(data.text, COLORS.ok)
    if data.what == 'list' then
      selected = nil
      showSelected()
      window.sellPanel.goldEdit:setText('')
      window.sellPanel.coinsEdit:setText('')
      send('sellable')
    elseif data.what == 'buy' then
      sendBrowse()
    elseif data.what == 'cancel' then
      if tabIndex == 3 then send('mine') else sendBrowse() end
    elseif data.what == 'orderPost' or data.what == 'orderCancel' then
      sendOrders()
    elseif data.what == 'fill' then
      sendOrders()
      if fillState then send('fillable', { id = fillState.order.id }) end
    end
  elseif a == 'error' then
    setStatus(data.text, COLORS.error)
    if browseWaiting then
      browseWaiting = false
      window.statusLabel.filterError = true
    end
  end
end

-- ---------------------------------------------------------------- public
function show()
  if not window or not g_game.isOnline() then return end
  window:show()
  window:raise()
  window:focus()
  send('open')
end

function hide()
  if not window then return end
  local tt = tooltips()
  if hoveredRow and tt and tt.hideTip then tt.hideTip(hoveredRow) end
  hoveredRow = nil
  window:hide()
end

function toggle()
  if not window then return end
  if window:isVisible() then hide() else show() end
end

-- the filters (the Modifiers section too) stay as they are while the character is logged in; a new login starts clean
local function onGameEnd()
  hide()
  meta, selected, tipCache, tipAsked, sellItems = nil, nil, {}, {}, {}
  lastFilter = { page = 1 }
  orderFilter, chosenKind, orderMods, fillState = { page = 1 }, nil, nil, nil
  closePrices()
  priceState = { seq = 0 }
  if window then
    clearMods()
    modsOpen = false
    layoutMods()
  end
end

function init()
  window = g_ui.displayUI('market')
  window:hide()
  for i, name in ipairs({ tr('Browse'), tr('Sell'), tr('My Offers'), tr('History'), tr('Buy Orders') }) do
    local b = g_ui.createWidget('ChaosTabButton', window.tabBar)
    b:setText(name)
    b.onClick = function() showTab(i) end
    tabs[i] = b
  end
  -- five tabs: each as wide as its text, so the wallet line on the right keeps its room
  local barWidth = 0
  for _, b in ipairs(tabs) do
    b:setWidth(math.max(64, b:getTextSize().width + 24))
    barWidth = barWidth + b:getWidth() + 4
  end
  window.tabBar:setWidth(barWidth)
  tabs[1]:setChecked(true)
  local p = window.browsePanel
  p.searchEdit.onTextChange = function(w, text)
    p.searchHint:setVisible(text == '')
    if not updating then search(1) end
  end
  p.searchEdit.onKeyPress = function(w, keyCode)
    if keyCode == KeyEnter then search(1) return true end
    return false
  end
  for _, id in ipairs({ 'catCombo', 'rarityCombo', 'curCombo', 'sortCombo' }) do
    p[id].onOptionChange = function() if not updating then search(1) end end
  end
  local mp = p.modPanel
  mp.modeCombo.onOptionChange = function(w, text, data)
    w.mode = data
    if not updating then updateModToggle() search(1) end
  end
  for _, id in ipairs({ 'needEdit', 'socketsEdit', 'qualityEdit' }) do
    mp[id].onTextChange = function() if not updating then search(1) end end
  end
  for _, id in ipairs({ 'freePCheck', 'freeSCheck', 'powerCheck', 'boundCheck' }) do
    local c = mp[id]
    c:setWidth(c:getTextSize().width + 26)
    c.onCheckChange = function() if not updating then search(1) end end
  end
  mp.modHint:setText(tr('Up to 6 modifiers. Type in the box on the left to find one. Tiers: T1 is the lowest, T8 the best (T5+ = T5 or better). '
    .. 'Values as on the item.'))
  connect(mp.modHint, { onGeometryChange = function() if modsOpen then addEvent(layoutMods) end end })
  local s = window.sellPanel
  s.goldEdit.onTextChange = function() updateFee() end
  s.coinsEdit.onTextChange = function() updateFee() end
  s.countEdit.onTextChange = function() updatePriceHint() end
  s.daysCombo.onOptionChange = function() if not updating then updateFee() end end
  s.sellSlot.onDrop = onDropItem
  fillFilterCombos()
  layoutMods()
  showSelected()
  updateFee()
  initOrders()
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, onMessage)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  if searchEvent then removeEvent(searchEvent) searchEvent = nil end
  if orderSearchEvent then removeEvent(orderSearchEvent) orderSearchEvent = nil end
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if window then
    window:destroy()
    window = nil
  end
  tabs = {}
  modRowWidgets = {}
end
