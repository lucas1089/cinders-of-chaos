-- luajit recipeview_test.lua && lua5.3 recipeview_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'recipeview.lua')
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local V = CraftingRecipeView

local sv = { installed = true, shards = 60, shardName = 'rune shards', maxCombine = 10 }
local rune = { key = 'chaos', name = 'Orb of Upheaval', cost = 25, count = 2, back = 10 }
local ember = { key = 'embershard', name = 'Ember Orb', cost = 1500, count = 0, back = 0, input = 29852,
  inputName = 'Ember Shards', inputSingular = 'Ember Shard', have = 3200 }
local crown = { key = 'crownshard', name = 'Crown Orb', cost = 1750, count = 0, back = 0, input = 29853,
  inputName = 'Crown Shards', inputSingular = 'Crown Shard', have = 1749 }

-- numbers
eq(V.thousands(1500), '1,500', 'thousands')
eq(V.thousands(17500), '17,500', 'five digits')
eq(V.thousands(999), '999', 'no separator')
eq(V.thousands(1000000), '1,000,000', 'millions')

-- which currency
eq(V.isShardRecipe(rune), false, 'a rune shard recipe')
eq(V.isShardRecipe(ember), true, 'a shard recipe')
eq(V.have(rune, sv), 60, 'rune shards from the view')
eq(V.have(ember, sv), 3200, 'Ember Shards from the row')
eq(V.currency(rune, sv), 'rune shards', 'rune shard plural')
eq(V.currency(ember, sv), 'Ember Shards', 'the server item name')
eq(V.costText(rune, sv), '25 shards', 'rune cost')
eq(V.costText(ember, sv), '1,500 Ember Shards', 'shard cost')

-- one click 1, Ctrl as many as paid for, at most maxCombine
eq(V.combineCount(V.have(ember, sv), ember.cost, sv.maxCombine, false), 1, 'a click makes one')
eq(V.combineCount(V.have(ember, sv), ember.cost, sv.maxCombine, true), 2, 'Ctrl: 3,200 pay for two')
eq(V.combineCount(V.have(crown, sv), crown.cost, sv.maxCombine, false), 0, 'one short: none')
eq(V.combineCount(V.have(crown, sv), crown.cost, sv.maxCombine, true), 0, 'one short, Ctrl: none')
eq(V.combineCount(100000, 1500, 10, true), 10, 'Ctrl stops at 10')
eq(V.combineCount(1500, 1500, 10, true), 1, 'exactly one')
eq(V.combineCount(100, 0, 10, true), 0, 'a broken recipe makes nothing')

-- the button
eq(V.enabled(ember, sv), true, 'enough Ember Shards')
eq(V.enabled(crown, sv), false, 'not enough Crown Shards')
eq(V.enabled(ember, { installed = false, shards = 0 }), true, 'shard recipes do not need the rune shard item')
eq(V.enabled(rune, sv), true, 'enough rune shards')
eq(V.enabled(rune, { installed = false, shards = 60 }), false, 'rune recipes need salvage installed')
eq(V.enabled({ key = 'exalted', cost = 100, count = 1, back = 40 }, sv), true, 'an orb to recycle')
eq(V.enabled({ key = 'exalted', cost = 100, count = 0, back = 40 }, sv), false, 'neither shards nor an orb')

-- recycling stays on the rune shard recipes
eq(V.recycleBack(rune), 10, 'recycle back')
eq(V.recycleBack({ key = 'x', cost = 1, input = 29852, back = 5 }), 0, 'a shard recipe never recycles')

-- the tooltip
local tip = V.tip(ember, sv)
eq(tip:find('1500 Ember Shards -> 1 Ember Orb', 1, true) ~= nil, true, 'tip names the shards: ' .. tip)
eq(tip:find('Your Ember Shards: 3,200.', 1, true) ~= nil, true, 'tip has the count')
eq(tip:find('Shift', 1, true), nil, 'no recycle line')
tip = V.tip(rune, sv)
eq(tip:find('25 rune shards -> 1 Orb of Upheaval', 1, true) ~= nil, true, 'rune tip')
eq(tip:find('Shift+click: recycle your Orb of Upheaval into 10 rune shards each.', 1, true) ~= nil, true, 'recycle line')
eq(tip:find('Your ', 1, true), nil, 'no count line on a rune recipe')

if fails > 0 then
  print(string.format('recipeview_test: %d of %d checks failed', fails, checks))
  os.exit(1)
end
print(string.format('recipeview_test: %d checks ok', checks))
