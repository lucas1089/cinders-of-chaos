-- Seasonal Journey tab of the Season window (game_season): the season's chapters, the objectives of the chosen chapter
-- with progress bars and its rewards. Messages and the pure parts: journeyview.lua (JourneyView). The tab buttons and
-- the dispatch of the journey* actions live in season.lua; the toast of a completed objective is game_chaosnotify's
-- (notifications opcode 79, action "journey").

SeasonJourneyTab = {}
local Tab = SeasonJourneyTab
local V = JourneyView

local OPCODE = 246
local window, panel
local st = V.new()
local bannerEvent

local function send(action)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = {} }))
  end
end

local function drawRewards(detail)
  local row = panel.rewardsRow
  row:destroyChildren()
  for _, r in ipairs(detail and detail.rewards or {}) do
    local cell = g_ui.createWidget('JourneyRewardCell', row)
    cell.text:setText(V.rewardLine(r))
    if r.piece then
      cell.text:setColor('#b070ff')
      cell:setTooltip(tr('A piece of the %s set', tostring(st.header and st.header.set or 'season')))
    end
    if tonumber(r.clientId) and tonumber(r.clientId) > 0 then
      cell.item:setItemId(tonumber(r.clientId))
      if tonumber(r.count) and tonumber(r.count) > 1 then cell.item:setItemCount(tonumber(r.count)) end
      cell.item:setVisible(true)
    elseif tonumber(r.look) then
      cell.look:setOutfit({ type = tonumber(r.look), head = 78, body = 94, legs = 114, feet = 0 })
      cell.look:setVisible(true)
    else
      local glyph = { passxp = 'XP', title = 'T' }
      cell.badge:setText(glyph[r.kind] or '?')
      cell.badge:setVisible(true)
    end
  end
end

local function drawDetail()
  local i = st.selected
  local c = i and st.chapters[i]
  panel.objectiveList:destroyChildren()
  panel.rewardsRow:destroyChildren()
  if not c then
    panel.chapterName:setText('')
    panel.chapterNote:setText('')
    return
  end
  panel.chapterName:setText(V.chapterLabel(c, i))
  panel.chapterName:setColor(V.STATE_COLOR[c.state] or '#e8b84a')
  panel.chapterNote:setText(V.chapterNote(c))
  local detail = st.details[i]
  local preview = st.header and st.header.preview
  for _, o in ipairs(detail and detail.objectives or {}) do
    local row = g_ui.createWidget('SeasonTrackRow', panel.objectiveList)
    local v = V.objectiveRow(o, preview)
    row.name:setText(v.text)
    row.name:setColor(v.done and '#7fc86a' or (c.state == 'locked' and '#8c8070' or '#d6c9ae'))
    row.mark:setText(v.done and '*' or '-')
    row.mark:setColor(v.done and '#7fc86a' or '#6b6258')
    row.reward:setText(v.tag or '')
    row.reward:setColor('#ff7a5a')
    row.progress:setPercent(v.percent)
    row.progress:setText(v.label)
    row.progress:setBackgroundColor(v.done and '#3f6e24' or '#8a5410')
  end
  drawRewards(detail)
end

local function drawChapters()
  panel.chapterList:destroyChildren()
  for i, c in ipairs(st.chapters) do
    local row = g_ui.createWidget('JourneyChapterRow', panel.chapterList)
    row.title:setText(V.chapterLabel(c, i))
    row.title:setColor(i == st.selected and '#f6cf72' or (c.state == 'locked' and '#8c8070' or '#d6c9ae'))
    row.status:setText(V.chapterStatus(c))
    row.status:setColor(V.STATE_COLOR[c.state] or '#d6c9ae')
    row:setChecked(i == st.selected)
    row:setTooltip(V.chapterNote(c))
    row.onClick = function() Tab.selectChapter(i) end
  end
end

function Tab.draw()
  if not panel then return end
  local h = st.header
  panel.journeyTitle:setText(V.title(h))
  panel.journeySummary:setText(V.summary(h, #st.chapters))
  panel.previewLabel:setText(h and h.preview and tostring(h.why or '') or '')
  panel.previewLabel:setVisible(h ~= nil and h.preview == true)
  panel.waitLabel:setVisible(h == nil)
  drawChapters()
  drawDetail()
end

function Tab.selectChapter(i)
  V.select(st, i)
  Tab.draw()
end

local function banner(text)
  if not panel then return end
  panel.doneBanner:setText(text)
  panel.doneBanner:setVisible(true)
  if bannerEvent then removeEvent(bannerEvent) end
  bannerEvent = scheduleEvent(function()
    bannerEvent = nil
    if panel then panel.doneBanner:setVisible(false) end
  end, 5000)
end

-- season.lua hands every journey* action of the season opcode here
function Tab.onMessage(action, data)
  if action == 'journey' then
    V.onHeader(st, data)
  elseif action == 'journeyChapter' then
    V.onChapter(st, data)
  elseif action == 'journeyDone' then
    banner(V.doneText(data))
    return
  end
  if panel and panel:isVisible() then Tab.draw() end
end

function Tab.open()
  if not panel then return end
  panel:setVisible(true)
  Tab.draw()
  send('journey')
end

function Tab.close()
  if panel and panel:isVisible() then
    panel:setVisible(false)
    if g_game.isOnline() then send('journeyClose') end
  end
end

function Tab.setup(win)
  window = win
  panel = win and win.journeyPanel or nil
  if panel then panel:setVisible(false) end
end

function Tab.reset()
  st = V.new()
  if bannerEvent then removeEvent(bannerEvent) bannerEvent = nil end
end

function Tab.terminate()
  Tab.reset()
  window, panel = nil, nil
end
