-- ChaosItemPicker: the item-picker mode of the helper's item slots (healing potions, runes, tools, timers, equipment,
-- supplies, food, stamina), the same as "Use with" (client/MANIFEST.md "Helper item slots").
-- The helper only pushed the 'target' cursor. With the system (native) cursor, which the client uses by default, that
-- shows nothing: game_interface's startUseWith also calls g_mouse.setGrabber(widget, 'target'), which sets the
-- system cursor. begin does both and finish undoes both, once. Right-click or Escape cancels: the slot's own release
-- handler runs with a position off the window, so it picks nothing (every helper handler returns quietly when no
-- widget is there) and does its own clean-up (ungrab, show the helper again).
-- Base patch 0066 calls begin after each picker sets its onMouseRelease, and finish where it popped the cursor.
ChaosItemPicker = ChaosItemPicker or {}
local P = ChaosItemPicker

P.OFF = { x = -100000, y = -100000 } -- a release here hits no widget
P.cancelling = false -- true while a cancel runs the slot's handler (a handler may skip its "no item" message)

-- the client calls (replaced in itempicker_test.lua)
P.env = P.env or {
  setGrabber = function(w) if g_mouse.setGrabber then g_mouse.setGrabber(w, 'target') end end,
  releaseGrabber = function(w) if g_mouse.releaseGrabber then g_mouse.releaseGrabber(w) end end,
  pushCursor = function() g_mouse.pushCursor('target') end,
  popCursor = function() g_mouse.popCursor('target') end,
  bindEscape = function(f) g_keyboard.bindKeyDown('Escape', f) end,
  unbindEscape = function(f) g_keyboard.unbindKeyDown('Escape', f) end,
  rightButton = function() return MouseRightButton end,
  leftButton = function() return MouseLeftButton end,
}

local active = nil -- {grabber, handler}

local function cancel()
  local a = active
  if not a or not a.handler then
    P.finish(a and a.grabber)
    return true
  end
  P.cancelling = true
  local ok, err = pcall(a.handler, a.grabber, P.OFF, P.env.leftButton())
  P.cancelling = false
  if active == a then P.finish(a.grabber) end -- a handler that did not call finish
  if not ok then error(err) end
  return true
end

-- the picker mode starts: call it after grabber.onMouseRelease is set
function P.begin(grabber)
  if not grabber then return end
  if active and active.grabber ~= grabber then cancel() end
  if active then P.finish(grabber) end
  local handler = grabber.onMouseRelease
  active = { grabber = grabber, handler = handler }
  if handler then
    grabber.onMouseRelease = function(self, pos, button)
      if button == P.env.rightButton() then return cancel() end
      return handler(self, pos, button)
    end
  end
  P.env.setGrabber(grabber)
  P.env.pushCursor()
  P.env.bindEscape(cancel)
end

-- the picker mode ends (a pick or a cancel): the cursor back, once
function P.finish(grabber)
  if not active or (grabber and active.grabber ~= grabber) then return false end
  local g = active.grabber
  active = nil
  P.env.unbindEscape(cancel)
  P.env.releaseGrabber(g)
  P.env.popCursor()
  return true
end

function P.isActive()
  return active ~= nil
end

P.cancel = cancel

return ChaosItemPicker
