-- game_sidepanelfit: the right and the left horizontal panel of game_interface (Options > Interface > Show Right /
-- Left Horizontal Panel) take only the room of the windows they show (client/MANIFEST.md "Horizontal panels").
-- The base gives a horizontal panel a fixed height (200, or the saved one) whatever it holds, and base patch 0077 paints
-- it 'alpha' in the extended view, so the room under its last window was a gap where the map shows through, with the
-- side panels pushed down below it. Worse, at login game_sidebars sets the saved height and the layout restore puts the
-- saved windows back in the panel even with the option off, so the gap stayed with the option off too.
-- This module checks both panels a few times a second. Option off: every window in the panel goes to the side panel
-- (in its order, at the top) and the height goes to 0. Option on: the height is the shown windows' height (none: 0;
-- a strip of 80 px while a window is dragged, so a window can still be dropped in), and the normal panel background.
-- Rules in sidepanelfit_logic.lua.
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

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

-- true / false, or nil when the setting cannot be read (then nothing is touched)
local function optionOn(name)
  local cs = modules and modules.client_settings
  if not cs or not cs.getOption then return nil end
  local ok, v = pcall(cs.getOption, name)
  if not ok then return nil end
  return v == true
end

local function dragging()
  local ok, w = pcall(function() return g_ui.getDraggingWidget() end)
  return ok and alive(w) and w:getClassName() == 'UIMiniWindow'
end

-- the side panel the windows of a horizontal panel go to (as the base's moveToOtherPanel: the right one, or the left
-- one for the left horizontal panel while a left side panel is shown)
local function targetPanel(gi, spec)
  if spec.id == 'horizontalLeftPanel' and gi.getLeftPanel then
    local lp = gi.getLeftPanel()
    if alive(lp) and lp:isVisible() then return lp end
  end
  return gi.getRightPanel and gi.getRightPanel() or nil
end

local function evict(gi, spec, panel)
  local target = targetPanel(gi, spec)
  if not alive(target) or target == panel then return end
  local kids = panel:getChildren()
  for i, w in ipairs(kids) do
    panel:removeChild(w)
    target:insertChild(math.min(i, target:getChildCount() + 1), w)
  end
  if #kids > 0 then
    g_logger.info('[sidepanelfit] ' .. #kids .. ' window(s) moved out of ' .. spec.id .. ' (option off)')
    if target.fitAll then pcall(target.fitAll, target) end
  end
end

local function fit(gi, spec, root, drag)
  local panel = root:getChildById(spec.id)
  if not alive(panel) then return end
  local kids = {}
  for _, c in ipairs(panel:getChildren()) do
    kids[#kids + 1] = { visible = c:isVisible(), height = c:getHeight(),
      marginTop = c:getMarginTop(), marginBottom = c:getMarginBottom() }
  end
  local plan = L.plan({
    optionOn = optionOn(spec.option),
    height = panel:getHeight(),
    children = #kids,
    visible = L.visibleCount(kids),
    content = L.contentHeight(kids, { top = panel:getPaddingTop(), bottom = panel:getPaddingBottom() }),
    limit = L.limit(root:getHeight()),
    dragging = drag,
  })
  if plan.evict then evict(gi, spec, panel) end
  if plan.opaque then panel:setImageColor('white') end
  if plan.height ~= nil then panel:setHeight(plan.height) end
end

function M.check()
  local gi = modules and modules.game_interface
  local root = gi and gi.getRootPanel and gi.getRootPanel() or nil
  if not alive(root) then return end
  local drag = dragging()
  for _, spec in ipairs(PANELS) do
    local ok, err = pcall(fit, gi, spec, root, drag)
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
