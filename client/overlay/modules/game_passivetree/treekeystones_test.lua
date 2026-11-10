-- luajit treekeystones_test.lua && lua5.3 treekeystones_test.lua (CI runs every client module test from the repo root)
-- The keystone cap's counting (treekeystones.lua, O447) on the real tree (treedata/nodes.lua): the 47 keystones, the
-- count of saved and planned nodes, the keystones of a path, and the pin of the client's default cap to the server's
-- passivetree_config.lua keystoneMax.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'treekeystones.lua')
dofile(dir .. 'treedata/nodes.lua')
local K = TreeKeystones
local nodes = getTreeNodes()
local fails, count = 0, 0
local function eq(a, b, what)
  count = count + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the cap: the server's number, pinned
local f = io.open(dir .. '../../../../server/data/scripts/chaos/passivetree_config.lua', 'r')
if f then
  f:close()
  local cfg = dofile(dir .. '../../../../server/data/scripts/chaos/passivetree_config.lua')
  eq(K.DEFAULT_MAX, cfg.keystoneMax, 'the default cap is the server config keystoneMax')
else
  print('note: server/data not found, the cap was not compared with passivetree_config.lua')
end
eq(K.DEFAULT_MAX, 3, 'the owner decision of 2026-11-09')
eq(K.max(3), 3, 'the server number'); eq(K.max(2), 2, 'a lower cap'); eq(K.max(0), 0, 'zero is a number')
eq(K.max(nil), 3, 'no number: the default'); eq(K.max('x'), 3, 'text: the default'); eq(K.max(-1), 3, 'negative: the default')
eq(K.max(2.5), 3, 'fraction: the default')

-- the tree: 47 keystones (44 before the round 4 keystones of O450, 38 before the class sections of O449), none of them a mastery
local keystones, masteries = {}, 0
for id, node in ipairs(nodes) do
  if node.isKeystone then keystones[#keystones + 1] = id end
  if node.isMastery and node.isKeystone then masteries = masteries + 1 end
end
eq(#keystones, 47, 'the tree has 47 keystones (44 before the round 4 keystones, O450)')
eq(masteries, 0, 'no mastery is a keystone')

-- held: saved set + planned list, an id in both counts once, other nodes and unknown ids are ignored
local a, b, c, d = keystones[1], keystones[2], keystones[3], keystones[4]
eq(K.held(nodes, {[a] = true, [b] = true, [2] = true, [3] = true}, {}), 2, 'two saved keystones')
eq(K.held(nodes, {[a] = true}, {b, c}), 3, 'saved and planned')
eq(K.held(nodes, {[a] = true}, {a, b}), 2, 'in both: once')
eq(K.held(nodes, {[a] = false}, {2, 9999}), 0, 'a false entry, a plain node, an unknown id')
eq(K.held(nodes, nil, nil), 0, 'nothing')
eq(K.held(nodes, {[665] = true, [666] = true, [703] = true, [704] = true, [705] = true}), 0, 'masteries are no keystones')

-- a path: only the keystones not owned yet
eq(K.newOnPath(nodes, {}, {2, a, b}), 2, 'two new keystones on the path')
eq(K.newOnPath(nodes, {[a] = true}, {2, a, b}), 1, 'one is owned')
eq(K.newOnPath(nodes, nil, nil), 0, 'no path')

-- over: held + new against the cap
eq(K.over(2, 1, 3), false, 'the third is fine')
eq(K.over(3, 0, 3), false, 'holding 3 and taking none')
eq(K.over(3, 1, 3), true, 'the fourth is over')
eq(K.over(2, 2, 3), true, 'two on a path from 2 held')
eq(K.over(3, 1, nil), true, 'no server number: the default cap')
eq(K.over(1, 1, 1), true, 'a lower cap from the server')

print(string.format('treekeystones_test: %d checks, %d failed', count, fails))
if fails > 0 then os.exit(1) end
