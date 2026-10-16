-- Pure rules of the map's default zoom (client/MANIFEST.md "Map zoom"; tested by chaosview_test.lua).
--
-- The game window draws `zoom` rows of tiles (UIMap zoom = visible height in tiles). The server sends a 17 x 13 tile
-- area unless the client asks for more (protocolgame.cpp updateAwareRange, at most 29 x 21), and game_interface keeps
-- the zoom inside what was sent: on a wide window that left 11 rows, so on a 2000 x 1340 window a tile was 122 px.
-- The client now asks for the largest area and starts at about 72 px per tile (15 rows there, 11 on a small window).
ChaosViewLogic = {}
local L = ChaosViewLogic

L.AWARE_WIDTH = 29   -- the server's limit (Map::maxClientViewportX * 2 + 1)
L.AWARE_HEIGHT = 21  -- (Map::maxClientViewportY * 2 + 1)
L.MIN_ROWS = 11      -- the classic view's height
L.MAX_DEFAULT_ROWS = 15
L.TILE_PIXELS = 72   -- the tile size a new player starts at

local function odd(n)
  n = math.floor(n)
  if n % 2 == 0 then n = n - 1 end
  return n
end

-- the furthest zoom out the area sent by the server allows (game_interface getExtendedMaxZoomOut):
-- awareWidth / awareHeight as g_map.getAwareRange() gives them, aspect = window width / height
function L.maxZoomOut(awareWidth, awareHeight, aspect)
  local zoom = odd(tonumber(awareHeight) or 13)
  aspect = tonumber(aspect) or 1
  while zoom > 3 do
    local width = math.floor(zoom * aspect)
    if width % 2 == 0 then width = width + 1 end
    if width <= (tonumber(awareWidth) or 0) then return zoom end
    zoom = zoom - 2
  end
  return 3
end

-- the zoom a player without a saved one starts at: about TILE_PIXELS per tile, from the classic 11 rows up to 15
function L.defaultZoom(windowHeight, maxZoom)
  local rows = odd((tonumber(windowHeight) or 0) / L.TILE_PIXELS)
  rows = math.max(L.MIN_ROWS, math.min(L.MAX_DEFAULT_ROWS, rows))
  if maxZoom and maxZoom >= 3 then rows = math.min(rows, maxZoom) end
  return rows
end

-- the zoom to use: the character's saved one (kept inside what the server sends), else the default
function L.zoomFor(saved, windowHeight, maxZoom)
  saved = tonumber(saved)
  if saved and saved >= 3 then
    if maxZoom and maxZoom >= 3 then return math.min(saved, maxZoom) end
    return saved
  end
  return L.defaultZoom(windowHeight, maxZoom)
end

return ChaosViewLogic
