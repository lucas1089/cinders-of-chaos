-- Character plate drawn over the top-left corner of the map: portrait of the player in a gold ring,
-- level badge, name, health and mana bars with numbers and a thin experience line.
-- Art comes from client/tools/gen_skin.py (group "hud"); the stock health/mana panel stays as it is.
local hud
local BAR_W = 166

local function child(id)
  return hud and hud:getChildById(id)
end

local function setFill(id, value, max)
  local w = child(id)
  if not w then return end
  local px = HudMath.fillWidth(value, max, BAR_W)
  w:setVisible(px > 0)
  if px > 0 then
    w:setWidth(px)
    w:setImageClip({ x = 0, y = 0, width = px, height = w:getHeight() })
  end
end

local ensureFresh

local function onHealthChange(player, health, maxHealth)
  ensureFresh()
  setFill('hpFill', health, maxHealth)
  local t = child('hpText')
  if t then t:setText(HudMath.pair(health, maxHealth)) end
end

local function onManaChange(player, mana, maxMana)
  setFill('mpFill', mana, maxMana)
  local t = child('mpText')
  if t then t:setText(HudMath.pair(mana, maxMana)) end
end

local function onLevelChange(player, level, percent)
  local l = child('level')
  if l then l:setText(tostring(level)) end
  setFill('xpFill', percent or 0, 100)
  local x = child('xpHover')
  if x then x:setTooltip(tr('Experience: %d%% to level %d', percent or 0, (level or 0) + 1)) end
end

local function onOutfitChange(creature)
  local player = g_game.getLocalPlayer()
  if hud and player and creature == player then
    local p = hud:recursiveGetChildById('portrait')
    if p then p:setOutfit(player:getOutfit()) end
  end
end

local function refresh()
  local player = g_game.getLocalPlayer()
  if not hud or not player then return end
  local p = hud:recursiveGetChildById('portrait')
  if p then p:setOutfit(player:getOutfit()) end
  local n = child('name')
  if n then n:setText(player:getName()) end
  onHealthChange(player, player:getHealth(), player:getMaxHealth())
  onManaChange(player, player:getMana(), player:getMaxMana())
  onLevelChange(player, player:getLevel(), player:getLevelPercent())
end

-- The plate lives in the game root panel, which the interface hides while offline, so it needs no
-- show/hide of its own. Name and portrait are refreshed on game start and, in case another handler of
-- the game start signal stops the chain, on the first stat update of a session too.
local fresh = false

local function online()
  fresh = true
  refresh()
  scheduleEvent(refresh, 500)
end

local function offline()
  fresh = false
end

ensureFresh = function()
  if not fresh and g_game.isOnline() then
    fresh = true
    addEvent(refresh)
  end
end

function init()
  -- in the game root panel next to the map (the map panel itself reaches above the visible area)
  hud = g_ui.loadUI('chaoshud', modules.game_interface.getRootPanel())
  connect(LocalPlayer, { onHealthChange = onHealthChange, onManaChange = onManaChange, onLevelChange = onLevelChange })
  connect(Creature, { onOutfitChange = onOutfitChange })
  connect(g_game, { onGameStart = online, onGameEnd = offline })
  if g_game.isOnline() then online() end
end

function terminate()
  disconnect(LocalPlayer, { onHealthChange = onHealthChange, onManaChange = onManaChange, onLevelChange = onLevelChange })
  disconnect(Creature, { onOutfitChange = onOutfitChange })
  disconnect(g_game, { onGameStart = online, onGameEnd = offline })
  if hud then
    hud:destroy()
    hud = nil
  end
end
