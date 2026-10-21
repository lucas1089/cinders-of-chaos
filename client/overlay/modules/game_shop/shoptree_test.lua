-- luajit shoptree_test.lua && lua5.3 shoptree_test.lua
-- The store's category tree (shoptree.lua): building it from the server's lists, an old server's flat list, counts,
-- the rows shown, opening and closing a parent, the path over the offers, finding a category by name.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'shoptree.lua')
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- as the server sends them (shop.lua): the flat list in tree order, then the parents
local cats = {
  { name = 'Starter', size = 3 },
  { name = 'This week', size = 5, endsIn = 3600 },
  { name = 'Bundles', size = 6 },
  { name = 'Premium Time', size = 3, parent = 'Premium & Services' },
  { name = 'Services', size = 5, parent = 'Premium & Services' },
  { name = 'Potions', size = 4, parent = 'Consumables' },
  { name = 'Outfits', size = 56, parent = 'Cosmetics' },
  { name = 'Wings', size = 21, parent = 'Cosmetics' },
  { name = 'Auras', size = 24, parent = 'Cosmetics' },
  { name = 'Crafting', size = 3 },
}
local groups = {
  { name = 'Premium & Services', size = 8, type = 'item', item = 3725 },
  { name = 'Consumables', size = 4, type = 'item', item = 7590 },
  -- Cosmetics without its own entry: made from its first subcategory, the count summed
}

local nodes = ShopTree.build(cats, groups)
eq(#nodes, 7, 'top nodes: Starter, This week, Bundles, three parents, Crafting')
eq(nodes[1].kind .. nodes[1].index, 'leaf1', 'Starter is a top category')
eq(nodes[4].kind, 'group', 'a parent')
eq(nodes[4].name, 'Premium & Services', 'the parent where its first subcategory is')
eq(#nodes[4].children, 2, 'its subcategories')
eq(nodes[4].children[2].index, 5, 'a subcategory keeps the server index')
eq(nodes[4].size, 8, 'the parent count the server sends')
eq(nodes[4].data.item, 3725, 'the parent icon from category_groups')
eq(nodes[6].name, 'Cosmetics', 'a parent missing from category_groups')
eq(nodes[6].size, 56 + 21 + 24, 'its count summed')
eq(nodes[6].data.name, 'Outfits', 'its icon from its first subcategory')
eq(nodes[7].name, 'Crafting', 'a top category after the parents')

-- an old server: no parent, no size, no groups -> the flat list, no counts
local flat = ShopTree.build({ { name = 'Wings' }, { name = 'Auras' } }, nil)
eq(#flat, 2, 'flat list')
eq(flat[2].kind .. flat[2].index, 'leaf2', 'flat leaf')
eq(ShopTree.label(flat[1].name, flat[1].size), 'Wings', 'no count without size')
eq(#ShopTree.rows(flat, {}), 2, 'every flat category shown')

-- rows: the parents closed, then one open
local rows = ShopTree.rows(nodes, {})
eq(#rows, 7, 'closed: only the top rows')
rows = ShopTree.rows(nodes, { Cosmetics = true })
eq(#rows, 10, 'Cosmetics open: its three subcategories too')
eq(rows[7].node.name .. rows[7].depth, 'Outfits1', 'a subcategory row is indented')
eq(rows[6].expanded, true, 'the open parent says so')
eq(rows[4].expanded, false, 'a closed parent says so')

-- toggle: one parent open at a time; opening selects its first subcategory unless the selection is inside
local ex, sel = ShopTree.toggle(nodes, {}, 'Cosmetics', 1)
eq(ex.Cosmetics, true, 'open'); eq(sel, 7, 'its first subcategory selected')
ex, sel = ShopTree.toggle(nodes, { Consumables = true }, 'Cosmetics', 8)
eq(ex.Consumables, nil, 'the other parent closes'); eq(sel, nil, 'the selection inside stays')
ex, sel = ShopTree.toggle(nodes, { Cosmetics = true }, 'Cosmetics', 8)
eq(next(ex), nil, 'a click on the open parent closes it'); eq(sel, nil, 'selection kept')
ex, sel = ShopTree.toggle(nodes, { Cosmetics = true }, 'Nope', 8)
eq(ex.Cosmetics, true, 'an unknown parent changes nothing'); eq(sel, nil, 'unknown: no selection')

-- path, reveal, find
local p = ShopTree.path(nodes, 8)
eq(#p .. p[1] .. '/' .. p[2], '2Cosmetics/Wings', 'path of a subcategory')
p = ShopTree.path(nodes, 3)
eq(#p .. p[1], '1Bundles', 'path of a top category')
eq(#ShopTree.path(nodes, 99), 0, 'unknown index: no path')
eq(ShopTree.reveal(nodes, 6).Consumables, true, 'reveal opens the parent')
eq(next(ShopTree.reveal(nodes, 10)), nil, 'a top category needs no parent open')
eq(ShopTree.find(nodes, 'Wings').index, 8, 'find a subcategory by name')
eq(ShopTree.find(nodes, 'Crafting').index, 10, 'find a top category by name')
eq(ShopTree.find(nodes, 'Depot Tabs'), nil, 'a category that is gone')
eq(ShopTree.firstLeaf(nodes).index, 1, 'the first category')
eq(ShopTree.firstLeaf({ nodes[6] }).index, 7, 'the first category of a parent')
eq(ShopTree.groupOf(nodes, 9).name, 'Cosmetics', 'group of a subcategory')
eq(ShopTree.groupOf(nodes, 2), nil, 'no group for a top category')

-- labels
eq(ShopTree.label('Wings', 21), 'Wings (21)', 'label with a count')
eq(ShopTree.label('Cosmetics', '101'), 'Cosmetics (101)', 'a count as text')

if fails > 0 then error(fails .. ' failure(s)') end
print('shoptree_test: ' .. checks .. ' checks passed')
