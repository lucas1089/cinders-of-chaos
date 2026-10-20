-- Boss Spawns window: every boss of the server by category, where it is and when it comes back.
-- Server: server/data/scripts/chaos/bossspawns.lua, extended opcode 217 (JSON {action, data}, sent with
-- Chaos.sendChunked and joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | refresh | pocketEnter {k} (server pocketboss.lua)
--   server -> client  list {now, refresh, cats = [{k, n, c, t}], rows = [{k, c, n, loc, p, lv, o, st, in, at, tx, ago, by,
--                     kills, alive, party}]}
--                     pocket {bosses = {key = {l, m, b, lv, ok}}, reset, inside} (the Pocket buttons; after every list)
--                     pocketError {text} (why a pocket did not open, already in the player's language)
-- The countdowns tick here every second from the moment the list arrived; the list is asked again every `refresh`
-- seconds while the window is open. Menu: Adventure > Boss Spawns (added with ChaosTopBar.addEntry).

local OPCODE = 217
local V = BossSpawnsView

local window
local data
local pocket -- the pocket charges (server pocketboss.lua)
local pocketAt = 0
local pocketMsg, pocketMsgAt -- the last refusal, shown for a few seconds in the bottom line
local receivedAt = 0
local askedAt = 0
local collapsed = {} -- category key -> true (kept for the session)
local live = {} -- {row = data row, widget = row widget} of the rows on screen
local tickEvent
local handlers = {}
local reported = {}

local function now() return g_clock.seconds() end

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[bossspawns] ' .. name .. ': ' .. tostring(res))
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

local function stopTick()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

local function elapsed() return math.max(0, now() - receivedAt) end

local function updateRow(entry, e)
  local text, color = V.status(entry.row, e)
  local w = entry.widget
  w.status:setText(text)
  w.status:setColor(color)
  w.sub:setText(V.statusSub(entry.row, e))
end

local function updateLive()
  local e = elapsed()
  for _, entry in ipairs(live) do updateRow(entry, e) end
  if window and pocketMsg and now() - (pocketMsgAt or 0) < 8 then
    window.updatedLabel:setText(pocketMsg)
  elseif window and data then
    local age = math.floor(e)
    window.updatedLabel:setText(age < 5 and tr('Updated just now') or tr('Updated %s', V.ago(age)))
  end
end

local function tick()
  tickEvent = nil
  if not window or not window:isVisible() then return end
  updateLive()
  local period = tonumber(data and data.refresh) or 30
  if data and elapsed() >= period and now() - askedAt >= period then
    askedAt = now() -- once per period even when the answer is late
    send('refresh')
  end
  tickEvent = scheduleEvent(tick, 1000)
end

local function setCreature(widget, o)
  if type(o) ~= 'table' or (tonumber(o.type) or 0) <= 0 then
    widget:setVisible(false)
    return
  end
  widget:setVisible(true)
  widget:setOutfit({ type = tonumber(o.type), head = tonumber(o.head) or 0, body = tonumber(o.body) or 0,
    legs = tonumber(o.legs) or 0, feet = tonumber(o.feet) or 0, addons = tonumber(o.addons) or 0 })
end

local function setPocket(w, r)
  local pk = V.pocket(r, pocket, math.max(0, now() - pocketAt))
  w.pocketButton:setVisible(pk ~= nil)
  if not pk then return end
  w.pocketButton:setText(pk.text)
  w.pocketButton:setTooltip(pk.tooltip)
  w.pocketButton:setEnabled(pk.enabled)
  local key = r.k
  w.pocketButton.onClick = function()
    send('pocketEnter', { k = key })
    return true
  end
end

local function render()
  if not window then return end
  local list = window.rowList
  list:destroyChildren()
  live = {}
  local filter = window.searchEdit:getText()
  local groups = V.group(data, filter)
  local shown, total = 0, 0
  local e = elapsed()
  for _, g in ipairs(groups) do
    total = total + g.total
    local header = g_ui.createWidget('BossSpawnsCategory', list)
    local folded = collapsed[g.cat.k] and filter == ''
    header.title:setText(V.header(g, folded))
    if g.cat.c then header.title:setColor(g.cat.c) end
    header.info:setText(tostring(g.cat.t or ''))
    local key = g.cat.k
    header.onClick = function()
      collapsed[key] = not collapsed[key]
      render()
      return true
    end
    if not folded then
      for _, r in ipairs(g.rows) do
        local w = g_ui.createWidget('BossSpawnsRow', list)
        setCreature(w.creature, r.o)
        w.name:setText(tostring(r.n or '?'))
        w.level:setText(V.levelText(r))
        w.loc:setText(tostring(r.loc or ''))
        w.coords:setText(V.where(r))
        w:setTooltip(V.tooltip(r, e))
        setPocket(w, r)
        live[#live + 1] = { row = r, widget = w }
        shown = shown + 1
      end
    end
  end
  updateLive()
  window.emptyText:setVisible(#groups == 0)
  if #groups == 0 then
    window.emptyText:setText(data and (filter ~= '' and tr('No boss matches.') or tr('No bosses listed.')) or tr('Loading...'))
  end
  window.countLabel:setText(data and tr('%d bosses', #(data.rows or {})) or '')
end

local function onList(d)
  data = d
  receivedAt = now()
  render()
end

local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  if msg.action == 'list' and type(msg.data) == 'table' then
    onList(msg.data)
  elseif msg.action == 'pocket' and type(msg.data) == 'table' then
    pocket = msg.data
    pocketAt = now()
    if data then render() end
  elseif msg.action == 'npc' then
    -- the pocket boss NPC (service_npcs*.lua) opens the window; an open one stays open
    if not (window and window:isVisible()) then show() end
  elseif msg.action == 'pocketError' and type(msg.data) == 'table' and type(msg.data.text) == 'string' then
    pocketMsg, pocketMsgAt = msg.data.text, now()
    updateLive()
  end
end

-- ---------------------------------------------------------------- window
function hide()
  stopTick()
  if window then window:hide() end
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  askedAt = now()
  send('open')
  stopTick()
  tick()
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

function refresh()
  send('refresh')
end

function foldAll(fold)
  if not data then return end
  for _, c in ipairs(data.cats or {}) do
    collapsed[c.k] = fold and true or nil
  end
  render()
end

-- for other modules and tests
function getState()
  return { rows = data and #(data.rows or {}) or 0, visible = window and window:isVisible() or false, shown = #live }
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'adventure',
      { text = 'Boss Spawns', icon = 'battlelist', modules = { 'game_bossspawns' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  data, pocket, pocketMsg = nil, nil, nil
  addMenu()
end

local function onGameEnd()
  hide()
  data, pocket, pocketMsg = nil, nil, nil
end

function init()
  local ok, ui = pcall(g_ui.displayUI, 'bossspawns')
  if ok and ui then
    window = ui
    window:hide()
    window.searchEdit.onTextChange = safe('search', function(_, text)
      window.searchHint:setVisible((text or '') == '')
      render()
    end)
  else
    g_logger.warning('[bossspawns] window not loaded: ' .. tostring(ui))
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
  stopTick()
  if window then window:destroy() window = nil end
  live, data, handlers = {}, nil, {}
end
