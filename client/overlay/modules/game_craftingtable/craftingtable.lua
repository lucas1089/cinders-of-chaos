-- Crafting Table window: the base server's crafting tables (data/scripts/customs/crafting/1crafting_mod.lua, extended
-- opcode 91, JSON; the protocol is described in craftingtableview.lua). Using a table makes the server send `show`
-- with its category: the window opens on that tab and asks for every page of recipes (10 per page). The other tabs can
-- be browsed; a craft is only accepted at a table of the recipe's category (server patch_base_crafting.py), so Craft is
-- off elsewhere and when the player walked away from where the table opened the window.
-- After `craft {success}` a bar runs for the server's 860 ms; the server's answer (`message`, server
-- patch_base_crafting_ui.py) is shown under the recipe, green or red. Craft x N sends the next request after the
-- previous one succeeded and the 1 s cooldown passed, and stops at the first refusal.
-- A recipe's `bonus` (server patch_base_crafting_bonus.py, at the player's skill) is shown under the gold line: the
-- rarity odds and item level of equipment, the extra-piece odds of potions and runes.
-- Skills: g_game.onCraftingSkill (base patch 0012), also read from game_craftskills. No menu entry (removed 2026-10-20); the tables open it
-- only explains where the tables are.

local V = CraftingTableView
local OPCODE = V.OPCODE
local TABLE_SECONDS = 290 -- the server keeps the table use 300 s

local window
local state = V.newState()
local current = 'herbalist'      -- the tab shown
local selected = {}              -- category -> recipe index
local mode = 'all'               -- list filter
local atTable, tableAt, tablePos -- the table's category, when (ms) and where the player stood
local skills = {}                -- index 0..6 -> level
local tips = {}                  -- tip key -> tooltip (false: the server has none)
local tipAsked = {}
local craft = nil                -- {recipe, startedAt, sentAt, left, lastStart}
local qty = 1
local events = {}
local handlers = {}
local reported = {}
local rows = {}                  -- recipe index -> row widget

local function nowMs() return g_clock.millis() end

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[craftingtable] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function cancelEvent(key)
  if events[key] then removeEvent(events[key]) events[key] = nil end
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode(V.request(action, data)))
  end
end

-- asks for the pages not received yet, each at most once in 3 s (the answers come one page at a time)
local asked = {} -- category -> page -> ms
local function fetchMissing(key)
  local a = asked[key] or {}
  asked[key] = a
  local t = nowMs()
  for _, p in ipairs(V.missingPages(state, key)) do
    if not a[p] or t - a[p] > 3000 then
      a[p] = t
      send('fetch', { category = key, page = p })
    end
  end
end

local function markStale(key)
  V.markStale(state, key)
  asked[key] = nil
end

-- ---------------------------------------------------------------- context
local function skillOf(key)
  local i = V.skillIndex(key)
  if not i then return nil end
  local cs = modules.game_craftskills
  if cs and type(rawget(cs, 'getSkill')) == 'function' then
    local ok, v = pcall(cs.getSkill, i)
    if ok and type(v) == 'table' and tonumber(v.level) then return tonumber(v.level) end
  end
  return skills[i]
end

local function isNear()
  if not tablePos then return false end
  local player = g_game.getLocalPlayer()
  local pos = player and player:getPosition()
  if not pos then return false end
  return pos.z == tablePos.z and math.abs(pos.x - tablePos.x) <= V.TABLE_RANGE
    and math.abs(pos.y - tablePos.y) <= V.TABLE_RANGE
end

local function tableCategory()
  if atTable and tableAt and nowMs() - tableAt <= TABLE_SECONDS * 1000 then return atTable end
  return nil
end

local function ctxFor(key)
  return { money = state.money, skill = skillOf(key), atTable = tableCategory(), near = isNear() }
end

local function selectedRecipe()
  local c = state.cats[current]
  local i = selected[current]
  return c and i and c.recipes[i] or nil
end

local function materialName(m)
  if m.name then return m.name end
  local ok, name = pcall(function()
    local t = g_things.getThingType(m.clientId, ThingCategoryItem)
    local md = t and t.getMarketData and t:getMarketData()
    return md and md.name ~= '' and md.name or nil
  end)
  return V.materialName(m, ok and name or nil)
end

-- ---------------------------------------------------------------- detail
local function setStatus(text, color)
  if not window then return end
  window.detail.status:setText(text or '')
  window.detail.status:setColor(color or V.COLORS.text)
end

local function setProgress(pct)
  if not window then return end
  local bar = window.detail.progress
  if pct == nil then
    bar:setVisible(false)
    return
  end
  bar:setVisible(true)
  bar:setPercent(pct)
end

local function renderDetail()
  if not window then return end
  local d = window.detail
  local r = selectedRecipe()
  d.matList:destroyChildren()
  if not r then
    d.resultSlot:setItemId(0)
    d.resultName:setText(tr('Choose a recipe'))
    d.resultSub:setText('')
    d.skillLine:setText('')
    d.goldLine:setText('')
    d.lockLine:setText('')
    d.bonusLine:setText('')
    d.matTitle:setVisible(false)
    d.craftButton:setEnabled(false)
    d.blockText:setText('')
    d.qtyLabel:setText('')
    d.qtyMinus:setEnabled(false)
    d.qtyPlus:setEnabled(false)
    return
  end
  local ctx = ctxFor(r.category)
  local check = V.check(r, ctx)
  local cat = V.category(r.category)
  d.resultSlot:setItemId(r.clientId)
  d.resultName:setText(r.name)
  d.resultSub:setText(tr('%s%s recipe %d', r.count > 1 and string.format('x%d  -  ', r.count) or '',
    cat and cat.name or '', r.index))
  local skillName = V.SKILL_NAMES[cat and cat.skill or 7]
  if ctx.skill then
    d.skillLine:setText(tr('%s skill: %d needed, yours %d', skillName, r.level, ctx.skill))
    d.skillLine:setColor(ctx.skill >= r.level and V.COLORS.good or V.COLORS.bad)
  else
    d.skillLine:setText(tr('%s skill: %d needed', skillName, r.level))
    d.skillLine:setColor(V.COLORS.text)
  end
  if state.money then
    d.goldLine:setText(tr('Gold: %s (you carry %s)', V.goldText(r.cost), V.goldText(state.money)))
    d.goldLine:setColor(state.money >= r.cost and V.COLORS.good or V.COLORS.bad)
  else
    d.goldLine:setText(tr('Gold: %s', V.goldText(r.cost)))
    d.goldLine:setColor(V.COLORS.text)
  end
  if r.locked then
    d.lockLine:setText(V.reasonText('locked', r, ctx))
    d.lockLine:setColor(V.COLORS.bad)
  else
    d.lockLine:setText('')
  end
  d.bonusLine:setText(V.bonusText(r))
  d.matTitle:setVisible(true)
  for i, m in ipairs(r.materials) do
    local w = g_ui.createWidget('CraftTableMaterial', d.matList)
    w.item:setItemId(m.clientId)
    local name = materialName(m)
    w.name:setText(name)
    w.item:setTooltip(name)
    w.count:setText(V.haveNeed(m))
    w.count:setColor(check.mats[i] and V.COLORS.good or V.COLORS.bad)
  end
  local max = V.maxCraftable(r, state.money)
  qty = V.clampQty(qty, max)
  local busy = craft ~= nil
  d.qtyLabel:setText(string.format('x %d', qty))
  d.qtyMinus:setEnabled(not busy and qty > 1)
  d.qtyPlus:setEnabled(not busy and qty < max)
  d.craftButton:setEnabled(check.ok and not busy)
  d.craftButton:setText(busy and tr('Crafting...') or (qty > 1 and tr('Craft x%d', qty) or tr('Craft')))
  d.blockText:setText(busy and '' or V.blockText(check, r, ctx))
end

-- ---------------------------------------------------------------- list
local function paintRow(w, r, ctx)
  local check = V.check(r, ctx)
  if r.locked then
    w.state:setText(tr('Locked'))
    w.state:setColor(V.COLORS.bad)
  elseif check.recipeOk then
    w.state:setText(tr('Ready'))
    w.state:setColor(V.COLORS.good)
  elseif ctx.skill and ctx.skill < r.level then
    w.state:setText(tr('Skill %d', r.level))
    w.state:setColor(V.COLORS.off)
  else
    w.state:setText(tr('Missing'))
    w.state:setColor(V.COLORS.warn)
  end
  local sel = selected[current] == r.index
  w:setBackgroundColor(sel and '#3a2a22' or '#1a151a')
  w.name:setColor(sel and V.COLORS.bright or V.COLORS.gold)
end

local function renderList()
  if not window then return end
  local list = window.recipeList
  list:destroyChildren()
  rows = {}
  local ctx = ctxFor(current)
  local all = V.recipes(state, current)
  local shown = V.filter(all, window.searchEdit:getText(), mode, ctx)
  if not selected[current] and shown[1] then
    selected[current] = shown[1].index
  end
  for _, r in ipairs(shown) do
    local w = g_ui.createWidget('CraftTableRow', list)
    w.item:setItemId(r.clientId)
    w.name:setText(r.name)
    w.sub:setText(V.rowSub(r))
    local index = r.index
    w.onClick = function()
      if selected[current] ~= index then
        selected[current] = index
        qty = 1
        if not craft then setStatus('') end
        for i, row in pairs(rows) do
          local rr = state.cats[current].recipes[i]
          if rr then paintRow(row, rr, ctx) end
        end
        renderDetail()
      end
      return true
    end
    rows[index] = w
    paintRow(w, r, ctx)
  end
  local empty = #shown == 0
  window.emptyText:setVisible(empty)
  if empty then
    if #all == 0 then
      window.emptyText:setText(tr('Loading...'))
    elseif mode == 'craftable' then
      window.emptyText:setText(tr('Nothing you can craft now.'))
    else
      window.emptyText:setText(tr('No recipe matches.'))
    end
  end
end

local function renderHeader()
  if not window then return end
  local cat = V.category(current)
  local at = tableCategory()
  local atCat = at and V.category(at)
  if at and isNear() then
    window.hint:setText(tr('You stand at the %s table. Materials and gold are counted in your backpack; a crafted item may roll a rarity.', atCat.name))
  elseif at then
    window.hint:setText(tr('You left the %s table: go back to it to craft.', atCat.name))
  else
    window.hint:setText(tr('Use a crafting table to craft. Each table crafts the recipes of its tab.'))
  end
  window.moneyLabel:setText(state.money and tr('Gold carried: %s', V.goldText(state.money)) or '')
  local s = skillOf(current)
  local name = V.SKILL_NAMES[cat and cat.skill or 7]
  window.skillLabel:setText(s and tr('%s skill: %d', name, s) or '')
  for _, c in ipairs(V.CATEGORIES) do
    local tab = window.tabBar:getChildById('tab_' .. c.key)
    if tab then
      tab:setChecked(c.key == current)
      tab:setText(c.name .. (c.key == at and ' *' or ''))
    end
  end
  window.filterAll:setChecked(mode == 'all')
  window.filterCraftable:setChecked(mode == 'craftable')
end

local function renderAll()
  renderHeader()
  renderList()
  renderDetail()
end

-- ---------------------------------------------------------------- crafting
local function stopCraft(text, color)
  cancelEvent('progress')
  cancelEvent('timeout')
  cancelEvent('next')
  craft = nil
  setProgress(nil)
  if text then setStatus(text, color) end
  renderDetail()
end

local function tickProgress()
  events.progress = nil
  if not craft or not craft.startedAt then return end
  local pct = V.progress(craft.startedAt, nowMs())
  setProgress(pct)
  if pct < 100 then
    events.progress = scheduleEvent(tickProgress, 40)
  end
end

local function sendCraft()
  if not craft then return end
  craft.sentAt = nowMs()
  craft.startedAt = nil
  send('craft', { category = craft.recipe.category, craftId = craft.recipe.index })
  setProgress(0)
  cancelEvent('timeout')
  events.timeout = scheduleEvent(function()
    events.timeout = nil
    if craft then stopCraft(tr('No answer from the server.'), V.COLORS.bad) end
  end, 5000)
end

function doCraft()
  local r = selectedRecipe()
  if not r or craft then return end
  local check = V.check(r, ctxFor(r.category))
  if not check.ok then
    setStatus(V.blockText(check, r, ctxFor(r.category)), V.COLORS.warn)
    return
  end
  craft = { recipe = r, left = qty, done = 0 }
  setStatus(tr('Crafting %s...', r.name), V.COLORS.text)
  sendCraft()
  renderDetail()
end

local function onAccepted()
  if not craft then return end
  craft.startedAt = nowMs()
  craft.lastStart = craft.sentAt
  cancelEvent('progress')
  tickProgress()
end

local function onCraftMessage(okMsg, text)
  local r = craft and craft.recipe or selectedRecipe()
  if r then
    -- the server sends the recipe's page again after a success; after a refusal the counts may have changed too
    if not okMsg then
      local p = V.pageOf(r.index)
      if asked[r.category] then asked[r.category][p] = nowMs() end
      send('fetch', { category = r.category, page = p })
    end
  end
  if not craft then
    setStatus(text, okMsg and V.COLORS.good or V.COLORS.bad)
    return
  end
  if not okMsg then
    local done = craft.done
    stopCraft(done > 0 and tr('%s (%d crafted before)', text, done) or text, V.COLORS.bad)
    return
  end
  craft.done = craft.done + 1
  craft.left = craft.left - 1
  setProgress(100)
  if craft.left <= 0 then
    local done = craft.done
    stopCraft(done > 1 and tr('%s (%d crafted)', text, done) or text, V.COLORS.good)
    return
  end
  setStatus(tr('%s (%d crafted, %d to go)', text, craft.done, craft.left), V.COLORS.good)
  cancelEvent('timeout')
  cancelEvent('next')
  events.next = scheduleEvent(function()
    events.next = nil
    if not craft then return end
    local again = state.cats[craft.recipe.category].recipes[craft.recipe.index] or craft.recipe
    local check = V.check(again, ctxFor(again.category))
    if not check.ok then
      stopCraft(tr('Stopped after %d: %s', craft.done, V.blockText(check, again, ctxFor(again.category))), V.COLORS.warn)
      return
    end
    craft.recipe = again
    sendCraft()
  end, V.repeatDelay(craft.lastStart, nowMs()))
end

-- ---------------------------------------------------------------- tooltip of the result
local function showResultTip(widget, hovered)
  local r = selectedRecipe()
  local tt = modules.game_itemtooltip
  if not hovered then
    if tt and tt.hideTip then pcall(tt.hideTip, widget) end
    return
  end
  if not r then return end
  local key = V.tipKey(r.category, r.index)
  local tip = tips[key]
  if tip and tt and tt.showTip then
    local b = V.bonusText(r)
    local extra = { { text = b ~= '' and b or tr('A crafted item may roll a rarity.'), color = V.COLORS.dim, sep = true } }
    pcall(tt.showTip, widget, key, tip, extra)
  elseif tip == nil and not tipAsked[key] then
    tipAsked[key] = true
    send('tip', { category = r.category, craftId = r.index })
  end
end

local function onTip(m)
  local key = V.tipKey(m.category, m.craftId)
  tips[key] = m.tip or false
  local r = selectedRecipe()
  if window and r and V.tipKey(r.category, r.index) == key then
    local slot = window.detail.resultSlot
    if not m.tip then slot:setTooltip(V.plainTip(r)) end
    if m.tip and slot:isHovered() then showResultTip(slot, true) end
  end
end

-- ---------------------------------------------------------------- server messages
local function selectTab(key)
  if not V.category(key) then return end
  if key ~= current and not craft then setStatus('') end
  current = key
  if not V.loaded(state, key) then fetchMissing(key) end
  if window then
    window.listScroll:setValue(0)
  end
  renderAll()
end

local function onShow(key)
  atTable, tableAt = key, nowMs()
  local player = g_game.getLocalPlayer()
  local pos = player and player:getPosition()
  tablePos = pos and { x = pos.x, y = pos.y, z = pos.z } or nil
  for k in pairs(state.cats) do markStale(k) end -- the counts are from earlier
  if window then
    window:show()
    window:raise()
    window:focus()
  end
  selectTab(key)
end

local function onFetch(data)
  local key = V.applyFetch(state, data)
  if not key then return end
  if key == current then
    renderList()
    renderDetail()
  end
  -- ask the next page once this one is in
  if key == current or key == atTable then fetchMissing(key) end
end

local function onMessage(protocol, opcode, msg)
  local m = V.parse(msg)
  if m.kind == 'chunk' then
    local text = V.addChunk(state, m.chunk)
    if text then
      local ok, full = pcall(json.decode, text)
      if ok then onMessage(protocol, opcode, full) end
    end
  elseif m.kind == 'fetch' then
    onFetch(m.data)
  elseif m.kind == 'show' then
    onShow(m.category)
  elseif m.kind == 'money' then
    state.money = m.money
    if window and window:isVisible() then renderAll() end
  elseif m.kind == 'accepted' then
    onAccepted()
  elseif m.kind == 'message' then
    onCraftMessage(m.ok, m.text)
  elseif m.kind == 'tip' then
    onTip(m)
  end
end

-- ---------------------------------------------------------------- window
function hide()
  if window then window:hide() end
  if craft then stopCraft(nil) end
end

function refresh()
  for k in pairs(state.cats) do markStale(k) end
  fetchMissing(current)
end

function setFilter(m)
  mode = m == 'craftable' and 'craftable' or 'all'
  renderHeader()
  renderList()
end

function changeQty(delta)
  qty = qty + delta
  renderDetail()
end

-- the menu entry: where the tables are (the window opens from a table)
function explain()
  -- the info box does not wrap: one line per row
  local text = tr('The crafting tables stand in the crafting hall, around x %d, y %d.\n'
    .. 'Top floor (z 4): general crafting, jewelsmith, armorsmith and weaponsmith.\n'
    .. 'Floor below (z 5): mining. Lowest floor (z 6): woodcutting and herbalist.\n\n'
    .. 'Use a table to open its recipes: the materials you carry, the gold and the skill\n'
    .. 'each one needs. Stand next to the table while you craft.', 31650, 32233)
  displayInfoBox(tr('Crafting Tables'), text)
end

-- for checks and other modules
function getState()
  local r = selectedRecipe()
  return { visible = window and window:isVisible() or false, category = current, atTable = tableCategory(),
    recipes = #V.recipes(state, current), selected = r and r.index or nil, money = state.money,
    crafting = craft ~= nil, status = window and window.detail.status:getText() or '' }
end

function selectRecipe(index)
  if state.cats[current] and state.cats[current].recipes[index] then
    selected[current] = index
    qty = 1
    renderAll()
  end
end

function search(text)
  if window then window.searchEdit:setText(text or '') end
end

function openTab(key) selectTab(key) end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    local ok, avail = pcall(function() return api.available and api.available() or {} end)
    for _, text in ipairs(ok and avail.economy or {}) do
      if text == 'Crafting Tables' then handlers.menu = true return end
    end
    handlers.menu = pcall(api.addEntry, 'economy',
      { text = 'Crafting Tables', icon = 'skills', modules = { 'game_craftingtable' }, fns = { 'explain' } })
  end
end

local function onCraftingSkill(index, level)
  skills[index] = tonumber(level)
  if window and window:isVisible() then renderHeader() renderDetail() end
end

local function onPositionChange()
  if window and window:isVisible() and atTable then
    renderHeader()
    renderDetail()
  end
end

local function onGameStart()
  state = V.newState()
  asked = {}
  tips, tipAsked, selected, skills = {}, {}, {}, {}
  atTable, tableAt, tablePos = nil, nil, nil
  -- no Economy > Crafting Tables entry (owner 2026-10-20: it only said where the tables are): addMenu() is not called
end

local function onGameEnd()
  hide()
  state = V.newState()
  asked = {}
end

local function buildTabs()
  for _, c in ipairs(V.CATEGORIES) do
    local tab = g_ui.createWidget('CraftTableTab', window.tabBar)
    tab:setId('tab_' .. c.key)
    tab:setText(c.name)
    local key = c.key
    tab.onClick = safe('tab', function() selectTab(key) end)
  end
  local first = window.tabBar:getChildByIndex(1)
  if first then first:setMarginLeft(0) end
end

function init()
  local ok, ui = pcall(g_ui.displayUI, 'craftingtable')
  if ok and ui then
    window = ui
    window:hide()
    buildTabs()
    window.searchEdit.onTextChange = safe('search', function(_, text)
      window.searchHint:setVisible((text or '') == '')
      renderList()
    end)
    window.filterAll.onClick = safe('filter', function() setFilter('all') end)
    window.filterCraftable.onClick = safe('filter', function() setFilter('craftable') end)
    local d = window.detail
    d.craftButton.onClick = safe('craft', doCraft)
    d.qtyMinus.onClick = safe('qty', function() changeQty(-1) end)
    d.qtyPlus.onClick = safe('qty', function() changeQty(1) end)
    d.resultSlot.onHoverChange = safe('tip', showResultTip)
    renderAll()
  else
    g_logger.warning('[craftingtable] window not loaded: ' .. tostring(ui))
  end
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd),
    onCraftingSkill = safe('skill', onCraftingSkill) }
  handlers.player = { onPositionChange = safe('position', onPositionChange) }
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, safe('opcode', onMessage))
  connect(g_game, handlers.game)
  connect(LocalPlayer, handlers.player)
  -- no Economy > Crafting Tables entry (owner 2026-10-20: it only said where the tables are): addMenu() is not called
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game)
  disconnect(LocalPlayer, handlers.player)
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  for k in pairs(events) do cancelEvent(k) end
  if window then window:destroy() window = nil end
  craft, handlers = nil, {}
end
