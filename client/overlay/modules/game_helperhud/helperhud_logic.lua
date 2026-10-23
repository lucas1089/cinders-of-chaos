-- Pure part of the helper's bot HUD (client/MANIFEST.md "Helper bot HUD"; tested by helperhud_test.lua).
-- The base client drew this HUD from the helper's cavebot file, which this client leaves out
-- (tools/assemble_client.sh), so Tools > Bot HUD > "Show Bot HUD" did nothing. game_helperhud draws it again.
-- No engine calls here: the runtime file (helperhud.lua) gathers the state and hands it in.
ChaosBotHudLogic = {}
local L = ChaosBotHudLogic

L.MAX_ROWS = 8
L.ROW_HEIGHT = 15
L.ROW_SPACING = 1
-- left of the value text: icon 13 + its margin 6 + name column 58 + the value's margin 4
L.ROW_LABEL_INSET = 13 + 6 + 58 + 4
-- the row container's margins inside a card, plus 2 px so trimmed text stops short of the border
L.CARD_INSET = 6 + 6 + 2
L.SIZES = {
  Compact = { width = 300, columns = 1 },
  Normal = { width = 520, columns = 2 },
  Wide = { width = 680, columns = 2 }
}

-- the HUD is on only when the player ticked "Show Bot HUD" (helper config botHud.enabled, saved per character)
function L.isEnabled(helperConfig)
  local hud = type(helperConfig) == 'table' and helperConfig.botHud or nil
  return type(hud) == 'table' and hud.enabled == true
end

local function shorten(text, limit)
  text = tostring(text or '')
  if #text <= limit then return text end
  return text:sub(1, limit) .. '..'
end
L.shorten = shorten

local function percent(value, max)
  value, max = tonumber(value) or 0, tonumber(max) or 0
  if max <= 0 then return 0 end
  return math.floor(value * 100 / max)
end

-- rows {icon, name, value, active} for the ticked sections. state:
--   targetName, spellName(id) -> name or nil, player = {health, maxHealth, mana, maxMana, level} or nil
-- tr: the translation function (the identity in tests)
function L.entries(helperConfig, state, tr)
  tr = tr or function(s, ...) return select('#', ...) > 0 and string.format(s, ...) or s end
  local cfg = type(helperConfig) == 'table' and helperConfig or {}
  local hud = type(cfg.botHud) == 'table' and cfg.botHud or {}
  state = state or {}
  local rows = {}
  local function add(show, active, icon, name, value)
    if show ~= true then return end
    rows[#rows + 1] = { icon = icon, name = name, value = value, active = active == true }
  end
  local off = tr('Off')

  local combatActive = (cfg.autoTargetEnabled or cfg.magicShooterEnabled) == true
  local parts = {}
  if cfg.autoTargetEnabled then parts[#parts + 1] = tr('Auto') end
  if cfg.magicShooterEnabled then parts[#parts + 1] = tr('Shooter') end
  if state.targetName then parts[#parts + 1] = shorten(state.targetName, 14) end
  add(hud.showTargeting, combatActive, 'shooter', tr('Combat'), combatActive and table.concat(parts, '  ') or off)

  -- healing: the heal spells and potions that are set
  local heals, potions = 0, 0
  for _, r in ipairs(type(cfg.spells) == 'table' and cfg.spells or {}) do
    if (tonumber(r.id) or 0) > 0 then heals = heals + 1 end
  end
  for _, r in ipairs(type(cfg.potions) == 'table' and cfg.potions or {}) do
    if (tonumber(r.id) or 0) > 0 then potions = potions + 1 end
  end
  local healing = {}
  if heals > 0 then healing[#healing + 1] = tr('%d spells', heals) end
  if potions > 0 then healing[#healing + 1] = tr('%d potions', potions) end
  add(hud.showHealing, #healing > 0, 'healing', tr('Healing'), #healing > 0 and table.concat(healing, '  ') or off)

  local haste = type(cfg.haste) == 'table' and cfg.haste[1] or {}
  local training = type(cfg.training) == 'table' and cfg.training[1] or {}
  local support = {}
  if haste.enabled then
    local name = state.spellName and state.spellName(haste.id) or nil
    support[#support + 1] = tr('Haste %s', name and shorten(name, 12) or tr('none'))
  end
  if training.enabled then support[#support + 1] = tr('Train %d%%', tonumber(training.percent) or 0) end
  add(hud.showHaste, (haste.enabled or training.enabled) == true, 'healing', tr('Support'),
    #support > 0 and table.concat(support, '  ') or off)

  local p = state.player
  if p then
    add(hud.showPlayer, true, 'healing', tr('Player'), tr('HP %d%%  MP %d%%  Lv %d',
      percent(p.health, p.maxHealth), percent(p.mana, p.maxMana), tonumber(p.level) or 0))
  end

  if #rows == 0 then
    rows[1] = { icon = 'tools', name = tr('Bot HUD'), value = tr('Pick sections in Tools > Bot HUD'), active = false }
  end
  return rows
end

-- how many rows are on (the status line counts the active ones)
function L.activeCount(rows)
  local n = 0
  for _, row in ipairs(rows or {}) do
    if row.active then n = n + 1 end
  end
  return n
end

-- the shape for `count` rows at size `sizeName`: one column up to four rows (and always for Compact), else two
function L.layout(sizeName, count)
  local size = L.SIZES[sizeName or 'Normal'] or L.SIZES.Normal
  count = math.max(1, tonumber(count) or 1)
  local twoColumns = size.columns > 1 and count > 4
  local perColumn = math.min(L.MAX_ROWS, twoColumns and math.ceil(count / 2) or count)
  local cardWidth = twoColumns and math.floor((size.width - 6) / 2) or size.width
  return {
    width = size.width,
    twoColumns = twoColumns,
    rowsPerColumn = perColumn,
    cardWidth = cardWidth,
    valueWidth = cardWidth - L.CARD_INSET - L.ROW_LABEL_INSET,
    cardHeight = 8 + perColumn * L.ROW_HEIGHT + math.max(0, perColumn - 1) * L.ROW_SPACING
  }
end

-- the HUD's top margin inside the map panel: 12 px below the visible top of the map, and below the menu bar when
-- the bar sits over the top of the map (the bar lives on the game root panel, the HUD on the map panel; in the
-- extended view the map panel starts above the window). mapY / visibleTop: screen y; bar: the bar's rect or nil
L.HUD_GAP = 12
L.BAR_GAP = 6
function L.topMargin(mapY, visibleTop, bar)
  local top = math.max(mapY, visibleTop or mapY)
  local y = top + L.HUD_GAP
  if bar and bar.height > 0 and bar.y < top + 60 and bar.y + bar.height > top then
    y = math.max(y, bar.y + bar.height + L.BAR_GAP)
  end
  return y - mapY
end

return ChaosBotHudLogic
