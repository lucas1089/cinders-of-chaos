local CODE = 109

local window = nil
local windowButton = nil
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

-- the card rail (O555)
local Entries = {} -- the "list" payload: {id, title, level, boss, queue}
local cards = {} -- [dungeon id] = its card widget
local railFilter = 'all' -- 'all' or a DungeonsView group key
local railSignature = nil -- the group of every dungeon (the rail is rebuilt when it changes)
local CARD_GAP = 8
local sideTab = 1

local function isMobileUI()
  return g_app ~= nil and g_app.isMobile ~= nil and g_app.isMobile() and true or false
end

local function ui(id)
  return window and window:recursiveGetChildById(id) or nil
end

local function playerLevel()
  local player = g_game.getLocalPlayer and g_game.getLocalPlayer() or nil
  return player and player.getLevel and player:getLevel() or nil
end

local function infoOf(id)
  return Dungeons[id]
end

function init()
  connect(
    g_game,
    {
      onGameStart = create,
      onGameEnd = destroy
    }
  )
  connect(LocalPlayer, { onLevelChange = onPlayerLevelChange })

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
  disconnect(LocalPlayer, { onLevelChange = onPlayerLevelChange })

  ProtocolGame.unregisterExtendedOpcode(CODE, onExtendedOpcode)

  destroy()
end

-- phone only (g_app.isMobile): the chosen dungeon shows page 1 (art header, difficulty tiles, requirements) or page 2 (the
-- Loot and Ranking tabs); the desktop layout never calls this and keeps both panels visible
local MOBILE_PAGES = {
  { 'infoPanel' },
  { 'sidePanel' }
}

function setMobilePage(n)
  if not window or not isMobileUI() then return end
  for page, ids in ipairs(MOBILE_PAGES) do
    for _, id in ipairs(ids) do
      local w = ui(id)
      if w then w:setVisible(page == n) end
    end
  end
  local a, b = ui('pageInfoTab'), ui('pageLootTab')
  if a then a:setChecked(n == 1) end
  if b then b:setChecked(n == 2) end
end

-- the Loot / Ranking tabs of the right panel (1 = loot and challenges, 2 = the two rank tables)
function showSideTab(n)
  if not window then return end
  sideTab = n == 2 and 2 or 1
  local loot, rank = ui('lootPage'), ui('rankPage')
  if loot then loot:setVisible(sideTab == 1) end
  if rank then rank:setVisible(sideTab == 2) end
  local a, b = ui('lootTab'), ui('rankTab')
  if a then a:setChecked(sideTab == 1) end
  if b then b:setChecked(sideTab == 2) end
end

function create()
  if window then return end
  window = g_ui.displayUI("dungeons")
  pcall(function() modules.game_howitworks.attach(window, 'dungeons') end) -- game_howitworks: the ? button
  window:hide()
  windowButton = modules.client_topmenu.addRightGameToggleButton("dungeonsButton", tr("Dungeons Finder"), "/images/topbuttons/dungeon", toggle)
  windowButton:setOn(false)

  setMobilePage(1)
  showSideTab(1)
  hookRailWheel()

  killCounter = g_ui.loadUI("killcounter", modules.game_interface.getMapPanel())
  killCounter:hide()
  -- movable, spot saved per character, double-click back (game_hudmove)
  if ChaosHudMove then
    ChaosHudMove.attach(killCounter, 'dungeonKillCounter', { otui = '/modules/game_dungeons/killcounter' })
  end

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
    selectedDungeonId = nil
    selectedDifficulty = 1
    queueTime = 0
    Dungeons = {}
    Entries = {}
    cards = {}
    railFilter = 'all'
    railSignature = nil

    if timeLeftEvent then
      removeEvent(timeLeftEvent)
    end
    timeLeftEvent = nil
    timeLeft = 0

    window:destroy()
    window = nil
  end

  if killCounter then
    if ChaosHudMove then ChaosHudMove.detach(killCounter) end
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

local function chipText(text)
  return ' ' .. tostring(text) .. ' '
end

-- one card: the picture slice of the dungeon, the boss, the group tag, name, level and queue
local function fillCard(card, entry, groupKey)
  local info = Dungeons[entry.id]
  local art = card:getChildById('art')
  if art then art:setImageSource(bannerFor(DungeonsView.bannerTitle(info or entry))) end
  local boss = card:getChildById('boss')
  if boss and entry.boss then boss:setOutfit(entry.boss) end
  card:getChildById('group'):setText(chipText(DungeonsView.groupTag(groupKey)))
  card:getChildById('title'):setText(entry.title or '')
  card:getChildById('level'):setText(DungeonsView.levelText(entry.level))
  card.dungeonId = entry.id
end

-- the parts of a card that change while the window is open: queue, best difficulty, the level veil
local function refreshCard(id)
  local card = cards[id]
  if not card then return end
  local entry
  for _, e in ipairs(Entries) do
    if e.id == id then entry = e break end
  end
  if not entry then return end
  local players = DungeonsView.queuePlayers(entry.queue)
  local queue = card:getChildById('queue')
  queue:setText(DungeonsView.queueText(players))
  queue:setColor(DungeonsView.queueTone(players))

  local info = Dungeons[id]
  local party = card:getChildById('party')
  local partyReq = info and info.req and info.req.party or nil
  if partyReq ~= nil and not isMobileUI() then
    party:setText(tr('Party:') .. ' ' .. tostring(partyReq))
    party:setVisible(true)
  else
    party:setVisible(false)
  end

  local best = card:getChildById('best')
  local bestText = info and DungeonsView.bestText(info.difficulty) or nil
  best:setText(bestText and chipText(bestText) or '')
  best:setVisible(bestText ~= nil)

  local veil = card:getChildById('lock')
  local lockText = DungeonsView.lockText(entry.level, playerLevel())
  if lockText then
    veil:getChildById('lockText'):setText(lockText)
    veil:setVisible(true)
  else
    veil:setVisible(false)
  end
end

local function refreshAllCards()
  for id in pairs(cards) do refreshCard(id) end
end

function onPlayerLevelChange()
  refreshAllCards()
  refreshQueueStatus()
end

local function markSelected(dungeonId)
  for id, card in pairs(cards) do
    card:setChecked(id == dungeonId)
  end
end

-- sideways wheel on the rail (the base scroll area only moves up and down)
function hookRailWheel()
  local rail, bar = ui('dungeonsRail'), ui('dungeonsRailScroll')
  if not rail or not bar then return end
  rail.onMouseWheel = function(self, mousePos, direction)
    if bar.getValue and bar.setValue then
      local step = 80
      bar:setValue(bar:getValue() + (direction == MouseWheelUp and -step or step))
    end
    return true
  end
end

local function groupsNow()
  return DungeonsView.arrange(Entries, infoOf, railFilter)
end

local function signatureNow()
  local parts = {}
  for _, e in ipairs(Entries) do
    local info = Dungeons[e.id]
    parts[#parts + 1] = e.id .. ':' .. DungeonsView.groupOf(e.level, info and info.weekly or nil)
  end
  table.sort(parts)
  return table.concat(parts, ',')
end

-- the cards of every group of the current filter, new
function rebuildRail()
  local rail = ui('dungeonsRail')
  if not rail then return end
  rail:destroyChildren()
  cards = {}
  local cardWidth = isMobileUI() and 128 or 156
  for _, group in ipairs(groupsNow()) do
    local box = g_ui.createWidget('DungeonGroup', rail)
    box:setWidth(DungeonsView.groupWidth(#group.items, cardWidth, CARD_GAP))
    box:getChildById('heading'):setText(group.title)
    local row = box:getChildById('row')
    for _, entry in ipairs(group.items) do
      local card = g_ui.createWidget('DungeonCard', row)
      card:setId('dungeon' .. entry.id)
      cards[entry.id] = card
      fillCard(card, entry, group.key)
      card.onMouseRelease = function(self, mousePos, button)
        if button ~= MouseLeftButton or not self:containsPoint(mousePos) or not self:isEnabled() then return false end
        doSelection(entry.id)
        return true
      end
    end
  end
  railSignature = signatureNow()
  refreshAllCards()
  markSelected(selectedDungeonId)
  local bar = ui('dungeonsRailScroll')
  if bar and bar.setValue then bar:setValue(0) end
end

-- the filter chips: All and every group that has a card (hidden when there is only one group)
local function buildFilters()
  local panel = ui('filters')
  if not panel then return end
  panel:destroyChildren()
  local filters = DungeonsView.filters(Entries, infoOf)
  local valid = false
  for _, f in ipairs(filters) do
    if f.key == railFilter then valid = true end
  end
  if not valid then railFilter = 'all' end
  for _, f in ipairs(filters) do
    local chip = g_ui.createWidget('DungeonFilterChip', panel)
    chip:setId('filter_' .. f.key)
    chip:setText(f.title)
    chip:setWidth(chip:getTextSize().width + 28)
    chip:setChecked(f.key == railFilter)
    chip.onClick = function() setFilter(f.key) end
  end
  panel:setVisible(#filters > 2)
end

function setFilter(key)
  if railFilter == key then return end
  railFilter = key
  local panel = ui('filters')
  if panel then
    for i = 1, panel:getChildCount() do
      local chip = panel:getChildByIndex(i)
      local id = chip and chip:getId()
      if id then chip:setChecked(id == 'filter_' .. key) end
    end
  end
  rebuildRail()
  local id = DungeonsView.pick(groupsNow(), selectedDungeonId)
  if id and id ~= selectedDungeonId then
    doSelection(id)
  end
end

-- the chosen card scrolls into view
local function showCard(id)
  local rail, card = ui('dungeonsRail'), cards[id]
  if rail and card and rail.ensureChildVisible then
    pcall(function() rail:ensureChildVisible(card) end)
  end
end

function onDungeonsList(data)
  if not window or type(data) ~= 'table' then return end
  Entries = {}
  for _, d in ipairs(data) do
    Entries[#Entries + 1] = d
  end
  buildFilters()
  rebuildRail()
  local id = DungeonsView.pick(groupsNow(), selectedDungeonId)
  if id then
    if Dungeons[id] then
      selectDungeon(id)
    else
      pendingInitialDungeonId = id
    end
  end
end

-- the requirements: a chip per number that applies, the quests, the items
local function applyRequirementsUI(dungeon)
  if not dungeon then return end
  local req = dungeon.req or {}

  local function chip(id, caption, value)
    local w = ui(id)
    if not w then return end
    if value ~= nil then
      w:setText(chipText(caption .. ' ' .. tostring(value)))
      w:setVisible(true)
    else
      w:setText('')
      w:setVisible(false)
    end
  end
  local function number(v)
    return type(v) == 'number' and formatShortNumber(v) or v
  end
  chip('reqLevel', tr('Level:'), number(req.level))
  chip('reqParty', tr('Party:'), number(req.party))
  chip('reqILvl', tr('Item Level:'), number(req.iLvl))
  chip('reqGold', tr('Gold:'), number(req.gold))
  local gold = ui('reqGold')
  if gold and req.gold then gold:setTooltip(comma_value(req.gold)) end

  local quests = ui('quests')
  if quests then
    if type(req.quests) == 'table' and #req.quests > 0 then
      quests:setText(tr('Quests') .. ': ' .. table.concat(req.quests, ', ') .. '.')
      quests:setVisible(true)
    else
      quests:setText('')
      quests:setVisible(false)
    end
  end

  local items = ui('items')
  if items then
    local any = false
    if type(req.items) == 'table' then
      for i = 1, 6 do
        local slot = items:getChildByIndex(i)
        local reqItem = req.items[i]
        if slot then
          if reqItem then
            slot:setItemId(reqItem.clientId)
            slot:setItemCount(reqItem.count)
            any = true
          else
            slot:setItem(nil)
          end
        end
      end
    end
    items:setVisible(any)
  end
end

-- the chosen dungeon's header: title on the picture, the chips under it
local function applyHeader(dungeonId)
  local dungeon, entry = Dungeons[dungeonId], nil
  for _, e in ipairs(Entries) do
    if e.id == dungeonId then entry = e break end
  end
  local banner, title = ui('banner'), ui('bannerTitle')
  if banner then banner:setImageSource(bannerFor(DungeonsView.bannerTitle(dungeon or entry))) end
  if title then title:setText((dungeon and dungeon.title) or (entry and entry.title) or '') end
  local chips = DungeonsView.headerChips(entry, dungeon, playerLevel())
  local level, queue, best = ui('chipLevel'), ui('chipQueue'), ui('chipBest')
  if level then
    level:setText(chipText(chips.level))
    level:setColor(chips.levelTone == 'red' and '#e03a1e' or '#d6c9ae')
  end
  if queue then
    queue:setText(chipText(chips.queue))
    queue:setColor(chips.queueTone)
  end
  if best then
    best:setText(chips.best and chipText(chips.best) or '')
    best:setVisible(chips.best ~= nil)
  end
end

function refreshQueueStatus()
  local status = currentUI.queueStatus or ui('queueStatus')
  local dungeon = Dungeons[selectedDungeonId]
  if not status or not dungeon then return end
  local players = DungeonsView.queuePlayers(dungeon.queue)
  local lockText = DungeonsView.lockText(dungeon.req and dungeon.req.level, playerLevel())
  if lockText then
    status:setText(lockText)
    status:setColor('#e03a1e')
  else
    status:setText(DungeonsView.queueShort(players))
    status:setColor(DungeonsView.queueTone(players))
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

  local previous = Dungeons[data.id]
  if previous then
    data.solo = data.solo or previous.solo -- the rank tables come in their own messages
    data.group = data.group or previous.group
  end
  Dungeons[data.id] = data
  if window and #Entries > 0 then
    if railSignature ~= signatureNow() then
      -- a Weekly Challenge payload moves its card to its own group
      buildFilters()
      rebuildRail()
    else
      refreshCard(data.id)
    end
  end
  if selectedDungeonId == data.id and window then
    applyDifficultyTexts(data)
    applyHeader(data.id)
    refreshQueueStatus()
  end

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

function setDungeonMenuInteractable(enabled)
  for id, card in pairs(cards) do
    if enabled then
      card:enable()
    else
      card:disable()
    end
  end
  if enabled then refreshAllCards() end
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

  -- no cooldown after a selection: picking a dungeon only redraws this window (no request), and the 2 s lock made the
  -- list feel slow (beta 2026-10-20)
  local ok, err = xpcall(function()
    selectDungeon(dungeonId)
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

-- banner art: DungeonsView.bannerFor (dungeonsview.lua)
function bannerFor(title)
  return DungeonsView.bannerFor(title, function(path) return g_resources.fileExists(path) end)
end

-- the six panel texts: the dungeon's own health curves when the server sent them, else the table's
function applyDifficultyTexts(dungeon)
  local panel = currentUI.difficultiesPanel
  if not panel then return end
  for i = 1, 6 do
    local button = panel:getChildByIndex(i)
    local info = button and button:getChildById("info")
    if info then
      info:setText(DungeonsView.panelText(i, dungeon and dungeon.health))
    end
  end
end

function selectDungeon(dungeonId)
  local dungeon = Dungeons[dungeonId]
  if not dungeon or not window then return end
  if selectedDungeonId == dungeonId then return end

  selectedDungeonId = dungeonId
  markSelected(dungeonId)
  showCard(dungeonId)

  currentUI.difficultiesPanel = ui("difficulties")
  currentUI.requirementsPanel = ui("requirements")
  currentUI.bossLootPanel = ui("bossLoot")
  currentUI.queueStatus = ui("queueStatus")
  currentUI.queueTime = ui("queueTime")
  currentUI.queueWaiting = ui("queueWaiting")
  currentUI.challengesPanel = ui("challenges")
  currentUI.soloTable = ui("soloTable")
  currentUI.groupTable = ui("groupTable")

  applyHeader(dungeonId)
  applyDifficultyTexts(dungeon)

  -- the tile that is lit is the difficulty a Join sends: the hardest the character has unlocked (the Weekly Challenge
  -- runs at difficulty 1 only, server weekly_challenge_config.lua)
  local wanted = dungeon.weekly and 1 or math.max(1, math.min(6, tonumber(dungeon.difficulty) or 1))
  lastDifficultyId = nil
  if currentUI.difficultiesPanel then
    for i = 2, 6 do
      local diffWidget = currentUI.difficultiesPanel:getChildByIndex(i)
      if diffWidget then
        if dungeon.difficulty < i or dungeon.weekly then
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
    local tile = currentUI.difficultiesPanel:getChildByIndex(wanted)
    if tile then currentUI.difficultiesPanel:focusChild(tile) end
  end

  applyRequirementsUI(dungeon)

  if currentUI.bossLootPanel then
    for i = 1, 28 do
      local slot = currentUI.bossLootPanel:getChildByIndex(i)
      if dungeon.loot[i] then
        local loot = dungeon.loot[i]
        slot:setItemId(loot.clientId)
        slot:setItemCount(loot.count)
        -- its name on hover, "Where to find" on a right click (game_itemfinder)
        local name = type(loot.name) == 'string' and loot.name ~= '' and loot.name or nil
        if name and (tonumber(loot.count) or 1) > 1 then name = string.format('%dx %s', loot.count, name) end
        slot:setTooltip(name or '')
        slot.lootClientId = loot.clientId
      else
        slot:setItem(nil)
        slot:setTooltip('')
        slot.lootClientId = nil
      end
      local finder = modules.game_itemfinder
      if finder and finder.attach then
        finder.attach(slot, function() return slot.lootClientId end)
      end
    end
  end

  refreshQueueStatus()
  if currentUI.queueTime then
    currentUI.queueTime:setText(SecondsToShortTime(dungeon.queue.estimated / 1000))
  end
  if currentUI.queueWaiting and not timerEvent then
    currentUI.queueWaiting:setText("00:00:00")
  end

  if currentUI.challengesPanel then
    currentUI.challengesPanel:destroyChildren()
    local weeklyTitle = DungeonsView.weeklyTitle(dungeon.weekly)
    if weeklyTitle then
      local widget = g_ui.createWidget("ChallengePanel", currentUI.challengesPanel)
      widget:setText(weeklyTitle)
      widget:getChildById("checkbox"):hide()
      widget:getChildById("description"):setText(DungeonsView.weeklyText(dungeon.weekly))
    end
    for i = 1, #dungeon.challenges do
      local challenge = dungeon.challenges[i]
      local widget = g_ui.createWidget("ChallengePanel", currentUI.challengesPanel)
      widget:setText(tr('%s (%s Points)', challenge.title, formatShortNumber(challenge.points)))
      widget:getChildById("checkbox"):setChecked(challenge.completed)
      widget:getChildById("description"):setText(challenge.desc)
    end
  end

  onDifficultyFocus(wanted, true)
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
  if not window then return end
  local queueWaiting = safeRecursiveGet(window, "queueWaiting")
  if queueWaiting then queueWaiting:setText("00:00:00") end
  queueTime = 0

  local queueDungeon = safeRecursiveGet(window, "queueDungeon")
  local queueButton = safeRecursiveGet(window, "queueButton")
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
  if not window then return end
  local queueWaiting = safeRecursiveGet(window, "queueWaiting")
  if queueWaiting then queueWaiting:setText("00:00:00") end
  queueTime = 0

  local queueDungeon = safeRecursiveGet(window, "queueDungeon")
  local queueButton = safeRecursiveGet(window, "queueButton")
  if queueButton then queueButton:setText(tr("Join")) end
  if queueDungeon then queueDungeon:setText("------") end
  if timerEvent then
    removeEvent(timerEvent)
    timerEvent = nil
  end
end

function queueTimer()
  if not window then return end
  local queueWaiting = safeRecursiveGet(window, "queueWaiting")
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
  if not window then return end
  local queueWaiting = safeRecursiveGet(window, "queueWaiting")
  if queueWaiting then queueWaiting:setText("00:00:00") end
  queueTime = 0

  local queueDungeon = safeRecursiveGet(window, "queueDungeon")
  local queueButton = safeRecursiveGet(window, "queueButton")
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
    refreshCard(data.id)
    if selectedDungeonId and selectedDungeonId == data.id and window then
      local difficultiesPanel = ui("difficulties")
      for i = 2, 6 do
        local diffWidget = difficultiesPanel and difficultiesPanel:getChildByIndex(i)
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
      applyHeader(data.id)
    end
  end
end

function onDungeonQueueUpdate(data)
  local dungeon = Dungeons[data.id]
  if dungeon then
    if type(dungeon.queue) ~= 'table' then dungeon.queue = {} end
    dungeon.queue.players = data.queue
    dungeon.queue.estimated = data.estimated
  end
  for _, entry in ipairs(Entries) do
    if entry.id == data.id then entry.queue = data.queue end
  end
  refreshCard(data.id)

  if selectedDungeonId == data.id then
    refreshQueueStatus()
    applyHeader(data.id)
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
  -- the chosen dungeon stays chosen; the first card when none is
  local id = DungeonsView.pick(groupsNow(), selectedDungeonId)
  if id and id ~= selectedDungeonId and Dungeons[id] then
    selectDungeon(id)
  end
  refreshAllCards()
  refreshQueueStatus()
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

-- for game_chaosmusic (O408): the HUD shows while the player is in a dungeon run
function getState()
  return { hud = killCounter ~= nil and killCounter:isVisible() or false }
end
