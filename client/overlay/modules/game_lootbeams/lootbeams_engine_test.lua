-- luajit lootbeams_engine_test.lua && lua5.3 lootbeams_engine_test.lua (from any folder)
-- The engine part of the loot beams (lootbeams.lua, O569) on a fake engine, with the real module code: a set piece on the ground
-- gets a beam widget over its tile, and the widget lands ON the item at several zooms and both sprite sizes. The fake engine draws
-- a tile widget the way base patch 0041 drawWidgetOverTile does (read in the engine source, seen in a client 2026-11-25, V8):
-- its centre at dest + g_sprites.spriteSize() + margins, with dest the tile's TOP LEFT on the screen. spriteSize is 32, or 64
-- with HD Sprite Upscaling: O569 (margins tw / 2 - 32) was off half a tile right and down with HD on (owner screenshot,
-- 2026-11-22), O716 (margins -32) half a tile left and up with HD off (V8). LB_SPR=32 forces the old fixed size: it fails.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- the fake engine
local TILE = 64 -- screen px of a tile (set per run)
local VIS = { width = 15, height = 11 }
local PLAYER = { x = 100, y = 100, z = 7 }
local panelRect = { x = 0, y = 0, width = 15 * TILE, height = 11 * TILE }
local SPR = 32 -- the sprite manager's size (set per run)
g_sprites = { spriteSize = function() return SPR end }

local function newWidget()
  local w = { margins = { l = 0, t = 0 }, size = { w = 0, h = 0 }, destroyed = false }
  function w:setImageSource() end
  function w:setImageSmooth() end
  function w:setPhantom() end
  function w:setOpacity() end
  function w:setImageClip() end
  function w:resize(a, b) self.size = { w = a, h = b } end
  function w:setMarginLeft(v) self.margins.l = v end
  function w:setMarginTop(v) self.margins.t = v end
  function w:isDestroyed() return self.destroyed end
  function w:destroy() self.destroyed = true end
  return w
end

local tiles = {}
local function tileAt(pos)
  local k = pos.x .. ',' .. pos.y .. ',' .. pos.z
  if not tiles[k] then
    local t = { pos = pos, widgets = {} }
    function t:addOverlayWidget(w) self.widgets[#self.widgets + 1] = w end
    function t:hasOverlayWidget(w)
      for _, x in ipairs(self.widgets) do if x == w then return true end end
      return false
    end
    function t:removeOverlayWidget(w)
      for i, x in ipairs(self.widgets) do if x == w then table.remove(self.widgets, i) return true end end
      return false
    end
    tiles[k] = t
  end
  return tiles[k]
end
Tile = { addOverlayWidget = true, hasOverlayWidget = true, removeOverlayWidget = true }
g_map = { getTile = function(pos) return tileAt(pos) end }
g_resources = { fileExists = function() return true end }
g_clock = { millis = function() return 5000 end }
g_ui = { createWidget = function(kind)
  if kind == 'UIWidget' then return newWidget() end
  error('no such widget ' .. tostring(kind))
end, importStyle = function() end }
local player = { getPosition = function() return PLAYER end }
g_game = { isOnline = function() return true end, getLocalPlayer = function() return player end }
g_logger = { warning = function() end, info = function() end }
local nodes = {}
g_settings = { getNode = function(k) return nodes[k] end, setNode = function(k, v) nodes[k] = v end }
local cycles = {}
function cycleEvent(fn, ms) cycles[#cycles + 1] = { fn = fn, ms = ms } return fn end
function removeEvent() end
function connect() end
function disconnect() end
rootWidget = {}
local panel = {
  getVisibleDimension = function() return VIS end,
  getRect = function() return panelRect end,
  isKeepAspectRatioEnabled = function() return false end,
}
local groundRows = {}
modules = {
  game_interface = { getMapPanel = function() return panel end },
  game_groundlabels = {
    getGroundItems = function() return groundRows end,
    getRowsVersion = function() return 1 end,
  },
}
dofile(dir .. '../game_lootfilter/lootfilterlogic.lua')
dofile(dir .. 'lootbeamslogic.lua')
local LB = LootBeamsLogic
if os.getenv('LB_SPR') then
  local box = LB.box
  LB.box = function(tw, th, key) return box(tw, th, key, tonumber(os.getenv('LB_SPR'))) end
end

-- the engine's draw of one overlay widget (base patch 0041 drawWidgetOverTile, dest = the tile's top left in screen px; the
-- player's tile is the middle one of the 15 x 11)
local function drawnCentre(pos, w)
  local destX = panelRect.width / 2 - TILE / 2 + (pos.x - PLAYER.x) * TILE
  local destY = panelRect.height / 2 - TILE / 2 + (pos.y - PLAYER.y) * TILE
  return destX + SPR + w.margins.l, destY + SPR + w.margins.t
end
local function tileCentre(pos)
  return panelRect.width / 2 + (pos.x - PLAYER.x) * TILE, panelRect.height / 2 + (pos.y - PLAYER.y) * TILE
end

local function tickOnce()
  for _, c in ipairs(cycles) do
    if c.ms == 300 then c.fn() end
  end
end

-- ---------------------------------------------------------------- a Common set shield on the ground, at several zooms
local itemPos = { x = 102, y = 99, z = 7 }
groundRows = { { pos = itemPos, rows = { { id = 7, nm = 'mirrored cinderwrought aegis', r = 1, st = 1, g = 'equipment', c = 1 } } } }
for run = 0, 9 do
  local tile = ({ 32, 48, 64, 98, 128 })[run % 5 + 1]
  SPR = run < 5 and 32 or 64
  TILE = tile
  panelRect = { x = 0, y = 0, width = 15 * TILE, height = 11 * TILE }
  tiles = {}
  cycles = {}
  dofile(dir .. 'lootbeams.lua') -- a fresh module (its locals) at each zoom
  init()
  tickOnce()
  local stats = getStats()
  eq(stats.widgets, 1, 'a set piece beams: one widget at ' .. tile .. ' px')
  local t = tileAt(itemPos)
  eq(#t.widgets, 1, 'the widget is on the item tile at ' .. tile .. ' px')
  local w = t.widgets[1]
  if w then
    local cx, cy = drawnCentre(itemPos, w)
    local tx, ty = tileCentre(itemPos)
    local h = w.size.h
    local footY = cy - h / 2 + LB.ART.footY * (h / LB.ART.h)
    eq(math.abs(cx - tx) <= 1.5, true, 'the beam column is over the item centre at ' .. tile .. ' px, sprite ' .. SPR .. ' (' .. cx .. ' vs ' .. tx .. ')')
    local wantFoot = ty + LB.ART.footDrop * tile / LB.ART.tile
    eq(math.abs(footY - wantFoot) <= 1.5, true, 'the ring is on the item at ' .. tile .. ' px, sprite ' .. SPR .. ' (' .. footY .. ' vs ' .. wantFoot .. ')')
    eq(math.abs(w.size.w - 2 * tile) <= 1, true, 'the picture is two tiles wide at ' .. tile .. ' px')
  end
end
terminate()

print(string.format('lootbeams_engine_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
