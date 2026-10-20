-- Pure rules of game_minimapsync (client/MANIFEST.md "Minimap after a death"; tested by minimapsync_logic_test.lua).
-- Lua 5.1 / LuaJIT and Lua 5.3.
MinimapSyncLogic = {}
local L = MinimapSyncLogic

-- the passes after the map of a new session is known (ms): at once, after game_interface restored the saved side
-- panel layout (its addEvent), after the minimap's own expansion restore (250 ms, retried) and after
-- game_chaoslayout (800 ms)
L.PASSES = { 0, 400, 1200, 3000 }

local MAX_XY = 65535
local MAX_Z = 15

-- a tile of the map (the engine's Position::isMapPosition)
function L.validPos(p)
  if type(p) ~= 'table' then return false end
  local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
  if not x or not y or not z then return false end
  return x >= 0 and y >= 0 and z >= 0 and x < MAX_XY and y < MAX_XY and z <= MAX_Z
end

function L.samePos(a, b)
  return L.validPos(a) and L.validPos(b) and a.x == b.x and a.y == b.y and a.z == b.z
end

-- what the window was at the death or the end of a session; nil when it was closed (the player's choice is kept)
-- w = { visible, fullmap, panelId, index, height }
function L.remember(w)
  if type(w) ~= 'table' then return nil end
  if w.visible ~= true and w.fullmap ~= true then return nil end
  return { panelId = w.panelId, index = tonumber(w.index) or 1, height = tonumber(w.height) }
end

-- the panel to put the window back in: the one it was in when that panel still exists and is shown, else the
-- fallback (game_interface.getRightPanel(), the rightmost side panel, where game_minimap puts it at start).
-- panels = { { id, usable } } (usable: alive and shown)
function L.pickPanel(want, panels, fallbackId)
  if type(want) == 'table' and want.panelId then
    for _, p in ipairs(panels or {}) do
      if p.id == want.panelId and p.usable then return p.id end
    end
  end
  return fallbackId
end

-- what to do now. s = { reason = 'start' | 'teleport' | 'end', fullmap, inWindow, windowShown, inPanel, want,
-- pos, camera }:
--   exitFullMap: a full map view (Ctrl+Shift+M) left over from the last session (or at its end) is closed, so the
--                minimap widget is back in its window and follows the character (game_minimap skips the camera while
--                the full map is open);
--   reparent:    the minimap widget is not inside its window (and no full map view): put it back;
--   restore:     the window was open at the death / the end of the session and now it is not shown, or not in a
--                shown side panel: put it back in a panel and open it (game_minimap.move);
--   recentre:    the camera is not on the character's tile;
--   consumeWant: the window is where it should be, so later passes no longer touch it (a close by the player stays).
function L.plan(s)
  s = s or {}
  local out = { exitFullMap = false, reparent = false, restore = false, recentre = false, consumeWant = false }
  local fullmap = s.fullmap == true
  if fullmap and s.reason ~= 'teleport' then
    out.exitFullMap = true
    fullmap = false
  end
  if fullmap or s.reason == 'end' then
    return out
  end
  out.reparent = s.inWindow == false
  if s.want ~= nil then
    if s.windowShown == true and s.inPanel == true then
      out.consumeWant = true
    else
      out.restore = true
    end
  end
  out.recentre = L.validPos(s.pos) and not L.samePos(s.camera, s.pos)
  return out
end

return MinimapSyncLogic
