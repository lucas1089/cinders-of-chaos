-- game_mobilebag: phones only. Container windows (backpacks, depot, loot bags) get bigger item cells that fill the side
-- panel (owner 2026-11-04: the backpack was too small to use with a finger). Runs after game_containers' own
-- Container.onOpen, which made the window and its 34 px grid; this sets the grid's cell size before the window takes its
-- height, and again when the panel changes width. A swipe scrolls the bag (game_touchscroll, base patch 0184).
-- Rules in mobilebag_logic.lua. Desktop: nothing changes.
ChaosMobileBag = ChaosMobileBag or {}
local M = ChaosMobileBag
local L = MobileBagLogic

local active = false

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

local function resize(window)
  if not alive(window) then return end
  local panel = window:getChildById('contentsPanel')
  local layout = panel and panel:getLayout()
  if not layout or not layout.setCellSize then return end
  local spacing = layout:getCellSpacing() or 0
  local cell = L.cell(panel:getPaddingRect().width, spacing)
  local cur = layout:getCellSize()
  if cur and cur.width == cell and cur.height == cell then return end
  layout:setCellSize({ width = cell, height = cell })
  if window.setContentMinimumHeight then
    window:setContentMinimumHeight(cell)
    window:setContentMaximumHeight(L.maxHeight(cell, spacing, layout:getNumLines()))
  end
end

local function onOpen(container)
  if not active or not container then return end
  local window = container.window
  if not alive(window) then return end
  pcall(resize, window)
  if not window.chaosMobileBag then
    window.chaosMobileBag = true
    local panel = window:getChildById('contentsPanel')
    if panel then
      connect(panel, { onGeometryChange = function() pcall(resize, window) end })
    end
  end
  -- the panel width is final once the window sits in its side panel
  addEvent(function() pcall(resize, window) end)
end

function M.init()
  if not g_app.isMobile() then return end
  active = true
  connect(Container, { onOpen = onOpen })
end

function M.terminate()
  if not active then return end
  active = false
  disconnect(Container, { onOpen = onOpen })
end
