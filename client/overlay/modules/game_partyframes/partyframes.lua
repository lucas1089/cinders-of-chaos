-- Party frames: a compact movable panel with a frame for every member of the character's party: outfit, name in the
-- class colour, level, leader crown, health and mana bars with numbers, the floor and distance, in fight / dead /
-- connection lost, and the member's first few buffs and debuffs. It updates live (the server sends the party's state
-- every 500 ms to clients that have the frames open, extended opcode 235, server partyframes.lua) and hides by itself
-- when the character is not in a party. Members in range show exact numbers; far members only a rough health bar.
-- Left click selects a member (and follows them while "clicking follows" is on), shift+click looks, right click opens
-- the menu (message, follow, look, pass the leadership and remove from the party for the leader, leave the party).
-- Movable (grab the strip on top), scale, own frame, buffs row, numbers, follow and lock are in the gear window, saved in
-- g_settings node 'chaosPartyFrames'. Pure parts: partymath.lua (partymath_test.lua). Menu: Hunt > Party Frames.

local OPCODE = 235
local NODE = 'chaosPartyFrames'
-- without a saved position the frames go to the right edge of the game view, between the map overlay's corner box and
-- its control strip (PartyMath.defaultPosition); the character plate, the buff bar and the rift / invasion HUDs are top
-- left. Before 2026-10-10 the default was 40, 296 (under the invasion HUD); saved positions are kept as they are.
local HEADER, GAP = 12, 2

local panel, settingsWindow, inviteWindow
local state = { members = {} }
local settings = PartyMath.sanitize(nil)
local frames = {}       -- member id -> frame widget
local selectedId
local tickEvent
local dragOffset
local watching = false

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function now() return g_clock.seconds() end

-- ---------------------------------------------------------------- settings
local function loadSettings()
  local ok, node = pcall(g_settings.getNode, NODE)
  settings = PartyMath.sanitize(ok and node or nil)
end

local function saveSettings()
  pcall(g_settings.setNode, NODE, settings)
  pcall(g_settings.save) -- a client that crashes or is killed keeps the position too
end

-- ---------------------------------------------------------------- server
local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function startWatching()
  if settings.shown and g_game.isOnline() then
    watching = true
    send('open', { buffs = settings.showBuffs })
  end
end

local function stopWatching()
  if watching then
    watching = false
    send('close')
  end
end

-- ---------------------------------------------------------------- frames
local function setIcon(widget, spec)
  local src, clip = '/images/game/buffs/spellbuff', nil
  local bb = modules.game_buffbar
  if bb and type(bb.iconFor) == 'function' then
    local ok, icon = pcall(bb.iconFor, spec, nil)
    if ok and icon then src, clip = icon.src, icon.clip end
  end
  widget:setImageSource(src)
  widget:setImageClip(clip or '0 0 26 26') -- our own buff icons are 26 x 26 (game_buffbar BuffMath.OWN_CLIP)
end

local function creatureOf(id)
  local ok, c = pcall(g_map.getCreatureById, id)
  return ok and c or nil
end

local function followOrStop(m)
  local creature = creatureOf(m.id)
  if not creature then return false end
  if g_game.getFollowingCreature() == creature then
    g_game.cancelFollow()
  else
    g_game.follow(creature)
  end
  return true
end

local updateAllFrames -- defined below

local function selectMember(m)
  selectedId = (selectedId ~= m.id) and m.id or selectedId
  if settings.follow and not PartyMath.flag(m, 'self') then followOrStop(m) end
  updateAllFrames()
end

local function showMenu(m)
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  local isSelf = PartyMath.flag(m, 'self')
  local leader = PartyMath.viewerIsLeader(state)
  if not isSelf then
    menu:addOption(tr('Message to %s', m.name), function() g_game.openPrivateChannel(m.name) end)
    local following = g_game.getFollowingCreature()
    local creature = creatureOf(m.id)
    if creature and following == creature then
      menu:addOption(tr('Stop following'), function() g_game.cancelFollow() end)
    elseif creature then
      menu:addOption(tr('Follow'), function() g_game.follow(creature) end)
    end
    if creature then menu:addOption(tr('Look'), function() g_game.look(creature) end) end
    menu:addSeparator()
  end
  if leader and not isSelf then
    menu:addOption(tr('Pass Leadership to %s', m.name), function() g_game.partyPassLeadership(m.id) end)
    menu:addOption(tr('Remove %s from the party', m.name), function() send('kick', { id = m.id }) end)
  end
  menu:addOption(tr('Invite a player...'), function() openInvite() end)
  if isSelf then
    menu:addOption(tr('Leave Party'), function() g_game.partyLeave() end)
  end
  menu:addSeparator()
  menu:addOption(tr('Copy Name'), function() g_window.setClipboardText(m.name) end)
  menu:display(g_window.getMousePosition())
end

local function onFramePress(frame, pos, button)
  local m = frame.member
  if not m then return false end
  if button == MouseLeftButton then
    if g_keyboard.isShiftPressed() then
      local creature = creatureOf(m.id)
      if creature then g_game.look(creature) end
    else
      selectMember(m)
    end
    return true
  elseif button == MouseRightButton then
    showMenu(m)
    return true
  end
  return false
end

local function frameFor(m)
  local f = frames[m.id]
  if not alive(f) then
    f = g_ui.createWidget('PartyFrame', panel)
    f:setId('member_' .. m.id)
    f.onMousePress = onFramePress
    frames[m.id] = f
  end
  return f
end

local function updateFrame(f, m, t, stale)
  f.member = m
  local scale = settings.scale
  local sc = function(px) return PartyMath.scaled(px, scale) end
  local word = PartyMath.stateWord(m, stale)
  local far = m.far

  f:setSize({ width = sc(PartyMath.FRAME_W), height = PartyMath.frameHeight(m, settings) })
  f:setOpacity((word == 'offline' or far) and 0.7 or 1.0)
  f:setBorderColor(selectedId == m.id and '#f6cf72' or (word == 'fight' and '#a8321f' or '#3a3339'))

  local outfit = f:getChildById('outfit')
  outfit:setSize({ width = sc(34), height = sc(34) })
  local key = m.outfit and table.concat({ m.outfit.type, m.outfit.head, m.outfit.body, m.outfit.legs, m.outfit.feet, m.outfit.addons }, ',') or ''
  if f.outfitKey ~= key and m.outfit then
    f.outfitKey = key
    outfit:setOutfit(m.outfit)
  end
  f:getChildById('level'):setText(tostring(m.level))

  local vocName, vocColor = PartyMath.vocation(m.voc)
  local nameLabel = f:getChildById('name')
  nameLabel:setText(m.name)
  nameLabel:setColor(word == 'dead' and '#7d7176' or vocColor)
  local crown = f:getChildById('crown')
  local leader = PartyMath.flag(m, 'leader')
  crown:setVisible(leader)
  nameLabel:setMarginLeft(leader and 20 or 4)
  nameLabel:setWidth(sc(86) - (leader and 16 or 0))

  local dist = f:getChildById('dist')
  dist:setText(PartyMath.distanceText(m))
  local floorMark = f:getChildById('floor')
  local floorCount = f:getChildById('floorCount')
  local dir, n = PartyMath.floorMark(m.dz)
  if dir then
    floorMark:setImageSource('/images/game/partyframes/' .. dir)
    floorMark:setVisible(true)
    floorCount:setText(tostring(n))
    floorCount:setVisible(true)
  else
    floorMark:setVisible(false)
    floorCount:setVisible(false)
  end
  local stateMark = f:getChildById('state')
  if word then
    stateMark:setImageSource('/images/game/partyframes/' .. word)
    stateMark:setVisible(true)
  else
    stateMark:setVisible(false)
  end

  local hp, mp = f:getChildById('hp'), f:getChildById('mp')
  hp:setHeight(sc(11))
  mp:setHeight(sc(11))
  hp:setMarginTop(sc(16))
  hp:setPercent(m.pct)
  hp:setBackgroundColor(PartyMath.hpColor(m.pct))
  hp:setText(settings.showNumbers and PartyMath.hpText(m) or '')
  mp:setVisible(not far)
  mp:setPercent(PartyMath.mpPct(m))
  mp:setText(settings.showNumbers and PartyMath.mpText(m) or '')

  local row = f:getChildById('buffs')
  row:setVisible(settings.showBuffs and not far and #m.buffs > 0)
  row:setMarginTop(sc(2))
  if row:isVisible() then
    local size, x = sc(14), 0
    local keep = {}
    for i, b in ipairs(m.buffs) do
      local w = row:getChildByIndex(i)
      if not w then w = g_ui.createWidget('PartyBuffIcon', row) end
      w:setSize({ width = size, height = size })
      w:setBorderColor(b.debuff and '#c9301f' or '#b8923a')
      setIcon(w, b.icon)
      w:addAnchor(AnchorTop, 'parent', AnchorTop)
      w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      w:setMarginLeft(x)
      w:setVisible(true)
      x = x + size + 2
      keep[i] = true
    end
    for i = #m.buffs + 1, row:getChildCount() do row:getChildByIndex(i):setVisible(false) end
  end
  f:setTooltip(PartyMath.tooltip(m, t))
end

updateAllFrames = function()
  if not alive(panel) then return end
  local t = now()
  local stale = PartyMath.stale(state, t)
  local members = PartyMath.visible(state, settings.showSelf)
  local keep = {}
  local ys, total = PartyMath.column(members, settings, HEADER, GAP)
  for i, m in ipairs(members) do
    local f = frameFor(m)
    keep[m.id] = true
    updateFrame(f, m, t, stale)
    f:addAnchor(AnchorTop, 'parent', AnchorTop)
    f:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    f:setMarginTop(ys[i])
    f:setMarginLeft(0)
  end
  for id, f in pairs(frames) do
    if not keep[id] then
      if alive(f) then f:destroy() end
      frames[id] = nil
    end
  end
  if selectedId and not keep[selectedId] then selectedId = nil end
  panel:setSize({ width = PartyMath.scaled(PartyMath.FRAME_W, settings.scale), height = math.max(total, HEADER + 1) })
  local title = panel:getChildById('header'):getChildById('title')
  title:setText(#members > 0 and tr('Party (%d)', #(state.members or {})) or tr('Party'))
  local inParty = PartyMath.inParty(state)
  panel:getChildById('header'):getChildById('invite'):setVisible(true)
  local visible = g_game.isOnline() and settings.shown and #members > 0
  panel:setVisible(visible)
  if visible then
    -- above the map overlay (game_mapoverlay draws the explored map see-through over the game view)
    local parent = panel:getParent()
    local overlay = parent and parent:getChildById('mapOverlay')
    if overlay and parent:getChildIndex(overlay) > parent:getChildIndex(panel) then panel:raise() end
  end
end

-- the default margins for the current layout (side panels and console can change)
local function defaultMargins(parent)
  local gi = modules.game_interface
  local sides, bottoms = {}, {}
  local function rectOf(name, list)
    local ok, w = pcall(function() return gi[name] and gi[name]() end)
    if ok and w and w:isVisible() then list[#list + 1] = w:getRect() end
  end
  rectOf('getRightPanel', sides)
  rectOf('getLeftPanel', sides)
  rectOf('getBottomPanel', bottoms)
  rectOf('getBottomActionPanel', bottoms)
  local free = PartyMath.freeArea(parent:getRect(), { width = g_window.getWidth(), height = g_window.getHeight() }, sides, bottoms)
  local pr = parent:getRect()
  return PartyMath.defaultPosition(free, panel:getWidth(), panel:getHeight(), pr.x, pr.y)
end

local function clampPanel()
  if not alive(panel) then return end
  if dragOffset then return end -- the hand is moving it
  local parent = panel:getParent()
  if not parent then return end
  local x, y = settings.x, settings.y
  if not x or not y then x, y = defaultMargins(parent) end
  x, y = PartyMath.clampPosition(x, y, panel:getWidth(), panel:getHeight(), parent:getWidth(), parent:getHeight())
  panel:setMarginLeft(x)
  panel:setMarginTop(y)
end

local function tick()
  if not alive(panel) or not g_game.isOnline() then return end
  updateAllFrames()
  clampPanel()
end

-- ---------------------------------------------------------------- opcode
local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then return end
  if msg.action == 'state' then
    PartyMath.apply(state, msg.data, now())
    updateAllFrames()
  end
end

-- ---------------------------------------------------------------- windows
local function syncSettingsWindow()
  if not alive(settingsWindow) then return end
  settingsWindow:recursiveGetChildById('scaleValue'):setText(settings.scale .. '%')
  settingsWindow:recursiveGetChildById('shownBox'):setChecked(settings.shown)
  settingsWindow:recursiveGetChildById('selfBox'):setChecked(settings.showSelf)
  settingsWindow:recursiveGetChildById('buffsBox'):setChecked(settings.showBuffs)
  settingsWindow:recursiveGetChildById('numbersBox'):setChecked(settings.showNumbers)
  settingsWindow:recursiveGetChildById('followBox'):setChecked(settings.follow)
  settingsWindow:recursiveGetChildById('lockBox'):setChecked(settings.locked)
end

function toggleSettings()
  if not alive(settingsWindow) then
    settingsWindow = g_ui.createWidget('PartyFramesSettings', g_ui.getRootWidget())
    settingsWindow:hide()
  end
  if settingsWindow:isVisible() then
    settingsWindow:hide()
  else
    syncSettingsWindow()
    settingsWindow:show()
    settingsWindow:raise()
    settingsWindow:focus()
  end
end

function stepScale(dir)
  settings.scale = PartyMath.stepScale(settings.scale, dir)
  saveSettings()
  syncSettingsWindow()
  updateAllFrames()
  clampPanel()
end

function setOption(name, value)
  if settings[name] == nil or settings[name] == value then return end
  settings[name] = value
  saveSettings()
  if name == 'shown' then
    if value then startWatching() else stopWatching() end
  elseif name == 'showBuffs' and watching then
    send('open', { buffs = value })
  end
  updateAllFrames()
end

function resetPosition()
  settings.x, settings.y = nil, nil
  saveSettings()
  clampPanel()
end

function openInvite()
  if not alive(inviteWindow) then
    inviteWindow = g_ui.createWidget('PartyInviteWindow', g_ui.getRootWidget())
  end
  inviteWindow:recursiveGetChildById('name'):clearText()
  inviteWindow:show()
  inviteWindow:raise()
  inviteWindow:focus()
  inviteWindow:recursiveGetChildById('name'):focus()
end

function closeInvite()
  if alive(inviteWindow) then inviteWindow:hide() end
end

function sendInvite()
  if not alive(inviteWindow) then return end
  local name = inviteWindow:recursiveGetChildById('name'):getText():trim()
  if #name >= 2 then send('invite', { name = name }) end
  closeInvite()
end

local function say(text)
  local tm = modules.game_textmessage
  if tm and type(tm.displayStatusMessage) == 'function' then pcall(tm.displayStatusMessage, text) end
end

-- menu entry: shows / hides the frames (they only show while the character is in a party, so say what happened)
function toggle()
  setOption('shown', not settings.shown)
  syncSettingsWindow()
  if settings.shown then
    say(PartyMath.inParty(state) and tr('Party frames on.') or tr('Party frames on: they show while you are in a party.'))
  else
    say(tr('Party frames off.'))
  end
end

function isShown() return settings.shown end
function getSelectedId() return selectedId end

-- ---------------------------------------------------------------- dragging
local function onHeaderPress(w, pos, button)
  if button == MouseRightButton then
    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)
    menu:addOption(tr('Invite a player...'), function() openInvite() end)
    menu:addOption(tr('Settings...'), function() toggleSettings() end)
    menu:display(g_window.getMousePosition())
    return true
  end
  if button ~= MouseLeftButton or settings.locked then return false end
  dragOffset = { x = pos.x - panel:getX(), y = pos.y - panel:getY() }
  w:grabMouse()
  return true
end

local function onHeaderMove(w, pos, moved)
  if not dragOffset then return false end
  local parent = panel:getParent()
  local x, y = PartyMath.clampPosition(pos.x - dragOffset.x - parent:getX(), pos.y - dragOffset.y - parent:getY(),
    panel:getWidth(), panel:getHeight(), parent:getWidth(), parent:getHeight())
  panel:setMarginLeft(x)
  panel:setMarginTop(y)
  return true
end

local function onHeaderRelease(w, pos, button)
  if not dragOffset then return false end
  dragOffset = nil
  w:ungrabMouse()
  local parent = panel:getParent()
  settings.x = panel:getX() - parent:getX()
  settings.y = panel:getY() - parent:getY()
  saveSettings()
  return true
end

-- ---------------------------------------------------------------- lifecycle
local function onGameStart()
  PartyMath.clear(state)
  watching = false
  updateAllFrames()
  clampPanel()
  scheduleEvent(function() startWatching() end, 400)
end

local function onGameEnd()
  watching = false
  PartyMath.clear(state)
  selectedId = nil
  updateAllFrames()
  if alive(panel) then panel:hide() end
end

function init()
  g_ui.importStyle('partyframes')
  loadSettings()
  panel = g_ui.createWidget('PartyFrames', modules.game_interface.getMapPanel())
  local header = panel:getChildById('header')
  header.onMousePress = onHeaderPress
  header.onMouseMove = onHeaderMove
  header.onMouseRelease = onHeaderRelease
  panel:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  tickEvent = cycleEvent(tick, 250)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  stopWatching()
  for _, f in pairs(frames) do if alive(f) then f:destroy() end end
  frames = {}
  if alive(settingsWindow) then settingsWindow:destroy() end
  if alive(inviteWindow) then inviteWindow:destroy() end
  if alive(panel) then panel:destroy() end
  panel, settingsWindow, inviteWindow = nil, nil, nil
end
