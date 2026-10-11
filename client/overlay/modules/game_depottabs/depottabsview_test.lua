-- luajit depottabsview_test.lua (CI runs every client *_test.lua under luajit and lua5.3)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'depottabsview.lua')
local V = DepotTabsView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function has(s, part, m) n = n + 1 if type(s) ~= 'string' or not s:find(part, 1, true) then error((m or '') .. ': ' .. tostring(s), 2) end end

local ids = {}
for i = 1, 17 do ids[i] = 22796 + i end
local s = V.apply(nil, { tabs = 4, max = 17, size = 100, ids = ids, chest = { 3502 }, hint = 'Buy more tabs in the Store (Depot Tabs).' })
eq(V.tabOf(s, 22797), 1, 'tab 1') eq(V.tabOf(s, 22813), 17, 'tab 17') eq(V.tabOf(s, 3502), nil, 'the chest is no tab')
eq(V.isChest(s, 3502), true, 'chest') eq(V.isChest(s, 22797), false, 'a tab is no chest')
eq(V.isLocked(s, 4), false, 'tab 4 open') eq(V.isLocked(s, 5), true, 'tab 5 locked')
eq(V.title(s, 3), 'Tab 3', 'no counts yet')
has(V.tooltip(s, 3), 'up to 100 items', 'tooltip without counts')
local used = {}
for i = 1, 17 do used[i] = 0 end
used[1], used[3], used[6] = 100, 87, 12
s = V.apply(s, { tabs = 4, max = 17, size = 100, used = used })
eq(V.title(s, 3), 'Tab 3 (87/100)', 'title with count')
eq(V.title(s, 6), 'Tab 6 (locked)', 'locked title')
has(V.tooltip(s, 3), '87 of 100', 'tooltip count')
has(V.tooltip(s, 6), 'locked', 'locked tooltip') has(V.tooltip(s, 6), '12 items inside', 'locked tooltip: items inside')
has(V.tooltip(s, 6), 'Store', 'locked tooltip: store hint')
eq(V.tooltip(s, 7):find('items inside', 1, true), nil, 'empty locked tab: no items line')
eq(V.titleColor(s, 1), '#d08040', 'full tab colour') eq(V.titleColor(s, 2), nil, 'open tab colour')
eq(V.titleColor(s, 9), '#8a8a8a', 'locked colour')
-- a later message without counts (a store purchase) keeps them and opens tab 5
s = V.apply(s, { tabs = 5, max = 17, size = 100 })
eq(V.title(s, 3), 'Tab 3 (87/100)', 'counts kept') eq(V.isLocked(s, 5), false, 'tab 5 open after a purchase')
eq(V.tabOf(s, 22797), 1, 'ids kept')
eq(V.apply(s, 'junk').tabs, 5, 'junk ignored')
print('depottabsview_test: ' .. n .. ' checks OK')
