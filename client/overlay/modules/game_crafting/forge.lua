-- The forge window (O481, owner request 2026-11-11): the crafting bench as "place the item, pick an action, check the
-- change, forge". It shares extended opcode 232 with the classic bench (crafting.lua forwards every message here);
-- forgeview.lua decides what it shows, the server (crafting.lua, chaos_crafting.lua C.explain) says what will happen.
-- Messages and fields: see the head of forgeview.lua. The window asks for the additive fields with open {forge = 1}.
-- The forge is the bench: there is no switch to the classic window (owner 2026-11-11, O487: players who switched found
-- no way back). The Salvage tab opens the classic window (crafting.lua) in its Salvage tab, once; its Forge button comes
-- back here. The Guide tab opens the Guide.
-- Nothing is computed here: counts, words, tags, costs and outcomes come from the server through forgeview.lua; the
-- window sends "apply" only for an action the server has explained for this very item (forgeview.lua V.request).
-- This file only places widgets; every surface is a theme style (forge.otui).

local OPCODE = 232

CraftingForge = CraftingForge or {}
local F = CraftingForge
local V = CraftingForgeView
local C = V.C

local fw                 -- the window
local info               -- the orbs and the reason texts (server "info")
local forgeInfo          -- {orbs = {key -> {kind, safety}}} (server "forgeinfo")
local state              -- last state
local lastExplain        -- last "explain" answer
local lastResult         -- last "result" answer (nil before the first craft)
local requested          -- the question asked last (orb|mod|sig): the same one is not asked twice
local sel = { orb = nil, mod = nil, tab = 'mod' }
local pending = false    -- an apply was sent, the next state has not come yet
local confirmBox
F.classicOnce = false    -- the classic window is wanted once (the menu's Salvage entry, the Salvage tab)

local okText, Text = pcall(dofile, '/modules/game_spellsupports/supportstext.lua')
if not okText or type(Text) ~= 'table' then Text = nil end
-- the item tooltip's tier colours (V.tierColor reads ItemTooltipLogic when it is loaded)
pcall(dofile, '/modules/game_itemtooltip/tooltiplogic.lua')

-- ---------------------------------------------------------------- helpers
local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function w(id) return fw and fw:recursiveGetChildById(id) or nil end

local function rows(value)
  local out = {}
  if type(value) == 'table' then
    for _, v in ipairs(value) do
      if type(v) == 'table' then out[#out + 1] = v end
    end
  end
  return out
end

local function setTip(widget, text)
  if text and text ~= '' then
    local out = {}
    for line in (tostring(text) .. '\n'):gmatch('(.-)\n') do
      out[#out + 1] = Text and Text.wrap(line, 64, '  ') or line
    end
    widget:setTooltip(table.concat(out, '\n'))
  else
    widget:removeTooltip()
  end
end

-- a widget at x, y of its parent (the list styles have no anchors of their own)
local function place(widget, x, y)
  widget:addAnchor(AnchorTop, 'parent', AnchorTop)
  widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  widget:setMarginLeft(x)
  widget:setMarginTop(y)
end

local function ctx()
  return { info = info, forge = forgeInfo, state = state or {}, sel = sel, explain = lastExplain, mod = sel.mod }
end

local function spaced(text)
  return (tostring(text):gsub('.', '%0 '):gsub(' $', ''))
end

-- ---------------------------------------------------------------- answers
local function ask()
  local item = state and state.item
  if not item or not sel.orb then return end
  local a = V.find(V.actions(ctx()), sel.orb)
  if not a or not a.itemOk then return end
  if a.kind == 'mod' then
    if not sel.mod then return end
    if not V.contains(type(item.pick) == 'table' and item.pick[a.key] or nil, sel.mod) then return end
  end
  local key = table.concat({ sel.orb, sel.mod or '', tostring(item.sig or '') }, '|')
  if key == requested then return end
  requested = key
  send('explain', { orb = sel.orb, path = item.path, id = item.id, sig = item.sig, mod = sel.mod })
end

-- ---------------------------------------------------------------- drawing
local render

local function renderSteps()
  for _, st in ipairs(V.stepper(ctx())) do
    local label = w('step' .. st.n)
    label:setText(string.format('%d %s', st.n, st.text))
    label:setColor(st.color)
    w('check' .. st.n):setVisible(st.state == 'done')
    if st.n < 4 then w('arrow' .. st.n):setText('>') end
    if st.state == 'now' then label:setFont('verdana-11px-rounded') else label:setFont('verdana-11px-antialised') end
  end
end

local function renderChips()
  local panel = w('matsPanel')
  panel:destroyChildren()
  local chips = V.chips(ctx())
  local pitch, per, nrows = V.chipLayout(#chips, 864)
  panel:setHeight(44 + (nrows - 1) * 36)
  for i, m in ipairs(chips) do
    local chip = g_ui.createWidget('ForgeChip', panel)
    place(chip, ((i - 1) % per) * pitch, math.floor((i - 1) / per) * 36)
    chip:setItemId(m.clientId)
    chip:setItemCount(V.iconCount(m.clientId))
    chip.cnt:setText(m.countText)
    chip:setOpacity(m.dim and 0.4 or 1.0)
    chip:setBorderWidth(m.use and 1 or 0)
    setTip(chip, m.tip)
  end
end

local function pips(container, filled, total)
  container:destroyChildren()
  container:setWidth(math.max(1, total * 11))
  for i = 1, total do
    local pip = g_ui.createWidget('UIWidget', container)
    pip:setSize({ width = 8, height = 8 })
    place(pip, (i - 1) * 11, 1)
    pip:setBorderWidth(1)
    local on = i <= filled
    pip:setBackgroundColor(on and C.gold or C.black)
    pip:setBorderColor(on and C.bright or C.off)
    pip:setPhantom(true)
  end
end

local function renderItem()
  local item = state and state.item
  local p = V.itemPanel(item)
  w('itemName'):setText(p.name)
  w('itemName'):setColor(p.color)
  local slot = w('itemSlot')
  slot:setItemId(item and tonumber(item.clientId) or 0)
  slot:setBorderWidth(item and 1 or 0)
  slot:setBorderColor(p.borderColor or C.off)
  w('lockButton'):setVisible(item ~= nil and item.kind ~= 'riftkey')
  w('lockButton'):setText(item and item.locked and tr('Unlock') or tr('Lock'))
  w('changeButton'):setVisible(item ~= nil)
  local line, bar, sockL, sockP = w('itemLine'), w('qualityBar'), w('socketLabel'), w('socketPips')
  local preL, preP, sufL, sufP, free = w('prefixLabel'), w('prefixPips'), w('suffixLabel'), w('suffixPips'), w('freeLabel')
  bar:setVisible(false)
  sockL:setVisible(false)
  sockP:destroyChildren()
  sockP:setWidth(1)
  preL:setVisible(false)
  sufL:setVisible(false)
  preP:destroyChildren() preP:setWidth(1)
  sufP:destroyChildren() sufP:setWidth(1)
  free:setText('')
  if not item then
    line:setText(p.line or '')
    return
  end
  if p.line then
    line:setText(p.line)
    if p.keyMods then
      preL:setText(tr('Modifiers'))
      preL:setVisible(true)
      pips(preP, p.keyMods.used, p.keyMods.max)
    end
    return
  end
  local parts = { p.rarityText, p.rarityColor }
  if p.level then
    parts[#parts + 1] = ' · ' .. tr('Item level') .. ' '
    parts[#parts + 1] = C.dim
    parts[#parts + 1] = tostring(p.level)
    parts[#parts + 1] = C.text
  end
  if p.quality then
    parts[#parts + 1] = ' · ' .. tr('Quality') .. ' '
    parts[#parts + 1] = C.dim
    parts[#parts + 1] = string.format('%d%%', p.quality.q)
    parts[#parts + 1] = C.good
  end
  line:setColoredText(parts)
  if p.quality then
    bar:setVisible(true)
    bar:setPercent(math.floor(p.quality.frac * 100 + 0.5))
    setTip(bar, tr('Quality %d%% of %d%%', p.quality.q, p.quality.cap))
  end
  if p.sockets then
    sockL:setText(tr('Sockets'))
    sockL:setVisible(true)
    pips(sockP, p.sockets.filled, p.sockets.max)
  end
  if p.prefix then
    preL:setText(tr('Prefixes'))
    sufL:setText(tr('Suffixes'))
    preL:setVisible(true)
    sufL:setVisible(true)
    pips(preP, p.prefix.used, p.prefix.max)
    pips(sufP, p.suffix.used, p.suffix.max)
    free:setText(p.free or '')
  end
  if p.flag then free:setText(p.flag) free:setColor(C.blood) else free:setColor(C.dim) end
end

local TAB_ID = { mod = 'tabMod', add = 'tabAdd', whole = 'tabWhole', sockets = 'tabSockets', salvage = 'tabSalvage', guide = 'tabGuide' }
local TAB_ORDER = { 'mod', 'add', 'whole', 'sockets', 'salvage', 'guide' }

local function renderTabs(actions)
  local item = state and state.item
  local shown = {}
  for _, t in ipairs(V.tabs(actions, item)) do
    shown[t.id] = t
  end
  for _, id in ipairs(TAB_ORDER) do
    local b = w(TAB_ID[id])
    local t = shown[id]
    b:setVisible(t ~= nil)
    if t then
      b:setText(V.tabText(t))
      local ok, size = pcall(function() return b:getTextSize() end)
      b:setWidth((ok and size and size.width or 110) + 26)
      b:setChecked(id == sel.tab)
    else
      b:setWidth(1)
    end
  end
  if not shown[sel.tab] then sel.tab = 'mod' end
end

local function renderMods(item)
  local list = w('modList')
  list:destroyChildren()
  local panel = V.itemPanel(item)
  local groups = V.groupList(item)
  if #groups == 0 then
    local note = g_ui.createWidget('ForgeNote', list)
    note:setText(tr('This item has no modifiers.'))
  end
  for _, g in ipairs(groups) do
    local plate = g_ui.createWidget('ForgeGroupPlate', list)
    local count = ''
    if g.side == 'prefix' and panel.prefix then count = string.format(' %d/%d', panel.prefix.used, panel.prefix.max)
    elseif g.side == 'suffix' and panel.suffix then count = string.format(' %d/%d', panel.suffix.used, panel.suffix.max) end
    plate.text:setText(g.label .. count)
    plate.text:setColor(g.side == 'implicit' and C.blood or C.gold)
    for _, r in ipairs(g.rows) do
      local row = g_ui.createWidget('ForgeModRow', list)
      local chosen = r.key ~= nil and r.key == sel.mod
      row.tier:setText(r.tierText)
      row.tier:setBackgroundColor(r.tier and r.color or '#00000000')
      row.text:setText(r.text)
      row.text:setColor(chosen and C.bright or (r.implicit and C.blood or (r.power and C.gold or C.text)))
      row.text:setFont(chosen and 'verdana-11px-rounded' or 'verdana-11px-antialised')
      row.range:setText(r.rangeText or '')
      if r.frac then
        row.roll:setPercent(math.floor(r.frac * 100 + 0.5))
        row.roll:setBackgroundColor(r.color)
      else
        row.roll:setVisible(false)
      end
      row.mark:setText(r.mark)
      if r.bound then
        setTip(row, tr('Bound: the orbs that change modifiers leave it alone. Only an Orb of Erasure frees it.'))
      end
      row.sel:setVisible(chosen)
      local key = r.key
      row.onMouseRelease = function(self, mousePos, button)
        if button ~= MouseLeftButton or not self:containsPoint(mousePos) or not key then return false end
        sel.mod = (sel.mod ~= key) and key or nil
        requested, lastExplain = nil, nil
        ask()
        render()
        return true
      end
    end
  end
  if item and item.veil == 1 then
    local note = g_ui.createWidget('ForgeNote', list)
    note:setText(tr('This item has a veiled modifier: an Orb of Unveiling reveals it.'))
  elseif item and item.rewards then
    local note = g_ui.createWidget('ForgeNote', list)
    note:setText(tr('Rewards: %s', item.rewards))
    note:setColor(C.good)
  end
end

local function renderSockets(item)
  local list = w('modList')
  list:destroyChildren()
  local s = type(item.sockets) == 'table' and item.sockets or {}
  local count = tonumber(s.count) or 0
  local head = g_ui.createWidget('ForgeGroupPlate', list)
  if count == 0 then
    head.text:setText(tr('No sockets (an Orb of Sockets gives up to %d)', tonumber(s.max) or 0))
    return
  end
  local filled = 0
  for _, row in ipairs(rows(s.list)) do
    if (tonumber(row.id) or 0) > 0 then filled = filled + 1 end
  end
  head.text:setText(tr('Sockets: %d / %d', filled, count))
  for _, row in ipairs(rows(s.list)) do
    local widget = g_ui.createWidget('ForgeSocketRow', list)
    local id, index = tonumber(row.id) or 0, row.index
    if id > 0 then
      widget.icon:setItemId(tonumber(row.clientId) or 0)
      widget.name:setText(row.name or '?')
      widget.name:setColor(row.color or C.text)
      widget.text:setText(row.text or '')
      widget.removeButton:setText(tostring(tonumber(row.cost) or 0))
      setTip(widget.removeButton, tr('Take the gem out for %d gold (bank first, then the backpack). It comes back to you.', tonumber(row.cost) or 0))
      widget.shatterButton:setTooltip(tr('Take the gem out for free: it is destroyed.'))
      widget.removeButton.onClick = function()
        widget.removeButton:setEnabled(false)
        send('gem', { op = 'remove', socket = index, path = item.path, id = item.id, sig = item.sig })
      end
      widget.shatterButton.onClick = function()
        widget.shatterButton:setEnabled(false)
        send('gem', { op = 'shatter', socket = index, path = item.path, id = item.id, sig = item.sig })
      end
    else
      widget.icon:setVisible(false)
      widget.name:setText(tr('Empty socket'))
      widget.name:setColor(C.dim)
      widget.text:setText(tr('Use a gem with the item to fill it'))
      widget.text:setColor(C.off)
      widget.removeButton:setVisible(false)
      widget.shatterButton:setVisible(false)
    end
  end
end

local function renderCards(actions)
  local list = w('actionList')
  list:destroyChildren()
  local cards = V.cards(actions, sel.tab, sel)
  local fit = V.cardsFit(#cards, 104)
  w('actionScroll'):setVisible(not fit)
  list:setMarginRight(fit and 0 or 15)
  local cw = fit and 214 or 207
  for i, c in ipairs(cards) do
    local card = g_ui.createWidget('ForgeCard', list)
    card:setWidth(cw)
    place(card, ((i - 1) % 2) * (cw + 4), math.floor((i - 1) / 2) * 36)
    local a = V.find(actions, c.key)
    card.icon:setItemId(a and a.clientId or 0)
    card.icon:setItemCount(V.iconCount(a and a.clientId))
    card.stripe:setBackgroundColor(c.stripe)
    card.verb:setText(c.verb)
    card.verb:setColor(c.chosen and C.bright or C.text)
    card.verb:setFont(c.chosen and 'verdana-11px-rounded' or 'verdana-11px-antialised')
    card.sub:setText(c.sub)
    card.sub:setColor(c.subIsReason and C.blood or C.dim)
    card.count:setText(c.count)
    card.count:setColor(c.dim and C.off or C.text)
    card.sel:setVisible(c.chosen)
    card:setOpacity(c.dim and 0.55 or 1.0)
    setTip(card, c.tip)
    local key = c.key
    card.onMouseRelease = function(self, mousePos, button)
      if button ~= MouseLeftButton or not self:containsPoint(mousePos) then return false end
      local now = V.find(V.actions(ctx()), key)
      if not now or not now.can then return true end -- a card that cannot be done only explains why (its tooltip)
      sel.orb = (sel.orb ~= key) and key or nil
      requested, lastExplain = nil, nil
      ask()
      render()
      return true
    end
  end
end

local function renderWhat(actions)
  local plate, tag, text = w('whatPlate'), w('whatTag'), w('whatText')
  local item = state and state.item
  local a = sel.orb and V.find(actions, sel.orb) or nil
  plate.text:setText(tr('What happens'))
  local cmp = nil
  local function hideCompare()
    for _, id in ipairs({ 'cmpLeftPill', 'cmpLeft', 'cmpArrow', 'cmpRightPill', 'cmpRight', 'cmpBound', 'cmpTail' }) do w(id):setVisible(false) end
    w('cmpLeftPill'):setHeight(0)
  end
  hideCompare()
  local costRow = w('costRow')
  costRow:setVisible(a ~= nil)
  w('costSep'):setVisible(a ~= nil)
  tag:setText('')
  if not item then
    text:setText(tr('Put an item on the bench first.'))
    text:setColor(C.dim)
    return
  end
  if not a then
    text:setText(tr('Pick an action on the right. The server tells you here what it will do before you forge.'))
    text:setColor(C.dim)
    return
  end
  tag:setText(V.tagLabel(a.tag))
  tag:setColor(V.tagColor(a.tag))
  local cost = V.costRow(a)
  w('costIcon'):setItemId(a.clientId)
  w('costIcon'):setItemCount(V.iconCount(a.clientId))
  w('costName'):setText(cost.name)
  w('costHave'):setText(cost.have)
  if not a.can then
    text:setText(a.why)
    text:setColor(C.blood)
  elseif V.answered(ctx()) then
    local s = V.sentence(lastExplain)
    if s.lead ~= '' then
      text:setColoredText({ s.lead, s.leadColor, ' ' .. s.text .. (s.warn and (' ' .. s.warn) or ''), C.text })
    else
      text:setText(s.text)
      text:setColor(lastExplain.ok == false and C.blood or C.text)
    end
    cmp = V.compare(lastExplain)
  else
    text:setText(tr('Asking the server...'))
    text:setColor(C.dim)
  end
  if cmp then
    w('cmpLeftPill'):setHeight(14)
    local function pill(id, side)
      local p = w(id)
      p:setVisible(side.pill ~= nil)
      p:setWidth(side.pill and 26 or 0)
      if side.pill then
        p:setText(side.pill)
        p:setBackgroundColor(side.pillColor)
      end
    end
    pill('cmpLeftPill', cmp.left)
    pill('cmpRightPill', cmp.right)
    w('cmpLeft'):setVisible(true)
    w('cmpLeft'):setText(cmp.left.text)
    w('cmpLeft'):setColor(C.dim)
    w('cmpArrow'):setVisible(true)
    w('cmpArrow'):setText('»')
    w('cmpRight'):setVisible(true)
    w('cmpRight'):setText(cmp.right.text)
    w('cmpRight'):setColor(cmp.right.color or C.text)
    w('cmpBound'):setVisible(cmp.right.bound ~= nil)
    w('cmpBound'):setText(cmp.right.bound or '')
    w('cmpTail'):setVisible(cmp.tail ~= '')
    w('cmpTail'):setText(cmp.tail)
    w('cmpTail'):setColor(cmp.tailColor or C.good)
  end
end

local function renderBar()
  local lines = V.barLines(ctx(), lastResult)
  local go = V.go(ctx())
  local l1 = w('barLine1')
  if lines.target ~= '' then
    l1:setColoredText({ lines.verb .. ' ', C.text, lines.target, C.gold })
  else
    l1:setText(lines.verb)
    l1:setColor(C.text)
  end
  w('barLine2'):setText(lines.guarantee)
  local mark, label = w('resultMark'), w('resultLabel')
  if lines.result.text ~= '' then
    mark:setVisible(lines.result.mark == 'ok')
    label:setText((lines.result.mark == 'fail' and '× ' or '') .. lines.result.text)
    label:setColor(lines.result.mark == 'fail' and C.blood or C.good)
    setTip(label, lines.result.text)
  else
    mark:setVisible(false)
    label:setText('')
  end
  local b = w('forgeButton')
  b:setText(spaced(go.title))
  b:setEnabled(go.enabled and not pending)
  local sub = w('goSub')
  sub:setText(go.sub)
  sub:setColor(go.risky and C.blood or C.dim)
  setTip(b, go.enabled and '' or go.sub)
end

local function renderGear()
  local list = w('gearList')
  list:destroyChildren()
  local items = rows(state and state.items)
  for _, it in ipairs(items) do
    local slot = g_ui.createWidget('ForgeGearSlot', list)
    slot:setItemId(tonumber(it.clientId) or 0)
    local rarity = tonumber(it.rarity) or 0
    local tip = it.name or ''
    if it.unique then tip = tip .. '\n' .. tr('Unique')
    elseif it.key then tip = tip .. '\n' .. tr('Rift Key')
    elseif rarity > 0 then tip = tip .. '\n' .. (it.rarityName or tr('Rarity %d', rarity)) end
    if rarity > 0 or it.unique or it.key then
      slot:setBorderWidth(1)
      slot:setBorderColor(it.unique and C.blood or it.key and V.KEY_COLOR or V.rarityColor(rarity))
    end
    if it.locked then
      tip = tip .. '\n' .. tr('Locked')
      slot:setOpacity(0.55)
    end
    setTip(slot, tip)
    local path, id = it.path, it.id
    slot.onMouseRelease = function(self, mousePos, button)
      if button == MouseLeftButton and self:containsPoint(mousePos) then
        lastResult = nil
        send('select', { path = path, id = id })
        return true
      end
      return false
    end
    slot.onDragEnter = function() return false end -- the grid is a picker, not a container
  end
  w('gearHint'):setText(tr('No gear or Rift Key in your backpack.'))
  w('gearHint'):setVisible(#items == 0)
end

function render()
  if not fw or not fw:isVisible() then return end
  local item = state and state.item
  local actions = V.actions(ctx())
  renderSteps()
  renderChips()
  renderItem()
  renderTabs(actions)
  local hasItem = item ~= nil
  w('gearPanel'):setVisible(not hasItem)
  w('leftPanel'):setVisible(hasItem)
  w('actionList'):setVisible(hasItem)
  w('whatBox'):setVisible(hasItem)
  if not hasItem then w('actionScroll'):setVisible(false) end
  if hasItem then
    if sel.tab == 'sockets' then renderSockets(item) else renderMods(item) end
    w('hintLabel'):setText(sel.tab == 'mod' and tr('Click a modifier to pick the target.') or '')
    renderCards(actions)
  else
    renderGear()
  end
  renderWhat(actions)
  renderBar()
end

-- ---------------------------------------------------------------- protocol
local function onState(data)
  if type(data.item) ~= 'table' then data.item = nil end
  local before = state and state.item
  state = data
  pending = false
  local item = data.item
  if not item then
    sel.orb, sel.mod = nil, nil
  elseif before and before.path ~= item.path then
    sel.orb, sel.mod = nil, nil
  else
    sel.mod = V.keepSelection(item, sel.mod) -- the selection stays on the same modifier while it exists
  end
  requested, lastExplain = nil, nil
  if sel.orb then
    local a = V.find(V.actions(ctx()), sel.orb)
    if not a then sel.orb = nil end
  end
  ask()
  if data.open and F.wanted() then F.show() end
  render()
end

-- crafting.lua forwards every message of the opcode here
function F.onMessage(action, data)
  if action == 'info' then
    info = data
  elseif action == 'forgeinfo' then
    forgeInfo = data
  elseif action == 'state' then
    onState(data)
  elseif action == 'explain' then
    lastExplain = data
    render()
  elseif action == 'result' then
    lastResult = data
    pending = false
    render()
  end
end

-- ---------------------------------------------------------------- the window
function F.wanted()
  return fw ~= nil and not F.classicOnce
end

function F.show()
  if not fw then return end
  fw:show()
  fw:raise()
  fw:focus()
  render()
end

function F.hide()
  if fw then fw:hide() end
end

function F.isVisible()
  return fw ~= nil and fw:isVisible()
end

function F.open()
  send('open', { forge = 1 })
end

function F.toggle()
  if not fw then return end
  if fw:isVisible() then
    F.hide()
    return
  end
  F.open()
end

function F.forge()
  if not fw or not fw:isVisible() or pending then return end
  local req, why = V.request(ctx())
  if not req then
    if why and why ~= '' then
      lastResult = { ok = false, text = why }
      renderBar()
    end
    return
  end
  local bar = V.bar(ctx())
  local function go()
    if confirmBox then confirmBox:destroy() confirmBox = nil end
    pending = true
    renderBar()
    send('apply', req)
  end
  if bar.confirm and displayGeneralBox then
    if confirmBox then confirmBox:destroy() confirmBox = nil end
    local function no()
      if confirmBox then confirmBox:destroy() confirmBox = nil end
    end
    confirmBox = displayGeneralBox(tr('Forge'), bar.confirm,
      { { text = tr('Forge'), callback = go }, { text = tr('Cancel'), callback = no }, anchor = AnchorHorizontalCenter }, go, no)
  else
    go()
  end
end

-- the Forge button of the classic window (shown for Salvage)
function F.switchTo()
  F.classicOnce = false
  if hide then hide() end -- the classic window (crafting.lua)
  F.open()
end

function F.tab(id)
  if id == 'salvage' then
    F.classicOnce = true
    F.hide()
    if openSalvage then openSalvage() end
    return
  elseif id == 'guide' then
    if showGuide then showGuide() end
    return
  end
  if sel.tab ~= id then
    sel.tab = id
    local a = sel.orb and V.find(V.actions(ctx()), sel.orb)
    if a and a.kind ~= id then sel.orb = nil end
    requested, lastExplain = nil, nil
  end
  render()
end

function F.lock()
  local item = state and state.item
  if not item then return end
  send('lock', { path = item.path, id = item.id, on = not item.locked })
end

function F.change()
  send('clear')
end

-- an item dragged from a container onto the slot
local function onSlotDrop(self, widget, mousePos)
  local item = widget and widget.currentDragThing
  if not item or not item.isItem or not item:isItem() then return false end
  local pos = item:getPosition()
  if not pos or pos.x ~= 65535 then
    lastResult = { ok = false, text = tr('Only items from your backpack can go on the bench.') }
    renderBar()
    return true
  end
  lastResult = nil
  send('select', { pos = { x = pos.x, y = pos.y, z = pos.z }, clientId = item:getId() })
  return true
end

function F.onGameEnd()
  F.hide()
  state, lastExplain, requested, lastResult = nil, nil, nil, nil
  sel.orb, sel.mod, sel.tab = nil, nil, 'mod'
  pending, F.classicOnce = false, false
  if confirmBox then confirmBox:destroy() confirmBox = nil end
end

function F.init()
  fw = g_ui.displayUI('forge')
  fw:hide()
  pcall(function() modules.game_howitworks.attach(fw, 'crafting') end)
  -- the Chaos fonts (client_chaos_theme ChaosTheme.fonts): the item's name as in the item tooltip, the button's word
  local theme = modules.client_chaos_theme and modules.client_chaos_theme.ChaosTheme
  if theme and theme.applyFont then
    pcall(theme.applyFont, w('itemName'), 'subtitle')
    pcall(theme.applyFont, w('forgeButton'), 'title')
  end
  local slot = w('itemSlot')
  slot.onDrop = onSlotDrop
  slot.onMouseRelease = function(self, mousePos, button)
    if button == MouseRightButton and state and state.item then
      send('clear')
      return true
    end
    return false
  end
  connect(g_game, { onGameEnd = F.onGameEnd })
end

function F.terminate()
  disconnect(g_game, { onGameEnd = F.onGameEnd })
  if confirmBox then confirmBox:destroy() confirmBox = nil end
  if fw then
    fw:destroy()
    fw = nil
  end
  state, info, forgeInfo, lastExplain, lastResult = nil, nil, nil, nil, nil
end

-- what forge.otui and crafting.otui call (modules.game_crafting.X)
function forgeHide() F.hide() end
function forgeNow() F.forge() end
function forgeSwitchTo() F.switchTo() end
function forgeLock() F.lock() end
function forgeChange() F.change() end
function forgeTab(id) F.tab(id) end
