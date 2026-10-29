-- Factions window: the four factions with their emblem and rank bar, the shown faction's lore, rival, standing, tokens,
-- contracts with progress and the quartermaster's offers with their lock state.
-- Server: server/data/scripts/chaos/factions.lua, extended opcode 215 (JSON {action, data}; the state goes out with
-- Chaos.sendChunked and is joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open {f?} | close | turnin {f} | deliver {key} | buy {key} | craft {key}
--   server -> client  state {...} (factionsview.lua has the shape) | msg {text, ok} | npc {f} (a faction NPC: open on f)
-- Menu: Adventure > Factions (added with ChaosTopBar.addEntry). Emblems: /images/factions/<key>.png
-- (client/tools/gen_faction_art.py).

local OPCODE = 215
local V = FactionsView

local window
local data
local selected
local tab = 'contracts'
local handlers = {}
local reported = {}
local msgEvent

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[factions] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function send(action, d)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = d or {} }))
  end
end

local function emblem(key, small)
  return '/images/factions/' .. tostring(key) .. (small and '_small' or '')
end

-- ---------------------------------------------------------------- the cards
local function renderCards()
  local list = window.cardList
  list:destroyChildren()
  local factions = {} -- an entry that is no table is left out
  for _, f in ipairs(type(data.factions) == 'table' and data.factions or {}) do
    if type(f) == 'table' then factions[#factions + 1] = f end
  end
  for _, f in ipairs(factions) do
    local card = g_ui.createWidget('FactionCard', list)
    card.emblem:setImageSource(emblem(f.k))
    card.emblem:setImageSize({ width = 48, height = 48 })
    card.name:setText(V.cardName(f))
    if f.c then card.name:setColor(f.c) end
    card.rank:setText(tostring(f.rn or ''))
    if f.rc then card.rank:setColor(f.rc) end
    card.near:setText(f.near and tr('%s is here', f.npc or '') or '')
    card.bar:setPercent(V.barPercent(f))
    card.bar:setText(V.barText(f))
    if f.rc then card.bar:setBackgroundColor(f.rc) end
    if f.k == selected then
      card:setImageSource('/images/chaos/panel_highlight')
      card:setImageBorder(8)
    end
    local key = f.k
    card.onClick = function()
      selected = key
      modules.game_factions.render()
      return true
    end
    card:setTooltip(V.nextText(f) .. '\n' .. V.weekText(f, data.weekCap))
  end
end

-- ---------------------------------------------------------------- the rows
local function contractRow(list, c, f)
  local row = g_ui.createWidget('FactionContractRow', list)
  local tag, color = V.contractTag(c)
  row.tag:setText(tag)
  row.tag:setColor(color)
  row.label:setText(tostring(c.label or ''))
  row.label:setTooltip(tostring(c.label or ''))
  row.rep:setText(tr('+%s rep', V.fmt(c.rep)))
  row.progress:setPercent(V.progressPercent(c))
  row.progress:setText(V.progressText(c))
  if c.done then
    row.progress:setBackgroundColor('#3f7a2a')
    row.label:setColor('#8c8070')
  else
    row.progress:setBackgroundColor(c.per == 'w' and '#5a3a8a' or '#8a6a1c')
  end
  local shown, enabled, tip = V.deliverButton(c, f)
  row.action:setVisible(shown)
  row.action:setEnabled(enabled)
  row.action:setTooltip(tip)
  if not shown then
    row.progress:setMarginRight(0)
  end
  local key = c.key
  row.action.onClick = function() send('deliver', { key = key }) return true end
  row:setTooltip(tostring(c.label or ''))
end

local function offerRow(list, o, f)
  local row = g_ui.createWidget('FactionOfferRow', list)
  local id = tonumber(o.item) or 0
  if id > 0 then row.item:setItemId(id) end
  row.name:setText(tostring(o.n or o.key))
  row.kind:setText(V.offerKindText(o))
  row.price:setText(V.priceText(o, f))
  local text, enabled, color, tip = V.offerButton(o, f)
  row.action:setText(text)
  row.action:setEnabled(enabled)
  row.action:setTooltip(tip)
  row.state:setText(tr('Needs %s', o.rn or '?'))
  row.state:setColor(color)
  if o.st == 'locked' then
    row.name:setColor('#8c8070')
    row.item:setOpacity(0.45)
  end
  local key, kind = o.key, o.kind
  row.action.onClick = function()
    send((o.st == 'owned' and kind == 'recipe') and 'craft' or 'buy', { key = key })
    return true
  end
  row:setTooltip(V.offerTooltip(o, f))
end

local function renderList(f)
  local list = window.detail.rowList
  list:destroyChildren()
  local rows = tab == 'offers' and V.offersFor(data, f.k) or V.contractsFor(data, f.k)
  for _, r in ipairs(rows) do
    if tab == 'offers' then offerRow(list, r, f) else contractRow(list, r, f) end
  end
  window.detail.emptyText:setVisible(#rows == 0)
  window.detail.emptyText:setText(tab == 'offers' and tr('Nothing on offer.') or tr('No contracts right now.'))
  window.detail.contractsTab:setChecked(tab ~= 'offers')
  window.detail.offersTab:setChecked(tab == 'offers')
  local open = V.contractsSummary(data, f.k)
  window.detail.contractsTab:setText(open > 0 and tr('Contracts (%d)', open) or tr('Contracts'))
end

local function renderDetail()
  local d = window.detail
  local f = V.faction(data, selected)
  d:setVisible(f ~= nil)
  if not f then return end
  d.emblem:setImageSource(emblem(f.k))
  d.name:setText(tostring(f.n or f.k))
  if f.c then d.name:setColor(f.c) end
  d.lore:setText(tostring(f.lore or ''))
  d.rival:setText(V.rivalText(data, f))
  d.rankBar:setPercent(V.barPercent(f))
  d.rankBar:setText(V.barText(f))
  if f.rc then d.rankBar:setBackgroundColor(f.rc) end
  d.nextLabel:setText(V.nextText(f))
  d.weekLabel:setText(V.weekText(f, data.weekCap))
  d.weekLabel:setColor(V.capped(f, data.weekCap) and '#e05a3a' or '#d6c9ae')
  d.drLabel:setText(V.drText(f))
  local tid = tonumber(f.tid) or 0
  if tid > 0 then d.tokenItem:setItemId(tid) end
  d.tokenLabel:setText(V.tokenText(f))
  local enabled, tip = V.tokenButton(f, data.weekCap)
  d.turnInButton:setEnabled(enabled)
  d.turnInButton:setTooltip(tip)
  d.handInLabel:setText(V.handInText(f))
  d.handInLabel:setColor(f.near and '#6fd86f' or '#d6c9ae')
  local goOn, goTip = V.goButton(f)
  d.goNpcButton:setEnabled(goOn)
  d.goNpcButton:setTooltip(goTip)
  renderList(f)
end

function render()
  if not window or not data then return end
  selected = V.select(data, selected)
  data.sel = nil
  renderCards()
  renderDetail()
  window.resetLabel:setText(V.resetText(data))
end

-- ---------------------------------------------------------------- messages
local function showMessage(text, ok)
  if not window then return end
  window.msgLabel:setText(tostring(text or ''))
  window.msgLabel:setColor(ok and '#6fd86f' or '#e05a3a')
  if msgEvent then removeEvent(msgEvent) end
  msgEvent = scheduleEvent(function()
    msgEvent = nil
    if window then window.msgLabel:setText('') end
  end, 6000)
end

local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local d = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    data = d
    render()
  elseif msg.action == 'msg' then
    showMessage(d.text, d.ok)
  elseif msg.action == 'npc' then
    local f = type(d.f) == 'string' and d.f or nil -- a faction key; anything else is not echoed back
    selected = f or selected
    show(f)
  end
end

-- ---------------------------------------------------------------- window
function hide()
  if window and window:isVisible() then
    send('close')
    window:hide()
  end
end

function show(f)
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  send('open', { f = f or selected })
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

function showTab(name)
  tab = name == 'offers' and 'offers' or 'contracts'
  render()
end

function turnIn()
  if selected then send('turnin', { f = selected }) end
end

-- the Go to NPC button: teleports in front of the shown faction's NPC (server npc_travel.lua, key "faction_<key>")
function goToNpc()
  local nt = modules.game_npctravel
  if selected and nt and nt.travel then nt.travel('faction_' .. selected) end
end

-- for other modules and tests: load a payload as if the server had sent it
function setData(d)
  data = d
  render()
end

function getState()
  return { selected = selected, tab = tab, visible = window and window:isVisible() or false,
    factions = data and #(data.factions or {}) or 0 }
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'adventure',
      { text = 'Factions', icon = 'quests', modules = { 'game_factions' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  data = nil
  addMenu()
end

local function onGameEnd()
  if window then window:hide() end
  data = nil
end

function init()
  local ok, ui = pcall(g_ui.displayUI, 'factions')
  if ok and ui then
    window = ui
    window:hide()
  else
    g_logger.warning('[factions] window not loaded: ' .. tostring(ui))
  end
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, safe('opcode', onMessage))
  connect(g_game, handlers.game)
  addMenu()
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game)
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if msgEvent then removeEvent(msgEvent) msgEvent = nil end
  if window then window:destroy() window = nil end
  data, handlers = nil, {}
end
