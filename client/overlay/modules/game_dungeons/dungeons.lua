local CODE = 109

local window = nil
local windowButton = nil
local dungeonInfo = nil
local killCounter = nil
local challengeNotifi = nil

local Dungeons = {}
local selectedDungeonId = nil
local selectedDifficulty = 1
local queueTime = 0
local timerEvent = nil
local timeLeft = 0
local timeLeftEvent = nil
local bossUnlocked = false
local bossNeed = 85 -- percent of the run's monsters that unlock the boss (the server's `need` in "start")

local pendingDifficulty = nil
local difficultyUpdateTimer = nil
local lastDifficultyId = nil

local pendingInitialDungeonId = nil
local pendingDungeonId = nil
local dungeonUpdateTimer = nil
local isApplyingDungeon = false
local selectionCooldownActive = false
local queuedSelection = nil
local selectionCooldownEnds = 0
local cooldownHint = nil
local selectionCooldownEvent = nil
local currentUI = {}

function init()
  connect(
    g_game,
    {
      onGameStart = create,
      onGameEnd = destroy
    }
  )

  ProtocolGame.registerExtendedOpcode(CODE, onExtendedOpcode)

  if g_game.isOnline() then
    create()
  end
end

function terminate()
  disconnect(
    g_game,
    {
      onGameStart = create,
      onGameEnd = destroy
    }
  )

  ProtocolGame.unregisterExtendedOpcode(CODE, onExtendedOpcode)

  destroy()
end

function create()
  if window then return end
  window = g_ui.displayUI("dungeons")
  window:hide()
  windowButton = modules.client_topmenu.addRightGameToggleButton("dungeonsButton", tr("Dungeons Finder"), "/images/topbuttons/dungeon", toggle)
  windowButton:setOn(false)

  dungeonInfo = window:getChildById("dungeonInfo")

  killCounter = g_ui.loadUI("killcounter", modules.game_interface.getMapPanel())
  killCounter:hide()

  challengeNotifi = g_ui.loadUI("challenge", modules.game_interface.getMapPanel())
  g_effects.fadeOut(challengeNotifi, 1)

  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:sendExtendedOpcode(CODE, json.encode({action = "fetch"}))
  end
end

function destroy()
  if windowButton then
    windowButton:destroy()
    windowButton = nil
  end

  if window then
    if timerEvent then
      removeEvent(timerEvent)
    end
    timerEvent = nil
    dungeonInfo = nil
    selectedDungeonId = nil
    selectedDifficulty = 1
    queueTime = 0
    Dungeons = {}

    if timeLeftEvent then
      removeEvent(timeLeftEvent)
    end
    timeLeftEvent = nil
    timeLeft = 0

    window:destroy()
    window = nil
  end

  if killCounter then
    killCounter:destroy()
    killCounter = nil
  end

  if challengeNotifi then
    challengeNotifi:destroy()
    challengeNotifi = nil
  end

  pendingDifficulty = nil
  if difficultyUpdateTimer then
    removeEvent(difficultyUpdateTimer)
    difficultyUpdateTimer = nil
  end
  lastDifficultyId = nil
  pendingDungeonId = nil
  if dungeonUpdateTimer then
    removeEvent(dungeonUpdateTimer)
    dungeonUpdateTimer = nil
  end
  isApplyingDungeon = false
  currentUI = {}
end

function safeRecursiveGet(parent, id)
  if not parent then return nil end
  return parent:recursiveGetChildById(id)
end

function onExtendedOpcode(protocol, code, buffer)
  if not g_game.isOnline() then
    return
  end
  local json_status, json_data =
    pcall(
    function()
      return json.decode(buffer)
    end
  )

  if not json_status then
    g_logger.error("[Dungeons] JSON error: " .. json_data)
    return false
  end

  local action = json_data.action
  local data = json_data.data

  if action == "list" then
    onDungeonsList(data)
  elseif action == "dungeon" then
    onDungeonData(data)
  elseif action == "solo" then
    onSoloRunners(data)
  elseif action == "group" then
    onGroupRunners(data)
  elseif action == "queue" then
    onDungeonQueue(data)
  elseif action == "prepare" then
    onDungeonPrepare()
  elseif action == "start" then
    onDungeonStart(data)
  elseif action == "finish" then
    onDungeonFinish(data)
  elseif action == "objective" then
    onDungeonObjective(data)
  elseif action == "killed" then
    onDungeonKilled(data)
  elseif action == "queueUpdate" then
    onDungeonQueueUpdate(data)
  elseif action == "difficulty" then
    onDungeonDifficulty(data)
  elseif action == "challenge" then
    onChallengeCompleted(data)
  elseif action == "stopQueue" then
    onStopQueue()
  elseif action == "open" then
    -- the dungeon entry tile was stepped on
    show()
    if windowButton then
      windowButton:setOn(true)
    end
  end
end

function onDungeonsList(data)
  local dungeonsMenus = window:getChildById("dungeonsMenu")
  dungeonsMenus.onChildFocusChange = onDungeonSelected

  dungeonsMenus:destroyChildren()
  table.sort(data, function(a, b) return a.level < b.level end)
  for i = 1, #data do
    local dungeon = data[i]
    local dungeonMenu = g_ui.createWidget("DungeonMenuItem", dungeonsMenus)
    dungeonMenu:setId("dungeon" .. dungeon.id)
    local boss = dungeonMenu:getChildById("boss")
    local title = dungeonMenu:getChildById("title")
    local level = dungeonMenu:getChildById("level")
    local queue = dungeonMenu:getChildById("queue")
    boss:setOutfit(dungeon.boss)
    title:setText(dungeon.title)
    level:setText(tr('%s+ Level', formatShortNumber(dungeon.level)))
    queue:setText(tr('Queue: %s', (dungeon.queue == 0 and tr("Open") or tr('%s Players', dungeon.queue))))
    if dungeon.queue >= 6 then
      queue:setColor("red")
    elseif dungeon.queue >= 3 then
      queue:setColor("orange")
    else
      queue:setColor("green")
    end
    dungeonMenu = nil
  end
  if #data > 0 then
    local firstDungeonId = data[1].id
    local firstChild = dungeonsMenus:getChildById("dungeon" .. firstDungeonId)
    if firstChild then
      dungeonsMenus.onChildFocusChange = nil
      dungeonsMenus:focusChild(firstChild)
      dungeonsMenus.onChildFocusChange = onDungeonSelected

      if Dungeons[firstDungeonId] then
        selectDungeon(firstDungeonId)
      else
        pendingInitialDungeonId = firstDungeonId
      end
    end
  end
end

local function applyRequirementsUI(dungeon)
  if not dungeon then return end
  local panel = currentUI.requirementsPanel
  if not panel then return end

  local req = dungeon.req or {}
  local reqTable = { "level", "party", "iLvl", "gold", "quests", "items" }

  for i, key in ipairs(reqTable) do
    local parent = panel:getChildByIndex(i)
    local hasRequirement = false

    if key == "items" then
      if req.items then
        for j = 1, 6 do
          if req.items[j] then
            hasRequirement = true
            break
          end
        end
      end
    else
      hasRequirement = req[key] ~= nil
    end

    if parent then
      if hasRequirement then
        parent:enable()
      else
        parent:disable()
        local child = parent:recursiveGetChildById(key)
        if child and key ~= "items" and key ~= "quests" then
          child:setText("")
        end
        if key == "quests" and parent:recursiveGetChildById("quests") then
          parent:recursiveGetChildById("quests"):setText("")
        end
      end
    end
  end

  if req.gold then
    local widget = panel:recursiveGetChildById("gold")
    if widget then
      widget:setText(formatShortNumber(req.gold))
      widget:setTooltip(comma_value(req.gold))
    end
  end

  if type(req.items) == "table" then
    local widget = panel:recursiveGetChildById("items")
    if widget then
      for i = 1, 6 do
        local slot = widget:getChildByIndex(i)
        local reqItem = req.items[i]
        if slot then
          if reqItem then
            slot:setItemId(reqItem.clientId)
            slot:setItemCount(reqItem.count)
          else
            slot:setItem(nil)
          end
        end
      end
    end
  end

  if type(req.quests) == "table" then
    local widget = panel:recursiveGetChildById("quests")
    if widget then
      if #req.quests > 0 then
        widget:setText(table.concat(req.quests, ", ") .. ".")
      else
        widget:setText("")
      end
    end
  end

  for _, key in ipairs({ "level", "party", "iLvl" }) do
    if req[key] ~= nil then
      local widget = panel:recursiveGetChildById(key)
      if widget then
        widget:setText(type(req[key]) == "number" and formatShortNumber(req[key]) or req[key])
      end
    end
  end
end

function onDungeonData(data)
  if type(data) ~= "table" then
    g_logger.error("[Dungeons] onDungeonData: expected table, got " .. type(data))
    return
  end

  if not data.id then
    local function shallowDump(t)
      if type(t) ~= "table" then return tostring(t) end
      local parts = {}
      for k, _ in pairs(t) do
        table.insert(parts, tostring(k))
      end
      return "keys(" .. table.concat(parts, ",") .. ")"
    end
    g_logger.error("[Dungeons] onDungeonData: missing id in payload: " .. shallowDump(data))
    return
  end

  Dungeons[data.id] = data

  if pendingInitialDungeonId == data.id then
    selectDungeon(data.id)
    pendingInitialDungeonId = nil
  end
end

function onSoloRunners(data)
  local dungeonId = data.id
  local difficulty = data.diff
  local dungeon = Dungeons[dungeonId]
  if not dungeon then return end
  dungeon.solo = dungeon.solo or {}
  dungeon.solo[difficulty] = data.top
end

function onGroupRunners(data)
  local dungeonId = data.id
  local difficulty = data.diff
  local dungeon = Dungeons[dungeonId]
  if not dungeon then return end
  dungeon.group = dungeon.group or {}
  dungeon.group[difficulty] = data.top
end

function refreshMenuQueueColor(menuDungeon)
  if not menuDungeon then return end
  local idStr = menuDungeon:getId()
  local dungeonId = tonumber(idStr and idStr:match("^dungeon(%d+)$"))
  local dungeon = dungeonId and Dungeons[dungeonId]
  if not dungeon then return end

  local queueLabel = menuDungeon:getChildById("queue")
  if not queueLabel then return end

  local queuePlayers
  if type(dungeon.queue) == "table" then
    queuePlayers = dungeon.queue.players or 0
  else
    queuePlayers = dungeon.queue or 0
  end

  queueLabel:setText(tr('Queue: %s', (queuePlayers == 0 and tr("Open") or tr('%s Players', queuePlayers))))
  if queuePlayers >= 6 then
    queueLabel:setColor("red")
  elseif queuePlayers >= 3 then
    queueLabel:setColor("orange")
  else
    queueLabel:setColor("green")
  end
end

function setDungeonMenuInteractable(enabled)
  local dungeonsMenus = window and window:getChildById("dungeonsMenu")
  if not dungeonsMenus then return end
  for i = 1, dungeonsMenus:getChildCount() do
    local child = dungeonsMenus:getChildByIndex(i)
    if child then
      if enabled then
        child:enable()
        refreshMenuQueueColor(child)
      else
        child:disable()
      end
    end
  end
end

function startSelectionCooldown()
  selectionCooldownActive = true
  selectionCooldownEnds = os.time() + 2
  setDungeonMenuInteractable(false)
  scheduleEvent(function()
    selectionCooldownActive = false
    setDungeonMenuInteractable(true)
    if queuedSelection and queuedSelection ~= selectedDungeonId then
      local pending = queuedSelection
      queuedSelection = nil
      doSelection(pending)
    end
  end, 2000)
end

function beginSelectionCooldown()
  if selectionCooldownEvent then
    removeEvent(selectionCooldownEvent)
    selectionCooldownEvent = nil
  end

  selectionCooldownActive = true
  selectionCooldownEnds = os.time() + 2

  setDungeonMenuInteractable(false)

  selectionCooldownEvent = scheduleEvent(function()
    selectionCooldownEvent = nil
    if not window then return end

    selectionCooldownActive = false
    setDungeonMenuInteractable(true)

    if queuedSelection and queuedSelection ~= selectedDungeonId then
      local pending = queuedSelection
      queuedSelection = nil
      doSelection(pending)
    end
  end, 2000)
end

function doSelection(dungeonId)
  if selectedDungeonId == dungeonId or isApplyingDungeon then return end

  if selectionCooldownActive then
    queuedSelection = dungeonId
    return
  end

  isApplyingDungeon = true

  local ok, err = xpcall(function()
    selectDungeon(dungeonId)
    beginSelectionCooldown()
  end, debug.traceback)

  if not ok then
    g_logger.error("doSelection error: " .. err)
    selectionCooldownActive = false
    if selectionCooldownEvent then
      removeEvent(selectionCooldownEvent)
      selectionCooldownEvent = nil
    end
    setDungeonMenuInteractable(true)
    queuedSelection = nil
  end

  isApplyingDungeon = false
end

function onDungeonSelected(parent, child, reason)
  if not child then return end
  local idStr = child:getId()
  if not idStr then return end
  local dungeonId = tonumber(idStr:match("^dungeon(%d+)$"))
  if not dungeonId then return end

  doSelection(dungeonId)
end

-- banner art lives in /images/dungeons/<short name>.png; the server sends the full title
local BANNERS = {
  ["Bones Dungeon"] = "Bones",
  ["Master of the Elements"] = "MasterElement",
  ["Forbidden Chevalier"] = "Forbidden",
  ["Rootmaw"] = "Rootmaw",
  ["Underworld"] = "Underworld"
}

function bannerFor(title)
  title = tostring(title or "")
  local candidates = { BANNERS[title], title, title:match("^(%S+)") }
  for _, name in ipairs(candidates) do
    if name and g_resources.fileExists("/images/dungeons/" .. name .. ".png") then
      return "/images/dungeons/" .. name
    end
  end
  return "/images/dungeons/Underworld"
end

function selectDungeon(dungeonId)
  local dungeon = Dungeons[dungeonId]
  if not dungeon then return end
  if selectedDungeonId == dungeonId then return end

  selectedDungeonId = dungeonId

  currentUI.difficultiesPanel = dungeonInfo:getChildById("difficulties")
  currentUI.requirementsPanel = dungeonInfo:getChildById("requirements")
  currentUI.bossLootPanel = dungeonInfo:getChildById("bossLoot")
  currentUI.queueStatus = dungeonInfo:recursiveGetChildById("queueStatus")
  currentUI.queueTime = dungeonInfo:recursiveGetChildById("queueTime")
  currentUI.queueWaiting = dungeonInfo:recursiveGetChildById("queueWaiting")
  currentUI.challengesPanel = dungeonInfo:getChildById("challenges")
  currentUI.soloTable = window and window:recursiveGetChildById("soloTable") or nil
  currentUI.groupTable = window and window:recursiveGetChildById("groupTable") or nil

  dungeonInfo:getChildById("banner"):setImageSource(bannerFor(dungeon.title))

  if currentUI.difficultiesPanel then
    if currentUI.difficultiesPanel:getChildCount() >= 1 then
      currentUI.difficultiesPanel:focusChild(currentUI.difficultiesPanel:getChildByIndex(1))
    end
    for i = 2, 6 do
      local diffWidget = currentUI.difficultiesPanel:getChildByIndex(i)
      if diffWidget then
        if dungeon.difficulty < i then
          diffWidget:disable()
          diffWidget:getChildById("lockBg"):show()
          diffWidget:getChildById("lockImg"):show()
        else
          diffWidget:enable()
          diffWidget:getChildById("lockBg"):hide()
          diffWidget:getChildById("lockImg"):hide()
        end
      end
    end
  end

  applyRequirementsUI(dungeon)

  if currentUI.bossLootPanel then
    for i = 1, 28 do
      local slot = currentUI.bossLootPanel:getChildByIndex(i)
      if dungeon.loot[i] then
        local loot = dungeon.loot[i]
        slot:setItemId(loot.clientId)
        slot:setItemCount(loot.count)
      else
        slot:setItem(nil)
      end
    end
  end

  if currentUI.queueStatus then
    local queuePlayers = dungeon.queue.players
    currentUI.queueStatus:setText(queuePlayers == 0 and tr("Open") or tr('%s Players', queuePlayers))
    if queuePlayers >= 6 then
      currentUI.queueStatus:setColor("red")
    elseif queuePlayers >= 3 then
      currentUI.queueStatus:setColor("orange")
    else
      currentUI.queueStatus:setColor("green")
    end
  end
  if currentUI.queueTime then
    currentUI.queueTime:setText(SecondsToShortTime(dungeon.queue.estimated / 1000))
  end
  if currentUI.queueWaiting then
    currentUI.queueWaiting:setText("00:00:00")
  end

  if currentUI.challengesPanel then
    currentUI.challengesPanel:destroyChildren()
    for i = 1, #dungeon.challenges do
      local challenge = dungeon.challenges[i]
      local widget = g_ui.createWidget("ChallengePanel", currentUI.challengesPanel)
      widget:setText(tr('%s (%s Points)', challenge.title, formatShortNumber(challenge.points)))
      widget:getChildById("checkbox"):setChecked(challenge.completed)
      widget:getChildById("description"):setText(challenge.desc)
    end
  end

  lastDifficultyId = nil
  onDifficultyFocus(dungeon.difficulty or 1, true)
end

function onDifficultyFocus(difficultyId, focused)
  if not focused then return end
  if selectedDifficulty == difficultyId and lastDifficultyId == difficultyId then
    return
  end

  pendingDifficulty = difficultyId
  if difficultyUpdateTimer then
    removeEvent(difficultyUpdateTimer)
    difficultyUpdateTimer = nil
  end

  difficultyUpdateTimer = scheduleEvent(function()
    difficultyUpdateTimer = nil
    local diff = pendingDifficulty
    pendingDifficulty = nil
    if not diff then return end
    if lastDifficultyId == diff then return end

    selectedDifficulty = diff
    lastDifficultyId = diff
    local dungeon = Dungeons[selectedDungeonId]
    if not dungeon then return end

    local soloTable = currentUI.soloTable or window:recursiveGetChildById("soloTable")
    local groupTable = currentUI.groupTable or window:recursiveGetChildById("groupTable")
    if soloTable then
      soloTable:clearData()
      if dungeon.solo and dungeon.solo[diff] then
        for i, runner in ipairs(dungeon.solo[diff]) do
          if runner.self then
            soloTable:addRow(
              {
                {text = runner.self},
                {text = runner.name},
                {text = MsToShortTime(runner.time)}
              },
              nil,
              "#2daadb"
            )
          else
            soloTable:addRow(
              {
                {text = i},
                {text = runner.name},
                {text = MsToShortTime(runner.time)}
              }
            )
          end
        end
      end
    end

    if groupTable then
      groupTable:clearData()
      if dungeon.group and dungeon.group[diff] then
        for i, group in ipairs(dungeon.group[diff]) do
          local names = select(2, string.gsub(group.name, "\n", ""))
          local height = names * 21
          if names == 1 then
            height = height + 8
          end
          if group.self then
            groupTable:addRow(
              {
                {text = group.self},
                {text = group.name},
                {text = MsToShortTime(group.time)}
              },
              height,
              "#2daadb"
            )
          else
            groupTable:addRow(
              {
                {text = i},
                {text = group.name},
                {text = MsToShortTime(group.time)}
              },
              height
            )
          end
        end
      end
    end
  end, 50)
end

function joinQueue()
  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:sendExtendedOpcode(CODE, json.encode({action = "queue", data = {id = selectedDungeonId, difficulty = selectedDifficulty}}))
  end
end

function onDungeonQueue(data)
  if not dungeonInfo then return end
  local queueWaiting = safeRecursiveGet(dungeonInfo, "queueWaiting")
  if queueWaiting then queueWaiting:setText("00:00:00") end
  queueTime = 0

  local queueDungeon = safeRecursiveGet(dungeonInfo, "queueDungeon")
  local queueButton = safeRecursiveGet(dungeonInfo, "queueButton")
  if not queueDungeon or not queueButton then return end

  if data.joined then
    queueButton:setText(tr("Leave"))
    local dungeon = Dungeons[data.id]
    if dungeon then
      queueDungeon:setText(dungeon.title)
    end
    if timerEvent then removeEvent(timerEvent) end
    timerEvent = scheduleEvent(queueTimer, 1000)
  else
    queueButton:setText(tr("Join"))
    queueDungeon:setText("------")
    if timerEvent then
      removeEvent(timerEvent)
      timerEvent = nil
    end
  end
end

function onStopQueue()
  if not dungeonInfo then return end
  local queueWaiting = safeRecursiveGet(dungeonInfo, "queueWaiting")
  if queueWaiting then queueWaiting:setText("00:00:00") end
  queueTime = 0

  local queueDungeon = safeRecursiveGet(dungeonInfo, "queueDungeon")
  local queueButton = safeRecursiveGet(dungeonInfo, "queueButton")
  if queueButton then queueButton:setText(tr("Join")) end
  if queueDungeon then queueDungeon:setText("------") end
  if timerEvent then
    removeEvent(timerEvent)
    timerEvent = nil
  end
end

function queueTimer()
  if not dungeonInfo then return end
  local queueWaiting = safeRecursiveGet(dungeonInfo, "queueWaiting")
  queueTime = queueTime + 1
  if queueWaiting then
    queueWaiting:setText(SecondsToShortTime(queueTime))
  end
  if timerEvent then removeEvent(timerEvent) end
  timerEvent = scheduleEvent(queueTimer, 1000)
end

function onDungeonPrepare()
  onStopQueue()
  if window:isVisible() then
    toggle()
  end
end

function onDungeonStart(data)
  if not dungeonInfo then return end
  local queueWaiting = safeRecursiveGet(dungeonInfo, "queueWaiting")
  if queueWaiting then queueWaiting:setText("00:00:00") end
  queueTime = 0

  local queueDungeon = safeRecursiveGet(dungeonInfo, "queueDungeon")
  local queueButton = safeRecursiveGet(dungeonInfo, "queueButton")
  if queueButton then queueButton:setText(tr("Join")) end
  if queueDungeon then queueDungeon:setText("------") end
  if timerEvent then
    removeEvent(timerEvent)
    timerEvent = nil
  end

  if not killCounter then return end
  killCounter:show()

  local bonusObjectives = killCounter:getChildById("bonusObjectives")
  if bonusObjectives then
    for i = bonusObjectives:getChildCount(), 2, -1 do
      bonusObjectives:getChildByIndex(i):destroy()
    end
    if data.objectives then
      local h = 16
      for _, obj in ipairs(data.objectives) do
        local w = g_ui.createWidget("ObjectiveCheckBox", bonusObjectives)
        w:addAnchor(AnchorTop, "prev", AnchorBottom)
        w:setMarginTop(5)
        w:setText(obj)
        h = h + 25
      end
      bonusObjectives:setHeight(h)
      bonusObjectives:setMarginTop(5)
      killCounter:setHeight(170 + h)
    else
      bonusObjectives:setHeight(0)
      bonusObjectives:setMarginTop(0)
      killCounter:setHeight(170)
    end
  end

  killCounter:getChildById("label"):setText("0%")
  local mainObjective = killCounter:getChildById("mainObjective")
  bossNeed = tonumber(data.need) or 85
  bossUnlocked = false
  mainObjective:setText(tr('Kill %d%% of the monsters to unlock %s', bossNeed, (data.boss or "")))
  mainObjective:setChecked(false)
  local bossObjective = killCounter:getChildById("bossObjective")
  bossObjective:setText(tr('Kill %s', (data.boss or "")))
  bossObjective:setEnabled(false)
  bossObjective:setChecked(false)
  killCounter:getChildById("monstersLeft"):setText(tr('Monsters remaining %s', (data.left or 0)))
  killCounter:getChildById("timeLeft"):setText(tr('Time left %s', MsToShortTime(data.duration or 0)))

  timeLeft = data.duration or 0
  if timeLeftEvent then removeEvent(timeLeftEvent) end
  timeLeftEvent = scheduleEvent(doTimeLeft, 100)
end

function doTimeLeft()
  timeLeft = timeLeft - 100
  killCounter:getChildById("timeLeft"):setText(tr('Time left %s', MsToShortTime(timeLeft)))
  if timeLeft > 0 then
    timeLeftEvent = scheduleEvent(doTimeLeft, 100)
  end
end

function onDungeonFinish(data)
  killCounter:hide()
  if timeLeftEvent then
    removeEvent(timeLeftEvent)
  end
end

function onDungeonObjective(data)
  local bonusObjectives = killCounter:getChildById("bonusObjectives")
  local objWidget = bonusObjectives:getChildByIndex(data.id + 1)
  objWidget:setChecked(data.finished)
end

function onDungeonKilled(data)
  local bar = killCounter:getChildById("bar")
  local bossObjective = killCounter:getChildById("bossObjective")
  if data.percent then
   local percent = math.min(100, data.percent)
        local maxWidth = 270  
        local maxHeight = 50  
        local newWidth = maxWidth * (percent / 100)
        local newHeight = maxHeight
        bar:setWidth(newWidth)
        bar:setHeight(newHeight)
    if not bossUnlocked then
      killCounter:getChildById("label"):setText(math.min(100, data.percent) .. "%")
    end
    if data.unlocked and not bossUnlocked then
      bossUnlocked = true
      killCounter:getChildById("mainObjective"):setChecked(true)
      killCounter:getChildById("label"):setText(tr("Boss unlocked!"))
      bossObjective:setEnabled(true)
	  local textWidget = challengeNotifi:getChildById("text")
  textWidget:setText(tr("Boss unlocked!"))
  challengeNotifi:setWidth(math.max(263, 96 + textWidget:getTextSize().width))
  g_effects.fadeIn(challengeNotifi, 250)
  scheduleEvent(
    function()
      if challengeNotifi then
        g_effects.fadeOut(challengeNotifi, 250)
      end
    end,
    3000
  )
    end
  elseif data.boss then
    bossObjective:setChecked(true)
	local textWidget = challengeNotifi:getChildById("text")
  textWidget:setText(tr("You completed the dungeon!"))
  challengeNotifi:setWidth(math.max(263, 96 + textWidget:getTextSize().width))
  g_effects.fadeIn(challengeNotifi, 250)
  scheduleEvent(
    function()
      if challengeNotifi then
        g_effects.fadeOut(challengeNotifi, 250)
      end
    end,
    3000
  )
  end
  if data.left then
    killCounter:getChildById("monstersLeft"):setText(tr('Monsters Alive: %s', data.left))
  end
end

function onDungeonDifficulty(data)
  local dungeon = Dungeons[data.id]
  if dungeon then
    dungeon.difficulty = data.difficulty
    if selectedDungeonId and selectedDungeonId == data.id then
      local difficultiesPanel = dungeonInfo:getChildById("difficulties")
      for i = 2, 6 do
        local diffWidget = difficultiesPanel:getChildByIndex(i)
        if dungeon.difficulty < i then
          diffWidget:disable()
          diffWidget:getChildById("lockBg"):show()
          diffWidget:getChildById("lockImg"):show()
        else
          diffWidget:enable()
          diffWidget:getChildById("lockBg"):hide()
          diffWidget:getChildById("lockImg"):hide()
        end
      end
    end
  end
end

function onDungeonQueueUpdate(data)
  local dungeon = Dungeons[data.id]
  if dungeon then
    dungeon.queue.players = data.queue
    dungeon.queue.estimated = data.estimated
  end

  local dungeonsMenus = window:getChildById("dungeonsMenu")
  local menuDungeon = dungeonsMenus:getChildById("dungeon" .. data.id)
  local queue = menuDungeon:getChildById("queue")
  local queuePlayers = data.queue
  queue:setText(tr('Queue: %s', (queuePlayers == 0 and tr("Open") or tr('%s Players', queuePlayers))))
  if queuePlayers >= 6 then
    queue:setColor("red")
  elseif queuePlayers >= 3 then
    queue:setColor("orange")
  else
    queue:setColor("green")
  end
  if selectedDungeonId == data.id then
    if currentUI.queueStatus then
      local queuePlayers = data.queue
      currentUI.queueStatus:setText(queuePlayers == 0 and tr("Open") or tr('%s Players', queuePlayers))
      if queuePlayers >= 6 then
        currentUI.queueStatus:setColor("red")
      elseif queuePlayers >= 3 then
        currentUI.queueStatus:setColor("orange")
      else
        currentUI.queueStatus:setColor("green")
      end
    end
    if currentUI.queueTime and Dungeons[data.id] then
      currentUI.queueTime:setText(SecondsToShortTime(Dungeons[data.id].queue.estimated / 1000))
    end
  end
end

function onChallengeCompleted(data)
  local textWidget = challengeNotifi:getChildById("text")
  textWidget:setText(tr('%s challenge completed!', data))
  challengeNotifi:setWidth(math.max(263, 96 + textWidget:getTextSize().width))
  g_effects.fadeIn(challengeNotifi, 250)
  scheduleEvent(
    function()
      if challengeNotifi then
        g_effects.fadeOut(challengeNotifi, 250)
      end
    end,
    3000
  )
end

function getKillCounter()
  return killCounter
end

function toggle()
  if not window then
    return
  end
  if windowButton:isOn() then
    hide()
    windowButton:setOn(false)
  else
    show()
    windowButton:setOn(true)
  end
end

function show()
  if not window or not windowButton then
    return
  end
  local dungeonsMenus = window:getChildById("dungeonsMenu")
  dungeonsMenus:focusChild(dungeonsMenus:getChildByIndex(1))
  window:show()
  window:raise()
  window:focus()
end

function hide()
  if not window then
    return
  end
  window:hide()
end

function comma_value(amount)
  local formatted = amount
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1.%2")
    if (k == 0) then
      break
    end
  end
  return formatted
end

function SecondsToShortTime(seconds)
  if seconds <= 0 then
    return "00:00:00"
  else
    local hours = string.format("%02.f", math.floor(seconds / 3600))
    local mins = string.format("%02.f", math.floor(seconds / 60 - (hours * 60)))
    local secs = string.format("%02.f", math.floor(seconds - hours * 3600 - mins * 60))
    return hours .. ":" .. mins .. ":" .. secs
  end
end

function MsToShortTime(ms)
  if ms <= 0 then
    return "00:00.000"
  else
    local mins = string.format("%02.f", math.floor(ms / 1000 / 60))
    local secs = string.format("%02.f", math.floor(ms / 1000 % 60))
    local millis = string.format("%d", (ms % 1000) / 100)
    return mins .. ":" .. secs .. "." .. millis
  end
end