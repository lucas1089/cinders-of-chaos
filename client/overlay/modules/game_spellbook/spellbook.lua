-- Spellbook window: every spell of the server with its data and area of effect.
-- Server: server/data/scripts/chaos/spellbook.lua, extended opcode 219 (JSON {action, data}).
--   server -> client  open {vocation, level, magicLevel, total, chunks, sig, unchanged, learned, vocationNames}
--                     spells {index, spells = [...]}  (several messages; none when unchanged)
--                     done {total, sig}
--                     show {}  (a spellbook item was used: open the window)
--   client -> server  open {have = sig of the cached list, prefetch}   (menu / toggle; prefetch: once after login)
-- Spell fields: name, words, level, maglevel, mana, manaPercent, soul, cooldown, groupCooldown, group, type,
-- element, target (single/area/self/front), center (caster/target), area (matrix: 1 hit, 2 centre, 3 centre + hit,
-- "front" spells face north), range, description, scaling, vocations (ids), premium, rune, runeClientId, id, needLearn.
-- premium is not shown: every spell is free (server/README.md "Free spells").
--
-- Speed: the window shows at once with the cached list. The rows are built once per list (the server's sig); a reopen
-- only refreshes the state that changes (learned, level, cooldown) and asks the server whether the list is still the
-- same (a two-message answer when it is). The list is fetched a few seconds after login, so the first Alt+S is instant.
-- Filter and order: spellbook_core.lua (ChaosSpellCore, shared with the spell pickers).

local Core = ChaosSpellCore -- spellbook_core.lua, loaded first (game_spellbook.otmod)

local OPCODE = 219
local PREFETCH_DELAY = 3000 -- ms after login
local COOLDOWN_TICK = 500   -- ms between cooldown label updates while the window is open

local ELEMENT_COLORS = {
  fire = '#e8582a', ice = '#7fd3f0', energy = '#b070ff', earth = '#5fbf3a', holy = '#f6e27a',
  death = '#8a3b9e', physical = '#b0a090', healing = '#4fd07f', lifedrain = '#c0304a', manadrain = '#3f6fd0',
  drown = '#3a8fc0', arcane = '#d070e0'
}
local DEFAULT_HIT = '#b8160f'
local CASTER_COLOR = '#f6cf72'
local EMPTY_COLOR = '#1a1416'
local MAX_CELL, MIN_CELL = 14, 5
local MAX_SINGLE_RANGE = 5 -- single-target preview: the target at most this many tiles away

local STATE_COLORS = { ready = '#8c8070', level = '#e03a1e', learn = '#e8902a', vocation = '#5a5048', cooldown = '#7fd3f0' }

local TYPE_TEXT = { damage = 'Damage', heal = 'Healing', buff = 'Support', summon = 'Summon', conjure = 'Conjure', utility = 'Utility' }
local TARGET_TEXT = { single = 'Single target', area = 'Area', self = 'Self', front = 'Area in front' }

local window
local rows = {}         -- row widgets, same order as spells
local spells = {}       -- received spell list (kept across logins; the sig check says when it is stale)
local spellsSig         -- server signature of `spells`
local builtSig          -- signature the rows were built for
local pending           -- list being received
local meta = {}         -- open header: vocation, level, magicLevel
local vocationNames = {}
local selected
local request           -- 'user' / 'prefetch' while an answer is expected; nil: the server opened it (/spells)
local prefetchEvent, cooldownEvent
local cooldownEnds = {} -- spell id -> g_clock.millis() when its cooldown ends
local iconCache = {}    -- words -> {folder, clip} / false (no sheet icon)
local paintedMap        -- words -> painted icon file / false, built once
local areaCells = {}    -- pooled cells of the area grid

-- ---------------------------------------------------------------- helpers
-- prefetch: the background fetch after login (the server does not count it as the player opening the window)
local function sendOpen(prefetch)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = 'open', data = { have = spellsSig, prefetch = prefetch or nil } }))
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

-- the character as the filter sees it: the server's vocation id, the live level and magic level
local function context()
  local ctx = { vocation = meta.vocation, level = meta.level, magicLevel = meta.magicLevel, learned = Core.learnedNames }
  local player = g_game.getLocalPlayer()
  if player then
    local ok, level = pcall(function() return player:getLevel() end)
    if ok and tonumber(level) and level > 0 then ctx.level = level end
    local okm, ml = pcall(function() return player:getMagicLevel() end)
    if okm and tonumber(ml) then ctx.magicLevel = ml end
  end
  return ctx
end

-- client setting "Painted icons" (g_settings 'chaosPaintedIcons', the Buff Bar settings; off by default): a Chaos
-- spell's painted 32 px icon (client/tools/gen_painted_icons.py), found by its words in game_chaosspells' spell data;
-- nil when the setting is off or the spell has none (then the spell sheet's icon as before). The words -> file map is
-- built once (it used to scan the spell data and touch the disk for every row of every open).
local function paintedSpellIcon(words)
  local ok, on = pcall(g_settings.getBoolean, 'chaosPaintedIcons')
  if not (ok and on == true) then return nil end
  if not paintedMap then
    paintedMap = {}
    local cs = modules.game_chaosspells
    local data = cs and cs.ChaosSpellData
    for _, s in ipairs(type(data) == 'table' and data or {}) do
      if s.words and s.clientId then
        local file = '/images/game/spells_painted/' .. s.clientId
        local okf, there = pcall(g_resources.fileExists, file .. '.png')
        paintedMap[s.words] = (okf and there == true) and file or false
      end
    end
  end
  return paintedMap[words] or nil
end

local function sheetIcon(words)
  local hit = iconCache[words]
  if hit == nil then
    hit = false
    if Spells and Spells.getSpellIcon then
      local ok, folder, clip = pcall(Spells.getSpellIcon, words)
      if ok and folder then hit = { folder, clip } end
    end
    iconCache[words] = hit
  end
  return hit or nil
end

local function setIcon(iconWidget, itemWidget, spell)
  iconWidget:setImageSource('')
  iconWidget:setVisible(true)
  itemWidget:setVisible(false)
  local painted = spell.words and paintedSpellIcon(spell.words)
  if painted then
    iconWidget:setImageSource(painted)
    iconWidget:setImageClip('0 0 32 32')
    return
  end
  if spell.words and spell.words ~= '' then
    local icon = sheetIcon(spell.words)
    if icon then
      iconWidget:setImageSource(icon[1])
      iconWidget:setImageClip(icon[2])
      return
    end
  end
  if tonumber(spell.runeClientId) then
    iconWidget:setVisible(false)
    itemWidget:setItemId(tonumber(spell.runeClientId))
    itemWidget:setVisible(true)
  end
end

-- a label's text cut with "..." to its width (the full text goes in the row's tooltip)
local function fitLabel(label, text)
  label:setText(text)
  local width = label:getWidth()
  if width <= 10 or label:getTextSize().width <= width then return end
  local cut = #text
  while cut > 1 do
    cut = cut - 1
    label:setText(text:sub(1, cut):gsub('%s+$', '') .. '...')
    if label:getTextSize().width <= width then return end
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
    -- the target (hit, white frame) at the spell's range, you below it
    local range = math.max(1, math.min(MAX_SINGLE_RANGE, tonumber(spell.range) or 1))
    local roles = { { 'targetHit' } }
    for _ = 2, range do roles[#roles + 1] = { 'empty' } end
    roles[#roles + 1] = { 'caster' }
    return roles
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
  local roles = areaRoles(spell)
  local nrows, ncols = #roles, 0
  for _, row in ipairs(roles) do ncols = math.max(ncols, #row) end
  local cell = math.floor(math.min((box:getWidth() - 8) / math.max(ncols, 1), (box:getHeight() - 8) / math.max(nrows, 1)))
  cell = math.max(MIN_CELL, math.min(MAX_CELL, cell))
  grid:setSize({ width = cell * ncols, height = cell * nrows })

  local hit = elementColor(spell.element)
  local used, hasTargetHit = 0, false
  for r, row in ipairs(roles) do
    for c, role in ipairs(row) do
      used = used + 1
      local w = areaCells[used]
      if not w then
        w = g_ui.createWidget('SpellbookCell', grid)
        w:addAnchor(AnchorTop, 'parent', AnchorTop)
        w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        areaCells[used] = w
      end
      w:setVisible(true)
      w:setSize({ width = cell - 1, height = cell - 1 })
      w:setMarginTop((r - 1) * cell)
      w:setMarginLeft((c - 1) * cell)
      w:setBorderWidth(1)
      w:setBorderColor('#2a2226')
      if role == 'hit' then
        w:setBackgroundColor(hit)
        w:setBorderColor('#0d0b0e')
      elseif role == 'caster' then
        w:setBackgroundColor(CASTER_COLOR)
        w:setBorderColor('#0d0b0e')
      elseif role == 'targetHit' or role == 'target' then
        hasTargetHit = hasTargetHit or role == 'targetHit'
        w:setBackgroundColor(role == 'targetHit' and hit or EMPTY_COLOR)
        w:setBorderWidth(cell >= 9 and 2 or 1)
        w:setBorderColor('#ffffff')
      else
        w:setBackgroundColor(EMPTY_COLOR)
      end
    end
  end
  for i = used + 1, #areaCells do areaCells[i]:setVisible(false) end

  local legend = window.details.legend
  legend.legendHit:setBackgroundColor(hit)
  -- the legend's target square looks like the one drawn: filled with the hit colour when the target is hit
  legend.legendTarget:setBackgroundColor(hasTargetHit and hit or EMPTY_COLOR)
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

  local ctx = context()
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
  if levelRow and ctx.level and level > ctx.level then levelRow.value:setColor('#e03a1e') end
  local ml = tonumber(spell.maglevel) or 0
  if ml > 0 then
    local mlRow = addStat(tr('Magic level'), ml)
    if mlRow and ctx.magicLevel and ml > ctx.magicLevel then mlRow.value:setColor('#e03a1e') end
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
    addStat(tr('Scales'), short, tr('Scales with %s', spell.scaling))
  end
  local short, full = vocationText(spell)
  addStat(tr('Vocations'), short, full)
  if spell.needLearn then
    local learned = Core.status(spell, { learned = Core.learnedNames }) ~= 'learn'
    local learnRow = addStat(tr('Learned spell'), learned and tr('Yes') or tr('No'))
    if learnRow and not learned then learnRow.value:setColor(STATE_COLORS.learn) end
  end

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
local function currentFilter()
  local option = window.filterCombo:getCurrentOption()
  return Core.normalizeFilter(option and option.data)
end

local function stateTip(status)
  if status == 'level' then return tr('Your level or magic level is too low.') end
  if status == 'learn' then return tr('Not learned yet.') end
  if status == 'vocation' then return tr('Not a spell of your vocation.') end
  return tr('You can cast it.')
end

-- the right-hand label of a row: level, "Learn", or the cooldown left
local function updateRowState(row, spell, ctx, now)
  local status = Core.status(spell, ctx)
  row.status = status
  local left = status == 'ready' and spell.id and Core.cooldownLeft(cooldownEnds[tonumber(spell.id)], now)
  if left then
    row.level:setText(tr('%ds', left))
    row.level:setColor(STATE_COLORS.cooldown)
  elseif status == 'learn' then
    row.level:setText(tr('Learn'))
    row.level:setColor(STATE_COLORS.learn)
  else
    row.level:setText(tr('Lv %s', formatShortNumber(tonumber(spell.level) or 0)))
    row.level:setColor(STATE_COLORS[status] or STATE_COLORS.ready)
  end
  row:setTooltip((spell.name or '?') .. '\n' .. stateTip(status))
  return left ~= nil and left ~= false
end

local function applyFilter()
  if not window then return end
  local text = window.searchEdit:getText()
  local filter = currentFilter()
  local ctx = context()
  local shown, firstShown = 0, nil
  local selectedVisible = false
  for i, row in ipairs(rows) do
    local visible = Core.matches(spells[i], ctx, filter, text)
    row:setVisible(visible)
    if visible then
      shown = shown + 1
      firstShown = firstShown or row
      if spells[i] == selected then selectedVisible = true end
    end
  end
  if #spells == 0 then
    window.countLabel:setText(tr('Loading spells...'))
  elseif filter == 'runes' then
    window.countLabel:setText(tr('%d runes', shown))
  else
    window.countLabel:setText(tr('%d spells', shown)) -- spells only: runes are under their own filter
  end
  if not selectedVisible then
    if firstShown then
      window.spellList:focusChild(firstShown, KeyboardFocusReason)
    else
      showDetails(nil)
    end
  end
end

-- learned / level / cooldown of every row, then the filter (a reopen does only this)
local function refreshState()
  if not window then return end
  local ctx, now = context(), g_clock.millis()
  for i, row in ipairs(rows) do updateRowState(row, spells[i], ctx, now) end
  applyFilter()
end

local buildGen, fittedGen = 0, 0 -- a list build / the build whose names were fitted
local function fitNames()
  if not (window and window:isVisible()) or fittedGen == buildGen then return end
  fittedGen = buildGen
  for i, row in ipairs(rows) do
    if row.name then fitLabel(row.name, spells[i].name or '?') end
  end
end

-- the rows, once per list (signature); a pooled row keeps its widget
local function buildList()
  local listWidget = window.spellList
  local layout = listWidget:getLayout()
  if layout then layout:disableUpdates() end
  for i, spell in ipairs(spells) do
    local row = rows[i]
    if not row then
      row = g_ui.createWidget('SpellbookRow', listWidget)
      rows[i] = row
    end
    row.spellIndex = i
    row:setVisible(true)
    setIcon(row.icon, row.item, spell)
    row.name:setText(spell.name or '?')
    row.name:setColor(spell.element and elementColor(spell.element) or '#d6c9ae')
    row.words:setText((spell.words and spell.words ~= '') and spell.words or (spell.rune and tr('Rune') or ''))
  end
  for i = #rows, #spells + 1, -1 do
    rows[i]:destroy()
    rows[i] = nil
  end
  if layout then
    layout:enableUpdates()
    layout:update()
  end
  builtSig = spellsSig
  buildGen = buildGen + 1
  selected = nil
  refreshState()
  addEvent(fitNames) -- after the layout pass: the labels have their width then
end

-- Up / Down (also while typing in the search box): the previous / next shown row becomes the selection
local function moveSelection(step)
  local shown, at = {}, nil
  local current = window.spellList:getFocusedChild()
  for _, row in ipairs(rows) do
    if row:isVisible() then
      shown[#shown + 1] = row
      if row == current then at = #shown end
    end
  end
  if #shown == 0 then return false end
  local index = at and math.max(1, math.min(#shown, at + step)) or 1
  window.spellList:focusChild(shown[index], KeyboardFocusReason)
  window.spellList:ensureChildVisible(shown[index])
  return true
end

local function onKeyPress(_, keyCode)
  if keyCode == KeyUp then return moveSelection(-1) end
  if keyCode == KeyDown then return moveSelection(1) end
  return false
end

local function onListFocus(_, focused)
  if focused and focused.spellIndex then
    showDetails(spells[focused.spellIndex])
  end
end

-- ---------------------------------------------------------------- cooldowns
local function stopCooldownTick()
  if cooldownEvent then
    removeEvent(cooldownEvent)
    cooldownEvent = nil
  end
end

local function cooldownTick()
  cooldownEvent = nil
  if not (window and window:isVisible()) then return end
  local ctx, now, any = context(), g_clock.millis(), false
  for i, row in ipairs(rows) do
    local id = tonumber(spells[i].id)
    if id and cooldownEnds[id] then
      if updateRowState(row, spells[i], ctx, now) then
        any = true
      else
        cooldownEnds[id] = nil -- over: the row shows its level again
      end
    end
  end
  if any then cooldownEvent = scheduleEvent(cooldownTick, COOLDOWN_TICK) end
end

local function onSpellCooldown(spellId, delay)
  spellId, delay = tonumber(spellId), tonumber(delay)
  if not spellId or not delay or delay <= 0 then return end
  cooldownEnds[spellId] = g_clock.millis() + delay
  if window and window:isVisible() and not cooldownEvent then cooldownTick() end
end

local function onLevelChange()
  if window and window:isVisible() then refreshState() end
end

-- ---------------------------------------------------------------- protocol
local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[spellbook] invalid JSON: ' .. tostring(msg))
    return
  end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'show' then
    -- a spellbook item was used (server: ChaosSpellbook.openWindow): open the window as Alt+S does
    if window and not window:isVisible() then toggle() end
    return
  end
  if msg.action == 'open' then
    meta = {
      vocation = tonumber(data.vocation) or 0,
      level = tonumber(data.level),
      magicLevel = tonumber(data.magicLevel)
    }
    Core.setLearned(data.learned)
    if type(data.vocationNames) == 'table' then
      vocationNames = {}
      for _, v in pairs(data.vocationNames) do
        if type(v) == 'table' and tonumber(v.id) then vocationNames[tonumber(v.id)] = tostring(v.name) end
      end
    end
    -- unchanged: the cached list is the server's (no spells messages follow)
    if data.unchanged == true and #spells > 0 then
      pending = nil
      spellsSig = type(data.sig) == 'string' and data.sig or spellsSig
    else
      pending = {}
    end
  elseif msg.action == 'spells' then
    pending = pending or {}
    for _, spell in ipairs(list(data.spells)) do
      if type(spell) == 'table' then pending[#pending + 1] = spell end
    end
  elseif msg.action == 'done' then
    local fresh = pending ~= nil
    if fresh then
      local sig = type(data.sig) == 'string' and data.sig or nil
      -- the same list again (a second full answer): keep the rows
      fresh = sig == nil or sig ~= builtSig or #pending ~= #spells
      spells = fresh and pending or spells
      spellsSig = sig
      pending = nil
      if fresh then Core.sort(spells) end
    end
    if window then
      if fresh or #rows ~= #spells then
        buildList()
      else
        refreshState()
        if selected then showDetails(selected) end
      end
    end
    local was = request
    request = nil
    if was == nil then show() end -- the server opened it (staff /spells)
  end
end

-- ---------------------------------------------------------------- window
function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  window.searchEdit:focus()
  refreshState()
  addEvent(fitNames)
  stopCooldownTick()
  cooldownTick()
end

function hide()
  stopCooldownTick()
  if window then window:hide() end
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
    return
  end
  show() -- at once, with the cached list (or "Loading spells..." the first time)
  request = 'user'
  sendOpen() -- the server answers "unchanged" (two small messages) or sends the new list
end

local function characterName()
  local ok, name = pcall(g_game.getCharacterName)
  return ok and name or nil
end

local function loadSavedFilter()
  local ok, node = pcall(g_settings.getNode, Core.SETTINGS_NODE)
  local key = Core.loadFilter(ok and node or nil, characterName())
  pcall(function() window.filterCombo:setCurrentOptionByData(key, true) end)
end

local function saveFilter()
  local name = characterName()
  if not name or name == '' then return end
  local ok, node = pcall(g_settings.getNode, Core.SETTINGS_NODE)
  node = Core.saveFilter(ok and node or nil, name, currentFilter())
  pcall(g_settings.setNode, Core.SETTINGS_NODE, node)
end

local function onGameStart()
  if window then loadSavedFilter() end
  if prefetchEvent then removeEvent(prefetchEvent) end
  prefetchEvent = scheduleEvent(function()
    prefetchEvent = nil
    if g_game.isOnline() and not request then
      request = 'prefetch'
      sendOpen(true)
    end
  end, PREFETCH_DELAY)
end

local function onGameEnd()
  hide()
  if prefetchEvent then
    removeEvent(prefetchEvent)
    prefetchEvent = nil
  end
  -- the list and its rows stay (the next login checks the signature); the character's state goes
  pending, selected, meta, request = nil, nil, {}, nil
  cooldownEnds = {}
  Core.setLearned({})
end

function init()
  window = g_ui.displayUI('spellbook')
  window:hide()
  local filterText = { learned = tr('Learned'), soon = tr('Available soon'), vocation = tr('My vocation'),
    all = tr('All spells'), runes = tr('Runes') }
  for _, f in ipairs(Core.FILTERS) do
    window.filterCombo:addOption(filterText[f.key] or f.text, f.key)
  end
  window.filterCombo.onOptionChange = function()
    saveFilter()
    applyFilter()
  end
  window.searchEdit.onTextChange = function() applyFilter() end
  window.searchEdit.onKeyPress = onKeyPress
  window.onKeyPress = onKeyPress
  window.spellList.onChildFocusChange = onListFocus
  showDetails(nil)
  window.countLabel:setText('')

  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd, onSpellCooldown = onSpellCooldown })
  connect(LocalPlayer, { onLevelChange = onLevelChange, onMagicLevelChange = onLevelChange })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd, onSpellCooldown = onSpellCooldown })
  disconnect(LocalPlayer, { onLevelChange = onLevelChange, onMagicLevelChange = onLevelChange })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  stopCooldownTick()
  if prefetchEvent then
    removeEvent(prefetchEvent)
    prefetchEvent = nil
  end
  if window then
    window:destroy()
    window = nil
  end
  rows, spells, pending, selected, spellsSig, builtSig = {}, {}, nil, nil, nil, nil
  areaCells, iconCache, paintedMap = {}, {}, nil
end
