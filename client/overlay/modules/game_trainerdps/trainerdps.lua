-- Trainer DPS panel (O573): a small movable panel that opens by itself when you hit a training monster and shows what you
-- deal to it: DPS now (the last 5 s), the average since the first hit, total, time, biggest hit, a bar per skill and per
-- element, the party members hitting the same trainer, the target profile; Reset, Copy and To chat. The session ends 10 s
-- after the last hit; the panel then shows the final result and hides after a while unless "Keep open" is on. The server
-- counts and attributes everything (server/data/scripts/chaos/trainer_meter.lua) and sends a summary once a second while
-- the session runs (JSON on extended opcode 147, joined by registerExtendedJSONOpcode):
--   server -> client  state {tn, tid, sid, act, end, empty, cur, avg, tot, hits, crits, max, mxn, dur, w, e, rows, el, prof,
--                     party?} | {none = 1}
--   client -> server  watch {on} | open | reset
-- The bar rows, mini buttons and number formats are the DPS meter's (game_dpsmeter). Settings (open by itself, keep open,
-- tab) are kept in g_settings node 'chaosTrainerDps'; the position by game_hudmove. Pure parts: trainerdpslogic.lua
-- (trainerdpslogic_test.lua). Menu: Hunt > DPS Meter > menu > Trainer DPS panel.

local OPCODE = 147
local NODE = 'chaosTrainerDps'

local panel
local settings = TrainerDpsLogic.sanitize(nil)
local state
local ctx = { visible = false, closeAt = nil, sid = nil }
local watching = false
local tabButtons, rowPool = {}, {}
local pollEvent
local refreshPanel

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function nowMs() return g_clock.millis() end

local function dm()
  if DpsMath then return DpsMath end
  return modules.game_dpsmeter and modules.game_dpsmeter.DpsMath
end

-- ---------------------------------------------------------------- settings, server
local function loadSettings()
  local ok, node = pcall(g_settings.getNode, NODE)
  settings = TrainerDpsLogic.sanitize(ok and node or nil)
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

-- the server sends summaries only to a client that asked: the panel is shown, or it opens by itself
local function updateWatching()
  local want = g_game.isOnline() and (settings.auto or (alive(panel) and panel:isVisible())) and true or false
  if want ~= watching then
    watching = want
    send('watch', { on = want })
  end
end

local function status(text)
  local tm = modules.game_textmessage
  if tm and tm.displayStatusMessage then tm.displayStatusMessage(text) end
end

-- ---------------------------------------------------------------- icons and rows
local function setIcon(row, kind, icon)
  local d = dm()
  local spec = d and d.iconSpec(kind, icon) or { kind = 'image', path = '/images/game/dpsmeter/other' }
  if spec.kind == 'item' then
    row.icon:setVisible(false)
    row.item:setItemId(spec.id)
    row.item:setVisible(true)
    return
  end
  row.item:setVisible(false)
  row.icon:setVisible(true)
  if spec.kind == 'spell' then
    if Spells and Spells.getSpellIcon then
      local ok, folder, clip = pcall(Spells.getSpellIcon, spec.words)
      if ok and folder then
        row.icon:setImageSource(folder)
        row.icon:setImageClip(clip)
        return
      end
    end
    row.icon:setImageSource(spec.fallback)
  else
    row.icon:setImageSource(spec.path)
  end
  row.icon:setImageClip('0 0 26 26')
end

local function rowAt(i)
  local row = rowPool[i]
  if not alive(row) then
    row = g_ui.createWidget('DpsBarRow', panel.rows)
    rowPool[i] = row
  end
  row:setVisible(true)
  return row
end

local function hideRowsFrom(i)
  for k = i, #rowPool do
    if alive(rowPool[k]) then rowPool[k]:setVisible(false) end
  end
end

local function setBar(row, frac, color)
  local width = math.max(1, panel.rows:getWidth() - 4 - 18)
  row.fill:setWidth(math.max(1, math.floor(width * math.max(0, math.min(1, frac)))))
  row.fill:setBackgroundColor(color)
end

local function setStat(stat, caption, value, tip)
  stat.caption:setText(caption)
  stat.value:setText(value)
  stat:setTooltip(tip or '')
end

-- ---------------------------------------------------------------- the panel
function refreshPanel()
  if not alive(panel) or not panel:isVisible() then return end
  local L = TrainerDpsLogic
  local d = dm()
  local st = L.stats(state)
  local hasParty = L.hasParty(state)
  if settings.tab == 'party' and not hasParty then settings.tab = 'src' end
  for key, b in pairs(tabButtons) do
    b:setOn(key == settings.tab)
    if key == 'party' then b:setVisible(hasParty) end
  end
  panel.header.liveDot:setVisible(state ~= nil and state.act == 1)
  panel.trainerName:setText(state and state.tn or '')
  setStat(panel.statCur, tr('DPS now'), st.cur, tr('%s damage per second over the last %d seconds', st.exactCur,
    math.floor(tonumber(state and state.w) or 5)))
  setStat(panel.statAvg, tr('Average'), st.avg, tr('%s damage per second since the first hit', st.exactAvg))
  setStat(panel.statTotal, tr('Total'), st.total, tr('%s damage in all', st.exactTotal))
  setStat(panel.statTime, tr('Time'), st.time, tr('From the first hit to the last one'))
  panel.bigLine:setText(tr('Biggest hit: %s', st.biggest))
  panel.bigLine:setTooltip(tr('%s damage', st.exactMax))
  panel.hitsLine:setText(st.hits)
  panel.profileLine:setText(L.profileText(state))
  panel.profileLine:setTooltip(tr('The trainer defends like a monster of this kind, so a number here means what it would against one'))
  panel.status:setText(L.status(state, L.secondsLeft(ctx.closeAt, nowMs())))
  panel.keepRow.keepBox:setChecked(settings.keep)
  panel.keepRow.autoBox:setChecked(settings.auto)
  local n = 0
  if settings.tab == 'el' then
    for i, r in ipairs(L.elementRows(state)) do
      local row = rowAt(i)
      row.item:setVisible(false)
      row.icon:setVisible(false)
      row.name:setText(r.name)
      row.name:setColor('#f2e8d0')
      row.value:setText(string.format('%s  %s%%', d and d.short(r.total) or tostring(r.total), tostring(r.pct)))
      row:setTooltip(tr('%s: %s damage, %s%%', r.name, d and d.exact(r.total) or tostring(r.total), tostring(r.pct)))
      setBar(row, r.frac, r.color)
      n = i
    end
  elseif settings.tab == 'party' then
    for i, r in ipairs(L.partyRows(state)) do
      local row = rowAt(i)
      setIcon(row, 'u', 'player')
      row.name:setText(r.name)
      row.name:setColor(r.me and '#f6cf72' or '#f2e8d0')
      row.value:setText(string.format('%s  %s/s', d and d.short(r.tot) or tostring(r.tot), d and d.short(r.cur) or tostring(r.cur)))
      row:setTooltip(tr('%s: %s damage, %s per second now, %s%% of the party', r.name,
        d and d.exact(r.tot) or tostring(r.tot), d and d.exact(r.cur) or tostring(r.cur), tostring(r.pct)))
      setBar(row, r.frac, r.me and '#a8843a' or '#5a4a6a')
      n = i
    end
  else
    for i, r in ipairs(L.skillRows(state)) do
      local row = rowAt(i)
      setIcon(row, r.kind, r.icon)
      row.name:setText(r.name)
      row.name:setColor('#f2e8d0')
      row.value:setText(string.format('%s  %s/s  %s%%', d and d.short(r.total) or tostring(r.total),
        d and d.short(r.rate) or tostring(r.rate), tostring(r.pct)))
      row:setTooltip(tr('%s\n%s in all, %s per second, %s%%\n%d hits, %d%% critical, average %s, max %s', r.name,
        d and d.exact(r.total) or tostring(r.total), d and d.exact(r.rate) or tostring(r.rate), tostring(r.pct), r.hits,
        r.critPct, d and d.exact(r.avg) or tostring(r.avg), d and d.exact(r.max) or tostring(r.max)))
      setBar(row, r.frac, r.color)
      n = i
    end
  end
  hideRowsFrom(n + 1)
  panel.emptyText:setText(state and not state.none and tr('Nothing counted yet.') or tr('No trainer hit yet.'))
  panel.emptyText:setVisible(n == 0)
end

local function stopPoll()
  if pollEvent then
    removeEvent(pollEvent)
    pollEvent = nil
  end
end

local function poll()
  if not alive(panel) or not panel:isVisible() then
    stopPoll()
    return
  end
  if TrainerDpsLogic.shouldClose(ctx.closeAt, settings, nowMs()) then
    hide()
    return
  end
  if ctx.closeAt then refreshPanel() end -- the seconds left
end

local function startPoll()
  if not pollEvent then pollEvent = cycleEvent(poll, 500) end
end

-- ---------------------------------------------------------------- protocol
local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' or msg.action ~= 'state' or type(msg.data) ~= 'table' or not alive(panel) then return end
  local data = msg.data
  ctx.visible = panel:isVisible()
  local r = TrainerDpsLogic.onState(ctx, data, settings, nowMs())
  state = (not data.none) and data or nil
  ctx.closeAt, ctx.sid = r.closeAt, r.sid
  if r.open and not ctx.visible then
    show()
    return
  end
  if r.closeAt then startPoll() end
  refreshPanel()
end

-- ---------------------------------------------------------------- public (menu, buttons)
function show()
  if not alive(panel) then return end
  panel:show()
  panel:raise()
  ctx.visible = true
  if ctx.closeAt then startPoll() end
  refreshPanel()
  updateWatching()
end

function hide()
  if not alive(panel) then return end
  panel:hide()
  ctx.visible = false
  ctx.closeAt = nil
  stopPoll()
  updateWatching()
end

function toggle()
  if alive(panel) and panel:isVisible() then hide() else show() end
end

function setKeep(on)
  on = on and true or false
  if settings.keep == on then return end
  settings.keep = on
  if on then ctx.closeAt = nil end
  saveSettings()
  refreshPanel()
end

function setAuto(on)
  on = on and true or false
  if settings.auto == on then return end
  settings.auto = on
  saveSettings()
  updateWatching()
  refreshPanel()
end

function setCloseAfter(seconds)
  settings.closeAfter = seconds
  saveSettings()
end

function resetMeter()
  send('reset')
end

function exportClipboard()
  local text = TrainerDpsLogic.summary(state)
  if text == '' then return end
  g_window.setClipboardText(text)
  status(tr('Trainer result copied to the clipboard.'))
end

-- one line into the chat input; the player decides whether to send it
function exportChat()
  local line = TrainerDpsLogic.chatLine(state, 240)
  if line == '' then return end
  local console = modules.game_console
  local edit = console and console.getConsole and console.getConsole()
  if edit then
    if console.enableChat then pcall(console.enableChat, true) end
    edit:setText(line)
    pcall(function() edit:setCursorPos(-1) end)
    pcall(function() edit:focus() end)
    status(tr('Trainer result put into the chat input.'))
  else
    g_window.setClipboardText(line)
    status(tr('Trainer result copied to the clipboard.'))
  end
end

function showMenu()
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addOption(tr('Copy the result'), function() exportClipboard() end)
  menu:addOption(tr('Result into the chat input'), function() exportChat() end)
  menu:addOption(tr('Reset the session'), function() resetMeter() end)
  menu:addSeparator()
  menu:addOption((settings.auto and '[x] ' or '[ ] ') .. tr('Open by itself'), function() setAuto(not settings.auto) end)
  menu:addOption((settings.keep and '[x] ' or '[ ] ') .. tr('Keep open'), function() setKeep(not settings.keep) end)
  for _, s in ipairs(TrainerDpsLogic.CLOSE_AFTER) do
    menu:addOption((settings.closeAfter == s and '[x] ' or '[ ] ') .. tr('Hide %d s after the session ends', s),
      function() setCloseAfter(s) end)
  end
  menu:addSeparator()
  menu:addOption(tr('Reset position'), function()
    if ChaosHudMove and ChaosHudMove.reset then ChaosHudMove.reset(panel) end
  end)
  menu:display(g_window.getMousePosition())
end

-- ---------------------------------------------------------------- lifecycle
local function buildTabs()
  panel.tabs:destroyChildren()
  tabButtons = {}
  for _, t in ipairs(TrainerDpsLogic.TABS) do
    local b = g_ui.createWidget('DpsTabButton', panel.tabs)
    b:setText(tr(t.name))
    b:setTooltip(tr(t.tip))
    local key = t.key
    b.onClick = function()
      settings.tab = key
      saveSettings()
      refreshPanel()
    end
    tabButtons[key] = b
  end
  tabButtons.party:setVisible(false)
end

local function onGameStart()
  state = nil
  ctx.closeAt, ctx.sid, ctx.visible = nil, nil, false
  watching = false
  if alive(panel) then panel:hide() end
  scheduleEvent(function() updateWatching() end, 500)
end

local function onGameEnd()
  watching = false
  state = nil
  stopPoll()
  if alive(panel) then panel:hide() end
end

function init()
  if not dm() then
    g_logger.warning('[trainerdps] the DPS meter module is missing: no panel')
    return
  end
  g_ui.importStyle('trainerdps')
  loadSettings()
  panel = g_ui.createWidget('TrainerDpsPanel', modules.game_interface.getRootPanel())
  panel:hide()
  -- movable, spot saved per character, double-click back (game_hudmove)
  if ChaosHudMove then
    ChaosHudMove.attach(panel, 'trainerDps', { otui = '/modules/game_trainerdps/trainerdps', style = 'TrainerDpsPanel' })
  end
  buildTabs()
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, onMessage)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  stopPoll()
  if watching then send('watch', { on = false }) end
  rowPool = {}
  if alive(panel) then
    if ChaosHudMove then ChaosHudMove.detach(panel) end
    panel:destroy()
  end
  panel, state = nil, nil
end
