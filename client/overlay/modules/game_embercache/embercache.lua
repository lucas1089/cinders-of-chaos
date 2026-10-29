-- Ember Cache window (server embercache.lua): this week's Ember points and the three milestones with their rewards,
-- today's points and the Daily Spark, the day book (what the character did today) and how to earn points (the
-- tooltip of "How to earn points"). Opened from the menu, Adventure > Ember Cache (ChaosTopBar.addEntry).
-- The server talks on extended opcode 174 (JSON, joined by registerExtendedJSONOpcode):
--   client -> server  open | close | get | offerQuote | offer
--   server -> client  state {open?, week, day, src, book} | offer {orbs, points, room, per, carried} (the quote)
-- Offer junk orbs: the button asks the server for a quote, a box shows it, Yes sends offer. The server decides what
-- is taken from the backpack (the client sends no number).
-- Rewards are given by the server when a milestone or the Spark is reached (a toast tells); the window only shows.
-- Pure parts: cacheview.lua (cacheview_test.lua).

local OPCODE = 174

local window
local state
local handlers = {}

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function safe(what, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then g_logger.warning('[embercache] ' .. what .. ': ' .. tostring(err)) end
  end
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

-- a view text {pattern, args...} through tr(); a pattern without letters ('%s', '%d / %d') is a value, not a key
local function text(t)
  if type(t) ~= 'table' then return '' end
  if type(t[1]) ~= 'string' or not t[1]:find('%a%a') then return CacheView.plain(t) end
  local args = {}
  for i = 2, #t do
    args[#args + 1] = type(t[i]) == 'table' and text(t[i]) or t[i]
  end
  return tr(t[1], (table.unpack or unpack)(args))
end

local function render()
  if not alive(window) then return end
  local v = CacheView.build(state)
  window.week:setText(text(v.week))
  window.weekEnds:setText(text({ v.weekEnds[1], v.weekLeft }))
  window.tiers:destroyChildren()
  for _, t in ipairs(v.tiers) do
    local row = g_ui.createWidget('EmberTierRow', window.tiers)
    row.title:setText(text(t.title))
    row.status:setText(text(t.status))
    row.status:setColor(t.color)
    row.reward:setText(text(t.reward))
  end
  window.sparks:setText(text(v.sparks))
  window.today:setText(text(v.today))
  window.spark:setText(text(v.spark))
  window.spark:setColor(v.sparkColor)
  window.sparkReward:setText(text(v.sparkReward))
  window.bonus:setText(text(v.bonus))
  window.book:destroyChildren()
  for i, r in ipairs(v.book) do
    local row = g_ui.createWidget('EmberBookRow', window.book)
    if i % 2 == 0 then row:setBackgroundColor('#141014') end
    row.label:setText(text(r[1]))
    row.value:setText(text(r[2]))
  end
  local lines = {}
  for _, s in ipairs(v.sources) do
    local line = text(s.label) .. ': ' .. text(s.pts)
    if s.cap then line = line .. ', ' .. text(s.cap) end
    lines[#lines + 1] = line
  end
  window.howTo:setTooltip(table.concat(lines, '\n'))
end

function show()
  if not alive(window) then return end
  window:show()
  window:raise()
  window:focus()
  send('open')
end

function hide()
  if alive(window) and window:isVisible() then
    window:hide()
    send('close')
  end
end

function toggle()
  if not alive(window) then return end
  if window:isVisible() then
    hide()
  else
    show()
  end
end

local offerBox

local function closeOffer()
  if offerBox then
    pcall(function() offerBox:destroy() end)
    offerBox = nil
  end
end

-- the quote came: a box with Yes / No (or only why there is nothing to offer)
local function showOffer(q)
  closeOffer()
  local v = CacheView.offer(q)
  if not displayGeneralBox then
    if v.can then send('offer') end
    return
  end
  local function yes() closeOffer() send('offer') end
  if v.can then
    offerBox = displayGeneralBox(tr('Offer junk orbs'), text(v.text),
      { { text = tr('Yes'), callback = yes }, { text = tr('No'), callback = closeOffer }, anchor = AnchorHorizontalCenter },
      yes, closeOffer)
  else
    offerBox = displayGeneralBox(tr('Offer junk orbs'), text(v.text),
      { { text = tr('Close'), callback = closeOffer }, anchor = AnchorHorizontalCenter }, closeOffer, closeOffer)
  end
end

function offerOrbs()
  send('offerQuote')
end

local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' or type(msg.data) ~= 'table' then return end
  if msg.action == 'offer' then
    showOffer(msg.data)
    return
  end
  if msg.action ~= 'state' then return end
  state = msg.data
  render()
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if not api or not api.addEntry or handlers.menu then return end
  local ok, shown = pcall(api.available)
  for _, entry in ipairs(ok and type(shown) == 'table' and shown.adventure or {}) do
    if entry == 'Ember Cache' then
      handlers.menu = true
      return
    end
  end
  handlers.menu = pcall(api.addEntry, 'adventure',
    { text = 'Ember Cache', icon = 'daily', modules = { 'game_embercache' }, fns = { 'toggle' } })
end

local function onGameStart()
  state = nil
  addMenu()
end

local function onGameEnd()
  closeOffer()
  if alive(window) then window:hide() end
  state = nil
end

function init()
  local ok, ui = pcall(g_ui.displayUI, 'embercache')
  if ok and ui then
    window = ui
    window:hide()
    pcall(function() modules.game_howitworks.attach(window, 'embercache') end) -- game_howitworks: the ? button
  else
    g_logger.warning('[embercache] window not loaded: ' .. tostring(ui))
  end
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  connect(g_game, handlers.game)
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, safe('opcode', onMessage))
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  if handlers.game then disconnect(g_game, handlers.game) end
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  closeOffer()
  if alive(window) then window:destroy() end
  window, state = nil, nil
  handlers = {}
end
