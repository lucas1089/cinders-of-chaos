-- game_mobilehud logic (pure, no engine calls). O401 (owner 2026-11-04): on a phone the bottom hotkey bars took room
-- from the map. The first time a character enters the game on a phone, the three bottom action bars are switched off
-- once; the flag keeps it from happening again, so a player who turns a bar back on (Options) keeps it.
MobileHudLogic = MobileHudLogic or {}
local L = MobileHudLogic

L.FLAG = 'chaosMobileNoBottomBars'
L.BARS = { 'actionBarShowBottom1', 'actionBarShowBottom2', 'actionBarShowBottom3' }
L.DELAY_MS = 1500   -- after the action bar module has built its bars for the character

-- the bars to switch off now (empty when not a phone or already done)
function L.barsToHide(isMobile, done)
  if not isMobile or done then return {} end
  local out = {}
  for i, name in ipairs(L.BARS) do out[i] = name end
  return out
end
