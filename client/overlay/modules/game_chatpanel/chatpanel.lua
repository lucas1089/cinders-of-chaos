-- game_chatpanel: the size of the bottom area (action bars + console) (client/MANIFEST.md "Chat panel").
-- * Width: a handle on the right edge (ChaosChatWidthGrip). The bottom splitter's right margin leaves the chosen
--   width, so the action bar shows fewer empty slots (it shows width / 36 of them) and the map stays visible.
-- * Height: the base splitter above the action bars; its minimum is lower (base patch 0056) and a new character
--   starts close to it. Both sizes are kept per character in the client settings (node chaos_chatpanel) and
--   clamped to the window (chatpanel_logic.lua, tested by chatpanel_test.lua).
ChaosChatPanel = ChaosChatPanel or {}
local M = ChaosChatPanel
local L = ChaosChatLogic

local SETTINGS_NODE = 'chaos_chatpanel'
local BASE_RIGHT_MARGIN = 1 -- bottomSplitter's margin-right in game_interface's otui

local grip = nil
local wantedWidth = L.DEFAULT_WIDTH
local character = nil
local dragging = false

local function root()
  local gi = modules.game_interface
  return gi and gi.getRootPanel and gi.getRootPanel() or nil
end

local function splitter()
  local r = root()
  return r and r:getChildById('bottomSplitter') or nil
end

local function available(s)
  return s:getWidth() + s:getMarginRight() - BASE_RIGHT_MARGIN
end

local function minimumHeight(s)
  if s.canUpdateMargin then
    local ok, v = pcall(s.canUpdateMargin, s, 0)
    if ok and tonumber(v) then return tonumber(v) end
  end
  return 150
end

local function applyWidth()
  local s = splitter()
  if not s or g_app.isMobile() then return end
  local margin = L.marginRightFor(wantedWidth, available(s), BASE_RIGHT_MARGIN)
  if s:getMarginRight() ~= margin then s:setMarginRight(margin) end
end

local function save()
  local s = splitter()
  if not s or not character then return end
  local saved = g_settings.getNode(SETTINGS_NODE) or {}
  saved[character] = { width = wantedWidth, height = s:getMarginBottom() }
  g_settings.setNode(SETTINGS_NODE, saved)
end

local function applySaved()
  local s = splitter()
  local player = g_game.getLocalPlayer()
  if not s or not player or g_app.isMobile() then return end
  character = player:getName()
  local size = L.sizeFor(g_settings.getNode(SETTINGS_NODE), character)
  wantedWidth = size.width
  applyWidth()
  local r = root()
  local height = L.clampHeight(size.height, minimumHeight(s), r and r:getHeight() or 0)
  if s:getMarginBottom() ~= height then s:setMarginBottom(height) end
end

-- ---------------------------------------------------------------- the width handle
local function onGripMove(self, mousePos)
  if not dragging then return false end
  local s = splitter()
  if not s then return true end
  wantedWidth = L.clampWidth(mousePos.x - s:getX(), available(s))
  applyWidth()
  return true
end

local function createGrip()
  local r, s = root(), splitter()
  if grip or not r or not s or g_app.isMobile() then return end
  grip = g_ui.createWidget('ChaosChatWidthGrip', r)
  grip:addAnchor(AnchorTop, 'bottomSplitter', AnchorBottom)
  grip:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  grip:addAnchor(AnchorLeft, 'bottomSplitter', AnchorRight)
  grip:setMarginLeft(13) -- past the action bar's lock column (12 px + 1)
  grip.onMousePress = function(self, mousePos, button)
    if button ~= MouseLeftButton then return false end
    dragging = true
    return true
  end
  grip.onMouseMove = onGripMove
  grip.onMouseRelease = function()
    if dragging then
      dragging = false
      save()
    end
    return true
  end
  grip.onHoverChange = function(self, hovered)
    if hovered then g_mouse.pushCursor('horizontal') elseif not dragging then g_mouse.popCursor('horizontal') end
  end
end

local function onGameStart()
  -- after game_interface has laid out its panels and restored its own splitter margin
  addEvent(function()
    createGrip()
    applySaved()
  end)
end

local function onGameEnd()
  save()
  character = nil
end

local function onRootGeometry()
  if g_game.isOnline() then applyWidth() end
end

function M.init()
  g_ui.importStyle('chatpanel')
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  local r = root()
  if r then connect(r, { onGeometryChange = onRootGeometry }) end
  if g_game.isOnline() then onGameStart() end
end

function M.terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  local r = root()
  if r then disconnect(r, { onGeometryChange = onRootGeometry }) end
  if g_game.isOnline() then save() end
  if grip then grip:destroy() grip = nil end
end
