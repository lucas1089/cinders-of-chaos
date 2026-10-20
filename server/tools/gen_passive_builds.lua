-- Regenerates server/data/scripts/chaos/passive_builds_data.lua (the Auto build paths of the passive tree) from the real
-- tree (passivetree_data.lua) and the recipes in passive_builds_config.lua. Run from the server/ folder:
--   luajit tools/gen_passive_builds.lua            write the data file
--   luajit tools/gen_passive_builds.lua --check    exit 1 when the file differs from what the tree and config give (CI)
--   lua5.3 works the same; the output is byte-identical under both. No clock, no random, no pairs() order.
-- Set PASSIVE_BUILDS_GEN_NO_MAIN = true before dofile() to load the functions (tests/passive_builds_test.lua).
--
-- Algorithm (the config file explains the scoring): a build is an ORDER of node ids in which every node touches the
-- start or an earlier node, so every prefix is a legal build and a character with fewer points takes the first N.
-- Role builds first walk to their `targets` (the cheapest legal path from what is already taken, ties to the higher
-- score), then both kinds grow greedily: every step looks at all nodes reachable through nodes the class may hold and
-- takes the whole path to the one with the best (score of the path / points of the path), until the budget is spent.

local Gen = {}
local OUT_DEFAULT = "data/scripts/chaos/passive_builds_data.lua"

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end
Gen.sortedKeys = sortedKeys

local function isFlag(stat)
	return stat:match("^ar%u") or stat:match("^ks%u") or stat:match("^ct%u")
end

-- a node with per-class variants of its own (the keystones 621 / 624). The class lanes (plain nodes with `v`) are not.
local function hasVariants(node)
	for _, stats in pairs(node.v or {}) do
		for stat in pairs(stats) do
			if isFlag(stat) then
				return true
			end
		end
	end
	return false
end

-- the nodes a theme build must not take unless named: flagged keystones / notables, per-class variants, masteries
local choiceMemo = setmetatable({}, {__mode = "k"})
local function needsChoice(node)
	local memo = choiceMemo[node]
	if memo ~= nil then
		return memo
	end
	memo = false
	if hasVariants(node) or node.m then
		memo = true
	end
	for stat in pairs(node.s or {}) do
		if isFlag(stat) then
			memo = true
		end
	end
	choiceMemo[node] = memo
	return memo
end
Gen.needsChoice = needsChoice

local function median(list)
	table.sort(list)
	return list[math.floor((#list + 1) / 2)] or 1
end

-- ------------------------------------------------------------------------------------------------ context
-- ctx = {tree, cfg, norm = {[stat] = median}, ignored = set}
function Gen.context(tree, cfg)
	local values = {}
	for _, id in ipairs(sortedKeys(tree.nodes)) do
		for stat, v in pairs(tree.nodes[id].s or {}) do
			if not isFlag(stat) and type(v) == "number" and v > 0 then
				values[stat] = values[stat] or {}
				values[stat][#values[stat] + 1] = v
			end
		end
	end
	local norm = {}
	for stat, list in pairs(values) do
		norm[stat] = median(list)
	end
	local ignored = {}
	for _, stat in ipairs(cfg.ignored) do
		ignored[stat] = true
	end
	return {tree = tree, cfg = cfg, norm = norm, ignored = ignored}
end

local function capOf(cfg, stat)
	if cfg.caps[stat] ~= nil then
		return cfg.caps[stat]
	end
	if stat:match("^absorb") then
		return cfg.caps.absorb
	end
	return math.huge
end

-- the stats a node gives this class: its variant, else its own; a mastery its chosen effect
local function statsOf(node, variant, choice)
	if node.m then
		return choice and node.m[choice] or {}
	end
	return (node.v and node.v[variant]) or node.s or {}
end
Gen.statsOf = statsOf

-- the weight table of a theme for a class: groups expanded, line skills / attributes / shielding added
function Gen.weights(cfg, theme, lineKey)
	local w = {}
	for name, weight in pairs(theme.stats or {}) do
		local group = cfg.groups[name]
		if group then
			for _, stat in ipairs(group) do
				w[stat] = math.max(w[stat] or 0, weight)
			end
		else
			w[name] = math.max(w[name] or 0, weight)
		end
	end
	if theme.skills then
		for stat, weight in pairs(cfg.lineSkills[lineKey] or {}) do
			w[stat] = math.max(w[stat] or 0, weight)
		end
	end
	if theme.attributes then
		for stat, weight in pairs(cfg.lineAttributes[lineKey] or {}) do
			w[stat] = math.max(w[stat] or 0, weight)
		end
	end
	if theme.shield and cfg.shieldLines[lineKey] then
		w.shieldingSkill = math.max(w.shieldingSkill or 0, 1)
	end
	return w
end

-- score of one node under weights `w` with the stats `acc` already taken; returns score, relevant (> 0 from the weights)
local function score(ctx, node, id, w, nodeScores, acc, variant, choice)
	local cfg = ctx.cfg
	local s, relevant = 0, false
	if nodeScores and nodeScores[id] then
		s = s + nodeScores[id]
		relevant = true
	end
	local plain = false
	local bad = ctx.bad or {}
	for stat, v in pairs(statsOf(node, variant, choice)) do
		if not isFlag(stat) and not ctx.ignored[stat] then
			-- a stat the class never uses (passivetree_stats_config.lua irrelevant) earns no base score
			plain = plain or not bad[stat]
			local weight = w[stat]
			if weight then
				-- a stat under its cap scores in full (the last node may overshoot, as in the game); at the cap it scores 0
				local gain = (acc[stat] or 0) >= capOf(cfg, stat) and 0 or v
				if gain > 0 then
					s = s + weight * gain / (ctx.norm[stat] or 1)
					relevant = true
				end
			end
		end
	end
	if plain and not node.m then
		s = s + cfg.baseScore
	end
	return s, relevant
end

-- ------------------------------------------------------------------------------------------------ growth
-- state = {set = {[id] = true}, order = {...}, acc = {[stat] = total}, masteries = {}}
local function newState()
	return {set = {}, order = {}, acc = {}, masteries = {}, relevant = 0}
end

local function take(ctx, st, id, w, nodeScores, variant, choice)
	local node = ctx.tree.nodes[id]
	local _, relevant = score(ctx, node, id, w, nodeScores, st.acc, variant, choice)
	st.set[id] = true
	st.order[#st.order + 1] = id
	if choice then
		st.masteries[id] = choice
	end
	if relevant then
		st.relevant = st.relevant + 1
	end
	for stat, v in pairs(statsOf(node, variant, choice)) do
		st.acc[stat] = (st.acc[stat] or 0) + v
	end
end

-- best effect of a mastery node under weights w
local function bestChoice(ctx, node, id, w, variant)
	local best, bestScore = 1, -1
	for i = 1, #node.m do
		local s = score(ctx, {s = node.m[i]}, id, w, nil, {}, variant)
		if s > bestScore then
			best, bestScore = i, s
		end
	end
	return best
end

-- Breadth-first from the taken set through nodes `ok(id)` accepts. Returns dist, parent, cum (cumulative score of the
-- path to a node, the best among the shortest paths).
local function search(ctx, st, ok, scoreOf)
	local tree = ctx.tree
	local dist, parent, cum = {}, {}, {}
	local queue, head = {}, 1
	local function start(id)
		dist[id] = 0
		cum[id] = 0
		queue[#queue + 1] = id
	end
	start(tree.root)
	for _, id in ipairs(st.order) do
		start(id)
	end
	while head <= #queue do
		local current = queue[head]
		head = head + 1
		local neighbours = tree.nodes[current].n
		for i = 1, #neighbours do
			local n = neighbours[i]
			if not st.set[n] and n ~= tree.root and ok(n) then
				local d = dist[current] + 1
				if dist[n] == nil then
					dist[n] = d
					parent[n] = current
					cum[n] = cum[current] + scoreOf(n)
					queue[#queue + 1] = n
				elseif dist[n] == d and cum[current] + scoreOf(n) > cum[n] then
					parent[n] = current
					cum[n] = cum[current] + scoreOf(n)
				end
			end
		end
	end
	return dist, parent, cum, queue
end

local function pathTo(parent, st, target)
	local path = {}
	local id = target
	while id and not st.set[id] and parent[id] do
		table.insert(path, 1, id)
		id = parent[id]
	end
	return path
end

-- one build. spec = {weights, nodeScores, targets, masteries, classKey, lineKey, variant, budget}
function Gen.grow(ctx, spec)
	local tree, cfg = ctx.tree, ctx.cfg
	local st = newState()
	local allowedTargets = {}
	for _, id in ipairs(spec.targets or {}) do
		allowedTargets[id] = true
	end
	for id in pairs(spec.nodeScores or {}) do
		allowedTargets[id] = true
	end
	local function allowed(id)
		local node = tree.nodes[id]
		return node and (not node.c or node.c[spec.classKey] == true)
	end
	local function ok(id)
		return allowed(id) and (allowedTargets[id] or not needsChoice(tree.nodes[id]))
	end
	-- scores only change when a stat reaches its cap: cached until then
	local cache, saturated = {}, {}
	local function scoreOf(id)
		local v = cache[id]
		if v == nil then
			local node = tree.nodes[id]
			local choice = node.m and (spec.masteries and spec.masteries[id] or bestChoice(ctx, node, id, spec.weights, spec.variant)) or nil
			v = (score(ctx, node, id, spec.weights, spec.nodeScores, st.acc, spec.variant, choice))
			cache[id] = v
		end
		return v
	end
	local function checkSaturation()
		for stat, total in pairs(st.acc) do
			if not saturated[stat] and total >= capOf(cfg, stat) then
				saturated[stat] = true
				cache = {}
			end
		end
	end
	-- on the way to a target a class notable or keystone may be passed (not a priced archetype keystone, a variant or a mastery)
	local function okTarget(id)
		local node = tree.nodes[id]
		if not allowed(id) then
			return false
		end
		if allowedTargets[id] then
			return true
		end
		if hasVariants(node) or node.m then
			return false
		end
		for stat in pairs(node.s or {}) do
			if stat:match("^ar%u") then
				return false
			end
		end
		return true
	end
	local function add(path)
		for _, id in ipairs(path) do
			if #st.order >= spec.budget then
				return
			end
			local node = tree.nodes[id]
			local choice
			if node.m then
				choice = spec.masteries and spec.masteries[id] or bestChoice(ctx, node, id, spec.weights, spec.variant)
			end
			take(ctx, st, id, spec.weights, spec.nodeScores, spec.variant, choice)
		end
		checkSaturation()
	end
	for _, target in ipairs(spec.targets or {}) do
		if not st.set[target] then
			if not allowed(target) then
				return nil, string.format("target %d is not a node of class %s", target, spec.classKey)
			end
			local _, parent = search(ctx, st, okTarget, scoreOf)
			local path = pathTo(parent, st, target)
			if #path == 0 then
				return nil, string.format("target %d is not reachable for class %s", target, spec.classKey)
			end
			add(path)
		end
	end
	while #st.order < spec.budget do
		local dist, parent, cum, queue = search(ctx, st, ok, scoreOf)
		local bestId, bestRatio, bestDist
		for _, id in ipairs(queue) do
			local d = dist[id]
			if d > 0 and (not needsChoice(tree.nodes[id]) or allowedTargets[id]) then
				local ratio = cum[id] / d
				if bestId == nil or ratio > bestRatio + 1e-9 or (math.abs(ratio - bestRatio) <= 1e-9 and
					(d < bestDist or (d == bestDist and id < bestId))) then
					bestId, bestRatio, bestDist = id, ratio, d
				end
			end
		end
		if not bestId then
			break
		end
		add(pathTo(parent, st, bestId))
	end
	return st
end

-- the three stats a build gives most (weighted by `weights`, else raw), as {{stat, total}, ...}
local function topStats(ctx, st, weights)
	local list = {}
	for stat, total in pairs(st.acc) do
		if ctx.cfg.statLabels[stat] and not ctx.ignored[stat] then
			list[#list + 1] = {stat, total, (weights[stat] or 0.01) * total / (ctx.norm[stat] or 1)}
		end
	end
	table.sort(list, function(a, b)
		if a[3] ~= b[3] then
			return a[3] > b[3]
		end
		return a[1] < b[1]
	end)
	local out = {}
	for i = 1, math.min(3, #list) do
		out[i] = {list[i][1], list[i][2]}
	end
	return out
end

local function themeNodeScores(theme, classKey, tree)
	local out = {}
	for id, s in pairs(theme.nodes or {}) do
		local node = tree.nodes[id]
		if node and (not node.c or node.c[classKey] == true) then
			out[id] = s
		end
	end
	return out
end

local function classListed(theme, classKey)
	if not theme.classes then
		return true
	end
	for _, key in ipairs(theme.classes) do
		if key == classKey then
			return true
		end
	end
	return false
end

-- all builds of one class: {roles..., themes...}; errors are returned as a list of strings
function Gen.classBuilds(ctx, classKey, lineKey, variant)
	local cfg = ctx.cfg
	local info = ctx.statsCfg and PassiveStatsCore.classInfo(ctx.statsCfg, classKey)
	ctx.bad = info and info.bad or {}
	local themes = {}
	for _, theme in ipairs(cfg.themes) do
		themes[theme.key] = theme
	end
	local builds, errors = {}, {}
	for _, role in ipairs(cfg.roles[classKey] or {}) do
		local theme = themes[role.fill]
		local weights = Gen.weights(cfg, theme, lineKey)
		for stat in pairs(ctx.bad) do
			weights[stat] = nil
		end
		local st, err = Gen.grow(ctx, {
			weights = weights, nodeScores = themeNodeScores(theme, classKey, ctx.tree), targets = role.targets,
			masteries = role.masteries, classKey = classKey, lineKey = lineKey, variant = variant, budget = cfg.maxPoints
		})
		if st then
			builds[#builds + 1] = {id = classKey .. "_" .. role.id, kind = "role", role = role, order = st.order,
				masteries = st.masteries, top = topStats(ctx, st, weights)}
		else
			errors[#errors + 1] = classKey .. "/" .. role.id .. ": " .. err
		end
	end
	for _, theme in ipairs(cfg.themes) do
		if classListed(theme, classKey) then
			local weights = Gen.weights(cfg, theme, lineKey)
			for stat in pairs(ctx.bad) do
				weights[stat] = nil
			end
			local nodeScores = themeNodeScores(theme, classKey, ctx.tree)
			local st = Gen.grow(ctx, {
				weights = weights, nodeScores = nodeScores, targets = {}, classKey = classKey, lineKey = lineKey,
				variant = variant, budget = cfg.maxPoints
			})
			local need = theme.minNodes or cfg.minNodes
			if st and st.relevant >= need then
				builds[#builds + 1] = {id = "focus_" .. theme.key, kind = "focus", theme = theme, order = st.order,
					masteries = st.masteries, top = topStats(ctx, st, weights), relevant = st.relevant}
			end
		end
	end
	return builds, errors
end

-- ------------------------------------------------------------------------------------------------ output
local function writeList(list)
	local parts = {}
	for i, v in ipairs(list) do
		parts[i] = tostring(v)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

function Gen.render(all)
	local out = {}
	local function w(s)
		out[#out + 1] = s
	end
	w("-- passive_builds_data.lua  (GENERATED by server/tools/gen_passive_builds.lua from passivetree_data.lua and")
	w("-- passive_builds_config.lua; do not edit by hand, CI checks it is up to date)")
	w("-- ChaosPassiveBuildsData.classes[classKey] = list of {id, kind = \"role\" | \"focus\", order = {node ids, each touching")
	w("-- the start or an earlier node}, masteries = {[node id] = effect}, top = {{stat, total}, ...}}")
	w("if ChaosPassiveBuildsData then return ChaosPassiveBuildsData end")
	w("ChaosPassiveBuildsData = {version = 1, maxPoints = " .. all.maxPoints .. ", classes = {")
	for _, classKey in ipairs(sortedKeys(all.classes)) do
		w("[\"" .. classKey .. "\"] = {")
		for _, b in ipairs(all.classes[classKey]) do
			local m = {}
			for _, id in ipairs(sortedKeys(b.masteries)) do
				m[#m + 1] = "[" .. id .. "]=" .. b.masteries[id]
			end
			local top = {}
			for i, t in ipairs(b.top) do
				top[i] = string.format("{\"%s\",%s}", t[1], tostring(t[2]))
			end
			w(string.format("{id=\"%s\",kind=\"%s\",order=%s,masteries={%s},top={%s}},", b.id, b.kind, writeList(b.order),
				table.concat(m, ","), table.concat(top, ",")))
		end
		w("},")
	end
	w("}}")
	w("return ChaosPassiveBuildsData")
	return table.concat(out, "\n") .. "\n"
end

-- everything: loads the tree, the config and the class rules; returns the data text and a list of errors
function Gen.build()
	local n = 0
	if not rawget(_G, "Chaos") then
		setmetatable(_G, {__index = function(t, k)
			if type(k) == "string" and k:match("^[A-Z_0-9]+$") then
				n = n + 1
				rawset(t, k, n)
				return n
			end
		end})
		dofile("data/scripts/chaos/chaos_constants.lua")
	end
	if not ChaosClasses then
		dofile("data/scripts/chaos/classes.lua")
	end
	local tree = dofile("data/scripts/chaos/passivetree_data.lua")
	local cfg = dofile("data/scripts/chaos/passive_builds_config.lua")
	if not PassiveStatsCore then
		dofile("data/scripts/chaos/passivetree_stats_core.lua")
	end
	local ctx = Gen.context(tree, cfg)
	ctx.statsCfg = dofile("data/scripts/chaos/passivetree_stats_config.lua")
	local all, errors = {maxPoints = cfg.maxPoints, classes = {}}, {}
	local ids = Chaos.classes.ids
	for _, classKey in ipairs(sortedKeys(ids)) do
		local vocId = ids[classKey]
		local base = Chaos.classes.baseOf[vocId]
		local lineKey = ChaosClasses.classKey(base)
		local builds, errs = Gen.classBuilds(ctx, classKey, lineKey, ChaosClasses.keystoneKey(vocId))
		all.classes[classKey] = builds
		for _, e in ipairs(errs) do
			errors[#errors + 1] = e
		end
	end
	return Gen.render(all), errors, all
end

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

if not PASSIVE_BUILDS_GEN_NO_MAIN then
	local text, errors = Gen.build()
	if #errors > 0 then
		for _, e in ipairs(errors) do
			io.stderr:write("gen_passive_builds: " .. e .. "\n")
		end
		os.exit(1)
	end
	if arg and arg[1] == "--check" then
		if readFile(OUT_DEFAULT) ~= text then
			io.stderr:write("passive_builds_data.lua is out of date: run luajit tools/gen_passive_builds.lua\n")
			os.exit(1)
		end
		print("passive_builds_data.lua is up to date")
	else
		local f = assert(io.open(OUT_DEFAULT, "wb"))
		f:write(text)
		f:close()
		print("wrote " .. OUT_DEFAULT .. " (" .. #text .. " bytes)")
	end
end

return Gen
