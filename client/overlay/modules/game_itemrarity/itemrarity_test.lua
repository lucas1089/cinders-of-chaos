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

-- the soft rarity outline (base patch 0044): the colours handed to the engine
eq(select(1, rarityHexToRgb('#4a90ff')), 74, 'hex red') eq(select(3, rarityHexToRgb('#4a90ff')), 255, 'hex blue')
eq(rarityHexToRgb('blue'), nil, 'not a colour') eq(rarityHexToRgb(nil), nil, 'nil colour')
local plan = getRarityOutlinePlan()
eq(#plan.colors, 16, '15 rarities and the unique colour')
eq(plan.colors[3][1], 3, 'rare slot') eq(plan.colors[3][2], 74, 'rare red') eq(plan.colors[3][4], 255, 'rare blue')
eq(plan.colors[16][1], 16, 'unique slot (the engine reads 16 as unique)')
eq(string.format('#%02x%02x%02x', plan.colors[16][2], plan.colors[16][3], plan.colors[16][4]), getUniqueColor(), 'unique colour')
eq(plan.minRarity, 2, 'common items get no outline') eq(plan.pulseFrom, 7, 'mythic and up breathe')
eq(plan.width >= 1 and plan.width <= 4, true, 'reach the engine accepts')
for _, c in ipairs(plan.colors) do
  eq(c[5] > 0 and c[5] <= 255, true, 'alpha of slot ' .. c[1])
end
-- the engine side, mocked (a client without patch 0044 has no setRarityOutlineColor)
local calls = { colors = {} }
local api = {
  setRarityOutlineColor = function(slot, r, g, b, a) calls.colors[slot] = { r, g, b, a } end,
  setRarityOutlineStyle = function(w, minR, pulse, ms) calls.style = { w, minR, pulse, ms } end,
  setRarityOutlineEnabled = function(map, slots) calls.enabled = { map, slots } end,
}
eq(applyRarityOutline(api, true, false), true, 'applied')
eq(calls.colors[5][1], 255, 'legendary colour sent') eq(calls.colors[16] ~= nil, true, 'unique colour sent')
eq(calls.style[2], 2, 'style sent') eq(calls.enabled[1], true, 'map on') eq(calls.enabled[2], false, 'slots off')
eq(applyRarityOutline({}, true, true), false, 'an engine without the patch: nothing')
eq(applyRarityOutline(nil, true, true), false, 'no engine')
Item = api
onOutlineOption('slots', false)
eq(calls.enabled[2], false, 'option: slots off')
onOutlineOption('map', false)
eq(calls.enabled[1], false, 'option: map off')
onOutlineOption('map', true) onOutlineOption('slots', true)
eq(calls.enabled[1] and calls.enabled[2], true, 'options back on')
Item = nil

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('itemrarity_test: ' .. checks .. ' checks OK')
