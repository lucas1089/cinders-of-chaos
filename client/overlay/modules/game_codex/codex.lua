-- Codex: an in-client encyclopedia of the item system. Tabs (Modifiers, Powers, Orbs, Gems, Uniques, Rift, Supports,
-- Basics), a search box (every word must be in the name or the page), the tab's filters (side, item kind, item level,
-- level, group...), the list on the left and the page of the chosen entry on the right.
-- No server round trip: everything comes from codex_data.lua, generated from the server's data files by
-- server/tools/gen_codex_data.lua (CI fails when it is stale). The logic without client API is codexview.lua.
--
-- codex_data.lua: CodexData = {rarities, tierLevels, tierWeights, tierWindow, shared = {ref -> section},
--   tabs = [{id, name, filters = [{key, label, match = "eq"|"has"|"max"|"ilvl", options = [{value, text}]}],
--            entries = [{id, name, color, sub, f = {filter key -> value}, tiers, tv, sections}]}]}
--   section = {h, p = [paragraphs], cols = [names], w = [relative widths], rows = [[cells]], links = [entry id | ""],
--              tiers = true (rows are T1..T8: the item level filter marks the ones that roll)} | {ref = shared key}
-- Opened from the top menu (Economy > Codex, Alt+K) and from the crafting bench (right-click a modifier: open(id)).
-- Every text wraps; the tooltips are broken into lines with SupportsText.wrap (game_spellsupports/supportstext.lua).

local theme -- ChaosTheme of client_chaos_theme (fonts), set in init
local window
local data
local tabIndex = 1
local values = {}       -- tab id -> {filter key -> value}
local queries = {}      -- tab id -> search text
local selected = {}     -- tab id -> entry id
local tabButtons = {}
local listRows = {}     -- entry id -> list row
local history = {}      -- entry ids opened by links (Backspace / right-click goes back)
local searchEvent
local updating = false

local ROW_BG = '#00000000'
local ROW_ALT = '#ffffff08'
local ROW_HEAD = '#e8b84a1a'
local ROW_MARK = '#f6cf7230'
local SELECT_TINT = '#f6cf72'

local okText, Text = pcall(dofile, '/modules/game_spellsupports/supportstext.lua')
if not okText or type(Text) ~= 'table' then Text = nil end

local TIP_CHARS = 64
local function tipText(text)
  text = tostring(text or '')
  if not Text then return text end
  local out = {}
  for line in (text .. '\n'):gmatch('(.-)\n') do
    out[#out + 1] = Text.wrap(line, TIP_CHARS, '  ')
  end
  return table.concat(out, '\n')
end

local function currentTab()
  return data and data.tabs[tabIndex]
end

-- the box ends `bottom` pixels below the lowest of `children`, at least `minHeight` high
local function followHeight(box, children, bottom, minHeight)
  local function fit()
    if box:isDestroyed() then return end
    local low = box:getY()
    for _, c in ipairs(children) do
      if not c:isDestroyed() and c:isVisible() then low = math.max(low, c:getY() + c:getHeight()) end
    end
    local h = math.max(minHeight or 0, low - box:getY() + (bottom or 0))
    if h ~= box:getHeight() then box:setHeight(h) end
  end
  -- the wrapped labels settle their height and place over several layout passes: fit now and once more after them
  local function later()
    fit()
    if box.fitPending then return end
    box.fitPending = true
    addEvent(function()
      box.fitPending = false
      fit()
    end)
  end
  for _, c in ipairs(children) do connect(c, { onGeometryChange = later }) end
  connect(box, { onGeometryChange = later })
  later()
end

-- ---------------------------------------------------------------- the page
local function clearPage()
  window.page:destroyChildren()
  window.pageTitle:setText('')
  window.pageSub:setText('')
end

local function linkName(id)
  local _, e = CodexView.find(data, id)
  return e and e.name or id
end

-- a table: cells placed by the relative widths, each row as high as its tallest cell
local function addTable(section, entry, level)
  local page = window.page
  local marks = CodexView.highlight(section, entry, level, data)
  local function makeRow(cells, kind, index, link)
    local row = g_ui.createWidget('CodexTableRow', page)
    local labels = {}
    for i, text in ipairs(cells) do
      local cell = g_ui.createWidget('CodexCell', row)
      cell:setText(text)
      if kind == 'head' then
        cell:setColor('#c8a85a')
      elseif i == 1 and link then
        cell:setColor('#7fa8ff')
      elseif kind == 'mark' then
        cell:setColor('#f6cf72')
      end
      labels[i] = cell
    end
    row:setBackgroundColor(kind == 'head' and ROW_HEAD or kind == 'mark' and ROW_MARK or (index % 2 == 0 and ROW_ALT or ROW_BG))
    local function place()
      if row:isDestroyed() then return end
      local width = row:getWidth()
      if width <= 1 or width == row.placedWidth then return end
      row.placedWidth = width
      local widths = CodexView.columns(section.w or {}, width - 8, 8)
      local x = 4
      for i, cell in ipairs(labels) do
        cell:setMarginLeft(x)
        cell:setWidth(widths[i] or 1)
        x = x + (widths[i] or 1) + 8
      end
    end
    connect(row, { onGeometryChange = place })
    followHeight(row, labels, 3, 16)
    place()
    if link and link ~= '' then
      row:setPhantom(false)
      row:setTooltip(tipText(tr('Open %s in the Codex.', linkName(link))))
      row.onClick = function() modules.game_codex.open(link, true) end
    end
    return row
  end
  local cols = section.cols or {}
  if table.concat(cols) ~= '' then makeRow(cols, 'head', 0) end
  for i, cells in ipairs(section.rows or {}) do
    local link = section.links and section.links[i]
    makeRow(cells, marks[i] and 'mark' or 'row', i, link ~= '' and link or nil)
  end
end

local function showEntry(entry)
  clearPage()
  if not entry then
    window.pageTitle:setText(tr('Nothing to show'))
    return
  end
  local tab = currentTab()
  local level = CodexView.levelOf(values[tab.id], tab.filters)
  window.pageTitle:setText(entry.name)
  if entry.color then window.pageTitle:setColor(entry.color) else window.pageTitle:setColor('#f6cf72') end
  window.pageSub:setText(CodexView.subline(entry, level, data))
  local page = window.page
  for _, raw in ipairs(entry.sections or {}) do
    local s = CodexView.section(raw, data.shared)
    if s then
      if s.h and s.h ~= '' then
        local head = g_ui.createWidget('CodexHeading', page)
        if theme then theme.applyFont(head, 'heading') end
        head:setText(s.h)
      end
      for _, p in ipairs(s.p or {}) do
        local label = g_ui.createWidget('CodexParagraph', page)
        label:setText(p)
      end
      if s.rows then
        addTable(s, entry, level)
        if s.tiers and level then
          local note = g_ui.createWidget('CodexParagraph', page)
          note:setColor('#8c8070')
          local ch = CodexView.tierChances(level, data)
          local parts = {}
          for _, r in ipairs(CodexView.tierRows(level, data)) do parts[#parts + 1] = string.format('T%d %s%%', r[1], ch[r[1]]) end
          note:setText(tr('Marked: the tiers that roll at item level %d (%s).', level, table.concat(parts, ', ')))
        end
      elseif s.links then
        for _, id in ipairs(s.links) do
          local link = g_ui.createWidget('CodexLink', page)
          link:setText(tr('See: %s', linkName(id)))
          link.onClick = function() modules.game_codex.open(id, true) end
        end
      end
    end
  end
  window.pageScroll:setValue(0)
end

-- ---------------------------------------------------------------- the list
local function markSelected()
  local tab = currentTab()
  for id, row in pairs(listRows) do
    if not row:isDestroyed() then
      local on = selected[tab.id] == id
      row:setImageColor(on and SELECT_TINT or '#ffffff')
      row:setBorderWidth(on and 1 or 0)
      row:setBorderColor('#e8b84a')
    end
  end
end

local function selectEntry(entry, keepScroll)
  local tab = currentTab()
  selected[tab.id] = entry and entry.id or nil
  markSelected()
  showEntry(entry)
  local row = entry and listRows[entry.id]
  if row and not keepScroll then
    -- after the rows above it took their wrapped height
    window.entryList:ensureChildVisible(row)
    scheduleEvent(function()
      if window and not row:isDestroyed() then window.entryList:ensureChildVisible(row) end
    end, 80)
  end
end

local function refreshList(keepScroll)
  local tab = currentTab()
  if not tab then return end
  window.entryList:destroyChildren()
  listRows = {}
  local level = CodexView.levelOf(values[tab.id], tab.filters)
  local list = CodexView.list(tab, queries[tab.id], values[tab.id], data.shared)
  for _, e in ipairs(list) do
    local row = g_ui.createWidget('CodexListRow', window.entryList)
    row.name:setText(e.name)
    if e.color then row.name:setColor(e.color) end
    row.sub:setText(CodexView.subline(e, level, data))
    row.entryId = e.id
    followHeight(row, { row.name, row.sub }, 4, 34)
    row.onClick = function() history = {}; selectEntry(e, true) end
    listRows[e.id] = row
  end
  window.countLabel:setText(tr('%d of %d', #list, #tab.entries))
  window.emptyLabel:setVisible(#list == 0)
  -- keep the chosen entry when it is still in the list, else the first one
  local keep
  for _, e in ipairs(list) do
    if e.id == selected[tab.id] then keep = e end
  end
  selectEntry(keep or list[1], keepScroll)
  if not keepScroll and not keep then window.listScroll:setValue(0) end
end

-- ---------------------------------------------------------------- filters and tabs
local function buildFilters()
  local tab = currentTab()
  local bar = window.filterBar
  bar:destroyChildren()
  values[tab.id] = values[tab.id] or {}
  local n = #tab.filters
  if n == 0 then return end
  local width = math.min(150, math.floor((bar:getWidth() - 6 * (n - 1)) / n))
  updating = true
  for _, f in ipairs(tab.filters) do
    local combo = g_ui.createWidget('ChaosComboBox', bar)
    combo:setWidth(width)
    combo:setTooltip(tipText(f.label))
    local current = 1
    for i, o in ipairs(f.options) do
      combo:addOption(o[2], o[1])
      if o[1] == (values[tab.id][f.key] or '') then current = i end
    end
    combo:setCurrentIndex(current)
    combo.onOptionChange = function(widget, text, value)
      if updating then return end
      values[tab.id][f.key] = value or ''
      refreshList()
    end
  end
  updating = false
end

local function showTab(index, keepSelection)
  if not data or not data.tabs[index] then return end
  tabIndex = index
  for i, b in ipairs(tabButtons) do b:setChecked(i == index) end
  local tab = currentTab()
  updating = true
  window.searchEdit:setText(queries[tab.id] or '')
  updating = false
  window.searchHint:setVisible((queries[tab.id] or '') == '')
  buildFilters()
  refreshList(keepSelection)
end

local function onSearch(widget, text)
  window.searchHint:setVisible(text == '')
  if updating then return end
  local tab = currentTab()
  queries[tab.id] = text
  removeEvent(searchEvent)
  searchEvent = scheduleEvent(function() searchEvent = nil refreshList() end, 150)
end

-- ---------------------------------------------------------------- public
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
  if window:isVisible() then hide() else show() end
end

-- open the page of an entry id ("mod:chaos_mod_attackspeed", "orb:ruin", "unique:8209"); fromLink keeps a way back
function open(id, fromLink)
  if not window or not data then return false end
  local index, entry = CodexView.find(data, id)
  if not index then return false end
  local tab = data.tabs[index]
  if fromLink then
    local cur = currentTab()
    if cur and selected[cur.id] then history[#history + 1] = { tab = tabIndex, id = selected[cur.id] } end
  end
  -- make sure the entry is in the list: clear the search and the filters that hide it
  local words = CodexView.tokens(queries[tab.id])
  if not CodexView.matches(entry, tab.filters, values[tab.id], words, data.shared) then
    queries[tab.id] = ''
    values[tab.id] = {}
  end
  selected[tab.id] = id
  showTab(index)
  show()
  return true
end

-- a modifier as the crafting bench sends it (attribute key, group); false when the Codex has no page for it
function openModifier(key, group)
  local id = data and CodexView.idForMod(key, group, data)
  return id ~= nil and open(id) or false
end

function back()
  local last = table.remove(history)
  if not last then return false end
  local tab = data.tabs[last.tab]
  selected[tab.id] = last.id
  showTab(last.tab)
  return true
end

local function onGameEnd()
  hide()
end

function init()
  data = CodexData
  window = g_ui.displayUI('codex')
  window:hide()
  -- the optional Fontin fonts (client_chaos_theme ChaosTheme.fonts): the page title and the section headings
  theme = modules.client_chaos_theme and modules.client_chaos_theme.ChaosTheme
  if theme and theme.applyFont then theme.applyFont(window.pageTitle, 'subtitle') else theme = nil end
  if not data then
    window.pageTitle:setText(tr('The Codex data is missing (codex_data.lua).'))
    return
  end
  for i, tab in ipairs(data.tabs) do
    local b = g_ui.createWidget('ChaosTabButton', window.tabBar)
    b:setText(tab.name)
    b:setTooltip(tipText(tr('%d entries', #tab.entries)))
    b.onClick = function() history = {}; showTab(i) end
    tabButtons[i] = b
  end
  window.searchEdit.onTextChange = onSearch
  -- Backspace goes back. The search box has the focus whenever the Codex is open (show), so it gets the key first:
  -- while it is empty (nothing to delete) Backspace goes back from there too
  local function onBackspace(widget, keyCode)
    if keyCode ~= KeyBackspace then return false end
    local search = window.searchEdit
    if search:isFocused() and search:getText() ~= '' then return false end
    return back()
  end
  window.onKeyDown = onBackspace
  window.searchEdit.onKeyDown = function(widget, keyCode)
    if keyCode == KeyBackspace and widget:getText() == '' then return back() end
    return false
  end
  window.page.onMouseRelease = function(widget, mousePos, button)
    if button == MouseRightButton then return back() end
    return false
  end
  showTab(1)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  removeEvent(searchEvent)
  searchEvent = nil
  if window then
    window:destroy()
    window = nil
  end
  tabButtons, listRows, history = {}, {}, {}
end
