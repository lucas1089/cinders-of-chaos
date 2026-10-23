-- The Chronicle window: the Ashen Chronicle of the running season (its chapters, each with the story, the goal bars,
-- your part and the top contributors, and what the world changed), the record of past seasons, and the Capital
-- Memorial (your "Show me on the Memorial" choice and what it remembers this season).
-- Server: server/data/scripts/chaos/chronicle.lua and memorial.lua, extended opcode 171 (JSON {action, data}; the
-- state goes out with Chaos.sendChunked and is joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | close (chronicle.lua) | mem | memset {records, fallen} (memorial.lua)
--   server -> client  state {...} | mem {...} (chronicleview.lua has both shapes)
-- A Hardcore fall asks the Memorial question with the server's modal window; the Memorial tab answers it too.
-- Menu: Adventure > Chronicle (added with ChaosTopBar.addEntry). The story comes in English and Portuguese; the window
-- shows the client's language.

local OPCODE = 171
local V = ChronicleView

local window
local data -- the chronicle state
local mem -- the memorial state
local tab = 'chapters'
local selected = { chapters = nil, record = 1, memorial = 'choice' }
local handlers = {}
local reported = {}
local msgEvent

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[chronicle] ' .. name .. ': ' .. tostring(res))
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

-- the client's language: client_chaos_locale (ChaosLocale.get(): 'pt-BR' | 'en'), else the stock locales module, else English
local function lang()
  local code
  local m = modules.client_chaos_locale
  local api = m and (type(m.ChaosLocale) == 'table' and m.ChaosLocale or m)
  if api and type(api.get) == 'function' then
    local ok, v = pcall(api.get)
    if ok and type(v) == 'string' then code = v end
  end
  if not code and modules.client_locales and modules.client_locales.getCurrentLocale then
    local ok, l = pcall(modules.client_locales.getCurrentLocale)
    if ok and type(l) == 'table' then code = l.name end
  end
  return V.lang(code)
end

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

-- ---------------------------------------------------------------- page helpers
local function clearPage(title, sub)
  window.page:destroyChildren()
  window.pageTitle:setText(title or '')
  window.pageSub:setText(sub or '')
  window.pageScroll:setValue(0)
end

local function heading(text)
  local w = g_ui.createWidget('ChronicleHeading', window.page)
  w:setText(text)
  return w
end

local function paragraph(text, style)
  local w = g_ui.createWidget(style or 'ChronicleParagraph', window.page)
  w:setText(text)
  return w
end

local function topList(rows, empty)
  if #rows == 0 then
    paragraph(empty, 'ChronicleNote')
    return
  end
  for _, r in ipairs(rows) do
    local row = g_ui.createWidget('ChronicleTopRow', window.page)
    row.place:setText(r.place .. '.')
    row.name:setText(r.name)
    row.value:setText(r.text)
  end
end

local function listRow(name, sub, color, onClick, isSelected)
  local row = g_ui.createWidget('ChronicleListRow', window.entryList)
  row.name:setText(name)
  row.sub:setText(sub)
  if color then row.sub:setColor(color) end
  if isSelected then
    row:setImageSource('/images/chaos/panel_highlight')
    row:setImageBorder(8)
  end
  row.onClick = onClick
  return row
end

-- ---------------------------------------------------------------- chapters
local function showChapter(i)
  local l = lang()
  local ch = V.chapters(data)[i]
  if type(ch) ~= 'table' then
    clearPage(tr('Nothing to show'), '')
    return
  end
  local line, color = V.chapterLine(ch)
  clearPage(tostring(V.pick(ch.title, l) or ''), line)
  window.pageSub:setColor(color)
  if ch.state == 'locked' then
    paragraph(tr('This page is still blank. The chapters before it must be written first.'), 'ChronicleNote')
  else
    for _, p in ipairs(V.paragraphs(ch.text, l)) do paragraph(p) end
  end
  heading(tr('Goals of the realm'))
  for _, g in ipairs(type(ch.goals) == 'table' and ch.goals or {}) do
    if type(g) == 'table' then
      local w = g_ui.createWidget('ChronicleGoal', window.page)
      w.label:setText(V.goalLabel(g, l))
      w.bar:setPercent(V.goalPercent(g))
      w.bar:setText(V.goalText(g))
      w.bar:setBackgroundColor(V.goalPercent(g) >= 100 and V.COLORS.barDone or V.COLORS.bar)
    end
  end
  if ch.state ~= 'locked' then
    paragraph(tr('Your part in this chapter: %s points.', V.fmt(ch.mine)), 'ChronicleNote')
  end
  if ch.state == 'done' then
    heading(tr('What changed'))
    paragraph(tostring(V.pick(ch.world, l) or ''))
    local pending = V.pendingText(ch)
    if pending then paragraph(pending, 'ChronicleNote') end
  end
  heading(tr('Who carried it'))
  topList(V.topRows(ch.top), tr('Nobody yet. The realm writes this chapter together.'))
end

local function renderChapters()
  local l = lang()
  window.entryList:destroyChildren()
  if not data or not data.active then
    window.headLabel:setText(tr('No Chronicle is being written now. It begins with the next season.'))
    clearPage(tr('The Ashen Chronicle'), '')
    paragraph(tr('Each season the whole realm writes a story together: world bosses, rifts, Omens, the Sepulchre and new heroes fill its chapters, and every written chapter changes the world.'))
    return
  end
  window.headLabel:setText(string.format('%s  -  %s', tostring(V.pick(data.title, l) or ''), tostring(data.season or '')))
  if not selected.chapters or not V.chapters(data)[selected.chapters] then
    selected.chapters = V.defaultChapter(data)
  end
  for i, ch in ipairs(V.chapters(data)) do
    if type(ch) == 'table' then
      local line, color = V.chapterLine(ch)
      listRow(tostring(V.pick(ch.title, l) or ''), line, color, function()
        selected.chapters = i
        renderChapters()
      end, i == selected.chapters)
    end
  end
  if selected.chapters then showChapter(selected.chapters) end
  if data.ending then
    heading(tr('The end of the book'))
    paragraph(tostring(V.pick(data.ending, l) or ''))
  end
end

-- ---------------------------------------------------------------- the record
local function renderRecord()
  local l = lang()
  window.entryList:destroyChildren()
  window.headLabel:setText(tr('Who carried each chapter of the past seasons'))
  local seasons = V.recordSeasons(data)
  if #seasons == 0 then
    clearPage(tr('The record'), '')
    paragraph(tr('No season has been closed yet. When one ends, the Chronicler writes down who carried each chapter.'), 'ChronicleNote')
    return
  end
  if not seasons[selected.record] then selected.record = 1 end
  for i, s in ipairs(seasons) do
    listRow(V.seasonTitle(s, l), tr('%d chapters recorded', #(type(s.chapters) == 'table' and s.chapters or {})), nil, function()
      selected.record = i
      renderRecord()
    end, i == selected.record)
  end
  local s = seasons[selected.record]
  clearPage(V.seasonTitle(s, l), '')
  for _, c in ipairs(type(s.chapters) == 'table' and s.chapters or {}) do
    if type(c) == 'table' then
      heading(tostring(V.pick(c.title, l) or ''))
      topList(V.topRows(c.top), tr('Nobody recorded.'))
    end
  end
end

-- ---------------------------------------------------------------- the Memorial
local function memorialChoicePage()
  local m = type(mem) == 'table' and mem or {}
  clearPage(tr('Show me on the Memorial'), tostring(m.season or ''))
  paragraph(tr('The Ember Memorial in the capital keeps the realm firsts, the season records and the fallen of Hardcore. It shows your name only if you want it to; you can change your mind at any time.'))
  local records = g_ui.createWidget('ChronicleCheck', window.page)
  records:setText(tr('Show my records and realm firsts'))
  records:setChecked(m.records == true)
  local fallen = g_ui.createWidget('ChronicleCheck', window.page)
  fallen:setText(tr('Show my Hardcore fall (name, level, class, cause and date)'))
  fallen:setChecked(m.fallen == true)
  if m.ask then
    paragraph(tr('Your character fell in Hardcore. Should the Memorial remember it? Tick the box above and save, or save it unticked.'), 'ChronicleNote')
  end
  local save = g_ui.createWidget('ChronicleSave', window.page)
  save:setText(tr('Save'))
  save.onClick = function()
    send('memset', V.choiceRequest(records:isChecked(), fallen:isChecked()))
    showMessage(tr('Saving your choice...'), true)
  end
  paragraph(tr('Records and realm firsts are shown unless you turn them off; a fall is shown only after your yes.'), 'ChronicleNote')
end

local function memorialRows(rows, empty)
  if #rows == 0 then
    paragraph(empty, 'ChronicleNote')
    return
  end
  for _, r in ipairs(rows) do
    heading(r.title)
    paragraph(r.text .. (r.when ~= '' and ('  (' .. r.when .. ')') or ''))
  end
end

local function renderMemorial()
  window.entryList:destroyChildren()
  local m = type(mem) == 'table' and mem or {}
  window.headLabel:setText(tr('The Ember Memorial, %s', tostring(m.season or '')))
  for _, s in ipairs(V.memorialSections(m)) do
    listRow(s.name, s.sub, nil, function()
      selected.memorial = s.id
      renderMemorial()
    end, s.id == selected.memorial)
  end
  if selected.memorial == 'firsts' then
    clearPage(tr('Realm firsts'), tostring(m.season or ''))
    memorialRows(V.memorialFirsts(m), tr('No realm first this season yet.'))
  elseif selected.memorial == 'records' then
    clearPage(tr('Records'), tostring(m.season or ''))
    memorialRows(V.memorialRecords(m), tr('No record this season yet.'))
  elseif selected.memorial == 'falls' then
    clearPage(tr('The fallen'), tostring(m.season or ''))
    memorialRows(V.memorialFalls(m), tr('Nobody is remembered here this season.'))
  else
    memorialChoicePage()
  end
end

-- ---------------------------------------------------------------- the window
function render()
  if not window or not window:isVisible() then return end
  window.tabBar.tabChapters:setChecked(tab == 'chapters')
  window.tabBar.tabRecord:setChecked(tab == 'record')
  window.tabBar.tabMemorial:setChecked(tab == 'memorial')
  if tab == 'record' then
    renderRecord()
  elseif tab == 'memorial' then
    renderMemorial()
  else
    renderChapters()
  end
end

function showTab(name)
  if name ~= 'chapters' and name ~= 'record' and name ~= 'memorial' then return end
  tab = name
  if name == 'memorial' then send('mem') end
  render()
end

local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local d = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    data = d
    render()
  elseif msg.action == 'mem' then
    mem = d
    if tab == 'memorial' then render() end
  end
end

function hide()
  if window and window:isVisible() then
    window:hide()
    send('close')
  end
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  send('open')
  send('mem')
  render()
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

-- for other modules and tests: load a payload as if the server had sent it
function setData(d, m)
  data = d
  mem = m
  render()
end

function getState()
  return { visible = window and window:isVisible() or false, tab = tab,
    chapters = data and #V.chapters(data) or 0, memorial = mem ~= nil }
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'adventure',
      { text = 'Chronicle', icon = 'quests', modules = { 'game_chronicle' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  data, mem = nil, nil
  addMenu()
end

local function onGameEnd()
  if window then window:hide() end
  data, mem = nil, nil
end

function init()
  local ok, ui = pcall(g_ui.displayUI, 'chronicle')
  if ok and ui then
    window = ui
    window:hide()
  else
    g_logger.warning('[chronicle] window not loaded: ' .. tostring(ui))
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
  if window then
    window:destroy()
    window = nil
  end
end
