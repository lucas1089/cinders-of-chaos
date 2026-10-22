-- Patch notes window: the weeks on the left, the selected week's notes on the right.
-- Server: server/data/scripts/chaos/patchnotes.lua, extended opcode 244 (JSON {action, data}). The notes live on the
-- server (data/patchnotes/*.md), so new notes need no client update.
--   server -> client  list {weeks = [{id, title, date, new}], selected, open, auto, autoEnabled, dailyFirst}
--                     note {id, title, date, part, parts, intro, sections = [{name, kind, cont, items = [{text, level,
--                           lead}]}]}   a long note comes in parts; PatchNotesView.join puts them back together
--                     changelog {available, server = {date}, published, entries = [{id, date, ts, pr, text, tags,
--                           client, pending}]}   the Changelog tab: every change that shipped (server
--                           changelog_core.lua, written at deploy time from the project history); a big answer comes in
--                           parts (Chaos.sendChunked), so this module listens with ProtocolGame.registerExtendedJSONOpcode
--   client -> server  open {id?} | get {id} | seen {id} | auto {enabled} | closed (window hidden) | changelog
-- Opened from the top menu (Social > Patch Notes, toggle()). At login the server sends `auto` once
-- per unseen week, in its turn in the server's login window queue (after the Daily Reward). The window also waits
-- by itself while the Daily Reward window (game_daily) is visible, or expected (PatchNotesView.autoStep), so the two
-- never stack; game_daily in turn waits while this window (id patchNotesWindow) is on screen. Drawing and that rule are in patchnotesview.lua (tested).

local OPCODE = 244
local V = PatchNotesView

local window
local weeks = {}            -- last week list
local entries = {}          -- id -> list widget
local notes = {}            -- id -> note (this session)
local selectedId
local shownId               -- note on screen
local seenSent = {}         -- id -> true once `seen` went out this session
local settingCheck = false  -- true while the checkbox is set from server data
local auto                  -- login auto-open state {dailyFirst, since, ...}
local autoEvent
local autoShownAt           -- clock when the window was opened by the auto-open (guard against a late daily window)
local AUTO_TICK_MS = 250
local AUTO_GUARD = 20       -- seconds after an auto-open during which a late Daily Reward window takes precedence

-- the Changelog tab
local tab = 'notes'         -- 'notes' | 'changelog'
local changelog             -- the last answer {server, published, entries}
local changelogAskedAt      -- clock of the last request (asked again after CHANGELOG_REFRESH seconds)
local changelogFilter = 'all'
local changelogSeenShown    -- the last look as it was when the tab was opened (the NEW marks stay while it is open)
local CHANGELOG_REFRESH = 300
local SEEN_KEY = 'chaos-changelog-seen' -- client setting: ts of the newest change at the last look
local NOTES_WIDGETS = { 'weeksLabel', 'weekFrame', 'weekList', 'weekScroll', 'noteFrame', 'noteArea', 'noteScroll',
  'autoCheck' }
local CHANGELOG_WIDGETS = { 'changelogInfo', 'filter_all', 'filter_server', 'filter_client', 'filter_content',
  'filter_website', 'changelogFrame', 'changelogList', 'changelogScroll' }

-- ---------------------------------------------------------------- helpers
local function now()
  return g_clock.millis() / 1000
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

-- the Daily Reward window of game_daily (a global of that sandboxed module), guarded
local function dailyVisible()
  local ok, visible = pcall(function()
    local m = modules and modules.game_daily
    local w = m and rawget(m, 'DailyWindow')
    return w and not w:isDestroyed() and w:isVisible() or false
  end)
  return ok and visible == true
end

-- a server modal dialog (the new-player welcome, a tutorial lesson) is on screen: the login auto-open waits for it
local function modalOpen()
  local ok, open = pcall(function()
    local md = modules and modules.game_modaldialog
    return md and rawget(md, 'modalDialog') ~= nil or false
  end)
  return ok and open == true
end

local function markSeen(id)
  if id and not seenSent[id] and window and window:isVisible() then
    seenSent[id] = true
    send('seen', { id = id })
    for _, w in ipairs(weeks) do
      if w.id == id then w.new = false end
    end
    local e = entries[id]
    if e then e.newBadge:setText('') end
  end
end

-- ---------------------------------------------------------------- note view
local STYLE_WIDGET = {
  title = 'PatchTitle', date = 'PatchDate', intro = 'PatchIntro', section = 'PatchSection', paragraph = 'PatchParagraph'
}

local function setText(label, b)
  local colored = V.colored(b)
  if colored and label.setColoredText then
    label:setColoredText(colored)
  else
    label:setText(V.plain(b))
    label:setColor(b.color or V.TEXT)
  end
end

local function renderNote(note)
  if not window then return end
  local area = window.noteArea
  area:destroyChildren()
  window.emptyText:setVisible(false)
  for _, b in ipairs(V.blocks(note)) do
    local widget
    if b.style == 'bullet' then
      widget = g_ui.createWidget(b.level == 2 and 'PatchSubBullet' or 'PatchBullet', area)
      widget.dot:setBackgroundColor(b.bulletColor or V.DIM)
      if b.level == 2 then
        widget.dot:setMarginLeft(21)
        widget.dot:setWidth(4)
        widget.dot:setHeight(4)
        widget.text:setMarginLeft(32)
      end
      setText(widget.text, b)
      -- the row follows its wrapped text (the label resizes itself once the layout gives it a width)
      local row = widget
      widget.text.onGeometryChange = function(label)
        local h = math.max(14, label:getHeight())
        if row:getHeight() ~= h then row:setHeight(h) end
      end
    else
      widget = g_ui.createWidget(STYLE_WIDGET[b.style] or 'PatchParagraph', area)
      if b.style == 'section' then
        widget:setText(b.text)
        widget:setColor(b.color)
      else
        setText(widget, b)
      end
    end
  end
  shownId = note.id
  if window.noteScroll then window.noteScroll:setValue(0) end
  markSeen(note.id)
end

local function showEmpty(text)
  if not window then return end
  window.noteArea:destroyChildren()
  window.emptyText:setText(text)
  window.emptyText:setVisible(tab == 'notes')
  shownId = nil
end

local function select(id)
  selectedId = id
  for key, e in pairs(entries) do e:setChecked(key == id) end
  if not id then
    showEmpty(tr('No patch notes yet.'))
    return
  end
  if notes[id] then
    renderNote(notes[id])
  else
    showEmpty(tr('Loading...'))
    send('get', { id = id })
  end
end

local function buildList()
  if not window then return end
  window.weekList:destroyChildren()
  entries = {}
  for _, w in ipairs(weeks) do
    local e = g_ui.createWidget('PatchWeekEntry', window.weekList)
    local t = V.weekText(w)
    e.date:setText(t.date)
    e.title:setText(t.title)
    e.newBadge:setText(t.new and tr('NEW') or '')
    e:setTooltip(t.title)
    local id = w.id
    e.onClick = function() select(id) end
    entries[id] = e
  end
end

-- ---------------------------------------------------------------- changelog
local function seenTs()
  local ok, v = pcall(g_settings.getNumber, SEEN_KEY)
  return ok and tonumber(v) or 0
end

local function saveSeen(ts)
  if ts and ts > seenTs() then pcall(g_settings.set, SEEN_KEY, ts) end
end

-- this client's update version and build (the signed updater's state, init.lua's Services.update)
local function clientInfo()
  local ok, status = pcall(function()
    local U = ChaosUpdater
    return U and U.status and U.status() or nil
  end)
  local okU, update = pcall(function() return Services and Services.update end)
  return V.clientInfo(ok and status or nil, okU and update or nil)
end

local function changelogTabText()
  if not window then return end
  local n = changelog and tab ~= 'changelog' and V.newCount(changelog.entries, seenTs()) or 0
  window.tabChangelog:setText(n > 0 and tr('Changelog (%d new)', n) or tr('Changelog'))
end

local function askChangelog()
  if changelogAskedAt and now() - changelogAskedAt < CHANGELOG_REFRESH then return end
  changelogAskedAt = now()
  send('changelog')
end

local function renderChangelog()
  if not window or tab ~= 'changelog' then return end
  local list = window.changelogList
  list:destroyChildren()
  window.changelogInfo:setText(V.infoText(changelog and changelog.server and changelog.server.date, clientInfo()))
  for _, f in ipairs(V.FILTERS) do
    local b = window['filter_' .. f]
    if b then b:setChecked(f == changelogFilter) end
  end
  if not changelog then
    window.changelogEmpty:setText(tr('Loading...'))
    window.changelogEmpty:setVisible(true)
    return
  end
  local rows, shown = V.changelogRows(changelog.entries, changelogFilter, changelogSeenShown or 0)
  for _, r in ipairs(rows) do
    if r.kind == 'date' then
      local w = g_ui.createWidget('ChangelogDate', list)
      w:setText(r.text)
    else
      local w = g_ui.createWidget('ChangelogEntry', list)
      w.dot:setBackgroundColor(r.color)
      if w.text.setColoredText then w.text:setColoredText(r.parts) else w.text:setText(r.plain) end
      local row = w
      w.text.onGeometryChange = function(label)
        local h = math.max(14, label:getHeight())
        if row:getHeight() ~= h then row:setHeight(h) end
      end
    end
  end
  local empty = #(changelog.entries or {}) == 0 and tr('No changes listed yet.')
    or (shown == 0 and tr('No changes with this tag.')) or nil
  window.changelogEmpty:setText(empty or '')
  window.changelogEmpty:setVisible(empty ~= nil)
  if window.changelogScroll then window.changelogScroll:setValue(0) end
  if window:isVisible() then saveSeen(V.newestTs(changelog.entries)) end
end

function setFilter(f)
  for _, known in ipairs(V.FILTERS) do
    if known == f then
      changelogFilter = f
      renderChangelog()
      return
    end
  end
end

function setTab(name)
  if not window then return end
  tab = name == 'changelog' and 'changelog' or 'notes'
  for _, id in ipairs(NOTES_WIDGETS) do
    local w = window[id]
    if w then w:setVisible(tab == 'notes') end
  end
  for _, id in ipairs(CHANGELOG_WIDGETS) do
    local w = window[id]
    if w then w:setVisible(tab == 'changelog') end
  end
  window.emptyText:setVisible(tab == 'notes' and shownId == nil and window.emptyText:getText() ~= '')
  window.changelogEmpty:setVisible(false)
  window.tabNotes:setChecked(tab == 'notes')
  window.tabChangelog:setChecked(tab == 'changelog')
  if tab == 'changelog' then
    changelogSeenShown = seenTs()
    askChangelog()
    renderChangelog()
  end
  changelogTabText()
end

local function onChangelog(data)
  local entries = {}
  for _, e in ipairs(type(data.entries) == 'table' and data.entries or {}) do
    if type(e) == 'table' then entries[#entries + 1] = e end
  end
  changelog = { server = type(data.server) == 'table' and data.server or {}, entries = entries }
  if tab == 'changelog' then renderChangelog() end
  changelogTabText()
end

-- ---------------------------------------------------------------- window
function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  if shownId then markSeen(shownId) end
  if tab == 'changelog' then
    changelogSeenShown = seenTs()
    renderChangelog()
  end
end

-- `closed` lets the server's login window queue (server daily.lua, ChaosLoginWindows) open the next window
local function hideAndReport()
  if window and window:isVisible() then
    window:hide()
    send('closed')
  end
end

function hide()
  hideAndReport()
  autoShownAt = nil
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
    return
  end
  auto = nil -- opened by hand: the login auto-open is done
  send('open', { id = selectedId }) -- the server answers with the list (open) and the note
end

-- ---------------------------------------------------------------- login auto-open
local function stopAuto()
  if autoEvent then removeEvent(autoEvent) autoEvent = nil end
end

local function autoTick()
  autoEvent = nil
  if not window or not g_game.isOnline() then return end
  if auto then
    if modalOpen() then
      -- try again on the next tick
    elseif V.autoStep(auto, dailyVisible(), now()) == 'show' then
      auto = nil
      show()
      autoShownAt = now()
    end
  elseif autoShownAt then
    -- a Daily Reward window that showed up late goes first: step aside and come back once it is closed
    if now() - autoShownAt > AUTO_GUARD or not window:isVisible() then
      autoShownAt = nil
      return
    end
    if dailyVisible() then
      hideAndReport()
      autoShownAt = nil
      auto = { dailyFirst = true, since = now(), sawDaily = true }
    end
  else
    return
  end
  autoEvent = scheduleEvent(autoTick, AUTO_TICK_MS)
end

local function startAuto(dailyFirst)
  if window:isVisible() then return end -- already open (menu or command)
  auto = { dailyFirst = dailyFirst == true, since = now() }
  stopAuto()
  autoTick()
end

-- ---------------------------------------------------------------- protocol
local function onList(data)
  weeks = {}
  for _, w in ipairs(type(data.weeks) == 'table' and data.weeks or {}) do
    if type(w) == 'table' and type(w.id) == 'string' then weeks[#weeks + 1] = w end
  end
  buildList()
  settingCheck = true
  window.autoCheck:setChecked(data.autoEnabled == false)
  settingCheck = false
  local id = type(data.selected) == 'string' and data.selected ~= '' and data.selected or (weeks[1] and weeks[1].id)
  if id and not entries[id] then id = weeks[1] and weeks[1].id end
  -- the note itself follows as its own message; keep a cached copy on screen until then
  selectedId = id
  for key, e in pairs(entries) do e:setChecked(key == id) end
  if id and notes[id] then renderNote(notes[id]) elseif not id then showEmpty(tr('No patch notes yet.')) end
  if data.open then
    auto = nil
    stopAuto()
    show()
    askChangelog() -- the tab shows how many changes are new
  elseif data.auto then
    startAuto(data.dailyFirst)
  end
end

local partial = {}           -- id -> {parts = {[i] = data}, got = n} while a note arrives in parts

local function onNote(data)
  if type(data.id) ~= 'string' then return end
  local total = math.max(1, math.min(50, tonumber(data.parts) or 1))
  local index = tonumber(data.part) or 1
  local p = partial[data.id]
  if not p or p.total ~= total then
    p = { total = total, got = 0, parts = {} }
    partial[data.id] = p
  end
  if not p.parts[index] then p.got = p.got + 1 end
  p.parts[index] = data
  if p.got < total then return end
  partial[data.id] = nil
  local note = V.join(p.parts, total)
  if not note then return end
  notes[data.id] = note
  if data.id == selectedId then renderNote(note) end
end

-- msg: decoded by ProtocolGame (registerExtendedJSONOpcode, which also joins chunked answers)
local function onExtendedOpcode(protocol, opcode, msg)
  if type(msg) ~= 'table' or not window then return end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'list' then
    onList(data)
  elseif msg.action == 'note' then
    onNote(data)
  elseif msg.action == 'changelog' then
    onChangelog(data)
  end
end

local function onGameEnd()
  stopAuto()
  hide()
  auto, autoShownAt = nil, nil
  weeks, entries, notes, seenSent, partial = {}, {}, {}, {}, {}
  selectedId, shownId = nil, nil
  changelog, changelogAskedAt, changelogSeenShown = nil, nil, nil
  if window then
    window.weekList:destroyChildren()
    window.noteArea:destroyChildren()
    window.changelogList:destroyChildren()
    setTab('notes')
  end
end

function init()
  window = g_ui.displayUI('patchnotes')
  window:hide()
  window.autoCheck.onCheckChange = function(widget, checked)
    if not settingCheck then send('auto', { enabled = not checked }) end
  end
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
  setTab('notes')
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  stopAuto()
  if window then
    window:destroy()
    window = nil
  end
end
