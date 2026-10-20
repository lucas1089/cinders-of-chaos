-- Pure rules of game_minimapsync (client/MANIFEST.md "Minimap after a death"; tested by minimapsync_logic_test.lua).
-- MinimapSyncLogic.plan(state) says what to do so the minimap of game_minimap shows the explored map around the
-- character: state = { reason = 'start' | 'teleport' | 'end', fullmap = bool, inWindow = bool, windowOpen = bool,
-- wantOpen = bool, pos = {x, y, z} | nil, camera = {x, y, z} | nil }.
-- Lua 5.1 / LuaJIT and Lua 5.3.
MinimapSyncLogic = {}
local L = MinimapSyncLogic

-- the passes after the map of a new session is known (ms): at once, after game_interface laid the side panels out
-- (next frames), after the minimap's own expansion restore (250 ms, retried) and game_chaoslayout (800 ms)
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

-- what to do now: { exitFullMap, reparent, open, recentre, consumeWant }
--   exitFullMap: a full map view (Ctrl+Shift+M) left over from the last session (or at its end) is closed, so the
--                minimap widget is back in its window and follows the character again (game_minimap skips the
--                camera while the full map is open);
--   reparent:    the minimap widget is not inside its window (and no full map view): put it back;
--   open:        the window was open when the character died or the session ended, and it is not now;
--   recentre:    the camera is not on the character's tile (also when a stuck drag made game_minimap skip it);
--   consumeWant: the window is open, so later passes no longer reopen it (a close by the player stays closed).
function L.plan(s)
  s = s or {}
  local out = { exitFullMap = false, reparent = false, open = false, recentre = false, consumeWant = false }
  local fullmap = s.fullmap == true
  if fullmap and s.reason ~= 'teleport' then
    out.exitFullMap = true
    fullmap = false
  end
  if fullmap or s.reason == 'end' then
    return out
  end
  out.reparent = s.inWindow == false
  if s.windowOpen then
    out.consumeWant = s.wantOpen == true
  elseif s.wantOpen == true then
    out.open = true
    out.consumeWant = true
  end
  out.recentre = L.validPos(s.pos) and not L.samePos(s.camera, s.pos)
  return out
end

-- whether the minimap window counts as open for the next session (it is shown, or the full map view replaced it)
function L.openAtEnd(windowVisible, fullmap)
  return windowVisible == true or fullmap == true
end

return MinimapSyncLogic
