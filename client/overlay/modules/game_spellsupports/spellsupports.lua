-- Spell supports: the support sockets of the character's spells. A window (Character > Spell Supports, or
-- using a support rune) lists the class kit's spells with their 1-3 sockets and the support runes carried; a rune
-- goes into a free socket by selecting it and pressing Socket or by dragging it (from the window's rune grid or from a
-- backpack) onto the socket; Remove gives it back for gold, Shatter destroys it; Combine 3 makes one rune of the next
-- level; the third socket of a spell is opened with Orbs of Sockets. The action bar shows small coloured pips on spell
-- buttons with runes and lists the runes in the button tooltip; the spellbook (game_spellbook) shows them under the
-- spell's description.
-- Server: server/data/scripts/chaos/supports.lua (rules: data/lib/chaos_supports.lua, design: SUPPORTS.md next to it),
-- extended opcode 243 (JSON):
--   server -> client  state {level, orbId, orbClientId, orbName, orbCount, orbsNeeded, spells = [spell], runes = [rune]}
--                     bar {spells = {["<spell id>"] = [rune with slot]}, words = {["<words>"] = spell id}}
--                     result {ok, text}
--                     part {id, index, total, text}: a slice of a bigger answer as JSON text (joined here)
--   client -> server  open | socket {spell, slot, rune} | socket {spell, slot, pos = {x, y, z}, clientId} |
--                     remove {spell, slot, keep} | unlock {spell} | combine {rune}
-- The server checks everything; the buttons only mirror its answer.

local OPCODE = 243
local ICONS = '/images/game/supports/'
local KIND_SHORT = { single = 'single', area = 'area', heal = 'heal', buff = 'buff' }

local window
local state            -- last state from the server
local bar = {}         -- spell id (string) -> runes, for the action bar and the spellbook
local barWords = {}    -- words -> spell id
local selectedSpell    -- spell id
local selectedRune     -- rune server id
local shatterArmed     -- {spell, slot, until}
local lastBookWords    -- the spell the spellbook shows (its Supports button opens that one)
local actionbarHooked  -- the original setupButtonTooltip of game_actionbar

-- ---------------------------------------------------------------- helpers
local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

-- the rows of a server list (spells, runes); an entry that is no table is left out (opcode_fuzz_test.lua)
local function list(value)
  local out = {}
  if type(value) == 'table' then
    for _, v in ipairs(value) do
      if type(v) == 'table' then out[#out + 1] = v end
    end
  end
  return out
end

local function gold(n)
  n = tonumber(n) or 0
  if n >= 1000000 then return string.format('%.1fM', n / 1000000) end
  if n >= 1000 then return string.format('%dk', math.floor(n / 1000)) end
  return tostring(n)
end

-- tooltips do not wrap: long lines are broken here
local TIP_CHARS = 64
local function tipText(text)
  local out = {}
  for line in (tostring(text or '') .. '\n'):gmatch('(.-)\n') do
    local lead = line:match('^%s*')
    out[#out + 1] = lead .. SupportsText.wrap(line, TIP_CHARS - #lead, lead .. '  ')
  end
  return table.concat(out, '\n')
end

-- ---------------------------------------------------------------- text that fits its box
-- fitLabel(label, text, tip, tipText): shows `text` in the label, shortened with "..." when it does not fit the
-- label's box (the height for a wrapped label, the width for a one-line one). The widget `tip` (the label itself
-- by default; a phantom label passes its row) then shows tipText (default: the full text) as its tooltip; its own
-- tooltip (tip.fitBaseTip) otherwise. The label refits whenever it is resized (rows are laid out after creation).
local function textFits(label, text)
  label:setText(text)
  local size = label:getTextSize()
  local width = label:getWidth() - label:getTextOffset().x - label:getPaddingLeft() - label:getPaddingRight()
  if size.width > width then return false end
  if not label:getTextWrap() then return true end
  return size.height <= label:getHeight() - label:getPaddingTop() - label:getPaddingBottom()
end

local function updateFitTip(tip)
  local cut = false
  for _, c in pairs(tip.fitCuts or {}) do cut = cut or c end
  local text = cut and tip.fitTipText or tip.fitBaseTip
  if text and text ~= '' then
    tip:setTooltip(tipText(text))
  else
    tip:removeTooltip()
  end
end

local function refit(label)
  local text = label.fitText or ''
  local cut = false
  if label:getWidth() > 1 and label:getHeight() > 1 then
    text, cut = SupportsText.shorten(text, function(candidate) return textFits(label, candidate) end)
  end
  label:setText(text)
  local tip = label.fitTip
  if tip and not tip:isDestroyed() then
    tip.fitCuts = tip.fitCuts or {}
    tip.fitCuts[label:getId()] = cut
    updateFitTip(tip)
  end
end

local function fitLabel(label, text, tip, fullTip)
  label.fitText = tostring(text or '')
  tip = tip or label
  label.fitTip = tip
  tip.fitTipText = fullTip or label.fitText
  if not label.fitHooked then
    label.fitHooked = true
    connect(label, { onGeometryChange = function(self) refit(self) end })
  end
  refit(label)
end

local function setResult(text, ok)
  if not window then return end
  window.resultLabel:setColor(ok == false and '#e03a1e' or '#9fdc7f')
  fitLabel(window.resultLabel, text or '')
end

local function setSpellIcon(widget, words)
  widget:setImageSource('')
  if words and words ~= '' and Spells and Spells.getSpellIcon then
    local ok, folder, clip = pcall(Spells.getSpellIcon, words)
    if ok and folder then
      widget:setImageSource(folder)
      widget:setImageClip(clip)
    end
  end
end

local function setRuneIcon(widget, rune)
  if rune and rune.key then
    widget:setImageSource(ICONS .. rune.key)
    widget:setImageClip('0 0 32 32')
  else
    widget:setImageSource('')
  end
end

local function spellById(id)
  for _, s in ipairs(list(state and state.spells)) do
    if tonumber(s.id) == tonumber(id) then return s end
  end
  return nil
end

local function runeById(id)
  for _, r in ipairs(list(state and state.runes)) do
    if tonumber(r.id) == tonumber(id) then return r end
  end
  return nil
end

local function runeAt(spell, slot)
  for _, r in ipairs(list(spell.runes)) do
    if tonumber(r.slot) == slot then return r end
  end
  return nil
end

local function runeTooltip(r)
  return tipText(string.format('%s\n%s.\nFits: %s spells.', r.name or '', r.text or '', r.fits or ''))
end

-- ---------------------------------------------------------------- pips (list rows and action bar)
local function fillPips(container, spell)
  container:destroyChildren()
  local count, max = tonumber(spell.count) or 0, tonumber(spell.max) or 3
  for i = 1, max do
    local pip = g_ui.createWidget('SupportPip', container)
    local r = runeAt(spell, i)
    if r then
      pip:setBackgroundColor(r.color or '#d6c9ae')
    elseif i <= count then
      pip:setBackgroundColor('#4a3e42')
    else
      pip:setBackgroundColor('#140f12')
      pip:setBorderColor('#2a2226')
    end
  end
end

-- ---------------------------------------------------------------- details
local function socketDrop(spellId, slot)
  return function(self, widget, mousePos)
    if not widget then return false end
    if widget.runeId then
      send('socket', { spell = spellId, slot = slot, rune = widget.runeId })
      return true
    end
    local item = widget.currentDragThing
    if item and item.isItem and item:isItem() then
      local pos = item:getPosition()
      if not pos or pos.x ~= 65535 then
        setResult(tr('Drag the rune from your backpack.'), false)
        return true
      end
      send('socket', { spell = spellId, slot = slot, pos = { x = pos.x, y = pos.y, z = pos.z }, clientId = item:getId() })
      return true
    end
    return false
  end
end

local function showDetails(spell)
  if not window then return end
  local d = window.details
  d.sockets:destroyChildren()
  local has = spell ~= nil
  for _, id in ipairs({ 'icon', 'name', 'info', 'headerSeparator', 'sockets' }) do
    d[id]:setVisible(has)
  end
  d.emptyText:setVisible(not has)
  if not spell then return end
  setSpellIcon(d.icon, spell.words)
  fitLabel(d.name, string.format('%s  (%s)', spell.name or '', spell.words or ''))
  fitLabel(d.info, tr('%s spell, level %d. Sockets open: %d of %d (2nd at level %d, 3rd at level %d with %d %s).',
    spell.kindName or spell.kind or '', tonumber(spell.level) or 0, tonumber(spell.count) or 0,
    tonumber(spell.max) or 3, tonumber(spell.secondLevel) or 0, tonumber(spell.thirdLevel) or 0,
    tonumber(state.orbsNeeded) or 2, tr('Orbs of Sockets')))
  local count = tonumber(spell.count) or 0
  for slot = 1, tonumber(spell.max) or 3 do
    local row = g_ui.createWidget('SupportSocket', d.sockets)
    local r = runeAt(spell, slot)
    local b1, b2 = row.buttons.first, row.buttons.second
    local name, text = '', ''
    row.slot.onDrop = socketDrop(spell.id, slot)
    row.onDrop = row.slot.onDrop
    if r then
      setRuneIcon(row.slot.icon, r)
      row.slot:setTooltip(runeTooltip(r))
      name = r.name .. (r.inactive and tr(' (socket closed)') or '')
      row.name:setColor(r.color or '#d6c9ae')
      text = r.text or ''
      b1:setText(tr('Remove') .. ' (' .. gold(r.cost) .. ')')
      b1:setTooltip(tr('The rune comes back for this much gold (bank first, then backpack).'))
      b1.onClick = function() send('remove', { spell = spell.id, slot = slot, keep = true }) end
      local armed = shatterArmed and shatterArmed.spell == spell.id and shatterArmed.slot == slot
        and shatterArmed['until'] > g_clock.millis()
      b2:setText(armed and tr('Sure?') or tr('Shatter'))
      b2:setTooltip(tr('Destroys the rune for free.'))
      b2.onClick = function()
        if shatterArmed and shatterArmed.spell == spell.id and shatterArmed.slot == slot
            and shatterArmed['until'] > g_clock.millis() then
          shatterArmed = nil
          send('remove', { spell = spell.id, slot = slot, keep = false })
        else
          shatterArmed = { spell = spell.id, slot = slot, ['until'] = g_clock.millis() + 3000 }
          b2:setText(tr('Sure?'))
        end
      end
    elseif slot <= count then
      name = tr('Empty socket')
      row.name:setColor('#d6c9ae')
      text = tr('Select a rune below and press Socket, or drag a rune here.')
      b1:setText(tr('Socket'))
      b1:setEnabled(selectedRune ~= nil)
      b1.onClick = function()
        if selectedRune then send('socket', { spell = spell.id, slot = slot, rune = selectedRune }) end
      end
      b2:setVisible(false)
    else
      row.slot:setEnabled(false)
      row.name:setColor('#6b6258')
      b2:setVisible(false)
      if slot == 3 and not spell.opened then
        name = tr('Locked socket')
        text = string.format('%s %d %s (%s %d). %s %d.', tr('Opens with'), tonumber(state.orbsNeeded) or 2,
          tr('Orbs of Sockets'), tr('you have'), tonumber(state.orbCount) or 0, tr('Needs level'),
          tonumber(spell.thirdLevel) or 0)
        b1:setText(tr('Open'))
        b1:setEnabled(spell.canOpen == true and (tonumber(state.orbCount) or 0) >= (tonumber(state.orbsNeeded) or 2))
        b1.onClick = function() send('unlock', { spell = spell.id }) end
      else
        name = tr('Locked socket')
        text = string.format('%s %d.', tr('Opens at level'), slot == 2 and (tonumber(spell.secondLevel) or 0)
          or (tonumber(spell.thirdLevel) or 0))
        b1:setVisible(false)
      end
    end
    local full = name .. '\n' .. text .. (r and r.inactive and ('\n' .. tr('No effect until the socket is open again.')) or '')
    fitLabel(row.name, name, row, full)
    fitLabel(row.text, text, row, full)
  end
end

-- ---------------------------------------------------------------- lists
local function buildSpells()
  local listWidget = window.spellList
  listWidget:destroyChildren()
  local focus
  for _, spell in ipairs(list(state.spells)) do
    local row = g_ui.createWidget('SupportSpellRow', listWidget)
    row.spellId = spell.id
    setSpellIcon(row.icon, spell.words)
    local kind = string.format('%s, level %d', KIND_SHORT[spell.kind] or spell.kind or '', tonumber(spell.level) or 0)
    local full = (spell.name or '') .. '\n' .. kind
    fitLabel(row.name, spell.name or '', row, full)
    fitLabel(row.kind, kind, row, full)
    fillPips(row.pips, spell)
    if (tonumber(state.level) or 0) < (tonumber(spell.level) or 0) then
      row.name:setColor('#6b6258')
    end
    row.onFocusChange = function(self, focused)
      if focused then
        selectedSpell = self.spellId
        showDetails(spellById(self.spellId))
      end
    end
    if tonumber(spell.id) == tonumber(selectedSpell) then focus = row end
  end
  focus = focus or listWidget:getFirstChild()
  if focus then
    listWidget:focusChild(focus, KeyboardFocusReason)
    selectedSpell = focus.spellId
    scheduleEvent(function()
      if focus and not focus:isDestroyed() and listWidget.ensureChildVisible then listWidget:ensureChildVisible(focus) end
    end, 50)
  end
  showDetails(spellById(selectedSpell))
end

local function showRuneInfo()
  local r = selectedRune and runeById(selectedRune)
  if not r then
    selectedRune = nil
    fitLabel(window.runeInfo, '')
    window.combineButton:setEnabled(false)
    return
  end
  window.runeInfo:setColor(r.color or '#d6c9ae')
  fitLabel(window.runeInfo, string.format('%s (x%d): %s. Fits %s spells.', r.name, tonumber(r.count) or 0,
    r.text or '', r.fits or ''))
  window.combineButton:setEnabled(r.combine == true and (tonumber(r.count) or 0) >= 3)
end

local function buildRunes()
  local grid = window.runeGrid
  grid:destroyChildren()
  local runes = list(state.runes)
  window.noRunes:setVisible(#runes == 0)
  for _, r in ipairs(runes) do
    local cell = g_ui.createWidget('SupportRuneCell', grid)
    cell.runeId = r.id
    setRuneIcon(cell.icon, r)
    cell.count:setText((tonumber(r.count) or 0) > 1 and tostring(r.count) or '')
    cell:setBorderColor(r.color or '#e8b84a')
    cell:setTooltip(runeTooltip(r) .. '\n' .. tr('Carried') .. ': ' .. tostring(r.count))
    cell.onFocusChange = function(self, focused)
      if focused then
        selectedRune = self.runeId
        showRuneInfo()
        showDetails(spellById(selectedSpell))
      end
    end
    cell.onDragEnter = function(self, mousePos) return true end
    cell.onDragLeave = function(self, droppedWidget, mousePos) return true end
    if tonumber(r.id) == tonumber(selectedRune) then
      grid:focusChild(cell, KeyboardFocusReason)
    end
  end
  showRuneInfo()
end

function combineSelected()
  if selectedRune then send('combine', { rune = selectedRune }) end
end

-- ---------------------------------------------------------------- action bar and spellbook
local function barRunes(spellId)
  return bar[tostring(spellId)]
end

local function decorateButton(button)
  local cache = button and button.cache
  local item = button and button.item
  if not item then return end
  local pips = item:getChildById('chaosSupportPips')
  local runes = cache and cache.isSpell and cache.spellData and barRunes(cache.spellData.id)
  if not runes or #runes == 0 then
    if pips then pips:destroy() end
    return
  end
  if not pips then
    pips = g_ui.createWidget('UIWidget', item)
    pips:setId('chaosSupportPips')
    pips:setPhantom(true)
    pips:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    pips:addAnchor(AnchorTop, 'parent', AnchorTop)
    pips:setMarginLeft(2)
    pips:setMarginTop(2)
    pips:setSize({ width = 20, height = 5 })
    local layout = UIHorizontalLayout.create(pips)
    layout:setSpacing(1)
    pips:setLayout(layout)
  end
  pips:destroyChildren()
  local lines = {}
  for _, r in ipairs(runes) do
    local pip = g_ui.createWidget('UIWidget', pips)
    pip:setSize({ width = 5, height = 5 })
    pip:setPhantom(true)
    pip:setBackgroundColor(r.color or '#d6c9ae')
    lines[#lines + 1] = '  ' .. SupportsText.wrap(string.format('%s: %s', r.name or '', r.text or ''), TIP_CHARS, '    ')
  end
  local tip = item:getTooltip() or ''
  tip = tip:gsub('\n\nSupports:.*$', '')
  item:setTooltip(tr('%s\n\nSupports:\n%s', tip, table.concat(lines, '\n')))
end

local function refreshActionBar()
  local ab = modules.game_actionbar
  local bars = ab and ab.actionBars
  if type(bars) ~= 'table' then return end
  for _, actionbar in pairs(bars) do
    local tabBar = actionbar and actionbar.tabBar
    if tabBar then
      for _, button in ipairs(tabBar:getChildren()) do
        if button.cache and button.cache.isSpell then
          pcall(ab.setupButtonTooltip, button, false)
        elseif button.item and button.item:getChildById('chaosSupportPips') then
          button.item:getChildById('chaosSupportPips'):destroy()
        end
      end
    end
  end
end

local function hookActionBar()
  local ab = modules.game_actionbar
  if actionbarHooked or not ab or type(ab.setupButtonTooltip) ~= 'function' then return end
  actionbarHooked = ab.setupButtonTooltip
  ab.setupButtonTooltip = function(button, isEmpty)
    local r = actionbarHooked(button, isEmpty)
    if not isEmpty then
      pcall(decorateButton, button)
    elseif button and button.item and button.item:getChildById('chaosSupportPips') then
      button.item:getChildById('chaosSupportPips'):destroy()
    end
    return r
  end
end

local function unhookActionBar()
  local ab = modules.game_actionbar
  if actionbarHooked and ab then
    ab.setupButtonTooltip = actionbarHooked
  end
  actionbarHooked = nil
  bar = {}
  pcall(refreshActionBar)
end

-- the spellbook's description (game_spellbook calls it with the shown spell's words): a short line (the rune names)
-- and the effects for its tooltip
function spellbookLine(words)
  lastBookWords = words
  local id = words and barWords[words]
  if not id then return nil end
  local runes = barRunes(id)
  if not runes or #runes == 0 then
    return tr('Supports: none socketed (Character > Spell Supports).')
  end
  local names, effects = {}, {}
  for _, r in ipairs(runes) do
    names[#names + 1] = r.name or ''
    effects[#effects + 1] = string.format('  %s: %s', r.name or '', r.text or '')
  end
  return tr('Supports') .. ': ' .. table.concat(names, ', ') .. '.',
    tr('Supports') .. ':\n' .. table.concat(effects, '\n')
end

-- for other windows (the spellbook): `text` in `label`, shortened with "..." when it does not fit the label's box;
-- `tip` is the label's tooltip (default: the full text when it was shortened)
function fitText(label, text, tip)
  label.fitBaseTip = tip
  fitLabel(label, text, label, tip)
end

function openFor(words)
  local id = barWords[words or lastBookWords or '']
  if id then selectedSpell = id end
  send('open')
end

-- ---------------------------------------------------------------- protocol
local parts = {} -- id -> {total, got, texts}
local handle

-- a slice of a bigger answer: kept until every slice is there, then handled as the whole message
local function onPart(data)
  local id, index, total = tonumber(data.id), tonumber(data.index), tonumber(data.total)
  if not id or not index or not total or total < 1 or total > 64 or type(data.text) ~= 'string' then return end
  local p = parts[id]
  if not p or p.total ~= total then
    p = { total = total, got = 0, texts = {} }
    parts[id] = p
  end
  if not p.texts[index] then
    p.texts[index] = data.text
    p.got = p.got + 1
  end
  if p.got < total then return end
  parts[id] = nil
  local ok, msg = pcall(json.decode, table.concat(p.texts))
  if ok and type(msg) == 'table' and msg.action ~= 'part' then handle(msg) end
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then return end
  handle(msg)
end

handle = function(msg)
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'part' then
    onPart(data)
  elseif msg.action == 'state' then
    state = data
    if not window then return end
    buildSpells()
    buildRunes()
    if not window:isVisible() then
      window:show()
      window:raise()
      window:focus()
    end
  elseif msg.action == 'bar' then
    bar = type(data.spells) == 'table' and data.spells or {}
    barWords = type(data.words) == 'table' and data.words or {}
    hookActionBar()
    pcall(refreshActionBar)
  elseif msg.action == 'result' then
    setResult(data.text, data.ok)
  end
end

-- ---------------------------------------------------------------- window
function show()
  send('open')
end

function hide()
  if window then window:hide() end
end

function toggle()
  if window and window:isVisible() then
    hide()
  else
    send('open')
  end
end

local function onGameEnd()
  hide()
  parts = {}
  state, selectedRune, shatterArmed = nil, nil, nil
  bar, barWords = {}, {}
  if window then setResult('') end
end

local function onGameStart()
  hookActionBar()
end

function init()
  window = g_ui.displayUI('spellsupports')
  window:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd, onGameStart = onGameStart })
  if g_game.isOnline() then hookActionBar() end
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd, onGameStart = onGameStart })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  unhookActionBar()
  if window then
    window:destroy()
    window = nil
  end
  state = nil
end
