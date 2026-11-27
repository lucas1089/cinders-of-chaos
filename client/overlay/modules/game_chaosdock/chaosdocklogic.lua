-- The side dock (O732, owner 2026-11-23, option A of the UI mockups): pure rules, no engine calls. chaosdock.lua draws the
-- panel and moves the windows; chaosdock_test.lua runs this file in the client loop (LuaJIT and Lua 5.3).
-- A tab holds the windows of menu entries (the text ChaosTopBar.addEntry gives them). An entry of a tab opens the dock on
-- that tab instead of a floating window; a tab with two or more windows shows one at a time, picked by a small tab row.
-- O755 (owner 2026-11-24, "do tamanho de 1 coluna mesmo, como a bp fica hoje"; "quando ele estiver fechado, so apareca o
-- mapa"): the dock is one right panel column wide, under the minimap, for every window. It never widens. A window keeps
-- the column's width (its parts laid out again by chaosdockcolumn.lua) or opens on its own beside the dock (fit 'float').
-- The right column shows only the minimap while the dock is closed.
ChaosDockLogic = {}
local L = ChaosDockLogic

L.WIDTH = 178          -- the column when the right panel cannot be measured: a side panel's width, the Inventory
                       -- panel's width in the right column before O755 (game_interface GameSidePanel)
L.SCROLL = 16          -- the scroll bar and its gap, right of a window taller than the dock (owner 2026-11-24)
L.CHROME = 135         -- the dock's frame, title, tabs, sub tabs and rule above its content, when it cannot be measured
L.PAD = 4              -- the dock frame around the hosted window, each side (chaosdock.otui padding)
L.TAB_GAP = 2          -- between two tabs and between two sub tabs (chaosdock.otui layout spacing)
L.SUB_COLS = 2         -- sub tabs a row: a tab with three windows has two rows (one column is narrow)
L.SUB_H = 20           -- a sub tab's height
L.MAP_GAP = 2          -- between the minimap and the dock under it
L.BAR_GAP = 6          -- between the dock's bottom and a hotbar it would cover
L.ORB_SLACK = 40       -- the docked globes may grow out of the hotbar frame
L.LOGIN_GRACE_MS = 5000 -- a bag the login opens is no click: the dock stays as it was saved
L.SLIDE_STEPS = 6
L.SETTING_ENABLED = 'chaosDockEnabled'
L.SETTING_TAB = 'chaosDockTab'
L.SETTING_SUBS = 'chaosDockSubs'
L.SETTING_OPEN = 'chaosDockOpen'
L.TOGGLE_KEY = 'Alt+D'
L.MINIMAP = 'minimapWindow' -- the one window the right column keeps while the dock is enabled

-- windows: entry = the menu entry text (also the tr() key of the sub tab), module / vars = where the module keeps the
-- window when it does (else the dock takes the window that the entry opened), getter = a module function that gives it,
-- shared = the module shows other pages in the same window (Character Info is one page of game_chaosinfo),
-- docked = a module function called with true when the dock takes the window and false when it gives it back (the
-- Inventory panel hides its own title bar and tab row: the dock has both), hidden = the dock takes the window even while
-- it is hidden (the Inventory panel has no window of its own any more, O755: its menu entry opens the stock one),
-- fit = 'column' (default: the column's width; ChaosDockColumn.LAYOUTS[entry] lays its parts out again for it) or
-- 'float' (too wide a grid for a column: it opens on its own, centred in the game left of the dock, which stays open).
L.TABS = {
  { id = 'equip', name = 'Equip.', glyph = 'pack', key = 'Alt+I', windows = {
    { entry = 'Inventory', module = 'game_bagpanel', getter = 'getWindow', docked = 'setDocked', hidden = true },
  } },
  { id = 'quests', name = 'Quests', glyph = 'book', key = 'Alt+Q', windows = {
    { entry = 'Quest Log', module = 'game_questlog', vars = { 'questLogWindow', 'questlogWindow' } },
    { entry = 'Main Quest', module = 'game_goals' },
    { entry = 'Quest Tracker', module = 'game_questlog', vars = { 'trackerWindow', 'questTrackerWindow' } },
  } },
  { id = 'attributes', name = 'Attributes', glyph = 'bolt', key = 'Alt+A', windows = {
    { entry = 'Skills', module = 'game_skills', vars = { 'skillsWindow' } },
    { entry = 'Character Info', module = 'game_chaosinfo', shared = true },
  } },
  -- no key of its own: Alt+S (Spellbook) and Alt+E (Market) are entry keys of the menu, and they open these tabs
  { id = 'spells', name = 'Spells', glyph = 'tome', windows = {
    { entry = 'Spellbook', module = 'game_spellbook' },
    { entry = 'Spell Supports', module = 'game_spellsupports' },
  } },
  { id = 'shop', name = 'Shop', glyph = 'scales', windows = {
    { entry = 'Market', module = 'game_market', fit = 'float' },
    { entry = 'Store', module = 'game_shop', fit = 'float' },
  } },
}

function L.tab(id)
  for _, t in ipairs(L.TABS) do
    if t.id == id then return t end
  end
  return nil
end

-- the tab and the sub index of a menu entry, or nil
function L.tabOf(text)
  for _, t in ipairs(L.TABS) do
    for i, w in ipairs(t.windows) do
      if w.entry == text then return t, i end
    end
  end
  return nil
end

-- "quests=2,spells=1" <-> { quests = 2, spells = 1 }; unknown tabs and bad indexes are dropped
function L.parseSubs(text)
  local out = {}
  if type(text) ~= 'string' then return out end
  for id, n in text:gmatch('([%w_]+)=(%d+)') do
    local t, i = L.tab(id), tonumber(n)
    if t and i and i >= 1 and i <= #t.windows then out[id] = i end
  end
  return out
end

function L.formatSubs(subs)
  local parts = {}
  for _, t in ipairs(L.TABS) do
    local i = subs and subs[t.id]
    if i then parts[#parts + 1] = t.id .. '=' .. i end
  end
  return table.concat(parts, ',')
end

-- the settings key of a character (O755: the open state, tab and windows are kept per character, as the pinned bags
-- of game_bagpanel): "chaosDockTab_Name_Of_Char"; no name, the plain key
function L.charKey(key, name)
  name = tostring(name or ''):gsub('[^%w]', '_')
  if name == '' then return key end
  return key .. '_' .. name
end

local function truthy(v) return v == true or v == 'true' or v == 1 or v == '1' end

-- the state from the settings: read(key) gives the stored value (nil when none). The dock is on unless turned off.
-- name: the character (its own keys first, then the plain ones of before O755); wasOpen: the dock was open when this
-- character left (it opens again at the next entry)
function L.newState(read, name)
  read = read or function() return nil end
  local function get(key)
    local v = name and read(L.charKey(key, name)) or nil
    if v == nil then v = read(key) end
    return v
  end
  local enabled = read(L.SETTING_ENABLED)
  local tab = get(L.SETTING_TAB)
  return {
    enabled = not (enabled == false or enabled == 'false' or enabled == 0),
    tab = L.tab(tab) and tab or L.TABS[1].id,
    subs = L.parseSubs(get(L.SETTING_SUBS)),
    open = false,
    wasOpen = name ~= nil and truthy(read(L.charKey(L.SETTING_OPEN, name))),
  }
end

function L.subOf(st, tabId)
  local t = L.tab(tabId)
  local i = st.subs[tabId]
  if t and i and i >= 1 and i <= #t.windows then return i end
  return 1
end

-- What a menu entry does: nil (not the dock's: the entry opens its window as before), { close = true } (the dock shows
-- that window now: a second press closes it, as the entry's hotkey did with the window) or { open = tab, sub = index }.
function L.route(st, text)
  if not st.enabled then return nil end
  local t, i = L.tabOf(text)
  if not t then return nil end
  if st.open and st.tab == t.id and L.subOf(st, t.id) == i then return { close = true } end
  return { open = t.id, sub = i }
end

-- the dock's own key: open on the last tab (and its last window), or close
function L.toggle(st)
  if not st.enabled then return nil end
  if st.open then return { close = true } end
  return { open = st.tab, sub = L.subOf(st, st.tab) }
end

-- a tab's key or a click on a tab: that tab with its last window; the key of the tab shown closes the dock
function L.pickTab(st, tabId, fromKey)
  if not st.enabled or not L.tab(tabId) then return nil end
  if fromKey and st.open and st.tab == tabId then return { close = true } end
  return { open = tabId, sub = L.subOf(st, tabId) }
end

-- a click on a sub tab
function L.pickSub(st, index)
  local t = L.tab(st.tab)
  if not st.enabled or not t or index < 1 or index > #t.windows then return nil end
  return { open = t.id, sub = index }
end

-- applies an action to the state; returns the settings to write ({ [key] = value }, chaosdock.lua writes them under the
-- character's keys) or nil
function L.apply(st, action)
  if not action then return nil end
  if action.close then
    st.open = false
    return { [L.SETTING_OPEN] = 'false' }
  end
  st.open = true
  st.tab = action.open
  st.subs[action.open] = action.sub
  return { [L.SETTING_TAB] = st.tab, [L.SETTING_SUBS] = L.formatSubs(st.subs), [L.SETTING_OPEN] = 'true' }
end

-- how a window fits the column: 'column' or 'float'; a phone sheet hosts every window at its width ('sheet')
function L.fitOf(spec, phone)
  if phone then return 'sheet' end
  return spec and spec.fit == 'float' and 'float' or 'column'
end

-- the dock's width: the right panel column (column = its rect, rootRight = the screen's right edge), from its left edge
-- to the screen's right; L.WIDTH when there is no column to measure. A phone gets the whole screen as a sheet.
function L.width(column, rootRight, phone, screenW)
  if phone then return tonumber(screenW) or 0 end
  rootRight = tonumber(rootRight) or 0
  if column and (column.width or 0) >= 40 and column.x and column.x < rootRight then
    return rootRight - column.x
  end
  return L.WIDTH
end

-- the height a hosted window has in the dock: its column layout's height, else its own
function L.heightIn(layout, natural)
  return layout and layout.height or natural
end

-- the dock's top margin under the minimap (O755: the dock takes the column under it): map = the minimap window's rect
-- when it is shown in the right column, rootTop = y of the screen top
function L.mapMargin(map, rootTop)
  if not map or not rootTop then return 0 end
  return math.max(0, map.y + map.height - rootTop + L.MAP_GAP)
end

-- the width of each of n tabs (or sub tabs) that share a row of `room` px with L.TAB_GAP between them
function L.share(n, room)
  n = math.max(1, n or 1)
  return math.max(0, math.floor(((room or 0) - L.TAB_GAP * (n - 1)) / n))
end

-- the sub tab rows of a tab with n windows, and their height
function L.subRows(n)
  if not n or n < 2 then return 0 end
  return math.ceil(n / L.SUB_COLS)
end

function L.subsHeight(n)
  local rows = L.subRows(n)
  if rows == 0 then return 0 end
  return rows * L.SUB_H + (rows - 1) * L.TAB_GAP
end

-- a window of the right column that hides while the dock is enabled: every one but the minimap and the dock's own
function L.hidesInColumn(id, heldIds)
  id = tostring(id or '')
  if id:find(L.MINIMAP, 1, true) then return false end
  if heldIds and heldIds[id] then return false end
  return true
end

-- a container window of the right column that the column must not hide (V37, seen in a client 2026-11-27: a chest on the
-- ground opened on the server and its window was hidden at once, as if it never opened). The bag panel hides the windows
-- of its own bags and the purse itself, so a container window still visible there is another one: a chest, a corpse,
-- the depot. It is lifted out of the column and stands left of it (L.liftPlaces)
function L.liftsFromColumn(id)
  return tostring(id or ''):match('^container%d+$') ~= nil
end

L.LIFT_GAP = 4

-- the places of the lifted windows: right-aligned against the column's left edge (colX), stacked down from top; a window
-- that would reach below bottom starts a new stack further left. sizes: { { width, height } } in order -> { { x, y } }
function L.liftPlaces(colX, top, bottom, sizes)
  local out = {}
  local right, y, stackW = colX - L.LIFT_GAP, top, 0
  for i, s in ipairs(sizes or {}) do
    if y > top and y + s.height > bottom then
      right, y, stackW = right - stackW - L.LIFT_GAP, top, 0
    end
    out[i] = { x = math.max(0, right - s.width), y = y }
    stackW = math.max(stackW, s.width)
    y = y + s.height + L.LIFT_GAP
  end
  return out
end

-- a bag opened by a click (game_bagpanel): the dock shows the Inventory. Not while the login restores the bags, not a
-- pinned bag's reopen, not in the first L.LOGIN_GRACE_MS of the game (the backpack the login opens)
function L.bagOpensDock(st, restoring, quiet, sinceStart)
  if not st or not st.enabled or restoring or quiet then return false end
  if (sinceStart or 0) < L.LOGIN_GRACE_MS then return false end
  return not (st.open and st.tab == 'equip')
end

-- whether a window scrolls in the dock: taller than the room under the dock's tabs (nothing is cut, owner 2026-11-24).
-- A miniwindow fills the room and scrolls its own contents; a window that fits keeps the whole room.
function L.scrolls(mini, height, room)
  if mini or not height or not room then return false end
  return height > room
end

-- the room under the dock's tabs: the screen height less the dock's margins and its chrome (measured: panel height less
-- content height; L.CHROME when that is not laid out yet)
function L.room(screenH, top, bottom, chrome)
  if not chrome or chrome <= 0 or chrome > 3 * L.CHROME then chrome = L.CHROME end
  return math.max(0, (tonumber(screenH) or 0) - (top or 0) - (bottom or 0) - chrome)
end

-- the dock's bottom margin: 0 (the whole height) unless the hotbar (and its globes) reach under the dock, then the dock
-- stops above it. dockLeft: x of the dock's left edge; bar: the hotbar frame rect or nil; rootBottom: y of the screen bottom.
function L.bottomMargin(dockLeft, bar, rootBottom)
  if not bar or not dockLeft or not rootBottom then return 0 end
  if bar.x + bar.width + L.ORB_SLACK <= dockLeft then return 0 end
  return math.max(0, rootBottom - bar.y + L.BAR_GAP)
end

-- the dock's top margin: 0 (from the top of the screen) unless the hub menu bar (client_chaos_topbar, O550) reaches over the
-- dock's left edge, then the dock starts below the bar: the two never cover each other.
-- dockLeft: x of the dock's left edge; bar: the menu bar rect or nil; rootTop: y of the screen top.
function L.topMargin(dockLeft, bar, rootTop)
  if not bar or not dockLeft or not rootTop then return 0 end
  if bar.x + bar.width <= dockLeft then return 0 end
  return math.max(0, bar.y + bar.height - rootTop + L.BAR_GAP)
end

-- the right margins of the slide in, from hidden (-width) to in place (0); out is the same list backwards
function L.slide(width, steps)
  steps = steps or L.SLIDE_STEPS
  local out = {}
  for i = 1, steps do
    local f = i / steps
    local eased = 1 - (1 - f) * (1 - f)
    out[i] = -math.floor(width * (1 - eased) + 0.5)
  end
  return out
end

-- the first widget of `after` that is not in `before` (eq compares two widgets: the engine gives a new userdata each time)
function L.pickNew(before, after, eq)
  eq = eq or function(a, b) return a == b end
  for _, w in ipairs(after) do
    local seen = false
    for _, b in ipairs(before) do
      if eq(w, b) then seen = true break end
    end
    if not seen then return w end
  end
  return nil
end

-- the keys to bind: the dock's key and each tab's key, without the keys `used` already has ({ [key] = true })
function L.hotkeys(used)
  used = used or {}
  local out = {}
  if not used[L.TOGGLE_KEY] then out[#out + 1] = { key = L.TOGGLE_KEY } end
  for _, t in ipairs(L.TABS) do
    if t.key and not used[t.key] then out[#out + 1] = { key = t.key, tab = t.id } end
  end
  return out
end

-- a menu entry that is not the dock's runs while the dock holds a shared window (one a module also shows other pages
-- in): the dock gives it back first, so that page opens as a window of its own
function L.releaseForOther(held, text)
  if L.tabOf(text) then return false end
  for _, h in ipairs(held or {}) do
    if h.spec and h.spec.shared then return true end
  end
  return false
end

L.FLOAT_NOTE = 'This window opens on its own, left of the panel.'

-- the tr() keys of the dock: tab names (English text) and the window names (the menu entry texts)
function L.texts()
  local out = { L.FLOAT_NOTE }
  for _, t in ipairs(L.TABS) do
    out[#out + 1] = t.name
    for _, w in ipairs(t.windows) do out[#out + 1] = w.entry end
  end
  return out
end

return L
