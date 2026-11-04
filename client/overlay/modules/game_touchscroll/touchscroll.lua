-- game_touchscroll: phones only. A finger swipe scrolls the list, window or bag under it (owner 2026-11-04: lists only
-- scrolled by holding the scroll bar). Base patch 0184 calls g_ui.onTouchScrollStart when a finger first moves more
-- than 8 px; true makes the touch a scroll: no left button press, so no item drag and no click at the lift. The moves
-- come to g_ui.onTouchScrollMove, the lift to g_ui.onTouchScrollEnd, then the content glides on and slows down.
-- A finger that rested 350 ms on an item still drags the item; a touch that starts on a scroll bar moves the bar as
-- before; the map and everything without a scroll bar are unchanged. Rules in touchscroll_logic.lua.
ChaosTouchScroll = ChaosTouchScroll or {}
local M = ChaosTouchScroll
local L = TouchScrollLogic

local state = nil    -- { bar, axis, value, samples }
local glideEvent = nil
local saved = nil

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

local function barOf(w, axis)
  local bar = axis == 'v' and w.verticalScrollBar or w.horizontalScrollBar
  if not alive(bar) or not bar:isVisible() then return nil end
  if not L.canScroll(bar:getMinimum(), bar:getMaximum()) then return nil end
  return bar
end

local function isScrollBar(w)
  local ok, name = pcall(w.getClassName, w)
  return ok and name == 'UIScrollBar'
end

-- the scroll bar a gesture moves, or nil
local function target(startPos, dx, dy, heldMs)
  local root = g_ui.getRootWidget()
  local hit = root and root:recursiveGetChildByPos(startPos, false)
  if not alive(hit) then return nil end
  local draggable = hit:isDraggable()
  local canV, canH, onBar = nil, nil, false
  local w = hit
  while alive(w) do
    if isScrollBar(w) then onBar = true break end
    canV = canV or barOf(w, 'v')
    canH = canH or barOf(w, 'h')
    w = w:getParent()
  end
  local axis = L.decide(dx, dy, heldMs, canV ~= nil, canH ~= nil, draggable, onBar)
  if axis == 'v' then return canV, axis end
  if axis == 'h' then return canH, axis end
  return nil
end

local function stopGlide()
  if glideEvent then removeEvent(glideEvent) glideEvent = nil end
end

local function apply(s, delta)
  if not alive(s.bar) then return false end
  local before = s.value
  s.value = L.value(s.value, delta, s.bar:getMinimum(), s.bar:getMaximum())
  s.bar:setValue(math.floor(s.value + 0.5))
  return s.value ~= before
end

local function onStart(startPos, pos, heldMs)
  stopGlide()
  state = nil
  if not startPos or not pos then return false end
  local ok, bar, axis = pcall(target, startPos, pos.x - startPos.x, pos.y - startPos.y, heldMs)
  if not ok or not bar then return false end
  state = { bar = bar, axis = axis, value = bar:getValue(), samples = {} }
  local d = axis == 'v' and pos.y - startPos.y or pos.x - startPos.x
  L.addSample(state.samples, g_clock.millis(), d)
  pcall(apply, state, d)
  return true
end

local function onMove(pos, moved)
  local s = state
  if not s or not moved then return end
  local d = s.axis == 'v' and moved.y or moved.x
  L.addSample(s.samples, g_clock.millis(), d)
  pcall(apply, s, d)
end

local function glide(s, v, last)
  glideEvent = nil
  local now = g_clock.millis()
  local d
  d, v = L.glide(v, now - last)
  local ok, moved = pcall(apply, s, d)
  if ok and moved and v ~= 0 then
    glideEvent = scheduleEvent(function() glide(s, v, now) end, L.FRAME_MS)
  end
end

local function onEnd(pos)
  local s = state
  state = nil
  if not s then return end
  local v = L.speed(s.samples, g_clock.millis())
  if v ~= 0 then
    local now = g_clock.millis()
    glideEvent = scheduleEvent(function() glide(s, v, now) end, L.FRAME_MS)
  end
end

function M.init()
  if not g_app.isMobile() then return end
  saved = { start = g_ui.onTouchScrollStart, move = g_ui.onTouchScrollMove, finish = g_ui.onTouchScrollEnd }
  g_ui.onTouchScrollStart = onStart
  g_ui.onTouchScrollMove = onMove
  g_ui.onTouchScrollEnd = onEnd
end

function M.terminate()
  stopGlide()
  state = nil
  if saved then
    g_ui.onTouchScrollStart = saved.start
    g_ui.onTouchScrollMove = saved.move
    g_ui.onTouchScrollEnd = saved.finish
    saved = nil
  end
end
