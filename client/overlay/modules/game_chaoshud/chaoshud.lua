-- Character plate drawn over the top-left corner of the map: portrait of the player in a gold ring,
-- level badge, name, health and mana bars with numbers and a thin experience line.
-- Art comes from client/tools/gen_skin.py (group "hud"). The plate replaces two stock HUD pieces (see tidyHud below):
-- the health/mana bars of the right panel are hidden, and the Helper's shortcut column starts hidden.
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

local function onOutfitChange(player, outfit)
  if hud and player and player:isLocalPlayer() then
    local p = hud:recursiveGetChildById('portrait')
    if p then p:setOutfit(outfit or player:getOutfit()) end
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

-- ---------------------------------------------------------------- duplicates of the plate
-- The stock health/mana bars at the top of the right panel (game_healthinfo) show what the plate shows: hidden, and
-- hidden again when the base client lays its panels out anew. The Helper's shortcut column on the left edge is hidden
-- once, on the first login with this client (the Helper window's "Shortcuts" option shows it again; the choice is
-- kept by the Helper).
local HELPER_DEFAULT_KEY = 'chaos_hud_helper_shortcuts_default'

local function stockBars()
  local m = modules.game_healthinfo
  local getter = m and rawget(m, 'getHealthInfoWindow')
  local w = type(getter) == 'function' and getter() or rawget(_G, 'healthInfoWindow')
  if w and not w:isDestroyed() then return w end
  return nil
end

local function hideStockBars()
  local w = stockBars()
  if not w then return end
  if w:isVisible() then w:hide() end
  if not w.chaosHidden then
    w.chaosHidden = true
    connect(w, { onVisibilityChange = function(widget, visible)
      if visible and g_game.isOnline() then scheduleEvent(function() if widget:isVisible() then widget:hide() end end, 1) end
    end })
  end
end

local function helperShortcutsOffOnce()
  if g_settings.getBoolean(HELPER_DEFAULT_KEY) then return end
  local m = modules.game_helper
  local helper = m and rawget(m, '_Helper')
  local shortcut = helper and helper.Shortcut
  if shortcut and type(shortcut.toggle) == 'function' then
    pcall(shortcut.toggle, false)
    g_settings.set(HELPER_DEFAULT_KEY, true)
  end
end

local function tidyHud()
  if not g_game.isOnline() then return end
  hideStockBars()
  helperShortcutsOffOnce()
end

-- The plate lives in the game root panel, which the interface hides while offline, so it needs no
-- show/hide of its own. Name and portrait are refreshed on game start and, in case another handler of
-- the game start signal stops the chain, on the first stat update of a session too.
local fresh = false

local function online()
  fresh = true
  refresh()
  scheduleEvent(refresh, 500)
  -- after the stock modules (and the Helper's own 1 s start) have built their panels
  scheduleEvent(tidyHud, 1500)
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
  -- the outfit hook goes on LocalPlayer: another module's LocalPlayer.onOutfitChange hides Creature.onOutfitChange for
  -- the local player, so a Creature hook never fired and the portrait kept the login outfit
  connect(LocalPlayer, { onHealthChange = onHealthChange, onManaChange = onManaChange, onLevelChange = onLevelChange,
    onOutfitChange = onOutfitChange })
  connect(g_game, { onGameStart = online, onGameEnd = offline })
  if g_game.isOnline() then online() end
end

function terminate()
  disconnect(LocalPlayer, { onHealthChange = onHealthChange, onManaChange = onManaChange, onLevelChange = onLevelChange,
    onOutfitChange = onOutfitChange })
  disconnect(g_game, { onGameStart = online, onGameEnd = offline })
  if hud then
    hud:destroy()
    hud = nil
  end
end
