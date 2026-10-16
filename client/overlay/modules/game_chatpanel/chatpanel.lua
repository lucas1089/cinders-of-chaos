-- game_chatpanel: size and place of the bottom area (action bars + console) (client/MANIFEST.md "Chat panel").
-- * The group life orb + chat + mana orb is centred in the game window by default and re-centred when the window
--   changes. The orbs (game_shaderfx) are anchored to the chat's edges and follow it.
-- * Move: the grip on the chat's left edge (ChaosChatMoveGrip) drags the chat sideways; double-click puts it back in
--   the centre (a drag that ends near the centre snaps back too).
-- * Width: the grip on the right edge (ChaosChatWidthGrip); double-click gives the default width back.
-- * Height: the base splitter above the action bars (bottomSplitter; base patch 0065 makes its drag reliable).
-- Width, height and place are kept per character in the client settings (node chaos_chatpanel) and clamped to the
-- window (chatpanel_logic.lua, tested by chatpanel_test.lua). The splitter's left margin belongs to this module while
-- it runs: base patch 0065 hands game_interface's own value (the reserved left column) to relayout.
ChaosChatPanel = ChaosChatPanel or {}
local M = ChaosChatPanel
local L = ChaosChatLogic

local SETTINGS_NODE = 'chaos_chatpanel'
local BASE_RIGHT_MARGIN = 1 -- bottomSplitter's margin-right in game_interface's otui

local widthGrip, moveGrip = nil, nil
local wantedWidth = L.DEFAULT_WIDTH
local offset = nil -- nil: centred
local character = nil
local drag = nil -- {kind = 'width' | 'move', startX, startOffset}
local lastPlace = nil
local watched = {}

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

local function minimumHeight(s)
  if s.canUpdateMargin then
    local ok, v = pcall(s.canUpdateMargin, s, 0)
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

-- x of the splitter's anchor lines and the region the group may use
local function region(s)
  local r = root()
  local lp, rp = child('gameLeftPanels'), child('gameRightPanels')
  local anchorLeft = lp and (lp:getX() + lp:getWidth()) or r:getX()
  local anchorRight = rp and rp:getX() or (r:getX() + r:getWidth())
  local left = anchorLeft + (tonumber(s.chaosBaseMarginLeft) or 0)
  local right = anchorRight - BASE_RIGHT_MARGIN
  if orbSize() > 0 then
    -- an orb is taller than a small chat: keep it off the side action bars above the bottom area
    local la, ra = child('gameLeftActionPanel'), child('gameRightActionPanel')
    if la then left = math.max(left, la:getX() + la:getWidth()) end
    if ra then right = math.min(right, ra:getX()) end
  end
  return anchorLeft, anchorRight, left, right
end

-- place the group (returns true when it did: base patch 0065 then leaves the splitter's left margin alone)
function M.relayout()
  local s, r = splitter(), root()
  if not s or not r or not g_game.isOnline() or g_app.isMobile() or not s:isVisible() then return false end
  local anchorLeft, anchorRight, left, right = region(s)
  local orb = orbSize()
  local place = L.layout({ regionLeft = left, regionRight = right, windowLeft = r:getX(), windowWidth = r:getWidth(),
    width = wantedWidth, offset = offset, orbSize = orb })
  local ml, mr = L.splitterMargins(place, anchorLeft, anchorRight)
  if s:getMarginLeft() ~= ml then s:setMarginLeft(ml) end
  if s:getMarginRight() ~= mr then s:setMarginRight(mr) end
  place.orbSize = place.orbs and orb or 0
  lastPlace = place
  local fx = modules.game_shaderfx
  if orb > 0 and fx and type(fx.setOrbsFit) == 'function' then pcall(fx.setOrbsFit, place.orbs) end
  return true
end

local function save()
  local s = splitter()
  if not s or not character then return end
  local saved = g_settings.getNode(SETTINGS_NODE) or {}
  saved[character] = { width = wantedWidth, height = s:getMarginBottom(), offset = offset }
  g_settings.setNode(SETTINGS_NODE, saved)
end

local function applySaved()
  local s = splitter()
  local player = g_game.getLocalPlayer()
  if not s or not player or g_app.isMobile() then return end
  character = player:getName()
  local size = L.sizeFor(g_settings.getNode(SETTINGS_NODE), character)
  wantedWidth = size.width
  offset = size.offset
  M.relayout()
  local r = root()
  local height = L.clampHeight(size.height, minimumHeight(s), r and r:getHeight() or 0)
  if s:getMarginBottom() ~= height then s:setMarginBottom(height) end
end

-- ---------------------------------------------------------------- the grips
-- The cursor: pushed once on hover, popped once when neither hovered nor dragged (a drag that ends off the grip used
-- to leave it pushed, and a pushed cursor made the base splitter skip its own setup)
local function cursorOn(grip)
  if grip.cursorPushed then return end
  grip.cursorPushed = g_mouse.applyNativeCursor('horizontal') and 'native' or 'pushed'
  if grip.cursorPushed == 'pushed' then g_mouse.pushCursor('horizontal') end
end

local function cursorOff(grip)
  if not grip.cursorPushed then return end
  if grip.cursorPushed == 'native' then g_mouse.restoreNativeCursor() else g_mouse.popCursor('horizontal') end
  grip.cursorPushed = nil
end

local function onGripMove(self, mousePos)
  if not drag or drag.grip ~= self then return false end
  local r = root()
  if not r then return true end
  if drag.kind == 'width' then
    wantedWidth = L.widthForGrip(mousePos.x, r:getX(), r:getWidth(), offset, lastPlace and lastPlace.orbSize or 0)
    wantedWidth = math.max(L.MIN_WIDTH, wantedWidth)
  else
    offset = L.dragOffset(drag.startOffset, drag.startX, mousePos.x)
  end
  M.relayout()
  if drag.kind == 'width' and lastPlace then wantedWidth = lastPlace.chatWidth end
  return true
end

local function makeGrip(style, kind)
  local grip = g_ui.createWidget(style, root())
  grip:addAnchor(AnchorTop, 'bottomSplitter', AnchorBottom)
  grip:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  if kind == 'width' then
    grip:addAnchor(AnchorLeft, 'bottomSplitter', AnchorRight)
    grip:setMarginLeft(L.WIDTH_GRIP_GAP)
  else
    grip:addAnchor(AnchorRight, 'bottomSplitter', AnchorLeft)
    grip:setMarginRight(L.MOVE_GRIP_GAP)
  end
  grip.onMousePress = function(self, mousePos, button)
    if button ~= MouseLeftButton then return false end
    local place = lastPlace
    drag = { grip = self, kind = kind, startX = mousePos.x, startOffset = place and place.offset or offset }
    cursorOn(self)
    return true
  end
  grip.onMouseMove = onGripMove
  grip.onMouseRelease = function(self)
    if drag and drag.grip == self then
      drag = nil
      if lastPlace then offset = lastPlace.offset end -- the clamped (or snapped) place
      save()
    end
    if not self:isHovered() then cursorOff(self) end
    return true
  end
  grip.onHoverChange = function(self, hovered)
    if hovered then cursorOn(self) elseif not (drag and drag.grip == self) then cursorOff(self) end
  end
  grip.onDoubleClick = function()
    if kind == 'width' then wantedWidth = L.DEFAULT_WIDTH else offset = nil end
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
  if not widthGrip then widthGrip = makeGrip('ChaosChatWidthGrip', 'width') end
  if not moveGrip then moveGrip = makeGrip('ChaosChatMoveGrip', 'move') end
  -- widgets other modules add to the root panel later must not cover the grips
  widthGrip:raise()
  moveGrip:raise()
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
  for _, g in ipairs({ widthGrip, moveGrip }) do
    if g then cursorOff(g) g:destroy() end
  end
  widthGrip, moveGrip, drag = nil, nil, nil
  -- hand the splitter's left margin back to game_interface
  local s = splitter()
  if s then s:setMarginLeft(tonumber(s.chaosBaseMarginLeft) or 0) end
end
