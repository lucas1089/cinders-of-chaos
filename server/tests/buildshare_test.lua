-- Run from the server/ folder: luajit tests/buildshare_test.lua (or lua5.3; CI runs both)
-- Build codes (buildshare_core.lua): round trip, checksum, versions, wrong class, unknown / disconnected nodes, keystones,
-- too many points (first N in path order), reset detection, the Paragon part, and that codes survive appended nodes.
-- Format version 2 (the mastery part) and version 1 codes (handed out before it) still read, typos rejected in both.
dofile("data/scripts/chaos/buildshare_core.lua")
local B = ChaosBuildShare
local tree = dofile("data/scripts/chaos/passivetree_data.lua")

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function sorted(list)
	local copy = {}
	for i, v in ipairs(list) do
		copy[i] = v
	end
	table.sort(copy)
	return table.concat(copy, ",")
end

-- a connected build: walk from the root, breadth first, n nodes (no keystones)
local function connected(n)
	local out, seen, queue, head = {}, {[tree.root] = true}, {tree.root}, 1
	while head <= #queue and #out < n do
		local id = queue[head]
		head = head + 1
		for _, nb in ipairs(tree.nodes[id].n) do
			if not seen[nb] and not tree.nodes[nb].v and not tree.nodes[nb].c and #out < n then
				seen[nb] = true
				out[#out + 1] = nb
				queue[#queue + 1] = nb
			end
		end
	end
	return out
end

-- round trip
local nodes = connected(40)
local code = B.encode({classId = 4, nodes = nodes})
check(code:match("^CB4%-[%w_%-]+$"), "code format " .. code)
local build = assert(B.decode(code))
check(build.classId == 4, "class id round trip")
check(sorted(build.nodes) == sorted(nodes), "nodes round trip")
check(build.paragon == nil, "no paragon part")
local big = connected(248)
local bigCode = B.encode({classId = 1, nodes = big, paragon = {damage = 40, critDamage = 50, health = 40, itemFind = 7}})
local bigBuild = assert(B.decode(bigCode))
check(sorted(bigBuild.nodes) == sorted(big), "248 nodes round trip")
check(bigBuild.paragon.damage == 40 and bigBuild.paragon.critDamage == 50 and bigBuild.paragon.health == 40 and
	bigBuild.paragon.itemFind == 7 and not bigBuild.paragon.speed, "paragon round trip")
check(#bigCode < 140, "248 node code is short (" .. #bigCode .. " chars)")
local all = {}
for id in pairs(tree.nodes) do
	if id ~= tree.root then
		all[#all + 1] = id
	end
end
check(#B.encode({classId = 3, nodes = all}) < 130, "whole tree code is short")
check(B.extract("look [build " .. code .. "] nice") == code, "extract from a build link")
check(B.decode("  " .. code .. " ") ~= nil, "surrounding spaces ignored")

-- checksum: every single character change is rejected
local body = code:sub(5)
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local rejected, tried = 0, 0
for i = 1, #body do
	for _, k in ipairs({1, 17, 40}) do
		local ch = body:sub(i, i)
		local pos = alphabet:find(ch, 1, true)
		local other = alphabet:sub((pos + k - 1) % 64 + 1, (pos + k - 1) % 64 + 1)
		local bad = "CB4-" .. body:sub(1, i - 1) .. other .. body:sub(i + 1)
		tried = tried + 1
		local ok, err = B.decode(bad)
		if not ok and err then
			rejected = rejected + 1
		end
	end
end
check(rejected == tried, string.format("typos rejected %d/%d", rejected, tried))
local swapped = "CB4-" .. body:sub(2, 2) .. body:sub(1, 1) .. body:sub(3)
check(body:sub(1, 1) == body:sub(2, 2) or B.decode(swapped) == nil, "swapped characters rejected")
local _, err = B.decode(code:sub(1, -3))
check(err and err:find("damaged"), "truncated code rejected: " .. tostring(err))
_, err = B.decode("hello")
check(err and err:find("not a build code"), "garbage rejected")
_, err = B.decode("CB4-" .. body .. "!")
check(err ~= nil, "bad character rejected")

-- versions
_, err = B.decode("CB0-" .. body)
check(err and err:find("old format"), "old version: " .. tostring(err))
_, err = B.decode("CB5-" .. body)
check(err and err:find("newer format"), "newer version: " .. tostring(err))
check(B.decode("CB2-" .. body) == nil, "a version 3 body under the version 2 prefix fails its checksum")
-- version 1 (before the masteries) still reads, the same nodes; its checksum covers "CB1"
local v1 = B.encode({classId = 4, nodes = nodes, paragon = {damage = 3}}, 1)
check(v1:match("^CB1%-"), "a version 1 code: " .. v1)
local v1Build = assert(B.decode(v1))
check(v1Build.version == 1 and sorted(v1Build.nodes) == sorted(nodes) and v1Build.paragon.damage == 3 and
	v1Build.masteries == nil, "version 1 decodes")
check(B.decode("CB2-" .. v1:sub(5)) == nil, "a version 1 body under the version 2 prefix fails its checksum")
local v1body, v1rej, v1tried = v1:sub(5), 0, 0
for i = 1, #v1body do
	local ch = v1body:sub(i, i)
	local pos = alphabet:find(ch, 1, true)
	local other = alphabet:sub(pos % 64 + 1, pos % 64 + 1)
	v1tried = v1tried + 1
	if not B.decode("CB1-" .. v1body:sub(1, i - 1) .. other .. v1body:sub(i + 1)) then
		v1rej = v1rej + 1
	end
end
check(v1rej == v1tried, "version 1 typos rejected")
check(B.encode({classId = 4, nodes = {626, 665}, masteries = {[665] = 2}}, 1):match("^CB1%-") and
	B.decode(B.encode({classId = 4, nodes = {626, 665}, masteries = {[665] = 2}}, 1)).masteries == nil,
	"version 1 has no mastery part")

-- class lines: the class byte is a stable line index, not a vocation id
check(B.lineIndex("warrior") == 1 and B.lineIndex("thief") == 4 and B.lineIndex("knight") == 0, "class line index")
check(B.lineName(2) == "Ranger" and B.lineName(0) == nil, "class line name")

-- plan: wrong class
local function names(id)
	return B.lineName(id) or "?"
end
local plan
plan, err = B.plan(tree, build, {classId = 1, className = names, current = {}, points = 100})
check(not plan and err:find("Thief") and err:find("Warrior"), "wrong class: " .. tostring(err))

-- plan: same class, empty tree, enough points
plan = assert(B.plan(tree, build, {classId = 4, current = {}, points = 100, keystoneKey = "knight"}))
check(plan.applied == 40 and plan.skipped == 0 and plan.added == 40 and plan.removed == 0, "plan onto an empty tree")
check(not plan.treeReset, "empty tree: no reset")
check(sorted(plan.nodes) == sorted(nodes), "plan keeps every node")

-- unknown node (a retired id) and a disconnected node
plan, err = B.plan(tree, {classId = 4, nodes = {2, 9, 9999}}, {classId = 4, current = {}, points = 100})
check(not plan and err:find("9999"), "unknown node: " .. tostring(err))
plan, err = B.plan(tree, {classId = 4, nodes = {2, 9, 600}}, {classId = 4, current = {}, points = 100})
check(not plan and err:find("600") and err:find("not connected"), "disconnected node: " .. tostring(err))

-- keystones: only with a variant for the importer's class
local path = {}
do -- a path from the root to keystone 621 (BFS parents)
	local parent, queue, head = {[tree.root] = 0}, {tree.root}, 1
	while head <= #queue do
		local id = queue[head]
		head = head + 1
		for _, nb in ipairs(tree.nodes[id].n) do
			if parent[nb] == nil then
				parent[nb] = id
				queue[#queue + 1] = nb
			end
		end
	end
	local id = 621
	while id ~= tree.root do
		path[#path + 1] = id
		id = parent[id]
	end
end
local ksBuild = assert(B.decode(B.encode({classId = 11, nodes = path})))
plan, err = B.plan(tree, ksBuild, {classId = 11, current = {}, points = 300, keystoneKey = nil})
check(not plan and err:find("keystone"), "keystone without a variant: " .. tostring(err))
plan, err = B.plan(tree, ksBuild, {classId = 11, current = {}, points = 300, keystoneKey = "knight"})
check(not plan and err:find("another class"), "keystone 621 is not for the Thief line: " .. tostring(err))
plan = B.plan(tree, ksBuild, {classId = 11, current = {}, points = 300, keystoneKey = "knight", classKey = "warrior"})
check(plan and plan.applied == #path, "keystone with a variant")

-- class sections: a Ninja path build imports for a Ninja, not for a Samurai (same line)
local ninja = assert(B.decode(B.encode({classId = 4, nodes = {626, 627, 628, 629, 630, 631}})))
plan = B.plan(tree, ninja, {classId = 4, current = {}, points = 300, keystoneKey = "ninja", classKey = "ninja"})
check(plan and plan.applied == 6, "ninja path for a ninja")
plan, err = B.plan(tree, ninja, {classId = 4, current = {}, points = 300, keystoneKey = "samurai", classKey = "samurai"})
check(not plan and err:find("629"), "ninja path refused for a samurai: " .. tostring(err))

-- too many points: the first N nodes in path order, always connected
plan = assert(B.plan(tree, build, {classId = 4, current = {}, points = 10}))
check(plan.applied == 10 and plan.skipped == 30 and #plan.notes == 1, "truncated to the points owned")
do
	local set = {}
	for _, id in ipairs(plan.nodes) do
		set[id] = true
	end
	local reached, queue, head, n = {[tree.root] = true}, {tree.root}, 1, 0
	while head <= #queue do
		local id = queue[head]
		head = head + 1
		for _, nb in ipairs(tree.nodes[id].n) do
			if set[nb] and not reached[nb] then
				reached[nb] = true
				n = n + 1
				queue[#queue + 1] = nb
			end
		end
	end
	check(n == 10, "the first N nodes are connected")
end
plan, err = B.plan(tree, build, {classId = 4, current = {}, points = 0})
check(not plan and err:find("no passive points"), "no points at all")

-- reset detection: a superset of the current tree is free, anything else takes points back
plan = assert(B.plan(tree, build, {classId = 4, current = {nodes[1], nodes[2]}, points = 100}))
check(not plan.treeReset and plan.added == 38 and plan.removed == 0, "superset of the current tree: no reset")
plan = assert(B.plan(tree, build, {classId = 4, current = connected(60), points = 100}))
check(plan.treeReset and plan.removed == 20 and plan.added == 0, "fewer nodes than now: reset")
plan = assert(B.plan(tree, build, {classId = 4, current = nodes, points = 100}))
check(not plan.treeChange, "same build: no change")
-- truncation keeps the nodes the character already has first
plan = B.plan(tree, build, {classId = 4, current = connected(2), points = 2})
check(plan and not plan.treeReset, "short on points: the nodes it has come first")

-- Paragon part
local pBuild = assert(B.decode(B.encode({classId = 4, nodes = nodes, paragon = {damage = 10, health = 5}})))
local max = {damage = 40, critDamage = 50, health = 40, reduction = 32, speed = 20, mana = 40, goldFind = 20, itemFind = 40}
plan = assert(B.plan(tree, pBuild, {classId = 4, current = {}, points = 100,
	paragon = {unlocked = true, total = 30, current = {}, max = max}}))
check(plan.paragon.damage == 10 and plan.paragon.health == 5 and plan.paragonChange and not plan.paragonReset,
	"paragon applied onto an empty track")
plan = assert(B.plan(tree, pBuild, {classId = 4, current = {}, points = 100,
	paragon = {unlocked = true, total = 30, current = {speed = 3}, max = max}}))
check(plan.paragonReset, "paragon points taken back: reset")
plan = assert(B.plan(tree, pBuild, {classId = 4, current = {}, points = 100,
	paragon = {unlocked = true, total = 12, current = {}, max = max}}))
check(plan.paragon.damage == 10 and plan.paragon.health == 2 and plan.paragonSkipped == 3, "paragon short on points")
plan = assert(B.plan(tree, pBuild, {classId = 4, current = {}, points = 100,
	paragon = {unlocked = false, total = 0, current = {}, max = max}}))
check(plan.paragon == nil and #plan.notes == 1, "paragon locked: skipped with a note")

-- mastery nodes: round trip, plan, effects kept / changed / defaulted
local mNodes = {626, 627, 628, 665}
local mCode = B.encode({classId = 4, nodes = mNodes, masteries = {[665] = 3}, paragon = {health = 2}})
local mBuild = assert(B.decode(mCode))
check(mBuild.version == 4 and mBuild.masteries[665] == 3 and mBuild.paragon.health == 2 and sorted(mBuild.nodes) == sorted(mNodes),
	"mastery round trip with a Paragon part")
local both = assert(B.decode(B.encode({classId = 4, nodes = {626, 627, 628, 665, 636}, masteries = {[665] = 1, [666] = 2}})))
check(both.masteries[665] == 1 and both.masteries[666] == 2, "two mastery choices")
local thief = {classId = 4, current = {}, points = 100, keystoneKey = "thief", classKey = "thief"}
plan = assert(B.plan(tree, mBuild, thief))
check(plan.masteries[665] == 3 and not plan.treeReset, "import takes the code's effect")
plan = assert(B.plan(tree, mBuild, {classId = 4, current = mNodes, currentMasteries = {[665] = 3}, points = 100,
	classKey = "thief"}))
check(not plan.treeChange, "same build and effect: no change")
plan = assert(B.plan(tree, mBuild, {classId = 4, current = mNodes, currentMasteries = {[665] = 1}, points = 100,
	classKey = "thief"}))
check(plan.treeChange and plan.treeReset and plan.masteryChanged == 1 and plan.masteries[665] == 3,
	"another effect for a held mastery is a respec")
local oldCode = assert(B.decode(B.encode({classId = 4, nodes = mNodes}, 1)))
plan = assert(B.plan(tree, oldCode, {classId = 4, current = mNodes, currentMasteries = {[665] = 4}, points = 100,
	classKey = "thief"}))
check(plan.masteries[665] == 4 and not plan.treeChange, "a version 1 code keeps the held effect")
plan = assert(B.plan(tree, oldCode, thief))
check(plan.masteries[665] == 1 and #plan.notes == 1 and plan.notes[1]:find("first effect"), "no effect named: the first, with a note")
plan, err = B.plan(tree, assert(B.decode(B.encode({classId = 4, nodes = mNodes, masteries = {[665] = 7}}))), thief)
check(not plan and err:find("effect 7"), "an effect the mastery does not have: " .. tostring(err))
plan, err = B.plan(tree, assert(B.decode(B.encode({classId = 4, nodes = {626}, masteries = {[626] = 1}}))), thief)
check(not plan and err:find("not a mastery"), "a choice for a plain node: " .. tostring(err))

-- stability: the tree gets new nodes appended (new ids), old codes stay valid and mean the same nodes
local grown = {root = tree.root, nodes = {}}
for id, node in pairs(tree.nodes) do
	local n = {}
	for i, v in ipairs(node.n) do
		n[i] = v
	end
	grown.nodes[id] = {n = n, s = node.s, v = node.v}
end
grown.nodes[625] = {n = {624}, s = {strength = 1}}
table.insert(grown.nodes[624].n, 625)
plan = assert(B.plan(grown, build, {classId = 4, current = {}, points = 100}))
check(sorted(plan.nodes) == sorted(nodes), "an old code is valid on a grown tree")
local newCode = B.encode({classId = 4, nodes = {625}})
check(B.decode(newCode).nodes[1] == 625, "new ids encode")

-- reworked nodes (B.REWORKED, 2026-10: 369, 376, 383, 390 became the line keystones): a code made before the change
-- (version 1 or 2) leaves them out, with the nodes only connected through them; a version 3 code keeps them
local function pathTo(target, classKey)
	local prev, queue, head = {[tree.root] = tree.root}, {tree.root}, 1
	while head <= #queue do
		local id = queue[head]
		head = head + 1
		for _, nb in ipairs(tree.nodes[id].n) do
			local node = tree.nodes[nb]
			if not prev[nb] and (not node.c or node.c[classKey]) and not node.v then
				prev[nb] = id
				queue[#queue + 1] = nb
			end
		end
	end
	local out, id = {}, target
	while id ~= tree.root do
		table.insert(out, 1, id)
		id = prev[id]
	end
	return out
end
check(B.REWORKED[383] == 3 and B.REWORKED[369] == 3 and B.REWORKED[376] == 3 and B.REWORKED[390] == 3, "reworked list")
local toCreed = pathTo(383, "thief")
check(toCreed[#toCreed] == 383 and #toCreed > 10, "a path to Blackblood Creed (" .. #toCreed .. " nodes)")
for _, version in ipairs({1, 2}) do
	local old = assert(B.decode(B.encode({classId = 4, nodes = toCreed}, version)))
	plan = assert(B.plan(tree, old, {classId = 4, classKey = "thief", current = {}, points = 300}))
	local held = {}
	for _, id in ipairs(plan.nodes) do held[id] = true end
	check(not held[383] and plan.reworked == 1 and plan.applied == #toCreed - 1, "version " .. version .. ": 383 left out")
	local noted = false
	for _, n in ipairs(plan.notes) do noted = noted or n:find("tree change", 1, true) ~= nil end
	check(noted, "version " .. version .. ": the note says so")
end
local new = assert(B.decode(B.encode({classId = 4, nodes = toCreed})))
plan = assert(B.plan(tree, new, {classId = 4, classKey = "thief", current = {}, points = 300}))
check(plan.applied == #toCreed and (plan.reworked or 0) == 0, "version 4 keeps the keystone")
plan, err = B.plan(tree, new, {classId = 4, classKey = "ninja", current = {}, points = 300})
check(plan and plan.applied == #toCreed, "every class of the line may take it")
plan, err = B.plan(tree, assert(B.decode(B.encode({classId = 1, nodes = toCreed}))), {classId = 1, classKey = "warrior",
	current = {}, points = 300})
check(not plan and err:find("another class"), "another line may not: " .. tostring(err))
-- a node only connected through a reworked one goes with it (a small made-up tree)
local mini = {root = 1, nodes = {[1] = {n = {383}}, [383] = {n = {1, 5}}, [5] = {n = {383}}}}
plan = assert(B.plan(mini, {classId = 4, version = 2, nodes = {383, 5}}, {classId = 4, current = {}, points = 9}))
check(plan.applied == 0 and plan.reworked == 2, "the node behind it is left out too")
_, err = B.plan(mini, {classId = 4, version = 3, nodes = {5}}, {classId = 4, current = {}, points = 9})
check(err and err:find("not connected"), "without a reworked node a gap is still an error")


-- the build archetype keystones (B.REWORKED version 4, 2026-10): a version 3 code (or older) leaves the twelve converted
-- leaves out, a version 4 code keeps them
check(B.VERSION == 4 and B.READS[3] and B.READS[4], "version 4 written, 3 still read")
for _, id in ipairs({77, 78, 81, 82, 106, 107, 108, 109, 253, 262, 355, 362}) do
	check(B.REWORKED[id] == 4, "reworked in version 4: " .. id)
end
local toPyre = pathTo(108, "warrior")
check(toPyre[#toPyre] == 108, "a path to Pyre Oath (" .. #toPyre .. " nodes)")
local v3 = assert(B.decode(B.encode({classId = 1, nodes = toPyre}, 3)))
plan = assert(B.plan(tree, v3, {classId = 1, classKey = "warrior", current = {}, points = 300}))
local heldPyre = false
for _, id in ipairs(plan.nodes) do heldPyre = heldPyre or id == 108 end
check(not heldPyre and plan.reworked == 1 and plan.applied == #toPyre - 1, "version 3: Pyre Oath left out")
plan = assert(B.plan(tree, assert(B.decode(B.encode({classId = 1, nodes = toPyre}))), {classId = 1, classKey = "warrior",
	current = {}, points = 300}))
check(plan.applied == #toPyre and (plan.reworked or 0) == 0, "version 4 keeps Pyre Oath")
plan, err = B.plan(tree, assert(B.decode(B.encode({classId = 2, nodes = toPyre}))), {classId = 2, classKey = "ranger",
	current = {}, points = 300})
check(not plan and err:find("another class"), "the Ranger line may not take Pyre Oath: " .. tostring(err))

print(string.format("buildshare_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
