-- Spellbook window: every spell of the server with its data and area of effect.
-- Server: server/data/scripts/chaos/spellbook.lua, extended opcode 219 (JSON {action, data}).
--   server -> client  open {vocation, level, magicLevel, total, chunks, vocationNames}
--                     spells {index, spells = [...]}  (several messages)
--                     done {total}
--   client -> server  open                             (menu / toggle; the server answers as for !spells)
-- Spell fields: name, words, level, maglevel, mana, manaPercent, soul, cooldown, groupCooldown, group, type,
-- element, target (single/area/self/front), center (caster/target), area (matrix: 1 hit, 2 centre, 3 centre + hit,
-- "front" spells face north), range, description, scaling, vocations (ids), premium, rune, runeClientId.

local OPCODE = 219

local ELEMENT_COLORS = {
  fire = '#e8582a', ice = '#7fd3f0', energy = '#b070ff', earth = '#5fbf3a', holy = '#f6e27a',
  death = '#8a3b9e', physical = '#b0a090', healing = '#4fd07f', lifedrain = '#c0304a', manadrain = '#3f6fd0',
  drown = '#3a8fc0', arcane = '#d070e0'
}
local DEFAULT_HIT = '#b8160f'
local CASTER_COLOR = '#f6cf72'
local EMPTY_COLOR = '#1a1416'
local MAX_CELL, MIN_CELL = 14, 5

local TYPE_TEXT = { damage = 'Damage', heal = 'Healing', buff = 'Support', summon = 'Summon', conjure = 'Conjure', utility = 'Utility' }
local TARGET_TEXT = { single = 'Single target', area = 'Area', self = 'Self', front = 'Area in front' }

local window
local rows = {}         -- row widgets, same order as spells
local spells = {}       -- received spell list
local pending           -- list being received
local meta = {}         -- open header: vocation, level, magicLevel, vocationNames
local vocationNames = {}
local selected
local FILTERS = { 'My vocation', 'All spells' }

-- ---------------------------------------------------------------- helpers
local function sendOpen()
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = 'open', data = {} }))
  end
end

local function list(value)
  local out = {}
  if type(value) == 'table' then
    for _, v in pairs(value) do out[#out + 1] = v end
  end
  return out
end

local function elementColor(element)
  return ELEMENT_COLORS[element or ''] or DEFAULT_HIT
end

local function capitalize(s)
  s = tostring(s or '')
  return (s:gsub('^%l', string.upper))
end

local function formatSeconds(ms)
  ms = tonumber(ms) or 0
  if ms <= 0 then return '-' end
  local s = ms / 1000
  if s == math.floor(s) then return string.format('%ds', s) end
  return string.format('%.1fs', s)
end

-- "Master Sorcerer" -> "MS"; a one-word class name keeps three letters ("Berserker" -> "Ber", "Beastmaster" -> "Bea"),
-- so the classes of the class rework stay apart
local function initials(name)
  local words = {}
  for word in tostring(name):gmatch('%a+') do words[#words + 1] = word end
  if #words == 1 then
    return words[1]:sub(1, 1):upper() .. words[1]:sub(2, 3):lower()
  end
  local out = ''
  for _, word in ipairs(words) do out = out .. word:sub(1, 1):upper() end
  return out
end

local function vocationText(spell)
  local ids = list(spell.vocations)
  if #ids == 0 then return 'Everyone', nil end
  table.sort(ids)
  local short, full = {}, {}
  for _, id in ipairs(ids) do
    local name = vocationNames[tonumber(id)] or ('#' .. tostring(id))
    short[#short + 1] = initials(name)
    full[#full + 1] = name
  end
  return table.concat(short, ', '), table.concat(full, ', ')
end

local function canUse(spell)
  local ids = list(spell.vocations)
  if #ids == 0 then return true end
  for _, id in ipairs(ids) do
    if tonumber(id) == tonumber(meta.vocation) then return true end
  end
  return false
end

local function setIcon(iconWidget, itemWidget, spell)
  iconWidget:setImageSource('')
  iconWidget:setVisible(true)
  itemWidget:setVisible(false)
  if spell.words and spell.words ~= '' and Spells and Spells.getSpellIcon then
    local ok, folder, clip = pcall(Spells.getSpellIcon, spell.words)
    if ok and folder then
      iconWidget:setImageSource(folder)
      iconWidget:setImageClip(clip)
      return
    end
  end
  if tonumber(spell.runeClientId) then
    iconWidget:setVisible(false)
    itemWidget:setItemId(tonumber(spell.runeClientId))
    itemWidget:setVisible(true)
  end
end

-- ---------------------------------------------------------------- area grid
-- returns a matrix of roles: 'hit', 'caster', 'target', 'targetHit', 'empty'
local function areaRoles(spell)
  local area = spell.area
  if type(area) == 'table' and #list(area) > 0 and (spell.target == 'area' or spell.target == 'front') then
    local roles = {}
    for r, row in ipairs(area) do
      roles[r] = {}
      for c, v in ipairs(list(row)) do
        v = tonumber(v) or 0
        local role = 'empty'
        if v == 1 then
          role = 'hit'
        elseif v == 2 or v == 3 then
          if spell.center == 'target' then
            role = (v == 3) and 'targetHit' or 'target'
          else
            role = 'caster'
          end
        end
        roles[r][c] = role
      end
    end
    return roles
  end
  if spell.target == 'single' then
    return { { 'targetHit' }, { 'empty' }, { 'caster' } }
  end
  return { { 'caster' } }
end

local function areaNote(spell)
  if spell.target == 'front' then return tr('Cast facing north (up).') end
  if spell.target == 'area' and spell.center == 'target' then return tr('Centred on the target.') end
  if spell.target == 'area' then return tr('Centred on you.') end
  if spell.target == 'single' then
    local range = tonumber(spell.range)
    return range and range > 0 and tr('One target, range %d.', range) or tr('One target.')
  end
  return tr('Affects only you.')
end

local function drawArea(spell)
  local box = window.details.areaBox
  local grid = box.areaGrid
  grid:destroyChildren()
  local roles = areaRoles(spell)
  local nrows, ncols = #roles, 0
  for _, row in ipairs(roles) do ncols = math.max(ncols, #row) end
  local cell = math.floor(math.min((box:getWidth() - 8) / math.max(ncols, 1), (box:getHeight() - 8) / math.max(nrows, 1)))
  cell = math.max(MIN_CELL, math.min(MAX_CELL, cell))
  grid:setSize({ width = cell * ncols, height = cell * nrows })

  local hit = elementColor(spell.element)
  for r, row in ipairs(roles) do
    for c, role in ipairs(row) do
      local w = g_ui.createWidget('SpellbookCell', grid)
      w:setSize({ width = cell - 1, height = cell - 1 })
      w:addAnchor(AnchorTop, 'parent', AnchorTop)
      w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      w:setMarginTop((r - 1) * cell)
      w:setMarginLeft((c - 1) * cell)
      if role == 'hit' then
        w:setBackgroundColor(hit)
        w:setBorderColor('#0d0b0e')
      elseif role == 'caster' then
        w:setBackgroundColor(CASTER_COLOR)
        w:setBorderColor('#0d0b0e')
      elseif role == 'targetHit' or role == 'target' then
        w:setBackgroundColor(role == 'targetHit' and hit or EMPTY_COLOR)
        w:setBorderWidth(cell >= 9 and 2 or 1)
        w:setBorderColor('#ffffff')
      else
        w:setBackgroundColor(EMPTY_COLOR)
      end
    end
  end

  local legend = window.details.legend
  legend.legendHit:setBackgroundColor(hit)
  window.details.areaNote:setText(areaNote(spell))
end

-- ---------------------------------------------------------------- details
local function addStat(key, value, tooltip)
  if value == nil or value == '' then return end
  local row = g_ui.createWidget('SpellbookStat', window.details.stats)
  row.key:setText(key)
  if type(value) == 'number' then
    -- numbers are shown short (15.3k), exact in the tooltip
    if not tooltip and (value >= 1000 or value <= -1000) then tooltip = comma_value(value) end
    value = formatShortNumber(value)
  end
  row.value:setText(tostring(value))
  if tooltip then row.value:setTooltip(tooltip) end
  return row
end

local function showDetails(spell)
  selected = spell
  local d = window.details
  local has = spell ~= nil
  for _, id in ipairs({ 'icon', 'name', 'words', 'headerSeparator', 'stats', 'areaTitle', 'areaBox', 'legend', 'areaNote', 'descSeparator', 'description' }) do
    d[id]:setVisible(has)
  end
  d.item:setVisible(false)
  d.emptyText:setVisible(not has)
  if not has then return end

  setIcon(d.icon, d.item, spell)
  d.name:setText(spell.name or '?')
  if spell.words and spell.words ~= '' then
    d.words:setText(spell.words)
  elseif spell.rune then
    d.words:setText(tr('Rune'))
  else
    d.words:setText('')
  end

  d.stats:destroyChildren()
  local level = tonumber(spell.level) or 0
  local levelRow = addStat(tr('Level'), level)
  if levelRow and meta.level and level > meta.level then levelRow.value:setColor('#e03a1e') end
  local ml = tonumber(spell.maglevel) or 0
  if ml > 0 then
    local mlRow = addStat(tr('Magic level'), ml)
    if mlRow and meta.magicLevel and ml > meta.magicLevel then mlRow.value:setColor('#e03a1e') end
  end
  local mana = tonumber(spell.mana) or 0
  if tonumber(spell.manaPercent) then
    addStat(tr('Mana'), spell.manaPercent .. '%')
  else
    addStat(tr('Mana'), mana > 0 and mana or '-')
  end
  if (tonumber(spell.soul) or 0) > 0 then addStat(tr('Soul'), tonumber(spell.soul)) end
  addStat(tr('Cooldown'), formatSeconds(spell.cooldown),
    spell.groupCooldown and tr('Group cooldown: %s', formatSeconds(spell.groupCooldown)) or nil)
  addStat(tr('Group'), capitalize(spell.group or '-'))
  addStat(tr('Type'), TYPE_TEXT[spell.type] or capitalize(spell.type or '-'))
  local elementRow = addStat(tr('Element'), spell.element and capitalize(spell.element) or '-')
  if elementRow and spell.element then elementRow.value:setColor(elementColor(spell.element)) end
  addStat(tr('Target'), TARGET_TEXT[spell.target] or '-')
  if spell.scaling then
    -- the column is narrow: short form here, the full text in the tooltip
    local short = spell.scaling:gsub('distance skill x weapon attack', 'dist. x weapon'):gsub('skill x weapon attack', 'skill x weapon')
    addStat(tr('Scales'), short, 'Scales with ' .. spell.scaling)
  end
  local short, full = vocationText(spell)
  addStat(tr('Vocations'), short, full)
  if spell.premium then addStat(tr('Premium'), tr('Yes')) end

  local text = spell.description or ''
  -- the spell's support runes (game_spellsupports), when that module knows the spell: a short line here, the effects
  -- in the tooltip; that module also shortens a description too long for its box (full text in the tooltip)
  local sup = modules.game_spellsupports
  local ok, line, effects = pcall(function()
    if sup and sup.spellbookLine then return sup.spellbookLine(spell.words) end
  end)
  local tip
  if ok and line then
    text = text .. '\n\n' .. line
    if effects then tip = (spell.description or '') .. '\n\n' .. effects end
  end
  if sup and sup.fitText then
    sup.fitText(d.description, text, tip)
  else
    d.description:setText(text)
    d.description:setTooltip(tip)
  end
  drawArea(spell)
end

-- ---------------------------------------------------------------- list
local function matches(spell, text, filter)
  if filter == 1 and not canUse(spell) then return false end
  if text ~= '' then
    local name = (spell.name or ''):lower()
    local words = (spell.words or ''):lower()
    if not name:find(text, 1, true) and not words:find(text, 1, true) then return false end
  end
  return true
end

local function currentFilter()
  local combo = window.filterCombo
  local option = combo:getCurrentOption()
  local data = option and tonumber(option.data)
  return data or 1
end

local function applyFilter()
  if not window then return end
  local text = window.searchEdit:getText():lower():gsub('^%s+', ''):gsub('%s+$', '')
  local filter = currentFilter()
  local shown, firstShown = 0, nil
  local selectedVisible = false
  for i, row in ipairs(rows) do
    local visible = matches(spells[i], text, filter)
    row:setVisible(visible)
    if visible then
      shown = shown + 1
      firstShown = firstShown or row
      if spells[i] == selected then selectedVisible = true end
    end
  end
  window.countLabel:setText(tr('%d spells', shown))
  if not selectedVisible then
    if firstShown then
      window.spellList:focusChild(firstShown, KeyboardFocusReason)
    else
      showDetails(nil)
    end
  end
end

local function buildList()
  window.spellList:destroyChildren()
  rows = {}
  for i, spell in ipairs(spells) do
    local row = g_ui.createWidget('SpellbookRow', window.spellList)
    row.spellIndex = i
    setIcon(row.icon, row.item, spell)
    row.name:setText(spell.name or '?')
    row.words:setText((spell.words and spell.words ~= '') and spell.words or (spell.rune and tr('Rune') or ''))
    row.level:setText(tr('Lv %s', formatShortNumber(tonumber(spell.level) or 0)))
    if meta.level and (tonumber(spell.level) or 0) > meta.level then row.level:setColor('#e03a1e') end
    if spell.element then row.name:setColor(elementColor(spell.element)) end
    rows[i] = row
  end
  selected = nil
  applyFilter()
end

local function onListFocus(_, focused)
  if focused and focused.spellIndex then
    showDetails(spells[focused.spellIndex])
  end
end

local function sortSpells(list)
  table.sort(list, function(a, b)
    local la, lb = tonumber(a.level) or 0, tonumber(b.level) or 0
    if la ~= lb then return la < lb end
    if (a.name or '') ~= (b.name or '') then return (a.name or '') < (b.name or '') end
    return (a.words or '') < (b.words or '')
  end)
end

-- ---------------------------------------------------------------- protocol
local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[spellbook] invalid JSON: ' .. tostring(msg))
    return
  end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'open' then
    meta = {
      vocation = tonumber(data.vocation) or 0,
      level = tonumber(data.level),
      magicLevel = tonumber(data.magicLevel)
    }
    vocationNames = {}
    for _, v in pairs(type(data.vocationNames) == 'table' and data.vocationNames or {}) do
      if type(v) == 'table' and tonumber(v.id) then vocationNames[tonumber(v.id)] = tostring(v.name) end
    end
    pending = {}
  elseif msg.action == 'spells' then
    pending = pending or {}
    for _, spell in ipairs(list(data.spells)) do
      if type(spell) == 'table' then pending[#pending + 1] = spell end
    end
  elseif msg.action == 'done' then
    spells = pending or {}
    pending = nil
    sortSpells(spells)
    buildList()
    show()
  end
end

-- ---------------------------------------------------------------- window
function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  window.searchEdit:focus()
end

function hide()
  if window then window:hide() end
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
    return
  end
  if #spells > 0 then show() end
  sendOpen() -- refresh (the server answers with open/spells/done)
end

local function onGameEnd()
  hide()
  spells, rows, pending, selected, meta = {}, {}, nil, nil, {}
  if window then window.spellList:destroyChildren() end
end

function init()
  window = g_ui.displayUI('spellbook')
  window:hide()
  for i, text in ipairs(FILTERS) do
    window.filterCombo:addOption(tr(text), i)
  end
  window.filterCombo.onOptionChange = function() applyFilter() end
  window.searchEdit.onTextChange = function() applyFilter() end
  window.spellList.onChildFocusChange = onListFocus
  showDetails(nil)
  window.countLabel:setText('')

  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if window then
    window:destroy()
    window = nil
  end
  rows, spells, pending, selected = {}, {}, nil, nil
end
