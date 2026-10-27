-- game_minimapsync: the minimap window of game_minimap ("Map View") is back, in a shown side panel and centred on
-- the character, after a death and the respawn in the temple (client/MANIFEST.md "Minimap after a death").
-- A death here is a fast relog (game_playerdeath Ok -> CharacterList.doLogin -> LoginEvent:tryLogin: logout and
-- login again at once). At every login game_interface.onPlayerLoad closes every side panel window and reopens the
-- saved ones one by one in an addEvent; until base patch 0096 one failing window ended that event and left every
-- window after it closed, the minimap (the last window of the rightmost panel) among them, until the next login.
-- This module remembers the window at the death and at the end of a session and, when the map of the new session is
-- known (passes after the layout restores) and after a teleport: closes a full map view left over, puts the minimap
-- widget back in its window, puts the window back in a shown side panel and opens it when it was open
-- (game_minimap.move, the same call the layout restore uses), and puts the camera and the cross on the character.
-- The explored map is never cleaned or reloaded. Rules in minimapsync_logic.lua.
ChaosMinimapSync = ChaosMinimapSync or {}
local M = ChaosMinimapSync
local L = MinimapSyncLogic

local events = {}
local want = nil       -- MinimapSyncLogic.remember of the window at the death / the end of the last session
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

local function call(m, name, ...)
  local fn = rawget(m, name)
  if type(fn) ~= 'function' then return nil end
  local ok, res = pcall(fn, ...)
  if not ok then g_logger.warning('[minimapsync] ' .. name .. ': ' .. tostring(res)) return nil end
  return res
end

-- the side panels a window can live in: { { id, widget, usable } }
local function sidePanels()
  local out = {}
  local gi = modules.game_interface
  local root = gi and gi.getRootPanel and gi.getRootPanel() or nil
  if not alive(root) then return out end
  for _, holderId in ipairs({ 'gameRightPanels', 'gameLeftPanels' }) do
    local holder = root:getChildById(holderId)
    for _, p in ipairs(holder and holder:getChildren() or {}) do
      if p:getClassName() == 'UIMiniWindowContainer' and not p.minimapExpansionReservation then
        out[#out + 1] = { id = p:getId(), widget = p, usable = alive(p) and p:isVisible() }
      end
    end
  end
  for _, id in ipairs({ 'horizontalRightPanel', 'horizontalLeftPanel' }) do
    local p = root:getChildById(id)
    if alive(p) then
      out[#out + 1] = { id = id, widget = p, usable = p:isVisible() and p:getWidth() > 0 }
    end
  end
  return out
end

local function panelOf(window)
  local parent = window:getParent()
  for _, p in ipairs(sidePanels()) do
    if p.widget == parent then return p end
  end
  return nil
end

local function readState(reason, m, widget, window)
  local p = panelOf(window)
  return {
    reason = reason,
    fullmap = rawget(m, 'fullmapView') == true,
    inWindow = widget:getParent() == window,
    windowShown = window:isExplicitlyVisible(),
    inPanel = p ~= nil and p.usable == true,
    want = want,
    pos = playerPos(),
    camera = widget:getCameraPosition(),
  }
end

local function restoreWindow(m, window)
  local panels = sidePanels()
  local gi = modules.game_interface
  local fallback = gi and gi.getRightPanel and gi.getRightPanel() or nil
  local id = L.pickPanel(want, panels, alive(fallback) and fallback:getId() or nil)
  local target = nil
  for _, p in ipairs(panels) do
    if p.id == id then target = p.widget end
  end
  target = target or fallback
  if not alive(target) then return end
  g_logger.info(string.format('[minimapsync] minimap window shown=%s parent=%s after the login: back in %s', -- i18n-ok: not UI text
    tostring(window:isExplicitlyVisible()), tostring(window:getParent() and window:getParent():getId()),
    tostring(target:getId())))
  call(m, 'move', target, want and want.height or nil, want and want.index or 1)
  if target:hasChild(window) then
    target:moveChildToIndex(window, math.max(1, math.min(want and want.index or 1, target:getChildCount())))
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
  if plan.restore then
    restoreWindow(m, window)
  end
  if plan.consumeWant then
    want = nil
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
  for i, delay in ipairs(L.PASSES) do
    local last = i == #L.PASSES
    events[#events + 1] = scheduleEvent(function()
      if g_game.isOnline() then M.sync('start') end
      if last then want = nil end -- a later close by the player is never undone
    end, delay)
  end
end

local function rememberWindow()
  local m, _, window = minimapModule()
  if not m then return end
  local p = panelOf(window)
  want = L.remember({ visible = window:isExplicitlyVisible(), fullmap = rawget(m, 'fullmapView') == true,
    panelId = p and p.id or nil, index = p and p.widget:getChildIndex(window) or 1, height = window:getHeight() })
end

local function onGameStart()
  cancelPasses()
  -- a module reload while online: the map is already known
  if L.validPos(playerPos()) then schedulePasses() end
end

local function onMapKnown()
  schedulePasses()
end

local function onTeleport()
  addEvent(function()
    if g_game.isOnline() then M.sync('teleport') end
  end)
end

local function onDeath()
  rememberWindow()
end

local function onGameEnd()
  cancelPasses()
  -- a death already remembered the window as it was before the death window
  if want == nil then rememberWindow() end
  M.sync('end')
end

local function safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then g_logger.warning('[minimapsync] ' .. name .. ': ' .. tostring(err)) end
  end
end

function M.init()
  -- the handlers return nothing: the engine stops a handler table at the first one that returns true
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
