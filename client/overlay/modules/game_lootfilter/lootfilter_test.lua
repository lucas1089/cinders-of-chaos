-- luajit lootfilter_test.lua && lua5.3 lootfilter_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'lootfilterlogic.lua')
local L = LootFilterLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(#L.RARITY, 15, '15 rarities')
eq(L.rarityName(5), 'Legendary', 'name 5')
eq(L.rarityName(0), nil, 'no rarity')

local s = L.normalize({ highlight = 4, dim = 2, show = { supplies = false } })
eq(s.lootMin, 0, 'missing field = default')
eq(s.show.supplies, false, 'category off')
eq(s.show.other, true, 'category on')
eq(L.normalize({ highlight = 40 }).highlight, 15, 'clamped')
eq(L.normalize(nil).highlight, 3, 'nil = defaults')

eq(L.classify({ r = 4, g = 'equipment' }, s), 'highlight', 'Epic glows')
eq(L.classify({ r = 3, g = 'equipment' }, s), 'normal', 'Rare plain')
eq(L.classify({ r = 1, g = 'equipment' }, s), 'dim', 'Common dimmed')
eq(L.classify({ r = 0, g = 'supplies' }, s), 'dim', 'supplies off')
eq(L.classify({ u = 1, g = 'equipment' }, s), 'highlight', 'unique (JSON 1)')
eq(L.classify({ o = true, g = 'currency' }, { highlight = 0, dim = 15, show = { currency = false } }), 'highlight', 'orb')
eq(L.classify({ r = 0, g = 'other' }, s), 'normal', 'other shown')

eq(L.color({ r = 5 }), '#ffd040', 'legendary colour')
eq(L.color({ u = 1, r = 5 }), L.UNIQUE_COLOR, 'unique colour')
eq(L.color({ o = 1 }), L.ORB_COLOR, 'orb colour')
eq(L.color({ r = 0 }), nil, 'no colour')

eq(L.label({ nm = 'Dawnforged Helmet', r = 5 }), '[Legendary] Dawnforged Helmet', 'label')
eq(L.label({ nm = 'Soulreaper', u = 1 }), '[Unique] Soulreaper', 'unique label')
eq(L.tooltip({ nm = 'gold coin', c = 50, left = 20 }), '50x gold coin\n20 left in the corpse\nClick: loot all   Shift+click: loot one', 'stack tooltip')
eq(L.tooltip({ nm = 'Sword', r = 3, c = 1, left = 0 }), '[Rare] Sword\nLooted (or gone)', 'gone tooltip')
eq(L.tooltip({ nm = 'Sword', c = 1, left = 1 }), 'Sword\nClick: loot', 'single tooltip')
eq(L.tooltip({ nm = 'Sword', r = 4, c = 1, left = 1, x = 'Attack Speed +5%; Life on Kill +12' }),
  '[Epic] Sword\nAttack Speed +5%; Life on Kill +12\nClick: loot', 'tooltip with Chaos modifiers')
eq(L.thresholdText(0), 'Off', 'off')
eq(L.thresholdText(5), 'Legendary+', 'threshold')

local list = { 1, 2, 3, 4 }
local dropped = L.trim(list, 2)
eq(#list, 2, 'trimmed')
eq(list[1], 3, 'oldest dropped')
eq(dropped[2], 2, 'dropped keys')

if fails > 0 then os.exit(1) end
print('lootfilter client tests OK')
