-- game_minimaphd, the decisions without client API (tested by minimaphd_logic_test.lua).
MinimapHdLogic = {}
local L = MinimapHdLogic

L.DIR = '/data/minimap_hd'
L.OPTION = 'hdMinimap'
L.SHADER = 'chaos_minimap_hd'
L.VERTEX = '/shaders/chaos_minimap_vertex'
L.FRAGMENT = '/shaders/chaos_minimap_hd'
L.MIN_SCALE = 2          -- px per tile: HD from here up, the flat colours below (the engine rule, chaosminimaphd.h lodFor)
L.MOBILE_FLAG = 'chaosHdMinimapMobile'

-- the settings value as a switch: a missing value (no settings module, no saved choice) counts as on
function L.isOn(value)
  return value ~= false
end

-- what the engine offers: a client without base patch 0197 has none of these and nothing changes
function L.hasEngine(minimap)
  return type(minimap) == 'table' and minimap.loadHdAtlas ~= nil and minimap.setHdEnabled ~= nil
end

-- phones draw the flat map the first time (a block picture is up to 1 MB of texture); the player may turn it back on
function L.mobileDefault(isMobile, done)
  return isMobile == true and done ~= true
end

-- the log line after the load: the engine returns the number of swatches, 0 for no HD map
function L.summary(count, enabled)
  if type(count) ~= 'number' or count <= 0 then return 'no HD minimap atlas found, the flat map stays' end
  return 'HD minimap: ' .. tostring(count) .. ' swatches, ' .. (enabled and 'on' or 'off')
end
