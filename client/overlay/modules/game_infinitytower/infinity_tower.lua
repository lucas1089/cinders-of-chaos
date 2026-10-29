local infinityTowerWindow = nil
local OPCODE_INFINITY_TOWER = 214
local milestoneWidgets = {}
local cachedTowerData = nil
local skipPanel = nil       -- the tower panel (floor, monsters, countdown, Next floor now): shown only inside a run
local skipButton = nil
local stateAtMs = 0
local tickEvent = nil
local towerState = nil      -- the last {action = 'state'} of the server
local lastSkipMs = nil
local AUTO_SKIP_KEY = 'chaosTowerAutoSkip' -- global per client install (the module has no per-character setting)

-- Milestones padrão espelhados do servidor, exibidos antes dos dados chegarem
local DEFAULT_MILESTONES = {
  { points = 60000,  items = { { id = 3043,  count = 30, name = "Gold Coin" } } },
  { points = 120000, items = { { id = 51964, count = 1,  name = "Prize" } } },
  { points = 180000, items = { { id = 63185, count = 1,  name = "Prize" } } },
  { points = 240000, items = { { id = 51956, count = 10, name = "Prize" } } },
  { points = 300000, items = { { id = 43895, count = 1,  name = "Prize" } } },
}

function init()
  ProtocolGame.registerExtendedOpcode(OPCODE_INFINITY_TOWER, onExtendedOpcode)

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })

  bindSkipKey()
  if g_game.isOnline() then
    onGameStart()
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })

  ProtocolGame.unregisterExtendedOpcode(OPCODE_INFINITY_TOWER)
  onGameEnd()
  unbindSkipKey()
  if tickEvent then removeEvent(tickEvent); tickEvent = nil end
  if skipPanel then
    skipPanel:destroy()
    skipPanel, skipButton = nil, nil
  end

  if infinityTowerWindow then
    infinityTowerWindow:destroy()
    infinityTowerWindow = nil
  end

  if seasonTimerEvent then
    removeEvent(seasonTimerEvent)
    seasonTimerEvent = nil
  end
end

function onGameStart()
  towerState = nil
  updateSkipButton()
  -- a relog never happens inside a run, but ask: the server answers with the state
  local protocol = g_game.getProtocolGame()
  if protocol then protocol:sendExtendedOpcode(OPCODE_INFINITY_TOWER, '{"action":"state"}') end
end

function onGameEnd()
  cachedTowerData = nil
  towerState = nil
  hide()
  updateSkipButton()
end

-- ---- Next floor now (server: infinitytower_run.lua ChaosTowerRun.skip; pure part towerskip.lua)
function gameRoot()
  local gi = modules.game_interface
  return gi and gi.getRootPanel and gi.getRootPanel() or nil
end

local function setLabel(id, text)
  local w = skipPanel and skipPanel:getChildById(id)
  if w then
    w:setText(text or '')
    w:setVisible(text ~= nil and text ~= '')
  end
end

local function refreshPanel()
  if not skipPanel then return end
  local d = TowerSkip.panel(towerState, g_clock.millis() - stateAtMs)
  if not d then return end
  setLabel('floorLabel', tr(d.floor.key, d.floor.n))
  setLabel('clearedLabel', tr(d.cleared.key, d.cleared.n))
  setLabel('monstersLabel', d.monsters and tr(d.monsters.key, d.monsters.left, d.monsters.total) or nil)
  local timerText
  if d.timer then
    timerText = d.timer.key == 'Floor time left: %s' and tr(d.timer.key, TowerSkip.clock(d.timer.secs)) or tr(d.timer.key, d.timer.secs)
  end
  setLabel('timerLabel', timerText)
end

local function tickPanel()
  tickEvent = nil
  if not skipPanel or not skipPanel:isVisible() then return end
  refreshPanel()
  tickEvent = scheduleEvent(tickPanel, 250)
end

function updateSkipButton()
  local view = TowerSkip.view(towerState)
  if view.visible and not skipPanel then
    local root = gameRoot()
    if not root then return end
    skipPanel = g_ui.createWidget('TowerPanel', root)
    skipButton = skipPanel:getChildById('skipButton')
    skipButton.onClick = function() skipFloor() end
    local autoBox = skipPanel:getChildById('autoSkipBox')
    autoBox:setChecked(autoSkipOn())
    autoBox.onCheckChange = function(_, checked)
      g_settings.set(AUTO_SKIP_KEY, checked)
      if checked then autoSkipCheck() end
    end
  end
  if not skipPanel then return end
  if not view.visible then
    skipPanel:hide()
    if tickEvent then removeEvent(tickEvent); tickEvent = nil end
    return
  end
  skipButton:setText(tr(view.key) .. ' (' .. TowerSkip.HOTKEY .. ')')
  skipButton:setTooltip(tr(view.tip))
  skipButton:setEnabled(view.enabled)
  skipPanel:show()
  refreshPanel()
  if not tickEvent then tickEvent = scheduleEvent(tickPanel, 250) end
end

function autoSkipOn()
  local ok, v = pcall(g_settings.getBoolean, AUTO_SKIP_KEY, false)
  return ok and v == true
end

-- once per pushed state (and when the box is ticked): send the skip if the pure rule allows it
function autoSkipCheck()
  local now = g_clock.millis()
  if not g_game.isOnline() or not TowerSkip.shouldAutoSkip(towerState, autoSkipOn(), lastSkipMs, now) then return end
  local protocol = g_game.getProtocolGame()
  if protocol then
    lastSkipMs = now
    protocol:sendExtendedOpcode(OPCODE_INFINITY_TOWER, '{"action":"skip"}')
  end
end

function skipFloor()
  if not g_game.isOnline() or not TowerSkip.canPress(towerState, g_clock.millis(), lastSkipMs) then return end
  local protocol = g_game.getProtocolGame()
  if protocol then
    lastSkipMs = g_clock.millis()
    protocol:sendExtendedOpcode(OPCODE_INFINITY_TOWER, '{"action":"skip"}')
  end
end

function bindSkipKey()
  local root = gameRoot()
  if root then g_keyboard.bindKeyDown(TowerSkip.HOTKEY, skipFloor, root) end
end

function unbindSkipKey()
  local root = gameRoot()
  if root then pcall(g_keyboard.unbindKeyDown, TowerSkip.HOTKEY, root) end
end

function onExtendedOpcode(protocol, opcode, buffer)
  local data = json.decode(buffer)
  if not data then return end

  if data.action == "state" then
    towerState = data
    stateAtMs = g_clock.millis()
    updateSkipButton()
    autoSkipCheck()
  elseif data.action == "open" then
    cachedTowerData = data
    show(data)
  elseif data.action == "update" then
    cachedTowerData = data
    if infinityTowerWindow and infinityTowerWindow:isVisible() then
      scheduleEvent(function()
        if data.milestones then
          populateMilestones(data.milestones, data.playerPoints or 0)
        end
        if data.rankings then
          populateRankings(data.rankings)
        end
        if data.topRewards then
          populatePodium(data.topRewards)
        end
        populateSeasonInfos(data)
      end, 50)
    end
  end
end

local function fixAcentos(str)
  return str:fixEncoding()
end

function setupDescription()
  local descLabel = infinityTowerWindow:recursiveGetChildById('descriptionLabel')
  if not descLabel then return end

  local text = [[[color=#f75f5f]Welcome to the Infinity Tower![/color]

The Infinity Tower is a solo challenge where you will face increasingly powerful waves of monsters. Push your limits and see how far you can go!

[color=#f75f5f]How It Works:[/color]
- Pull the [color=#f75f5f]lever[/color] to start the event and enter your exclusive instance.
- Each floor has [color=#f75f5f]3 waves[/color] of monsters that must be defeated.
- After clearing all waves, you will earn [color=#f75f5f]Tower Points[/color] and may choose to advance to the next floor or leave.
- Difficulty [color=#f75f5f]scales progressively[/color] with each new floor reached.

[color=#f75f5f]Rewards and Scoring:[/color]
- Each completed floor grants [color=#f75f5f]Experience immediately[/color].
- You will also accumulate [color=#f75f5f]Tower Points[/color] for every floor cleared.
- Reaching Tower Point milestones will unlock [color=#f75f5f]special rewards[/color] on the progress bar below.
- Simply click the [color=#f75f5f]"Claim"[/color] button to collect your exclusive rewards!
- At the end of each season, the [color=#f75f5f]top 3 players[/color] will receive the [color=#f75f5f]"Top Rank Rewards"[/color] chests with exclusive prizes!

[color=#f75f5f]Important Rules:[/color]
- If you die during the event, [color=#f75f5f]you will not lose any level or skills[/color]. You will be healed and safely returned to the temple.
- Your time is tracked! Try to reach [color=#f75f5f]as high as possible in the shortest time[/color] to earn a spot on the Ranking (Top 10).
- The Ranking updates [color=#f75f5f]immediately[/color] whenever you beat your own record of [color=#f75f5f]Highest Floor or Best Time[/color].

[color=#f75f5f]Tip:[/color] Prepare well before entering! Bring potions, proper equipment, and good luck!]]

  descLabel:parseColoredText(text, '#ffffff')
end

function enterTower()
  local protocol = g_game.isOnline() and g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE_INFINITY_TOWER, '{"action":"enter"}')
    hide()
  end
end

function leaveTower()
  local protocol = g_game.isOnline() and g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE_INFINITY_TOWER, '{"action":"leave"}')
    hide()
  end
end

function toggle()
  if infinityTowerWindow and infinityTowerWindow:isVisible() then
    hide()
  else
    show(cachedTowerData)
    if g_game.isOnline() then
      local protocol = g_game.getProtocolGame()
      if protocol then
        protocol:sendExtendedOpcode(OPCODE_INFINITY_TOWER, '{"action":"request"}')
      end
    end
  end
end

function showLoadingState()
  local seasonLabel = infinityTowerWindow:recursiveGetChildById('seasonLabel')
  if seasonLabel then seasonLabel:setText(tr('Current Season: --')) end
  local endLabel = infinityTowerWindow:recursiveGetChildById('seasonEndLabel')
  if endLabel then endLabel:setText(tr('Season Ends In: --')) end
  local tryLabel = infinityTowerWindow:recursiveGetChildById('nextTryLabel')
  if tryLabel then tryLabel:setText(tr('Next Try Available: --')) end
  local pointsLabel = infinityTowerWindow:recursiveGetChildById('towerPointsLabel')
  if pointsLabel then pointsLabel:setText(tr('Your Tower Points: 0')) end

  populateMilestones(DEFAULT_MILESTONES, 0)
end

function show(data)
  if not infinityTowerWindow then
    infinityTowerWindow = g_ui.displayUI('infinity_tower')
    pcall(function() modules.game_howitworks.attach(infinityTowerWindow, 'tower') end) -- game_howitworks: the ? button
    if not infinityTowerWindow then return end
    setupDescription()
    populatePodium()
  end

  infinityTowerWindow:show()
  infinityTowerWindow:raise()
  infinityTowerWindow:focus()
  startShimmer()

  if data then
    -- Delay to ensure layout is calculated
    scheduleEvent(function()
      if data.milestones then
        populateMilestones(data.milestones, data.playerPoints or 0)
      end
      if data.rankings then
        populateRankings(data.rankings)
      end
      if data.topRewards then
        populatePodium(data.topRewards)
      end
      populateSeasonInfos(data)
    end, 50)
  else
    scheduleEvent(showLoadingState, 50)
  end
end

function hide()
  stopShimmer()
  if seasonTimerEvent then
    removeEvent(seasonTimerEvent)
    seasonTimerEvent = nil
  end
  if infinityTowerWindow then
    infinityTowerWindow:hide()
  end
end

-- The "Top Rank Rewards" podium: the chests the top 3 get at the season end (server: infinitytower.lua, Chaos.tower
-- seasonEnd). The server sends them as topRewards {place, name, id = the chest's client id, text}; until then the
-- stock chest looks of the server config are shown (treasure chest, chest, box of the 10.98 items).
local DEFAULT_TOP_REWARDS = {
  { place = 1, name = 'Gold Tower Chest', id = 2478 },
  { place = 2, name = 'Silver Tower Chest', id = 2472 },
  { place = 3, name = 'Copper Tower Chest', id = 2469 },
}

function populatePodium(topRewards)
  if not infinityTowerWindow then return end
  for _, entry in ipairs(topRewards or DEFAULT_TOP_REWARDS) do
    local place = tonumber(entry.place)
    local item = place and infinityTowerWindow:recursiveGetChildById('podiumItem' .. place)
    if item and tonumber(entry.id) then
      item:setItemId(tonumber(entry.id))
    end
    local slot = place and infinityTowerWindow:recursiveGetChildById('rewardSlot' .. place)
    if slot then
      slot:setTooltip(tostring(entry.text or entry.name or ''))
    end
  end
end

function clearMilestoneWidgets()
  for _, w in ipairs(milestoneWidgets) do
    if w and not w:isDestroyed() then
      w:destroy()
    end
  end
  milestoneWidgets = {}
end

function populateMilestones(milestones, playerPoints)
  local track = infinityTowerWindow:recursiveGetChildById('milestoneTrack')
  local progressPanel = infinityTowerWindow:recursiveGetChildById('pointsProgress')
  if not track or not progressPanel then return end

  clearMilestoneWidgets()

  local maxPoints = milestones[#milestones] and milestones[#milestones].points or 1
  local barWidth = progressPanel:getWidth()
  local barX = progressPanel:getX() - track:getX()
  local barY = progressPanel:getY() - track:getY()

  for i, milestone in ipairs(milestones) do
    local ratio = milestone.points / maxPoints
    local xPos = barX + math.floor(ratio * barWidth)

    -- White vertical divider above the bar (grows upward, does not enter the bar)
    local divider = g_ui.createWidget('UIWidget', track)
    divider:setId('milestoneDivider' .. i)
    divider:setSize({width = 2, height = 50})
    divider:setBackgroundColor('#ffffffcc')
    divider:addAnchor(AnchorBottom, 'pointsProgress', AnchorTop)
    divider:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    divider:setMarginBottom(0)
    divider:setMarginLeft(xPos - 1)
    table.insert(milestoneWidgets, divider)

    -- Points label above the item slot
    local pointsStr = formatShortNumber(milestone.points)
    local pointsLbl = g_ui.createWidget('UIWidget', track)
    pointsLbl:setId('milestonePoints' .. i)
    pointsLbl:setSize({width = 50, height = 12})
    pointsLbl:setText(tr('%s pts', pointsStr))
    pointsLbl:setFont('cipsoftFont')
    pointsLbl:setColor('#ffda34')
    pointsLbl:setTextAlign(AlignCenter)
    pointsLbl:addAnchor(AnchorBottom, 'pointsProgress', AnchorTop)
    pointsLbl:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    pointsLbl:setMarginBottom(58)
    pointsLbl:setMarginLeft(xPos - 25)
    table.insert(milestoneWidgets, pointsLbl)

    -- Item slot above the bar
    local itemSlot = g_ui.createWidget('TowerRewardItem', track)
    itemSlot:setId('milestoneItem' .. i)
    itemSlot:addAnchor(AnchorBottom, 'pointsProgress', AnchorTop)
    itemSlot:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    itemSlot:setMarginBottom(12)
    itemSlot:setMarginLeft(xPos - 17)
    table.insert(milestoneWidgets, itemSlot)

    -- Set item data
    local firstItem = milestone.items and milestone.items[1]
    if firstItem then
      local itemWidget = itemSlot:getChildById('item')
      if itemWidget then
        itemWidget:setItemId(firstItem.id)
        itemWidget:setItemCount(firstItem.count)
      end
      local tooltipText = firstItem.name or 'Item'
      if firstItem.count > 1 then
        tooltipText = firstItem.count .. 'x ' .. tooltipText
      end
      itemSlot:setTooltip(tooltipText)
    end

    -- Dim if claimed
    if milestone.claimed then
      itemSlot:setOpacity(0.4)
    end

    -- Claim button below the bar
    local claimBtn = g_ui.createWidget('Button', track)
    claimBtn:setId('claimBtn' .. i)
    claimBtn:setSize({width = 43, height = 20})
    claimBtn:setText(tr('Claim'))
    claimBtn:setFont('cipsoftFont')
    claimBtn:addAnchor(AnchorTop, 'pointsProgress', AnchorBottom)
    claimBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    claimBtn:setMarginTop(4)
    claimBtn:setMarginLeft(xPos - 21)
    table.insert(milestoneWidgets, claimBtn)

    -- Enable/disable based on points and claimed status
    if milestone.claimed then
      claimBtn:setEnabled(false)
      claimBtn:setText(tr('Done'))
    elseif playerPoints >= milestone.points then
      claimBtn:setEnabled(true)
      claimBtn.onClick = function()
        -- Send claim request to server
        if ProtocolGame then
          local protocol = g_game.getProtocolGame()
          if protocol then
            local payload = '{"action":"claim", "milestoneIndex":' .. i .. '}'
            protocol:sendExtendedOpcode(214, payload)
          end
        end
      end
    else
      claimBtn:setEnabled(false)
    end
  end

  -- Update progress bar
  local progressBar = infinityTowerWindow:recursiveGetChildById('progressBar')
  local progressLabel = infinityTowerWindow:recursiveGetChildById('progressLabel')

  if progressBar and progressLabel then
    local percent = math.min(playerPoints / maxPoints, 1.0)
    local fillWidth = math.floor((barWidth - 6) * percent)
    progressBar:setWidth(fillWidth)
    progressLabel:setText(tr('%s / %s pts', formatShortNumber(playerPoints), formatShortNumber(maxPoints)))
    progressLabel:setTooltip(tr('%s / %s pts', comma_value(playerPoints), comma_value(maxPoints)))
  end
end

function populateRankings(rankings)
  local rankList = infinityTowerWindow:recursiveGetChildById('rankList')
  if not rankList then return end

  rankList:destroyChildren()

  if not rankings or #rankings == 0 then return end

  local rankColors = { '#FFD700', '#C0C0C0', '#CD7F32' }

  for i, rankData in ipairs(rankings) do
    local row = g_ui.createWidget('TowerRankRow', rankList)
    if not row then break end

    local color = rankColors[i] or '#FFFFFF'

    local rankWidget = row:getChildById('rank')
    if rankWidget then
      rankWidget:setText(tostring(i))
      rankWidget:setColor(color)
    end

    local nameWidget = row:getChildById('name')
    if nameWidget then
      nameWidget:setText(rankData.name or '')
      nameWidget:setColor(color)
    end

    local floorWidget = row:getChildById('floor')
    if floorWidget then
      floorWidget:setText(formatShortNumber(rankData.floor or 0))
    end

    local timeWidget = row:getChildById('time')
    if timeWidget then
      local t = rankData.time or 0
      timeWidget:setText(string.format('%02d:%02d', math.floor(t / 60), t % 60))
    end
  end
end

-- Shimmer animation
local shimmerEvent = nil
local shimmerDirection = -1
local shimmerOpacity = 1.0

function startShimmer()
  if shimmerEvent then return end

  local function animate()
    if not infinityTowerWindow then return end
    local label = infinityTowerWindow:recursiveGetChildById('topRankLabel')
    if not label then return end

    shimmerOpacity = shimmerOpacity + (shimmerDirection * 0.03)
    if shimmerOpacity <= 0.4 then
      shimmerOpacity = 0.4
      shimmerDirection = 1
    elseif shimmerOpacity >= 1.0 then
      shimmerOpacity = 1.0
      shimmerDirection = -1
    end

    label:setOpacity(shimmerOpacity)
    shimmerEvent = scheduleEvent(animate, 50)
  end

  animate()
end

function stopShimmer()
  if shimmerEvent then
    removeEvent(shimmerEvent)
    shimmerEvent = nil
  end
end

local seasonTimerEvent = nil

local function formatTimeRemaining(seconds)
    if seconds <= 0 then return "Now" end
    local days = math.floor(seconds / (24 * 60 * 60))
    local hours = math.floor((seconds % (24 * 60 * 60)) / (60 * 60))
    local minutes = math.floor((seconds % (60 * 60)) / 60)
    local secs = seconds % 60
    
    if days > 0 then
        return tr("%d days, %02d:%02d:%02d", days, hours, minutes, secs)
    else
        return string.format("%02d:%02d:%02d", hours, minutes, secs)
    end
end

-- "5 Crystal Coin, 2 Orb of Upheaval" from the server's {count, name} list
local function rewardItemsText(items)
  local parts = {}
  for _, it in ipairs(items or {}) do
    parts[#parts + 1] = string.format('%d %s', it.count or 0, it.name or '?')
  end
  return table.concat(parts, ', ')
end

-- the next milestone floor of the tower and what it pays (floorRewards of the server payload, O144)
function populateNextReward(floorRewards)
  if not infinityTowerWindow then return end
  local label = infinityTowerWindow:recursiveGetChildById('nextRewardLabel')
  if not label then return end
  if not floorRewards or not floorRewards.nextFloor then
    label:setText(tr('Next reward: --'))
    return
  end
  local lines = { tr('Next reward: floor %s', floorRewards.nextFloor) }
  local first = rewardItemsText(floorRewards.first)
  if first ~= '' then
    lines[#lines + 1] = tr('First clear this season: %s', first)
  end
  local again = rewardItemsText(floorRewards.repeatable)
  if again ~= '' then
    lines[#lines + 1] = tr('Every clear: %s', again)
  end
  label:setText(table.concat(lines, '\n'))
end

function populateSeasonInfos(data)
  if not infinityTowerWindow then return end
  populateNextReward(data.floorRewards)
  local seasonLabel = infinityTowerWindow:recursiveGetChildById('seasonLabel')
  local endLabel = infinityTowerWindow:recursiveGetChildById('seasonEndLabel')
  local tryLabel = infinityTowerWindow:recursiveGetChildById('nextTryLabel')
  local pointsLabel = infinityTowerWindow:recursiveGetChildById('towerPointsLabel')
  
  if seasonLabel then seasonLabel:setText(tr('Current Season: %s', (data.seasonNum or 1))) end
  if pointsLabel then
    pointsLabel:setText(tr('Your Tower Points: %s', formatShortNumber(data.playerPoints or 0)))
    pointsLabel:setTooltip(tr('Your Tower Points: %s', comma_value(data.playerPoints or 0)))
  end
  
  -- Clear existing timer
  if seasonTimerEvent then
    removeEvent(seasonTimerEvent)
    seasonTimerEvent = nil
  end
  
  local targetSeasonEnd = data.seasonEnd or 0
  local targetNextTry = data.nextTry or 0
  
  local function updateTimers()
      if not infinityTowerWindow or not infinityTowerWindow:isVisible() then
          seasonTimerEvent = nil
          return
      end
      
      local now = os.time()
      if endLabel then
          local remainEnd = targetSeasonEnd - now
          if remainEnd > 0 then
              endLabel:setText(tr('Season Ends In: %s', formatTimeRemaining(remainEnd)))
          else
              endLabel:setText(tr("Season Ends In: Finished"))
          end
      end
      
      if tryLabel then
          local remainTry = targetNextTry - now
          if remainTry > 0 then
              tryLabel:setText(tr('Next Try Available: %s', formatTimeRemaining(remainTry)))
          else
              tryLabel:setText(tr("Next Try Available: Ready Now!"))
          end
      end
      
      seasonTimerEvent = scheduleEvent(updateTimers, 1000)
  end
  
  updateTimers()
end
