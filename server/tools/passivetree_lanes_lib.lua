-- Path rules of the class lanes of the passive tree (tools/gen_class_lanes.lua, tests/passivetree_paths_test.lua).
-- Pure Lua, no engine calls, Lua 5.1 / LuaJIT and Lua 5.3, deterministic (no pairs() order in any result).
--
-- A "route" is the shortest legal path of a class from the start (node 1) to a target (a keystone or a notable): the
-- fewest nodes, then the fewest irrelevant nodes, then the most relevant nodes. A node is
--   "rel"      a flag node (keystone / class / archetype / mastery: the point of the route) or one with a primary or
--              secondary stat of the class (passivetree_stats_config.lua)
--   "bad"      a stat from the class's irrelevant list
--   "neutral"  anything else (a plain stat the class does not care about)
-- Lanes.stats(tree, classKey, variantKey, id, lanes) is what the class gets from the node: its variant, else its own
-- stats; a lane ({[node id] = stats}, the generated re-skin of classlanes.lua) replaces a plain node's stats for that
-- variant key.

local Lanes = {}

function Lanes.isFlagNode(node)
	if node.m then
		return true
	end
	for stat in pairs(node.s or {}) do
		if stat:match("^ar%u") or stat:match("^ks%u") or stat:match("^ct%u") then
			return true
		end
	end
	for _, v in pairs(node.v or {}) do
		for stat in pairs(v) do
			if stat:match("^ar%u") or stat:match("^ks%u") or stat:match("^ct%u") then
				return true
			end
		end
	end
	return false
end

function Lanes.allowed(node, classKey)
	return node ~= nil and (not node.c or node.c[classKey] == true)
end

-- class of one node: "rel" | "bad" | "neutral"
function Lanes.kind(node, id, info, variantKey, lane)
	if Lanes.isFlagNode(node) then
		return "rel"
	end
	local stats = (lane and lane[id]) or (node.v and node.v[variantKey]) or node.s or {}
	local tag, bad = nil, false
	for stat in pairs(stats) do
		if info.bad[stat] then
			bad = true
		end
		local t = info.tag[stat]
		if t then
			tag = true
		end
	end
	if bad then
		return "bad"
	end
	return tag and "rel" or "neutral"
end

-- routes[target] = {path = {ids}, rel = n, bad = n, len = n} for every target the class can reach
function Lanes.routes(tree, classKey, info, variantKey, targets, lane)
	local kind = {}
	local function kindOf(id)
		local k = kind[id]
		if not k then
			k = Lanes.kind(tree.nodes[id], id, info, variantKey, lane)
			kind[id] = k
		end
		return k
	end
	local best = {[tree.root] = {len = 0, rel = 0, bad = 0, parent = false}}
	local layer = {tree.root}
	while #layer > 0 do
		local nextLayer, seen = {}, {}
		for _, id in ipairs(layer) do
			local cur = best[id]
			local neighbours = tree.nodes[id].n
			for i = 1, #neighbours do
				local n = neighbours[i]
				local node = tree.nodes[n]
				if n ~= tree.root and Lanes.allowed(node, classKey) and (best[n] == nil or best[n].len == cur.len + 1) then
					local k = kindOf(n)
					local cand = {len = cur.len + 1, rel = cur.rel + (k == "rel" and 1 or 0), bad = cur.bad + (k == "bad" and 1 or 0),
						parent = id}
					local old = best[n]
					if old == nil or cand.bad < old.bad or (cand.bad == old.bad and cand.rel > old.rel)
							or (cand.bad == old.bad and cand.rel == old.rel and id < old.parent) then
						best[n] = cand
						if not seen[n] then
							seen[n] = true
							nextLayer[#nextLayer + 1] = n
						end
					end
				end
			end
		end
		table.sort(nextLayer)
		layer = nextLayer
	end
	local routes = {}
	for _, t in ipairs(targets) do
		local b = best[t]
		if b and t ~= tree.root then
			local path, id = {}, t
			while id and id ~= tree.root do
				table.insert(path, 1, id)
				id = best[id].parent
			end
			routes[t] = {path = path, rel = b.rel, bad = b.bad, len = b.len}
		end
	end
	return routes
end

-- the numbers of a class: {targets, avg (mean share of relevant nodes), min, passing (routes with share >= x and no bad
-- node), bad (routes with a bad node), worst = {ids}}
function Lanes.summary(routes, targets, x)
	local out = {targets = 0, sum = 0, min = 1, passing = 0, bad = 0, worst = {}}
	for _, t in ipairs(targets) do
		local r = routes[t]
		if r then
			local share = r.rel / r.len
			out.targets = out.targets + 1
			out.sum = out.sum + share
			out.min = math.min(out.min, share)
			if share >= x and r.bad == 0 then
				out.passing = out.passing + 1
			else
				out.worst[#out.worst + 1] = t
			end
			if r.bad > 0 then
				out.bad = out.bad + 1
			end
		end
	end
	out.avg = out.targets > 0 and out.sum / out.targets or 0
	return out
end

return Lanes
