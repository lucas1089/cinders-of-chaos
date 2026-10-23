-- game_helperhud: the helper's bot HUD (client/MANIFEST.md "Helper bot HUD"). Global ChaosBotHud, not sandboxed:
-- modules/game_helper calls ChaosBotHud.refreshBotHud() every 250 ms while online and ChaosBotHud.applyBotHudConfig()
-- when Tools > Bot HUD changes. The on/off state and the sections live in the helper's character save (botHud), so the HUD comes
-- back after a relog. Rows and layout: helperhud_logic.lua (helperhud_test.lua).
ChaosBotHud = ChaosBotHud or {}
local M = ChaosBotHud
local L = ChaosBotHudLogic

local hud = nil
local lastLayoutKey = nil
local lastMarginTop = nil

-- the helper tab icons in /images/ui/helper, the same clips as the helper window's tabs
local ICONS = {
  healing = { x = 0, y = 204, width = 34, height = 34 },
  tools = { x = 34, y = 204, width = 34, height = 34 },
  shooter = { x = 68, y = 204, width = 34, height = 34 }
}
local NAME_COLOR = { [true] = '#e8e8e8', [false] = '#7c736f' }
local VALUE_COLOR = { [true] = '#d8c7a8', [false] = '#6e6560' }
local ICON_COLOR = { [true] = '#ffffff', [false] = '#ffffff60' }

local function helperEnv()
  return modules and modules.game_helper or nil
end

local function helperConfig()
  local env = helperEnv()
  local helper = env and env._Helper
  if helper and helper.getHelperConfig then
    local ok, cfg = pcall(helper.getHelperConfig)
    if ok and type(cfg) == 'table' then return cfg end
  end
  return nil
end

local function destroy()
  if hud and not hud:isDestroyed() then hud:destroy() end
  hud = nil
  lastLayoutKey = nil
  lastMarginTop = nil
end

local function ensure()
  if hud and not hud:isDestroyed() then return hud end
  local gi = modules.game_interface
  local map = gi and gi.getMapPanel and gi.getMapPanel()
  if not map then return nil end
  hud = g_ui.createWidget('ChaosBotHud', map)
  if not hud then return nil end
  hud:addAnchor(AnchorTop, 'parent', AnchorTop)
  hud:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  hud:setMarginTop(L.HUD_GAP)
  return hud
end

-- keeps the HUD below the menu bar (client_chaos_topbar), which is drawn over the top of the map
local function placeBelowMenuBar(widget)
  local map = widget:getParent()
  local gi = modules.game_interface
  local root = gi and gi.getRootPanel and gi.getRootPanel()
  if not map or not root then return end
  local bar = root:getChildById('chaosMenuBar')
  local rect = bar and bar:isVisible() and bar:getRect() or nil
  local margin = L.topMargin(map:getY(), root:getY(), rect)
  if margin ~= lastMarginTop then
    lastMarginTop = margin
    widget:setMarginTop(margin)
  end
end

-- trims text to a pixel width with the real font metrics (binary search, only when it does not fit)
local function setFittedText(label, text, available)
  if label._hudText == text and label._hudAvailable == available then return end
  label._hudText, label._hudAvailable = text, available
  label:setText(text)
  if available <= 0 or label:getTextSize().width <= available then return end
  local low, high = 0, #text
  while low < high do
    local mid = math.floor((low + high + 1) / 2)
    label:setText(text:sub(1, mid) .. '..')
    if label:getTextSize().width <= available then low = mid else high = mid - 1 end
  end
  label:setText(text:sub(1, low) .. '..')
end

local function rowsOf(card)
  local container = card and card:getChildById('rows')
  if not container then return {} end
  local rows = {}
  for i = 1, L.MAX_ROWS do
    local row = container:getChildById('row' .. i)
    if not row then
      row = g_ui.createWidget('ChaosBotHudRow', container)
      row:setId('row' .. i)
    end
    rows[i] = row
  end
  return rows
end

local function applyRow(row, entry, valueWidth)
  if not row then return end
  if not entry then row:setVisible(false) return end
  local icon, name, value = row:getChildById('rowIcon'), row:getChildById('rowName'), row:getChildById('rowValue')
  if icon and ICONS[entry.icon] and row._icon ~= entry.icon then
    row._icon = entry.icon
    icon:setImageClip(ICONS[entry.icon])
  end
  if icon then icon:setImageColor(ICON_COLOR[entry.active]) end
  if name then
    name:setText(entry.name)
    name:setColor(NAME_COLOR[entry.active])
  end
  if value then
    setFittedText(value, entry.value, valueWidth)
    value:setColor(VALUE_COLOR[entry.active])
  end
  row:setVisible(true)
end

local function gatherState(cfg)
  local env = helperEnv() or {}
  local state = {}
  local target = g_game.getAttackingCreature and g_game.getAttackingCreature() or nil
  state.targetName = target and target:getName() or nil
  local spells = rawget(_G, 'Spells') or env.Spells
  state.spellName = function(id)
    local spell = id and id > 0 and spells and spells.getSpellDataById and spells.getSpellDataById(id) or nil
    return spell and (spell.name or spell.words) or nil
  end
  local player = g_game.getLocalPlayer()
  if player then
    state.player = { health = player:getHealth(), maxHealth = player:getMaxHealth(), mana = player:getMana(),
      maxMana = player:getMaxMana(), level = player:getLevel() }
  end
  return state
end

function M.refreshBotHud()
  local cfg = helperConfig()
  if not g_game.isOnline() or not L.isEnabled(cfg) then
    destroy()
    return
  end
  local widget = ensure()
  if not widget then return end
  placeBelowMenuBar(widget)
  local entries = L.entries(cfg, gatherState(cfg), tr)
  local shape = L.layout(cfg.botHud.size, #entries)

  local active = L.activeCount(entries)
  local color = active > 0 and '#44ad25' or '#707070'
  local status = widget:getChildById('hudStatus')
  if status then
    status:setColor(color)
    status:setText(active > 0 and tr('Active: %d modules', active) or tr('Standby'))
  end
  local dot = widget:getChildById('hudStatusDot')
  if dot then
    dot:setBackgroundColor(color)
    dot:setBorderColor(color)
  end

  local left, right = widget:getChildById('hudLeftCard'), widget:getChildById('hudRightCard')
  local leftRows, rightRows = rowsOf(left), rowsOf(right)
  for i = 1, L.MAX_ROWS do
    applyRow(leftRows[i], i <= shape.rowsPerColumn and entries[i] or nil, shape.valueWidth)
    applyRow(rightRows[i], shape.twoColumns and entries[shape.rowsPerColumn + i] or nil, shape.valueWidth)
  end

  -- re-anchoring and resizing relayout the whole HUD: only when the shape changes
  local header = left and (left:getY() - widget:getY()) or 0
  if header <= 0 then header = 25 end
  local key = string.format('%d|%s|%d|%d', shape.width, tostring(shape.twoColumns), shape.rowsPerColumn, header)
  if key ~= lastLayoutKey then
    lastLayoutKey = key
    if left then
      left:removeAnchor(AnchorRight)
      left:addAnchor(AnchorRight, 'parent', shape.twoColumns and AnchorHorizontalCenter or AnchorRight)
      left:setMarginRight(shape.twoColumns and 3 or 0)
      left:setHeight(shape.cardHeight)
    end
    if right then
      right:setVisible(shape.twoColumns)
      right:setHeight(shape.cardHeight)
    end
    widget:setSize({ width = shape.width, height = header + shape.cardHeight })
  end
  widget:setVisible(true)
end

-- Tools > Bot HUD changed (the helper saved the config first)
function M.applyBotHudConfig(config)
  if type(config) == 'table' and config.enabled == true then
    lastLayoutKey = nil
    M.refreshBotHud()
  else
    destroy()
  end
end

function M.init()
  g_ui.importStyle('helperhud')
  connect(g_game, { onGameEnd = destroy })
end

function M.terminate()
  disconnect(g_game, { onGameEnd = destroy })
  destroy()
end
