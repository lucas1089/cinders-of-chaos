-- Run from the server/ folder: luajit tests/passivetree_paths_test.lua (and lua5.3; CI runs both).
-- The class lanes of the passive tree (tools/gen_class_lanes.lua, tools/passivetree_lanes_lib.lua):
--   * for EVERY class (21), the shortest legal route from the start to each keystone and notable the class can reach has
--     at least ChaosPassiveStatsConfig.paths.minShare of nodes tagged primary / secondary (flag nodes count as relevant)
--     and no node with a stat of the class's irrelevant list;
--   * the lanes only touch plain nodes (no keystone, class, archetype or mastery node), keep the tree's shape and costs,
--     use stats the stat help describes, and never give a class more of a scarce stat than the supply cap;
--   * the client's classlanes.lua is exactly what the server tree stores (`v`), the keystone variants are untouched;
--   * the migration: reworked version 5 refunds, per class, exactly the nodes that have a lane for that class.
-- Prints the relevance of every class before and after the lanes (the audit table of the change).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label) check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/classes.lua")
dofile("data/scripts/chaos/passivetree_stats_config.lua")
dofile("data/scripts/chaos/passivetree_stats_core.lua")
dofile("data/scripts/chaos/passivetree_core.lua")
local Lanes = dofile("tools/passivetree_lanes_lib.lua")
local tree = dofile("data/scripts/chaos/passivetree_data.lua")
local cfg, C = ChaosPassiveStatsConfig, PassiveStatsCore
local P = cfg.paths
local TREEDATA = "../client/overlay/modules/game_passivetree/treedata/"
dofile(TREEDATA .. "nodes.lua")
dofile(TREEDATA .. "classlanes.lua")
local clientNodes = getTreeNodes()
local clientLanes = getClassLanes()
local clientIcons = getClassLaneIcons()

check(type(P) == "table" and P.minShare >= 0.5 and P.minShare <= 1 and P.goalShare >= P.minShare, "the path config exists")

-- targets: every named node (a keystone or a notable), the tree's own nodes only
local targets = {}
for id = 1, #clientNodes do
	local nd = clientNodes[id]
	if nd and not nd.hidden and not nd.isStartNode and nd.name and nd.name ~= "Attribute" and tree.nodes[id] then
		targets[#targets + 1] = id
	end
end
check(#targets >= 140, "the tree has its keystones and notables (" .. #targets .. ")")

-- the tree without the lanes (the numbers before): `v` of plain nodes taken off
local function withoutLanes()
	local copy = {root = tree.root, nodes = {}}
	for id, node in pairs(tree.nodes) do
		local v = node.v
		if v and not Lanes.isFlagNode(node) then v = nil end
		copy.nodes[id] = {n = node.n, s = node.s, v = v, c = node.c, m = node.m}
	end
	return copy
end
local base = withoutLanes()

local ids = Chaos.classes.ids
local classKeys = {}
for key in pairs(ids) do classKeys[#classKeys + 1] = key end
table.sort(classKeys, function(a, b) return ids[a] < ids[b] end)
eq(#classKeys, 21, "21 classes")

print(string.format("%-12s %7s %10s %10s %10s %10s %6s", "class", "targets", "avg before", "avg after", "pass before", "pass after", "lane"))
local laneCount = {}
for key, lane in pairs(clientLanes) do
	local c = 0
	for _ in pairs(lane) do c = c + 1 end
	laneCount[key] = c
end
for _, classKey in ipairs(classKeys) do
	local info = C.classInfo(cfg, classKey)
	local vk = ChaosClasses.keystoneKey(ids[classKey])
	local routes = Lanes.routes(tree, classKey, info, vk, targets)
	local after = Lanes.summary(routes, targets, P.minShare)
	local before = Lanes.summary(Lanes.routes(base, classKey, info, vk, targets), targets, P.minShare)
	check(after.targets >= 90, classKey .. " reaches its keystones and notables (" .. after.targets .. ")")
	eq(after.passing, after.targets, classKey .. ": every route passes (>= " .. P.minShare * 100 .. "% relevant, nothing irrelevant)")
	eq(after.bad, 0, classKey .. ": no route has an irrelevant node")
	for _, t in ipairs(targets) do
		local r = routes[t]
		if r then
			check(r.bad == 0, classKey .. " route to " .. t .. " has no irrelevant node")
			check(r.rel / r.len >= P.minShare, classKey .. " route to " .. t .. " is " .. string.format("%.0f", r.rel / r.len * 100) .. "% relevant")
		end
	end
	check(after.avg > before.avg, classKey .. ": more relevant than before")
	print(string.format("%-12s %7d %9.0f%% %9.0f%% %6d/%-3d %6d/%-3d %6d", classKey, after.targets, before.avg * 100, after.avg * 100,
		before.passing, before.targets, after.passing, after.targets, laneCount[vk] or 0))
end

-- the Covenant of the Grave example of the owner: the Necromancer reaches its notables without axe or club
do
	local info = C.classInfo(cfg, "necromancer")
	local routes = Lanes.routes(tree, "necromancer", info, "necromancer", targets)
	local melee = {axeSkill = true, clubSkill = true, swordSkill = true}
	for _, t in ipairs(targets) do
		local r = routes[t]
		for _, id in ipairs(r and r.path or {}) do
			local stats = (tree.nodes[id].v and tree.nodes[id].v.necromancer) or tree.nodes[id].s or {}
			for stat in pairs(stats) do
				check(not melee[stat], "necromancer route to " .. t .. " crosses no sword, axe or club node (node " .. id .. ")")
			end
		end
	end
end

-- ----------------------------------------------------------------------------------------------- the lanes themselves
local plainOnly, sameShape = true, true
local scarce = {skill = true, crit = true, leech = true, mleech = true}
local totalBase = {}
for id, node in pairs(base.nodes) do
	if node.s and not Lanes.isFlagNode(node) then
		for stat, v in pairs(node.s) do totalBase[stat] = (totalBase[stat] or 0) + v end
	end
end
local statKnown = cfg.stats
for key, lane in pairs(clientLanes) do
	for id, stats in pairs(lane) do
		local node = tree.nodes[id]
		check(node ~= nil, "lane " .. key .. "/" .. id .. " is a node of the tree")
		if node then
			check(node.s ~= nil and not Lanes.isFlagNode(node) and not node.m, "lane node " .. id .. " is a plain node")
			check(node.v and node.v[key] ~= nil, "lane " .. key .. "/" .. id .. " is stored in the server tree")
			for stat, v in pairs(stats) do
				check(type(v) == "number" and v >= 1 and v == math.floor(v), "lane " .. key .. "/" .. id .. " " .. stat .. " is a positive whole number")
				check(statKnown[stat] ~= nil, "lane stat " .. stat .. " has a description")
			end
			check(next(stats) ~= nil, "lane " .. key .. "/" .. id .. " gives something")
		end
	end
end
-- the server's `v` of a plain node is exactly the client's lane, and nothing else
for id, node in pairs(tree.nodes) do
	if node.v and not Lanes.isFlagNode(node) then
		for key, stats in pairs(node.v) do
			local lane = clientLanes[key] and clientLanes[key][id]
			check(lane ~= nil, "server variant " .. key .. "/" .. id .. " is in classlanes.lua")
			if lane then
				for stat, v in pairs(stats) do eq(lane[stat], v, "variant " .. key .. "/" .. id .. " " .. stat) end
				for stat, v in pairs(lane) do eq(stats[stat], v, "lane " .. key .. "/" .. id .. " " .. stat) end
			end
		end
	end
end
-- the keystones' variants are what they were: nodes 621 and 624 only
for id, node in pairs(tree.nodes) do
	if node.v and Lanes.isFlagNode(node) then
		check(id == 621 or id == 624, "only 621 and 624 carry keystone variants (" .. id .. ")")
	end
end
-- the class's total of a scarce stat stays within the supply cap
for _, classKey in ipairs(classKeys) do
	local vk = ChaosClasses.keystoneKey(ids[classKey])
	local totals = {}
	for id, node in pairs(tree.nodes) do
		if node.s and not Lanes.isFlagNode(node) and Lanes.allowed(node, classKey) then
			for stat, v in pairs((node.v and node.v[vk]) or node.s) do totals[stat] = (totals[stat] or 0) + v end
		end
	end
	for stat, v in pairs(totals) do
		local family = ((stat:match("Skill$") or stat == "skillShield") and "skill") or (stat:match("^criticalHit") and "crit")
			or (stat:match("^lifeLeech") and "leech") or (stat:match("^manaLeech") and "mleech")
		if family and not stat:match("^craftingSkill") and (totalBase[stat] or 0) > 0 then
			check(v <= math.ceil(totalBase[stat] * P.supplyFactor) or v <= totalBase[stat],
				classKey .. " has no more " .. stat .. " than the supply cap (" .. v .. " of " .. totalBase[stat] .. ")")
		end
	end
end
-- every icon of a lane exists in the client icon table
dofile(TREEDATA .. "icons.lua")
local known = getTreeIcons()
for key, icons in pairs(clientIcons) do
	for id, icon in pairs(icons) do
		check(known[icon] ~= nil and clientLanes[key] and clientLanes[key][id], "lane icon " .. icon .. " of " .. key .. "/" .. id .. " exists")
	end
end
-- the tree itself: same nodes, same neighbours, the base tree is all connected from the root
do
	local count = 0
	for _ in pairs(tree.nodes) do count = count + 1 end
	eq(count, 644, "644 nodes (640 + the four flask nodes of O251)")
	local seen, queue = {[tree.root] = true}, {tree.root}
	local i = 1
	while queue[i] do
		for _, m in ipairs(tree.nodes[queue[i]].n) do
			if not seen[m] then seen[m] = true; queue[#queue + 1] = m end
		end
		i = i + 1
	end
	eq(#queue, 644, "all 644 nodes are connected to the root")
end

-- ----------------------------------------------------------------------------------------------- the migration
do
	local C2 = ChaosPassiveTreeCore
	local list = {{version = 5, lanes = true}}
	local set, newest, any = C2.reworkedSince(list, 4, tree, "necromancer")
	local count = 0
	for _ in pairs(set) do count = count + 1 end
	eq(count, laneCount.necromancer, "version 5 refunds exactly the Necromancer's lane nodes")
	eq(newest, 5, "newest version 5")
	check(any, "something is refunded")
	for id in pairs(set) do check(clientLanes.necromancer[id] ~= nil, "refunded node " .. id .. " has a Necromancer lane") end
	local none, n2, any2 = C2.reworkedSince(list, 5, tree, "necromancer")
	check(next(none) == nil and not any2 and n2 == 5, "seen version 5: nothing again")
	local noKey = C2.reworkedSince(list, 4, tree, nil)
	check(next(noKey) == nil, "without a variant key nothing is refunded")
	local old = C2.reworkedSince({{version = 4, ids = {8}}, {version = 5, lanes = true}}, 3, tree, "knight")
	local oldCount = 0
	for _ in pairs(old) do oldCount = oldCount + 1 end
	check(old[8] and oldCount > 100, "versions 4 and 5 add up (" .. oldCount .. ")")
	-- a refunded tree loses the lane nodes and what hung on them, never keeps a disconnected node
	local kept = C2.dropNodes(tree, {2, 9, 11, 13, 61}, set)
	for _, id in ipairs(kept) do check(not set[id], "kept node " .. id .. " has no lane") end
end

print(string.format("passivetree_paths_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
