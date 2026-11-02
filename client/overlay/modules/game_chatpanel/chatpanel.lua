-- game_chatpanel: size and place of the bottom area (action bars + console) (client/MANIFEST.md "Chat panel").
-- * The group life orb + chat + mana orb is centred in the game window by default and re-centred when the window
--   changes. The orbs (game_shaderfx) are anchored to the chat's edges and follow it.
-- * Move: the handle above the chat's top-left corner (ChaosChatMoveHandle, its title) or the grip on its left edge
--   (ChaosChatMoveGrip) drag the chat anywhere in the game area, clamped to the screen (up only in the extended view:
--   the classic view docks the map above it). Double-click puts it back at the bottom centre; a move that ends near
--   the centre or the bottom edge snaps back there.
-- * Width: the grip on the right edge (ChaosChatWidthGrip) moves the right edge only, the left edge stays (it used to
--   widen around the centre, so near the right side the chat grew to the left). Double-click: the default width.
-- * Height: the base splitter above the action bars (bottomSplitter; base patch 0065 makes its drag reliable).
-- Width, height and place are kept per character in the client settings (node chaos_chatpanel) and clamped to the
-- window (chatpanel_logic.lua, tested by chatpanel_test.lua). The lift (the chat moved up) goes into the splitter's
-- bottom margin (height + lift) and the console's (gameBottomPanel); the splitter's own height rules are wrapped so
-- they keep working on the height alone. The splitter's left margin belongs to this module while
-- it runs: base patch 0065 hands game_interface's own value (the reserved left column) to relayout.
ChaosChatPanel = ChaosChatPanel or {}
local M = ChaosChatPanel
local L = ChaosChatLogic

local SETTINGS_NODE = 'chaos_chatpanel'
local BASE_RIGHT_MARGIN = 1 -- bottomSplitter's margin-right in game_interface's otui

local widthGrip, moveGrip, handle = nil, nil, nil
local wantedWidth = L.DEFAULT_WIDTH
local placeX = nil -- the chat's left edge from the window's left edge; nil: centred
local legacyOffset = nil -- a place saved before placeX (pixels from the centre); the first layout turns it into placeX
local lift = 0 -- pixels between the window's bottom edge and the group (0: on the bottom edge)
local appliedLift = 0 -- the lift in the splitter's bottom margin and the console's now
local character = nil
local drag = nil -- {grip, kind = 'width' | 'move', start = {x, lift, mouseX, mouseY}}
local lastPlace = nil
local baseCanUpdate, baseGeometry = nil, nil -- the splitter's own functions (game_interface's otui)

local function root()
  local gi = modules.game_interface
  return gi and gi.getRootPanel and gi.getRootPanel() or nil
end

local function splitter()
  local r = root()
  return r and r:getChildById('bottomSplitter') or nil
end

local function child(id)
  local r = root()
  local w = r and r:getChildById(id)
  if w and w:isVisible() and w:getWidth() > 0 then return w end
end

-- the smallest chat height (action bars + a few lines), from the splitter's own rule
local function minimumHeight(s)
  local f = baseCanUpdate or s.canUpdateMargin
  if f then
    local ok, v = pcall(f, s, 0)
    if ok and tonumber(v) then return tonumber(v) end
  end
  return 150
end

local function orbSize()
  local fx = modules.game_shaderfx
  if fx and type(fx.getOrbReserve) == 'function' then
    local ok, v = pcall(fx.getOrbReserve)
    if ok then return tonumber(v) or 0 end
  end
  return 0
end

-- the classic view docks the map above the bottom area: the chat stays on the bottom edge there
local function canLift()
  local ok, classic = pcall(function()
    return g_settings.getBoolean('classicView') and not g_gameConfig.isExtendedViewUI()
  end)
  return not (ok and classic)
end

-- x of the splitter's anchor lines and the region the group may use: the whole game area between the side panels
-- (the reserved left column and the side action bars no longer limit it: the player places the chat)
local function region()
  local r = root()
  local lp, rp = child('gameLeftPanels'), child('gameRightPanels')
  local anchorLeft = lp and (lp:getX() + lp:getWidth()) or r:getX()
  local anchorRight = rp and rp:getX() or (r:getX() + r:getWidth())
  return anchorLeft, anchorRight, anchorLeft, anchorRight - BASE_RIGHT_MARGIN
end

local function chatHeight(s)
  return math.max(0, s:getMarginBottom() - appliedLift)
end

-- the side bars game_interface ends on the splitter's top edge: a lifted chat must not shorten them, so their bottom
-- margin loses the lift (they keep ending where they did)
local SIDE_BARS = { 'gameLeftTopBar', 'gameLeftActionPanel', 'gameRightTopBar', 'gameRightActionPanel' }
local sideBarMargins = {} -- id -> the bar's own bottom margin

-- the lift goes into the splitter's bottom margin (height + lift), the console's bottom margin and the grips'
local function applyLift(s, newLift)
  local height = chatHeight(s)
  appliedLift = newLift
  if s:getMarginBottom() ~= height + newLift then s:setMarginBottom(height + newLift) end
  local r = root()
  local bottom = r and r:getChildById('gameBottomPanel')
  if bottom and bottom:getMarginBottom() ~= newLift then bottom:setMarginBottom(newLift) end
  for _, g in ipairs({ widthGrip, moveGrip }) do
    if g and g:getMarginBottom() ~= newLift then g:setMarginBottom(newLift) end
  end
  for _, id in ipairs(SIDE_BARS) do
    local bar = r and r:getChildById(id)
    if bar then
      if sideBarMargins[id] == nil then sideBarMargins[id] = bar:getMarginBottom() end
      local margin = sideBarMargins[id] - newLift
      if bar:getMarginBottom() ~= margin then bar:setMarginBottom(margin) end
    end
  end
end

-- place the group (returns true when it did: base patch 0065 then leaves the splitter's left margin alone)
function M.relayout()
  local s, r = splitter(), root()
  if not s or not r or not g_game.isOnline() or g_app.isMobile() or not s:isVisible() then return false end
  local anchorLeft, anchorRight, left, right = region()
  local orb = orbSize()
  local place = L.layout({ regionLeft = left, regionRight = right, windowLeft = r:getX(), windowWidth = r:getWidth(),
    width = wantedWidth, x = placeX, offset = legacyOffset, orbSize = orb,
    keepLeft = drag ~= nil and drag.kind == 'width' })
  if legacyOffset then placeX, legacyOffset = place.x, nil end
  local ml, mr = L.splitterMargins(place, anchorLeft, anchorRight)
  if s:getMarginLeft() ~= ml then s:setMarginLeft(ml) end
  if s:getMarginRight() ~= mr then s:setMarginRight(mr) end
  place.orbSize = place.orbs and orb or 0
  local wanted = canLift() and lift or 0
  applyLift(s, L.clampLift(wanted, L.groupHeight(chatHeight(s), place.orbSize), r:getHeight()))
  lastPlace = place
  local fx = modules.game_shaderfx
  if orb > 0 and fx and type(fx.setOrbsFit) == 'function' then pcall(fx.setOrbsFit, place.orbs) end
  return true
end

-- game_shaderfx: the orbs' distance from the window's bottom edge follows the chat
function M.getLift()
  return appliedLift
end

local function save()
  local s = splitter()
  if not s or not character then return end
  local saved = g_settings.getNode(SETTINGS_NODE) or {}
  saved[character] = { width = wantedWidth, height = chatHeight(s), x = placeX, lift = lift }
  g_settings.setNode(SETTINGS_NODE, saved)
end

-- the splitter's own rules (game_interface's otui) think in its bottom margin; with a lift that margin is
-- height + lift, so the rules get the height and the lift is added back
local function wrapSplitter(s)
  if baseCanUpdate or not s.canUpdateMargin then return end
  baseCanUpdate, baseGeometry = s.canUpdateMargin, s.onGeometryChange
  s.canUpdateMargin = function(self, margin)
    local height = baseCanUpdate(self, margin - appliedLift)
    if appliedLift > 0 then
      -- a lifted chat grows up to the screen's top edge at most (handle included)
      local parent = self:getParent()
      local top = parent and (parent:getHeight() - appliedLift - L.SPLITTER - L.HANDLE_HEIGHT) or height
      height = math.max(minimumHeight(self), math.min(height, top))
    end
    return height + appliedLift
  end
  if baseGeometry then
    s.onGeometryChange = function(self, ...)
      local height = chatHeight(self)
      local parent = self:getParent()
      local cap = parent and math.max(parent:getHeight() - 150, minimumHeight(self)) or height
      local fixed = math.min(cap, height) + appliedLift
      if fixed ~= self:getMarginBottom() then self:setMarginBottom(fixed) end
    end
  end
end

local function unwrapSplitter(s)
  if not baseCanUpdate then return end
  if s then
    s.canUpdateMargin = baseCanUpdate
    s.onGeometryChange = baseGeometry
  end
  baseCanUpdate, baseGeometry = nil, nil
end

local function applySaved()
  local s = splitter()
  local player = g_game.getLocalPlayer()
  if not s or not player or g_app.isMobile() then return end
  character = player:getName()
  local size = L.sizeFor(g_settings.getNode(SETTINGS_NODE), character)
  wantedWidth = size.width
  placeX, legacyOffset = size.x, size.offset
  lift = size.lift or 0
  -- game_interface restored its own margin (which may hold an old lift): start from the bottom edge
  appliedLift = 0
  local r = root()
  local height = L.clampHeight(size.height, minimumHeight(s), r and r:getHeight() or 0)
  if s:getMarginBottom() ~= height then s:setMarginBottom(height) end
  M.relayout()
end

-- ---------------------------------------------------------------- the grips and the move handle
-- The cursor: pushed once on hover, popped once when neither hovered nor dragged (a drag that ends off the grip used
-- to leave it pushed, and a pushed cursor made the base splitter skip its own setup)
local function cursorOn(grip)
  if grip.cursorPushed then return end
  local name = grip.chaosCursor or 'horizontal'
  grip.cursorPushed = g_mouse.applyNativeCursor(name) and 'native' or 'pushed'
  if grip.cursorPushed == 'pushed' then g_mouse.pushCursor(name) end
end

local function cursorOff(grip)
  if not grip.cursorPushed then return end
  if grip.cursorPushed == 'native' then
    g_mouse.restoreNativeCursor()
  else
    g_mouse.popCursor(grip.chaosCursor or 'horizontal')
  end
  grip.cursorPushed = nil
end

local function onGripMove(self, mousePos)
  if not drag or drag.grip ~= self then return false end
  local r = root()
  if not r then return true end
  if drag.kind == 'width' then
    local chatLeft = lastPlace and lastPlace.chatLeft or 0
    wantedWidth = math.max(L.MIN_WIDTH, L.widthForGrip(mousePos.x, chatLeft))
  else
    placeX, lift = L.dragPlace(drag.start, mousePos.x, mousePos.y)
  end
  M.relayout()
  if lastPlace then
    if drag.kind == 'width' then wantedWidth = lastPlace.chatWidth end
    placeX = lastPlace.x
  end
  lift = appliedLift
  return true
end

-- kind 'width': the right edge's grip; 'move': the left edge's grip and the handle (title) above the chat
local function makeGrip(style, kind, isHandle)
  local grip = g_ui.createWidget(style, root())
  if isHandle then
    grip:addAnchor(AnchorBottom, 'bottomSplitter', AnchorTop)
    grip:addAnchor(AnchorLeft, 'bottomSplitter', AnchorLeft)
    grip.chaosCursor = 'pointer'
  else
    grip:addAnchor(AnchorTop, 'bottomSplitter', AnchorBottom)
    grip:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    grip:setMarginBottom(appliedLift)
    if kind == 'width' then
      grip:addAnchor(AnchorLeft, 'bottomSplitter', AnchorRight)
      grip:setMarginLeft(L.WIDTH_GRIP_GAP)
    else
      grip:addAnchor(AnchorRight, 'bottomSplitter', AnchorLeft)
      grip:setMarginRight(L.MOVE_GRIP_GAP)
      grip.chaosCursor = 'pointer'
    end
  end
  grip.onMousePress = function(self, mousePos, button)
    if button ~= MouseLeftButton then return false end
    local r = root()
    local place = lastPlace
    -- a centred chat gets a fixed left edge as soon as it is resized or moved: the width grip only moves the right
    -- edge, the move starts from where the chat is
    if place and r then placeX = place.chatLeft - r:getX() end
    drag = { grip = self, kind = kind,
             start = { x = placeX or 0, lift = appliedLift, mouseX = mousePos.x, mouseY = mousePos.y } }
    cursorOn(self)
    return true
  end
  grip.onMouseMove = onGripMove
  grip.onMouseRelease = function(self)
    if drag and drag.grip == self then
      local kind = drag.kind
      drag = nil
      if lastPlace then
        if kind == 'move' then
          placeX, lift = L.snapPlace(lastPlace, appliedLift)
        else
          -- after a resize the chat keeps its left edge (a centred chat is no longer re-centred)
          placeX = lastPlace.x
        end
        M.relayout()
      end
      save()
    end
    if not self:isHovered() then cursorOff(self) end
    return true
  end
  grip.onHoverChange = function(self, hovered)
    if hovered then cursorOn(self) elseif not (drag and drag.grip == self) then cursorOff(self) end
  end
  grip.onDoubleClick = function()
    if kind == 'width' then wantedWidth = L.DEFAULT_WIDTH else placeX, lift = nil, 0 end
    M.relayout()
    save()
    return true
  end
  grip:raise()
  return grip
end

local function createGrips()
  local r, s = root(), splitter()
  if not r or not s or g_app.isMobile() then return end
  wrapSplitter(s)
  if not widthGrip then widthGrip = makeGrip('ChaosChatWidthGrip', 'width') end
  if not moveGrip then moveGrip = makeGrip('ChaosChatMoveGrip', 'move') end
  if not handle then handle = makeGrip('ChaosChatMoveHandle', 'move', true) end
  -- widgets other modules add to the root panel later must not cover the grips
  widthGrip:raise()
  moveGrip:raise()
  handle:raise()
end

local function onGameStart()
  -- after game_interface has laid out its panels and restored its own splitter margin
  addEvent(function()
    createGrips()
    applySaved()
  end)
end

local function onGameEnd()
  save()
  character = nil
  lastPlace = nil
  drag = nil
end

local function onGeometry()
  if g_game.isOnline() and not drag then M.relayout() end
end

local function watch(on)
  local r = root()
  if not r then return end
  for _, w in ipairs({ r, r:getChildById('gameLeftPanels'), r:getChildById('gameRightPanels') }) do
    if w then
      if on then connect(w, { onGeometryChange = onGeometry }) else disconnect(w, { onGeometryChange = onGeometry }) end
    end
  end
end

function M.init()
  g_ui.importStyle('chatpanel')
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  watch(true)
  if g_game.isOnline() then onGameStart() end
end

function M.terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  watch(false)
  if g_game.isOnline() then save() end
  for _, g in ipairs({ widthGrip, moveGrip, handle }) do
    if g then cursorOff(g) g:destroy() end
  end
  widthGrip, moveGrip, handle, drag = nil, nil, nil, nil
  -- hand the splitter's left margin, its rules and the bottom edge back to game_interface
  local s = splitter()
  if s then
    applyLift(s, 0)
    s:setMarginLeft(tonumber(s.chaosBaseMarginLeft) or 0)
  end
  unwrapSplitter(s)
end
