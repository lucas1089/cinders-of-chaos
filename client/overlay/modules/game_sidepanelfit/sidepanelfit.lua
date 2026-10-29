-- game_sidepanelfit: the right and the left horizontal panel of game_interface (Options > Interface > Show Right /
-- Left Horizontal Panel) take no space while they hold no shown window (client/MANIFEST.md "Horizontal panels").
-- The base gives a shown panel a fixed height (200, or the saved one) whatever it holds, and base patch 0077 paints it
-- 'alpha' in the extended view, so an empty panel was a tall gap where the map shows through, with the side panels
-- pushed down below it. This module checks both panels a few times a second: no shown child -> height 0 (a strip of
-- 80 px while a window is dragged, so a window can still be dropped in); a window arrives -> the last height, or 200,
-- and the normal panel background. Switching the option off is the base's (height 0, windows moved out); on again,
-- an empty panel collapses at the next check, so there is no gap either way. Rules in sidepanelfit_logic.lua.
ChaosSidePanelFit = ChaosSidePanelFit or {}
local M = ChaosSidePanelFit
local L = SidePanelFitLogic

local PANELS = {
  { id = 'horizontalRightPanel', option = 'showRightHorizontalPanel' },
  { id = 'horizontalLeftPanel', option = 'showLeftHorizontalPanel' },
}
local INTERVAL = 250 -- ms

local cycle = nil
local handlers = {}
local remembered = {}

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

local function optionOn(name)
  local cs = modules and modules.client_settings
  if not cs or not cs.getOption then return false end
  local ok, v = pcall(cs.getOption, name)
  return ok and v == true
end

local function dragging()
  local ok, w = pcall(function() return g_ui.getDraggingWidget() end)
  return ok and alive(w) and w:getClassName() == 'UIMiniWindow'
end

local function fit(spec, root, drag)
  local panel = root:getChildById(spec.id)
  if not alive(panel) then return end
  local shown = {}
  for _, c in ipairs(panel:getChildren()) do
    shown[#shown + 1] = { visible = c:isVisible() }
  end
  local plan = L.plan({
    optionOn = optionOn(spec.option),
    height = panel:getHeight(),
    remembered = remembered[spec.id],
    visible = L.visibleCount(shown),
    dragging = drag,
  })
  if plan.remember then remembered[spec.id] = plan.remember end
  if plan.opaque then panel:setImageColor('white') end
  if plan.height ~= nil then panel:setHeight(plan.height) end
end

function M.check()
  local gi = modules and modules.game_interface
  local root = gi and gi.getRootPanel and gi.getRootPanel() or nil
  if not alive(root) then return end
  local drag = dragging()
  for _, spec in ipairs(PANELS) do
    local ok, err = pcall(fit, spec, root, drag)
    if not ok then g_logger.warning('[sidepanelfit] ' .. spec.id .. ': ' .. tostring(err)) end
  end
end

local function stop()
  if cycle then removeEvent(cycle) cycle = nil end
end

local function start()
  stop()
  cycle = cycleEvent(M.check, INTERVAL)
end

function M.init()
  handlers.game = { onGameStart = function() start() end, onGameEnd = function() stop() end }
  connect(g_game, handlers.game)
  if g_game.isOnline() then start() end
end

function M.terminate()
  if handlers.game then disconnect(g_game, handlers.game) end
  handlers = {}
  stop()
end
