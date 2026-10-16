-- game_shaderfx: the UI widget shaders of base patch 0044 (client/MANIFEST.md "game_shaderfx").
--   liquid orbs   two orbs beside the chat panel, health at its left edge and mana at its right edge, bottom-aligned
--                 with it (anchored to bottomSplitter, so they follow its resize and move; game_chatpanel centres the
--                 group and leaves out the orbs on a window too narrow for them). Health and mana as a moving liquid
--                 (chaos_ui_orb); a change of the value makes it slosh. Option liquidOrbs (off by default), size
--                 liquidOrbSize (small / medium / large, medium by default).
--   frame shine   a light sweep across the rarity frame of legendary-and-up and unique items in inventory and
--                 container slots (chaos_ui_shine; game_itemrarity calls onRarityFrame). Option rarityFrameShine.
--   greyscale     an item its player locked (custom attribute 3 = 1) is drawn grey in its slot; a bound item (2, the
--                 Everfull potions) keeps its colours (chaos_ui_grey as the item shader;
--                 game_itemrarity calls onSlotItem). setGreyed(widget, on) for any other module.
-- The engine part (UIWidget:setUiShader / setUiShaderParams) is base patch 0044; a client without it keeps plain
-- images (every call is guarded). Pure helpers in shaderfxlogic.lua (shaderfx_test.lua).
local L = ShaderFxLogic

local orbs -- {health = widget, mana = widget} while the orbs exist
local orbsFit = true -- game_chatpanel: false when the window leaves no room for them beside the chat
local options = { shine = true, orbs = false, orbSize = L.ORB_DEFAULT_SIZE }
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
  return orbs and orbs[kind] or nil
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

-- size of the orbs (option liquidOrbSize) and of their number
local function applyOrbSize()
  local size, liquidSize, font = L.orbSize(options.orbSize)
  for _, kind in ipairs({ 'health', 'mana' }) do
    local w = orbWidget(kind)
    if w then
      w:setSize({ width = size, height = size })
      local liquid = w:getChildById('liquid')
      if liquid then liquid:setSize({ width = liquidSize, height = liquidSize }) end
      local label = w:getChildById('value')
      if label then pcall(label.setFont, label, font) end
    end
  end
end

-- anchor the orbs to the chat panel's edges (bottomSplitter): health right of its left edge's grip, mana past the
-- width grip, both on the window's bottom edge like the chat. Without the chat panel (mobile) or game_chatpanel: the
-- bottom corners of the root panel.
local function placeOrbs()
  if not orbs then return end
  local gi = modules.game_interface
  local root = gi and gi.getRootPanel and gi.getRootPanel()
  local splitter = root and root:getChildById('bottomSplitter')
  local logic = rawget(_G, 'ChaosChatLogic')
  local m = logic and logic.orbMargins and logic.orbMargins() or nil
  local beside = splitter and splitter:isVisible() and m ~= nil
  for _, kind in ipairs({ 'health', 'mana' }) do
    local w = orbWidget(kind)
    if w then
      w:breakAnchors()
      w:addAnchor(AnchorBottom, 'parent', AnchorBottom)
      w:setMarginBottom(m and m.bottom or L.ORB_EDGE)
      if beside then
        if kind == 'health' then
          w:addAnchor(AnchorRight, 'bottomSplitter', AnchorLeft)
          w:setMarginRight(m.left)
        else
          w:addAnchor(AnchorLeft, 'bottomSplitter', AnchorRight)
          w:setMarginLeft(m.right)
        end
      elseif kind == 'health' then
        w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        w:setMarginLeft(L.ORB_EDGE)
      else
        w:addAnchor(AnchorRight, 'parent', AnchorRight)
        w:setMarginRight(L.ORB_EDGE)
      end
      w:setVisible(orbsFit)
    end
  end
end

-- game_chatpanel: the room the orbs take beside the chat (0 while they are off)
function getOrbReserve()
  if not options.orbs then return 0 end
  return (L.orbSize(options.orbSize))
end

-- game_chatpanel: whether the orbs fit beside the chat in this window
-- (game_chatpanel loads after this module: its call also anchors the orbs to the chat once its logic exists)
function setOrbsFit(fit)
  orbsFit = fit ~= false
  placeOrbs()
end

local function relayoutChat()
  local chat = rawget(_G, 'ChaosChatPanel')
  if chat and chat.relayout then pcall(chat.relayout) end
end

local function destroyOrbs()
  if sloshEvent then removeEvent(sloshEvent) sloshEvent = nil end
  if orbs then
    for _, w in pairs(orbs) do w:destroy() end
    orbs = nil
  end
  orbState = {}
end

local function createOrbs()
  if orbs then return end
  local gi = modules.game_interface
  local root = gi and gi.getRootPanel and gi.getRootPanel()
  if not root then return end
  g_ui.importStyle('shaderfx')
  orbs = {}
  for kind, id in pairs({ health = 'healthOrb', mana = 'manaOrb' }) do
    local w = g_ui.createWidget('ChaosOrb', root)
    w:setId(id)
    orbs[kind] = w
  end
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
  applyOrbSize()
  placeOrbs()
  if g_game.isOnline() then refreshOrbs() end
end

local function applyOrbs()
  if options.orbs then createOrbs() else destroyOrbs() end
  relayoutChat() -- the chat makes room for the orbs (or takes it back)
end

-- ---------------------------------------------------------------- options (client_settings, base patch 0044)
function onOption(which, value)
  if which == 'shine' then
    options.shine = value ~= false
    if g_game.isOnline() then refreshFrames() end
  elseif which == 'orbs' then
    options.orbs = value == true
    applyOrbs()
  elseif which == 'orbSize' then
    options.orbSize = tonumber(value) or L.ORB_DEFAULT_SIZE
    applyOrbSize()
    relayoutChat()
  end
end

local function readOptions()
  local s = modules.client_settings
  if not s or not s.getOption then return end
  local ok, v = pcall(s.getOption, 'rarityFrameShine')
  if ok and v ~= nil then options.shine = v ~= false end
  ok, v = pcall(s.getOption, 'liquidOrbs')
  if ok and v ~= nil then options.orbs = v == true end
  ok, v = pcall(s.getOption, 'liquidOrbSize')
  if ok and tonumber(v) then options.orbSize = tonumber(v) end
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
