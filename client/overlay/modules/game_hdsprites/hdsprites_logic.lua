-- game_hdsprites, the decisions without client API (tested by hdsprites_logic_test.lua).
HdSpritesLogic = {}
local L = HdSpritesLogic

L.DIR = '/data/hd'
L.OPTION = 'hdMonsters'
L.MOBILE_FLAG = 'chaosHdMonstersMobile'

-- the settings value as a switch: a missing value (no settings module, no saved choice) counts as on
function L.isOn(value)
  return value ~= false
end

-- phones draw HD monsters off the first time (the pictures are 4x the pixels of the plain ones and every sprite is cut and
-- scaled once); once per install, the player may turn it back on. true: switch the option off now
function L.mobileDefault(isMobile, done)
  return isMobile == true and done ~= true
end

-- what to tell the log after the load: the engine returns the number of sprites, 0 for no overlay
function L.summary(count, enabled)
  if type(count) ~= 'number' or count <= 0 then return 'no HD overlay found' end
  return 'HD overlay: ' .. tostring(count) .. ' sprites, ' .. (enabled and 'on' or 'off')
end
