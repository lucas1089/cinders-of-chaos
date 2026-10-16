-- game_chaosview: the map's zoom (client/MANIFEST.md "Map zoom"). At game start the client asks the server for its
-- largest map area (29 x 21 tiles) and sets the zoom: the character's saved zoom (Ctrl+= / Ctrl+-, kept per character
-- in the client settings, node chaos_view) or the default of chaosview_logic.lua. Without the larger area the zoom
-- was held at 11 rows, so a big window showed huge tiles.
ChaosView = ChaosView or {}
local M = ChaosView
local L = ChaosViewLogic

local SETTINGS_NODE = 'chaos_view'
local POLL_MS = 1000

local character = nil
local lastZoom = nil
local pollEvent = nil

local function mapPanel()
  local gi = modules.game_interface
  return gi and gi.getMapPanel and gi.getMapPanel() or nil
end

local function rootPanel()
  local gi = modules.game_interface
  return gi and gi.getRootPanel and gi.getRootPanel() or nil
end

local function savedZoom()
  local node = g_settings.getNode(SETTINGS_NODE)
  return type(node) == 'table' and character and node[character] or nil
end

local function saveZoom(zoom)
  if not character then return end
  local node = g_settings.getNode(SETTINGS_NODE) or {}
  node[character] = zoom
  g_settings.setNode(SETTINGS_NODE, node)
end

local function applyZoom()
  local map, root = mapPanel(), rootPanel()
  if not map or not root or root:getHeight() <= 0 or not g_game.isOnline() then return end
  local range = g_map.getAwareRange()
  local maxZoom = L.maxZoomOut(range.width, range.height, root:getWidth() / root:getHeight())
  map:setMaxZoomOut(maxZoom)
  local zoom = L.zoomFor(savedZoom(), root:getHeight(), maxZoom)
  map:setZoom(zoom)
  lastZoom = map:getZoom()
end

-- a zoom the player picked (Ctrl+= / Ctrl+-) is kept for this character
local function poll()
  pollEvent = nil
  local map = mapPanel()
  if map and g_game.isOnline() then
    local zoom = map:getZoom()
    if lastZoom and zoom ~= lastZoom then
      saveZoom(zoom)
    end
    lastZoom = zoom
  end
  pollEvent = scheduleEvent(poll, POLL_MS)
end

local function onGameStart()
  local player = g_game.getLocalPlayer()
  character = player and player:getName() or nil
  lastZoom = nil
  addEvent(function()
    if g_game.isOnline() and g_game.changeMapAwareRange then
      g_game.changeMapAwareRange(L.AWARE_WIDTH, L.AWARE_HEIGHT)
    end
    applyZoom() -- again when the server answers with the new area (onMapChangeAwareRange)
  end)
  if not pollEvent then pollEvent = scheduleEvent(poll, POLL_MS) end
end

local function onGameEnd()
  character = nil
  lastZoom = nil
  if pollEvent then removeEvent(pollEvent) pollEvent = nil end
end

local function onAwareRange()
  -- after game_interface's own updateSize for the new area
  addEvent(applyZoom)
end

local function onRootGeometry()
  -- game_interface may clamp the zoom while the window changes size: that is not the player's choice
  lastZoom = nil
  if g_game.isOnline() then addEvent(applyZoom) end
end

function M.init()
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd, onMapChangeAwareRange = onAwareRange })
  local root = rootPanel()
  if root then connect(root, { onGeometryChange = onRootGeometry }) end
  if g_game.isOnline() then onGameStart() end
end

function M.terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd, onMapChangeAwareRange = onAwareRange })
  local root = rootPanel()
  if root then disconnect(root, { onGeometryChange = onRootGeometry }) end
  onGameEnd()
end
