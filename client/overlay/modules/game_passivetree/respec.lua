-- Respec prices in the passive tree window (server: server/data/scripts/chaos/respec.lua, numbers in respec_config.lua).
-- The server sends respecInfo {level, full, paragon, node, free, freeBelowLevel} with every requestPoints and after each
-- reset / refund; this file shows it on the Reset button tooltip, in the reset dialog (passivetree.lua reset() asks
-- respecResetText) and in the refund dialog of a right-clicked saved node (refundNode {id}).
ChaosTreeHandlers = ChaosTreeHandlers or {}
local respecInfo = nil
local refundBox = nil
local nodeNames = nil

function formatGold(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return (out:gsub('^,', ''))
end

function getRespecInfo()
  return respecInfo
end

local function freeText(info)
  if info.free == 'level' then
    return tr('free below level %d', info.freeBelowLevel or 50)
  elseif info.free == 'vocation' then
    return tr('free once after your class changed')
  end
  return nil
end

local function priceText(cost, info)
  if (cost or 0) <= 0 then
    return 'free' .. (freeText(info) and (' (' .. freeText(info) .. ')') or '')
  end
  return tr('%s gold coins', formatGold(cost))
end

local function refreshTooltip()
  local window = getTreeWindow and getTreeWindow()
  local button = window and window:recursiveGetChildById('resetPresetButton')
  if button and respecInfo then
    button:setTooltip(tr('Reset the whole tree: %s.\nRight-click a saved node to refund only that node: %s.',
      priceText(respecInfo.full, respecInfo), priceText(respecInfo.node, respecInfo)))
  end
end

ChaosTreeHandlers.respecInfo = function(data)
  if type(data) ~= 'table' then
    return
  end
  respecInfo = data
  refreshTooltip()
end

-- reset() in passivetree.lua shows this text when the server's price is known
function respecResetText()
  if not respecInfo then
    sendAction('respecInfo')
    return tr('The reset price is not known yet. Press Reset again in a moment.')
  end
  return tr('Reset your whole passive tree for %s? Every point becomes free to spend again.\n' ..
    'To take back only one node, right-click it instead (%s).', priceText(respecInfo.full, respecInfo),
    priceText(respecInfo.node, respecInfo))
end

-- the name the class sees (a class lane's or a keystone variant's, treelanes.lua), else the node's own
local function nodeName(id)
  local map = getTreeNodeMap and getTreeNodeMap()
  local node = map and map[id]
  if node then
    return TreeLanes.displayName(node, getTreeVariant()) or tr('this keystone')
  end
  if not nodeNames then
    nodeNames = {}
    local ok, nodes = pcall(getTreeNodes)
    if ok and type(nodes) == 'table' then
      for i, n in pairs(nodes) do
        nodeNames[i] = n.name or tr('this keystone')
      end
    end
  end
  return nodeNames[id] or ('node ' .. id)
end

local function closeRefund()
  if refundBox then
    refundBox:destroy()
    refundBox = nil
  end
end

-- right-click on a node widget (passivetree.lua buildTree; a press: this client delivers no right-button release to it)
function onNodeMousePress(widget, mousePos, button)
  if button ~= MouseRightButton then
    return false
  end
  local id = tonumber(widget:getId())
  if isTreeReadOnly and isTreeReadOnly() then
    return false -- another character's tree (Inspect Player)
  end
  if not id or not widget:isOn() or not widget.blocked then
    return false -- not allocated (a planned node: left-click takes it out of the plan)
  end
  closeRefund()
  local cost = respecInfo and respecInfo.node
  local text = tr('Refund %s? The point becomes free to spend again.\nPrice: %s.', nodeName(id),
    cost and priceText(cost, respecInfo) or tr('asked from the server'))
  local function ok()
    sendAction('refundNode', {id = id})
    closeRefund()
  end
  refundBox = displayGeneralBox(tr('Refund node'), text, {
    {text = tr('Refund'), callback = ok},
    {text = tr('Cancel'), callback = closeRefund},
    anchor = AnchorHorizontalCenter
  }, ok, closeRefund)
  return true
end
