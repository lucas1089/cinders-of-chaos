-- Passive tree rules without engine calls (passivetree.lua, buildshare.lua, loadouts.lua, inspect.lua;
-- tests: server/tests/passivetree_plan_test.lua). Numbers in passivetree_config.lua. Lua 5.1 / LuaJIT and Lua 5.3.
--
--   ChaosPassiveTreeCore.parseAlloc(text)             ids, masteries of a saved allocation text (see below)
--   ChaosPassiveTreeCore.formatAlloc(ids, masteries)  the text; ids sorted, mastery choices only for listed mastery ids
--   ChaosPassiveTreeCore.isMastery(node)              the node offers effects to choose from (node.m)
--   ChaosPassiveTreeCore.nodeStats(node, variantKey, choice)   the stats a node gives (variant, or the chosen effect)
--   ChaosPassiveTreeCore.cleanMasteries(tree, ids, masteries)  only allocated mastery nodes with a valid choice
--   ChaosPassiveTreeCore.toMap(raw) / toList(map)     masteries from a request ({{id, choice}} or {[id] = choice}) / to JSON
--   ChaosPassiveTreeCore.validatePlan(tree, current, currentMasteries, plan, ctx)   a whole planned allocation, see there
--   ChaosPassiveTreeCore.checkMasteryChange(tree, current, masteries, id, choice)  changing the effect of a saved mastery
--   ChaosPassiveTreeCore.reworkedSince(list, seen, tree, variantKey) / dropNodes(tree, ids, drop)   the free refund of reworked nodes
--
-- Saved allocation text (the `nodes` column of chaos_passive_tree and the `tree` column of chaos_loadouts):
--   "2,3,9"              node ids (root excluded), as before
--   "2,3,9,665|665:2"    the same, then "|" and the chosen effect of each allocated mastery node (id:choice)
-- A text without "|" is read exactly as before, so every saved tree stays valid.
--
-- Mastery nodes (node.m = {{customStats of effect 1}, {effect 2}, ...} in passivetree_data.lua, from `masteries` in the
-- client's nodes.lua): one point like every node; the player picks one effect when the node is planned (free). Changing
-- the effect of a saved mastery costs the single-node refund price (respec.lua); a refund or reset drops the choice.

ChaosPassiveTreeCore = ChaosPassiveTreeCore or {}
local M = ChaosPassiveTreeCore

local function config(cfg)
	return cfg or ChaosPassiveTreeConfig or {maxPlanNodes = 300}
end

local function int(value)
	local n = tonumber(value)
	if not n or n ~= n or n == math.huge or n == -math.huge or n ~= math.floor(n) then
		return nil
	end
	return n
end

-- ------------------------------------------------------------------------------------------------ saved text
function M.parseAlloc(text)
	text = tostring(text or "")
	local idPart, rest = text:match("^([^|]*)|(.*)$")
	idPart = idPart or text
	local ids, seen = {}, {}
	for token in idPart:gmatch("%d+") do
		local id = tonumber(token)
		if id and id > 0 and not seen[id] then
			seen[id] = true
			ids[#ids + 1] = id
		end
	end
	local masteries = {}
	for id, choice in (rest or ""):gmatch("(%d+):(%d+)") do
		id, choice = tonumber(id), tonumber(choice)
		if seen[id] and choice > 0 then
			masteries[id] = choice
		end
	end
	return ids, masteries
end

function M.formatAlloc(ids, masteries)
	local copy, set = {}, {}
	for i, id in ipairs(ids or {}) do
		copy[i] = id
		set[id] = true
	end
	table.sort(copy)
	local text = table.concat(copy, ",")
	local keys = {}
	for id, choice in pairs(masteries or {}) do
		if set[id] and int(choice) and choice > 0 then
			keys[#keys + 1] = id
		end
	end
	if #keys == 0 then
		return text
	end
	table.sort(keys)
	local parts = {}
	for i, id in ipairs(keys) do
		parts[i] = id .. ":" .. masteries[id]
	end
	return text .. "|" .. table.concat(parts, ",")
end

-- ------------------------------------------------------------------------------------------------ mastery nodes
function M.isMastery(node)
	return type(node) == "table" and type(node.m) == "table" and #node.m > 0
end

function M.validChoice(node, choice)
	choice = int(choice)
	return M.isMastery(node) and choice ~= nil and choice >= 1 and choice <= #node.m
end

-- the stats a node gives: a mastery its chosen effect (nothing without a choice), a keystone the variant of
-- variantKey when it has one, any other node its own stats
function M.nodeStats(node, variantKey, choice)
	if not node then
		return nil
	end
	if M.isMastery(node) then
		return M.validChoice(node, choice) and node.m[int(choice)] or nil
	end
	return (node.v and variantKey and node.v[variantKey]) or node.s
end

function M.cleanMasteries(tree, ids, masteries)
	local out = {}
	for _, id in ipairs(ids or {}) do
		local choice = masteries and masteries[id]
		if M.validChoice(tree.nodes[id], choice) then
			out[id] = int(choice)
		end
	end
	return out
end

-- a request's masteries: a list {{id = n, choice = c}} (what the client sends) or a map {[id] = c} / {["id"] = c}.
-- Returns a map, or nil + error for anything malformed (an id twice is malformed too).
function M.toMap(raw)
	local out = {}
	if raw == nil then
		return out
	end
	if type(raw) ~= "table" then
		return nil, "Malformed request."
	end
	local count = 0
	for key, value in pairs(raw) do
		local id, choice
		if type(value) == "table" then
			id, choice = int(value.id), int(value.choice)
		else
			id, choice = int(key), int(value)
		end
		count = count + 1
		if not id or not choice or id < 1 or count > 64 then
			return nil, "Malformed request."
		end
		if out[id] then
			return nil, string.format("Mastery node %d is in the request twice.", id)
		end
		out[id] = choice
	end
	return out
end

function M.toList(map)
	local list = {}
	for id, choice in pairs(map or {}) do
		list[#list + 1] = {id = id, choice = choice}
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

-- ------------------------------------------------------------------------------------------------ the planner
-- ids of `set` (a set of node ids, root excluded) reached from the root through `set`, as a set
local function reach(tree, set)
	local reached, queue, head = {[tree.root] = true}, {tree.root}, 1
	while head <= #queue do
		local current = queue[head]
		head = head + 1
		local node = tree.nodes[current]
		for _, neighbour in ipairs(node and node.n or {}) do
			if set[neighbour] and not reached[neighbour] then
				reached[neighbour] = true
				queue[#queue + 1] = neighbour
			end
		end
	end
	return reached
end
M.reach = reach

-- The plan without the nodes the character already holds (a plan made from a view of the tree that was a step behind the
-- server: a refund, a second window, a reply still on its way). Holding a node already is what the plan wants, so it is no
-- reason to refuse the rest: plan.nodes / plan.masteries are copied without those ids. Returns the new plan and the number
-- of nodes dropped; a malformed plan is returned as it is (validatePlan refuses it).
function M.dropOwned(current, plan)
	if type(plan) ~= "table" or type(plan.nodes) ~= "table" then
		return plan, 0
	end
	local owned = {}
	for _, id in ipairs(current or {}) do
		owned[id] = true
	end
	local nodes, dropped = {}, 0
	for _, value in ipairs(plan.nodes) do
		local id = int(value)
		if id and owned[id] then
			dropped = dropped + 1
		else
			nodes[#nodes + 1] = value
		end
	end
	if dropped == 0 then
		return plan, 0
	end
	local masteries = plan.masteries
	if type(masteries) == "table" then
		local kept = {}
		for key, value in pairs(masteries) do
			local isEntry = type(value) == "table"
			local id = isEntry and int(value.id) or int(key)
			if not (id and owned[id]) then
				if isEntry then
					kept[#kept + 1] = value -- a list of {id, choice} stays a list
				else
					kept[key] = value -- a map {[id] = choice} stays a map
				end
			end
		end
		masteries = kept
	end
	return {nodes = nodes, masteries = masteries}, dropped
end

-- A whole planned allocation (planApply), checked like a save of the saved nodes plus the plan:
--   tree             passivetree_data.lua
--   current          the saved node ids (list), currentMasteries their chosen effects ({[id] = choice})
--   plan             {nodes = {ids to add, in any order}, masteries = {{id, choice}} or {[id] = choice}}
--   ctx              {classKey, allowed = function(node, classKey) -> bool (ChaosClassTree.allowed; default: unmarked
--                     nodes only), points = passive points owned, maxNodes = request cap (config maxPlanNodes)}
-- Rules: a table; 1..maxNodes ids; every id a known node (not the root), not twice, not already allocated, one the class
-- may hold; saved + planned nodes <= points; every planned node connected to the root through saved and planned nodes
-- (a breadth-first walk); every planned mastery node has a valid choice; a choice only for planned mastery nodes (a
-- saved one changes through checkMasteryChange, which is priced).
-- Returns {ids = saved then planned (list), added = planned (list), masteries = saved + planned choices (map)} or
-- nil, error text, error code ("malformed", "empty", "size", "unknown", "duplicate", "owned", "class", "points",
-- "disconnected", "mastery").
function M.validatePlan(tree, current, currentMasteries, plan, ctx, cfg)
	cfg = config(cfg)
	ctx = ctx or {}
	if type(plan) ~= "table" or type(plan.nodes) ~= "table" then
		return nil, "Malformed request.", "malformed"
	end
	local raw = plan.nodes
	local n = 0
	for _ in pairs(raw) do
		n = n + 1
	end
	if n == 0 then
		return nil, "Nothing is planned.", "empty"
	end
	local cap = ctx.maxNodes or cfg.maxPlanNodes or 300
	if n > cap or #raw ~= n then
		return nil, n > cap and string.format("The plan is too large (at most %d nodes).", cap) or "Malformed request.",
			n > cap and "size" or "malformed"
	end
	local allowed = ctx.allowed or function(node, classKey)
		return not node.c or (classKey ~= nil and node.c[classKey] == true)
	end
	local owned = {}
	for _, id in ipairs(current or {}) do
		owned[id] = true
	end
	local set, added = {}, {}
	for _, value in ipairs(raw) do
		local id = int(value)
		local node = id and tree.nodes[id]
		if not node or id == tree.root then
			return nil, "Unknown node in the plan.", "unknown"
		end
		if set[id] then
			return nil, string.format("Node %d is in the plan twice.", id), "duplicate"
		end
		if owned[id] then
			return nil, string.format("Node %d is already allocated.", id), "owned"
		end
		if not allowed(node, ctx.classKey) then
			return nil, string.format("Node %d belongs to another class.", id), "class"
		end
		set[id] = true
		added[#added + 1] = id
	end
	local points = math.max(0, math.floor(tonumber(ctx.points) or 0))
	local total = #(current or {}) + #added
	if total > points then
		return nil, string.format("The plan needs %d points; you have %d free.", #added, math.max(0, points - #(current or {}))),
			"points"
	end
	local all = {}
	for id in pairs(owned) do
		all[id] = true
	end
	for id in pairs(set) do
		all[id] = true
	end
	local reached = reach(tree, all)
	table.sort(added)
	for _, id in ipairs(added) do
		if not reached[id] then
			return nil, string.format("Node %d is not connected to your allocated nodes.", id), "disconnected"
		end
	end
	local choices, err = M.toMap(plan.masteries)
	if not choices then
		return nil, err, "malformed"
	end
	for id, choice in pairs(choices) do
		local node = tree.nodes[id]
		if not M.isMastery(node) then
			return nil, string.format("Node %d is not a mastery node.", id), "mastery"
		end
		if owned[id] then
			return nil, "A saved mastery changes its effect with Change effect (a priced respec), not with a plan.", "mastery"
		end
		if not set[id] then
			return nil, string.format("Mastery node %d is not in the plan.", id), "mastery"
		end
		if not M.validChoice(node, choice) then
			return nil, string.format("Mastery node %d has no effect %d.", id, choice), "mastery"
		end
	end
	local masteries = M.cleanMasteries(tree, current, currentMasteries)
	for _, id in ipairs(added) do
		if M.isMastery(tree.nodes[id]) then
			if not choices[id] then
				return nil, string.format("Choose an effect for the mastery node %d.", id), "mastery"
			end
			masteries[id] = choices[id]
		end
	end
	local ids = {}
	for _, id in ipairs(current or {}) do
		ids[#ids + 1] = id
	end
	for _, id in ipairs(added) do
		ids[#ids + 1] = id
	end
	return {ids = ids, added = added, masteries = masteries}
end

-- the effect of a saved mastery node changes: true, or nil + error text
function M.checkMasteryChange(tree, current, masteries, id, choice)
	id, choice = int(id), int(choice)
	local node = id and tree.nodes[id]
	if not M.isMastery(node) then
		return nil, "That is not a mastery node."
	end
	local held = false
	for _, other in ipairs(current or {}) do
		held = held or other == id
	end
	if not held then
		return nil, "That mastery is not allocated: plan it and choose its effect there."
	end
	if not M.validChoice(node, choice) then
		return nil, "That mastery has no such effect."
	end
	if masteries and masteries[id] == choice then
		return nil, "That effect is already chosen."
	end
	return true
end

-- ------------------------------------------------------------------------------------------------ reworked nodes
-- A node whose meaning changed a lot (config `reworked`: {{version, ids}}, append only) is refunded once, for free:
-- the saved trees lose it, and the nodes only connected through it, at the first login after its version.
-- reworkedSince(list, seen, tree, variantKey) -> set of the ids reworked after version `seen` (a storage value; -1 /
-- nil = none seen), the newest version (seen when there is nothing newer). An entry with `lanes = true` also reworks,
-- for a character whose variant key is `variantKey`, every plain node that has a class lane for that key (the
-- generated re-skin of the tree for one class, tools/gen_class_lanes.lua): its stat changed for that class only.
function M.reworkedSince(list, seen, tree, variantKey)
	seen = tonumber(seen) or -1
	local set, newest, any = {}, seen, false
	for _, entry in ipairs(list or {}) do
		local v = tonumber(entry.version) or 0
		if v > seen then
			for _, id in ipairs(entry.ids or {}) do
				set[id] = true
				any = true
			end
			if entry.lanes and tree and variantKey then
				for id, node in pairs(tree.nodes) do
					if node.s and node.v and node.v[variantKey] then
						set[id] = true
						any = true
					end
				end
			end
		end
		if v > newest then
			newest = v
		end
	end
	return set, newest, any
end

-- dropNodes(tree, ids, drop) -> kept (list, in the order of ids), removed (list of {id, why = "reworked" |
-- "disconnected"}). The ids are a saved allocation (root excluded); drop is a set of ids.
function M.dropNodes(tree, ids, drop)
	local set, order, removed = {}, {}, {}
	for _, id in ipairs(ids or {}) do
		if drop[id] then
			removed[#removed + 1] = {id = id, why = "reworked"}
		elseif not set[id] then
			set[id] = true
			order[#order + 1] = id
		end
	end
	if #removed == 0 then
		return order, removed
	end
	local reached = reach(tree, set)
	local kept = {}
	for _, id in ipairs(order) do
		if reached[id] then
			kept[#kept + 1] = id
		else
			removed[#removed + 1] = {id = id, why = "disconnected"}
		end
	end
	return kept, removed
end

return ChaosPassiveTreeCore
