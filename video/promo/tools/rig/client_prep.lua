-- rig.sh char: a clean frame for footage. Closes open windows, hides the chat panel, the fps and ping labels,
-- and raises the minimum light so dark hunts read on video.
for _, w in ipairs(rootWidget:getChildren()) do
  if w:isVisible() and w:getClassName() == 'UIWindow' then w:destroy() end
end
local gi = modules.game_interface
local b = gi.getBottomPanel()
b:setHeight(0)
b:hide()
pcall(function() modules.client_topmenu.setFpsVisible(false) modules.client_topmenu.setPingVisible(false) end)
pcall(function() gi.getMapPanel():setMinimumAmbientLight(0.7) end)
pcall(function() g_modules.getModule('game_deathrecap'):unload() end)
-- scripted input for takes: Rig.seq({{delay_ms, fn}, ...}) runs each fn after the delays add up
Rig = Rig or {}
function Rig.near(maxd)
  local me = g_game.getLocalPlayer()
  local pos = me:getPosition()
  local best, bd = nil, 99
  for _, c in ipairs(g_map.getSpectators(pos, false)) do
    if c:isMonster() and c:getPosition().z == pos.z then
      local d = math.max(math.abs(c:getPosition().x - pos.x), math.abs(c:getPosition().y - pos.y))
      if d < bd then best, bd = c, d end
    end
  end
  if best and bd <= (maxd or 7) then return best end
end
function Rig.seq(steps)
  local t = 0
  for _, s in ipairs(steps) do
    t = t + s[1]
    local f = s[2]
    scheduleEvent(function() pcall(f) end, t)
  end
  return t
end
function Rig.say(w) return function() g_game.talk(w) end end
function Rig.walk(d) return function() g_game.walk(d) end end
function Rig.attack() return function() local m = Rig.near(7) if m then g_game.attack(m) end end end
function Rig.attackName(part)
  return function()
    for _, c in ipairs(g_map.getSpectators(g_game.getLocalPlayer():getPosition(), false)) do
      if c:getName():find(part) then g_game.attack(c) end
    end
  end
end
return 'prepped'
