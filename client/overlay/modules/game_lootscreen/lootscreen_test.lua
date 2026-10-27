-- luajit lootscreen_test.lua && lua5.3 lootscreen_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'lootscreen_core.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local loot = { color = 'green', screenTarget = 'lowCenterLabel', consoleTab = 'Loot' }
local types = { [29] = loot, [30] = loot }
local prev = LootScreen.apply(types, 29)
eq(prev, loot, 'previous entry returned')
eq(types[29].screenTarget, nil, 'no screen target')
eq(types[29].consoleTab, 'Loot', 'console tab kept')
eq(types[29].color, 'green', 'colour kept')
eq(types[30].screenTarget, 'lowCenterLabel', 'other mode sharing the table untouched')
eq(loot.screenTarget, 'lowCenterLabel', 'stock table not modified')
eq(LootScreen.apply(types, 29), false, 'second apply does nothing')
LootScreen.restore(types, 29, prev)
eq(types[29], loot, 'restored')
eq(LootScreen.apply(nil, 29), false, 'nil types')
eq(LootScreen.apply({}, 29), false, 'missing mode entry')
if fails > 0 then os.exit(1) end
print('lootscreen tests OK')
