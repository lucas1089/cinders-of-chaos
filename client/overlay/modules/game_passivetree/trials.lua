-- Vocation Trials panel of the passive tree window. The server (server/data/scripts/chaos/trials.lua) owns the rules and
-- checks everything again; this panel shows its trialState and sends:
--   trialRequest -> trialState, trialChoose {pair, side} (side 0 gives a pair up: the Clear button of each row), trialEnter {tier}, trialLeave
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

-- ------------------------------------------------------------------------------------------------ a trial is open (O559)
-- The Trials button of the passive tree glows and wears a "!" badge while a trial is open (rule: TrialsMath.openTier), with
-- the trial and the reason in its tooltip; a toast tells it once for every new availability. The state is asked for at login
-- and when the level reaches the next difficulty, so the button is right without opening the window.
-- Hooks for other modules (the hub menu card), through modules.game_passivetree:
--   trialsAvailableCount()  -> 0 / 1 (trials open now)         trialsPendingPicks() -> pairs of nodes waiting for a choice
--   trialsAvailableText()   -> the sentence for a tooltip ('' when none)
--   trialsSubscribe(fn)     -> fn(count, pendingPicks) is called whenever one of them changes; trialsUnsubscribe(fn)
local BASE_TIP = 'Vocation Trials: clear your vocation trial to open pairs of special nodes (choose one of each pair)'
local TOAST_SETTING = 'chaosTrialToast'
local REQUEST_DELAY_MS, LEVEL_DELAY_MS = 4000, 1500
local listeners = {}
local lastCount, lastPicks = 0, 0
local pulseEvent, requestEvent = nil, nil

function trialsAvailableCount()
  return TrialsMath.availableCount(trialsState)
end

function trialsPendingPicks()
  return TrialsMath.pendingPicks(trialsState)
end

function trialsAvailableText()
  return TrialsMath.availableText(trialsState)
end

function trialsSubscribe(fn)
  if type(fn) == 'function' then
    listeners[fn] = true
  end
end

function trialsUnsubscribe(fn)
  listeners[fn] = nil
end

local function trialsButton()
  local tree = getTreeWindow()
  if not tree or (tree.isDestroyed and tree:isDestroyed()) then
    return nil
  end
  return tree:getChildById('trialsButton')
end

local function stopPulse()
  if pulseEvent then
    removeEvent(pulseEvent)
    pulseEvent = nil
  end
  local button = trialsButton()
  if button then
    button:setImageColor('#ffffff')
    button:setColor('#dfdfdf')
  end
end

local function pulse()
  pulseEvent = nil
  local button = trialsButton()
  if not button or trialsAvailableCount() == 0 then
    return
  end
  button:setImageColor(TrialsMath.pulseColor(g_clock.millis()))
  button:setColor('#f6cf72')
  pulseEvent = scheduleEvent(pulse, 100)
end

local function lastToastKey()
  local ok, v = pcall(g_settings.getString, TOAST_SETTING)
  return ok and v ~= '' and v or nil
end

local function toastOnce()
  local name = g_game.getCharacterName and g_game.getCharacterName() or ''
  local key = TrialsMath.toastKey(name, trialsState)
  if not TrialsMath.shouldToast(lastToastKey(), key) then
    return
  end
  pcall(g_settings.set, TOAST_SETTING, key)
  local tree = getTreeWindow()
  if tree and tree:isVisible() then
    return -- the player is looking at the tree already
  end
  local notify = modules.game_chaosnotify
  if notify and notify.addNotification then
    pcall(notify.addNotification, 'TRIAL', TrialsMath.toastText(trialsState))
  end
end

-- the button, the toast and the listeners follow the state
local function updateAvailability()
  local count, picks = trialsAvailableCount(), trialsPendingPicks()
  local button = trialsButton()
  if button then
    local badge = button:getChildById('trialsBadge')
    if badge then
      badge:setText(TrialsMath.badgeText(trialsState))
      badge:setVisible(count > 0)
    end
    button:setTooltip(TrialsMath.buttonTooltip(trialsState, tr(BASE_TIP)))
    if count > 0 and not pulseEvent then
      pulse()
    elseif count == 0 then
      stopPulse()
    end
  end
  if count > 0 and count ~= lastCount then
    toastOnce()
  end
  if count ~= lastCount or picks ~= lastPicks then
    lastCount, lastPicks = count, picks
    for fn in pairs(listeners) do
      pcall(fn, count, picks)
    end
  end
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
    tip = tr('%s\nPart of this node needs the server\'s spell events.', tip)
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
    trialsWindow.trialName:setText(tr('No trial for this vocation'))
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
    row.rowTitle:setText(tr('Pair %d\n%s%s', p, entry.tier, entry.locked and tr('\n(locked)') or ''))
    row.rowTitle:setColor(entry.locked and '#8c8070' or COLOR_TITLE)
    setCard(row.cardA, s, entry, 1)
    setCard(row.cardB, s, entry, 2)
    local clearInfo = TrialsMath.clearCard(s, entry)
    row.clearButton:setEnabled(clearInfo.enabled)
    row.clearButton:setTooltip(clearInfo.tooltip)
  end
end

-- server -> client trialState
ChaosTreeHandlers.trialState = function(data)
  if type(data) ~= 'table' then
    return
  end
  trialsState = data
  refreshTrials()
  updateAvailability()
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
  confirmBox = displayGeneralBox(entry.held == 0 and tr('Choose a node') or tr('Switch node'), TrialsMath.confirmText(s, entry, side), {
    {text = tr('Ok'), callback = ok},
    {text = tr('Cancel'), callback = closeConfirm},
    anchor = AnchorHorizontalCenter
  }, ok, closeConfirm)
end

-- gives a pair up: no node held (trialChoose side 0); the server charges what a switch costs
function clearTrialPair(pair)
  local s = trialsState
  if not s or not s.supported or not s.pairs[pair] or (s.pairs[pair].held or 0) == 0 then
    return
  end
  local entry = s.pairs[pair]
  closeConfirm()
  local function ok()
    sendAction('trialChoose', {pair = pair, side = 0})
    closeConfirm()
  end
  confirmBox = displayGeneralBox(tr('Give up a node'), TrialsMath.clearConfirmText(s, entry), {
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
      row.clearButton.onClick = function()
        clearTrialPair(p)
      end
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
  if requestEvent then
    removeEvent(requestEvent)
    requestEvent = nil
  end
  stopPulse()
  updateAvailability()
end

-- asks for the state without the window (login, the level of the next difficulty)
local function requestSoon(ms)
  if requestEvent then
    return
  end
  requestEvent = scheduleEvent(function()
    requestEvent = nil
    if g_game.isOnline() then
      sendAction('trialRequest')
    end
  end, ms)
end

local function onTrialsLevel(player, level)
  if TrialsMath.needsRefresh(trialsState, level) then
    requestSoon(LEVEL_DELAY_MS)
  end
end

local function onTrialsGameStart()
  requestSoon(REQUEST_DELAY_MS)
end

function initTrials()
  connect(g_game, {onGameStart = onTrialsGameStart})
  connect(LocalPlayer, {onLevelChange = onTrialsLevel})
  if g_game.isOnline() then
    onTrialsGameStart()
  end
end

function terminateTrials()
  disconnect(g_game, {onGameStart = onTrialsGameStart})
  disconnect(LocalPlayer, {onLevelChange = onTrialsLevel})
  listeners = {}
end
