-- luajit shopview_test.lua && lua5.3 shopview_test.lua
-- The store's new layout (shopview.lua, O556): the rail, the chips of a group, the home page pick, the card states,
-- the details plan and the filter of the search results.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'shoptree.lua')
dofile(dir .. 'shopview.lua')
local V = ShopView
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local cats = {
  { name = 'Starter', size = 3 },
  { name = 'This week', size = 5, endsIn = 3600 },
  { name = 'Bundles', size = 6 },
  { name = 'Premium Time', size = 3, parent = 'Premium & Services' },
  { name = 'Services', size = 5, parent = 'Premium & Services' },
  { name = 'Potions', size = 4, parent = 'Consumables' },
  { name = 'Outfits', size = 56, parent = 'Cosmetics' },
  { name = 'Wings', size = 21, parent = 'Cosmetics' },
  { name = 'Outfit Shaders', size = 14, parent = 'Cosmetics' },
  { name = 'Crafting', size = 3 },
}
local groups = { { name = 'Premium & Services', size = 8 }, { name = 'Consumables', size = 4 } }
local nodes = ShopTree.build(cats, groups)

-- the rail: one entry per top node, Home first
local rail = V.rail(nodes, true)
eq(#rail, 8, 'rail: Home, Starter, This week, Bundles, 3 parents, Crafting')
eq(rail[1].key, 'home', 'Home first')
eq(rail[2].key, 'c:1', 'a top category keeps its index')
eq(rail[3].endsIn, 3600, 'the weekly entry carries its timer')
eq(rail[5].kind .. ':' .. rail[5].name, 'group:Premium & Services', 'a parent is one entry')
eq(rail[7].size, 91, 'a parent without a size: the sum of its subcategories')
eq(#V.rail(nodes, false), 7, 'no Home entry without a home page')
eq(V.entry(rail, 'g:Cosmetics').name, 'Cosmetics', 'entry by key')
eq(V.entry(rail, 'zzz'), nil, 'unknown key')
eq(V.railKeyOf(nodes, 8), 'g:Cosmetics', 'the rail key of a subcategory is its parent')
eq(V.railKeyOf(nodes, 2), 'c:2', 'of a top category itself')
eq(V.railKeyOf(nodes, 99), nil, 'unknown category')
-- what an entry opens
eq(V.indexFor(nodes, V.entry(rail, 'c:10')), 10, 'a leaf opens itself')
eq(V.indexFor(nodes, V.entry(rail, 'g:Cosmetics')), 7, 'a parent opens its first subcategory')
eq(V.indexFor(nodes, V.entry(rail, 'g:Cosmetics'), 8), 8, 'or the one already shown inside it')
eq(V.indexFor(nodes, V.entry(rail, 'g:Cosmetics'), 2), 7, 'a category outside it does not count')
eq(V.indexFor(nodes, nil), nil, 'no entry')
eq(V.indexFor(nodes, V.entry(rail, 'home')), nil, 'Home opens no category')

-- chips: the subcategories of a group, the count in the text when it fits
local chips = V.chips(nodes, 'Cosmetics', 19)
eq(#chips, 3, 'three chips')
eq(chips[2].index, 8, 'a chip keeps the server index')
eq(chips[2].text, 'Wings (21)', 'name and count')
eq(chips[3].text, 'Outfit Shaders (14)', 'fits in 19')
eq(V.chips(nodes, 'Cosmetics', 12)[3].text, 'Outfit Sh...', 'does not fit: the name alone, clipped')
eq(#V.chips(nodes, 'Crafting', 19), 0, 'a top category has no chips')
eq(V.chipText('Wings', nil, 19), 'Wings', 'no count without size')
eq(V.chipText('Wings', 21, nil), 'Wings (21)', 'no limit')

-- clip: never longer than max, never inside a UTF-8 sequence
eq(V.clip('Frostborn Set', 20), 'Frostborn Set', 'fits')
eq(V.clip('Wings of the Eternal Flame', 12), 'Wings of...', 'clipped with dots')
eq(#V.clip('Wings of the Eternal Flame', 12) <= 12, true, 'not longer than max')
eq(V.clip('Po\xC3\xA7\xC3\xB5es de Mana Grandes', 5), 'Po...', 'the cut backs off a half sequence')
eq(V.clip('abcdef', 3), 'abc', 'max 3 or less: no dots')
eq(V.clip(nil, 5), '', 'nil')

-- the home page: weekly first, then the starter packs, then the bundles
local home = V.homeSections(nodes)
eq(#home, 3, 'three sections')
eq(home[1].key .. home[1].index, 'weekly2', 'the weekly strip on top')
eq(home[1].endsIn, 3600, 'with its timer')
eq(home[2].key .. home[2].index, 'starter1', 'starter packs')
eq(home[3].key .. home[3].index, 'bundles3', 'bundles')
eq(home[3].size, 6, 'the count')
-- no starter pack for sale, no rotation: what is there
local home2 = V.homeSections(ShopTree.build({ { name = 'Bundles', size = 2 }, { name = 'Wings', parent = 'Cosmetics', size = 3 } }, nil))
eq(#home2, 1, 'only the bundles')
eq(#V.homeSections(ShopTree.build({ { name = 'Wings' } }, nil)), 0, 'an old server: no home page')
eq(#V.homeSections(nil), 0, 'nil')
-- a subcategory called Bundles is no top category
eq(#V.homeSections(ShopTree.build({ { name = 'Bundles', parent = 'Cosmetics' } }, nil)), 0, 'inside a parent does not count')
-- the limit per section and the pick
eq(V.homeLimit('weekly', 3), 6, 'weekly: two rows')
eq(V.homeLimit('bundles', 3), 3, 'bundles: one row')
eq(V.homeLimit('starter', 0), 1, 'at least one column')
local offers = { { title = 'a' }, { title = 'b' }, { title = 'c' }, { title = 'd' }, { title = 'e' } }
local pick, more = V.homePick(offers, 3, 6)
eq(#pick, 3, 'three shown')
eq(more, 3, 'the rest of the category (size 6)')
pick, more = V.homePick(offers, 6, nil)
eq(#pick .. ':' .. more, '5:0', 'everything shown, no size')
pick, more = V.homePick(nil, 3, 4)
eq(#pick .. ':' .. more, '0:4', 'page not here yet: the whole size is "more"')
eq(V.columns(540, 170, 6), 3, 'three columns in 540 px')
eq(V.columns(212, 170, 6), 1, 'one column on the phone')
eq(V.columns(0, 170, 6), 1, 'width unknown: one')
eq(V.gridHeight(5, 3, 68, 6), 142, 'five cards, three columns: two rows')
eq(V.gridHeight(0, 3, 68, 6), 0, 'none: no height')
eq(V.gridHeight(3, 3, 68, 6), 68, 'one row')

-- tags
eq(V.tagKind('New'), 'new', 'new')
eq(V.tagKind('Featured'), 'featured', 'featured')
eq(V.tagKind('Sale -20%'), 'sale', 'sale')
eq(V.tagKind('Launch sale -20%'), 'sale', 'a named sale')
eq(V.tagKind('Limited'), 'other', 'other')
eq(V.salePercent({ 'New', 'Launch sale -20%' }), 20, 'percentage from the tag')
eq(V.salePercent({ 'New' }), nil, 'none')
eq(V.salePercent(nil), nil, 'nil')

-- tag labels through a translator
local up = function(k) return '<' .. k .. '>' end
eq(V.tagLabel('New', up), '<New>', 'new label')
eq(V.tagLabel('Featured', up), '<Featured>', 'featured label')
eq(V.tagLabel('Launch sale -20%', up), '<Launch sale> -20%', 'a named sale keeps its percentage')
eq(V.tagLabel('Sale -5%', up), '<Sale> -5%', 'sale')
eq(V.tagLabel('Limited', up), '<Limited>', 'another tag')
eq(V.tagLabel('Limited'), 'Limited', 'no translator')

-- card states
local st = V.cardState({ cost = 100, tags = { 'New' } }, 500)
eq(st.badge, 'new', 'new badge')
eq(st.priceKind, 'normal', 'normal price')
eq(st.affordable, true, 'affordable')
st = V.cardState({ cost = 100, oldCost = 125, tags = { 'Sale -20%', 'New' } }, 500)
eq(st.badge .. st.badgeText, 'sale-20%', 'sale beats new, with the percentage')
eq(st.priceKind, 'sale', 'sale price')
st = V.cardState({ cost = 90, oldCost = 100 }, 500)
eq(st.badgeText, '-10%', 'percentage from the two prices when no tag says it')
st = V.cardState({ cost = 100, oldCost = 125, tags = { 'Sale -20%' }, owned = true }, 500)
eq(st.badge .. st.priceKind, 'ownedowned', 'owned beats the sale')
st = V.cardState({ cost = 600 }, 500)
eq(st.affordable, false, 'not affordable')
eq(st.missing, 100, 'coins short')
eq(st.priceKind, 'poor', 'poor price')
st = V.cardState({ cost = 600 }, nil)
eq(st.affordable, true, 'balance unknown: the server decides')
st = V.cardState({ cost = 600, tags = { 'Limited' } }, 1000)
eq(st.badge .. ':' .. st.badgeText, 'other:Limited', 'another tag shows as it is')
st = V.cardState({ cost = 5, tags = { 'Featured' } }, 10)
eq(st.badge, 'featured', 'featured')
st = V.cardState(nil, 10)
eq(st.badge, nil, 'nil data')
eq(V.subLine({ type = 'item', count = 100 }), 'x100', 'a pack of 100')
eq(V.subLine({ type = 'item', count = 1 }), '', 'a single item')
eq(V.subLine({ type = 'outfit', count = 3 }), '', 'a creature has no pack count')
eq(V.historyDate('Bought on 2026-11-14 12:30 for 40 Chaos Coins.'), '2026-11-14 12:30', 'history date')
eq(V.historyDate('Comprado'), nil, 'no date')

-- the details plan
local sel = { category = 1, page = 1, offer = 1 }
local plan = V.detailPlan({ cost = 100, gift = true }, 500, sel, true, { show = true })
eq(plan.buy and plan.giftEnabled and plan.gift and plan.try, true, 'everything on')
eq(plan.note, nil, 'no note')
eq(plan.hasLook, true, 'look column')
plan = V.detailPlan({ cost = 100, gift = true, owned = true }, 500, sel, false, nil)
eq(plan.buy, false, 'owned: no buy')
eq(plan.note, 'owned', 'owned note')
eq(plan.try, false, 'no try plan, no button')
plan = V.detailPlan({ cost = 900, gift = true }, 500, sel, false, { show = false })
eq(plan.buy, false, 'poor: no buy')
eq(plan.gift, true, 'gift still shown')
eq(plan.giftEnabled, false, 'but off')
eq(plan.note, 'poor', 'poor note')
eq(plan.missing, 400, 'the missing coins')
plan = V.detailPlan({ cost = 900 }, 500, nil, false, nil)
eq(plan.showBuy, false, 'a history line has no buy')
eq(plan.note, 'history', 'history note')

-- the search results: filter chips by top group
local results = {
  { title = 'a', path = { 'Cosmetics', 'Wings' } }, { title = 'b', path = { 'Cosmetics', 'Auras' } },
  { title = 'c', path = { 'Consumables', 'Potions' } }, { title = 'd', path = { 'Bundles' } },
}
local rg = V.resultGroups(results)
eq(#rg, 4, 'All and three groups')
eq(rg[1].name, nil, 'All first')
eq(rg[1].count, 4, 'the total')
eq(rg[2].name .. rg[2].count, 'Cosmetics2', 'in order of appearance')
eq(rg[4].name .. rg[4].count, 'Bundles1', 'a top category is its own group')
eq(#V.resultGroups({ results[1], results[2] }), 0, 'one group: nothing to filter')
eq(#V.resultGroups(nil), 0, 'nil')
eq(#V.filterResults(results, 'Cosmetics'), 2, 'the group')
eq(#V.filterResults(results, nil), 4, 'all')
eq(#V.filterResults(results, 'Nothing'), 0, 'none')
eq(#V.filterResults(nil, nil), 0, 'nil list')

eq(V.pageText(2, 5), '2 / 5', 'page text')
eq(V.pageText(1, 1), '', 'one page: none')
eq(V.pageText(9, 3), '3 / 3', 'clamped')

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks FAILED') os.exit(1) end
print('shopview_test: ' .. checks .. ' checks OK')
