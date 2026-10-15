-- Another character's passive tree, read-only (Inspect Player: game_playerinspect calls showOtherTree with the server's
-- `tree` packet {name, nodes, masteries = [{id, choice}], cls, line, vocation, spent, total}; server inspect.lua, which
-- sends it only when the inspect is allowed, so the privacy setting holds). The tree window shows that tree in place
-- of the own one: the other class's section and keystone variants, the chosen mastery effects in the tooltips, its
-- bonuses in "Info & Bonuses". Nothing can be planned, applied or refunded; the editing buttons are off and a banner
-- names the character. "Back to my tree", Close or the top menu button show the own tree again.
local EDIT_BUTTONS = {'applyPoints', 'resetPresetButton', 'paragonButton', 'buildShareButton', 'trialsButton'}

local function child(id)
  local window = getTreeWindow()
  return window and window:recursiveGetChildById(id)
end

local function setEditing(enabled)
  for _, id in ipairs(EDIT_BUTTONS) do
    local button = child(id)
    if button then
      button:setEnabled(enabled)
    end
  end
  local bar = child('planBar')
  if bar then
    bar:setVisible(enabled)
  end
end

function showOtherTree(data)
  local window = getTreeWindow()
  if not window or type(data) ~= 'table' or type(data.nodes) ~= 'table' then
    return
  end
  closeParagon()
  closeTrials()
  if closeBuildShare then
    closeBuildShare()
  end
  plannerReset()
  setEditing(false)
  setTreeViewing(data)
  local banner = child('viewBanner')
  if banner then
    local label = banner:getChildById('viewText')
    label:setText(tr('%s: %d passive node%s (read-only)', tostring(data.name or '?'), #data.nodes,
      #data.nodes == 1 and '' or 's'))
    banner:setVisible(true)
  end
  window:show()
  window:raise()
  window:focus()
end

function closeOtherTree()
  local banner = child('viewBanner')
  if banner then
    banner:setVisible(false)
  end
  setEditing(true)
  setTreeViewing(nil)
  plannerUpdateBar()
end
