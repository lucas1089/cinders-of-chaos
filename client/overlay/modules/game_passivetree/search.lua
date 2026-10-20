-- Passive tree search (the matching is treeplan.lua TreePlan.search, tested by treeplan_test.lua). The box at the
-- bottom left finds the shown nodes whose name or bonus text holds every typed word (any case, any order): mastery
-- effects and keystone lines count. Every match gets a gold frame, the current one an orange frame and the view
-- centred on it; Next / Prev (Enter / Shift+Enter in the box) step through the matches, the label counts them.
local entries, entriesFor = nil, nil
local matches, index = {}, 0
local marked = {} -- [widget] = true: widgets with a search frame
local MATCH, CURRENT = '#e8c25a', '#ff7a2a'

local function child(id)
  local window = getTreeWindow()
  return window and window:recursiveGetChildById(id)
end

-- the searchable text of a node: its name and stat lines as the class sees them (its class variant's: a keystone of
-- 621 / 624 or a class lane, treelanes.lua, so a re-skinned "Pyre Litany" is found by its new name and stats, not by
-- "holy"), the description lines and the effects
local function nodeText(node)
  local parts = {}
  local function add(list)
    for _, line in ipairs(list or {}) do
      parts[#parts + 1] = line
    end
  end
  local variant = getTreeVariant()
  local own = variant and node[variant]
  -- a class lane replaces the node's own name and stats for that class; a keystone keeps its base name ("... Keystone")
  local lane = type(own) == 'table' and own.customStats ~= nil and not node.isKeystone
  if not lane then
    parts[#parts + 1] = node.name or ''
  end
  for key, value in pairs(node) do
    if type(value) == 'table' and value.customStats and key ~= 'masteries' and
      (key == variant or (variant == nil and node.isKeystone and value.name)) then
      parts[#parts + 1] = TreeLanes.displayName(node, key) or ''
      add(getCustomStatString(value.customStats))
      add(value.stats)
    end
  end
  if node.customStats and not lane then
    add(getCustomStatString(node.customStats, true))
  end
  add(node.stats)
  for _, effect in ipairs(node.masteries or {}) do
    parts[#parts + 1] = effect.name
    add(getCustomStatString(effect.customStats or {}))
  end
  return TreePlan.normalize(table.concat(parts, ' '))
end

local function buildEntries()
  local map = getTreeNodeMap() or {}
  if entriesFor == map and entries then
    return entries
  end
  local ids = {}
  for id, node in pairs(map) do
    if not node.isStartNode then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  entries = {}
  for _, id in ipairs(ids) do
    entries[#entries + 1] = {id = id, text = nodeText(map[id])}
  end
  entriesFor = map
  return entries
end

local function unmarkAll()
  for widget in pairs(marked) do
    if not widget:isDestroyed() then
      widget.searchFrame = nil
      applyTreeNodeBorder(widget) -- passivetree.lua: back to the Stats mark or none
    end
  end
  marked = {}
end

local function mark()
  unmarkAll()
  for i, id in ipairs(matches) do
    local widget = getTreeNodeWidget(id)
    if widget then
      widget.searchFrame = {width = i == index and 3 or 2, color = i == index and CURRENT or MATCH}
      applyTreeNodeBorder(widget)
      marked[widget] = true
    end
  end
  local label = child('searchCount')
  if label then
    local edit = child('searchEdit')
    label:setText(TreePlan.countText(index, #matches, edit and edit:getText() or ''))
    label:setColor(#matches == 0 and '#e07060' or '#d8cfc0')
  end
end

local function go(i)
  index = i
  local node = (getTreeNodeMap() or {})[matches[index] or 0]
  if node then
    panTreeTo(node)
  end
  mark()
end

-- the box's text changed
function onTreeSearchChange()
  local edit = child('searchEdit')
  local query = edit and edit:getText() or ''
  matches = TreePlan.search(buildEntries(), query)
  index = 0
  if #matches > 0 then
    go(1)
  else
    mark()
  end
end

function treeSearchNext()
  if #matches > 0 then
    go(TreePlan.step(index, #matches, 1))
  end
end

function treeSearchPrev()
  if #matches > 0 then
    go(TreePlan.step(index, #matches, -1))
  end
end

-- new widgets (a zoom level, another class, an inspected tree): the matches again, without moving the view
function refreshTreeSearch()
  local edit = child('searchEdit')
  if not edit or edit:getText() == '' then
    unmarkAll()
    return
  end
  local current = matches[index]
  matches = TreePlan.search(buildEntries(), edit:getText())
  index = 0
  for i, id in ipairs(matches) do
    if id == current then
      index = i
    end
  end
  mark()
end

function clearTreeSearch()
  local edit = child('searchEdit')
  if edit then
    edit:setText('')
  end
  matches, index = {}, 0
  unmarkAll()
  mark()
end

function focusTreeSearch()
  local edit = child('searchEdit')
  if edit then
    edit:focus()
    edit:selectAll()
  end
end
