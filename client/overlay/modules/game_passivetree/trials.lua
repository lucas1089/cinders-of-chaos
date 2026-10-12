-- Vocation Trials panel of the passive tree window. The server (server/data/scripts/chaos/trials.lua) owns the rules and
-- checks everything again; this panel shows its trialState and sends:
--   trialRequest -> trialState, trialChoose {pair, side} (side 0 gives a pair up), trialEnter {tier}, trialLeave
-- Maths and texts in trialsmath.lua. The window, the node cards and the tier buttons are in trials.otui (ornate skin styles).
-- The run itself is shown by the rift HUD (game_rift): clock, lives, progress.
ChaosTreeHandlers = ChaosTreeHandlers or {}
local trialsWindow = nil
local trialsState = nil
local confirmBox = nil
local COLOR_TITLE, COLOR_TEXT = '#e8b84a', '#d6c9ae'

function getTrialsState()
  return trialsState
end

local function closeConfirm()
  if confirmBox then
    confirmBox:destroy()
    confirmBox = nil
  end
end

local function setCard(card, state, entry, side)
  local node = entry.nodes[side]
  local info = TrialsMath.card(state, entry, side)
  card.cardName:setText(TrialsMath.fit(node.name, 30))
  card.cardName:setColor(entry.locked and '#8c8070' or (entry.held == side and '#f6cf72' or COLOR_TITLE))
  for i = 1, TrialsMath.MAX_LINES do
    local label = card['line' .. i]
    local line = node.lines and node.lines[i]
    if line and not entry.locked then
      label:setText((line.good and '+ ' or '- ') .. TrialsMath.fit(line.text, 46))
      label:setColor(line.good and TrialsMath.GOOD or TrialsMath.BAD)
    elseif line then
      label:setText('? ' .. string.rep('.', 14))
      label:setColor(TrialsMath.DIM)
    else
      label:setText('')
    end
  end
  card.lore:setText(entry.locked and '' or TrialsMath.fit(node.lore or '', 52))
  card.status:setText(TrialsMath.fit(info.status, 30))
  card.status:setColor(info.statusColor)
  card.action:setText(info.action)
  card.action:setEnabled(info.enabled)
  local tip = info.tooltip
  if node.needsSpellEvents and not entry.locked then
    tip = tip .. '\nPart of this node needs the server\'s spell events.'
  end
  card:setTooltip(tip)
  card.action:setTooltip(tip)
  card.cardSide = side
  card.cardPair = entry.pair
end

local function refreshTrials()
  if not trialsWindow or not trialsState then
    return
  end
  local s = trialsState
  if not s.supported then
    trialsWindow.trialName:setText('No trial for this vocation')
    trialsWindow.story:setText('')
    trialsWindow.content:setVisible(false)
    return
  end
  trialsWindow.content:setVisible(true)
  trialsWindow.trialName:setText(TrialsMath.fit(s.trial, 40))
  trialsWindow.story:setText(TrialsMath.fit(s.story, 190))
  trialsWindow.content.tokens:setText(TrialsMath.tokensLine(s))
  for i = 1, 3 do
    local button = trialsWindow.content.tiers['tier' .. i]
    local info = TrialsMath.tierButton(s, i)
    button:setText(info.text)
    button:setEnabled(info.enabled)
    button:setTooltip(info.tooltip)
  end
  trialsWindow.leaveButton:setVisible(s.running == true)
  for p = 1, 3 do
    local entry = s.pairs[p]
    local row = trialsWindow.content.pairsPanel['row' .. p]
    row.rowTitle:setText(string.format('Pair %d\n%s%s', p, entry.tier, entry.locked and '\n(locked)' or ''))
    row.rowTitle:setColor(entry.locked and '#8c8070' or COLOR_TITLE)
    setCard(row.cardA, s, entry, 1)
    setCard(row.cardB, s, entry, 2)
  end
end

-- server -> client trialState
ChaosTreeHandlers.trialState = function(data)
  if type(data) ~= 'table' then
    return
  end
  trialsState = data
  refreshTrials()
end

function chooseTrialNode(pair, side)
  local s = trialsState
  if not s or not s.supported or not s.pairs[pair] then
    return
  end
  local entry = s.pairs[pair]
  closeConfirm()
  local function ok()
    sendAction('trialChoose', {pair = pair, side = side})
    closeConfirm()
  end
  confirmBox = displayGeneralBox(entry.held == 0 and 'Choose a node' or 'Switch node', TrialsMath.confirmText(s, entry, side), {
    {text = tr('Ok'), callback = ok},
    {text = tr('Cancel'), callback = closeConfirm},
    anchor = AnchorHorizontalCenter
  }, ok, closeConfirm)
end

function enterTrialTier(tier)
  if trialsState and trialsState.supported then
    closeTrials()
    sendAction('trialEnter', {tier = tier})
    local tree = getTreeWindow()
    if tree and tree:isVisible() then
      hide()
    end
  end
end

function leaveTrial()
  sendAction('trialLeave')
end

function openTrials()
  local tree = getTreeWindow()
  if not tree then
    return
  end
  if not trialsWindow then
    trialsWindow = g_ui.loadUI('trials', tree)
    for p = 1, 3 do
      local row = trialsWindow.content.pairsPanel['row' .. p]
      for _, id in ipairs({'cardA', 'cardB'}) do
        local card = row[id]
        local pair = p
        card.action.onClick = function()
          chooseTrialNode(pair, card.cardSide or (id == 'cardA' and 1 or 2))
        end
      end
    end
    for i = 1, 3 do
      local tier = i
      trialsWindow.content.tiers['tier' .. i].onClick = function()
        enterTrialTier(tier)
      end
    end
  end
  trialsWindow:show()
  trialsWindow:raise()
  trialsWindow:focus()
  refreshTrials()
  sendAction('trialRequest')
end

function closeTrials()
  closeConfirm()
  if trialsWindow then
    trialsWindow:hide()
  end
end

function toggleTrials()
  if trialsWindow and trialsWindow:isVisible() then
    closeTrials()
  else
    openTrials()
  end
end

function destroyTrials()
  closeTrials()
  if trialsWindow then
    trialsWindow:destroy()
    trialsWindow = nil
  end
  trialsState = nil
end
