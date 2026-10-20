-- Regenerates server/data/scripts/chaos/passivetree_data.lua from the client's tree.
-- Run from the client treedata folder (it dofile()s nodes.lua relative to the cwd):
--   cd client/overlay/modules/game_passivetree/treedata
--   lua5.3 ../../../../../server/tools/gen_passivetree_data.lua ../../../../../server/data/scripts/chaos/passivetree_data.lua
-- Edges are taken from both `out` and `inputs` and stored undirected; per-node customStats are kept.
-- Per-class variants (node.knight / .juggernaut / ... , the keys of VARIANTS below, used by the keystones) with their own
-- customStats are stored in `v`; passivetree.lua uses them instead of `s` for that variant key (ChaosClasses.keystoneKey).
-- The class lanes (treedata/classlanes.lua, tools/gen_class_lanes.lua) are stored in the same `v` for the plain nodes: the stats
-- a node gives one class instead of its own. Run gen_class_lanes.lua BEFORE this when the tree or the stat lists changed.
-- node.classes (the classes that may take the node) is stored as `c` = {[class key] = true} (class_tree.lua checks it).
-- A mastery node (node.masteries = {{name, customStats}, ...}: 2-4 effects, the player picks one) is stored as
-- `m` = {{customStats of effect 1}, {effect 2}, ...} in that order (passivetree_core.lua; never reorder, only append).
-- Start nodes (isStartNode) other than the root are the start of a class section: they are not stored; their edges
-- go to the root instead, so the section connects to the root like any other branch. Hidden nodes (node.hidden: a stray
-- node of the original tree, never reachable) are not stored either.
-- (One client node has the typo `customStast` and therefore carries no stats; fix it client-side.)
dofile("nodes.lua")
dofile("classlanes.lua")
local nodes = getTreeNodes()
local LANES = getClassLanes() -- {[variant key] = {[node id] = stats}}: the per-class re-skin of plain nodes (tools/gen_class_lanes.lua)
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
  if (nodes[a] and nodes[a].hidden) or (nodes[b] and nodes[b].hidden) then return end
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
w("--         c = {[class key] = true} (only these classes may take the node; none = every class),")
w("--         m = {{customStats of effect 1}, ...} (mastery nodes: the player picks one effect) }")
w("if ChaosPassiveTreeData then return ChaosPassiveTreeData end")
w("ChaosPassiveTreeData = { root = 1, nodes = {")
local stats_total = 0
local VARIANTS = {"beastmaster", "berserker", "deadeye", "illusionist", "ironsage", "juggernaut", "knight", "monk", "paladin",
  "sentinel", "sorcerer"}
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
  if (n.isStartNode and id ~= ROOT) or n.hidden then goto continue end
  written = written + 1
  local nb = {}
  for k in pairs(adj[id]) do nb[#nb+1] = k end
  table.sort(nb)
  local s = n.customStats and statList(n.customStats) or {}
  stats_total = stats_total + #s
  local v = {}
  local vmap = {}
  for _, voc in ipairs(VARIANTS) do
    local variant = n[voc]
    if type(variant) == "table" and variant.customStats then
      vmap[voc] = statList(variant.customStats)
    end
  end
  -- a class lane re-skins a plain node (one with no variant of its own) for one variant key
  if next(vmap) == nil and n.customStats and not n.masteries then
    for key, lane in pairs(LANES) do
      if lane[id] then vmap[key] = statList(lane[id]) end
    end
  end
  local vkeys = {}
  for key in pairs(vmap) do vkeys[#vkeys + 1] = key end
  table.sort(vkeys)
  for _, key in ipairs(vkeys) do
    stats_total = stats_total + #vmap[key]
    v[#v+1] = key .. "={" .. table.concat(vmap[key], ",") .. "}"
  end
  local c = {}
  if n.classes then
    local keys = {}
    for _, k in ipairs(n.classes) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do c[#c + 1] = k .. "=true" end
  end
  local m = {}
  if n.masteries then
    assert(#n.masteries >= 2 and #n.masteries <= 4, "mastery node " .. id .. ": 2 to 4 effects")
    for i, effect in ipairs(n.masteries) do
      assert(type(effect.customStats) == "table" and next(effect.customStats), "mastery node " .. id .. " effect " .. i .. ": stats")
      local ms = statList(effect.customStats)
      stats_total = stats_total + #ms
      m[#m + 1] = "{" .. table.concat(ms, ",") .. "}"
    end
  end
  w(string.format("[%d]={n={%s}%s%s%s%s},", id, table.concat(nb, ","), #s > 0 and (",s={" .. table.concat(s, ",") .. "}") or "",
    #v > 0 and (",v={" .. table.concat(v, ",") .. "}") or "", #c > 0 and (",c={" .. table.concat(c, ",") .. "}") or "",
    #m > 0 and (",m={" .. table.concat(m, ",") .. "}") or ""))
  ::continue::
end
w("} }")
w("return ChaosPassiveTreeData")
io.open(arg[1], "w"):write(table.concat(out, "\n") .. "\n")
print(written, stats_total)
