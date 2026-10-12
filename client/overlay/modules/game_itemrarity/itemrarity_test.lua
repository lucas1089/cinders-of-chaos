-- luajit itemrarity_test.lua && lua5.3 itemrarity_test.lua
-- The rarity of an item from its custom attributes (server engine patch 0003), the description-tag fallback for servers
-- without it, and the frame colour.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local features = {}
g_game = { getFeature = function(f) return features[f] == true end }
dofile(dir .. 'itemrarity.lua')
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local function item(attrs, tooltip)
  return {
    getCustomAttribute = function(self, k) return attrs[k] or 0 end,
    getTooltip = function() return tooltip or '' end
  }
end

eq(ChaosItemAttr.RARITY, 1, 'rarity key') eq(ChaosItemAttr.VERSION, 7, 'version key')

-- a server that sends attributes
features[126] = true
eq(hasItemAttributes(), true, 'feature on')
eq(getItemRarityId(item({ [1] = 5 })), 5, 'rarity from the attribute')
eq(getRarityName(5), 'Legendary', 'name')
eq(getItemRarityId(item({}, 'a [MYTHIC] sword')), 0, 'with attributes the description tag is not read')
eq(getItemRarityId(item({ [1] = 99 })), 0, 'unknown rarity')
eq(getItemFrameColor(item({ [1] = 3 })), '#4a90ff', 'rare frame')
eq(getItemFrameColor(item({ [1] = 3, [4] = 1 })), getUniqueColor(), 'unique frame wins')
eq(isUniqueItem(item({ [4] = 1 })), true, 'unique flag')
eq(getItemFrameColor(item({})), nil, 'plain item: no frame')
eq(getItemAttribute(nil, 1), 0, 'no item')
eq(getItemAttribute({}, 1), 0, 'an item without the method (old engine)')

-- a server without the patch: the description tag
features[126] = nil
eq(getItemRarityId(item({}, '[EPIC] Dawnforged Helmet')), 4, 'tag fallback')
eq(getItemRarityId(item({}, '[DIVINE] [X] ring')), 10, 'older tag name')
eq(getItemRarityId(item({}, '[FOO] ring')), 0, 'other tags ignored')
eq(getItemRarityId(nil), 0, 'nil item')

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('itemrarity_test: ' .. checks .. ' checks OK')
