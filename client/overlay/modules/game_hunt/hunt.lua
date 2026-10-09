-- Hunt tracker window: session time (pause / resume / reset), experience and exp/h, time to the next level, loot value
-- and loot/h, supplies used, profit and profit/h, damage dealt, healing, kills per monster, looted items and the Chaos
-- drops (orbs, uniques, items with a rarity). The server counts everything (server/data/scripts/chaos/hunt.lua) and
-- pushes it on extended opcode 241 (JSON {action, data}):
--   server -> client  state {open?, t, p, xp, xph, lvl, left, ttl, lv, lvh, sv, svh, pf, pfh, dmg, dps, heal, hps, kc,
--                     k = [[name, n]], l = [[clientId, n, gold, name, rarity, unique, orb]],
--                     s = [[clientId, n, gold, name]], x = [[clientId, n, name, rarity, unique, orb]]}
--   client -> server  open | close | get | pause | resume | reset
-- While the window is open the server sends a state every 2 s; the session clock ticks here in between.
-- The top menu (Hunt -> Hunt Tracker) calls toggle().
-- The base client's analyser (mods/game_analyser) is not used: its loot, supply, damage and kill panes are fed by
-- game-protocol messages this server's protocol never sends (see server/README.md "Hunt tracker").

local OPCODE = 241

local window
local state            -- last state received
local stateAt = 0      -- g_clock.seconds() when it arrived
local selected = 'loot'
local tabs = {}
local stats = {}
local tickEvent

local TABS = {
  { key = 'kills', name = 'Kills' },
  { key = 'loot', name = 'Loot' },
  { key = 'supplies', name = 'Supplies' },
  { key = 'drops', name = 'Chaos Drops' },
}

local STATS = {
  { key = 'xp', name = 'Experience' }, { key = 'xph', name = 'Exp/h' },
  { key = 'next', name = 'Next level' }, { key = 'kc', name = 'Kills' },
  { key = 'lv', name = 'Loot' }, { key = 'lvh', name = 'Loot/h' },
  { key = 'sv', name = 'Supplies' }, { key = 'svh', name = 'Supplies/h' },
  { key = 'pf', name = 'Profit' }, { key = 'pfh', name = 'Profit/h' },
  { key = 'dmg', name = 'Damage' }, { key = 'dps', name = 'Damage/s' },
  { key = 'heal', name = 'Healing' }, { key = 'hps', name = 'Healing/s' },
}

-- ---------------------------------------------------------------- helpers
local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function setStat(key, text, tooltip, color)
  local w = stats[key]
  if not w then return end
  w.value:setText(text)
  w.value:setTooltip(tooltip or '')
  w.value:setColor(color or HuntMath.TEXT_COLOR)
end

local function goldStat(key, n, color)
  setStat(key, HuntMath.short(n), HuntMath.exact(n) .. ' gold', color)
end

local function seconds()
  if not state then return 0 end
  return HuntMath.elapsed(state.t, state.p == 1, stateAt, g_clock.seconds())
end

-- ---------------------------------------------------------------- stats
local function updateClock()
  if not window or not state then return end
  window.sessionPanel.sessionTime:setText(HuntMath.duration(seconds()))
end

local function showStats()
  if not window or not state then return end
  local st = state
  updateClock()
  local paused = st.p == 1
  window.sessionPanel.statusLabel:setText(paused and tr('Paused') or tr('Running'))
  window.sessionPanel.statusLabel:setColor(paused and '#e03a1e' or '#7ccf5c')
  window.sessionPanel.pauseButton:setText(paused and tr('Resume') or tr('Pause'))
  window.sessionPanel.pauseButton:setTooltip(paused and tr('Count again from here.') or tr('Stop the clock and the counters.'))

  setStat('xp', HuntMath.short(st.xp), HuntMath.exact(st.xp) .. ' experience')
  setStat('xph', HuntMath.short(st.xph), HuntMath.exact(st.xph) .. ' experience per hour')
  setStat('next', HuntMath.nextLevel(st.ttl),
    tr('Level %d: %s experience to level %d at the current rate', tonumber(st.lvl) or 0, HuntMath.exact(st.left),
      (tonumber(st.lvl) or 0) + 1))
  setStat('kc', HuntMath.exact(st.kc), '')
  goldStat('lv', st.lv)
  goldStat('lvh', st.lvh)
  goldStat('sv', st.sv)
  goldStat('svh', st.svh)
  goldStat('pf', st.pf, HuntMath.profitColor(st.pf))
  goldStat('pfh', st.pfh, HuntMath.profitColor(st.pfh))
  setStat('dmg', HuntMath.short(st.dmg), HuntMath.exact(st.dmg) .. ' damage dealt')
  setStat('dps', HuntMath.exact(st.dps), tr('Average over the session'))
  setStat('heal', HuntMath.short(st.heal), HuntMath.exact(st.heal) .. ' health healed')
  setStat('hps', HuntMath.exact(st.hps), tr('Average over the session'))
end

-- ---------------------------------------------------------------- list
local function addRow(index, icon, label, color, countText, valueText, tooltip)
  local row = g_ui.createWidget('HuntRow', window.rowList)
  if icon and icon > 0 then
    row.icon:setItemId(icon)
    row.icon:setVisible(true)
  else
    row.icon:setVisible(false)
    row.icon:setWidth(0)
  end
  row.name:setText(label)
  row.name:setColor(color or HuntMath.TEXT_COLOR)
  row.count:setText(countText or '')
  row.value:setText(valueText or '')
  row.value:setTooltip(tooltip or '')
  if index % 2 == 0 then row:setBackgroundColor('#141014') end
  return row
end

local function showList()
  if not window then return end
  window.rowList:destroyChildren()
  local st = state or {}
  local n, total, empty = 0, '', ''
  if selected == 'kills' then
    for i, k in ipairs(HuntMath.killRows(st.k, st.kc)) do
      addRow(i, 0, k.name, nil, k.count .. 'x', k.percent .. '%', tr('%d%% of the kills', k.percent))
      n = n + 1
    end
    total = tr('Kills: %s', HuntMath.exact(st.kc))
    empty = tr('No kills yet.')
  elseif selected == 'loot' then
    for i, r in ipairs(HuntMath.lootRows(st.l)) do
      local label, color = HuntMath.itemLabel(r.name, r.rarity, r.unique, r.orb)
      addRow(i, r.id, label, color, r.count .. 'x', HuntMath.short(r.value), HuntMath.exact(r.value) .. ' gold')
      n = n + 1
    end
    total = tr('Loot value: %s gold', HuntMath.exact(st.lv))
    empty = tr('No loot yet. Only corpses you own are counted.')
  elseif selected == 'supplies' then
    for i, r in ipairs(HuntMath.supplyRows(st.s)) do
      addRow(i, r.id, HuntMath.itemLabel(r.name), nil, r.count .. 'x', HuntMath.short(r.value),
        HuntMath.exact(r.value) .. ' gold')
      n = n + 1
    end
    total = tr('Supplies used: %s gold', HuntMath.exact(st.sv))
    empty = tr('No potions, runes or ammunition used yet (not counted in protection zones).')
  else
    for i, r in ipairs(HuntMath.specialRows(st.x)) do
      local label, color = HuntMath.itemLabel(r.name, r.rarity, r.unique, r.orb)
      addRow(i, r.id, label, color, '', r.count .. 'x', '')
      n = n + 1
    end
    total = tr('Chaos drops: orbs, uniques and items with a rarity')
    empty = tr('No Chaos drops yet.')
  end
  window.totalLabel:setText(total)
  window.emptyText:setText(empty)
  window.emptyText:setVisible(n == 0)
end

local function selectTab(key)
  selected = key
  for k, tab in pairs(tabs) do tab:setChecked(k == key) end
  showList()
end

local function build()
  window.statsPanel:destroyChildren()
  stats = {}
  for _, s in ipairs(STATS) do
    local w = g_ui.createWidget('HuntStat', window.statsPanel)
    w.name:setText(tr(s.name))
    w.value:setText('-')
    stats[s.key] = w
  end
  window.tabs:destroyChildren()
  tabs = {}
  for _, t in ipairs(TABS) do
    local tab = g_ui.createWidget('HuntTab', window.tabs)
    tab:setText(tr(t.name))
    local key = t.key
    tab.onClick = function() selectTab(key) end
    tabs[key] = tab
  end
  selectTab(selected)
end

-- ---------------------------------------------------------------- protocol
local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[hunt] invalid JSON: ' .. tostring(msg))
    return
  end
  if msg.action ~= 'state' or type(msg.data) ~= 'table' then return end
  state = msg.data
  stateAt = g_clock.seconds()
  if not window then return end
  if state.open then show() end
  if window:isVisible() then
    showStats()
    showList()
  end
end

-- ---------------------------------------------------------------- window
local function tick()
  tickEvent = nil
  if not window or not window:isVisible() then return end
  updateClock()
  tickEvent = scheduleEvent(tick, 1000)
end

function show()
  if not window then return end
  local wasVisible = window:isVisible()
  window:show()
  window:raise()
  window:focus()
  if not wasVisible then
    showStats()
    showList()
  end
  if not tickEvent then tick() end
end

function hide()
  if window and window:isVisible() then
    window:hide()
    send('close')
  end
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
    return
  end
  send('open') -- the server answers with a state (open), which shows the window
end

function togglePause()
  if not state then return end
  send(state.p == 1 and 'resume' or 'pause')
end

function reset()
  if not window then return end
  local box
  local function yes()
    if box then box:destroy() box = nil end
    send('reset')
  end
  local function no()
    if box then box:destroy() box = nil end
  end
  if displayGeneralBox then
    box = displayGeneralBox(tr('Reset session'), tr('Start a new hunting session from zero?'),
      { { text = tr('Yes'), callback = yes }, { text = tr('No'), callback = no }, anchor = AnchorHorizontalCenter }, yes, no)
  else
    yes()
  end
end

function copySummary()
  if not state then return end
  g_window.setClipboardText(HuntMath.summary(state, seconds()))
  if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
    modules.game_textmessage.displayStatusMessage(tr('Hunt summary copied to the clipboard.'))
  end
end

local function onGameEnd()
  if window then window:hide() end
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  state = nil
end

function init()
  window = g_ui.displayUI('hunt')
  window:hide()
  build()
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  if window then
    window:destroy()
    window = nil
  end
  state, tabs, stats = nil, {}, {}
end
