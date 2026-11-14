-- NPC dialogue window (rebuilt in O571, owner 2026-11-14): talk to an NPC from its right-click menu ("Talk"), a left click
-- (smart controls) or "Use"; the player walks up to it when it is too far, says "hi", and the conversation runs in a window of
-- its own, beside the NPC and never over the character: the NPC's portrait (its own outfit, large), its name and title, the
-- whole conversation as a scrolling log (the NPC's lines with their {keywords} as gold clickable words, the player's lines
-- apart on the right), the keywords of the latest reply as chips in groups (quests marked, the most useful first), Yes / No /
-- Trade when they fit the reply, an input with Say, and Bye. Esc, Bye or the x end it ("bye"); walking out of the NPC's talk
-- radius closes it (the server ends the conversation then).
--
-- Every NPC works unchanged: nothing on the server. The 10.98 server sends an NPC's answers as private NPC speech
-- (MessageModes.NpcFrom / NpcFromStartBlock, the console's "NPCs" tab); the console hands those to
-- game_npctrade.tryHandleNpcDialogMessage first (the base client's own NPC dialog window); the game's own onTalk signal
-- brings the same line too (O160: the window does not depend on the console). This module replaces that
-- function and its companions (onNpcPlayerTalk, onNpcConversationAttempt, endNpcConversation,
-- setNpcDialogWindowEnabled), game_interface.talkToNpc (the menu's Talk), g_game.use on an NPC and g_map.addThing
-- (the conversation NPC's words over its head) while it is loaded and puts it all back on unload: lines of the NPC we
-- talk to go to the window, every other line (another NPC, a public "Good bye" when walking away) stays in the
-- console. The player's
-- words go out as the engine expects: "hi" in the default channel, the rest as private NPC talk (MessageModes.NpcTo),
-- the same packets the console's NPCs tab sends. Server windows (modal windows of the Ascendant Oracle and the Keeper
-- of Trials, the trade window) open as usual; the dialogue window stays where it is.
--
-- Settings: Options > Interface > "Disable NPC Dialog Window" (the base client's option) turns the window off: NPC
-- talk stays in the console as before, Talk still walks up and greets. g_settings node 'npcTalk': consoleCopy (also
-- copy the conversation into the console's NPCs tab), from the window's "..." menu.
-- The logic without client API (keywords, groups, buttons, geometry) is npctalk_logic.lua, the widgets npctalkview.lua.

local L = NpcTalkLogic

local APPROACH_TIMEOUT = 10000 -- walking up to an NPC gives up after this long
local SUPPRESS_MS = 3000       -- after a goodbye, the NPC's farewell goes to the console, not to a new window
local SWITCH_GAP_MS = 1500     -- Talk to another NPC: "bye" to the first, "hi" this much later
local IDLE_MS = 120000         -- the stock NpcHandler forgets an idle player after 120 s; so does the window
local TICK_MS = 20
local MAX_TRANSCRIPT = 40

local window, view
local settings = { consoleCopy = false }
local originals = {}
local origTalkToNpc, origUse, origAddThing
local tickEvent
local escapeBound = false

-- the conversation: {id, name, creature, turn = {npc lines}, said, history = {all npc lines}, transcript = {{side, who,
-- text}} (the log), placed, started, lastActivity}; approach: {creature, started}
local conv
local approach
local suppressAllUntil = 0 -- until then NPC lines stay in the console (the farewells answering a goodbye)
local tracks = {}     -- creature id -> {pos, from}: the last step, for the walk offset

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

-- ---------------------------------------------------------------- walk offsets (the window is placed by where the walking NPC is drawn)
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

-- ---------------------------------------------------------------- the window
local function setStatus(text)
  if view then view:setStatus(text or '') end
end

local sendText -- forward

local function tradeIsOpen()
  local trade = modules.game_npctrade
  return trade and trade.isTrading and trade.isTrading() or false
end

-- the title line under the NPC's name: a word of its name ("Archivist Maelis"), else what the conversation shows it to be
local function refreshTitle()
  if not conv or not view then return end
  local _, title = L.splitName(conv.name)
  if not title then
    local role = L.role(conv.history, tradeIsOpen())
    if role == 'trade' then title = tr('Trader') elseif role == 'quests' then title = tr('Has quests') end
  end
  view:setTitle(title or '')
end

local function layoutContent()
  if not alive(window) or not view then return end
  local inner = window:getWidth() - window:getPaddingLeft() - window:getPaddingRight()
  view:layoutChips(inner)
  view:setQuickWidth(inner)
end

local function refreshChipsAndButtons()
  if not conv or not alive(window) then return end
  local shown = L.buttons(conv.turn, conv.history, tradeIsOpen())
  -- the keywords a quick button already offers are no chips (the Bye button is always there)
  local offered = { bye = true }
  for _, id in ipairs(L.BUTTONS) do if shown[id] then offered[id] = true end end
  view:setButtons(shown)
  view:setChips(L.groups(L.chips(conv.turn, offered)))
  conv.hint = #L.keywords(conv.turn) > 0 and tr('Click a gold word to say it.') or nil
  layoutContent()
end

-- the log: everything said so far, the NPC's lines and the player's apart
local function refreshText()
  if not conv or not alive(window) then return end
  view:renderLog(conv.transcript, #conv.turn == 0)
  refreshChipsAndButtons()
  refreshTitle()
end

local function focusInput()
  if alive(window) and window:isVisible() then
    window:raise()
    -- the whole chain up to the root: a relog can leave the root's focus on another window
    view:focusInput()
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
  for _, id in ipairs({ 'bottomSplitter', 'gameBottomActionPanel', 'gameBottomPanel', 'chaosHotbar' }) do
    local b = child(id)
    if b and b.y > r.y + r.height / 2 then limits.bottom = math.min(limits.bottom, b.y) end
  end
  local bar = child('chaosMenuBar')
  if bar and bar.y < r.y + 60 then limits.top = math.max(limits.top, bar.y + bar.height) end
  return limits
end

-- Where the window opens (one place for it: O572): beside the NPC on the side away from the player, never over either of
-- them, inside the part of the map the player sees; the middle of that part when the NPC is not on screen. Done once per
-- conversation: the window is draggable and stays where the player puts it.
local function placeWindow()
  if not conv or not alive(window) then return end
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
  local npcAt = L.tileCenter(mapArea, stretch, spriteSize, cam, walkOffset(p, spriteSize), c:getPosition(),
    walkOffset(c, spriteSize))
  local playerAt = L.tileCenter(mapArea, stretch, spriteSize, cam, walkOffset(p, spriteSize), p:getPosition(),
    walkOffset(p, spriteSize))
  local w, h = L.windowSize(area)
  window:setSize({ width = w, height = h })
  local spot
  if npcAt then
    local r = rootPanel():getRect()
    local screen = { x = r.x, y = math.max(r.y, screenLimits().top or r.y), width = r.width, height = r.height }
    screen.height = r.y + r.height - screen.y
    spot = L.windowPlace(w, h, npcAt, playerAt, spriteSize * stretch, area, 8, screen)
  else
    spot = { x = area.x + math.floor((area.width - w) / 2), y = area.y + math.floor((area.height - h) / 2) }
  end
  window:setPosition(spot)
  conv.placed = true
  layoutContent()
end

local function hideWindow()
  if alive(window) then window:hide() end
end

local function showWindow()
  if not alive(window) then return end
  window:show()
  if conv and not conv.placed then placeWindow() else layoutContent() end
  window:raise()
end

-- ---------------------------------------------------------------- conversation
local stopTicking

local function closeConversation(suppress)
  -- a goodbye reaches every NPC in range that was listening (a "hi" greets them all): their farewells stay in the
  -- console instead of opening a new window
  if suppress then suppressAllUntil = now() + SUPPRESS_MS end
  conv = nil
  hideWindow()
  if alive(window) and view then
    view:renderLog({}, false)
    view:setChips({})
    view:clearInput()
  end
  if not approach then stopTicking() end
end

local startTicking

local function openConversation(creature)
  conv = {
    id = creature:getId(), name = creature:getName(), creature = creature,
    turn = {}, history = {}, transcript = {}, started = now(), lastActivity = now(),
  }
  if not alive(window) then return end
  local outfit = creature:getOutfit()
  local okType, thingType = pcall(g_things.getThingType, outfit.type or 0, ThingCategoryCreature)
  local big = okType and thingType and math.max(thingType:getWidth(), thingType:getHeight()) >= 2
  local who, title = L.splitName(conv.name)
  view:setNpc({ name = who, title = title, outfit = outfit, big = big })
  if enabled() then
    showWindow()
    refreshText()
    focusInput()
  end
  startTicking()
end

-- "bye" to the NPC (unless already said), the trade window shut, the dialogue window closed
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

-- the player said something to the NPC (from the window, or typed in the console's NPCs tab)
local function onPlayerSaid(text)
  if not conv then return end
  conv.said = text
  conv.turn = {}
  conv.lastActivity = now()
  table.insert(conv.transcript, { side = 'player', who = tr('You'), text = text })
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
  table.insert(conv.transcript, { side = 'player', who = tr('You'), text = 'hi' })
  if alive(window) and window:isVisible() then refreshText() end
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
    -- the window is open already; greet again when the NPC opened it by itself (a goodbye of its own, say) or left
    -- the last words unanswered
    if not conv.said or (#conv.turn == 0 and now() - conv.lastActivity > 4000) then greet(creature) end
    if enabled() then
      showWindow()
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

-- ---------------------------------------------------------------- the tick: approach, range, idle
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
    elseif alive(window) and window:isVisible() then
      -- an NPC that already counts the player as its guest does not greet again: say so instead of waiting forever
      local status = (#conv.turn == 0 and now() - conv.lastActivity > 4000) and tr('No answer yet.') or conv.hint or ''
      if view:status() ~= status then setStatus(status) end
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
-- the NPC standing on `pos`, among the creatures on screen
local function findNpcAt(pos)
  local p = player()
  if not p or not pos then return nil end
  for _, c in ipairs(g_map.getSpectators(p:getPosition(), false) or {}) do
    if c:isNpc() and L.samePos(c:getPosition(), pos) then return c end
  end
  return nil
end

local lastLine -- {name, text, at, handled}: the line the window saw last (the hook and the talk signal both bring it)

-- one line of an NPC: true when the window took it (the console then leaves it out unless it keeps a copy)
local function onNpcLine(name, _, mode, text, pos)
  local route = L.routeNpcLine({ mode = mode, name = name, text = text, pos = pos }, {
    modes = { npcFrom = MessageModes.NpcFrom, npcFromStartBlock = MessageModes.NpcFromStartBlock },
    enabled = enabled(),
    suppressed = suppressAllUntil > now(),
    conv = conv and { name = conv.name, pos = conv.creature:getPosition() } or nil,
  })
  if route == 'open' then
    local lname = name:lower()
    local creature = (approach and approach.creature:getName():lower() == lname and approach.creature) or
      findNpcAt(pos) or findNpc(name)
    local p = player()
    if not creature or not p or not L.inRange(p:getPosition(), creature:getPosition(), L.TALK_RANGE + 1) then
      return false
    end
    openConversation(creature)
    route = 'conv'
  end
  if route ~= 'conv' then return false end
  if not alive(window) then return false end
  if not window:isVisible() then showWindow() end
  table.insert(conv.turn, text)
  table.insert(conv.history, text)
  while #conv.history > MAX_TRANSCRIPT do table.remove(conv.history, 1) end
  table.insert(conv.transcript, { side = 'npc', who = conv.name, text = text })
  while #conv.transcript > MAX_TRANSCRIPT do table.remove(conv.transcript, 1) end
  conv.lastActivity = now()
  refreshText()
  return not settings.consoleCopy
end

-- Every NPC line comes in twice: through the console (its hook, which also keeps the line out of the console) and
-- through the game's talk signal below, which does not depend on the console at all (a console that stops short, or a
-- hook that is not in place, no longer leaves the window at "..."). The second copy answers as the first did.
local function deliverNpcLine(name, mode, text, pos)
  local at = now()
  if L.isDuplicate(lastLine, name, text, at) then return lastLine.handled end
  local handled = onNpcLine(name, nil, mode, text, pos)
  lastLine = { name = name, text = text, at = at, handled = handled }
  return handled
end

local function onTalkSignal(name, _, mode, text, _, pos)
  local ok, err = pcall(deliverNpcLine, name, mode, text, pos)
  if not ok then warn('onTalk', err) end
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

-- the player said something in Local Chat: a greeting opens the window for the NPC that answers
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
  tryHandleNpcDialogMessage = function(name, _, mode, text) return deliverNpcLine(name, mode, text, nil) end,
  onNpcPlayerTalk = function(...) return onConsoleNpcTalk(...) end,
  onNpcConversationAttempt = function(...) return onConsoleLocalTalk(...) end,
  endNpcConversation = function(...) return onEndNpcConversation(...) end,
  closeNpcDialog = function(...) return onEndNpcConversation(...) end,
  setNpcDialogWindowEnabled = function(...) return onDialogWindowEnabled(...) end,
}

-- a map text ("<name> says:" ...) of the conversation NPC, at its tile, while the window shows
local function isConversationText(thing, pos)
  if type(thing) ~= 'userdata' or not pos or not enabled() or not alive(window) or not window:isVisible() then
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
  -- us): the lines of the NPC in the window stay off the map, the window shows them
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
  if conv and alive(window) and window:isVisible() then
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
  window = g_ui.createWidget('NpcTalkWindow', root)
  window:setId('npcTalkWindow')
  window.chaosNoMirror = true -- the NPC's portrait is a creature widget: the RmlUi window mirror leaves it in OTUI
  window:hide()
  view = NpcTalkView.new(window)
  view.on.say = function(text) sendText(text) end
  view.on.word = function(word) sendText(word) end
  view.on.bye = function() endConversation(true) end
  view.on.close = function() endConversation(true) end
  view.on.options = showOptions
  g_keyboard.bindKeyPress('Enter', function()
    view.ui.sayButton.onClick()
    return true -- not on to the game, which would switch the chat mode
  end, view.ui.input)
  g_keyboard.bindKeyDown('Escape', onEscape, window)
  -- Esc with the map focused: the game's own Esc bindings run as well (this one never claims the key)
  g_keyboard.bindKeyDown('Escape', onRootEscape, root)
  escapeBound = true
  installHooks()
  connect(g_game, { onGameEnd = onGameEnd, onTalk = onTalkSignal })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd, onTalk = onTalkSignal })
  stopTicking()
  approach, conv = nil, nil
  removeHooks()
  local root = rootPanel()
  if escapeBound and root then
    pcall(g_keyboard.unbindKeyDown, 'Escape', onRootEscape, root)
  end
  escapeBound = false
  if alive(window) then window:destroy() end
  window, view = nil, nil
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
function getWindow() return window end
