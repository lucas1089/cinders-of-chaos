-- Mentor window (server data/scripts/chaos/mentor.lua, extended opcode 194, JSON {action, data}; the server sends
-- through Chaos.sendChunked, joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | sync | list {line, lang, online} | register {lang, hours, note, accepting, public} |
--                     retire | choose {guid} | invite {name} | accept {guid} | decline {guid} | dismiss |
--                     release {guid} | seek {on} | buy {key}
--   server -> client  status {...} (open = true: show the window) | mentors {rows, filter} | message {text, error}
-- Menu: Social > Mentors. The server decides everything; the texts are in mentorview.lua.

local OPCODE = 194
local V = MentorView

local window
local status
local mentorRows
local page = 'find'
local tabs = {}
local handlers = {}
local reported = {}
local filling = false

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[mentor] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function note(text, color)
  if window then
    window.note:setText(text or '')
    window.note:setColor(color or V.COLORS.dim)
  end
end

local function plate(widget, text)
  if widget and widget.label then widget.label:setText(text) end
end

-- ------------------------------------------------------------ pages
local function fillFind()
  local p = window.findPage
  p.pickText:setText(V.pickText(status))
  filling = true
  p.seekCheck:setChecked(status and status.seeking or false)
  p.seekCheck:setEnabled(status ~= nil and status.canPick == true and not status.apprentice)
  if p.lineCombo:getOptionsCount() <= 1 and status then
    p.lineCombo:clearOptions()
    for _, o in ipairs(V.lineOptions(status)) do p.lineCombo:addOption(o[2], o[1]) end
    p.lineCombo:setCurrentIndex(1)
  end
  filling = false
  local inv = p.invites
  inv:destroyChildren()
  local invites = V.inviteRows(status)
  for _, r in ipairs(invites) do
    local w = g_ui.createWidget('MentorInviteRow', inv)
    w.text:setText(r.text)
    if r.kind == 'referrer' then
      w.accept:setText(tr('Choose'))
      w.accept.onClick = function() send('choose', { guid = r.guid }) end
      w.decline:hide()
    else
      w.accept.onClick = function() send('accept', { guid = r.guid }) end
      w.decline.onClick = function() send('decline', { guid = r.guid }) end
    end
  end
  inv:setHeight(#invites * 33)
  local list = p.mentorList
  list:destroyChildren()
  p.listEmpty:setText(V.emptyList(mentorRows))
  for _, r in ipairs(V.mentorRows(mentorRows, status)) do
    local w = g_ui.createWidget('MentorRow', list)
    w.title:setText(r.title)
    w.sub:setText(r.sub)
    w.noteText:setText(r.note)
    w.status:setText(r.status)
    w.status:setColor(r.statusColor)
    w.choose:setEnabled(r.canChoose)
    w.choose.onClick = function() send('choose', { guid = r.guid }) end
  end
end

local function fillMine()
  local p = window.minePage
  local title, sub = V.mineHeader(status)
  p.header.mentorName:setText(title)
  p.header.mentorSub:setText(sub)
  local text, color = V.bonusLine(status)
  p.header.bonus:setText(text)
  p.header.bonus:setColor(color)
  p.header.dismissButton:setVisible(status ~= nil and status.apprentice ~= nil)
  plate(p.milestonesPlate, tr('Milestones (your mentor earns Mentor Marks)'))
  local list = p.milestoneList
  list:destroyChildren()
  for _, r in ipairs(V.milestoneRows(status and status.apprentice and status.apprentice.milestones or {})) do
    local w = g_ui.createWidget('MentorMilestoneRow', list)
    w.name:setText(r.text)
    w.state:setText(r.state)
    w.state:setColor(r.color)
    w.marks:setText(r.marks)
  end
  local rules = status and status.rules or {}
  p.mineRules:setText(tr('Graduation at level %d: %s for you, %d Mentor Marks for your mentor (after %d minutes ' ..
    'hunting together). Dismissing your mentor ends the link.', tonumber(rules.gradLevel) or 0, tostring(rules.gradReward or ''),
    tonumber(rules.gradMarks) or 0, tonumber(rules.gradShared) or 0))
end

local function fillMentoring()
  local p = window.mentoringPage
  local m = status and status.mentor
  p.requirements:setText(V.requirementsText(status))
  p.card.saveButton:setText(m and tr('Save card') or tr('Become a mentor'))
  p.card.saveButton:setEnabled(m ~= nil or (status ~= nil and status.canMentor == true))
  p.card.retireButton:setVisible(m ~= nil)
  if m and not p.card.lang:isFocused() then
    p.card.lang:setText(m.lang or '')
    p.card.hours:setText(m.hours or '')
    p.card.cardNote:setText(m.note or '')
    p.card.accepting:setChecked(m.accepting == true)
    p.card.public:setChecked(m.public == true)
  elseif not m then
    p.card.accepting:setChecked(true)
    p.card.public:setChecked(true)
  end
  p.stats:setText(V.mentorStats(status))
  p.inviteEdit:setEnabled(m ~= nil)
  p.inviteButton:setEnabled(m ~= nil)
  plate(p.apprenticesPlate, V.apprenticesHeader(status))
  local rows = V.apprenticeRows(status)
  p.apprenticesEmpty:setText(m and #rows == 0 and tr('No apprentices yet: invite one or wait to be chosen.') or '')
  local list = p.apprenticeList
  list:destroyChildren()
  for _, r in ipairs(rows) do
    local w = g_ui.createWidget('MentorApprenticeRow', list)
    w.title:setText(r.title)
    w.sub:setText(r.sub)
    for _, st in ipairs(r.steps) do
      local l = g_ui.createWidget('MentorStep', w.steps)
      l:setText(st.text)
      l:setColor(st.color)
      l:setTooltip(st.tip)
    end
    w.release.onClick = function() send('release', { guid = r.guid }) end
  end
end

local function fillShop()
  local p = window.shopPage
  p.shopHeader:setText(V.shopHeader(status))
  local list = p.shopList
  list:destroyChildren()
  for _, r in ipairs(V.shopRows(status)) do
    local w = g_ui.createWidget('MentorShopRow', list)
    w.name:setText(r.name)
    w.name:setColor(r.color)
    w.desc:setText(r.desc)
    w.price:setText(r.price)
    w.buy:setText(r.button)
    w.buy:setEnabled(r.buyable)
    w.buy.onClick = function() send('buy', { key = r.key }) end
  end
end

local function fillTop()
  local p = window.topPage
  plate(p.topPlate, tr('Top mentors by graduates'))
  local rows = V.topRows(status)
  p.topEmpty:setText(#rows == 0 and tr('Nobody has graduated an apprentice yet.') or '')
  local list = p.topList
  list:destroyChildren()
  for _, r in ipairs(rows) do
    local w = g_ui.createWidget('MentorTopRow', list)
    w.rank:setText(r.rank)
    w.name:setText(r.name)
    w.value:setText(r.value)
  end
end

local FILL = { find = fillFind, mine = fillMine, mentoring = fillMentoring, shop = fillShop, top = fillTop }

local function refresh()
  if not window then return end
  for key, tab in pairs(tabs) do tab:setChecked(key == page) end
  for key in pairs(FILL) do
    local w = window[key .. 'Page']
    if w then w:setVisible(key == page) end
  end
  local fn = FILL[page]
  if fn then fn() end
end

function showPage(name)
  if not FILL[name] then return end
  page = name
  refresh()
  if name == 'find' and mentorRows == nil and status then search() end
end

-- ------------------------------------------------------------ actions
function search()
  if not window then return end
  local p = window.findPage
  local line = p.lineCombo:getCurrentOption() and p.lineCombo:getCurrentOption().data or ''
  local online = p.onlineCombo:getCurrentOption() and p.onlineCombo:getCurrentOption().data or 'any'
  send('list', V.filter(line, p.langEdit:getText(), online))
end

function saveCard()
  local c = window and window.mentoringPage.card
  if not c then return end
  send('register', { lang = c.lang:getText(), hours = c.hours:getText(), note = c.cardNote:getText(),
    accepting = c.accepting:isChecked(), public = c.public:isChecked() })
end

function retire() send('retire') end
function dismiss() send('dismiss') end

function invite()
  local e = window and window.mentoringPage.inviteEdit
  if not e or e:getText() == '' then
    note(tr('Type the character name first.'), V.COLORS.bad)
    return
  end
  send('invite', { name = e:getText() })
end

-- ------------------------------------------------------------ protocol
local function onMessage(protocol, opcode, msg)
  if type(msg) == 'string' then
    local ok, decoded = pcall(json.decode, msg)
    msg = ok and decoded or nil
  end
  if type(msg) ~= 'table' or type(msg.data) ~= 'table' then return end
  local d = msg.data
  if msg.action == 'status' then
    local first = status == nil
    status = d
    if d.open and window then
      if first or not window:isVisible() then page = V.firstTab(d) end
      note('')
      refresh()
      window:show()
      window:raise()
      window:focus()
      if page == 'find' then search() end
    else
      refresh()
    end
  elseif msg.action == 'mentors' then
    mentorRows = d.rows or {}
    if page == 'find' then refresh() end
  elseif msg.action == 'message' then
    note(d.text or '', d.error and V.COLORS.bad or V.COLORS.good)
  end
end

function show() send('open') end

function hide()
  if window then window:hide() end
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

-- for other modules and tests
function getState()
  return { status = status, rows = mentorRows, page = page, visible = window and window:isVisible() or false }
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'social',
      { text = 'Mentors', icon = 'vip', modules = { 'game_mentor' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  status, mentorRows = nil, nil
  addMenu()
end

local function onGameEnd()
  hide()
  status, mentorRows = nil, nil
end

local function buildTabs()
  for _, t in ipairs(V.TABS) do
    local tab = g_ui.createWidget('MentorTab', window.tabs)
    tab:setText(tr(t[2]))
    local key = t[1]
    tab.onClick = function() showPage(key) end
    tabs[key] = tab
  end
  local p = window.findPage
  p.onlineCombo:clearOptions()
  for _, o in ipairs(V.ONLINE_OPTIONS) do p.onlineCombo:addOption(tr(o[2]), o[1]) end
  p.lineCombo:clearOptions()
  p.lineCombo:addOption(tr('Any class'), '')
  p.seekCheck.onCheckChange = function(widget, checked)
    if not filling and status then send('seek', { on = checked }) end
  end
end

function init()
  g_ui.importStyle('mentor')
  handlers.opcode = safe('opcode', onMessage)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  local ok, ui = pcall(g_ui.createWidget, 'MentorWindow', rootWidget)
  if ok and ui then
    window = ui
    window:hide()
    local built, err = pcall(buildTabs)
    if not built then g_logger.warning('[mentor] tabs: ' .. tostring(err)) end
  else
    g_logger.warning('[mentor] window not loaded: ' .. tostring(ui))
  end
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  addMenu()
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game)
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if window then window:destroy() window = nil end
  tabs = {}
  handlers = {}
end
