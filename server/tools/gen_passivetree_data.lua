-- Regenerates server/data/scripts/chaos/passivetree_data.lua from the client's tree.
-- Run from the client treedata folder (it dofile()s nodes.lua relative to the cwd):
--   cd client/overlay/modules/game_passivetree/treedata
--   lua5.3 ../../../../../server/tools/gen_passivetree_data.lua ../../../../../server/data/scripts/chaos/passivetree_data.lua
-- Edges are taken from both `out` and `inputs` and stored undirected; per-node customStats are kept.
-- Per-class variants (node.knight / .juggernaut / ... , the keys of VARIANTS below, used by the keystones) with their own
-- customStats are stored in `v`; passivetree.lua uses them instead of `s` for that variant key (ChaosClasses.keystoneKey).
-- node.classes (the classes that may take the node) is stored as `c` = {[class key] = true} (class_tree.lua checks it).
-- Start nodes (isStartNode) other than the root are the start of a class section: they are not stored; their edges
-- go to the root instead, so the section connects to the root like any other branch.
-- (One client node has the typo `customStast` and therefore carries no stats; fix it client-side.)
dofile("nodes.lua")
local nodes = getTreeNodes()
local ids = {}
for id in pairs(nodes) do ids[#ids+1] = id end
table.sort(ids)
local adj = {}
for _, id in ipairs(ids) do adj[id] = adj[id] or {} end
local ROOT = 1
-- a class section's start node stands for the root
local function alias(id)
  if nodes[id] and nodes[id].isStartNode then return ROOT end
  return id
end
local function link(a, b)
  a, b = alias(a), alias(b)
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
w("-- Format: ChaosPassiveTreeData.nodes[id] = { n = {neighbour ids (undirected)}, s = {customStats},")
w("--         v = {[variant key] = {customStats of that variant}} (keystones; replaces s for that key),")
w("--         c = {[class key] = true} (only these classes may take the node; none = every class) }")
w("if ChaosPassiveTreeData then return ChaosPassiveTreeData end")
w("ChaosPassiveTreeData = { root = 1, nodes = {")
local stats_total = 0
local VARIANTS = {"beastmaster", "berserker", "deadeye", "druid", "illusionist", "juggernaut", "knight", "monk", "paladin",
  "sorcerer"}
local function statList(cs)
  local keys, s = {}, {}
  for k in pairs(cs) do keys[#keys+1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do s[#s+1] = k .. "=" .. tostring(cs[k]) end
  return s
end
local written = 0
for _, id in ipairs(ids) do
  local n = nodes[id]
  if n.isStartNode and id ~= ROOT then goto continue end
  written = written + 1
  local nb = {}
  for k in pairs(adj[id]) do nb[#nb+1] = k end
  table.sort(nb)
  local s = n.customStats and statList(n.customStats) or {}
  stats_total = stats_total + #s
  local v = {}
  for _, voc in ipairs(VARIANTS) do
    local variant = n[voc]
    if type(variant) == "table" and variant.customStats then
      local vs = statList(variant.customStats)
      stats_total = stats_total + #vs
      v[#v+1] = voc .. "={" .. table.concat(vs, ",") .. "}"
    end
  end
  local c = {}
  if n.classes then
    local keys = {}
    for _, k in ipairs(n.classes) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do c[#c + 1] = k .. "=true" end
  end
  w(string.format("[%d]={n={%s}%s%s%s},", id, table.concat(nb, ","), #s > 0 and (",s={" .. table.concat(s, ",") .. "}") or "",
    #v > 0 and (",v={" .. table.concat(v, ",") .. "}") or "", #c > 0 and (",c={" .. table.concat(c, ",") .. "}") or ""))
  ::continue::
end
w("} }")
w("return ChaosPassiveTreeData")
io.open(arg[1], "w"):write(table.concat(out, "\n") .. "\n")
print(written, stats_total)
