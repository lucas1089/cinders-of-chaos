-- Auto build panel of the passive tree window (server/data/scripts/chaos/passive_builds.lua). The server lists the builds
-- of the class (Recommended per role, Focus themes), previews one (nodes, points, price) and applies it. The client
-- shows the lists in a dropdown, the preview in the tree and the maths of autobuildview.lua; it never builds a plan itself.
--   autobuildList -> autobuildList {group, builds, owned, held, free, cap} (twice: role, focus)
--   autobuildPreview {build} -> autobuildPreview {...} | autobuildError {message, build, retry}
-- The picked build's preview is asked for whenever none is shown (a new pick, opening the window again, after an
-- Apply) and every request ends: an answer, or asked again on a timeout, then an error line (autobuildview.lua).
--   autobuildApply {build, mode = "add" | "reset", cost} -> autobuildApplied {message} | autobuildError {message}
-- Save to a loadout slot (O448): the picked build's tree goes into a loadout slot the player picks (the live tree does not
-- change, only the tree of the slot is written; the server decides, loadouts.lua saveBuild):
--   autobuildSlots -> autobuildSlots {slots, limit, ...}; autobuildSaveSlot {build, slot, confirm}
--   -> autobuildSlotSaved {message, lines} | autobuildError {message, slot, needConfirm, name}
ChaosTreeHandlers = ChaosTreeHandlers or {}
local abWindow = nil
local groups = {role = {}, focus = {}}
local state = {owned = 0, held = 0, free = 0}
local rows = {}
local preview = nil
local selected = nil -- id of the picked build
local confirmBox = nil
local filling = false
local pending = nil -- {build, tries, event}: the preview asked for and not answered yet
local seq = 0 -- number of the last preview request sent (the answer carries it back, O560)
local lastSentAt = nil -- g_clock.millis() of the last preview request
local sendEvent = nil -- the request waiting for the minimum gap
local failed = nil -- id of the build whose preview failed (not asked again until it is picked again)
local note = nil -- {text, color}: the server's last word (an error, the applied message), shown under the preview
local RED = '#e07060'
local slotWindow = nil -- the slot picker
local slotRows = {} -- its rows: {slot, name, empty, text}
local slotChoice = nil -- index of the picked row
local slotBuild = nil -- {id, name}: the build being saved to a slot
local slotBox = nil -- the question before a held slot is replaced

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
    local text, color = AutoBuildView.detail(currentBuild(), state, preview, note)
    label:setText(text)
    label:setColor(color)
  end
  local apply, reset = child('applyButton'), child('resetButton')
  local save = child('saveSlotButton')
  if save then
    save:setEnabled(currentBuild() ~= nil)
  end
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

local function clearPending()
  if pending and pending.event then
    removeEvent(pending.event)
  end
  pending = nil
end

local askPreview
local sendPreview

local function cancelSend()
  if sendEvent then
    removeEvent(sendEvent)
    sendEvent = nil
  end
end

local function previewFailed(text)
  if pending then
    failed = pending.build
  end
  clearPending()
  note = {text = text, color = RED}
  refresh()
end

local function onPreviewTimeout()
  if not pending then
    return
  end
  pending.event = nil
  if not alive() or not abWindow:isVisible() then
    clearPending()
    return
  end
  if AutoBuildView.onTimeout(pending) == 'retry' then
    askPreview()
  else
    previewFailed(tr('The server did not answer the preview. Close and reopen Auto build to try again.'))
  end
end

-- asks for the picked build's preview (again: the same build counts its tries); the answer or the timeout ends the wait
-- (O560) at most one request per AutoBuildView.MIN_GAP_MS: a pick inside the gap waits for it, and the request that goes
-- out asks for whatever is picked THEN, so the last pick always wins
askPreview = function()
  preview = nil
  cancelSend()
  local delay = AutoBuildView.gateDelay(lastSentAt, g_clock.millis())
  if delay > 0 and selected then
    refresh()
    sendEvent = scheduleEvent(function()
      sendEvent = nil
      sendPreview()
    end, delay)
    return
  end
  sendPreview()
end

sendPreview = function()
  preview = nil
  local before = pending
  clearPending()
  if selected then
    pending = AutoBuildView.ask(before, selected)
    pending.event = scheduleEvent(onPreviewTimeout, AutoBuildView.PREVIEW_TIMEOUT_MS)
    seq = seq + 1
    pending.seq = seq
    lastSentAt = g_clock.millis()
    sendAction('autobuildPreview', {build = selected, seq = seq})
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
  if r.id ~= selected or failed == r.id then
    selected = r.id
    failed, note = nil, nil
    clearPending()
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
  failed, note = nil, nil
  fillCombo()
  refresh()
  sendAction('autobuildList') -- its answer asks for the picked build's preview (autobuildList below)
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
  cancelSend()
  clearPending()
  if preview then
    preview = nil
    sendAction('requestNodesUnlocked')
    sendAction('requestPoints')
  end
end

function closeSlotWindow()
  if slotBox then
    slotBox:destroy()
    slotBox = nil
  end
  if slotWindow then
    slotWindow:destroy()
    slotWindow = nil
  end
end

function closeAutoBuild()
  closeSlotWindow()
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
  closeSlotWindow()
  closeConfirm()
  cancelSend()
  clearPending()
  preview, failed, note = nil, nil, nil
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

-- ------------------------------------------------------------------------------------------------ save to a loadout slot (O448)
local function sendSave(slot, confirm)
  if slotBuild then
    sendAction('autobuildSaveSlot', {build = slotBuild.id, slot = slot, confirm = confirm and true or false})
  end
end

-- a held slot: the player confirms before its tree is replaced (also the answer to a save the server wants confirmed)
local function askReplace(slot, name)
  if not slotBuild then
    return
  end
  if slotBox then
    slotBox:destroy()
    slotBox = nil
  end
  local function ok()
    sendSave(slot, true)
    closeSlotWindow()
  end
  local function cancel()
    if slotBox then
      slotBox:destroy()
      slotBox = nil
    end
  end
  slotBox = displayGeneralBox(tr('Save to a loadout slot'), AutoBuildView.replaceText(slot, name, slotBuild.name), {
    {text = tr('Replace'), callback = ok},
    {text = tr('Cancel'), callback = cancel},
    anchor = AnchorHorizontalCenter
  }, ok, cancel)
end

local function onSlotPick(combo, text, data)
  slotChoice = tonumber(data)
end

local function openSlotWindow(rows_)
  closeSlotWindow()
  slotRows, slotChoice = rows_, 1
  slotWindow = g_ui.loadUI('autobuildslot', getTreeWindow())
  local combo = slotWindow:recursiveGetChildById('slotCombo')
  combo.onOptionChange = onSlotPick
  combo:clearOptions()
  for i, r in ipairs(slotRows) do
    combo:addOption(r.text, i)
  end
  combo:setCurrentIndex(1)
  slotWindow:recursiveGetChildById('introText'):setText(AutoBuildView.pickText(slotBuild))
  slotWindow:show()
  slotWindow:raise()
  slotWindow:focus()
end

-- the button: ask the server which slots can take a build
function saveToSlotAutoBuild()
  local b = currentBuild()
  if not b then
    return
  end
  slotBuild = {id = b.id, name = b.name}
  note = nil
  sendAction('autobuildSlots')
end

-- the picker's Save
function saveSlotOk()
  local r = slotRows[slotChoice or 0]
  if not r or not slotBuild then
    closeSlotWindow()
    return
  end
  if r.empty then
    sendSave(r.slot, false)
    closeSlotWindow()
  else
    askReplace(r.slot, r.name)
  end
end

-- ------------------------------------------------------------------------------------------------ server messages
ChaosTreeHandlers.autobuildList = function(data)
  if type(data) ~= 'table' or (data.group ~= 'role' and data.group ~= 'focus') or not alive() then
    return
  end
  groups[data.group] = type(data.builds) == 'table' and data.builds or {}
  state = {owned = data.owned or 0, held = data.held or 0, free = data.free or 0, cap = data.cap}
  fillCombo()
  -- not only on the first list: after reopening the window or an Apply no preview is shown, and waiting for one that
  -- was never asked for left "Asking the server for a preview..." for good
  if AutoBuildView.needsPreview(selected, preview, pending, failed) then
    askPreview()
  else
    refresh()
  end
end

ChaosTreeHandlers.autobuildPreview = function(data)
  if type(data) ~= 'table' or not alive() or not abWindow:isVisible() then
    return
  end
  if data.build ~= selected or AutoBuildView.isStale(seq, data) then
    return -- an answer to an earlier pick
  end
  clearPending()
  failed = nil
  if note and note.color == RED then
    note = nil
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

ChaosTreeHandlers.autobuildSlots = function(data)
  if type(data) ~= 'table' or not slotBuild or not alive() then
    return
  end
  local rows_ = AutoBuildView.slotRows(data)
  if #rows_ == 0 then
    slotBuild = nil
    note = {text = AutoBuildView.noSlotText(data), color = RED}
    refresh()
    return
  end
  openSlotWindow(rows_)
end

ChaosTreeHandlers.autobuildSlotSaved = function(data)
  closeSlotWindow()
  slotBuild = nil
  if alive() then
    note = {text = AutoBuildView.savedText(data), color = AutoBuildView.GOOD}
    refresh()
  end
end

ChaosTreeHandlers.autobuildError = function(data)
  local text = type(data) == 'table' and data.message or tr('The build could not be applied.')
  if AutoBuildView.isSlotAnswer(data) then
    -- the answer to a save into a slot: never a preview's error
    if data.needConfirm and slotBuild and data.build == slotBuild.id then
      askReplace(data.slot, data.name)
      return
    end
    closeSlotWindow()
    slotBuild = nil
    if alive() and abWindow:isVisible() then
      note = {text = text, color = RED}
      refresh()
    else
      sendMessageBox(tr('Auto build'), text)
    end
    return
  end
  if not (alive() and abWindow:isVisible()) then
    clearPending()
    sendMessageBox(tr('Auto build'), text)
    return
  end
  if AutoBuildView.isStale(seq, data) then
    return -- the error of a request that a newer pick replaced
  end
  local answer = AutoBuildView.onError(pending, data)
  if answer == 'retry' then
    -- too fast: ask again when the server says (MAX_TRIES still ends the wait)
    if pending.event then
      removeEvent(pending.event)
    end
    pending.event = scheduleEvent(onPreviewTimeout, AutoBuildView.retryDelay(data))
    return
  elseif answer == 'fail' then
    previewFailed(text)
    return
  end
  if type(data) == 'table' and data.build ~= nil and data.build ~= selected then
    return -- the error of an earlier pick's preview
  end
  note = {text = text, color = RED}
  refresh()
end

ChaosTreeHandlers.autobuildApplied = function(data)
  preview = nil
  clearPending()
  failed = nil
  note = {text = type(data) == 'table' and data.message or tr('Build applied.'), color = AutoBuildView.GOOD}
  refresh()
  sendAction('autobuildList') -- the new points; its answer asks for the preview on the new tree
end
