-- luajit catalogcore_test.lua && lua5.3 catalogcore_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'catalogcore.lua')
local C = ProficiencyCatalogCore
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local types = { sword = 1, club = 2, axe = 3, fist = 4, bow = 5, crossbow = 6, wand = 7 }
local items = {
  [100] = { category = 20, name = 'Steel Blade' },              -- sword by market category
  [101] = { category = 6, name = 'Cheese' },                    -- food: no
  [102] = { weaponType = 3, name = 'Ember Axe' },               -- no market data, axe by weapon type
  [103] = { category = 21, name = '' },                         -- weapon without a name: no
  [104] = { category = 19, name = 'Hunter Bow' },
  [105] = { weaponType = 99, name = 'Odd' },                    -- unknown weapon type: no
  [106] = { category = 27, name = 'Iron Knuckles' },
  [107] = { weaponType = 7, name = 'Spark Wand' },
}
local list, seen = C.collect(function(id) return items[id] end, 99, 110, types)
eq(seen, 8, 'items looked at')
eq(#list, 5, 'five weapons')
eq(list[1].id, 100, 'in id order'); eq(list[1].category, 20, 'sword'); eq(list[1].name, 'Steel Blade', 'name')
eq(list[2].id, 102, 'axe by weapon type'); eq(list[2].category, 17, 'axe category')
eq(list[3].category, 19, 'distance'); eq(list[4].category, 27, 'fist'); eq(list[5].category, 21, 'wand by weapon type')
eq(C.categoryOfWeaponType({}, 1), nil, 'empty types table'); eq(C.categoryOfWeaponType({ throw = 8 }, 8), 19, 'throwing weapons')
eq(C.categoryOfWeaponType(nil, 1), nil, 'no types table'); eq(C.categoryOfWeaponType(types, nil), nil, 'no weapon type')
list = C.collect(function() return nil end, 1, 5, types)
eq(#list, 0, 'nothing known')

print('proficiencycatalog tests OK (' .. checks .. ' checks)')
if fails > 0 then os.exit(1) end
