-- Build code panel of the passive tree window: export / import a build (server/data/scripts/chaos/buildshare.lua).
-- The server encodes, decodes and validates; the client never decodes a code itself. It asks for a preview and shows
-- what the server sends: the nodes that would be allocated (shown in the tree), points needed vs. owned, what changes
-- and the price. Apply sends the code back with the price the preview showed.
--   buildExport -> buildCode {code}, buildPreview {code} -> buildPreview {...} | buildError {message},
--   buildApply {code, cost} -> buildApplied {message} | buildError {message}
ChaosTreeHandlers = ChaosTreeHandlers or {}
local buildWindow = nil
local preview = nil
local confirmBox = nil

local function alive()
  if buildWindow and buildWindow.isDestroyed and buildWindow:isDestroyed() then
    buildWindow = nil -- the tree window was destroyed (logout)
  end
  return buildWindow
end

local function child(id)
  alive()
  return buildWindow and buildWindow:recursiveGetChildById(id)
end

local function setPreviewText(text, color)
  local label = child('previewText')
  if label then
    label:setText(text or '')
    label:setColor(color or '#d8cfc0')
  end
end

local function refreshButtons()
  local apply, cancel = child('applyButton'), child('cancelButton')
  if apply then
    apply:setEnabled(preview ~= nil and preview.change == true)
  end
  if cancel then
    cancel:setEnabled(preview ~= nil)
  end
end

function openBuildShare()
  local tree = getTreeWindow()
  if not tree then
    return
  end
  if not alive() then
    buildWindow = g_ui.loadUI('buildshare', tree)
  end
  buildWindow:show()
  buildWindow:raise()
  buildWindow:focus()
  refreshButtons()
end

local function closeConfirm()
  if confirmBox then
    confirmBox:destroy()
    confirmBox = nil
  end
end

-- leave the preview: the tree shows the saved allocation again
function cancelBuildPreview()
  closeConfirm()
  if preview then
    preview = nil
    sendAction('requestNodesUnlocked')
    sendAction('requestPoints')
  end
  setPreviewText('')
  refreshButtons()
end

function closeBuildShare()
  cancelBuildPreview()
  if buildWindow then
    buildWindow:hide()
  end
end

function toggleBuildShare()
  if buildWindow and buildWindow:isVisible() then
    closeBuildShare()
  else
    openBuildShare()
  end
end

function destroyBuildShare()
  closeConfirm()
  preview = nil
  if buildWindow then
    buildWindow:destroy()
    buildWindow = nil
  end
end

function exportBuild()
  sendAction('buildExport')
end

function pasteBuild()
  local edit = child('codeEdit')
  if edit then
    edit:setText((g_window.getClipboardText() or ''):gsub('%s+', ' '):sub(1, 600))
  end
end

function importBuild()
  local edit = child('codeEdit')
  local code = edit and edit:getText() or ''
  if code:gsub('%s', '') == '' then
    setPreviewText(tr('Paste a build code into the box first.'), '#e07060')
    return
  end
  setPreviewText(tr('Asking the server for a preview...'))
  sendAction('buildPreview', {code = code})
end

function applyBuild()
  if not preview or not preview.change then
    return
  end
  closeConfirm()
  local price = (preview.cost or 0) > 0 and (tr('%s gold coins', formatGold(preview.cost))) or 'free'
  local text = tr('Apply this build (%d nodes%s)?\nPrice: %s.', preview.applied or 0,
    (preview.removed or 0) > 0 and tr(', %d of your nodes taken back', preview.removed) or '', price)
  local sentCode, sentCost = preview.code, preview.cost or 0
  local function ok()
    sendAction('buildApply', {code = sentCode, cost = sentCost})
    closeConfirm()
  end
  confirmBox = displayGeneralBox(tr('Import build'), text, {
    {text = tr('Apply'), callback = ok},
    {text = tr('Cancel'), callback = closeConfirm},
    anchor = AnchorHorizontalCenter
  }, ok, closeConfirm)
end

-- ------------------------------------------------------------------------------------------------ server messages
ChaosTreeHandlers.buildCode = function(data)
  if type(data) ~= 'table' or type(data.code) ~= 'string' then
    return
  end
  openBuildShare()
  local edit = child('codeEdit')
  if edit then
    edit:setText(data.code)
  end
  g_window.setClipboardText(data.code)
  setPreviewText(tr('Your build code (%d nodes%s) was copied to the clipboard.\nShare it, or paste it in chat as a build link: [build %s]',
    #(data.nodes or {}), data.paragon and tr(' and your Paragon points') or '', data.code))
end

ChaosTreeHandlers.buildPreview = function(data)
  if type(data) ~= 'table' then
    return
  end
  local tree = getTreeWindow()
  if not tree or not tree:isVisible() then
    return -- a chat preview (!build import) while the window is closed: the chat has the summary
  end
  openBuildShare()
  preview = data
  local edit = child('codeEdit')
  if edit and edit:getText() == '' then
    edit:setText(data.code or '')
  end
  local lines = {data.summary or ''}
  lines[#lines + 1] = tr('Points: the build needs %d, you own %d.', data.wanted or 0, data.points or 0)
  if data.change then
    lines[#lines + 1] = 'The tree shows the build now. Apply Build to take it, Cancel Preview to go back.'
  end
  setPreviewText(table.concat(lines, '\n'), data.change and '#d8cfc0' or '#c0b080')
  showTreeAllocation(data.nodes or {}, true, data.masteries)
  refreshButtons()
end

ChaosTreeHandlers.buildError = function(data)
  local text = type(data) == 'table' and data.message or tr('The build could not be imported.')
  if buildWindow and buildWindow:isVisible() then
    setPreviewText(text, '#e07060')
  else
    sendMessageBox(tr('Build code'), text)
  end
end

ChaosTreeHandlers.buildApplied = function(data)
  preview = nil
  refreshButtons()
  setPreviewText(type(data) == 'table' and data.message or tr('Build imported.'), '#80c070')
end
