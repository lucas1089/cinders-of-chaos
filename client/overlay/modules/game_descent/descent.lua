-- The Ember Descent: the run HUD, the boon choice (three cards, sometimes a curse), the merchant and the entry window.
-- Server: server/data/scripts/chaos/descent.lua, extended opcode 205 (JSON {action, data}).
--   server -> client  info {...}   the entry window (the city portal, Adventure > Ember Descent)
--                     hud {room, rooms, type, state, depth, left, wave, waves, monsters, embers, reward, ward,
--                          boons = [{k, n, d, s, m}], curses = [{k, n, d, r}], party = [{name, alive, hp}], weekly, ...}
--                     offer {id, source, cards = [{k, n, d, s, m}], curse = {k, n, d, r, e} | nil, timeout, room, rooms}
--                     shop {embers, wares = [{k, n, d, p, off}]}, closeOffer, closeShop, closeInfo, msg {text},
--                     end {result, depth, rooms, gold, items, title, text, weekly}
--   client -> server  open | start {weekly} | craft | pick {offer, card, curse} | buy {key} | ready | leave | query
-- Pure helpers: descentmath.lua (descentmath_test.lua). Boon icons: /images/game/buffs/descent_b_<key> and
-- descent_c_<key> (client/tools/gen_descent_icons.py; the buff bar shows the same icons).

local OPCODE = 205
local M = DescentMath

local hud, offerWindow, shopWindow, infoWindow
local data -- the last hud data
local receivedAt = 0
local offer -- the open offer
local offerAt = 0
local info
local tickEvent, hideEvent
local handlers = {}
local reported = {}

local function now() return g_clock.seconds() end

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[descent] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function send(action, payload)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = payload or {} }))
  end
end

local function child(w, id)
  return w and w:recursiveGetChildById(id)
end

-- ---------------------------------------------------------------- HUD
local function place()
  local mapPanel = hud and hud:getParent()
  local plate = rootWidget:recursiveGetChildById('chaosHud')
  if not mapPanel or not plate or not plate:isVisible() then return end
  local r = plate:getRect()
  local bottom = r.y + r.height
  local buffs = rootWidget:recursiveGetChildById('buffBar')
  if buffs and buffs:isVisible() then
    local b = buffs:getRect()
    bottom = math.max(bottom, b.y + b.height)
  end
  local top = bottom + 8 - mapPanel:getY()
  if hud:getMarginTop() ~= top then hud:setMarginTop(top) end
end

local function updateClock()
  if not hud or not data then return end
  local left = M.left(data.left, receivedAt, now())
  local clock = child(hud, 'clock')
  clock:setText(data.state == 'done' and tr('Over') or M.clock(left))
  clock:setColor(left <= 60 and '#ff4030' or (left <= 300 and '#ff9a30' or '#f4d27a'))
  if offerWindow and offerWindow:isVisible() and offer then
    local l = M.left(offer.timeout, offerAt, now())
    child(offerWindow, 'subtitle'):setText(string.format('Room %d / %d   -   %s left to choose',
      tonumber(offer.room) or 0, tonumber(offer.rooms) or 0, M.clock(l)))
  end
end

local function stopTick()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

local function tick()
  tickEvent = nil
  updateClock()
  place()
  if data and data.state ~= 'done' then
    tickEvent = scheduleEvent(tick, 500)
  end
end

local function fillIcons(parent, list, curse)
  parent:destroyChildren()
  for _, b in ipairs(list) do
    local w = g_ui.createWidget('DescentBoonIcon', parent)
    w:setImageSource(M.icon(b.k, curse))
    w:setTooltip(M.tooltip(b, curse))
    local s = tonumber(b.s) or 1
    w:getChildById('stacks'):setText((not curse and s > 1) and tostring(s) or '')
  end
end

local function render()
  if not hud or not data then return end
  child(hud, 'title'):setText(data.weekly and tr('The Ember Descent (weekly)') or tr('The Ember Descent'))
  local room = child(hud, 'room')
  room:setText(M.roomLine(data) .. (data.theme and ('\n' .. tostring(data.theme)) or ''))
  room:setColor(M.roomColor(data.type))
  local bar = child(hud, 'progress')
  bar:setPercent(M.progress(data))
  bar:setText(string.format('Depth %d / %d', tonumber(data.depth) or 0, tonumber(data.rooms) or 0))
  bar:setBackgroundColor('#8a3a10')
  child(hud, 'state'):setText(M.stateLine(data))
  child(hud, 'embers'):setText(M.embersLine(data))
  local boons = type(data.boons) == 'table' and data.boons or {}
  local curses = type(data.curses) == 'table' and data.curses or {}
  fillIcons(child(hud, 'boons'), boons, false)
  fillIcons(child(hud, 'curses'), curses, true)
  child(hud, 'boonsHeader'):setText(#boons > 0 and tr('Boons') or tr('No boons yet'))
  child(hud, 'cursesHeader'):setVisible(#curses > 0)
  child(hud, 'curses'):setVisible(#curses > 0)
  local party = child(hud, 'party')
  party:destroyChildren()
  local list = type(data.party) == 'table' and data.party or {}
  if #list > 1 then
    for _, p in ipairs(list) do
      local l = g_ui.createWidget('DescentPartyLabel', party)
      l:setText(M.partyLine(p))
      if not p.alive then l:setColor('#8c8070') end
    end
  end
  local cont = child(hud, 'continueButton')
  cont:setVisible(data.state == 'rest')
  cont:setEnabled(not data.ready)
  updateClock()
end

local function showHud()
  if not hud then return end
  if hideEvent then removeEvent(hideEvent) hideEvent = nil end
  child(hud, 'result'):setVisible(false)
  child(hud, 'buttons'):setVisible(true)
  for _, id in ipairs({ 'state', 'boonsHeader', 'boons', 'party' }) do
    child(hud, id):setVisible(true)
  end
  place()
  hud:show()
  hud:raise()
end

local function hideHud()
  stopTick()
  if hideEvent then removeEvent(hideEvent) hideEvent = nil end
  if hud then hud:hide() end
  data = nil
end

local function onHud(d)
  local fresh = not data
  data = d
  receivedAt = now()
  if fresh or not hud:isVisible() then showHud() end
  render()
  stopTick()
  tick()
end

-- ---------------------------------------------------------------- the boon choice
local function hideOffer()
  offer = nil
  if offerWindow then offerWindow:hide() end
end

local function pick(index)
  if not offer then return end
  local check = child(offerWindow, 'curseCheck')
  send('pick', { offer = offer.id, card = index, curse = offer.curse ~= nil and check:isChecked() or false })
  hideOffer()
end

local function onOffer(d)
  if not offerWindow then return end
  offer = d
  offerAt = now()
  local cards = child(offerWindow, 'cards')
  cards:destroyChildren()
  local list = type(d.cards) == 'table' and d.cards or {}
  local xs = M.cardLayout(#list, 180, 14, cards:getWidth() > 0 and cards:getWidth() or 608)
  for i, c in ipairs(list) do
    local card = g_ui.createWidget('DescentCard', cards)
    card:setMarginLeft(xs[i])
    card:getChildById('icon'):setImageSource(M.icon(c.k))
    card:getChildById('name'):setText(M.cardTitle(c))
    card:getChildById('note'):setText(M.cardNote(c))
    card:getChildById('desc'):setText(tostring(c.d or ''))
    card:getChildById('pick').onClick = function() pick(i) end
  end
  local strip = child(offerWindow, 'curseStrip')
  local check = child(offerWindow, 'curseCheck')
  check:setChecked(false)
  if type(d.curse) == 'table' then
    strip:setVisible(true)
    child(offerWindow, 'curseIcon'):setImageSource(M.icon(d.curse.k, true))
    child(offerWindow, 'curseText'):setText(M.curseLine(d.curse))
    offerWindow:setHeight(400)
  else
    strip:setVisible(false)
    offerWindow:setHeight(340)
  end
  offerWindow:setText(d.source == 'shrine' and tr('The Shrine: Choose a Boon') or
    (d.source == 'merchant' and tr('Boon Cache: Choose a Boon') or tr('Choose a Boon')))
  offerWindow:show()
  offerWindow:raise()
  offerWindow:focus()
  updateClock()
end

-- ---------------------------------------------------------------- the merchant
function hideShop()
  if shopWindow then shopWindow:hide() end
end

local function onShop(d)
  if not shopWindow then return end
  child(shopWindow, 'embers'):setText(string.format('Your embers: %s', M.number(d.embers)))
  local wares = child(shopWindow, 'wares')
  wares:destroyChildren()
  for _, w in ipairs(type(d.wares) == 'table' and d.wares or {}) do
    local row = g_ui.createWidget('DescentWareRow', wares)
    local st = M.ware(w, d.embers)
    row:getChildById('name'):setText(tostring(w.n or ''))
    row:getChildById('desc'):setText(tostring(w.d or ''))
    local buy = row:getChildById('buy')
    buy:setText(st.text)
    buy:setEnabled(st.can)
    local key = w.k
    buy.onClick = function() send('buy', { key = key }) end
  end
  shopWindow:show()
  shopWindow:raise()
end

-- ---------------------------------------------------------------- the entry window
function hideInfo()
  if infoWindow then infoWindow:hide() end
end

local function onInfo(d)
  info = d
  if not infoWindow then return end
  local lines = child(infoWindow, 'lines')
  lines:destroyChildren()
  for _, l in ipairs(M.infoLines(d)) do
    local w = g_ui.createWidget('DescentText', lines)
    w:setText(l.text)
    w:setColor(l.color)
  end
  local c = M.craft(d)
  child(infoWindow, 'craftLine'):setText(c.text)
  child(infoWindow, 'craftButton'):setEnabled(c.can)
  local b = M.entryButtons(d)
  local normal, weekly = child(infoWindow, 'normalButton'), child(infoWindow, 'weeklyButton')
  normal:setText(b.normal.text or tr('Descend'))
  normal:setEnabled(b.normal.can)
  weekly:setText(b.weekly.text or tr('Weekly Descent'))
  weekly:setEnabled(b.weekly.can)
  if not infoWindow:isVisible() then child(infoWindow, 'message'):setText('') end
  infoWindow:show()
  infoWindow:raise()
  infoWindow:focus()
end

function toggle()
  if infoWindow and infoWindow:isVisible() then
    hideInfo()
  else
    send('open')
  end
end

function start(weekly)
  send('start', { weekly = weekly and true or false })
end

function craft()
  send('craft')
end

function ready()
  send('ready')
end

function leave()
  send('leave')
end

-- ---------------------------------------------------------------- the end
local function onEnd(d)
  hideOffer()
  hideShop()
  local e = M.endLines(d)
  if not data then
    data = { state = 'done', room = d.depth, rooms = d.rooms, depth = d.depth, type = 'boss', left = 0 }
    showHud()
  end
  data.state = 'done'
  data.depth = d.depth
  render()
  stopTick()
  local result = child(hud, 'result')
  result:setText(e.title .. '\n' .. table.concat(e.lines, '\n'))
  result:setColor(e.color)
  result:setVisible(true)
  child(hud, 'buttons'):setVisible(false)
  -- the summary takes the place of the run's state: the HUD stays above the bottom panel
  for _, id in ipairs({ 'state', 'boonsHeader', 'boons', 'cursesHeader', 'curses', 'party' }) do
    child(hud, id):setVisible(false)
  end
  if hideEvent then removeEvent(hideEvent) end
  hideEvent = scheduleEvent(hideHud, 20000)
end

-- ---------------------------------------------------------------- protocol
local function onMessage(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[descent] invalid JSON: ' .. tostring(msg))
    return
  end
  local d = type(msg.data) == 'table' and msg.data or {}
  local a = msg.action
  if a == 'hud' then
    onHud(d)
  elseif a == 'offer' then
    onOffer(d)
  elseif a == 'closeOffer' then
    if not d.id or (offer and offer.id == d.id) then hideOffer() end
  elseif a == 'shop' then
    onShop(d)
  elseif a == 'closeShop' then
    hideShop()
  elseif a == 'info' then
    onInfo(d)
  elseif a == 'closeInfo' then
    hideInfo()
  elseif a == 'msg' then
    if infoWindow and infoWindow:isVisible() then
      child(infoWindow, 'message'):setText(tostring(d.text or ''))
    elseif modules.game_textmessage then
      modules.game_textmessage.displayFailureMessage(tostring(d.text or ''))
    end
  elseif a == 'end' then
    onEnd(d)
  end
end

-- offline rendering and tests: feed a server message as if it came on the opcode
function receive(msg)
  onMessage(nil, OPCODE, type(msg) == 'string' and msg or json.encode(msg))
end

function getState()
  return { hud = hud and hud:isVisible() or false, offer = offerWindow and offerWindow:isVisible() or false,
    shop = shopWindow and shopWindow:isVisible() or false, info = infoWindow and infoWindow:isVisible() or false,
    room = data and data.room or 0, boons = data and type(data.boons) == 'table' and #data.boons or 0 }
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'adventure',
      { text = 'Ember Descent', icon = 'infinitytower', modules = { 'game_descent' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  addMenu()
  send('query')
end

local function onGameEnd()
  hideOffer()
  hideShop()
  hideInfo()
  hideHud()
end

function init()
  g_ui.importStyle('descent')
  handlers.opcode = safe('opcode', onMessage)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  local function make(style, parent)
    local ok, w = pcall(g_ui.createWidget, style, parent)
    if ok and w then
      w:hide()
      return w
    end
    g_logger.warning('[descent] ' .. style .. ' not loaded: ' .. tostring(w))
    return nil
  end
  hud = make('DescentHud', modules.game_interface.getMapPanel())
  offerWindow = make('DescentOfferWindow', rootWidget)
  shopWindow = make('DescentShopWindow', rootWidget)
  infoWindow = make('DescentInfoWindow', rootWidget)
  ProtocolGame.registerExtendedOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game or {})
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  stopTick()
  if hideEvent then removeEvent(hideEvent) hideEvent = nil end
  for _, w in ipairs({ hud, offerWindow, shopWindow, infoWindow }) do
    if w then w:destroy() end
  end
  hud, offerWindow, shopWindow, infoWindow, data, offer = nil, nil, nil, nil, nil, nil
  handlers = {}
end
