-- game_shaderfx: the UI widget shaders of base patch 0044 (client/MANIFEST.md "game_shaderfx").
--   liquid orbs   two orbs at the bottom corners of the game window, health and mana as a moving liquid
--                 (chaos_ui_orb); a change of the value makes it slosh. Option liquidOrbs (off by default).
--   frame shine   a light sweep across the rarity frame of legendary-and-up and unique items in inventory and
--                 container slots (chaos_ui_shine; game_itemrarity calls onRarityFrame). Option rarityFrameShine.
--   greyscale     a locked item (custom attribute 3) is drawn grey in its slot (chaos_ui_grey as the item shader;
--                 game_itemrarity calls onSlotItem). setGreyed(widget, on) for any other module.
-- The engine part (UIWidget:setUiShader / setUiShaderParams) is base patch 0044; a client without it keeps plain
-- images (every call is guarded). Pure helpers in shaderfxlogic.lua (shaderfx_test.lua).
local L = ShaderFxLogic

local orbs
local options = { shine = true, orbs = false }
local orbState = {} -- 'health' / 'mana' -> {fill, slosh}
local sloshEvent
local SLOSH_TICK = 50
local registered = false

local function hasUiShaders(widget)
  return widget and widget.setUiShader ~= nil and widget.setUiShaderParams ~= nil
end

local function registerShaders()
  if registered or not g_shaders or not g_shaders.createShader then return end
  registered = true
  for _, s in ipairs(L.UI_SHADERS) do
    local ok, err = pcall(g_shaders.createShader, s.name, s.vertex, s.fragment)
    if not ok then
      g_logger.warning('[shaderfx] ' .. s.name .. ': ' .. tostring(err))
    end
  end
end

-- ---------------------------------------------------------------- greyscale
-- grey a widget (an item slot: its item; any other widget: its image) or take our grey back
function setGreyed(widget, on)
  if not widget or widget:isDestroyed() then return end
  if widget.setItemShader then
    L.applyItemGrey(widget, on) -- marks the slot before the shader call, which re-enters here (shaderfxlogic.lua)
  elseif hasUiShaders(widget) then
    if on then
      widget:setUiShader('chaos_ui_grey')
      widget.sfxGrey = true
    elseif widget.sfxGrey then
      widget:setUiShader('')
      widget.sfxGrey = nil
    end
  end
end

-- game_itemrarity: an inventory or container slot got an item (or none)
function onSlotItem(widget, item)
  setGreyed(widget, L.isLocked(item))
end

-- ---------------------------------------------------------------- frame shine
-- game_itemrarity: a slot's rarity frame was coloured (rarityId 0 = no frame any more)
function onRarityFrame(frame, rarityId, unique)
  if not hasUiShaders(frame) or frame:isDestroyed() then return end
  local parent = frame:getParent()
  local key = parent and (parent:getId() .. ':' .. tostring(parent:getParent() and parent:getParent():getId() or '')) or frame:getId()
  local a, b, c, d = L.shineParams(rarityId, unique, options.shine, key)
  if a then
    frame:setUiShader('chaos_ui_shine')
    frame:setUiShaderParams(a, b, c, d)
    frame.sfxShine = { rarityId, unique }
  elseif frame.sfxShine or frame:getUiShader() == 'chaos_ui_shine' then
    frame:setUiShader('')
    frame.sfxShine = nil
  end
end

local function refreshFrames()
  -- game_itemrarity is not sandboxed: its functions are globals
  local refresh = rawget(_G, 'updateRarityFrame') or updateRarityFrame
  if type(refresh) ~= 'function' then return end
  for _, container in pairs(g_game.getContainers() or {}) do
    local panel = container.itemsPanel
    if panel and not panel:isDestroyed() then
      for _, child in ipairs(panel:getChildren()) do
        if child.getItem then pcall(refresh, child) end
      end
    end
  end
  local inv = modules.game_inventory
  local panel = inv and inv.getInventoryPanel and inv.getInventoryPanel()
  if panel then
    for slot = 1, 10 do
      local w = panel:getChildById('slot' .. slot)
      if w then pcall(refresh, w) end
    end
  end
end

-- ---------------------------------------------------------------- orbs
local function orbWidget(kind)
  return orbs and orbs:getChildById(kind == 'health' and 'healthOrb' or 'manaOrb')
end

local function paintOrb(kind)
  local w = orbWidget(kind)
  local st = orbState[kind]
  if not w or not st then return end
  local liquid = w:getChildById('liquid')
  if liquid and hasUiShaders(liquid) then
    liquid:setUiShaderParams(L.orbParams(st.fill, st.slosh, kind == 'health' and 0.13 or 0.71))
  end
end

local function sloshTick()
  sloshEvent = nil
  local again = false
  for kind, st in pairs(orbState) do
    if st.slosh > 0 then
      st.slosh = L.decay(st.slosh, SLOSH_TICK)
      paintOrb(kind)
      again = again or st.slosh > 0
    end
  end
  if again then sloshEvent = scheduleEvent(sloshTick, SLOSH_TICK) end
end

local function setOrb(kind, value, max)
  local st = orbState[kind] or { fill = 0, slosh = 0 }
  orbState[kind] = st
  local fill = L.fill(value, max)
  st.slosh = L.sloshAfter(st.fill, fill, st.slosh)
  st.fill = fill
  paintOrb(kind)
  local w = orbWidget(kind)
  local label = w and w:getChildById('value')
  if label then
    local f = rawget(_G, 'formatShortNumber') or tostring
    label:setText(f(value or 0))
  end
  if st.slosh > 0 and not sloshEvent then sloshEvent = scheduleEvent(sloshTick, SLOSH_TICK) end
end

local function onHealthChange(player, health, maxHealth)
  setOrb('health', health, maxHealth)
end

local function onManaChange(player, mana, maxMana)
  setOrb('mana', mana, maxMana)
end

local function refreshOrbs()
  local player = g_game.getLocalPlayer()
  if not player then return end
  setOrb('health', player:getHealth(), player:getMaxHealth())
  setOrb('mana', player:getMana(), player:getMaxMana())
end

local function destroyOrbs()
  if sloshEvent then removeEvent(sloshEvent) sloshEvent = nil end
  if orbs then orbs:destroy() orbs = nil end
  orbState = {}
end

local function createOrbs()
  if orbs then return end
  local gi = modules.game_interface
  local map = gi and gi.getMapPanel and gi.getMapPanel()
  if not map then return end
  orbs = g_ui.loadUI('shaderfx', map)
  if not orbs then return end
  for kind, color in pairs(L.ORB_COLORS) do
    local w = orbWidget(kind)
    local liquid = w and w:getChildById('liquid')
    if liquid then
      liquid:setImageColor(color)
      if hasUiShaders(liquid) then
        liquid:setUiShader('chaos_ui_orb')
      end
    end
  end
  if g_game.isOnline() then refreshOrbs() end
end

local function applyOrbs()
  if options.orbs then createOrbs() else destroyOrbs() end
end

-- ---------------------------------------------------------------- options (client_settings, base patch 0044)
function onOption(which, value)
  if which == 'shine' then
    options.shine = value ~= false
    if g_game.isOnline() then refreshFrames() end
  elseif which == 'orbs' then
    options.orbs = value == true
    applyOrbs()
  end
end

local function readOptions()
  local s = modules.client_settings
  if not s or not s.getOption then return end
  local ok, v = pcall(s.getOption, 'rarityFrameShine')
  if ok and v ~= nil then options.shine = v ~= false end
  ok, v = pcall(s.getOption, 'liquidOrbs')
  if ok and v ~= nil then options.orbs = v == true end
end

function init()
  registerShaders()
  readOptions()
  connect(LocalPlayer, { onHealthChange = onHealthChange, onManaChange = onManaChange })
  connect(g_game, { onGameStart = refreshOrbs })
  applyOrbs()
end

function terminate()
  disconnect(LocalPlayer, { onHealthChange = onHealthChange, onManaChange = onManaChange })
  disconnect(g_game, { onGameStart = refreshOrbs })
  destroyOrbs()
end
