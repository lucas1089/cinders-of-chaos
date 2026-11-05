-- Cinema mode (O411; client/MANIFEST.md "Streamer and cinema modes"): Ctrl+Shift+H in the game hides every panel and
-- window (side panels, chat, top menu, action bars, HUD on the map, toasts, floating windows) and lets the map fill the
-- window, for promo videos; Ctrl+Shift+H again (or the end of the game) brings back exactly the widgets it hid.
--   * the widgets hidden: every visible sibling of the map panel and of each of its parents up to the root, and the map
--     panel's own children (the HUD drawn on it); the list is kept, and a widget that shows up while the mode is on
--     (a toast, a window a module re-shows) is hidden and added to it. A widget that was already hidden is not touched.
--   * the map: in the classic view it is anchored between the side panels and the chat, so it is set to fill its parent
--     for the mode and the game interface lays it out again afterwards (refreshViewMode, as at login); in the extended
--     view it already fills the window and is left alone.
--   * Options > Misc. "Cinema mode (Ctrl+Shift+H): also hide the names and bars of other players": Creature.setInfoHide
--     bit 2 (base patch 0186); a client without the patch hides all names and bars instead (UIMap.setDrawNames /
--     setDrawHealthBars, set back after).
-- Global: ChaosCinema.toggle(), .isOn().

ChaosCinema = ChaosCinema or {}
local M = ChaosCinema
local C = StreamerCore

local TICK_MS = 250

local on = false
local hidden = {}
local mapState = nil   -- { refilled = bool, names, bars }
local tickEvent

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

local function iface()
  return modules and modules.game_interface
end

local function mapPanel()
  local gi = iface()
  return gi and gi.getMapPanel and gi.getMapPanel() or nil
end

local function isClassic()
  local ok, v = pcall(g_settings.getBoolean, 'classicView')
  local extended = g_gameConfig and g_gameConfig.isExtendedViewUI and g_gameConfig.isExtendedViewUI()
  return ok and v == true and not extended
end

-- the chain from the map up to the root and every sibling on the way, in StreamerCore.cinemaPick's shape
local function snapshot(map)
  local chain = {}
  local w = map
  local root = g_ui.getRootWidget()
  while alive(w) and w ~= root do
    local parent = w:getParent()
    if not parent then break end
    local siblings = {}
    for _, s in ipairs(parent:getChildren()) do
      siblings[#siblings + 1] = { widget = s, visible = s:isVisible() }
    end
    chain[#chain + 1] = { widget = w, siblings = siblings }
    w = parent
  end
  local kids = {}
  for _, c in ipairs(map:getChildren()) do kids[#kids + 1] = { widget = c, visible = c:isVisible() } end
  return C.cinemaPick(chain, kids)
end

local function useInfoMask()
  return Creature and Creature.setInfoHide ~= nil
end

local function applyOthers(map, start)
  local opts = ChaosStreamer and ChaosStreamer.opts and ChaosStreamer.opts() or C.normalize(nil)
  if useInfoMask() then
    if ChaosStreamer and ChaosStreamer.setCinema then ChaosStreamer.setCinema(start) end
    return
  end
  -- no base patch 0186: one switch for every creature
  if not (mapState and map.setDrawNames and map.isDrawingNames and map.isDrawingHealthBars) then return end
  local want = start and opts.cinemaHideOthers
  if want and mapState.names == nil then
    mapState.names = map:isDrawingNames()
    mapState.bars = map:isDrawingHealthBars()
    map:setDrawNames(false)
    map:setDrawHealthBars(false)
  elseif not want and mapState.names ~= nil then
    map:setDrawNames(mapState.names)
    map:setDrawHealthBars(mapState.bars)
    mapState.names, mapState.bars = nil, nil
  end
end

local function tick()
  tickEvent = nil
  if not on then return end
  local map = mapPanel()
  if alive(map) then
    local found = snapshot(map)
    C.addNew(hidden, found)
    for _, w in ipairs(found) do if alive(w) then w:hide() end end
  end
  tickEvent = scheduleEvent(tick, TICK_MS)
end

function M.isOn() return on end

function M.start()
  if on or not g_game.isOnline() then return false end
  local map = mapPanel()
  if not alive(map) then return false end
  on = true
  mapState = { refilled = false }
  hidden = snapshot(map)
  for _, w in ipairs(hidden) do w:hide() end
  if isClassic() then
    map:breakAnchors()
    map:fill('parent')
    map:setMarginLeft(0)
    map:setMarginRight(0)
    map:setMarginTop(0)
    map:setMarginBottom(0)
    mapState.refilled = true
  end
  applyOthers(map, true)
  tickEvent = scheduleEvent(tick, TICK_MS)
  return true
end

function M.stop()
  if not on then return false end
  on = false
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  for _, w in ipairs(hidden) do
    if alive(w) then w:show() end
  end
  hidden = {}
  local map = mapPanel()
  if alive(map) then
    applyOthers(map, false)
    local gi = iface()
    if mapState and mapState.refilled and gi and gi.refreshViewMode then pcall(gi.refreshViewMode) end
  elseif ChaosStreamer and ChaosStreamer.setCinema then
    ChaosStreamer.setCinema(false)
  end
  mapState = nil
  return true
end

function M.toggle()
  if on then M.stop() else M.start() end
end

-- the sub-option changed while the mode is on
local function onStreamerOptions()
  if not on then return end
  local map = mapPanel()
  if alive(map) then applyOthers(map, true) end
end

local function onGameEnd()
  M.stop()
end

function M.init()
  g_keyboard.bindKeyDown(C.HOTKEY_CINEMA, M.toggle)
  connect(g_game, { onGameEnd = onGameEnd })
  if ChaosStreamer and ChaosStreamer.addListener then ChaosStreamer.addListener(onStreamerOptions) end
end

function M.terminate()
  M.stop()
  disconnect(g_game, { onGameEnd = onGameEnd })
  pcall(g_keyboard.unbindKeyDown, C.HOTKEY_CINEMA)
end
