-- Depot tabs: the logic without client API (tested by depottabsview_test.lua).
-- The server (data/scripts/chaos/depot.lua) sends on extended opcode 111:
--   tabs {tabs, max, size, used = [n per tab] (missing: keep the last counts), ids = [client id per tab],
--         chest = [client ids of the depot chest], lockers = [client ids], inbox, market, hint, store,
--         names = [per tab], colors = [palette key per tab], palette = [{key, name, color}], nameMax, town}
--   open {tab, ok, text}   the answer to the window's open request
-- Tab n is the box with client id ids[n]; tabs above `tabs` are locked (withdraw-only).
-- The depot window (depottabs.lua, depottabs.otui): the tab buttons, the 10x10 grid of the active tab, the footer, the
-- rename / colour dialog, and which opened container plays which part (locker, chest, tab).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

DepotTabsView = {}
local V = DepotTabsView

V.LOCKED_OPACITY = 0.4
V.TAB_COLUMNS = 6 -- tab buttons per row (17 tabs and the store button: 3 rows)
V.TAB_W, V.TAB_H, V.TAB_GAP = 60, 22, 2
V.GRID_COLUMNS = 10 -- item slots per row of the grid (100 items: 10 rows)
V.SLOT, V.SLOT_GAP = 34, 2
V.COLORS = { text = '#d6c9ae', dim = '#8c8070', gold = '#e8b84a', bright = '#f6cf72', warn = '#e03a1e',
  full = '#d08040', locked = '#8a8a8a' }

local function int(v)
  v = tonumber(v) or 0
  if v ~= v then return 0 end
  return math.floor(v)
end

function V.newState()
  return { tabs = 0, max = 0, size = 100, used = {}, byId = {}, ids = {}, chest = {}, lockers = {}, inbox = 0, market = 0,
    hint = '', store = 'Depot Tabs', names = {}, colors = {}, palette = {}, paletteByKey = {}, nameMax = 16, town = '' }
end

-- merges one server message into the state (a message without `used` keeps the last counts, one without `names` the
-- last names and colours)
function V.apply(state, d)
  state = state or V.newState()
  if type(d) ~= 'table' then return state end
  if d.tabs ~= nil then state.tabs = int(d.tabs) end
  if d.max ~= nil then state.max = int(d.max) end
  state.size = int(d.size) > 0 and int(d.size) or state.size
  if type(d.hint) == 'string' then state.hint = d.hint end
  -- '' = tabs are not sold now (the depot is withdraw-only): no store button
  if type(d.store) == 'string' then state.store = d.store end
  if type(d.town) == 'string' then state.town = d.town end
  if int(d.nameMax) > 0 then state.nameMax = int(d.nameMax) end
  if int(d.inbox) > 0 then state.inbox = int(d.inbox) end
  if int(d.market) > 0 then state.market = int(d.market) end
  if type(d.ids) == 'table' then
    state.byId, state.ids = {}, {}
    for i, id in ipairs(d.ids) do
      state.byId[int(id)] = i
      state.ids[i] = int(id)
    end
  end
  if type(d.chest) == 'table' then
    state.chest = {}
    for _, id in ipairs(d.chest) do state.chest[int(id)] = true end
  end
  if type(d.lockers) == 'table' then
    state.lockers = {}
    for _, id in ipairs(d.lockers) do state.lockers[int(id)] = true end
  end
  if type(d.used) == 'table' then
    state.used = {}
    for i, n in ipairs(d.used) do state.used[i] = int(n) end
  end
  if type(d.palette) == 'table' then
    state.palette, state.paletteByKey = {}, {}
    for _, p in ipairs(d.palette) do
      if type(p) == 'table' and type(p.key) == 'string' and type(p.color) == 'string' then
        local entry = { key = p.key, name = tostring(p.name or p.key), color = p.color }
        state.palette[#state.palette + 1] = entry
        state.paletteByKey[p.key] = entry
      end
    end
  end
  if type(d.names) == 'table' then
    state.names = {}
    for i, n in ipairs(d.names) do state.names[i] = type(n) == 'string' and n or '' end
  end
  if type(d.colors) == 'table' then
    state.colors = {}
    for i, c in ipairs(d.colors) do state.colors[i] = type(c) == 'string' and c or '' end
  end
  return state
end

function V.known(state)
  return state ~= nil and next(state.byId) ~= nil
end

function V.tabOf(state, clientId)
  return state and state.byId[int(clientId)] or nil
end

function V.isChest(state, clientId)
  return state ~= nil and state.chest[int(clientId)] == true
end

function V.isLocker(state, clientId)
  return state ~= nil and state.lockers[int(clientId)] == true
end

function V.isLocked(state, tab)
  return int(tab) > int(state.tabs)
end

-- ---------------------------------------------------------------- names and colours
function V.customName(state, tab)
  local n = state.names[int(tab)]
  if type(n) == 'string' and n ~= '' then return n end
  return nil
end

-- "Potions", or "Tab 3" for a tab without a name
function V.tabName(state, tab)
  return V.customName(state, tab) or string.format('Tab %d', int(tab))
end

-- the colour of a tab's accent (#rrggbb), nil for the default
function V.accent(state, tab)
  local key = state.colors[int(tab)]
  local p = key and state.paletteByKey[key]
  return p and p.color or nil
end

-- the text of a tab button: the number, or the name cut to `maxChars` characters ("Potions", "Runes and..")
function V.buttonText(state, tab, maxChars)
  local name = V.customName(state, tab)
  if not name then return tostring(int(tab)) end
  maxChars = int(maxChars) > 2 and int(maxChars) or 8
  if #name <= maxChars then return name end
  return name:sub(1, maxChars - 2):gsub(' +$', '') .. '..'
end

-- the name a player typed, as the server will store it ("" = default); nil and the reason when the server would refuse
-- it (the server checks again: depot_core.lua cleanName)
function V.cleanName(state, raw)
  if raw == nil then return '' end
  if type(raw) ~= 'string' then return nil, tr('Not a name.') end
  local s = raw:gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
  if s:find('[%c\127-\159]') then
    return nil, tr('A tab name may only use letters, digits, spaces and punctuation.')
  end
  if #s > state.nameMax then
    return nil, tr('A tab name has at most %d characters.', state.nameMax)
  end
  return s
end

-- the colour choices of the dialog: the default first, then the palette
function V.colorChoices(state)
  local list = { { key = '', name = 'Default', color = nil } }
  for _, p in ipairs(state.palette) do list[#list + 1] = p end
  return list
end

-- a local change before the server's answer (the server's tab list replaces it)
function V.setStyle(state, tab, name, color)
  tab = int(tab)
  if tab < 1 or tab > math.max(int(state.max), #state.ids) then return false end
  state.names[tab] = name or ''
  state.colors[tab] = (color and state.paletteByKey[color]) and color or ''
  for t = 1, tab - 1 do
    state.names[t] = state.names[t] or ''
    state.colors[t] = state.colors[t] or ''
  end
  return true
end

-- ---------------------------------------------------------------- titles, tooltips, footer
-- the window title of a tab (a stock window, or the box's own title): "Tab 3 (87/100)", "Potions (locked)"
function V.title(state, tab)
  local name = V.tabName(state, tab)
  if V.isLocked(state, tab) then
    return string.format('%s (locked)', name)
  end
  local used = state.used[int(tab)]
  if used == nil then
    return name
  end
  return string.format('%s (%d/%d)', name, used, state.size)
end

-- the tooltip of a tab (a tab button, or a box in a stock depot chest window)
function V.tooltip(state, tab)
  local used = state.used[int(tab)]
  local name = V.customName(state, tab)
  local head = name and string.format('Tab %d: %s\n', int(tab), name) or ''
  if V.isLocked(state, tab) then
    local inside = (used and used > 0) and tr('%d items inside: you can take them out.\n', used) or ''
    return tr('%sTab %d is locked (your account has %d of %d tabs).\n%s%s', head, int(tab), state.tabs,
      state.max, inside, state.hint ~= '' and state.hint or tr('Buy more tabs in the Store.'))
  end
  if used == nil then
    return tr('%sTab %d: up to %d items (a bag counts with its contents).', head, int(tab), state.size)
  end
  return tr('%sTab %d: %d of %d items (a bag counts with its contents).', head, int(tab), used, state.size)
end

-- the title colour of a full or locked tab (nil: leave the default)
function V.titleColor(state, tab)
  if V.isLocked(state, tab) then return V.COLORS.locked end
  local used = state.used[int(tab)]
  if used and used >= state.size then return V.COLORS.full end
  return nil
end

function V.windowTitle(state)
  if state.town ~= '' then return state.town .. ' Depot' end
  return 'Depot'
end

-- the line above the grid: "Tab 3: Potions" / "Tab 3", and the lock note
function V.header(state, tab)
  if not tab then return tr('Opening the depot...') end
  local name = V.customName(state, tab)
  local text = name and string.format('Tab %d: %s', int(tab), name) or string.format('Tab %d', int(tab))
  if V.isLocked(state, tab) then text = tr('%s  (locked: withdraw only)', text) end
  return text
end

-- {items = "87/100 items", itemsColor, tabs = "8 of 17 tabs"}
function V.footer(state, tab)
  local out = { tabs = string.format('%d of %d tabs', int(state.tabs), int(state.max)), itemsColor = V.COLORS.text }
  local used = tab and state.used[int(tab)]
  if not tab or used == nil then
    out.items = string.format('-/%d items', state.size)
  else
    out.items = string.format('%d/%d items', used, state.size)
    if used >= state.size then out.itemsColor = V.COLORS.full end
  end
  if tab and V.isLocked(state, tab) then out.itemsColor = V.COLORS.locked end
  return out
end

-- does the store sell depot tabs now (the server sends store = '' while the depot is withdraw-only)
function V.storeSells(state)
  return type(state and state.store) == 'string' and state.store ~= ''
end

-- ---------------------------------------------------------------- layout
-- the tab buttons: {tab = n | 'store', x, y} in rows of TAB_COLUMNS; the store button follows the last tab while some
-- tab can still be bought (and the store sells tabs: store ~= '')
function V.tabCells(state)
  local cells = {}
  local count = math.max(int(state.max), #state.ids)
  for t = 1, count do cells[#cells + 1] = { tab = t } end
  if int(state.tabs) < count and V.storeSells(state) then cells[#cells + 1] = { tab = 'store' } end
  for i, c in ipairs(cells) do
    local col = (i - 1) % V.TAB_COLUMNS
    local row = math.floor((i - 1) / V.TAB_COLUMNS)
    c.col, c.row = col, row
    c.x = col * (V.TAB_W + V.TAB_GAP)
    c.y = row * (V.TAB_H + V.TAB_GAP)
  end
  return cells
end

-- the size of the tab block and of the item grid (w, h in pixels; rows)
function V.blockSize(state)
  local cells = V.tabCells(state)
  local rows = math.max(1, math.ceil(#cells / V.TAB_COLUMNS))
  local tabsW = V.TAB_COLUMNS * V.TAB_W + (V.TAB_COLUMNS - 1) * V.TAB_GAP
  local tabsH = rows * V.TAB_H + (rows - 1) * V.TAB_GAP
  local gridRows = math.max(1, math.ceil(int(state.size) / V.GRID_COLUMNS))
  local gridW = V.GRID_COLUMNS * V.SLOT + (V.GRID_COLUMNS - 1) * V.SLOT_GAP
  local gridH = gridRows * V.SLOT + (gridRows - 1) * V.SLOT_GAP
  return { tabsW = tabsW, tabsH = tabsH, tabRows = rows, gridW = gridW, gridH = gridH, gridRows = gridRows }
end

-- how a tab button looks: {text, checked, locked, opacity, accent, tooltip}; maxChars: of the name (default 7, 5 locked).
-- measure (optional): text -> pixel width in the button's font; the name is then also cut until it fits the label
-- (V.LABEL_W: open, or left of the lock).
V.LABEL_W = { open = 52, locked = 43 } -- TAB_W less the padding; locked: also the lock, with 3 px of the left padding

function V.fitText(state, tab, maxChars, width, measure)
  local text = V.buttonText(state, tab, maxChars)
  if not measure or not V.customName(state, tab) then return text end
  local n = maxChars
  while n > 3 and measure(text) > width do
    n = n - 1
    text = V.buttonText(state, tab, n)
  end
  return text
end

function V.button(state, tab, active, maxChars, measure)
  local locked = V.isLocked(state, tab)
  maxChars = maxChars or (locked and 5 or 7) -- a locked button also shows the lock
  local text = V.fitText(state, tab, maxChars, locked and V.LABEL_W.locked or V.LABEL_W.open, measure)
  return { text = text, checked = int(tab) == int(active), locked = locked,
    opacity = (locked and int(tab) ~= int(active)) and 0.7 or 1, accent = V.accent(state, tab),
    tooltip = V.tooltip(state, tab) }
end

-- a coloured tab: its colour fills the button as a translucent tint over the iron plate (V.PLATE), stronger when hovered
-- and strongest on the active tab. The text is dark on a light tint and light on a dark one (the relative luminance of
-- the tint over the plate against V.DARK_TEXT_ABOVE), with a shadow; hovering does not switch it.
V.PLATE = '#332c33' -- the middle of the tab_normal plate
V.FILL_ALPHA = { normal = 0x80, hover = 0x9c, active = 0xd0 }
V.DARK_TEXT_ABOVE = 0.2
V.TEXT_ON_FILL = { dark = '#1c1612', light = '#f6ecd6' }

local function rgb(hex)
  if type(hex) ~= 'string' then return nil end
  local r, g, b = hex:match('^#(%x%x)(%x%x)(%x%x)')
  if not r then return nil end
  return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

local function linear(c)
  c = c / 255
  if c <= 0.04045 then return c / 12.92 end
  return ((c + 0.055) / 1.055) ^ 2.4
end

-- the relative luminance (0..1) of `hex` drawn with `alpha` (0..255) over the plate
function V.tintLuminance(hex, alpha)
  local r, g, b = rgb(hex)
  if not r then return nil end
  local pr, pg, pb = rgb(V.PLATE)
  local a = (tonumber(alpha) or 255) / 255
  local function mix(c, p) return linear(c * a + p * (1 - a)) end
  return 0.2126 * mix(r, pr) + 0.7152 * mix(g, pg) + 0.0722 * mix(b, pb)
end

-- the colours of a tab button: {fill = '#rrggbbaa' | nil, text, shadow}
function V.buttonColors(state, tab, active, hovered)
  local checked = int(tab) == int(active)
  local accent = V.accent(state, tab)
  if not accent then
    local text = checked and V.COLORS.bright or (hovered and V.COLORS.text)
      or (V.isLocked(state, tab) and V.COLORS.locked or V.COLORS.dim)
    return { fill = nil, text = text, shadow = false }
  end
  local alpha = checked and V.FILL_ALPHA.active or (hovered and V.FILL_ALPHA.hover or V.FILL_ALPHA.normal)
  local dark = V.tintLuminance(accent, checked and V.FILL_ALPHA.active or V.FILL_ALPHA.normal) > V.DARK_TEXT_ABOVE
  return { fill = accent:sub(1, 7) .. string.format('%02x', alpha),
    text = dark and V.TEXT_ON_FILL.dark or V.TEXT_ON_FILL.light, shadow = not dark }
end

-- ---------------------------------------------------------------- which part an opened container plays
-- info = {clientId (of the container's item), holdsChest (the container holds a depot chest), id (container id),
--         pendingChest, pendingTab (ids the window asked for), windowOpen}
-- -> 'locker' | 'chest' | 'tab' | nil (a stock window)
function V.classify(state, info)
  if not V.known(state) or type(info) ~= 'table' then return nil end
  local cid = int(info.clientId)
  if V.tabOf(state, cid) and (info.windowOpen or (info.pendingTab ~= nil and info.id == info.pendingTab)) then
    return 'tab'
  end
  if V.isChest(state, cid) then return 'chest' end
  if V.isLocker(state, cid) or info.holdsChest then return 'locker' end
  return nil
end

-- the tab the window opens first: the last one used, else tab 1
function V.firstTab(state, last)
  last = int(last)
  if last >= 1 and last <= math.max(int(state.max), #state.ids) then return last end
  return 1
end
