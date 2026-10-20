-- Auto build panel of the passive tree window (server/data/scripts/chaos/passive_builds.lua). The server lists the builds
-- of the class (Recommended per role, Focus themes), previews one (nodes, points, price) and applies it. The client
-- shows the lists in a dropdown, the preview in the tree and the maths of autobuildview.lua; it never builds a plan itself.
--   autobuildList -> autobuildList {group, builds, owned, held, free, cap} (twice: role, focus)
--   autobuildPreview {build} -> autobuildPreview {...} | autobuildError {message}
--   autobuildApply {build, mode = "add" | "reset", cost} -> autobuildApplied {message} | autobuildError {message}
ChaosTreeHandlers = ChaosTreeHandlers or {}
local abWindow = nil
local groups = {role = {}, focus = {}}
local state = {owned = 0, held = 0, free = 0}
local rows = {}
local preview = nil
local selected = nil -- id of the picked build
local confirmBox = nil
local filling = false

local function alive()
  if abWindow and abWindow.isDestroyed and abWindow:isDestroyed() then
    abWindow = nil -- the tree window was destroyed (logout)
  end
  return abWindow
end

local function child(id)
  alive()
  return abWindow and abWindow:recursiveGetChildById(id)
end

local function currentBuild()
  local i = selected and AutoBuildView.indexOf(rows, selected)
  return i and rows[i].build or nil
end

local function refresh()
  local label = child('detailText')
  if label then
    local text, color = AutoBuildView.detail(currentBuild(), state, preview)
    label:setText(text)
    label:setColor(color)
  end
  local apply, reset = child('applyButton'), child('resetButton')
  if apply then
    apply:setEnabled(AutoBuildView.canApply(preview))
  end
  if reset then
    reset:setEnabled(AutoBuildView.canReset(preview))
  end
end

local function fillCombo()
  local combo = child('buildCombo')
  if not combo then
    return
  end
  rows = AutoBuildView.rows(groups)
  filling = true
  combo:clearOptions()
  for i, r in ipairs(rows) do
    combo:addOption(r.text, i)
  end
  local i = selected and AutoBuildView.indexOf(rows, selected) or AutoBuildView.firstBuild(rows)
  if i then
    combo:setCurrentIndex(i)
    selected = rows[i].id
  else
    selected = nil
  end
  filling = false
end

local function askPreview()
  preview = nil
  if selected then
    sendAction('autobuildPreview', {build = selected})
  else
    showTreeAllocation({}, false)
    sendAction('requestNodesUnlocked')
  end
  refresh()
end

local function onPick(combo, text, data)
  if filling then
    return
  end
  local r = rows[tonumber(data) or 0]
  if not r then
    return
  end
  if r.heading then
    -- headings are not builds: go back to the previous pick
    local i = selected and AutoBuildView.indexOf(rows, selected) or AutoBuildView.firstBuild(rows)
    if i then
      filling = true
      combo:setCurrentIndex(i)
      filling = false
    end
    return
  end
  if r.id ~= selected then
    selected = r.id
    askPreview()
  end
end

function openAutoBuild()
  local tree = getTreeWindow()
  if not tree then
    return
  end
  if not alive() then
    abWindow = g_ui.loadUI('autobuild', tree)
    abWindow:recursiveGetChildById('buildCombo').onOptionChange = onPick
  end
  abWindow:show()
  abWindow:raise()
  abWindow:focus()
  fillCombo()
  refresh()
  sendAction('autobuildList')
end

local function closeConfirm()
  if confirmBox then
    confirmBox:destroy()
    confirmBox = nil
  end
end

-- leave the preview: the tree shows the saved allocation again
local function leavePreview()
  closeConfirm()
  if preview then
    preview = nil
    sendAction('requestNodesUnlocked')
    sendAction('requestPoints')
  end
end

function closeAutoBuild()
  leavePreview()
  if abWindow then
    abWindow:hide()
  end
end

function toggleAutoBuild()
  if abWindow and abWindow:isVisible() then
    closeAutoBuild()
  else
    openAutoBuild()
  end
end

function destroyAutoBuild()
  closeConfirm()
  preview = nil
  if abWindow then
    abWindow:destroy()
    abWindow = nil
  end
end

function applyAutoBuild()
  if not AutoBuildView.canApply(preview) then
    return
  end
  closeConfirm()
  sendAction('autobuildApply', {build = preview.build, mode = 'add', cost = 0})
end

function resetAndApplyAutoBuild()
  if not AutoBuildView.canReset(preview) then
    return
  end
  closeConfirm()
  local sentBuild, sentCost = preview.build, (preview.reset and preview.reset.cost) or 0
  local function ok()
    sendAction('autobuildApply', {build = sentBuild, mode = 'reset', cost = sentCost})
    closeConfirm()
  end
  confirmBox = displayGeneralBox(tr('Reset and apply'), AutoBuildView.confirmText(preview), {
    {text = tr('Apply'), callback = ok},
    {text = tr('Cancel'), callback = closeConfirm},
    anchor = AnchorHorizontalCenter
  }, ok, closeConfirm)
end

-- ------------------------------------------------------------------------------------------------ server messages
ChaosTreeHandlers.autobuildList = function(data)
  if type(data) ~= 'table' or (data.group ~= 'role' and data.group ~= 'focus') or not alive() then
    return
  end
  groups[data.group] = type(data.builds) == 'table' and data.builds or {}
  state = {owned = data.owned or 0, held = data.held or 0, free = data.free or 0, cap = data.cap}
  local first = selected == nil
  fillCombo()
  if first and selected then
    askPreview()
  else
    refresh()
  end
end

ChaosTreeHandlers.autobuildPreview = function(data)
  if type(data) ~= 'table' or not alive() or not abWindow:isVisible() then
    return
  end
  if data.build ~= selected then
    return -- an answer to an earlier pick
  end
  preview = data
  -- the tree shows what Reset and apply would build when it takes something back, else what Apply adds on top
  local reset = data.reset or {}
  local add = data.add or {}
  if (reset.removed or 0) > 0 then
    showTreeAllocation(reset.nodes or {}, true, reset.masteries)
  else
    showTreeAllocation(add.nodes or {}, true, add.masteries)
  end
  refresh()
end

ChaosTreeHandlers.autobuildError = function(data)
  local text = type(data) == 'table' and data.message or tr('The build could not be applied.')
  local label = child('detailText')
  if abWindow and abWindow:isVisible() and label then
    label:setText(text)
    label:setColor('#e07060')
  else
    sendMessageBox(tr('Auto build'), text)
  end
end

ChaosTreeHandlers.autobuildApplied = function(data)
  preview = nil
  local label = child('detailText')
  refresh()
  if label then
    label:setText(type(data) == 'table' and data.message or tr('Build applied.'))
    label:setColor(AutoBuildView.GOOD)
  end
  sendAction('autobuildList')
end
