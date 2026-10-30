-- game_walkpad: the walking pad of client_mobile (the round pad with 4 arrows, phones only) can be moved.
-- A small handle sits in the top left corner of the pad. Drag it: the whole pad follows your finger and the place is
-- saved in g_settings (as a fraction of the free room, so a scale change keeps it on screen). Double tap the handle: the
-- pad goes back to the default place (left edge, above the health orb). Walking on the pad itself is the base's and
-- unchanged: the handle is a child that takes its own touches. client_mobile creates the pad, this module only finds it
-- by id 'keypad' and moves its anchors. Rules in walkpad_logic.lua. No base patch.
ChaosWalkPad = ChaosWalkPad or {}
local M = ChaosWalkPad
local L = WalkPadLogic

local KEY_X, KEY_Y = 'chaosWalkPadX', 'chaosWalkPadY'
local RETRY_MS, RETRY_MAX = 500, 40

local keypad, handle, parent
local findEvent
local tries = 0
local drag = nil       -- { sx, sy, px, py, moved }
local lastTap = nil    -- { ms, x, y }

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

local function isTouch(button)
  return button == MouseTouch or button == MouseLeftButton
end

local function sizes()
  return parent:getWidth(), parent:getHeight(), keypad:getWidth(), keypad:getHeight()
end

local function place(x, y)
  local sw, sh, w, h = sizes()
  x, y = L.clamp(x, y, sw, sh, w, h)
  keypad:breakAnchors()
  keypad:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  keypad:addAnchor(AnchorTop, 'parent', AnchorTop)
  keypad:setMarginLeft(x)
  keypad:setMarginTop(y)
  keypad:setMarginRight(0)
  keypad:setMarginBottom(0)
  return x, y
end

local function save(x, y)
  local sw, sh, w, h = sizes()
  local fx, fy = L.toFraction(x, y, sw, sh, w, h)
  pcall(function()
    g_settings.set(KEY_X, fx)
    g_settings.set(KEY_Y, fy)
    g_settings.save()
  end)
end

local function forget()
  pcall(function()
    g_settings.set(KEY_X, -1)
    g_settings.set(KEY_Y, -1)
    g_settings.save()
  end)
end

local function savedFraction()
  local ok, fx = pcall(g_settings.getNumber, KEY_X, -1)
  local ok2, fy = pcall(g_settings.getNumber, KEY_Y, -1)
  if not ok or not ok2 then return nil, nil end
  return fx, fy
end

local function restore()
  if not alive(keypad) or not alive(parent) then return end
  local sw, sh, w, h = sizes()
  if sw <= 0 or sh <= 0 then return end
  local fx, fy = savedFraction()
  local x, y = L.fromFraction(fx, fy, sw, sh, w, h)
  place(x, y)
end

local function curPos()
  return keypad:getX() - parent:getX(), keypad:getY() - parent:getY()
end

local function onPress(widget, pos, button)
  if not isTouch(button) then return false end
  local px, py = curPos()
  drag = { sx = pos.x, sy = pos.y, px = px, py = py, moved = 0 }
  return true
end

local function onMove(widget, pos, offset)
  if not drag then return false end
  local dx, dy = pos.x - drag.sx, pos.y - drag.sy
  drag.moved = math.max(drag.moved, math.abs(dx), math.abs(dy))
  if not L.isTap(drag.moved) then
    local sw, sh, w, h = sizes()
    local x, y = L.drag(drag.px, drag.py, dx, dy, sw, sh, w, h)
    place(x, y)
  end
  return true
end

local function onRelease(widget, pos, button)
  if not isTouch(button) or not drag then return false end
  local d = drag
  drag = nil
  if L.isTap(d.moved) then
    local now = g_clock.millis()
    if lastTap and L.isDoubleTap(lastTap.ms, lastTap.x, lastTap.y, now, pos.x, pos.y) then
      lastTap = nil
      forget()
      restore()
    else
      lastTap = { ms = now, x = pos.x, y = pos.y }
    end
  else
    lastTap = nil
    save(curPos())
  end
  return true
end

local function build()
  parent = keypad:getParent()
  handle = g_ui.createWidget('UIWidget', keypad)
  handle:setId('walkpadHandle')
  handle:setSize({ width = L.HANDLE, height = L.HANDLE })
  handle:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  handle:addAnchor(AnchorTop, 'parent', AnchorTop)
  handle:setMarginLeft(4)
  handle:setMarginTop(4)
  handle:setBackgroundColor('#000000aa')
  handle:setBorderWidth(2)
  handle:setBorderColor('#ffffffaa')
  handle:setFocusable(false)
  handle:setPhantom(false)
  handle.onMousePress = onPress
  handle.onTouchPress = onPress
  handle.onMouseMove = onMove
  handle.onMouseRelease = onRelease
  handle.onTouchRelease = onRelease
  connect(parent, { onGeometryChange = restore })
  restore()
end

local function find()
  findEvent = nil
  local root = g_ui.getRootWidget()
  keypad = root and root:recursiveGetChildById('keypad') or nil
  if alive(keypad) and alive(keypad:getParent()) then
    build()
    return
  end
  keypad = nil
  tries = tries + 1
  if tries < RETRY_MAX then
    findEvent = scheduleEvent(find, RETRY_MS)
  end
end

function M.init()
  if not g_app.isMobile() then return end
  find()
end

function M.terminate()
  if findEvent then removeEvent(findEvent) findEvent = nil end
  if alive(parent) then pcall(disconnect, parent, { onGeometryChange = restore }) end
  if alive(handle) then handle:destroy() end
  handle, keypad, parent = nil, nil, nil
end
