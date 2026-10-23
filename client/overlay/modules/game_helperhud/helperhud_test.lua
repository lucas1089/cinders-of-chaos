-- luajit helperhud_test.lua && lua5.3 helperhud_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'helperhud_logic.lua')
local L = ChaosBotHudLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- on/off comes from the saved helper config only
eq(L.isEnabled(nil), false, 'no config')
eq(L.isEnabled({}), false, 'no botHud')
eq(L.isEnabled({ botHud = { enabled = false } }), false, 'off')
eq(L.isEnabled({ botHud = { enabled = true } }), true, 'on')

-- the sections of the helper's botHud
local cfg = {
  botHud = { enabled = true, size = 'Normal', showTargeting = true, showHealing = true,
    showHaste = true, showPlayer = true },
  autoTargetEnabled = true,
  haste = { { enabled = true, id = 6 } },
  spells = { { id = 11, percent = 80 }, { id = 0, percent = 50 } },
  potions = { { id = 266, percent = 50 }, { id = 268, percent = 30 } },
}
local state = {
  targetName = 'Ember Wraith',
  spellName = function(id) return id == 6 and 'Swiftstep' or nil end,
  player = { health = 50, maxHealth = 200, mana = 30, maxMana = 60, level = 42 },
}
local rows = L.entries(cfg, state)
eq(#rows, 4, 'four ticked sections')
eq(rows[1].name, 'Combat', 'combat first')
eq(rows[1].value, 'Auto  Ember Wraith', 'combat value')
eq(rows[1].active, true, 'combat active')
eq(rows[2].value, '1 spells  2 potions', 'healing value')
eq(rows[2].active, true, 'healing active')
eq(rows[3].value, 'Haste Swiftstep', 'support value')
eq(rows[4].value, 'HP 25%  MP 50%  Lv 42', 'player value')
eq(L.activeCount(rows), 4, 'active rows')
local idle = L.entries({ botHud = { showHealing = true } }, {})
eq(idle[1].value, 'Off', 'nothing set: healing off')
eq(idle[1].active, false, 'and dimmed')

-- nothing ticked: one hint row instead of an empty card
local none = L.entries({ botHud = { enabled = true } }, {})
eq(#none, 1, 'hint row')
eq(none[1].active, false, 'hint dimmed')

-- the player row needs a player; a missing max does not divide by zero
local p = L.entries({ botHud = { showPlayer = true } }, { player = { health = 5, maxHealth = 0, mana = 0, maxMana = 0, level = 1 } })
eq(p[1].value, 'HP 0%  MP 0%  Lv 1', 'zero max')

-- long names are capped
eq(L.shorten('abcdefghijklmnop', 14), 'abcdefghijklmn..', 'shorten')

-- layout: up to four rows in one column; Compact is always one column
local s = L.layout('Normal', 4)
eq(s.twoColumns, false, 'four rows one column')
eq(s.rowsPerColumn, 4, 'four per column')
eq(s.cardWidth, 520, 'full width card')
s = L.layout('Normal', 5)
eq(s.twoColumns, true, 'five rows two columns')
eq(s.rowsPerColumn, 3, 'three per column')
eq(s.cardWidth, 257, 'half card')
eq(s.valueWidth, 257 - L.CARD_INSET - L.ROW_LABEL_INSET, 'value width')
eq(s.cardHeight, 8 + 3 * 15 + 2, 'card height')
s = L.layout('Compact', 7)
eq(s.twoColumns, false, 'compact one column')
eq(s.rowsPerColumn, 7, 'compact rows')
eq(L.layout('Bogus', 1).width, 520, 'unknown size is Normal')
eq(L.layout('Wide', 20).rowsPerColumn, L.MAX_ROWS, 'rows capped')

-- top margin: below the menu bar when it covers the top of the map
eq(L.topMargin(0, 0, nil), 12, 'no bar: 12 px')
eq(L.topMargin(0, 0, {y = 2, height = 36}), 2 + 36 + 6, 'below the menu bar')
eq(L.topMargin(100, 0, {y = 2, height = 36}), 12, 'bar above the map: 12 px')
eq(L.topMargin(-40, 0, nil), 52, 'map starts above the window: visible top')
eq(L.topMargin(-40, 0, {y = 2, height = 36}), 2 + 36 + 6 + 40, 'extended view below the bar')
eq(L.topMargin(0, 0, {y = 2, height = 0}), 12, 'hidden bar ignored')
eq(L.topMargin(0, 0, {y = 400, height = 36}), 12, 'bar lower down ignored')

if fails > 0 then os.exit(1) end
print('helperhud tests OK')
