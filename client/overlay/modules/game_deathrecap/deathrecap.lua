-- Death recap: after a death the window shows who hit the character in its last seconds (each attacker with its look,
-- damage, share, health / mana part and element split), the killing blow, the time window, the experience and levels
-- lost and the last hits; the left column lists the character's last 5 deaths. It opens by itself after a death (at
-- the next login, where the server fills in what was lost) or a defeat in a mode, unless the player turned "Open after
-- a death" off (g_settings node 'chaosDeathRecap'). Menu: Hunt > Death Recap (ChaosTopBar.addEntry).
-- The server (server/data/scripts/chaos/deathrecap.lua) talks on extended opcode 154 (JSON, joined by
-- registerExtendedJSONOpcode):
--   client -> server  open {id?} | get {id}
--   server -> client  history {list, sel, recap} | recap {id, recap, auto}
-- Pure parts: deathrecaplogic.lua (deathrecaplogic_test.lua).

local OPCODE = 154
local NODE = 'chaosDeathRecap'

local window
local settings = DeathRecapLogic.sanitize(nil)
local history = {}   -- the summaries, newest first
local selected       -- id of the recap shown (nil: one sent without an id)
local current        -- the recap shown
local handlers = {}

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function safe(what, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then g_logger.warning('[deathrecap] ' .. what .. ': ' .. tostring(err)) end
  end
end

local function loadSettings()
  local ok, node = pcall(g_settings.getNode, NODE)
  settings = DeathRecapLogic.sanitize(ok and node or nil)
end

local function saveSettings()
  pcall(g_settings.setNode, NODE, settings)
  pcall(g_settings.save)
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

-- ---------------------------------------------------------------- render
local KIND_ICONS = { e = '/images/game/dpsmeter/env', h = '/images/game/dpsmeter/other', o = '/images/game/dpsmeter/other',
  u = '/images/game/dpsmeter/player', s = '/images/game/dpsmeter/player', c = '/images/game/dpsmeter/monster' }

local function fillBar(bar, segments, frac)
  bar:destroyChildren()
  local width = math.max(1, bar:getWidth())
  local full = math.floor(width * math.max(0, math.min(1, frac or 1)))
  local x = 0
  for i, s in ipairs(segments) do
    local w = (i == #segments) and (full - x) or math.floor(full * s.frac + 0.5)
    if w > 0 then
      local seg = g_ui.createWidget('DeathBarSegment', bar)
      seg:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      seg:setMarginLeft(x)
      seg:setWidth(w)
      seg:setBackgroundColor(s.color)
      x = x + w
    end
  end
end

local function renderHistory()
  local list = window.historyList
  list:destroyChildren()
  local rows = DeathRecapLogic.historyRows(history, selected)
  for _, r in ipairs(rows) do
    local b = g_ui.createWidget('DeathHistoryButton', list)
    b.title:setText(r.title)
    b.killer:setText(r.killer)
    b.sub:setText(r.sub)
    b:setChecked(r.selected)
    local id = r.id
    b.onClick = function()
      if id ~= selected then
        selected = id
        renderHistory()
        send('get', { id = id })
      end
    end
  end
  window.historyEmpty:setVisible(#rows == 0)
end

local function renderRecap()
  local L = DeathRecapLogic
  local h = L.header(current)
  local head = window.headPanel
  head.title:setText(current and tr(h.title) or tr('No death to show'))
  head.sub:setText(current and h.sub or '')
  head.loss:setText(current and tr(h.loss) or '')
  head.blow:setText(current and tr(L.killingBlow(current)) or '')
  window.window:setText(current and tr(h.window) or '')
  window.totals:setText(current and tr(h.totals) or '')
  fillBar(window.elementBar, L.segments({ total = current and tonumber(current.tot) or 0,
    elements = L.elements(current and current.el) }), 1)

  window.rowList:destroyChildren()
  local rows = L.rows(current)
  for i, r in ipairs(rows) do
    local row = g_ui.createWidget('DeathAttackerRow', window.rowList)
    if i % 2 == 0 then row:setBackgroundColor('#141014') end
    local hasLook = false
    if r.outfit then
      hasLook = pcall(row.creature.setOutfit, row.creature, r.outfit)
    end
    row.creature:setVisible(hasLook)
    row.kindIcon:setVisible(not hasLook)
    if not hasLook then row.kindIcon:setImageSource(KIND_ICONS[r.kind] or KIND_ICONS.c) end
    row.name:setText(r.name)
    row.name:setColor(r.color)
    row.value:setText(string.format('%s  %s%%', L.short(r.total), tostring(r.pct)))
    local info = { string.format('%s, %d hit%s', tr(r.kindName), r.hits, r.hits == 1 and '' or 's') }
    if r.crits > 0 then info[#info + 1] = tr('%d%% critical', r.critPct) end
    if r.mp > 0 then info[#info + 1] = tr('mana %s', L.short(r.mp)) end
    if r.elText ~= '' then info[#info + 1] = r.elText end
    row.info:setText(table.concat(info, '  |  '))
    row:setTooltip(tr('%s\n%s damage (%s%%): health %s, mana %s\n%d hits, %d critical, max %s', r.name, L.exact(r.total),
      tostring(r.pct), L.exact(r.hp), L.exact(r.mp), r.hits, r.crits, L.exact(r.max)))
    -- the bar is laid out after the row joins the list
    local bar, segs, frac = row.bar, L.segments(r), r.frac
    scheduleEvent(function() if alive(bar) then fillBar(bar, segs, frac) end end, 1)
  end
  window.emptyText:setText(current and tr('No hits were recorded before this death.') or tr('No death recorded yet.'))
  window.emptyText:setVisible(#rows == 0)

  window.timelineFrame.timeline:destroyChildren()
  for _, e in ipairs(L.timeline(current)) do
    local line = g_ui.createWidget('DeathTimelineLine', window.timelineFrame.timeline)
    line:setText(e.text)
    if e.time == 'death' then line:setColor('#e03a1e') end
  end
end

local function render()
  if not alive(window) then return end
  window.autoOpen:setChecked(settings.autoOpen)
  renderHistory()
  renderRecap()
  -- the element bar needs its laid-out width
  scheduleEvent(function()
    if alive(window) and current then
      fillBar(window.elementBar, DeathRecapLogic.segments({ total = tonumber(current.tot) or 0,
        elements = DeathRecapLogic.elements(current.el) }), 1)
    end
  end, 1)
end

-- ---------------------------------------------------------------- public
function show()
  if not alive(window) then return end
  window:show()
  window:raise()
  window:focus()
  render()
  send('open', { id = selected })
end

function hide()
  if alive(window) then window:hide() end
end

function toggle()
  if alive(window) and window:isVisible() then hide() else show() end
end

function setAutoOpen(on)
  settings.autoOpen = on and true or false
  saveSettings()
end

-- for other modules and checks
function getState()
  return { visible = alive(window) and window:isVisible() or false, history = #history, selected = selected,
    autoOpen = settings.autoOpen, killer = current and current.kb and current.kb.n or nil }
end

-- ---------------------------------------------------------------- protocol
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' or type(msg.data) ~= 'table' then return end
  local d = msg.data
  if msg.action == 'history' then
    history = type(d.list) == 'table' and d.list or {}
    selected = tonumber(d.sel)
    current = type(d.recap) == 'table' and d.recap or nil
    render()
  elseif msg.action == 'recap' then
    if type(d.recap) ~= 'table' then return end
    current = d.recap
    selected = tonumber(d.id)
    if d.auto then
      if not settings.autoOpen then return end
      if alive(window) and not window:isVisible() then
        window:show()
        window:raise()
      end
      -- the history around it
      send('open', { id = selected })
    end
    render()
  end
end

-- ---------------------------------------------------------------- lifecycle
local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if not api or not api.addEntry or handlers.menu then return end
  -- once per client run (a module reload keeps the entry the first load added)
  local ok, shown = pcall(api.available)
  for _, text in ipairs(ok and type(shown) == 'table' and shown.hunt or {}) do
    if text == 'Death Recap' then
      handlers.menu = true
      return
    end
  end
  handlers.menu = pcall(api.addEntry, 'hunt',
    { text = 'Death Recap', icon = 'battlelist', modules = { 'game_deathrecap' }, fns = { 'toggle' } })
end

local function onGameStart()
  history, selected, current = {}, nil, nil
  addMenu()
end

local function onGameEnd()
  hide()
  history, selected, current = {}, nil, nil
end

function init()
  loadSettings()
  local ok, ui = pcall(g_ui.displayUI, 'deathrecap')
  if ok and ui then
    window = ui
    window:hide()
    window.autoOpen.onCheckChange = function(_, checked) setAutoOpen(checked) end
  else
    g_logger.warning('[deathrecap] window not loaded: ' .. tostring(ui))
  end
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  connect(g_game, handlers.game)
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, safe('opcode', onMessage))
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  if handlers.game then disconnect(g_game, handlers.game) end
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if alive(window) then window:destroy() end
  window, history, selected, current = nil, {}, nil, nil
  handlers = {}
end
