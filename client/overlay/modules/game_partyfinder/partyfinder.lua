-- Party Finder window: browse groups, apply with a role, post and run your own listing, quick join.
-- Server: server/data/scripts/chaos/party_finder.lua, extended opcode 208 (JSON {action, data}, sent with
-- Chaos.sendChunked and joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open | hide | refresh | post {...} | unlist | apply {id, role} | withdraw {id} | accept {id, g}
--                     | decline {id, g} | queue {role, a} | unqueue
--   server -> client  init {acts, roles, my, lv, exp, defExp, lim} | list {rows, mine, badge, applied, queue}
--                     | badge {n} | notice {text, kind} | nudge {text, a, n} (players look for a group for the content you
--                     entered: a toast with [Join] that opens the browse tab)
-- The server pushes a new list while the window is open; the time left counts down here every second. A new
-- application shows a toast and a badge on the Social menu (also while the window is closed). Menu: Social > Party
-- Finder (added with ChaosTopBar.addEntry).

local OPCODE = 208
local V = PartyFinderView

local window
local srv -- the server's init message
local data -- the last list
local receivedAt = 0
local tab = 'browse'
local tabs = {}
local live = {} -- {row, widget} of the browse rows on screen
local tickEvent
local handlers = {}
local reported = {}
local updating = false
local badgeCount = 0
local badgeWidget
local menuEntry
local toast, toastEvent
local formFilled -- the listing id the form was filled from

local function now() return g_clock.seconds() end

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[partyfinder] ' .. name .. ': ' .. tostring(res))
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

local function elapsed() return math.max(0, now() - receivedAt) end

local function setMessage(text, color)
  if window then
    window.messageLabel:setText(text or '')
    window.messageLabel:setColor(color or V.COLORS.text)
  end
end

-- ---------------------------------------------------------------- badge and toast
local function updateBadge()
  local text = V.badgeText(badgeCount)
  if menuEntry then
    menuEntry.text = badgeCount > 0 and tr('Party Finder (%d)', badgeCount) or tr('Party Finder')
    local top = modules.client_chaos_topbar
    if top and top.ChaosTopBar and top.ChaosTopBar.refresh then pcall(top.ChaosTopBar.refresh) end
  end
  if tabs.my then
    tabs.my:setText(badgeCount > 0 and tr('My Group (%d)', badgeCount) or tr('My Group'))
  end
  local root = g_ui.getRootWidget()
  local button = root and root:recursiveGetChildById('chaosMenu_social')
  if button and (not badgeWidget or badgeWidget:getParent() ~= button) then
    if badgeWidget then badgeWidget:destroy() end
    badgeWidget = g_ui.createWidget('PartyFinderBadge', button)
    badgeWidget:addAnchor(AnchorTop, 'parent', AnchorTop)
    badgeWidget:addAnchor(AnchorRight, 'parent', AnchorRight)
    badgeWidget:setMarginTop(-3)
    badgeWidget:setMarginRight(-3)
  end
  if badgeWidget then
    badgeWidget:setText(text)
    badgeWidget:setVisible(text ~= '')
    badgeWidget:setTooltip(tr('Party Finder: %d application(s)', badgeCount))
  end
end

local function setBadge(n)
  badgeCount = math.max(0, tonumber(n) or 0)
  updateBadge()
end

local function hideToast()
  if toastEvent then removeEvent(toastEvent) toastEvent = nil end
  if toast then toast:destroy() toast = nil end
end

local function showToast(text, tabKey)
  hideToast()
  local root = g_ui.getRootWidget()
  if not root then return end
  toast = g_ui.createWidget('PartyFinderToast', root)
  toast.text:setText(text)
  toast:addAnchor(AnchorTop, 'parent', AnchorTop)
  toast:addAnchor(AnchorRight, 'parent', AnchorRight)
  toast:setMarginTop(44)
  toast:setMarginRight(16)
  toast.onClick = function() hideToast() show() selectTab(tabKey or 'my') return true end
  toast:raise()
  toastEvent = scheduleEvent(hideToast, 7000)
end

-- ---------------------------------------------------------------- combos
local function fillCombo(combo, options, keep)
  local current = keep and combo:getCurrentOption()
  combo:clearOptions()
  for _, o in ipairs(options) do combo:addOption(o[1], o[2], true) end
  if current then combo:setCurrentOptionByData(current.data, true) end
end

local function comboData(combo)
  local o = combo:getCurrentOption()
  return o and o.data
end

local function roleOptions(list, first)
  local out = {}
  if first then out[1] = first end
  for _, r in ipairs(list) do out[#out + 1] = { V.roleName(r), r } end
  return out
end

local function activityOptions(first)
  local out = {}
  if first then out[1] = first end
  for _, a in ipairs(srv and srv.acts or {}) do out[#out + 1] = { a.n, a.k } end
  return out
end

-- ---------------------------------------------------------------- browse
local SLOT, SLOT_GAP, SLOT_COLS = 18, 2, 10

-- the slot boxes wrap: a raid of 15 is two rows of 8 + 7. -> the number of rows
local function fillSlots(panel, row)
  panel:destroyChildren()
  local slots = V.slots(row)
  local cols, rows = V.slotGrid(#slots, SLOT_COLS)
  panel:setSize({ width = cols * (SLOT + SLOT_GAP) - SLOT_GAP, height = rows * (SLOT + SLOT_GAP) - SLOT_GAP })
  for _, s in ipairs(slots) do
    local w = g_ui.createWidget('PartyFinderSlot', panel)
    w:setText(V.roleLetter(s.role))
    if s.filled then
      w:setBackgroundColor(V.roleColor(s.role))
      w:setColor('#0d0b0e')
      w:setOpacity(s.st == 'invited' and 0.6 or 1)
    else
      w:setBackgroundColor(V.COLORS.open)
      w:setColor(V.roleColor(s.role))
      w:setBorderColor(V.roleColor(s.role))
    end
  end
  panel:setTooltip(V.compTooltip(row))
  return rows
end

local function applyTo(row)
  local roles = V.applyRoles(row, srv and srv.my)
  if #roles == 1 then
    send('apply', { id = row.id, role = roles[1] })
    return
  end
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  for _, r in ipairs(roles) do
    menu:addOption(tr('Apply as %s', V.roleName(r)), function() send('apply', { id = row.id, role = r }) end)
  end
  menu:display(g_window.getMousePosition())
end

local function renderBrowse()
  if not window then return end
  local p = window.browsePanel
  local list = p.rowList
  list:destroyChildren()
  live = {}
  local f = { a = comboData(p.activityFilter) or '', role = comboData(p.roleFilter) or '', fits = p.fitsCheck:isChecked() }
  local level = srv and srv.lv or 0
  local rows = V.filter(data and data.rows, f, level)
  local e = elapsed()
  for _, row in ipairs(rows) do
    local w = g_ui.createWidget('PartyFinderRow', list)
    w.activity:setText(row.an or '?')
    w.note:setText(row.note or '')
    w.note:setTooltip(row.note ~= '' and row.note or nil)
    w.sub:setText(V.subLine(row, e))
    w.openText:setText(V.openText(row))
    local slotRows = fillSlots(w.slots, row)
    w:setHeight(48 + (slotRows - 1) * (SLOT + SLOT_GAP))
    local ok, why = V.canApply(row, srv and srv.my, level)
    if row.mine then
      w.action:setText(tr('Manage'))
      w.action.onClick = function() selectTab('my') end
      w.state:setText(tr('Your group'))
      w.state:setColor(V.COLORS.gold)
    elseif row.ap then
      w.action:setText(tr('Withdraw'))
      w.action.onClick = function() send('withdraw', { id = row.id }) end
      w.state:setText(tr('Applied as %s', V.roleName(row.ap)))
      w.state:setColor(V.roleColor(row.ap))
    else
      w.action:setText(tr('Apply'))
      w.action:setEnabled(ok)
      w.action.onClick = function() applyTo(row) end
      w.state:setText(ok and '' or why)
      w.state:setColor(V.COLORS.dim)
    end
    if row.mine then w:setBackgroundColor('#241c14') end
    live[#live + 1] = { row = row, widget = w }
  end
  p.emptyText:setVisible(#rows == 0)
  p.emptyText:setText(data and ((data.rows and #data.rows > 0) and tr('No group matches the filters.')
    or tr('No groups are looking right now. Post your own under My Group.')) or tr('Loading...'))
  p.countLabel:setText(data and tr('%d of %d groups', #rows, #(data.rows or {})) or '')
  -- quick join line
  local q = data and data.queue
  p.queuePanel.queueButton:setText(q and tr('Leave queue') or tr('Join queue'))
  p.queuePanel.queueRole:setEnabled(not q)
  p.queuePanel.queueActivity:setEnabled(not q)
  p.queuePanel.queueStatus:setText(q and V.queueText(q, srv and srv.acts, e) or '')
end

-- ---------------------------------------------------------------- my group
-- the wanted boxes go up to the activity's cap per role (raid: 3 tanks, 4 healers, 12 DPS); `suggest` sets the
-- activity's proposal (a new listing only)
local function updateWant(act, suggest)
  local f = window.myPanel.form
  local lim = V.limits(act, srv and srv.lim)
  for _, e in ipairs({ { f.wantTank, 'tank' }, { f.wantHealer, 'healer' }, { f.wantDps, 'dps' } }) do
    local combo, r = e[1], e[2]
    local current = tonumber(comboData(combo)) or 0
    local counts = {}
    for i = 0, lim.per[r] do counts[#counts + 1] = { tostring(i), i } end
    fillCombo(combo, counts)
    local want = suggest and act and act.suggest and tonumber(act.suggest[r]) or current
    combo:setCurrentOptionByData(math.min(want, lim.per[r]), true)
  end
end

local function updateDetail(suggest)
  local f = window.myPanel.form
  local act = V.activityOf(srv and srv.acts, comboData(f.activity))
  updateWant(act, suggest and not (data and data.mine))
  local kind = V.formKind(act)
  f.lo:setVisible(kind == 'range')
  f.hi:setVisible(kind == 'range')
  f.toLabel:setVisible(kind == 'range')
  f.target:setVisible(kind == 'targets')
  f.title:setVisible(kind == 'title')
  f.lDetail:setVisible(kind ~= 'none')
  if kind == 'range' then
    f.lDetail:setText(act.range.label or tr('Range'))
    f.lo:setTooltip(tr('%d to %d', act.range.min, act.range.max))
  elseif kind == 'targets' then
    f.lDetail:setText(tr('Target'))
    local opts = { { tr('Any'), 0 } }
    for i, t in ipairs(act.targets) do opts[#opts + 1] = { t, i } end
    fillCombo(f.target, opts, true)
  elseif kind == 'title' then
    f.lDetail:setText(tr('Title'))
  end
end

local function formValues()
  local f = window.myPanel.form
  return { a = comboData(f.activity), lo = f.lo:getText(), hi = f.hi:getText(), t = comboData(f.target),
    title = f.title:getText(), tank = comboData(f.wantTank), healer = comboData(f.wantHealer), dps = comboData(f.wantDps),
    minLevel = f.minLevel:getText(), note = f.note:getText(), exp = comboData(f.exp), role = comboData(f.role),
    auto = f.auto:isChecked() }
end

local function updateSize()
  local f = window.myPanel.form
  local size = V.formSize(formValues())
  local max = V.limits(V.activityOf(srv and srv.acts, comboData(f.activity)), srv and srv.lim).max
  f.sizeLabel:setText(tr('group of %d / %d', size, max))
  f.sizeLabel:setColor(size > max and V.COLORS.error or V.COLORS.dim)
end

-- the form from the listing the server has (once per listing, so typing is not overwritten by pushes)
local function fillForm(input)
  local f = window.myPanel.form
  updating = true
  f.activity:setCurrentOptionByData(input.a, true)
  updateDetail()
  f.lo:setText(tostring(input.lo or ''))
  f.hi:setText(tostring(input.hi or ''))
  f.target:setCurrentOptionByData(input.t or 0, true)
  f.title:setText(input.title or '')
  f.role:setCurrentOptionByData(input.role, true)
  local want = input.want or {}
  f.wantTank:setCurrentOptionByData(want.tank or 0, true)
  f.wantHealer:setCurrentOptionByData(want.healer or 0, true)
  f.wantDps:setCurrentOptionByData(want.dps or 0, true)
  f.minLevel:setText(tostring(input.minLevel or 1))
  f.note:setText(input.note or '')
  f.exp:setCurrentOptionByData(input.exp, true)
  f.auto:setChecked(input.auto and true or false)
  updating = false
  updateSize()
end

local function renderMine()
  if not window then return end
  local panel = window.myPanel
  local f = panel.form
  local mine = data and data.mine
  f.postButton:setText(mine and tr('Update') or tr('Post'))
  f.unlistButton:setEnabled(mine ~= nil)
  if mine and formFilled ~= mine.id and mine.input then
    formFilled = mine.id
    fillForm(mine.input)
  elseif not mine then
    formFilled = nil
  end
  if mine then
    f.listedLabel:setText(tr('Listed: %s', mine.an or '?'))
    f.listedSub:setText(string.format('%s  -  %s', V.openText(mine), V.timeLeft((mine.left or 0) - elapsed()) .. ' left'))
    fillSlots(f.mySlots, mine)
    f.mySlots:setVisible(true)
  else
    f.listedLabel:setText(tr('Not listed'))
    f.listedSub:setText(tr('Fill in the form and post: other players see your group under Browse.'))
    f.mySlots:setVisible(false)
  end
  local list = panel.appList
  list:destroyChildren()
  local apps = mine and mine.apps or {}
  for _, a in ipairs(apps) do
    local w = g_ui.createWidget('PartyFinderApplicant', list)
    w.name:setText(V.applicantLine(a))
    w.role:setText(V.roleName(a.r))
    w.role:setColor(V.roleColor(a.r))
    w.info:setText((a.q and tr('quick join, ') or '') .. V.ago((a.ago or 0) + elapsed()))
    w.accept.onClick = function() send('accept', { id = mine.id, g = a.g }) end
    w.decline.onClick = function() send('decline', { id = mine.id, g = a.g }) end
  end
  panel.appsEmpty:setVisible(#apps == 0)
  panel.appsEmpty:setText(mine and tr('No applications yet.') or tr('Post a listing to get applications.'))
  panel.appsPlate.appsTitle:setText(tr('Applications (%d)', #apps))
end

local function render()
  if not window then return end
  renderBrowse()
  renderMine()
end

-- every second: the time left on the rows on screen
local function tick()
  tickEvent = nil
  if not window or not window:isVisible() then return end
  local e = elapsed()
  for _, entry in ipairs(live) do entry.widget.sub:setText(V.subLine(entry.row, e)) end
  local q = data and data.queue
  if q then window.browsePanel.queuePanel.queueStatus:setText(V.queueText(q, srv and srv.acts, e)) end
  local mine = data and data.mine
  if mine then
    window.myPanel.form.listedSub:setText(string.format('%s  -  %s', V.openText(mine),
      V.timeLeft((mine.left or 0) - e) .. ' left'))
  end
  tickEvent = scheduleEvent(tick, 1000)
end

local function stopTick()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

-- ---------------------------------------------------------------- server messages
local function onInit(d)
  srv = d
  V.setRoles(d.roles)
  if not window then return end
  local p, f = window.browsePanel, window.myPanel.form
  updating = true
  fillCombo(p.activityFilter, activityOptions({ tr('All activities'), '' }), true)
  fillCombo(p.roleFilter, roleOptions(V.ROLE_ORDER, { tr('Any role'), '' }), true)
  fillCombo(p.queuePanel.queueRole, roleOptions(d.my or {}), true)
  fillCombo(p.queuePanel.queueActivity, activityOptions({ tr('Any activity'), '' }), true)
  fillCombo(f.activity, activityOptions(), true)
  fillCombo(f.role, roleOptions(d.my or {}), true)
  local exps = {}
  for _, m in ipairs(d.exp or {}) do exps[#exps + 1] = { m >= 60 and tr('%d h', math.floor(m / 60)) or tr('%d min', m), m } end
  fillCombo(f.exp, exps, true)
  if not comboData(f.exp) or not formFilled then f.exp:setCurrentOptionByData(d.defExp, true) end
  f.note:setMaxLength(d.lim and d.lim.note or 80)
  f.title:setMaxLength(d.lim and d.lim.title or 24)
  if f.minLevel:getText() == '' then f.minLevel:setText('1') end
  updating = false
  updateDetail()
  updateSize()
  local names = {}
  for _, r in ipairs(d.my or {}) do names[#names + 1] = V.roleName(r) end
  window.hint:setText(tr('Level %d  -  your class plays %s', d.lv or 0, table.concat(names, ' / ')))
end

local function onList(d)
  data = d
  receivedAt = now()
  setBadge(d.badge)
  render()
end

local function onNotice(d)
  local text = tostring(d.text or '')
  if d.kind == 'error' then
    setMessage(text, V.COLORS.error)
  else
    setMessage(text, d.kind == 'accepted' and V.COLORS.ok or V.COLORS.text)
  end
  if d.kind == 'apply' or d.kind == 'accepted' then showToast(text) end
end

-- the group nudge (server groupnudge.lua): players look for a group for the content just entered; one toast with [Join],
-- a click opens the browse tab
local function onNudge(d)
  local text = type(d.text) == 'string' and d.text or ''
  if text == '' or #text > 160 then return end
  showToast(text .. ' ' .. tr('[Join]'), 'browse')
end

local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' or type(msg.data) ~= 'table' then return end
  if msg.action == 'init' then onInit(msg.data)
  elseif msg.action == 'list' then onList(msg.data)
  elseif msg.action == 'badge' then setBadge(msg.data.n)
  elseif msg.action == 'notice' then onNotice(msg.data)
  elseif msg.action == 'nudge' then onNudge(msg.data) end
end

-- ---------------------------------------------------------------- window
function selectTab(key)
  tab = key
  for k, t in pairs(tabs) do t:setChecked(k == key) end
  if window then
    window.browsePanel:setVisible(key == 'browse')
    window.myPanel:setVisible(key == 'my')
  end
end

function hide()
  stopTick()
  if window and window:isVisible() then
    window:hide()
    send('hide')
  end
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  setMessage('')
  send('open')
  stopTick()
  tick()
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

function refresh() send('refresh') end

function post()
  if not window or not srv then return end
  local input = V.postInput(srv.acts, formValues())
  formFilled = nil -- take the server's cleaned values back into the form
  send('post', input)
end

function unlist() send('unlist') end

function toggleQueue()
  if not window then return end
  if data and data.queue then
    send('unqueue')
  else
    local p = window.browsePanel
    send('queue', { role = comboData(p.queuePanel.queueRole), a = comboData(p.queuePanel.queueActivity) or '' })
  end
end

-- for other modules and tests
function getState()
  return { rows = data and #(data.rows or {}) or 0, shown = #live, badge = badgeCount, tab = tab,
    visible = window and window:isVisible() or false, mine = data and data.mine ~= nil or false }
end

-- offline rendering and tests: feed a server message as if it came on the opcode
function receive(msg) onMessage(nil, OPCODE, msg) end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    menuEntry = { text = 'Party Finder', icon = 'vip', modules = { 'game_partyfinder' }, fns = { 'toggle' } }
    handlers.menu = pcall(api.addEntry, 'social', menuEntry)
  end
end

local function onGameStart()
  data, srv = nil, nil
  setBadge(0)
  addMenu()
end

local function onGameEnd()
  hide()
  hideToast()
  data, srv, formFilled = nil, nil, nil
  setBadge(0)
end

function init()
  local ok, ui = pcall(g_ui.displayUI, 'partyfinder')
  if ok and ui then
    window = ui
    window:hide()
    for _, t in ipairs({ { 'browse', 'Browse' }, { 'my', 'My Group' } }) do
      local b = g_ui.createWidget('PartyFinderTab', window.tabs)
      b:setText(tr(t[2]))
      local key = t[1]
      b.onClick = function() selectTab(key) end
      tabs[key] = b
    end
    selectTab('browse')
    local p, f = window.browsePanel, window.myPanel.form
    local rerender = safe('filter', function() if not updating then renderBrowse() end end)
    p.activityFilter.onOptionChange = rerender
    p.roleFilter.onOptionChange = rerender
    p.fitsCheck.onCheckChange = rerender
    f.activity.onOptionChange = safe('activity', function() if not updating then updateDetail(true) updateSize() end end)
    local resize = safe('size', function() if not updating then updateSize() end end)
    f.wantTank.onOptionChange = resize
    f.wantHealer.onOptionChange = resize
    f.wantDps.onOptionChange = resize
  else
    g_logger.warning('[partyfinder] window not loaded: ' .. tostring(ui))
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
  hideToast()
  if badgeWidget then badgeWidget:destroy() badgeWidget = nil end
  if window then window:destroy() window = nil end
  live, data, srv, handlers, tabs = {}, nil, nil, {}, {}
end
