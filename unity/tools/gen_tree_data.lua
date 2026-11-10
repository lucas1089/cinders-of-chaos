-- Passive tree layout for the Unity client: unity/Client/Assets/Chaos/Resources/PassiveTree.json.
-- The server sends only the allocated ids (opcode 65), so the shape of the tree (positions, links, names, stat lines) comes
-- from the main client's data: client/overlay/modules/game_passivetree/treedata (nodes, groups, class lanes) and the
-- stat lines of passivetree.lua getCustomStatString, run here with an English tr().
-- Run from the repo root:  luajit unity/tools/gen_tree_data.lua [--check]   (also lua5.3). --check exits 1 when stale.
--
-- Phase 8 track A adds the icon key (k, and ik: the class variants' own icon keys), the group (g) and orbit (b) of a node for its curved links, the group
-- centres ("groups": {id: [x, y]}), and a second file PassiveTreeIcons.json with the clip of every icon key the nodes use and the painted option's cells.
--
-- Format (compact JSON, sorted keys): {"version":1,"nodes":[node...],"groups":{...}}; node:
--   i id, x y position (the client's own: group centre + orbit), t type (s start, c common, u uncommon, r rare, v very rare,
--   m mythic, d divine / keystone, M mastery), n name, s stat lines [text], d description paragraph, l class line (only that
--   line sees it), c classes that may take it, h 1 hidden, o linked ids (undirected), a mastery effects [{n, s}],
--   v variants {key: {n, s, d}} for the class a player is (the "vocation" key of sendNodes): only what differs from the node.
local root = arg and arg[0] and arg[0]:match("^(.*)/unity/tools/") or "."
local mod = root .. "/client/overlay/modules/game_passivetree/"
local out = root .. "/unity/Client/Assets/Chaos/Resources/PassiveTree.json"
local outIcons = root .. "/unity/Client/Assets/Chaos/Resources/PassiveTreeIcons.json"

local function load(file, env)
  local f = assert(loadfile(mod .. file))
  return f()
end

-- the tree data files read each other through dofile with module-relative names
local realDofile = dofile
function dofile(name)
  if name:match("^treedata/") then return realDofile(mod .. name) end
  return realDofile(name)
end
realDofile(mod .. "treeplan.lua")
realDofile(mod .. "treelanes.lua")
realDofile(mod .. "treedata.lua")
realDofile(mod .. "treespellmods.lua") -- the words of the spell modifier masteries (O451), read by getCustomStatString

-- getCustomStatString lives in passivetree.lua, which only defines locals and functions at its top level
function tr(s, ...) if select("#", ...) > 0 then return string.format(s, ...) end return s end
local oldG = _G
setmetatable(_G, {__index = function() return function() end end})
realDofile(mod .. "passivetree.lua")
setmetatable(_G, nil)
realDofile(mod .. "treetext.lua")

local data = getTreeData()
local nodes, groups = data.nodes, data.groups

local function statLines(customStats)
  return getCustomStatString(customStats or {})
end

local function paragraph(lines)
  if type(lines) ~= "table" or #lines == 0 then return nil end
  return table.concat(lines, " ")
end

-- name, stat lines and description of a node for a variant key (nil key: the node itself)
local function view(node, key)
  local vn = key and node[key] or nil
  local cs = (vn and vn.customStats) or node.customStats
  local name = (vn and vn.name) or node.name or ""
  local s = {}
  local d
  if node.isMastery then
    d = paragraph(node.stats)
  elseif cs then
    s = statLines(cs)
    d = paragraph((vn and vn.stats) or ((node.classes or node.isKeystone) and node.stats) or nil)
  elseif node.stats then
    d = paragraph(node.stats)
  end
  return {n = name, s = s, d = d}
end

local function same(a, b)
  if a.n ~= b.n or a.d ~= b.d or #a.s ~= #b.s then return false end
  for i, v in ipairs(a.s) do if b.s[i] ~= v then return false end end
  return true
end

local PLAIN = {inputs = true, out = true, classes = true, masteries = true, stats = true, customStats = true}
local keys = {}
for _, node in pairs(nodes) do
  for k, v in pairs(node) do
    if type(v) == "table" and not PLAIN[k] and (v.customStats or v.stats or v.name) then keys[k] = true end
  end
end

local adj = TreePlan.graph(nodes)
local round = function(v) return math.floor(v * 10 + 0.5) / 10 end
local orbitDist = {[0] = 0, 60, 80, 120, 191, 250, 290}

local list = {}
local usedIcons = {}
local ids = {}
for id in pairs(nodes) do ids[#ids + 1] = id end
table.sort(ids)
for _, id in ipairs(ids) do
  local node = nodes[id]
  local group = groups[node.group]
  local x, y = group.x, group.y
  if not node.isStartNode then
    local angle = (node.orbitIndex * math.pi) / 180
    local dist = (node.orbitDist and node.orbitDist > 0) and node.orbitDist or orbitDist[node.orbit]
    x = group.x + math.sin(angle) * dist
    y = group.y - math.cos(angle) * dist
  end
  local t = "c"
  if node.isStartNode then t = "s"
  elseif node.isMastery then t = "M"
  elseif node.isKeystone then t = "d"
  elseif node.isUncommon then t = "u"
  elseif node.isRare then t = "r"
  elseif node.isVeryRare then t = "v"
  elseif node.isMythic then t = "m"
  elseif node.isDivine then t = "d" end
  local base = view(node, nil)
  local entry = {i = id, x = round(x), y = round(y), t = t, n = base.n, o = adj[id] or {}}
  if #base.s > 0 then entry.s = base.s end
  if base.d then entry.d = base.d end
  if node.line then entry.l = node.line end
  if node.classes then entry.c = node.classes end
  if node.hidden then entry.h = 1 end
  if node.group then entry.g = node.group end
  if node.orbit and node.orbit > 0 then entry.b = node.orbit end
  if node.icon then entry.k = node.icon; usedIcons[node.icon] = true end
  do
    local ik
    for key in pairs(keys) do
      local vn = node[key]
      if type(vn) == "table" and vn.icon and vn.icon ~= node.icon and data.icons[vn.icon] then
        ik = ik or {}
        ik[key] = vn.icon
        usedIcons[vn.icon] = true
      end
    end
    if ik then entry.ik = ik end
  end
  if node.isMastery then
    entry.a = {}
    for i, effect in ipairs(node.masteries or {}) do
      entry.a[i] = {n = effect.name or "", s = statLines(effect.customStats)}
    end
  end
  local variants
  for key in pairs(keys) do
    if node[key] then
      local v = view(node, key)
      if not same(v, base) then
        variants = variants or {}
        local rec = {}
        if v.n ~= base.n then rec.n = v.n end
        rec.s = v.s
        if v.d then rec.d = v.d end
        variants[key] = rec
      end
    end
  end
  if variants then entry.v = variants end
  list[#list + 1] = entry
end

-- sorted-key JSON, no spaces
local function esc(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    local map = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\t'] = '\\t', ['\r'] = '\\r'}
    return map[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end
local function enc(v)
  local tv = type(v)
  if tv == "string" then return esc(v) end
  if tv == "number" then
    if v == math.floor(v) then return string.format("%d", v) end
    return string.format("%.1f", v)
  end
  if tv == "boolean" then return tostring(v) end
  if tv == "table" then
    if #v > 0 or next(v) == nil then
      local parts = {}
      for i = 1, #v do parts[i] = enc(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local ks = {}
    for k in pairs(v) do ks[#ks + 1] = k end
    table.sort(ks)
    local parts = {}
    for _, k in ipairs(ks) do parts[#parts + 1] = esc(k) .. ":" .. enc(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("cannot encode " .. tv)
end

local lines = {'{"version":1,"nodes":['}
for i, e in ipairs(list) do lines[#lines + 1] = enc(e) .. (i < #list and "," or "") end
local groupList = {}
for gid, g in pairs(groups) do groupList[tostring(gid)] = {round(g.x), round(g.y)} end
lines[#lines + 1] = '],"groups":' .. enc(groupList) .. '}'
local text = table.concat(lines, "\n") .. "\n"

-- the icon clips: key -> {f file (nil: skills), x, y, w, h}; painted: key -> {x, y} of the 64 px cell in painted_nodes.png (only the keys nodes use)
local iconTable, paintedTable = {}, {}
for key in pairs(usedIcons) do
  local ic = data.icons[key]
  if ic then
    local rec = {x = ic.x or 0, y = ic.y or 0, w = ic.w or 0, h = ic.h or 0}
    if ic.file then rec.f = (ic.file:gsub("^/images/passivetree/", "")) end
    iconTable[key] = rec
  end
  local pt = data.painted and data.painted[key]
  if pt then paintedTable[key] = {pt.x, pt.y} end
end
local iconText = '{"version":1,"icons":' .. enc(iconTable) .. ',"painted":' .. enc(paintedTable) .. '}\n'

local check = false
for _, a in ipairs(arg or {}) do if a == "--check" then check = true end end
if check then
  local f = io.open(out, "rb")
  local have = f and f:read("*a")
  if f then f:close() end
  if have ~= text then
    io.stderr:write("PassiveTree.json is stale: run luajit unity/tools/gen_tree_data.lua\n")
    os.exit(1)
  end
  local fi = io.open(outIcons, "rb")
  local haveIcons = fi and fi:read("*a")
  if fi then fi:close() end
  if haveIcons ~= iconText then
    io.stderr:write("PassiveTreeIcons.json is stale: run luajit unity/tools/gen_tree_data.lua\n")
    os.exit(1)
  end
  print("PassiveTree.json: ok (" .. #list .. " nodes)")
else
  local f = assert(io.open(out, "wb"))
  f:write(text)
  f:close()
  local fi = assert(io.open(outIcons, "wb"))
  fi:write(iconText)
  fi:close()
  print("wrote " .. out .. " (" .. #list .. " nodes, " .. #text .. " bytes)")
end
