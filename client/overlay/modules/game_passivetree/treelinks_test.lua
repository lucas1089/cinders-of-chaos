-- luajit treelinks_test.lua && lua5.3 treelinks_test.lua (CI runs every client module test from the repo root)
-- The tree's links agree between the client and the server, and every allocation the server accepts is shown whole.
-- A link listed on one end only (50 -> 115, 365 -> 364) left the node past it dim although the server had it saved:
-- a deep allocation down that branch showed dim until the node above (116) was taken, and the planner priced the dim
-- nodes again (a 30-point plan the server charged 0 or 1). Checks: every link of nodes.lua is listed on both ends; the
-- client's undirected links equal the server's (passivetree_data.lua, class starts folded into the root); for every
-- class, the server's path to every node it may hold (and its whole reachable tree) is shown allocated by
-- TreePlan.connected (passivetree.lua applyAllocation); TreePlan.linkBack repairs a one-sided link; the planner counts
-- saved ids as owned (TreePlan.ownedIds), so a plan never prices them.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'treeplan.lua')
dofile(dir .. 'treedata/nodes.lua')
dofile(dir .. '../../../../server/data/scripts/chaos/passivetree_data.lua')
local P = TreePlan
local nodes = getTreeNodes()
local server = ChaosPassiveTreeData
local fails, count = 0, 0
local function eq(a, b, what)
  count = count + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local function lists(node, id)
  for _, list in ipairs({node.out or {}, node.inputs or {}}) do
    for _, other in pairs(list) do
      if other == id then return true end
    end
  end
  return false
end

-- 1. every link of nodes.lua is listed on both ends
local oneSided = {}
for id, node in pairs(nodes) do
  for _, list in ipairs({node.out or {}, node.inputs or {}}) do
    for _, other in pairs(list) do
      if nodes[other] and not lists(nodes[other], id) then
        oneSided[#oneSided + 1] = id .. '->' .. other
      end
    end
  end
end
table.sort(oneSided)
eq(table.concat(oneSided, ' '), '', 'links listed on one end only')

-- 2. the client's undirected links equal the server's (a class start stands for the root there; hidden nodes left out)
local function alias(id)
  return (nodes[id] and nodes[id].isStartNode) and server.root or id
end
local clientEdges = {}
for id, node in pairs(nodes) do
  for _, list in ipairs({node.out or {}, node.inputs or {}}) do
    for _, other in pairs(list) do
      if nodes[other] and not node.hidden and not nodes[other].hidden then
        local a, b = alias(id), alias(other)
        if a ~= b then
          clientEdges[math.min(a, b) .. '-' .. math.max(a, b)] = true
        end
      end
    end
  end
end
local serverEdges = {}
for id, node in pairs(server.nodes) do
  for _, other in ipairs(node.n or {}) do
    serverEdges[math.min(id, other) .. '-' .. math.max(id, other)] = true
    eq(lists({out = server.nodes[other] and server.nodes[other].n}, id), true, 'server link ' .. id .. '-' .. other .. ' both ends')
  end
end
local onlyClient, onlyServer = {}, {}
for e in pairs(clientEdges) do if not serverEdges[e] then onlyClient[#onlyClient + 1] = e end end
for e in pairs(serverEdges) do if not clientEdges[e] then onlyServer[#onlyServer + 1] = e end end
table.sort(onlyClient)
table.sort(onlyServer)
eq(table.concat(onlyClient, ' '), '', 'links only the client has')
eq(table.concat(onlyServer, ' '), '', 'links only the server has')

-- 3. per class: what the window shows (nodeMap: shown for the line, not hidden) and the server's reach
local LINE_OF = { warrior = 'warrior', juggernaut = 'warrior', berserker = 'warrior', ranger = 'ranger',
  deadeye = 'ranger', beastmaster = 'ranger', mystic = 'mystic', elementalist = 'mystic', illusionist = 'mystic',
  thief = 'thief', ninja = 'thief', samurai = 'thief', monk = 'monk', shadowfist = 'monk', ironsage = 'monk',
  necromancer = 'necromancer', lich = 'necromancer', bonelord = 'necromancer', templar = 'templar',
  inquisitor = 'templar', sentinel = 'templar' }
-- every class key the server data names is covered
for _, node in pairs(server.nodes) do
  for key in pairs(node.c or {}) do
    eq(LINE_OF[key] ~= nil, true, 'class ' .. key .. ' has a line in this test')
  end
end

local function windowOf(line, data)
  local map = {}
  for id, node in pairs(data) do
    if not node.hidden and (not node.line or node.line == line) then
      map[id] = node
    end
  end
  local starts = {}
  for id, node in pairs(map) do
    if node.isStartNode then starts[id] = true end
  end
  return map, P.graph(map), starts
end

local function shown(map, adj, starts, ids)
  return P.connected(adj, ids, starts, function(id) return map[id] ~= nil end)
end

local classes = {}
for key in pairs(LINE_OF) do classes[#classes + 1] = key end
table.sort(classes)
for _, class in ipairs(classes) do
  local map, adj, starts = windowOf(LINE_OF[class], nodes)
  local function may(id)
    local node = server.nodes[id]
    return node ~= nil and (node.c == nil or node.c[class] == true)
  end
  -- the server's breadth-first tree from the root over the nodes this class may hold
  local parent, queue, head = {[server.root] = false}, {server.root}, 1
  while head <= #queue do
    local id = queue[head]
    head = head + 1
    local nbs = {}
    for _, other in ipairs(server.nodes[id].n or {}) do nbs[#nbs + 1] = other end
    table.sort(nbs)
    for _, other in ipairs(nbs) do
      if parent[other] == nil and may(other) then
        parent[other] = id
        queue[#queue + 1] = other
      end
    end
  end
  local all, dimPaths, notShown = {}, 0, {}
  for id in pairs(parent) do
    if id ~= server.root then
      all[#all + 1] = id
      if not map[id] then notShown[#notShown + 1] = id end
      local path, at = {}, id
      while at and at ~= server.root do
        path[#path + 1] = at
        at = parent[at]
      end
      local on = shown(map, adj, starts, path)
      for _, p in ipairs(path) do
        if not on[p] then
          dimPaths = dimPaths + 1
          print('  ' .. class .. ': path to ' .. id .. ' shows ' .. p .. ' dim')
          break
        end
      end
    end
  end
  table.sort(notShown)
  eq(table.concat(notShown, ','), '', class .. ': nodes the server lets it hold that the window does not show')
  eq(dimPaths, 0, class .. ': server paths shown with a dim node')
  local on = shown(map, adj, starts, all)
  local dim = 0
  for _, id in ipairs(all) do
    if not on[id] then dim = dim + 1 end
  end
  eq(dim, 0, class .. ': the whole reachable tree shown allocated')
end

-- 4. the tester's allocation (Warrior: down 50 -> 115, skipping 116, into the lower branch) on the tree as it was
-- before: node 115 did not list 50 and node 364 did not list 365
local function copyNodes()
  local out = {}
  for id, node in pairs(nodes) do
    local n = {}
    for k, v in pairs(node) do n[k] = v end
    n.out, n.inputs = {}, {}
    for i, v in ipairs(node.out or {}) do n.out[i] = v end
    for i, v in ipairs(node.inputs or {}) do n.inputs[i] = v end
    out[id] = n
  end
  return out
end
local old = copyNodes()
old[115].inputs = {116}
old[364].inputs = {353}
old[1].inputs = {}
local deep = {2, 30, 31, 43, 44, 45, 46, 50, 115, 117, 162, 163, 164, 350, 349, 352, 353, 364, 363, 366}
-- the window's former rule: a node joined only through its own lists
local function ownListsShown(map, ids)
  local wanted, target = {}, {}
  for _, id in ipairs(ids) do wanted[id] = true end
  for id, node in pairs(map) do if node.isStartNode then target[id] = true end end
  local progress = true
  while progress do
    progress = false
    for id in pairs(wanted) do
      if map[id] then
        for _, list in ipairs({map[id].out or {}, map[id].inputs or {}}) do
          for _, other in pairs(list) do
            if wanted[id] and target[other] then
              target[id], wanted[id], progress = true, nil, true
            end
          end
        end
      end
    end
  end
  return target
end
local oldMap = windowOf('warrior', old)
local before = ownListsShown(oldMap, deep)
eq(before[50], true, 'old tree, old rule: 50 shown')
eq(before[115], nil, 'old tree, old rule: 115 dim (the bug)')
eq(before[366], nil, 'old tree, old rule: everything past 115 dim (the bug)')
local withUpper = ownListsShown(oldMap, {2, 30, 31, 43, 44, 45, 46, 50, 116, 115, 117, 162})
eq(withUpper[115] and withUpper[162], true, 'old tree, old rule: taking 116 lit the rest (as the tester saw)')
-- the fix: the undirected graph shows it whole even on the old lists; linkBack repairs the lists themselves
local _, oldAdj, oldStarts = windowOf('warrior', old)
local after = shown(oldMap, oldAdj, oldStarts, deep)
for _, id in ipairs(deep) do
  eq(after[id], true, 'old tree, undirected: ' .. id .. ' shown')
end
eq(P.linkBack(old), 7, 'linkBack: the 7 one-sided links (115, 364 and the root ring) listed back')
eq(lists(old[115], 50) and lists(old[364], 365) and lists(old[1], 3), true, 'linkBack: listed on both ends')
eq(P.linkBack(old), 0, 'linkBack twice: nothing more')
local repaired = ownListsShown(windowOf('warrior', old), deep)
eq(repaired[366], true, 'repaired lists, old rule: the whole branch shown')
eq(P.linkBack(copyNodes()), 0, 'nodes.lua needs no repair')

-- shown ids only: a node the window does not have, a stray id and a start node are not shown
local map, adj, starts = windowOf('warrior', nodes)
local on = shown(map, adj, starts, {2, '9', 626, 999999, 'x'})
eq(on[2] and on[9], true, 'ids as numbers or strings')
eq(on[626], nil, 'another line\'s section node is not shown')
eq(on[999999], nil, 'an unknown id is not shown')
eq(shown(map, adj, starts, {9})[9], nil, 'a node cut off from the start is not shown')
local excl = P.connected(adj, {2, 9}, starts, nil, function(id, set) return id == 9 and set[2] == true end)
eq(excl[2] == true and excl[9] == nil, true, 'an excluded twin keeps the node out')

-- 5. the planner: saved ids count as owned, so a plan never prices them (the "30 points, charged 0 or 1" report)
local owned = P.ownedIds({[1] = true, [2] = true}, {[30] = true, [31] = true, [43] = true})
eq(owned[1] and owned[2] and owned[30] and owned[43], true, 'owned: shown and saved')
local passable = function(id)
  local n = map[id]
  return n ~= nil and not n.isStartNode and not owned[id] and not n.hidden
end
eq(table.concat(P.findPath(adj, owned, 44, passable), ','), '44', 'one step past a saved node costs 1')
eq(#P.findPath(adj, owned, 43, passable), 0, 'a saved node costs nothing')
local savedDeep = {}
for _, id in ipairs(deep) do savedDeep[id] = true end
local ownedDeep = P.ownedIds({[1] = true}, savedDeep)
eq(#P.findPath(adj, ownedDeep, 366, function(id) return map[id] ~= nil and not ownedDeep[id] end), 0,
  'the deep saved node is owned: priced 0')
eq(next(P.ownedIds(nil, nil)), nil, 'nothing owned')
eq(P.ownedIds(nil, {[5] = false})[5], nil, 'a false entry is not owned')

print(string.format('treelinks_test: %d checks, %d failures', count, fails))
if fails > 0 then os.exit(1) end
