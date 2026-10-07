-- Regenerates server/data/scripts/chaos/passivetree_data.lua from the client's tree.
-- Run from the client treedata folder (it dofile()s nodes.lua relative to the cwd):
--   cd client/overlay/modules/game_passivetree/treedata
--   lua5.3 ../../../../../server/tools/gen_passivetree_data.lua ../../../../../server/data/scripts/chaos/passivetree_data.lua
-- Edges are taken from both `out` and `inputs` and stored undirected; per-node customStats are kept.
-- (One client node has the typo `customStast` and therefore carries no stats; fix it client-side.)
dofile("nodes.lua")
local nodes = getTreeNodes()
local ids = {}
for id in pairs(nodes) do ids[#ids+1] = id end
table.sort(ids)
local adj = {}
for _, id in ipairs(ids) do adj[id] = adj[id] or {} end
local function link(a, b)
  if nodes[a] and nodes[b] and a ~= b then adj[a][b] = true; adj[b][a] = true end
end
for _, id in ipairs(ids) do
  local n = nodes[id]
  for _, o in pairs(n.out or {}) do link(id, o) end
  for _, o in pairs(n.inputs or {}) do link(id, o) end
end
local out = {}
local w = function(s) out[#out+1] = s end
w("-- passivetree_data.lua  (GENERATED from client/overlay/modules/game_passivetree/treedata/nodes.lua)")
w("-- Do not edit by hand: regenerate with server/tools/gen_passivetree_data.lua if the client tree changes.")
w("-- Format: ChaosPassiveTreeData.nodes[id] = { n = {neighbour ids (undirected)}, s = {customStats} }")
w("if ChaosPassiveTreeData then return ChaosPassiveTreeData end")
w("ChaosPassiveTreeData = { root = 1, nodes = {")
local stats_total = 0
for _, id in ipairs(ids) do
  local n = nodes[id]
  local nb = {}
  for k in pairs(adj[id]) do nb[#nb+1] = k end
  table.sort(nb)
  local s = {}
  local cs = n.customStats
  if cs then
    local keys = {}
    for k in pairs(cs) do keys[#keys+1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do s[#s+1] = k .. "=" .. tostring(cs[k]); stats_total = stats_total + 1 end
  end
  w(string.format("[%d]={n={%s}%s},", id, table.concat(nb, ","), #s > 0 and (",s={" .. table.concat(s, ",") .. "}") or ""))
end
w("} }")
w("return ChaosPassiveTreeData")
io.open(arg[1], "w"):write(table.concat(out, "\n") .. "\n")
print(#ids, stats_total)
