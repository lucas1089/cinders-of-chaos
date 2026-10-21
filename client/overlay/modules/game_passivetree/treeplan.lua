-- Passive tree planner and search: the logic without client API (tested by treeplan_test.lua; used by planner.lua and
-- search.lua). The server checks every plan again (server/data/scripts/chaos/passivetree_core.lua validatePlan).
--
-- Graph: TreePlan.graph(nodes) from the client's nodes.lua list (`out` and `inputs`, undirected; hidden nodes and
-- links to missing nodes left out). A class section's start node is a node of its own here (the server folds it into
-- the root); it is always owned, so a path grows from it like from the root.
--
-- Plan state (TreePlan.new): list (planned ids in the order they were added), set, masteries ({[id] = chosen effect}
-- of planned mastery nodes), undo / redo (snapshots, at most HISTORY). Every change records a snapshot first, so undo
-- and redo restore whole states; the server sync (prune) and reset are not recorded.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
TreePlan = {}

local HISTORY = 100
TreePlan.HISTORY = HISTORY

-- ------------------------------------------------------------------------------------------------ graph
function TreePlan.graph(nodes)
  local adj = {}
  local function link(a, b)
    if a == b or not nodes[a] or not nodes[b] or nodes[a].hidden or nodes[b].hidden then
      return
    end
    adj[a] = adj[a] or {}
    adj[b] = adj[b] or {}
    adj[a][b] = true
    adj[b][a] = true
  end
  for id, node in pairs(nodes) do
    for _, list in ipairs({node.out or {}, node.inputs or {}}) do
      for _, other in pairs(list) do
        link(id, other)
      end
    end
  end
  local out = {}
  for id, set in pairs(adj) do
    local list = {}
    for other in pairs(set) do
      list[#list + 1] = other
    end
    table.sort(list)
    out[id] = list
  end
  return out
end

-- Makes every link of nodes.lua listed on both ends: a link a -> b (in a's `out` or `inputs`) that b does not list
-- is added to b's `inputs`. The server stores the links undirected (tools/gen_passivetree_data.lua); the window reads
-- a node's own lists (canAllocate, refreshConnectors, the respec checks), so a one-sided link left the node past it
-- dim although the server had it allocated (node 115 behind 50). Returns the number of links added.
function TreePlan.linkBack(nodes)
  local added = 0
  local function lists(node, id)
    for _, list in ipairs({node.out or {}, node.inputs or {}}) do
      for _, other in pairs(list) do
        if other == id then
          return true
        end
      end
    end
    return false
  end
  local ids = {}
  for id in pairs(nodes) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local node = nodes[id]
    for _, list in ipairs({node.out or {}, node.inputs or {}}) do
      for _, other in pairs(list) do
        local back = nodes[other]
        if back and other ~= id and not lists(back, id) then
          back.inputs = back.inputs or {}
          back.inputs[#back.inputs + 1] = id
          added = added + 1
        end
      end
    end
  end
  return added
end

-- The ids of an allocation shown as allocated (a set): every id of `ids` that connects to a start node (starts: a
-- set) through the shown ids, over the undirected graph adj (TreePlan.graph), like the server's check (passivetree_core
-- reach). shown(id): the window has the node (nodeMap); excluded(id, set): a twin of it is in (node.exclude).
function TreePlan.connected(adj, ids, starts, shown, excluded)
  local wanted = {}
  for _, raw in pairs(ids or {}) do
    local id = tonumber(raw)
    if id and not starts[id] and (not shown or shown(id)) then
      wanted[id] = true
    end
  end
  local reached, queue, head = {}, {}, 1
  local sorted = {}
  for id in pairs(starts) do
    sorted[#sorted + 1] = id
  end
  table.sort(sorted)
  for _, id in ipairs(sorted) do
    reached[id] = true
    queue[#queue + 1] = id
  end
  while head <= #queue do
    local id = queue[head]
    head = head + 1
    for _, other in ipairs(adj[id] or {}) do
      if wanted[other] and not reached[other] and not (excluded and excluded(other, reached)) then
        reached[other] = true
        queue[#queue + 1] = other
      end
    end
  end
  return reached
end

-- The allocated set the planner grows from: the ids shown allocated (a map of id -> node or true) and the ids the
-- server saved (a set). A saved id the window shows dim still counts as owned, so it is never planned or priced.
function TreePlan.ownedIds(shown, saved)
  local set = {}
  for id in pairs(shown or {}) do
    set[id] = true
  end
  for id, on in pairs(saved or {}) do
    if on then
      set[id] = true
    end
  end
  return set
end

-- Shortest path from the owned set (allocated and planned ids, a set) to target: a breadth-first walk from every owned
-- node at once, only onto nodes passable(id) accepts (shown, the class may hold it, not a start node). Ties go to the
-- lower ids (sorted sources and neighbours), so the same click always plans the same path.
-- Returns the new ids from the owned side to target (target last), {} when target is owned, or nil (no path).
function TreePlan.findPath(adj, owned, target, passable)
  if owned[target] then
    return {}
  end
  if not passable(target) then
    return nil
  end
  local sources = {}
  for id in pairs(owned) do
    sources[#sources + 1] = id
  end
  table.sort(sources)
  local parent, queue, head = {}, {}, 1
  for _, id in ipairs(sources) do
    parent[id] = false
    queue[#queue + 1] = id
  end
  while head <= #queue do
    local id = queue[head]
    head = head + 1
    for _, other in ipairs(adj[id] or {}) do
      if parent[other] == nil and passable(other) then
        parent[other] = id
        if other == target then
          local path, at = {}, other
          while at and not owned[at] do
            table.insert(path, 1, at)
            at = parent[at]
          end
          return path
        end
        queue[#queue + 1] = other
      end
    end
  end
  return nil
end

-- ------------------------------------------------------------------------------------------------ plan state
function TreePlan.new()
  return {list = {}, set = {}, masteries = {}, undo = {}, redo = {}}
end

local function snapshot(state)
  local list, masteries = {}, {}
  for i, id in ipairs(state.list) do
    list[i] = id
  end
  for id, choice in pairs(state.masteries) do
    masteries[id] = choice
  end
  return {list = list, masteries = masteries}
end

local function restore(state, snap)
  state.list, state.set, state.masteries = {}, {}, {}
  for i, id in ipairs(snap.list) do
    state.list[i] = id
    state.set[id] = true
  end
  for id, choice in pairs(snap.masteries) do
    state.masteries[id] = choice
  end
end

local function record(state)
  state.undo[#state.undo + 1] = snapshot(state)
  if #state.undo > HISTORY then
    table.remove(state.undo, 1)
  end
  state.redo = {}
end

function TreePlan.cost(state)
  return #state.list
end

function TreePlan.isEmpty(state)
  return #state.list == 0
end

function TreePlan.has(state, id)
  return state.set[id] == true
end

-- adds a path (from findPath); returns the number of new ids
function TreePlan.addPath(state, path)
  local fresh = {}
  for _, id in ipairs(path or {}) do
    if not state.set[id] then
      fresh[#fresh + 1] = id
    end
  end
  if #fresh == 0 then
    return 0
  end
  record(state)
  for _, id in ipairs(fresh) do
    state.list[#state.list + 1] = id
    state.set[id] = true
  end
  return #fresh
end

-- takes a planned id out, with every planned id that no longer connects to the allocated set (allocated: a set)
-- through allocated and planned ids. Returns the removed ids.
function TreePlan.remove(state, id, adj, allocated)
  if not state.set[id] then
    return {}
  end
  record(state)
  local keep = {}
  for _, other in ipairs(state.list) do
    if other ~= id then
      keep[other] = true
    end
  end
  local reached, queue, head = {}, {}, 1
  local sources = {}
  for other in pairs(allocated) do
    sources[#sources + 1] = other
  end
  table.sort(sources)
  for _, other in ipairs(sources) do
    reached[other] = true
    queue[#queue + 1] = other
  end
  while head <= #queue do
    local at = queue[head]
    head = head + 1
    for _, nb in ipairs(adj[at] or {}) do
      if keep[nb] and not reached[nb] then
        reached[nb] = true
        queue[#queue + 1] = nb
      end
    end
  end
  local list, removed = {}, {}
  for _, other in ipairs(state.list) do
    if other ~= id and reached[other] then
      list[#list + 1] = other
    else
      removed[#removed + 1] = other
      state.set[other] = nil
      state.masteries[other] = nil
    end
  end
  state.list = list
  return removed
end

function TreePlan.setMastery(state, id, choice)
  if not state.set[id] or state.masteries[id] == choice then
    return false
  end
  record(state)
  state.masteries[id] = choice
  return true
end

function TreePlan.clear(state)
  if #state.list == 0 then
    return false
  end
  record(state)
  state.list, state.set, state.masteries = {}, {}, {}
  return true
end

function TreePlan.undo(state)
  local snap = table.remove(state.undo)
  if not snap then
    return false
  end
  state.redo[#state.redo + 1] = snapshot(state)
  restore(state, snap)
  return true
end

function TreePlan.redo(state)
  local snap = table.remove(state.redo)
  if not snap then
    return false
  end
  state.undo[#state.undo + 1] = snapshot(state)
  restore(state, snap)
  return true
end

-- the server's allocation arrived: planned ids that are allocated now leave the plan (not recorded)
function TreePlan.prune(state, allocated)
  local list, changed = {}, false
  for _, id in ipairs(state.list) do
    if allocated[id] then
      state.set[id] = nil
      state.masteries[id] = nil
      changed = true
    else
      list[#list + 1] = id
    end
  end
  state.list = list
  return changed
end

-- an empty plan and no history (after an apply, or the tree of another character)
function TreePlan.reset(state)
  state.list, state.set, state.masteries, state.undo, state.redo = {}, {}, {}, {}, {}
end

-- planned mastery ids without a chosen effect (isMastery(id) -> bool), in plan order
function TreePlan.missingMasteries(state, isMastery)
  local out = {}
  for _, id in ipairs(state.list) do
    if isMastery(id) and not state.masteries[id] then
      out[#out + 1] = id
    end
  end
  return out
end

-- the planApply request: {nodes = {ids}, masteries = {{id, choice}}}
function TreePlan.request(state)
  local nodes, masteries = {}, {}
  for i, id in ipairs(state.list) do
    nodes[i] = id
  end
  for _, id in ipairs(state.list) do
    if state.masteries[id] then
      masteries[#masteries + 1] = {id = id, choice = state.masteries[id]}
    end
  end
  return {nodes = nodes, masteries = masteries}
end

-- "Plan: 5 / 12 points", and whether it fits
function TreePlan.costText(cost, free)
  free = math.max(0, math.floor(tonumber(free) or 0))
  if cost == 0 then
    return tr('No plan: click a node to plan the path to it.'), true
  end
  local fits = cost <= free
  return string.format('Plan: %d / %d point%s%s', cost, free, free == 1 and '' or 's',
    fits and '' or string.format(' (%d short)', cost - free)), fits
end

-- ------------------------------------------------------------------------------------------------ search
function TreePlan.normalize(text)
  text = tostring(text or ''):lower():gsub('%s+', ' ')
  return (text:gsub('^ ', ''):gsub(' $', ''))
end

-- entries: list of {id = n, text = lower case name and bonus lines}; query: words that must all be found (plain text,
-- any order). Returns the matching ids in the order of entries.
function TreePlan.search(entries, query)
  local words = {}
  for word in TreePlan.normalize(query):gmatch('%S+') do
    words[#words + 1] = word
  end
  local out = {}
  if #words == 0 then
    return out
  end
  for _, entry in ipairs(entries) do
    local text = entry.text or ''
    local all = true
    for _, word in ipairs(words) do
      if not text:find(word, 1, true) then
        all = false
        break
      end
    end
    if all then
      out[#out + 1] = entry.id
    end
  end
  return out
end

-- the next index after `index` in 1..count going dir (+1 / -1), wrapping; 0 when count is 0
function TreePlan.step(index, count, dir)
  if count <= 0 then
    return 0
  end
  index = tonumber(index) or 0
  if index < 1 or index > count then
    return dir < 0 and count or 1
  end
  return (index - 1 + (dir < 0 and -1 or 1)) % count + 1
end

-- "3 / 12", "No match", ""
function TreePlan.countText(index, count, query)
  if TreePlan.normalize(query) == '' then
    return ''
  end
  if count == 0 then
    return tr('No match')
  end
  return string.format('%d / %d', index, count)
end

return TreePlan
