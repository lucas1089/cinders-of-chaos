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
eq(getItemFrameColor(item({ [1] = 3 })), '#4a90ff', 'magic frame')
-- the seven rarities: Common 1, Uncommon 2, Magic 3, Rare 4, Legendary 5, Divine 10; an old item's 6 .. 9 and 11 .. 15 are the rarity they became
local names = { 'Common', 'Uncommon', 'Magic', 'Rare', 'Legendary', 'Divine' }
local ids = getRarityIds()
eq(#ids, 6, 'six rarities an item can carry')
for i, id in ipairs(ids) do eq(getRarityName(id), names[i], 'name of ' .. id) end
eq(getRarityName(3), 'Magic', 'id 3 is Magic') eq(getRarityName(4), 'Rare', 'id 4 is Rare')
for old, want in pairs({ [6] = 5, [7] = 5, [8] = 5, [9] = 5, [11] = 10, [12] = 10, [13] = 10, [14] = 10, [15] = 10 }) do
  eq(getRarityCanonId(old), want, 'old id ' .. old)
  eq(getItemRarityId(item({ [1] = old })), want, 'an item with the old id ' .. old)
  eq(getRarityColor(old), getRarityColor(want), 'its colour is the rarity it became')
end
eq(getRarityCanonId(0), 0) eq(getRarityCanonId(16), 0, 'Unique is the flag, not an id')
eq(getRarityStyle(7), nil, 'an old Mythic has no metal look any more') eq(getRarityStyle(10) ~= nil, true, 'Divine keeps it') eq(getRarityStyle(13) ~= nil, true, 'an old Cosmic is Divine')
eq(getItemFrameColor(item({ [1] = 3, [4] = 1 })), getUniqueColor(), 'unique frame wins')
eq(isUniqueItem(item({ [4] = 1 })), true, 'unique flag')
eq(getItemFrameColor(item({})), nil, 'plain item: no frame')
eq(getItemAttribute(nil, 1), 0, 'no item')
eq(getItemAttribute({}, 1), 0, 'an item without the method (old engine)')

-- a server without the patch: the description tag
features[126] = nil
eq(getItemRarityId(item({}, '[EPIC] Dawnforged Helmet')), 4, 'tag fallback (an old name)')
eq(getItemRarityId(item({}, '[MAGIC] ring')), 3, 'tag of today') eq(getItemRarityId(item({}, '[MYTHIC] ring')), 5, 'an old name maps')
eq(getItemRarityId(item({}, '[DIVINE] [X] ring')), 10, 'older tag name')
eq(getItemRarityId(item({}, '[FOO] ring')), 0, 'other tags ignored')
eq(getItemRarityId(nil), 0, 'nil item')

-- the soft rarity outline (base patch 0044): the colours handed to the engine
eq(select(1, rarityHexToRgb('#4a90ff')), 74, 'hex red') eq(select(3, rarityHexToRgb('#4a90ff')), 255, 'hex blue')
eq(rarityHexToRgb('blue'), nil, 'not a colour') eq(rarityHexToRgb(nil), nil, 'nil colour')
local plan = getRarityOutlinePlan()
eq(#plan.colors, 16, '15 ids (the old ones are rows too) and the unique colour')
eq(plan.colors[3][1], 3, 'magic slot') eq(plan.colors[3][2], 74, 'rare red') eq(plan.colors[3][4], 255, 'rare blue')
eq(plan.colors[16][1], 16, 'unique slot (the engine reads 16 as unique)')
eq(string.format('#%02x%02x%02x', plan.colors[16][2], plan.colors[16][3], plan.colors[16][4]), getUniqueColor(), 'unique colour')
eq(plan.minRarity, 2, 'common items get no outline') eq(plan.pulseFrom, 5, 'legendary and up breathe')
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

-- the stock value frame of container slots is switched off and reset
do
  local set = {}
  local db = { setRarityItem = function(w, it) set[#set + 1] = { w, it } end }
  local function slot(item) return { itemsDatabaseRarityClip = '32 0 32 32', itemsDatabaseRarityImageSource = '/images/ui/rarity_frames',
    getItem = function() return item end, isDestroyed = function() return false end } end
  local a, b = slot('potion'), slot(nil)
  local panel = { getChildren = function() return { a, b } end, isDestroyed = function() return false end }
  eq(silenceStockValueFrames(panel, db), true, 'first call sweeps')
  eq(panel.drawRarity, false, 'panel drawRarity off')
  eq(#set, 2, 'both slots reset, the empty one too')
  eq(a.itemsDatabaseRarityClip, nil, 'remembered clip dropped (a stale frame is redrawn)')
  eq(set[2][2], nil, 'empty slot redrawn without an item')
  eq(silenceStockValueFrames(panel, db), false, 'already off: no sweep')
  eq(silenceStockValueFrames(panel, db, true), true, 'force sweeps again (container reopened in the same window)')
  eq(#set, 4, 'forced sweep reset both again')
  eq(silenceStockValueFrames(nil, db), false, 'no panel')
  eq(resetStockValueFrame(a, nil), false, 'no database')
  eq(resetStockValueFrame(a, {}), false, 'database without setRarityItem')
end

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('itemrarity_test: ' .. checks .. ' checks OK')
