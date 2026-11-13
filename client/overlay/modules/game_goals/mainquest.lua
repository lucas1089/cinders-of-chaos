-- Main Quest window of game_goals (O551): the chapters, their steps and the epilogue, from the server's `mq` message (GoalsView.onMQ).
-- Functions are of the module (init and terminate are called from goals.lua, which owns the channel).

local V = GoalsView
local mqWindow
local chosen -- the chapter shown

function initMainQuest()
  mqWindow = g_ui.displayUI('mainquest')
  mqWindow:hide()
end

function terminateMainQuest()
  if mqWindow then
    mqWindow:destroy()
    mqWindow = nil
  end
end

local function mq()
  local st = mqState()
  return st and st.mq or nil
end

local function stepColor(s)
  if s.state == 'done' then return '#7cc070' end
  if s.state == 'open' then return '#f6cf72' end
  return '#8c8070'
end

function drawMainQuest()
  if not mqWindow or not mqWindow:isVisible() then return end
  local data = mq()
  mqWindow.waitLabel:setVisible(data == nil)
  mqWindow.chapterList:destroyChildren()
  mqWindow.stepList:destroyChildren()
  if not data then return end
  chosen = chosen or V.mqChapter(data)
  for _, c in ipairs(data.chapters) do
    local b = g_ui.createWidget('MQChapterButton', mqWindow.chapterList)
    b:setText(V.mqChapterLine(c))
    b:setColor(tonumber(c.n) == chosen and '#f6cf72' or '#d6c9ae')
    local n = tonumber(c.n)
    b.onClick = function() chosen = n drawMainQuest() end
  end
  local intro = ''
  for _, c in ipairs(data.chapters) do
    if tonumber(c.n) == chosen then intro = tostring(c.intro or '') end
  end
  mqWindow.introLabel:setText(intro)
  if chosen >= 8 then
    for _, e in ipairs(data.epilogue) do
      local row = g_ui.createWidget('MQStepRow', mqWindow.stepList)
      row.title:setText(tr('%s (from level %d)', tostring(e.title or ''), tonumber(e.level) or 0))
      row.hint:setText(tostring(e.text or ''))
    end
  else
    for _, s in ipairs(V.mqSteps(data, chosen)) do
      local row = g_ui.createWidget('MQStepRow', mqWindow.stepList)
      row.title:setText(V.mqStepLine(s))
      row.title:setColor(stepColor(s))
      row.hint:setText(tostring(s.hint or ''))
    end
  end
  mqWindow.goButton:setEnabled(data.state == 0)
  mqWindow.skipChapterButton:setEnabled(data.state == 0)
end

function showMainQuest()
  if not mqWindow then return end
  chosen = nil
  mqWindow:show()
  mqWindow:raise()
  mqWindow:focus()
  sendData('mqOpen')
  drawMainQuest()
end

function hideMainQuest()
  if mqWindow then mqWindow:hide() end
end

function toggleMainQuest()
  if not mqWindow then return end
  if mqWindow:isVisible() then hideMainQuest() else showMainQuest() end
end

function skipChapter()
  sendData('mqSkip', { scope = 'chapter' })
  scheduleEvent(function() sendData('mqOpen') end, 300)
end

-- the Go button: the open step's where, as a click on the tracker row does it
function goCurrentStep()
  local st = mqState()
  local r = st and st.welcome and st.welcome[1]
  if not r then return end
  if V.action(r.where) then runWhere(r.where) end
  sendData('mqGo', { step = r.key })
end
