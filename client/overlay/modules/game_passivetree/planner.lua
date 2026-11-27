-- Passive tree planner (the logic is treeplan.lua, tested by treeplan_test.lua). A left click on a node that is not
-- allocated plans the shortest path to it from the allocated set (and the plan), over nodes the class may take; a click
-- on a planned node takes it out with what hangs on it; a planned mastery opens its choice of effects. Planned nodes
-- are drawn with the "checked" frame of passivetree.otui and their links as the allocation's edge. Undo / Redo / Clear
-- (also Ctrl+Z / Ctrl+Y) work on whole plan states. Apply sends the whole plan in one request:
--   client -> server  planApply {nodes = [ids], masteries = [{id, choice}]}   masteryChoose {id, choice}
--   server -> client  planResult {ok, message} (after sendNodes / sendPoints when it saved something)
-- The server checks the plan like a save (server/data/scripts/chaos/passivetree_core.lua validatePlan) and saves all of
-- it or nothing. A saved mastery's effect changes through masteryChoose, for the single-node refund price (respec.lua).
ChaosTreeHandlers = ChaosTreeHandlers or {}
local plan = TreePlan.new()
local adjacency, adjacencyFor = nil, nil
local choiceWindow = nil
local confirmBox = nil
local lastMessage, lastColor = nil, nil

local function nodes()
  return getTreeNodeMap() or {}
end

local function graph()
  local map = nodes()
  if adjacencyFor ~= map then
    adjacency, adjacencyFor = TreePlan.graph(map), map
  end
  return adjacency
end

-- the allocated ids: the ones shown and every id the server saved (getTreeSaved), so a plan never prices an owned node
local function allocatedSet()
  return TreePlan.ownedIds(getTreeAllocated(), getTreeSaved and getTreeSaved())
end

local function ownedSet()
  local set = allocatedSet()
  for id in pairs(plan.set) do
    set[id] = true
  end
  return set
end

-- a node the plan may step on: shown (in nodeMap), the class may take it, not a start node, not owned (shown allocated
-- or saved on the server), no excluded twin taken
local function passable(id)
  local node = nodes()[id]
  if not node or node.locked or node.isStartNode or node.alloc or (getTreeSaved and getTreeSaved()[id]) then
    return false
  end
  if node.exclude and (allocatedSet()[node.exclude] or plan.set[node.exclude]) then
    return false
  end
  return true
end

local function isMasteryId(id)
  local node = nodes()[id]
  return node ~= nil and node.isMastery == true
end

local function child(id)
  local window = getTreeWindow()
  return window and window:recursiveGetChildById(id)
end

function plannerChoice(id)
  return plan.set[id] and plan.masteries[id] or nil
end

function plannerIds()
  local out = {}
  for i, id in ipairs(plan.list) do
    out[i] = id
  end
  return out
end

-- the plan bar: cost against the free points, the buttons
function plannerUpdateBar()
  local label = child('planCost')
  if not label then
    return
  end
  local text, fits = TreePlan.costText(TreePlan.cost(plan), getTreeFreePoints())
  if lastMessage and TreePlan.isEmpty(plan) then
    text, fits = lastMessage, lastColor ~= '#e07060'
  end
  label:setText(text)
  label:setColor(lastMessage and TreePlan.isEmpty(plan) and lastColor or (fits and '#d8cfc0' or '#e07060'))
  local readOnly = isTreeReadOnly()
  local undo, redo, clear, apply = child('planUndo'), child('planRedo'), child('planClear'), child('applyPoints')
  if undo then undo:setEnabled(not readOnly and #plan.undo > 0) end
  if redo then redo:setEnabled(not readOnly and #plan.redo > 0) end
  if clear then clear:setEnabled(not readOnly and not TreePlan.isEmpty(plan)) end
  if apply then apply:setEnabled(not readOnly and not TreePlan.isEmpty(plan)) end
end

-- the planned flags and widgets after any change of the plan (or new widgets)
function plannerRefresh()
  for id, node in pairs(nodes()) do
    local planned = plan.set[id] == true
    if (node.planned == true) ~= planned then
      node.planned = planned or nil
      refreshTreeNode(node)
    elseif planned then
      local widget = getTreeNodeWidget(id)
      if widget and not widget:isChecked() then
        refreshTreeNode(node)
      end
    end
  end
  if refreshTreeKeystones then
    refreshTreeKeystones() -- the keystone counter and the cap note of the tooltips (O447)
  end
  plannerUpdateBar()
end

local function changed()
  lastMessage = nil
  plannerRefresh()
  calculateStats()
end

-- passivetree.lua applyAllocation: ids the server saved leave the plan
function plannerOnAllocation()
  TreePlan.prune(plan, allocatedSet())
  plannerRefresh()
end

function plannerReset()
  TreePlan.reset(plan)
  closeMasteryChoice()
  if getTreeWindow() then
    plannerRefresh()
  end
end

function plannerUndo()
  if TreePlan.undo(plan) then changed() end
end

function plannerRedo()
  if TreePlan.redo(plan) then changed() end
end

function plannerClear()
  closeMasteryChoice()
  if TreePlan.clear(plan) then changed() end
end

-- ------------------------------------------------------------------------------------------------ mastery choice
local function closeConfirm()
  if confirmBox then
    confirmBox:destroy()
    confirmBox = nil
  end
end

function closeMasteryChoice()
  closeConfirm()
  if choiceWindow then
    choiceWindow:destroy()
    choiceWindow = nil
  end
end

local function effectText(effect)
  return table.concat(getCustomStatString(effect.customStats or {}), ' ')
end

local function changeSaved(node, choice)
  closeConfirm()
  local info = getRespecInfo and getRespecInfo()
  local price = info and ((info.node or 0) > 0 and (tr('%s gold coins', formatGold(info.node))) or 'free') or tr('the single-node refund price')
  local effect = node.masteries[choice]
  local function ok()
    sendAction('masteryChoose', {id = node.id, choice = choice})
    closeMasteryChoice()
  end
  confirmBox = displayGeneralBox(tr('Change mastery effect'), tr('Change %s to %s?\nPrice: %s (like refunding one node).',
    node.name or tr('this mastery'), effect.name or (tr('effect %s', choice)), price), {
    {text = tr('Change'), callback = ok},
    {text = tr('Cancel'), callback = closeConfirm},
    anchor = AnchorHorizontalCenter
  }, ok, closeConfirm)
end

-- the effects of a mastery as buttons; saved: the node is allocated (a change is priced), else it is planned (free)
-- the choice window: its height without the effect list, the gap between two buttons, the room round a button's text
CHOICE_CHROME, CHOICE_SPACING, CHOICE_PAD = 130, 6, 10
-- F46: the room kept free above and below the window, its lowest height, and the list's gap for its scroll bar
CHOICE_MARGIN, CHOICE_MIN, CHOICE_BAR = 16, 250, 16

-- the height the choice window may take: the smaller of the tree window and the interface (540 on a phone)
local function choiceRoom(win)
  local h = rootWidget and rootWidget:getHeight() or 0
  local parent = win and win:getParent()
  if parent and parent:getHeight() > 0 and (h <= 0 or parent:getHeight() < h) then h = parent:getHeight() end
  return h
end

-- the window at the wanted height, cut to the screen: the list scrolls and leaves room for its bar when it was cut
local function fitChoice(win, total)
  local height, cut = TreePlan.choiceFit(total, choiceRoom(win), CHOICE_MARGIN, CHOICE_MIN)
  win:setHeight(height)
  win.effectsScrollBar:setVisible(cut)
  win.effects:setMarginRight(cut and CHOICE_BAR or 0)
  return cut
end

function openMasteryChoice(node, saved)
  closeMasteryChoice()
  local tree = getTreeWindow()
  if not tree or not node or not node.isMastery then
    return
  end
  choiceWindow = g_ui.loadUI('mastery', tree)
  choiceWindow:setText(node.name or tr('Mastery'))
  local current = saved and getSavedMastery(node.id) or plan.masteries[node.id]
  choiceWindow.hint:setText(saved and tr('Pick another effect. A change costs the single-node refund price.') or
    tr('Pick one effect. You can change it for free until you apply the plan.'))
  local list = choiceWindow.effects
  local rows = CHOICE_CHROME
  local bases, buttons = {}, {}
  for i, effect in ipairs(node.masteries or {}) do
    local button = g_ui.createWidget('MasteryEffectButton', list)
    -- a combo mastery (O686 phase 6b) is a short two-line text: its button is lower, so eight effects still fit a 540 px screen
    local combo = effect.customStats and effect.customStats.comboMod
    button:setHeight(combo and 34 or 46)
    rows = rows + (combo and 34 or 46) + CHOICE_SPACING
    bases[#bases + 1], buttons[#buttons + 1] = combo and 34 or 46, button
    button:setText(string.format('%s%s\n%s', effect.name or ('Effect ' .. i), current == i and '  (chosen)' or '', effectText(effect)))
    button:setOn(current == i)
    button.onClick = function()
      if saved then
        if current ~= i then
          changeSaved(node, i)
        end
        return
      end
      TreePlan.setMastery(plan, node.id, i)
      closeMasteryChoice()
      changed()
      -- the next planned mastery that still needs an effect
      local missing = TreePlan.missingMasteries(plan, isMasteryId)
      if #missing > 0 then
        openMasteryChoice(nodes()[missing[1]], false)
      end
    end
  end
  fitChoice(choiceWindow, rows) -- up to 7 effects of three lines since O451, and a low combo mastery button since O686 phase 6b
  local remove = choiceWindow.removeButton
  remove:setVisible(not saved)
  remove.onClick = function()
    closeMasteryChoice()
    TreePlan.remove(plan, node.id, graph(), allocatedSet())
    changed()
  end
  choiceWindow:show()
  choiceWindow:raise()
  choiceWindow:focus()
  -- once the layout gave the buttons their width, each grows to its wrapped text (TreePlan.choiceHeights)
  -- a second pass when the list was cut: the scroll bar made the buttons narrower, so their text wraps again (F46)
  local shown = choiceWindow
  local function measure(pass)
    if choiceWindow ~= shown or shown:isDestroyed() then
      return
    end
    local texts = {}
    for i, button in ipairs(buttons) do
      texts[i] = button:getWidth() > 0 and button:getTextSize().height or nil
    end
    local heights, total = TreePlan.choiceHeights(bases, texts, CHOICE_PAD, CHOICE_SPACING, CHOICE_CHROME)
    for i, button in ipairs(buttons) do
      button:setHeight(heights[i])
    end
    local wasCut = shown.effectsScrollBar:isVisible()
    local cut = fitChoice(shown, total)
    if pass == 1 and cut ~= wasCut then
      scheduleEvent(function() measure(2) end, 50)
    end
  end
  scheduleEvent(function() measure(1) end, 50)
end

-- ------------------------------------------------------------------------------------------------ clicks and apply
function plannerClick(node)
  if isTreeReadOnly() then
    return false
  end
  if isTreePreviewShown() then
    sendMessageBox('Planner', tr('A build code preview is shown. Cancel the preview (Build Code) to plan again.'))
    return false
  end
  if node.alloc then
    if node.isMastery and node.blocked then
      openMasteryChoice(node, true)
      return true
    end
    return false -- saved: right-click refunds it (respec.lua)
  end
  if plan.set[node.id] then
    if node.isMastery then
      openMasteryChoice(node, false)
    else
      TreePlan.remove(plan, node.id, graph(), allocatedSet())
      changed()
    end
    return true
  end
  if node.locked then
    sendMessageBox('Planner', tr('This node belongs to another class.'))
    return false
  end
  local path = TreePlan.findPath(graph(), ownedSet(), node.id, passable)
  if not path then
    sendMessageBox('Planner', tr('No path leads there over nodes your class can take.'))
    return false
  end
  -- the keystone cap (O447): a path that takes the keystones past the cap is not planned; the server would refuse it too
  if treeKeystonesOver and treeKeystonesOver(TreeKeystones.newOnPath(nodes(), ownedSet(), path)) then
    sendMessageBox('Planner', getTreeKeystoneCapText())
    return false
  end
  TreePlan.addPath(plan, path)
  changed()
  local missing = TreePlan.missingMasteries(plan, isMasteryId)
  if #missing > 0 then
    openMasteryChoice(nodes()[missing[1]], false)
  end
  return true
end

function plannerApply()
  if TreePlan.isEmpty(plan) then
    sendMessageBox(tr('Apply plan'), tr('Nothing is planned. Click a node to plan the path to it.'))
    return
  end
  local missing = TreePlan.missingMasteries(plan, isMasteryId)
  if #missing > 0 then
    openMasteryChoice(nodes()[missing[1]], false)
    return
  end
  local cost, free = TreePlan.cost(plan), getTreeFreePoints()
  if cost > free then
    sendMessageBox(tr('Apply plan'), tr('The plan needs %d points; you have %d free. Undo or take nodes out first.', cost, free))
    return
  end
  sendAction('planApply', TreePlan.request(plan))
  lastMessage, lastColor = nil, nil
  local label = child('planCost')
  if label then
    label:setText(tr('Applying...'))
  end
end

ChaosTreeHandlers.planResult = function(data)
  if type(data) ~= 'table' then
    return
  end
  if data.ok then
    TreePlan.reset(plan) -- sendNodes came first: the plan's ids are allocated now
    lastMessage, lastColor = tostring(data.message or tr('Applied.')), '#80c070'
    plannerRefresh()
    calculateStats()
  else
    lastMessage, lastColor = nil, nil
    plannerUpdateBar()
    sendMessageBox(tr('Passive tree'), tostring(data.message or tr('The plan was not applied.')))
  end
end

function destroyPlanner()
  closeMasteryChoice()
  TreePlan.reset(plan)
  adjacency, adjacencyFor = nil, nil
  lastMessage, lastColor = nil, nil
end
