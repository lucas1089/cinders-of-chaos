-- Achievements window: categories, a progress bar per achievement, points (character and account), hidden ones as
-- "???", a title selector (every title the character holds, for the server's name plates) and the recent unlocks.
-- Server: server/data/scripts/chaos/achievements.lua, extended opcode 250 (JSON {action, data}).
--   server -> client  state {open, points, accountPoints, maxPoints, unlocked, total, categories = [{key, name, done,
--                            total, points, max}], recent = [{id, name, points, at}], titles = [{key, text, at}],
--                            titlesOn, activeTitle}
--                     list {first, last, rows = [{i, n, d, c, p, h, u, v, t, ti, r}]}   (sent in parts after state)
--                     unlock {id, name, points, title}                                   (the toast comes on opcode 79)
--                     track {ap, steps, cats}   the reward track (cosmetics_core.lua trackView): account point
--                            milestones and category completion, each with its cosmetic; sent after state
--   client -> server  open | get
-- The top menu (Character > Achievements) calls toggle().

local OPCODE = 250
local V = AchievementsView

local window
local state            -- last state received
local rows = {}        -- rows being received / shown
local pending = {}     -- rows of a list still arriving
local selected = V.ALL -- category shown
local categoryButtons = {}
local updatingCombo = false
local wantOpen = false
local track            -- last reward track received (nil: an older server, the track panel stays hidden)

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function list(value)
  local out = {}
  if type(value) == 'table' then
    for _, v in ipairs(value) do out[#out + 1] = v end
  end
  return out
end

-- ---------------------------------------------------------------- rows
local function createRow(r)
  local row = g_ui.createWidget('AchievementRow', window.rowList)
  local unlocked = V.isUnlocked(r)
  local hiddenLocked = V.isHiddenLocked(r)
  row.name:setText(r.n or '?')
  row.points:setText(tostring(tonumber(r.p) or 0) .. ' pts')
  row.desc:setText(r.d or '')
  row.extra:setText(hiddenLocked and '' or V.extraText(r))
  row.progress:setPercent(V.percent(r))
  if unlocked then
    row.name:setColor('#f6cf72')
    row.points:setColor('#e8b84a')
    row.progress:setText(tr('Unlocked %s', V.dateText(r.u)))
    row.progress:setBackgroundColor('#8a6a1c')
    row:setBackgroundColor('#2a1e0c')
  else
    row.progress:setText(V.progressText(r))
    if hiddenLocked then
      row.desc:setColor('#6b6258')
      row.progress:setBackgroundColor('#3a3339')
    end
  end
  return row
end

local function createTrackRow(r)
  local row = g_ui.createWidget('AchievementRow', window.rowList)
  row.name:setText(r.name)
  row.points:setText(r.right)
  row.desc:setText(r.desc)
  row.extra:setText(r.extra)
  row.progress:setPercent(r.percent)
  row.progress:setText(r.progress)
  row:setTooltip(r.tip)
  if r.color then row.name:setColor(r.color) end -- a chat colour previews itself
  if r.accent then row.extra:setBackgroundColor(r.accent) end -- a label accent behind the kind line
  if r.done then
    if not r.color then row.name:setColor('#f6cf72') end
    row.points:setColor('#e8b84a')
    row.progress:setBackgroundColor('#8a6a1c')
    row:setBackgroundColor('#2a1e0c')
  end
  return row
end

local function showRows()
  if not window then return end
  window.rowList:destroyChildren()
  if selected == V.TRACK then
    local trackRows = V.trackRows(track)
    for _, r in ipairs(trackRows) do createTrackRow(r) end
    window.emptyText:setVisible(#trackRows == 0)
    return
  end
  local shown = V.filter(rows, selected, selected ~= V.RECENT)
  for _, r in ipairs(shown) do createRow(r) end
  window.emptyText:setVisible(#shown == 0)
end

local function selectCategory(key)
  selected = key
  for k, b in pairs(categoryButtons) do b:setChecked(k == key) end
  showRows()
end

local function buildCategories()
  window.categoryPanel:destroyChildren()
  categoryButtons = {}
  local entries = { { key = V.ALL, label = tr('All  %d/%d', tonumber(state.unlocked) or 0, tonumber(state.total) or 0) },
    { key = V.RECENT, label = tr('Recently unlocked') } }
  if track then
    entries[#entries + 1] = { key = V.TRACK, label = tr('Reward track  %d/%d', V.trackReached(track), #list(track.steps)),
      tip = tr('Cosmetics earned by playing: account point milestones and complete categories. Never sold.') }
  end
  for _, c in ipairs(list(state.categories)) do
    local reward = V.categoryReward(track, c.key)
    entries[#entries + 1] = { key = c.key, label = V.categoryLabel(c),
      tip = tr('%d of %d points', tonumber(c.points) or 0, tonumber(c.max) or 0) .. (reward and ('\n' .. reward) or '') }
  end
  for _, e in ipairs(entries) do
    local b = g_ui.createWidget('AchievementCategory', window.categoryPanel)
    b:setText(e.label)
    if e.tip then b:setTooltip(e.tip) end
    local key = e.key
    b.onClick = function() selectCategory(key) end
    b:setChecked(key == selected)
    categoryButtons[key] = b
  end
end

local function buildTitles()
  local combo = window.titleCombo
  updatingCombo = true
  combo:clearOptions()
  -- every title the character holds (achievements, leaderboards, siege, seasons); older servers: achievement titles
  local titles = #list(state.heldTitles) > 0 and list(state.heldTitles) or list(state.titles)
  local on = state.titlesOn and true or false
  combo:setVisible(on)
  window.titleLabel:setVisible(on)
  if on then
    combo:addOption(tr('Newest title'), 'auto')
    combo:addOption(tr('No title'), 'none')
    local current
    for _, t in ipairs(titles) do
      combo:addOption(t.text, t.text)
      if t.text == state.activeTitle then current = t.text end
    end
    if current then combo:setCurrentOption(current) else combo:setCurrentOption(tr('Newest title')) end
    window.hintLabel:setText(tr('Your title shows above your name.'))
  else
    window.hintLabel:setText(tr('Titles: %d.', #titles))
  end
  updatingCombo = false
end

-- the reward track strip: a bar to the next milestone and one pip per milestone (tooltip = preview)
local function showTrack()
  if not window then return end
  local panel = window.trackPanel
  panel:setVisible(track ~= nil)
  if not track then return end
  panel.trackBar:setPercent(V.trackPercent(track))
  panel.trackBar:setText(V.trackText(track))
  local nxt = V.trackNext(track)
  panel.trackBar:setTooltip(nxt and V.rewardTooltip(nxt, track.ap) or tr('Every milestone reached.'))
  local pips = panel.trackPips
  pips:destroyChildren()
  local all = list(track.steps)
  local width = math.floor(math.max(pips:getWidth(), 1) / math.max(#all, 1))
  for _, s in ipairs(all) do
    local pip = g_ui.createWidget('AchievementTrackPip', pips)
    pip:setWidth(width)
    pip:setText(V.group(tonumber(s.p) or 0))
    if (tonumber(track.ap) or 0) >= (tonumber(s.p) or 0) then
      pip:setColor('#f6cf72')
    elseif s == nxt then
      pip:setColor('#5cc8c0')
    end
    pip:setTooltip(V.rewardTooltip(s, track.ap))
  end
end

local function showState()
  if not window or not state then return end
  window.summaryLabel:setText(V.summaryText(state))
  window.summaryLabel:setTooltip(tr('Account points count each achievement once, whichever character earned it. Maximum: %d.',
    tonumber(state.maxPoints) or 0))
  local recent = {}
  for _, r in ipairs(list(state.recent)) do
    recent[#recent + 1] = string.format('%s (+%d)', r.name or '?', tonumber(r.points) or 0)
  end
  window.recentPanel.recentLabel:setText(#recent > 0 and (tr('Recent:') .. ' ' .. table.concat(recent, ',  '))
    or tr('Recent: nothing yet. Level up, hunt tiered monsters, seal rifts...'))
  buildCategories()
  buildTitles()
  showTrack()
end

-- ---------------------------------------------------------------- protocol
local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[achievements] invalid JSON: ' .. tostring(msg))
    return
  end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    state = data
    wantOpen = data.open and true or wantOpen
    showState()
  elseif msg.action == 'list' then
    if data.first then pending = {} end
    for _, r in ipairs(list(data.rows)) do pending[#pending + 1] = r end
    if data.last then
      rows = pending
      pending = {}
      showRows()
      if wantOpen then
        wantOpen = false
        show()
      end
    end
  elseif msg.action == 'track' then
    track = data
    if state then
      buildCategories()
      showTrack()
    end
    if selected == V.TRACK then showRows() end
  elseif msg.action == 'unlock' then
    if window and window:isVisible() then send('get') end
  end
end

-- ---------------------------------------------------------------- window
function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
end

function hide()
  if window then window:hide() end
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
    return
  end
  send('open')
end

local function onTitleChange(combo, text, data)
  if updatingCombo or not data then return end
  send('title', { title = V.titleParam(data) })
  scheduleEvent(function() send('get') end, 600)
end

local function onGameEnd()
  hide()
  state, rows, pending, selected, track = nil, {}, {}, V.ALL, nil
end

function init()
  window = g_ui.displayUI('achievements')
  window:hide()
  window.titleCombo.onOptionChange = onTitleChange
  window.trackPanel.trackPips.onGeometryChange = function() if track then showTrack() end end
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if window then
    window:destroy()
    window = nil
  end
  state, rows, pending, categoryButtons, track = nil, {}, {}, {}, nil
end
