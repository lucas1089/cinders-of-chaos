-- luajit depottabsview_test.lua (CI runs every client *_test.lua under luajit and lua5.3)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'depottabsview.lua')
local V = DepotTabsView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function has(s, part, m) n = n + 1 if type(s) ~= 'string' or not s:find(part, 1, true) then error((m or '') .. ': ' .. tostring(s), 2) end end

local ids = {}
for i = 1, 17 do ids[i] = 22796 + i end
local palette = { { key = 'gold', name = 'Gold', color = '#e8b84a' }, { key = 'jade', name = 'Jade', color = '#3fae74' },
  { key = 'ash', name = 'Ash Grey', color = '#8c8a86' } }
eq(V.known(V.newState()), false, 'nothing known before the first message')
local s = V.apply(nil, { tabs = 4, max = 17, size = 100, ids = ids, chest = { 3502 }, lockers = { 1589, 1590 }, inbox = 13404,
  market = 13405, hint = 'Buy more tabs in the Store (Depot Tabs).', store = 'Depot Tabs', palette = palette, nameMax = 16,
  town = 'Ashford Hollow' })
eq(V.known(s), true, 'known after the first message')
eq(V.tabOf(s, 22797), 1, 'tab 1') eq(V.tabOf(s, 22813), 17, 'tab 17') eq(V.tabOf(s, 3502), nil, 'the chest is no tab')
eq(V.isChest(s, 3502), true, 'chest') eq(V.isChest(s, 22797), false, 'a tab is no chest')
eq(V.isLocker(s, 1590), true, 'locker') eq(V.isLocker(s, 3502), false, 'the chest is no locker')
eq(s.inbox, 13404, 'inbox id') eq(s.market, 13405, 'market id') eq(s.ids[3], 22799, 'ids by tab')
eq(V.isLocked(s, 4), false, 'tab 4 open') eq(V.isLocked(s, 5), true, 'tab 5 locked')
eq(V.title(s, 3), 'Tab 3', 'no counts yet')
has(V.tooltip(s, 3), 'up to 100 items', 'tooltip without counts')
eq(V.windowTitle(s), 'Ashford Hollow Depot', 'window title with the town')
eq(V.windowTitle(V.newState()), 'Depot', 'window title without a town')
local used = {}
for i = 1, 17 do used[i] = 0 end
used[1], used[3], used[6] = 100, 87, 12
s = V.apply(s, { tabs = 4, max = 17, size = 100, used = used })
eq(s.town, 'Ashford Hollow', 'town kept') eq(#s.palette, 3, 'palette kept')
eq(V.title(s, 3), 'Tab 3 (87/100)', 'title with count')
eq(V.title(s, 6), 'Tab 6 (locked)', 'locked title')
has(V.tooltip(s, 3), '87 of 100', 'tooltip count')
has(V.tooltip(s, 6), 'locked', 'locked tooltip') has(V.tooltip(s, 6), '12 items inside', 'locked tooltip: items inside')
has(V.tooltip(s, 6), 'Store', 'locked tooltip: store hint')
eq(V.tooltip(s, 7):find('items inside', 1, true), nil, 'empty locked tab: no items line')
eq(V.titleColor(s, 1), '#d08040', 'full tab colour') eq(V.titleColor(s, 2), nil, 'open tab colour')
eq(V.titleColor(s, 9), '#8a8a8a', 'locked colour')

-- the window: header, footer, buttons
eq(V.header(s, 3), 'Tab 3', 'header') has(V.header(s, 6), 'withdraw only', 'locked header')
has(V.header(s, nil), 'Opening', 'header before a tab is open')
local f = V.footer(s, 3)
eq(f.items, '87/100 items', 'footer items') eq(f.tabs, '4 of 17 tabs', 'footer tabs') eq(f.itemsColor, V.COLORS.text, 'normal colour')
eq(V.footer(s, 1).itemsColor, V.COLORS.full, 'a full tab') eq(V.footer(s, 6).itemsColor, V.COLORS.locked, 'a locked tab')
eq(V.footer(s, nil).items, '-/100 items', 'no tab yet')
local b = V.button(s, 3, 3, 8)
eq(b.text, '3', 'button: the number') eq(b.checked, true, 'active button') eq(b.locked, false, 'open button')
eq(b.opacity, 1, 'open button opacity') eq(b.accent, nil, 'default accent')
b = V.button(s, 9, 3, 8)
eq(b.checked, false, 'inactive') eq(b.locked, true, 'locked button') eq(b.opacity, 0.7, 'locked button dimmed')
has(b.tooltip, 'Buy more tabs in the Store', 'locked button tooltip')
eq(V.button(s, 9, 9, 8).opacity, 1, 'the active locked tab is not dimmed')

-- layout: 17 tabs and the store button in rows of 6, a 10x10 grid
local cells = V.tabCells(s)
eq(#cells, 18, '17 tabs and the store button')
eq(cells[18].tab, 'store', 'the store button last')
eq(cells[1].x, 0, 'first x') eq(cells[1].y, 0, 'first y')
eq(cells[6].col, 5, 'six per row') eq(cells[7].row, 1, 'second row') eq(cells[7].x, 0, 'second row starts left')
eq(cells[7].y, V.TAB_H + V.TAB_GAP, 'second row y') eq(cells[18].row, 2, 'three rows')
eq(cells[2].x, V.TAB_W + V.TAB_GAP, 'second button x')
local size = V.blockSize(s)
eq(size.tabRows, 3, 'three rows of tabs') eq(size.gridRows, 10, 'ten rows of items')
eq(size.gridW, 10 * 34 + 9 * 2, 'grid width') eq(size.gridH, size.gridW, 'a square grid')
eq(size.tabsW, 6 * 60 + 5 * 2, 'tab block width')
eq(size.tabsW <= size.gridW + 20, true, 'the tab block is about as wide as the grid')
local all = V.apply(V.apply(nil, { tabs = 17, max = 17, size = 100, ids = ids }), {})
eq(#V.tabCells(all), 17, 'every tab open: no store button')

-- names and colours
eq(V.tabName(s, 3), 'Tab 3', 'default name')
local names, colors = {}, {}
for i = 1, 17 do names[i], colors[i] = '', '' end
names[3], colors[3] = 'Potions', 'jade'
names[5], colors[5] = 'Runes and bolts!', 'gold'
colors[8] = 'pink' -- not in the palette: the default colour
s = V.apply(s, { tabs = 4, max = 17, size = 100, names = names, colors = colors })
eq(V.tabName(s, 3), 'Potions', 'custom name') eq(V.title(s, 3), 'Potions (87/100)', 'title with the name')
eq(V.title(s, 5), 'Runes and bolts! (locked)', 'locked title with the name')
eq(V.header(s, 3), 'Tab 3: Potions', 'header with the name')
has(V.tooltip(s, 3), 'Tab 3: Potions', 'tooltip with the name')
eq(V.accent(s, 3), '#3fae74', 'jade accent') eq(V.accent(s, 4), nil, 'default accent') eq(V.accent(s, 8), nil, 'unknown colour')
eq(V.buttonText(s, 3, 8), 'Potions', 'a short name fits') eq(V.buttonText(s, 5, 8), 'Runes..', 'a long name is cut')
eq(V.buttonText(s, 4, 8), '4', 'no name: the number')
eq(V.button(s, 3, 1, 8).accent, '#3fae74', 'button accent')
eq(V.button(s, 3, 1).text, 'Potions', 'default cut: 7 characters')
eq(V.button(s, 5, 1).text, 'Run..', 'a locked button keeps room for the lock')
-- the name is also cut to the label's width (measure: 8 px a character here)
local function px(t) return #t * 8 end
eq(V.button(s, 3, 1, nil, px).text, 'Poti..', 'cut to the open label width (52 px)')
eq(V.button(s, 5, 1, nil, function(t) return #t * 9 end).text, 'Ru..', 'cut to the room left of the lock (43 px)')
eq(V.button(s, 4, 1, nil, px).text, '4', 'a number is never cut')
eq(V.button(s, 3, 1, nil, function() return 999 end).text, 'P..', 'at least one letter')
-- the colours: a translucent fill, the text dark on a light tint and light (with a shadow) on a dark one
local c = V.buttonColors(s, 3, 1, false)
eq(c.fill, '#3fae7480', 'jade fill') eq(c.text, V.TEXT_ON_FILL.light, 'light text on jade') eq(c.shadow, true, 'shadow')
eq(V.buttonColors(s, 3, 1, true).fill, '#3fae749c', 'hover: stronger fill')
eq(V.buttonColors(s, 3, 3, false).fill, '#3fae74d0', 'active: strongest fill')
eq(V.buttonColors(s, 3, 3, false).text, V.TEXT_ON_FILL.dark, 'dark text on the active jade')
eq(V.buttonColors(s, 5, 1, false).text, V.TEXT_ON_FILL.light, 'light text on gold')
eq(V.buttonColors(s, 5, 1, true).text, V.TEXT_ON_FILL.light, 'hovering keeps the text colour')
eq(V.buttonColors(s, 5, 5, false).text, V.TEXT_ON_FILL.dark, 'dark text on the active gold')
c = V.buttonColors(s, 4, 1, false)
eq(c.fill, nil, 'default: no fill') eq(c.text, V.COLORS.dim, 'default text') eq(c.shadow, false, 'no shadow')
eq(V.buttonColors(s, 4, 1, true).text, V.COLORS.text, 'default hover text')
eq(V.buttonColors(s, 4, 4, false).text, V.COLORS.bright, 'default active text')
eq(V.buttonColors(s, 9, 1, false).text, V.COLORS.locked, 'default locked text')
eq(V.tintLuminance('#e6dcc0', 0x80) > V.DARK_TEXT_ABOVE, true, 'bone is light')
eq(V.tintLuminance('#c0241c', 0xd0) < V.DARK_TEXT_ABOVE, true, 'crimson is dark')
eq(V.tintLuminance('nope', 0x80), nil, 'not a colour')
-- a message without names keeps them
s = V.apply(s, { tabs = 5, max = 17, size = 100 })
eq(V.tabName(s, 3), 'Potions', 'names kept') eq(V.isLocked(s, 5), false, 'tab 5 open after a purchase')
-- the dialog
eq(V.cleanName(s, '  Gems   and ore '), 'Gems and ore', 'trimmed')
eq(V.cleanName(s, '1234567890abcdef'), '1234567890abcdef', '16 characters')
local nm, why = V.cleanName(s, '1234567890abcdefg')
eq(nm, nil, '17 characters') has(why, 'at most 16', 'length reason')
eq(V.cleanName(s, 'a\1b'), nil, 'control character') eq(V.cleanName(s, 'Caf\233'), 'Caf\233', 'Latin-1')
eq(V.cleanName(s, '   '), '', 'empty: default') eq(V.cleanName(s, nil), '', 'nil: default')
local choices = V.colorChoices(s)
eq(#choices, 4, 'default and three colours') eq(choices[1].key, '', 'default first') eq(choices[2].key, 'gold', 'then the palette')
eq(V.setStyle(s, 4, 'Food', 'ash'), true, 'local style')
eq(V.tabName(s, 4), 'Food', 'local name') eq(V.accent(s, 4), '#8c8a86', 'local colour')
V.setStyle(s, 4, '', 'nope')
eq(V.tabName(s, 4), 'Tab 4', 'reset name') eq(V.accent(s, 4), nil, 'unknown key: default colour')
eq(V.setStyle(s, 40, 'x', ''), false, 'no tab 40')

-- which part an opened container plays
eq(V.classify(s, { clientId = 1589 }), 'locker', 'a locker')
eq(V.classify(s, { clientId = 9999, holdsChest = true }), 'locker', 'a container holding the chest')
eq(V.classify(s, { clientId = 3502 }), 'chest', 'the chest')
eq(V.classify(s, { clientId = 22799, windowOpen = false }), nil, 'a box with the window closed: stock window')
eq(V.classify(s, { clientId = 22799, windowOpen = true }), 'tab', 'a box with the window open')
eq(V.classify(s, { clientId = 22799, id = 4, pendingTab = 4 }), 'tab', 'the box the window asked for')
eq(V.classify(s, { clientId = 2854, windowOpen = true }), nil, 'a backpack')
eq(V.classify(V.newState(), { clientId = 1589 }), nil, 'nothing known yet: stock window')
eq(V.firstTab(s, 7), 7, 'the last tab') eq(V.firstTab(s, 0), 1, 'tab 1 first') eq(V.firstTab(s, 30), 1, 'no tab 30')

eq(V.apply(s, 'junk').tabs, 5, 'junk ignored')
print('depottabsview_test: ' .. n .. ' checks OK')
