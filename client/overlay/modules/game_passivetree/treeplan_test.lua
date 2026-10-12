-- luajit treeplan_test.lua && lua5.3 treeplan_test.lua (CI runs every client module test from the repo root)
-- The planner and search logic (treeplan.lua) on the real tree (treedata/nodes.lua): the graph, shortest paths from the
-- allocated set (class sections, ascended paths and other lines' nodes are not passable), the plan with undo / redo /
-- clear, removing a planned node with what hangs on it, mastery choices, the request, the cost text, search and paging.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'treeplan.lua')
dofile(dir .. 'treedata/nodes.lua')
local P = TreePlan
local nodes = getTreeNodes()
local fails, count = 0, 0
local function eq(a, b, what)
  count = count + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function join(list) return table.concat(list or {}, ',') end

local adj = P.graph(nodes)
eq(join(adj[628]), '627,629,632,665', 'neighbours of a line node, mastery included')
eq(adj[1] ~= nil and #adj[1] >= 6, true, 'the root has its ring')

-- what a class may walk on (the window: shown for its line, allowed for its class, never a start node)
local function passableFor(class, line)
  return function(id)
    local n = nodes[id]
    if not n or n.hidden or n.isStartNode then return false end
    if n.line and n.line ~= line then return false end
    if n.classes then
      for _, c in ipairs(n.classes) do if c == class then return true end end
      return false
    end
    return true
  end
end
local warrior = passableFor('warrior', 'warrior')
local thief = passableFor('thief', 'thief')
local ninja = passableFor('ninja', 'thief')

local owned = {[1] = true}
eq(join(P.findPath(adj, owned, 9, warrior)), '2,9', 'two steps from the start')
eq(join(P.findPath(adj, owned, 2, warrior)), '2', 'a node next to the start')
eq(join(P.findPath(adj, owned, 1, warrior)), '', 'an owned node: nothing to plan')
eq(P.findPath(adj, owned, 626, warrior), nil, "another line's section: no path")
local thiefOwned = {[1] = true, [625] = true}
eq(join(P.findPath(adj, thiefOwned, 665, thief)), '626,627,628,665', 'the mastery through the line nodes')
eq(P.findPath(adj, thiefOwned, 631, thief), nil, 'an ascended path is closed to the base class')
eq(join(P.findPath(adj, thiefOwned, 631, ninja)), '626,627,628,629,630,631', 'and open to the ninja')
local far = P.findPath(adj, owned, 621, warrior)
eq(far ~= nil and far[#far] == 621, true, 'a keystone far away')
local seen = {}
for i, id in ipairs(far) do
  eq(seen[id], nil, 'no node twice in a path')
  seen[id] = true
  local prev = far[i - 1] or 1
  local linked = false
  for _, nb in ipairs(adj[id]) do linked = linked or nb == prev end
  eq(linked, true, 'each step is a link (' .. prev .. '-' .. id .. ')')
end
-- the shortest: no shorter path exists (breadth first from the root over every passable node)
do
  local dist, queue, head = {[1] = 0}, {1}, 1
  while head <= #queue do
    local id = queue[head]; head = head + 1
    for _, nb in ipairs(adj[id] or {}) do
      if dist[nb] == nil and warrior(nb) then dist[nb] = dist[id] + 1; queue[#queue + 1] = nb end
    end
  end
  eq(#far, dist[621], 'the path is the shortest (' .. dist[621] .. ')')
end
-- from a bigger owned set the path starts at the nearest owned node
local some = {[1] = true, [2] = true, [9] = true, [11] = true}
eq(join(P.findPath(adj, some, 13, warrior)), '13', 'one step from an owned node')

-- plan state: add, undo, redo, clear
local s = P.new()
eq(P.addPath(s, P.findPath(adj, owned, 9, warrior)), 2, 'two planned')
eq(P.cost(s), 2, 'cost')
local both = {[1] = true, [2] = true, [9] = true}
eq(P.addPath(s, P.findPath(adj, both, 13, warrior)), 2, 'planned on from the plan (11, 13)')
eq(join(s.list), '2,9,11,13', 'plan order')
eq(P.addPath(s, {9}), 0, 'a planned id again adds nothing')
eq(P.undo(s), true, 'undo')
eq(join(s.list), '2,9', 'undone')
eq(P.redo(s), true, 'redo')
eq(join(s.list), '2,9,11,13', 'redone')
eq(P.redo(s), false, 'nothing more to redo')
-- remove: what hangs on the removed node goes too
local removed = P.remove(s, 9, adj, {[1] = true})
eq(join(removed), '9,11,13', 'removing 9 drops 11 and 13 (no other link to the start)')
eq(join(s.list), '2', 'left')
eq(P.undo(s), true, 'undo the removal')
eq(join(s.list), '2,9,11,13', 'back')
removed = P.remove(s, 13, adj, {[1] = true})
eq(join(removed), '13', 'a leaf goes alone')
eq(P.clear(s), true, 'clear')
eq(P.cost(s), 0, 'empty')
eq(P.clear(s), false, 'clearing an empty plan records nothing')
eq(P.undo(s), true, 'undo the clear')
eq(join(s.list), '2,9,11', 'the plan is back')
-- a new change after undo drops the redo history
P.undo(s)
P.addPath(s, {3})
eq(P.redo(s), false, 'a change clears redo')
-- history cap
local h = P.new()
for i = 1, P.HISTORY + 20 do P.addPath(h, {1000 + i}) end
eq(#h.undo, P.HISTORY, 'history is capped')

-- masteries
local m = P.new()
P.addPath(m, P.findPath(adj, thiefOwned, 665, thief))
local function isMastery(id) return nodes[id] and nodes[id].isMastery == true end
eq(join(P.missingMasteries(m, isMastery)), '665', 'the mastery needs an effect')
eq(P.setMastery(m, 665, 2), true, 'choose an effect')
eq(P.setMastery(m, 665, 2), false, 'the same effect again: no change')
eq(#P.missingMasteries(m, isMastery), 0, 'chosen')
eq(P.setMastery(m, 629, 1), false, 'not planned: no choice')
local req = P.request(m)
eq(join(req.nodes), '626,627,628,665', 'request nodes')
eq(req.masteries[1].id == 665 and req.masteries[1].choice == 2, true, 'request masteries')
P.undo(m)
eq(m.masteries[665], nil, 'undo takes the choice back')
P.redo(m)
eq(m.masteries[665], 2, 'redo puts it back')
P.remove(m, 628, adj, thiefOwned)
eq(m.masteries[665], nil, 'removing the path drops the choice')
-- prune after the server saved the plan
local q = P.new()
P.addPath(q, {2, 9, 11})
eq(P.prune(q, {[2] = true, [9] = true}), true, 'prune')
eq(join(q.list), '11', 'allocated ids leave the plan')
P.reset(q)
eq(P.cost(q) + #q.undo + #q.redo, 0, 'reset')

-- cost text
local text, fits = P.costText(5, 12)
eq(text, 'Plan: 5 / 12 points', 'cost text')
eq(fits, true, 'fits')
text, fits = P.costText(5, 3)
eq(fits, false, 'over')
eq(text:find('2 short', 1, true) ~= nil, true, 'how many short')
eq(select(2, P.costText(0, 0)), true, 'empty plan fits')

-- search
local entries = {}
for id = 1, #nodes do
  local n = nodes[id]
  if n and not n.hidden then
    local parts = {n.name or ''}
    for stat, v in pairs(n.customStats or {}) do parts[#parts + 1] = stat .. ' ' .. tostring(v) end
    for _, eff in ipairs(n.masteries or {}) do parts[#parts + 1] = eff.name end
    entries[#entries + 1] = {id = id, text = P.normalize(table.concat(parts, ' '))}
  end
end
local hits = P.search(entries, 'Living Shadow')
eq(join(hits), '631', 'a keystone by name')
hits = P.search(entries, '  KEEN   edge ')
eq(join(hits), '665', 'a mastery effect, any case and spacing')
hits = P.search(entries, 'shadow living')
eq(join(hits), '631', 'words in any order')
eq(#P.search(entries, ''), 0, 'empty query: nothing')
eq(#P.search(entries, 'zzzz'), 0, 'no match')
eq(#P.search(entries, 'strength') > 5, true, 'a stat matches many')
eq(P.step(0, 5, 1), 1, 'first')
eq(P.step(5, 5, 1), 1, 'wraps forward')
eq(P.step(1, 5, -1), 5, 'wraps back')
eq(P.step(0, 5, -1), 5, 'previous from nothing: the last')
eq(P.step(3, 0, 1), 0, 'no matches')
eq(P.countText(2, 7, 'x'), '2 / 7', 'count text')
eq(P.countText(0, 0, 'x'), 'No match', 'no match text')
eq(P.countText(0, 0, ' '), '', 'no query')

print(string.format('treeplan_test: %d checks, %d failures', count, fails))
if fails > 0 then os.exit(1) end
