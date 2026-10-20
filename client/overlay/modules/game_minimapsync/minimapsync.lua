-- game_minimapsync: the minimap (game_minimap, the "Map View" window) shows the explored map around the character
-- after a death and the respawn in the temple, and after any far teleport (client/MANIFEST.md "Minimap after a
-- death"). game_minimap moves its camera only from LocalPlayer.onPositionChange and skips it while its widget is
-- being dragged or the full map view (Ctrl+Shift+M) is open; nothing sets the view up again when a session starts.
-- This module does, from outside the base module: when the map of a new session is known (several passes, after the
-- side panels and the layout modules placed the windows) and on every teleport it puts the camera and the cross on
-- the character's tile, closes a full map view left over from the last session, puts the minimap widget back in its
-- window and reopens the window when it was open at the death or the end of the session. Nothing is cleaned: the
-- explored map (g_minimap, minimap.otmm) stays as it is. Rules in minimapsync_logic.lua.
ChaosMinimapSync = ChaosMinimapSync or {}
local M = ChaosMinimapSync
local L = MinimapSyncLogic

local events = {}
local wantOpen = nil   -- the window was open at the death / the end of the last session
local handlers = {}

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

local function minimapModule()
  local m = modules and modules.game_minimap
  if type(m) ~= 'table' then return nil end
  local widget, window = rawget(m, 'minimapWidget'), rawget(m, 'minimapWindow')
  if not alive(widget) or not alive(window) then return nil end
  return m, widget, window
end

local function playerPos()
  local player = g_game.getLocalPlayer()
  return player and player:getPosition() or nil
end

-- the state MinimapSyncLogic.plan reads
local function readState(reason, m, widget, window)
  return {
    reason = reason,
    fullmap = rawget(m, 'fullmapView') == true,
    inWindow = widget:getParent() == window,
    windowOpen = window:isVisible(),
    wantOpen = wantOpen,
    pos = playerPos(),
    camera = widget:getCameraPosition(),
  }
end

local function call(m, name, ...)
  local fn = rawget(m, name)
  if type(fn) == 'function' then
    local ok, err = pcall(fn, ...)
    if not ok then g_logger.warning('[minimapsync] ' .. name .. ': ' .. tostring(err)) end
  end
end

-- one pass: reason 'start' (a new session), 'teleport' or 'end'
function M.sync(reason)
  local m, widget, window = minimapModule()
  if not m then return nil end
  local plan = L.plan(readState(reason, m, widget, window))
  if plan.exitFullMap then
    call(m, 'toggleFullMap')
  end
  if plan.reparent and alive(widget) and alive(window) then
    widget:setParent(window)
    widget:fill('parent')
  end
  if plan.open then
    call(m, 'open')
  end
  if plan.consumeWant then
    wantOpen = nil
  end
  if plan.recentre then
    local pos = playerPos()
    widget:setCameraPosition(pos)
    widget:setCrossPosition(playerPos())
    call(m, 'updateFloorImage', pos.z)
  end
  return plan
end

local function cancelPasses()
  for _, e in ipairs(events) do removeEvent(e) end
  events = {}
end

local function schedulePasses()
  cancelPasses()
  for _, delay in ipairs(L.PASSES) do
    events[#events + 1] = scheduleEvent(function()
      if g_game.isOnline() then M.sync('start') end
    end, delay)
  end
end

local function rememberOpen()
  local m, _, window = minimapModule()
  if m then
    wantOpen = L.openAtEnd(window:isVisible(), rawget(m, 'fullmapView') == true) or nil
  end
end

local function onGameStart()
  cancelPasses()
  -- a session that starts with the map already known (a module reload while online)
  if L.validPos(playerPos()) then schedulePasses() end
end

local function onMapKnown()
  schedulePasses()
end

local function onTeleport()
  -- after game_minimap's own handlers of the same packet
  addEvent(function()
    if g_game.isOnline() then M.sync('teleport') end
  end)
end

local function onDeath()
  rememberOpen()
end

local function onGameEnd()
  cancelPasses()
  -- a death already remembered the window; a plain logout remembers it now
  if wantOpen == nil then rememberOpen() end
  M.sync('end')
end

local function safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then g_logger.warning('[minimapsync] ' .. name .. ': ' .. tostring(err)) end
  end
end

function M.init()
  -- a handler that returns nothing: the engine stops a handler table at the first one that returns true
  handlers.game = { onGameStart = safe('start', onGameStart), onMapKnown = safe('mapKnown', onMapKnown),
    onTeleport = safe('teleport', onTeleport), onDeath = safe('death', onDeath), onGameEnd = safe('end', onGameEnd) }
  connect(g_game, handlers.game)
  if g_game.isOnline() then onGameStart() end
end

function M.terminate()
  if handlers.game then disconnect(g_game, handlers.game) end
  handlers = {}
  cancelPasses()
end

-- for checks
function M.getState()
  local m, widget, window = minimapModule()
  if not m then return { attached = false } end
  local s = readState('check', m, widget, window)
  s.attached = true
  s.passes = #events
  return s
end
