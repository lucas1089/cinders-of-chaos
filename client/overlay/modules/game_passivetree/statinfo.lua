-- Stat help of the passive tree window (server/data/scripts/chaos/passivetree_stats.lua, maths: statinfoview.lua).
-- The server sends the stats of the class with their names, descriptions and Primary / Secondary tag. The window shows
-- the Primary / Secondary header, marks the nodes (gold border: a Primary stat, silver: a Secondary one), adds the
-- description lines to a node tooltip and lists the stats in the Stats panel. Without the message everything stays as before.
--   statInfo -> statInfo {cls, part, parts, header, stats} (a few messages)
ChaosTreeHandlers = ChaosTreeHandlers or {}
local info = StatInfoView.new()
local siWindow = nil

local function alive()
  if siWindow and siWindow.isDestroyed and siWindow:isDestroyed() then
    siWindow = nil
  end
  return siWindow
end

function requestStatInfo()
  info = StatInfoView.new()
  sendAction('statInfo')
end

-- node widget border by the tag of the node's stats
function markStatNode(widget, stats)
  local color = StatInfoView.color(StatInfoView.tag(info, stats))
  if color then
    widget:setBorderWidth(2)
    widget:setBorderColor(color)
  else
    widget:setBorderWidth(0)
  end
end

-- extra tooltip lines: what each stat of the node does
function statInfoLines(stats)
  return StatInfoView.lines(info, stats)
end

local function fillPanel()
  if not alive() then
    return
  end
  local list = siWindow:recursiveGetChildById('rows')
  list:destroyChildren()
  for _, row in ipairs(StatInfoView.rows(info)) do
    local label = g_ui.createWidget('StatInfoRow', list)
    label:setText(row.text)
    label:setColor(row.color)
  end
end

local function refreshHeader()
  local tree = getTreeWindow()
  local label = tree and tree:recursiveGetChildById('statHeader')
  if label then
    label:setText(StatInfoView.headerText(info))
  end
end

function openStatInfo()
  local tree = getTreeWindow()
  if not tree then
    return
  end
  if not alive() then
    siWindow = g_ui.loadUI('statinfo', tree)
  end
  siWindow:show()
  siWindow:raise()
  siWindow:focus()
  fillPanel()
end

function closeStatInfo()
  if siWindow then
    siWindow:hide()
  end
end

function toggleStatInfo()
  if siWindow and siWindow:isVisible() then
    closeStatInfo()
  else
    openStatInfo()
  end
end

ChaosTreeHandlers.statInfo = function(data)
  info = StatInfoView.add(info, data)
  if info.got < info.parts then
    return -- more parts follow
  end
  refreshHeader()
  fillPanel()
  refreshStatMarks() -- passivetree.lua: marks and tooltips of every node widget
end
