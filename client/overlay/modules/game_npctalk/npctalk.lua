-- NPC dialogue window: talk to an NPC from its right-click menu ("Talk"), a left click (smart controls) or "Use"; the
-- player walks up to it when it is too far, says "hi", and the whole conversation runs in a speech bubble over the NPC:
-- its name and outfit, its latest reply (long replies wrap; the bubble grows up to a limit, then scrolls), the
-- {keywords} of the reply as clickable words and chips, a text field, and Yes / No / Trade / Bye when they fit. Esc,
-- Bye or the x end it ("bye"); walking out of the NPC's talk radius closes it (the server ends the conversation then).
--
-- Every NPC works unchanged: nothing on the server. The 10.98 server sends an NPC's answers as private NPC speech
-- (MessageModes.NpcFrom / NpcFromStartBlock, the console's "NPCs" tab); the console hands those to
-- game_npctrade.tryHandleNpcDialogMessage first (the base client's own NPC dialog window). This module replaces that
-- function and its companions (onNpcPlayerTalk, onNpcConversationAttempt, endNpcConversation,
-- setNpcDialogWindowEnabled), game_interface.talkToNpc (the menu's Talk), g_game.use on an NPC and g_map.addThing
-- (the conversation NPC's words over its head) while it is loaded and puts it all back on unload: lines of the NPC we
-- talk to go to the bubble, every other line (another NPC, a public "Good bye" when walking away) stays in the
-- console. The player's
-- words go out as the engine expects: "hi" in the default channel, the rest as private NPC talk (MessageModes.NpcTo),
-- the same packets the console's NPCs tab sends. Server windows (modal windows of the Ascendant Oracle and the Keeper
-- of Trials, the trade window) open as usual; the bubble stays where it is.
--
-- Settings: Options > Interface > "Disable NPC Dialog Window" (the base client's option) turns the bubble off: NPC
-- talk stays in the console as before, Talk still walks up and greets. g_settings node 'npcTalk': consoleCopy (also
-- copy the conversation into the console's NPCs tab), from the bubble's "..." menu.
-- The logic without client API (keywords, buttons, geometry) is npctalk_logic.lua.

local L = NpcTalkLogic

local APPROACH_TIMEOUT = 10000 -- walking up to an NPC gives up after this long
local SUPPRESS_MS = 3000       -- after a goodbye, the NPC's farewell goes to the console, not to a new bubble
local SWITCH_GAP_MS = 1500     -- Talk to another NPC: "bye" to the first, "hi" this much later
local IDLE_MS = 120000         -- the stock NpcHandler forgets an idle player after 120 s; so does the bubble
local TICK_MS = 20
local TAIL_W, TAIL_H = 22, 12
local MAX_TRANSCRIPT = 40

local okText, Text = pcall(dofile, '/modules/game_spellsupports/supportstext.lua')
if not okText or type(Text) ~= 'table' then Text = nil end

local bubble, tail
local settings = { consoleCopy = false }
local originals = {}
local origTalkToNpc, origUse, origAddThing
local tickEvent
local escapeBound = false

-- the conversation: {id, name, creature, turn = {npc lines}, said, history = {all npc lines}, transcript, started,
-- lastActivity}; approach: {creature, started}
local conv
local approach
local suppressAllUntil = 0 -- until then NPC lines stay in the console (the farewells answering a goodbye)
local tracks = {}     -- creature id -> {pos, from}: the last step, for the walk offset
local layoutKey

-- ---------------------------------------------------------------- helpers
local function warn(where, err)
  g_logger.warning('[npctalk] ' .. where .. ': ' .. tostring(err))
end

local function safe(where, fn)
  return function(...)
    local ok, a, b = pcall(fn, ...)
    if not ok then warn(where, a) return nil end
    return a, b
  end
end

local function alive(w)
  return w and not w:isDestroyed()
end

local function now()
  return g_clock.millis()
end

local function loadSettings()
  local node = g_settings.getNode('npcTalk') or {}
  settings.consoleCopy = node.consoleCopy == true or node.consoleCopy == 'true'
end

local function saveSettings()
  g_settings.setNode('npcTalk', { consoleCopy = settings.consoleCopy })
end

-- the base client's option "Disable NPC Dialog Window" (Options > Interface)
local function enabled()
  local cs = modules.client_settings
  if cs and cs.getOption then
    local ok, off = pcall(cs.getOption, 'disableNpcDialogWindow')
    if ok and off then return false end
  end
  return true
end

local function mapPanel()
  local gi = modules.game_interface
  return gi and gi.getMapPanel and gi.getMapPanel()
end

local function rootPanel()
  local gi = modules.game_interface
  return gi and gi.getRootPanel and gi.getRootPanel()
end

local function player()
  return g_game.getLocalPlayer()
end

local function isNpcCreature(thing)
  if type(thing) ~= 'userdata' then return false end
  local ok, yes = pcall(function() return thing:isCreature() and thing:isNpc() end)
  return ok and yes or false
end

local function failure(text)
  if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
    modules.game_textmessage.displayFailureMessage(text)
  end
end

-- the NPC called `name` nearest to the player, among the creatures on screen
local function findNpc(name)
  local p = player()
  if not p or not name then return nil end
  local want, best, bestDist = name:lower(), nil, nil
  for _, c in ipairs(g_map.getSpectators(p:getPosition(), false) or {}) do
    if c:isNpc() and (c:getName() or ''):lower() == want then
      local d = L.distance(p:getPosition(), c:getPosition()) or 99
      if not bestDist or d < bestDist then best, bestDist = c, d end
    end
  end
  return best
end

-- the console's NPCs tab (created on demand: the console selects it, as it does for every NPC line)
local function npcTab()
  local console = modules.game_console
  if not console then return nil end
  local tab = console.getTabByName and console.getTabByName(NPC_NAME_CHAT)
  if not tab and console.g_chat and console.g_chat.addTabMessages then
    tab = console.g_chat:addTabMessages(NPC_NAME_CHAT, false)
  end
  return tab
end

local function copyPlayerLineToConsole(text)
  local tab = npcTab()
  local p = player()
  if tab and p then
    tab:addMessage(g_game.getCharacterName(), p:getLevel(), MessageModes.NpcTo, text)
  end
end

-- ---------------------------------------------------------------- walk offsets (the bubble follows a walking NPC)
local function trackOf(creature)
  local id = creature:getId()
  local pos = creature:getPosition()
  local t = tracks[id]
  if not t then
    t = { pos = pos }
    tracks[id] = t
  elseif pos and (pos.x ~= t.pos.x or pos.y ~= t.pos.y or pos.z ~= t.pos.z) then
    t.from, t.pos = t.pos, pos
  end
  return t
end

local DIRS = { ['0,-1'] = 0, ['1,0'] = 1, ['0,1'] = 2, ['-1,0'] = 3, ['1,-1'] = 4, ['1,1'] = 5, ['-1,1'] = 6, ['-1,-1'] = 7 }

local function walkOffset(creature, spriteSize)
  local t = trackOf(creature)
  if not t.from or not creature:isWalking() then return { x = 0, y = 0 } end
  local dir = DIRS[(t.pos.x - t.from.x) .. ',' .. (t.pos.y - t.from.y)]
  if not dir then return { x = 0, y = 0 } end
  local duration = creature:getStepDuration(false, dir)
  local progress = duration and duration > 0 and creature:getWalkTicksElapsed() / duration or 1
  local x, y = L.walkOffset(t.from, t.pos, progress, spriteSize)
  return { x = x, y = y }
end

-- ---------------------------------------------------------------- the bubble
local function setStatus(text)
  if alive(bubble) then bubble.status:setText(text or '') end
end

local function resetLayout()
  layoutKey = nil
end

local function transcriptTooltip()
  if not conv or not alive(bubble) then return end
  local text = L.transcript(conv.transcript, 64, 16, Text and Text.wrap or nil)
  if text ~= '' then
    bubble.npcName:setTooltip(text)
  else
    bubble.npcName:removeTooltip()
  end
end

local sendText -- forward

-- a font of client_chaos_theme (ChaosTheme.fonts) on a widget, only when that font is loaded: the NPC's lines in
-- 'dialogue' (IM Fell English), its name in 'heading' (Alegreya SC); the player's line, chips and buttons keep the
-- UI font
local function applyThemeFont(widget, role)
  local theme = modules.client_chaos_theme and modules.client_chaos_theme.ChaosTheme
  if theme and theme.applyFont then theme.applyFont(widget, role) end
end

local function addReplyLabel(text)
  local label = g_ui.createWidget('NpcTalkText', bubble.textScroll)
  applyThemeFont(label, 'dialogue')
  local colored, hasKeys = L.coloredText(text, L.COLORS.npc, L.COLORS.keyword, true)
  if hasKeys then
    label:setEventListener(EVENT_TEXT_CLICK)
    label:setEventListener(EVENT_TEXT_HOVER)
    label.onTextClick = function(_, word) sendText(word) end
    label.onTextHoverChange = function(widget, _, hovered)
      if hovered and not widget.pointer then
        widget.pointer = true
        g_mouse.pushCursor('pointer')
      elseif not hovered and widget.pointer then
        widget.pointer = nil
        g_mouse.popCursor('pointer')
      end
    end
    label.onDestroy = function(widget)
      if widget.pointer then
        widget.pointer = nil
        g_mouse.popCursor('pointer')
      end
    end
  end
  label:setColoredText(colored)
end

local function refreshChipsAndButtons()
  if not conv or not alive(bubble) then return end
  local tradeOpen = modules.game_npctrade and modules.game_npctrade.isTrading and modules.game_npctrade.isTrading()
  local shown = L.buttons(conv.turn, conv.history, tradeOpen)
  local hidden = {}
  for _, id in ipairs(L.BUTTONS) do
    local button = bubble.quickButtons[id]
    button:setVisible(shown[id])
    if shown[id] then hidden[id] = true end
  end
  bubble.chips:destroyChildren()
  conv.hint = #L.keywords(conv.turn) > 0 and tr('Click a gold word to say it.') or nil
  for _, word in ipairs(L.chips(conv.turn, hidden)) do
    local chip = g_ui.createWidget('NpcTalkChip', bubble.chips)
    chip:setText(word)
    chip.fullWidth = chip:getTextSize().width + 16
    chip:setWidth(chip.fullWidth)
    chip:addAnchor(AnchorTop, 'parent', AnchorTop)
    chip:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    chip.onClick = function() sendText(word) end
  end
  resetLayout()
end

-- the reply area: what the player said last (dim), then the NPC's lines since
local function refreshText()
  if not conv or not alive(bubble) then return end
  bubble.textScroll:destroyChildren()
  if conv.said then
    local said = g_ui.createWidget('NpcTalkSaid', bubble.textScroll)
    said:setText(tr('You') .. ': ' .. conv.said)
  end
  if #conv.turn == 0 then
    local waiting = g_ui.createWidget('NpcTalkSaid', bubble.textScroll)
    waiting:setText('...')
  end
  for _, line in ipairs(conv.turn) do addReplyLabel(line) end
  refreshChipsAndButtons()
  transcriptTooltip()
  scheduleEvent(function()
    if alive(bubble) then bubble.textScrollBar:setValue(bubble.textScrollBar:getMaximum()) end
  end, 60)
end

local function focusInput()
  if alive(bubble) and bubble:isVisible() then
    bubble:raise()
    if alive(tail) then tail:raise() end
    -- the whole chain up to the root: a relog can leave the root's focus on another window
    if bubble.input.recursiveFocus then
      bubble.input:recursiveFocus(KeyboardFocusReason)
    else
      bubble:focus()
      bubble.input:focus()
    end
  end
end

-- what covers the map: the window's edges, the side panels, the console and action bars below it, the top menu bar
local function screenLimits()
  local root = rootPanel()
  if not root then return {} end
  local r = root:getRect()
  local limits = { left = r.x, right = r.x + r.width, top = r.y, bottom = r.y + r.height }
  local function child(id)
    local w = root:getChildById(id)
    if w and w:isVisible() and w:getWidth() > 0 and w:getHeight() > 0 then return w:getRect() end
  end
  local lp = child('gameLeftPanels')
  if lp then limits.left = math.max(limits.left, lp.x + lp.width) end
  local rp = child('gameRightPanels')
  if rp then limits.right = math.min(limits.right, rp.x) end
  for _, id in ipairs({ 'bottomSplitter', 'gameBottomActionPanel', 'gameBottomPanel' }) do
    local b = child(id)
    if b and b.y > r.y + r.height / 2 then limits.bottom = math.min(limits.bottom, b.y) end
  end
  local bar = child('chaosMenuBar')
  if bar and bar.y < r.y + 60 then limits.top = math.max(limits.top, bar.y + bar.height) end
  return limits
end

-- size and place the bubble over the NPC (every tick: the NPC and the camera move)
local function layout()
  if not conv or not alive(bubble) then return end
  local map = mapPanel()
  local c = conv.creature
  local p = player()
  if not map or not c or not p then return end
  local spriteSize = (g_sprites and g_sprites.spriteSize and g_sprites.spriteSize()) or 32
  local vis = map:getVisibleDimension()
  local panelRect = map.getPaddingRect and map:getPaddingRect() or map:getRect()
  local keep = map.isKeepAspectRatioEnabled and map:isKeepAspectRatioEnabled()
  local mapArea = L.mapRect(panelRect, vis, keep)
  local stretch = L.stretch(mapArea, vis, spriteSize)
  local area = L.visibleArea(mapArea, screenLimits())
  local cam = map:getCameraPosition() or p:getPosition()
  local center = L.tileCenter(mapArea, stretch, spriteSize, cam, walkOffset(p, spriteSize), c:getPosition(),
    walkOffset(c, spriteSize))
  if not center then return end

  -- width and height: wider maps get a slightly wider bubble; the reply area grows up to a limit, then scrolls
  local width = math.max(300, math.min(400, math.floor(area.width * 0.36)))
  local maxText = math.max(56, math.min(260, math.floor(area.height * 0.5) - 130))
  local key = width .. ':' .. maxText .. ':' .. bubble.textScroll:getChildCount() .. ':' .. bubble.chips:getChildCount()
  local contentH = 0
  for _, child in ipairs(bubble.textScroll:getChildren()) do
    if child:isVisible() then contentH = contentH + child:getHeight() + child:getMarginBottom() end
  end
  key = key .. ':' .. contentH
  if key ~= layoutKey then
    layoutKey = key
    bubble:setWidth(width)
    local textH = math.max(14, math.min(contentH, maxText))
    local scrolls = contentH > maxText
    bubble.textScrollBar:setVisible(scrolls)
    bubble.textScroll:setPaddingRight(scrolls and 16 or 0)
    bubble.textScroll:setHeight(textH)
    -- chips in rows (anchored to the chips panel's top left: they move with the bubble)
    local widths = {}
    local chips = bubble.chips:getChildren()
    for i, chip in ipairs(chips) do widths[i] = chip.fullWidth or chip:getWidth() end
    local inner = width - bubble:getPaddingLeft() - bubble:getPaddingRight()
    local places, chipsH = L.flow(widths, inner, 20, 4, 4)
    for i, chip in ipairs(chips) do
      chip:setMarginLeft(places[i].x)
      chip:setMarginTop(places[i].y)
      chip:setWidth(places[i].width)
    end
    bubble.chips:setHeight(chipsH)
    bubble.chips:setMarginTop(chipsH > 0 and 6 or 0)
    -- quick buttons share the row
    local visible = {}
    for _, id in ipairs(L.BUTTONS) do
      if bubble.quickButtons[id]:isVisible() then visible[#visible + 1] = bubble.quickButtons[id] end
    end
    local bw = math.floor((inner - 4 * math.max(0, #visible - 1)) / math.max(1, #visible))
    for _, b in ipairs(visible) do b:setWidth(math.min(bw, 90)) end
    local h = bubble:getPaddingTop() + 40 + 6 + textH + (chipsH > 0 and (chipsH + 6) or 0) + 6 + 22 + 6 + 22 +
      bubble:getPaddingBottom()
    bubble:setHeight(h)
  end
  -- the tail points at the NPC's name (drawn 12 px above the point over its head) or, under it, at its feet
  local outfit = c:getOutfit()
  local dispY = 8
  local okType, thingType = pcall(g_things.getThingType, outfit.type or 0, ThingCategoryCreature)
  if okType and thingType and thingType.getDisplacementY then dispY = thingType:getDisplacementY() end
  local top = center.y - math.floor((spriteSize / 2 + dispY + 2) * stretch) - 16
  local bottom = center.y + math.floor((spriteSize / 2 - dispY) * stretch) + 2
  local place = L.place(bubble:getWidth(), bubble:getHeight(), { x = center.x, y = top }, { x = center.x, y = bottom },
    area, TAIL_W, TAIL_H, 4)
  bubble:setPosition({ x = place.x, y = place.y })
  if alive(tail) then
    tail:setImageSource('/modules/game_npctalk/images/' .. (place.below and 'tail_up' or 'tail_down'))
    tail:setPosition({ x = place.tailX, y = place.tailY })
  end
end

local function hideBubble()
  if alive(bubble) then bubble:hide() end
  if alive(tail) then tail:hide() end
end

local function showBubble()
  if not alive(bubble) then return end
  bubble:show()
  if alive(tail) then tail:show() end
  resetLayout()
  layout()
  bubble:raise()
  if alive(tail) then tail:raise() end
end

-- ---------------------------------------------------------------- conversation
local stopTicking

local function closeConversation(suppress)
  -- a goodbye reaches every NPC in range that was listening (a "hi" greets them all): their farewells stay in the
  -- console instead of opening a new bubble
  if suppress then suppressAllUntil = now() + SUPPRESS_MS end
  conv = nil
  hideBubble()
  if alive(bubble) then
    bubble.textScroll:destroyChildren()
    bubble.chips:destroyChildren()
    bubble.input:clearText()
  end
  if not approach then stopTicking() end
end

local startTicking

local function openConversation(creature)
  conv = {
    id = creature:getId(), name = creature:getName(), creature = creature,
    turn = {}, history = {}, transcript = {}, started = now(), lastActivity = now(),
  }
  if not alive(bubble) then return end
  bubble.npcName:setText(conv.name)
  bubble.npcName:removeTooltip()
  local portrait = bubble.portraitFrame.portrait
  local outfit = creature:getOutfit()
  local okType, thingType = pcall(g_things.getThingType, outfit.type or 0, ThingCategoryCreature)
  local big = okType and thingType and math.max(thingType:getWidth(), thingType:getHeight()) >= 2
  portrait:setSize(big and { width = 64, height = 64 } or { width = 40, height = 40 })
  portrait:setMarginRight(big and -2 or 0)
  portrait:setMarginBottom(big and -4 or 0)
  portrait:setOutfit(outfit)
  setStatus('')
  if enabled() then
    showBubble()
    refreshText()
    focusInput()
  end
  startTicking()
end

-- "bye" to the NPC (unless already said), the trade window shut, the bubble closed
local function endConversation(sayBye)
  if not conv then return end
  if sayBye and g_game.isOnline() then
    g_game.talkPrivate(MessageModes.NpcTo, NPC_NAME_CHAT, 'bye')
    if settings.consoleCopy then copyPlayerLineToConsole('bye') end
  end
  local trade = modules.game_npctrade
  if trade and trade.isTrading and trade.isTrading() and trade.closeNpcTrade then
    pcall(trade.closeNpcTrade)
  end
  closeConversation(true)
end

-- the player said something to the NPC (from the bubble, or typed in the console's NPCs tab)
local function onPlayerSaid(text)
  if not conv then return end
  conv.said = text
  conv.turn = {}
  conv.lastActivity = now()
  table.insert(conv.transcript, { who = tr('You'), text = text })
  while #conv.transcript > MAX_TRANSCRIPT do table.remove(conv.transcript, 1) end
  refreshText()
end

sendText = function(text)
  text = L.trim(text)
  if text == '' or not g_game.isOnline() then return end
  if L.isFarewell(text) then
    endConversation(true)
    return
  end
  if L.isGreeting(text) then
    g_game.talk(text)
  else
    g_game.talkPrivate(MessageModes.NpcTo, NPC_NAME_CHAT, text)
    if settings.consoleCopy then copyPlayerLineToConsole(text) end
  end
  onPlayerSaid(text)
  focusInput()
end

local function greet(creature)
  if conv and conv.id ~= creature:getId() then endConversation(true) end
  if not conv then openConversation(creature) end
  conv.said = 'hi'
  conv.turn = {}
  conv.lastActivity = now()
  table.insert(conv.transcript, { who = tr('You'), text = 'hi' })
  if alive(bubble) and bubble:isVisible() then refreshText() end
  g_game.talk('hi')
end

-- walk to the nearest tile in the NPC's talk radius that the player can reach (an NPC behind a counter has no free
-- tile next to it, so following it would fail); nil when there is none
local MAX_PATHS = 12
local function walkTowards(creature)
  local p = player()
  local ppos, npos = p and p:getPosition(), creature:getPosition()
  if not ppos or not npos or ppos.z ~= npos.z then return nil end
  local tries = 0
  for _, pos in ipairs(L.approachTiles(npos, ppos, L.TALK_RANGE)) do
    local tile = g_map.getTile(pos)
    if tile and tile:isWalkable() then
      tries = tries + 1
      local ok, dirs, result = pcall(g_map.findPath, ppos, pos, 20000, 0)
      if ok and result == nil and type(dirs) == 'table' and type(dirs[2]) == 'number' then
        dirs, result = dirs[1], dirs[2]
      end
      if ok and result == 0 and type(dirs) == 'table' and #dirs > 0 then
        p:autoWalk(pos)
        return pos
      end
      if tries >= MAX_PATHS then break end
    end
  end
  return nil
end

-- Talk: greet the NPC, walking up to it first when it is out of its talk radius
local function talkTo(creature)
  if not isNpcCreature(creature) or not g_game.isOnline() then return false end
  local p = player()
  if not p then return false end
  if conv and conv.id == creature:getId() then
    -- the bubble is open already; greet again when the NPC opened it by itself (a goodbye of its own, say) or left
    -- the last words unanswered
    if not conv.said or (#conv.turn == 0 and now() - conv.lastActivity > 4000) then greet(creature) end
    if enabled() then
      showBubble()
      focusInput()
    end
    return true
  end
  -- one conversation at a time: the current one ends first; the "hi" waits until the farewells of the NPCs that
  -- heard the "bye" are in (or the NPC we turn to would answer the "hi" with its goodbye)
  local notBefore = 0
  if conv then
    endConversation(true)
    notBefore = now() + SWITCH_GAP_MS
  end
  local ppos, npos = p:getPosition(), creature:getPosition()
  if not npos or not ppos or ppos.z ~= npos.z then
    failure(tr('You cannot reach %s.', creature:getName()))
    return false
  end
  if notBefore == 0 and L.inRange(ppos, npos) then
    approach = nil
    greet(creature)
    return true
  end
  approach = { creature = creature, started = now(), notBefore = notBefore }
  if not L.inRange(ppos, npos) then
    approach.target = walkTowards(creature)
    approach.npcPos = npos
    if not approach.target then
      approach = nil
      failure(tr('You cannot reach %s.', creature:getName()))
      return false
    end
  end
  startTicking()
  return true
end

-- ---------------------------------------------------------------- the tick: approach, range, idle, placement
local function tick()
  if not g_game.isOnline() then
    approach = nil
    closeConversation(false)
    return
  end
  local p = player()
  if not p then return end
  if approach then
    local c = approach.creature
    if c:isRemoved() then
      approach = nil
    elseif now() < approach.notBefore then
      -- waiting for the farewells of the last conversation
    elseif L.inRange(p:getPosition(), c:getPosition()) then
      approach = nil
      if p:isAutoWalking() then p:stopAutoWalk() end
      greet(c)
    elseif now() - approach.started > APPROACH_TIMEOUT then
      approach = nil
      if p:isAutoWalking() then p:stopAutoWalk() end
      failure(tr('You cannot reach %s.', c:getName()))
    elseif not p:isAutoWalking() and not p:isWalking() and now() - (approach.walked or 0) > 300 then
      -- the walk ended short (blocked, or the NPC moved on): pick a tile again
      local npos = c:getPosition()
      approach.walked = now()
      approach.retries = (approach.retries or 0) + 1
      if approach.retries > 6 or not walkTowards(c) then
        approach = nil
        failure(tr('You cannot reach %s.', c:getName()))
      end
      if approach then approach.npcPos = npos end
    end
  end
  if conv then
    local c = conv.creature
    if c:isRemoved() or not L.inRange(p:getPosition(), c:getPosition()) then
      -- out of the talk radius: the server ends the conversation itself (its "walk away" line goes to the console)
      closeConversation(true)
    elseif now() - conv.lastActivity > IDLE_MS then
      closeConversation(true)
    elseif alive(bubble) and bubble:isVisible() then
      -- an NPC that already counts the player as its guest does not greet again: say so instead of waiting forever
      local status = (#conv.turn == 0 and now() - conv.lastActivity > 4000) and tr('No answer yet.') or conv.hint or ''
      if bubble.status:getText() ~= status then setStatus(status) end
      layout()
    end
  end
  if not conv and not approach then stopTicking() end
end

startTicking = function()
  if not tickEvent then tickEvent = cycleEvent(safe('tick', tick), TICK_MS) end
end

stopTicking = function()
  if tickEvent then
    removeEvent(tickEvent)
    tickEvent = nil
  end
  tracks = {}
end

-- ---------------------------------------------------------------- the console hooks (game_npctrade's functions)
-- an NPC line: true when the bubble took it (the console then leaves it out unless it keeps a copy)
local function onNpcLine(name, _, mode, text)
  if mode ~= MessageModes.NpcFrom and mode ~= MessageModes.NpcFromStartBlock then return false end
  if not enabled() or not name or name == '' or not text or text == '' then return false end
  local lname = name:lower()
  if conv and conv.name:lower() ~= lname then return false end -- another NPC: console
  if not conv then
    if suppressAllUntil > now() then return false end
    local creature = (approach and approach.creature:getName():lower() == lname and approach.creature) or findNpc(name)
    local p = player()
    if not creature or not p or not L.inRange(p:getPosition(), creature:getPosition(), L.TALK_RANGE + 1) then
      return false
    end
    openConversation(creature)
  end
  if not alive(bubble) then return false end
  if not bubble:isVisible() then showBubble() end
  table.insert(conv.turn, text)
  table.insert(conv.history, text)
  while #conv.history > MAX_TRANSCRIPT do table.remove(conv.history, 1) end
  table.insert(conv.transcript, { who = conv.name, text = text })
  while #conv.transcript > MAX_TRANSCRIPT do table.remove(conv.transcript, 1) end
  conv.lastActivity = now()
  refreshText()
  return not settings.consoleCopy
end

-- the player typed in the console's NPCs tab (the console has sent it already and leaves showing it to us)
local function onConsoleNpcTalk(text)
  if not text or text == '' then return end
  if not conv or settings.consoleCopy or not enabled() then copyPlayerLineToConsole(text) end
  if L.isGreeting(text) then
    suppressAllUntil = 0
  elseif L.isFarewell(text) and not conv then
    suppressAllUntil = now() + SUPPRESS_MS -- the farewells answering it stay in the console
  end
  if not conv then return end
  if L.isFarewell(text) then
    closeConversation(true)
    return
  end
  onPlayerSaid(text)
end

-- the player said something in Local Chat: a greeting opens the bubble for the NPC that answers
local function onConsoleLocalTalk(text)
  if not text then return end
  if L.isGreeting(text) then suppressAllUntil = 0 end
end

local function onEndNpcConversation(...)
  if conv then
    endConversation(true)
    return
  end
  if originals.endNpcConversation then return originals.endNpcConversation(...) end
end

local function onDialogWindowEnabled(on)
  if not on then closeConversation(false) end
end

local HOOKS = {
  tryHandleNpcDialogMessage = function(...) return onNpcLine(...) end,
  onNpcPlayerTalk = function(...) return onConsoleNpcTalk(...) end,
  onNpcConversationAttempt = function(...) return onConsoleLocalTalk(...) end,
  endNpcConversation = function(...) return onEndNpcConversation(...) end,
  closeNpcDialog = function(...) return onEndNpcConversation(...) end,
  setNpcDialogWindowEnabled = function(...) return onDialogWindowEnabled(...) end,
}

-- a map text ("<name> says:" ...) of the conversation NPC, at its tile, while the bubble shows
local function isConversationText(thing, pos)
  if type(thing) ~= 'userdata' or not pos or not enabled() or not alive(bubble) or not bubble:isVisible() then
    return false
  end
  local ok, text = pcall(function() return thing.addColoredMessage and thing:getText() end)
  if not ok or type(text) ~= 'string' then return false end
  local npos = conv.creature:getPosition()
  if not npos or L.distance(npos, pos) ~= 0 then return false end
  local prefix = conv.name:lower() .. ' says'
  return text:sub(1, #prefix):lower() == prefix
end

local function installHooks()
  local trade = modules.game_npctrade
  if trade then
    for name, fn in pairs(HOOKS) do
      originals[name] = rawget(trade, name) or trade[name]
      -- a failing hook must not lose the line: the console shows it then
      trade[name] = function(...)
        local ok, res = pcall(fn, ...)
        if not ok then
          warn(name, res)
          return false
        end
        return res
      end
    end
    -- the base window may be open already (a conversation before this module loaded)
    if originals.hideNpcDialog then pcall(originals.hideNpcDialog) end
  else
    warn('init', 'game_npctrade is not loaded: NPC lines stay in the console')
  end
  local gi = modules.game_interface
  if gi and gi.talkToNpc then
    origTalkToNpc = gi.talkToNpc
    gi.talkToNpc = safe('talkToNpc', talkTo)
  elseif gi and gi.addMenuHook then
    gi.addMenuHook('npcTalk', tr('Talk'), function(_, _, _, creature) talkTo(creature) end,
      function(_, _, _, creature) return isNpcCreature(creature) end)
  end
  -- the console writes every NPC line over the NPC's head too (Chat:sendMapText, just before it hands the line to
  -- us): the lines of the NPC in the bubble stay off the map, the bubble shows them
  origAddThing = g_map.addThing
  g_map.addThing = function(thing, pos, ...)
    if conv and isConversationText(thing, pos) then return end
    return origAddThing(thing, pos, ...)
  end
  -- "Use" on an NPC (the classic mouse controls and the menu's Use) does nothing on this server: it talks instead
  origUse = g_game.use
  g_game.use = function(thing, ...)
    if isNpcCreature(thing) then
      talkTo(thing)
      return
    end
    return origUse(thing, ...)
  end
end

local function removeHooks()
  local trade = modules.game_npctrade
  if trade then
    for name in pairs(HOOKS) do
      if originals[name] ~= nil then trade[name] = originals[name] end
    end
  end
  originals = {}
  local gi = modules.game_interface
  if gi and origTalkToNpc then gi.talkToNpc = origTalkToNpc end
  if gi and gi.removeMenuHook and not origTalkToNpc then pcall(gi.removeMenuHook, 'npcTalk') end
  origTalkToNpc = nil
  if origUse then g_game.use = origUse end
  origUse = nil
  if origAddThing then g_map.addThing = origAddThing end
  origAddThing = nil
end

-- ---------------------------------------------------------------- the "..." menu
local function showOptions()
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addCheckBoxOption(tr('Copy the dialogue to the console'), function()
    settings.consoleCopy = not settings.consoleCopy
    saveSettings()
  end, nil, settings.consoleCopy)
  menu:addSeparator()
  menu:addOption(tr('Talk in the console instead'), function()
    local cs = modules.client_settings
    if cs and cs.setOption then pcall(cs.setOption, 'disableNpcDialogWindow', true) end
    closeConversation(false) -- the NPC still listens: the talk goes on in the console's NPCs tab
    local console = modules.game_console
    if console and console.g_chat and console.g_chat.addTabMessages then
      pcall(console.g_chat.addTabMessages, console.g_chat, NPC_NAME_CHAT, true)
    end
    if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
      modules.game_textmessage.displayStatusMessage(
        tr('NPC dialogue window off. Options > Interface > "Disable NPC Dialog Window" turns it on again.'))
    end
  end)
  menu:display(g_window.getMousePosition())
end

-- ---------------------------------------------------------------- module
local function onEscape()
  if conv and alive(bubble) and bubble:isVisible() then
    endConversation(true)
    return true
  end
  return false
end

local function onRootEscape()
  onEscape()
  return false
end

local function onGameEnd()
  approach = nil
  closeConversation(false)
  suppressAllUntil = 0
end

function init()
  loadSettings()
  local root = rootPanel()
  if not root then
    warn('init', 'no game interface')
    return
  end
  g_ui.importStyle('npctalk')
  bubble = g_ui.createWidget('NpcTalkBubble', root)
  bubble:setId('npcTalkBubble')
  applyThemeFont(bubble.npcName, 'heading')
  bubble:hide()
  tail = g_ui.createWidget('NpcTalkTail', root)
  tail:setId('npcTalkTail')
  tail:hide()
  for _, id in ipairs(L.BUTTONS) do
    local word = id
    bubble.quickButtons[id].onClick = function() sendText(word) end
  end
  bubble.sayButton.onClick = function()
    local text = bubble.input:getText()
    bubble.input:clearText()
    sendText(text)
  end
  bubble.closeButton.onClick = function() endConversation(true) end
  bubble.optionsButton.onClick = showOptions
  g_keyboard.bindKeyPress('Enter', function()
    bubble.sayButton.onClick()
    return true -- not on to the game, which would switch the chat mode
  end, bubble.input)
  g_keyboard.bindKeyDown('Escape', onEscape, bubble)
  -- Esc with the map focused: the game's own Esc bindings run as well (this one never claims the key)
  g_keyboard.bindKeyDown('Escape', onRootEscape, root)
  escapeBound = true
  installHooks()
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  stopTicking()
  approach, conv = nil, nil
  removeHooks()
  local root = rootPanel()
  if escapeBound and root then
    pcall(g_keyboard.unbindKeyDown, 'Escape', onRootEscape, root)
  end
  escapeBound = false
  if alive(bubble) then bubble:destroy() end
  if alive(tail) then tail:destroy() end
  bubble, tail = nil, nil
end

-- for tests and other modules
function talkToNpc(creature) return talkTo(creature) end
function say(text) sendText(text) end
function close() endConversation(true) end
function isTalking() return conv ~= nil end
function getConversation()
  if not conv then return nil end
  return { name = conv.name, id = conv.id, turn = conv.turn, said = conv.said }
end
function getBubble() return bubble end
