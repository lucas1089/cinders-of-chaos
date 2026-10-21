-- Pure helpers of the store's category tree (server shop.lua: "category_groups" + "categories"). The layout of the base
-- server's store window: top categories, and parents (Cosmetics, Consumables ...) that open to their subcategories.
-- The server sends the flat list of the categories that sell (each with its index, `size` offers and `parent`) and the
-- parents; a server without the tree sends no parent, and the list stays flat. No client API; shoptree_test.lua.
ShopTree = {}

-- categories: the server's list (index = the category id the client asks pages for); groups: the parents
-- ({name, size?, ...} with their icon fields). -> nodes in list order: a leaf {kind = 'leaf', index, name, size, data}
-- or a group {kind = 'group', name, size, data, children = {leaf, ...}} where its first subcategory stands. A parent
-- missing from groups is made from its first subcategory (its icon).
function ShopTree.build(categories, groups)
  local byName = {}
  for _, g in ipairs(groups or {}) do
    if type(g) == 'table' and type(g.name) == 'string' then byName[g.name] = g end
  end
  local nodes, open = {}, {}
  for i, cat in ipairs(categories or {}) do
    local leaf = { kind = 'leaf', index = i, name = tostring(cat.name or ''), size = tonumber(cat.size), data = cat }
    local p = type(cat.parent) == 'string' and cat.parent ~= '' and cat.parent or nil
    if p then
      local g = open[p]
      if not g then
        g = { kind = 'group', name = p, data = byName[p] or cat, children = {} }
        open[p] = g
        nodes[#nodes + 1] = g
      end
      leaf.parent = p
      g.children[#g.children + 1] = leaf
    else
      nodes[#nodes + 1] = leaf
    end
  end
  -- a group's count: what the server says, else the sum of its subcategories (nil when none of them has a size)
  for _, n in ipairs(nodes) do
    if n.kind == 'group' then
      local sum
      for _, c in ipairs(n.children) do
        if c.size then sum = (sum or 0) + c.size end
      end
      n.size = tonumber(byName[n.name] and byName[n.name].size) or sum
    end
  end
  return nodes
end

-- the group that holds category `index`, or nil (a top category, or unknown)
function ShopTree.groupOf(nodes, index)
  for _, n in ipairs(nodes or {}) do
    if n.kind == 'group' then
      for _, c in ipairs(n.children) do
        if c.index == index then return n end
      end
    end
  end
  return nil
end

-- the leaf of category `index`, or nil
function ShopTree.leaf(nodes, index)
  for _, n in ipairs(nodes or {}) do
    if n.kind == 'leaf' and n.index == index then return n end
    for _, c in ipairs(n.children or {}) do
      if c.index == index then return c end
    end
  end
  return nil
end

-- the first leaf of the tree (or of a group node)
function ShopTree.firstLeaf(nodes)
  for _, n in ipairs(nodes or {}) do
    if n.kind == 'leaf' then return n end
    if n.children and n.children[1] then return n.children[1] end
  end
  return nil
end

-- the leaf whose name is `name` (a category shown in more than one place: the first)
function ShopTree.find(nodes, name)
  for _, n in ipairs(nodes or {}) do
    if n.kind == 'leaf' and n.name == name then return n end
    for _, c in ipairs(n.children or {}) do
      if c.name == name then return c end
    end
  end
  return nil
end

-- {group name?, category name} of category `index` (the path shown over the offers)
function ShopTree.path(nodes, index)
  local leaf = ShopTree.leaf(nodes, index)
  if not leaf then return {} end
  if leaf.parent then return { leaf.parent, leaf.name } end
  return { leaf.name }
end

-- The rows the category list shows: every top node, and the subcategories of the expanded groups.
-- expanded = {[group name] = true}. -> {{node, depth = 0 | 1, expanded = bool (groups)}}
function ShopTree.rows(nodes, expanded)
  local rows = {}
  for _, n in ipairs(nodes or {}) do
    if n.kind == 'group' then
      local open = expanded and expanded[n.name] == true or false
      rows[#rows + 1] = { node = n, depth = 0, expanded = open }
      if open then
        for _, c in ipairs(n.children) do
          rows[#rows + 1] = { node = c, depth = 1 }
        end
      end
    else
      rows[#rows + 1] = { node = n, depth = 0 }
    end
  end
  return rows
end

-- A click on a group, as the base layout does it: one group open at a time. Opening it closes the others and, when the
-- selected category is not one of its subcategories, selects its first one; a click on the open group closes it.
-- -> the new expanded set, the category index to select (nil: keep the selection)
function ShopTree.toggle(nodes, expanded, groupName, selected)
  local group
  for _, n in ipairs(nodes or {}) do
    if n.kind == 'group' and n.name == groupName then group = n end
  end
  if not group then return expanded or {}, nil end
  if expanded and expanded[groupName] then
    return {}, nil
  end
  local select
  local inside = false
  for _, c in ipairs(group.children) do
    if c.index == selected then inside = true end
  end
  if not inside and group.children[1] then select = group.children[1].index end
  return { [groupName] = true }, select
end

-- the expanded set that shows category `index` (its group open, the others closed); {} for a top category
function ShopTree.reveal(nodes, index)
  local g = ShopTree.groupOf(nodes, index)
  if g then return { [g.name] = true } end
  return {}
end

-- "Wings (21)"; the name alone without a count
function ShopTree.label(name, size)
  if tonumber(size) then return string.format('%s (%d)', tostring(name or ''), tonumber(size)) end
  return tostring(name or '')
end
