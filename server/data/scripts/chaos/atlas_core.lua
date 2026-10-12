-- Rift Atlas: the pure part (no engine calls), shared by atlas.lua and tests/riftatlas_test.lua.
--   index      the node graph of atlas_config.lua: nodes by id, symmetric links, costs
--   grid       the completion cells (theme x tier, flawless / swift per tier, omen kinds), their points, the cells a
--              sealed run earns
--   tree       allocate / refund rules (connected to the start, points, keystone limit), sanitize of a loaded state
--   effects    the summed node effects of an allocation for one run (theme, tier), capped, with the keystone on top:
--              the flat table rift_core.lua takes (R.applyAtlasFx, R.atlasBonus, R.atlasReward, R.keyOdds)
--   text       tooltip lines, the totals, the payloads of the client window (game_riftatlas)
--   layout     the checks of the map (minimum distance between nodes, links clear of other nodes)
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosAtlasCore = ChaosAtlasCore or {}
local A = ChaosAtlasCore

local floor = math.floor

-- ===================================================================== index
-- cfg._idx = {byId = {[id] = node}, adj = {[id] = {[other] = true}}, list = nodes in config order}
function A.index(cfg)
	if cfg._idx then
		return cfg._idx
	end
	local idx = {byId = {}, adj = {}, list = {}}
	for _, n in ipairs(cfg.nodes) do
		n.kind = n.kind or "small"
		idx.byId[n.id] = n
		idx.adj[n.id] = idx.adj[n.id] or {}
		idx.list[#idx.list + 1] = n
	end
	for _, n in ipairs(cfg.nodes) do
		for _, l in ipairs(n.links or {}) do
			if idx.byId[l] then
				idx.adj[n.id][l] = true
				idx.adj[l][n.id] = true
			end
		end
	end
	cfg._idx = idx
	return idx
end

function A.node(cfg, id)
	return A.index(cfg).byId[tonumber(id) or -1]
end

function A.cost(cfg, node)
	return node and (cfg.costs[node.kind or "small"] or 1) or 0
end

-- ===================================================================== sets
-- a set {[key] = true} <-> "a,b,c" (sorted, so the stored text is stable)
function A.encodeSet(set)
	local list = {}
	for k, v in pairs(set or {}) do
		if v then
			list[#list + 1] = tostring(k)
		end
	end
	table.sort(list, function(a, b)
		local na, nb = tonumber(a), tonumber(b)
		if na and nb then
			return na < nb
		end
		return a < b
	end)
	return table.concat(list, ",")
end

-- numbers = true: keys become numbers (node ids)
function A.decodeSet(text, numbers)
	local set = {}
	if type(text) ~= "string" then
		return set
	end
	for part in text:gmatch("[^,%s]+") do
		local k = numbers and tonumber(part) or part
		if k then
			set[k] = true
		end
	end
	return set
end

local function count(set)
	local n = 0
	for _, v in pairs(set or {}) do
		if v then
			n = n + 1
		end
	end
	return n
end
A.count = count

-- ===================================================================== grid
-- every cell of the grid: {key, kind = "cell"|"flawless"|"swift"|"omen", theme (index), tier, omen (kind key), points}
-- rcfg = rift_config.lua (themes, omen.kinds). Cell keys: c<theme>.<tier>, f<tier>, s<tier>, o<kind>.
function A.cells(cfg, rcfg)
	local list = {}
	local P = cfg.points
	for ti = 1, #rcfg.themes do
		for tier = 1, cfg.tiers do
			list[#list + 1] = {key = "c" .. ti .. "." .. tier, kind = "cell", theme = ti, tier = tier, points = P.cell}
		end
	end
	for tier = 1, cfg.tiers do
		list[#list + 1] = {key = "f" .. tier, kind = "flawless", tier = tier, points = P.flawless}
	end
	for tier = 1, cfg.tiers do
		list[#list + 1] = {key = "s" .. tier, kind = "swift", tier = tier, points = P.swift}
	end
	for _, k in ipairs(rcfg.omen and rcfg.omen.kinds or {}) do
		list[#list + 1] = {key = "o" .. k.key, kind = "omen", omen = k.key, name = k.name, points = P.omen}
	end
	return list
end

function A.cellMap(cfg, rcfg)
	local map = {}
	for _, c in ipairs(A.cells(cfg, rcfg)) do
		map[c.key] = c
	end
	return map
end

function A.maxPoints(cfg, rcfg)
	local n = 0
	for _, c in ipairs(A.cells(cfg, rcfg)) do
		n = n + c.points
	end
	return n
end

function A.themeIndex(rcfg, name)
	for i, th in ipairs(rcfg.themes) do
		if th.name == name then
			return i
		end
	end
	return nil
end

-- points of the done cells (unknown keys count nothing)
function A.earned(cfg, rcfg, done)
	local map, n = A.cellMap(cfg, rcfg), 0
	for k, v in pairs(done or {}) do
		if v and map[k] then
			n = n + map[k].points
		end
	end
	return n
end

function A.spent(cfg, alloc)
	local n = 0
	for id, v in pairs(alloc or {}) do
		if v then
			n = n + A.cost(cfg, A.node(cfg, id))
		end
	end
	return n
end

-- the Swift time of a tier in seconds: a run of that tier sealed within it earns the tier's Swift cell. With the
-- generated layouts (rift_config.lua layout) and the density on, it is the rift model's clear time of the tier on its
-- size band's typical layout (ChaosRiftCore.clearSeconds: packs, guardian and the walk) for a solo player with
-- cfg.swiftDps times the model player's damage, rounded down to cfg.swiftRound seconds; so it grows with the map size
-- and the tier, and a strong player can earn it at every tier. A tier never gets less time than a lower tier: the
-- model's time falls inside a size band (the walk gets faster with the level), so each tier takes the most of its own
-- and every lower tier's time. Without them (or without rift_core.lua loaded):
-- cfg.swiftShare of rift_config.lua timeLimit (5:00). The run's own limit (Waning Veil, atlas time) does not matter.
function A.swiftSeconds(cfg, rcfg, tier)
	local R = ChaosRiftCore
	tier = floor(tonumber(tier) or 1)
	if cfg.swiftDps and R and R.clearSeconds and R.band and R.densityOn and R.band(rcfg, tier) and R.densityOn(rcfg) then
		local step = cfg.swiftRound or 1
		local best = 0
		for t = 1, tier do
			if R.band(rcfg, t) then
				best = math.max(best, floor(R.clearSeconds(rcfg, t, 1, cfg.swiftDps) / step) * step)
			end
		end
		return best
	end
	return floor(rcfg.timeLimit * cfg.swiftShare)
end

-- the Swift time of every tier of the grid: {[tier] = seconds}
function A.swiftTable(cfg, rcfg)
	local t = {}
	for tier = 1, cfg.tiers do
		t[tier] = A.swiftSeconds(cfg, rcfg, tier)
	end
	return t
end

-- the cells a sealed run earns. info = {theme = name, tier, omen = kind key or nil, deaths, secs}
function A.runCells(cfg, rcfg, info)
	local out = {}
	if info.omen then
		out[#out + 1] = "o" .. info.omen
		return out
	end
	local tier = floor(tonumber(info.tier) or 0)
	if tier < 1 or tier > cfg.tiers then
		return out
	end
	local ti = A.themeIndex(rcfg, info.theme)
	if ti then
		out[#out + 1] = "c" .. ti .. "." .. tier
	end
	if (tonumber(info.deaths) or 0) == 0 then
		out[#out + 1] = "f" .. tier
	end
	if info.secs and info.secs <= A.swiftSeconds(cfg, rcfg, tier) then
		out[#out + 1] = "s" .. tier
	end
	return out
end

-- adds the new cells to `done`; returns the list of new cell defs and the points they give
function A.credit(cfg, rcfg, done, keys)
	local map = A.cellMap(cfg, rcfg)
	local new, pts = {}, 0
	for _, k in ipairs(keys) do
		local c = map[k]
		if c and not done[k] then
			done[k] = true
			new[#new + 1] = c
			pts = pts + c.points
		end
	end
	return new, pts
end

-- "Abyssal Rift tier 4", "Flawless tier 4", "Swift tier 4", "Omen: Bloodmoon"
function A.cellName(rcfg, c)
	if c.kind == "cell" then
		return string.format("%s tier %d", rcfg.themes[c.theme].name, c.tier)
	elseif c.kind == "flawless" then
		return string.format("Flawless tier %d", c.tier)
	elseif c.kind == "swift" then
		return string.format("Swift tier %d", c.tier)
	end
	return "Omen: " .. tostring(c.name or c.omen)
end

-- ===================================================================== tree rules
local function keystones(cfg, alloc)
	local n = 0
	for id, v in pairs(alloc) do
		local node = v and A.node(cfg, id)
		if node and node.kind == "keystone" then
			n = n + 1
		end
	end
	return n
end
A.keystones = keystones

-- every allocated node reachable from the start through allocated nodes
function A.connected(cfg, alloc)
	local idx = A.index(cfg)
	local start = cfg.startId
	local seen, queue = {[start] = true}, {start}
	local i = 1
	while queue[i] do
		local id = queue[i]
		i = i + 1
		for other in pairs(idx.adj[id] or {}) do
			if alloc[other] and not seen[other] then
				seen[other] = true
				queue[#queue + 1] = other
			end
		end
	end
	for id, v in pairs(alloc) do
		if v and id ~= start and not seen[id] then
			return false
		end
	end
	return true
end

-- alloc = {[id] = true} WITHOUT the start (the start is always held). points = points available (earned - spent).
-- Returns true or false, reason.
function A.canAllocate(cfg, alloc, id, points)
	local node = A.node(cfg, id)
	if not node or node.kind == "start" then
		return false, "unknown"
	end
	id = node.id
	if alloc[id] then
		return false, "held"
	end
	if A.cost(cfg, node) > (points or 0) then
		return false, "points"
	end
	if node.kind == "keystone" and keystones(cfg, alloc) >= cfg.keystoneMax then
		return false, "keystone"
	end
	for other in pairs(A.index(cfg).adj[id]) do
		if other == cfg.startId or alloc[other] then
			return true
		end
	end
	return false, "path"
end

function A.canRefund(cfg, alloc, id)
	local node = A.node(cfg, id)
	if not node or not alloc[node.id] then
		return false, "not held"
	end
	alloc[node.id] = nil
	local ok = A.connected(cfg, alloc)
	alloc[node.id] = true
	if not ok then
		return false, "path"
	end
	return true
end

-- a loaded state made valid against the current config: unknown nodes dropped, at most keystoneMax keystones (the
-- first by id kept), only what stays connected, and no more than the points allow (the farthest nodes go first).
-- Returns the cleaned alloc and true when something changed.
function A.sanitize(cfg, rcfg, alloc, done)
	local clean, changed = {}, false
	local ids = {}
	for id, v in pairs(alloc or {}) do
		local node = v and A.node(cfg, id)
		if node and node.kind ~= "start" then
			ids[#ids + 1] = node.id
		elseif v then
			changed = true
		end
	end
	table.sort(ids)
	local ks = 0
	for _, id in ipairs(ids) do
		if A.node(cfg, id).kind == "keystone" then
			ks = ks + 1
			if ks > cfg.keystoneMax then
				changed = true
			else
				clean[id] = true
			end
		else
			clean[id] = true
		end
	end
	-- keep only what the start reaches
	local idx = A.index(cfg)
	local seen, order = {[cfg.startId] = true}, {}
	local queue, i = {cfg.startId}, 1
	while queue[i] do
		local id = queue[i]
		i = i + 1
		local nbrs = {}
		for other in pairs(idx.adj[id] or {}) do
			nbrs[#nbrs + 1] = other
		end
		table.sort(nbrs)
		for _, other in ipairs(nbrs) do
			if clean[other] and not seen[other] then
				seen[other] = true
				queue[#queue + 1] = other
				order[#order + 1] = other
			end
		end
	end
	local kept = {}
	for _, id in ipairs(order) do
		kept[id] = true
	end
	if count(kept) ~= count(clean) then
		changed = true
	end
	-- over budget: drop the nodes reached last (leaves of the walk) until it fits
	local budget = A.earned(cfg, rcfg, done)
	local k = #order
	while A.spent(cfg, kept) > budget and k > 0 do
		local id = order[k]
		k = k - 1
		if kept[id] then
			kept[id] = nil
			if not A.connected(cfg, kept) then
				kept[id] = true -- not a leaf now; try the one before
			else
				changed = true
			end
		end
	end
	if A.spent(cfg, kept) > budget then
		kept, changed = {}, true -- cannot happen with a connected tree, but never leave more spent than earned
	end
	return kept, changed
end

-- ===================================================================== effects
local KEYS = {"density", "elite", "time", "modReward", "goldMult", "keyChance", "keyUpgrade", "fragments", "chaos", "divine",
	"rolls", "goblin", "coffer", "lives", "betterMods"}
A.STATS = KEYS

-- the stat entries of an allocation (start included), in node order: {{stat, value, theme, minTier, node}}
function A.entries(cfg, alloc)
	local out = {}
	for _, n in ipairs(A.index(cfg).list) do
		if alloc[n.id] then
			for _, s in ipairs(n.stats or {}) do
				out[#out + 1] = {stat = s.stat, value = s.value, theme = s.theme, minTier = s.minTier, node = n.id}
			end
		end
	end
	return out
end

-- the flat modifiers of one run. ctx = {theme = name or nil, tier = number or nil, omen = kind or nil}.
-- A stat with a theme counts only in that theme; one with minTier only at that tier or higher (no tier: not at all).
-- themeWeights = {[theme] = percent} is always filled (rift_core.lua R.pickTheme picks the theme before the rest).
-- An omen arena gets nil: the atlas shapes rifts, not the guardian arenas.
function A.resolve(cfg, alloc, ctx)
	ctx = ctx or {}
	if ctx.omen then
		return nil
	end
	local am = {themeWeights = {}}
	for _, k in ipairs(KEYS) do
		am[k] = 0
	end
	for _, e in ipairs(A.entries(cfg, alloc or {})) do
		if e.stat == "themeWeight" then
			if e.theme then
				am.themeWeights[e.theme] = (am.themeWeights[e.theme] or 0) + e.value
			end
		elseif (not e.theme or e.theme == ctx.theme) and (not e.minTier or (ctx.tier and ctx.tier >= e.minTier)) then
			am[e.stat] = (am[e.stat] or 0) + e.value
		end
	end
	for k, cap in pairs(cfg.caps or {}) do
		if type(am[k]) == "number" and am[k] > cap then
			am[k] = cap
		end
	end
	for th, v in pairs(am.themeWeights) do
		am.themeWeights[th] = math.min(v, cfg.caps and cfg.caps.themeWeight or v)
	end
	am.betterMods = am.betterMods > 0
	-- the keystone (at most keystoneMax; their flags combine)
	for _, n in ipairs(A.index(cfg).list) do
		local ks = alloc and alloc[n.id] and n.keystone and cfg.keystones[n.keystone]
		if ks then
			am.keystone = n.name
			if ks.oneLife then
				am.oneLife = true
			end
			if ks.rewardMult then
				am.rewardMult = (am.rewardMult or 0) + ks.rewardMult
			end
			if ks.guardianMult then
				am.guardianMult = (am.guardianMult or 1) * ks.guardianMult
			end
			if ks.orbsMult then
				am.orbsMult = (am.orbsMult or 1) * ks.orbsMult
			end
			if ks.keyChanceMult then
				am.keyChanceMult = (am.keyChanceMult or 1) * ks.keyChanceMult
			end
			if ks.keyAscend then
				am.keyAscend = true
			end
			if ks.timeMult then
				am.timeMult = (am.timeMult or 1) * ks.timeMult
			end
			if ks.density then
				am.density = am.density + ks.density
			end
		end
	end
	return am
end

-- ===================================================================== text
local function num(v)
	if v == floor(v) then
		return tostring(floor(v))
	end
	return (string.format("%.2f", v):gsub("0+$", ""))
end
A.num = num

function A.statLine(cfg, s)
	local fmt = cfg.statText[s.stat] or (s.stat .. " %s")
	local text = fmt:find("%%s") and string.format(fmt, num(s.value)) or fmt
	if s.theme then
		text = text .. " in " .. s.theme
	end
	if s.minTier then
		text = text .. string.format(" (tier %d+)", s.minTier)
	end
	return text
end

function A.nodeLines(cfg, node)
	local lines = {}
	for _, s in ipairs(node.stats or {}) do
		lines[#lines + 1] = A.statLine(cfg, s)
	end
	if node.text then
		lines[#lines + 1] = node.text
	end
	return lines
end

-- summary of an allocation: one line per stat and theme (all themes first), then the keystone
function A.totals(cfg, alloc)
	local sums, order = {}, {}
	for _, e in ipairs(A.entries(cfg, alloc)) do
		local k = e.stat .. "|" .. (e.theme or "") .. "|" .. (e.minTier or "")
		if not sums[k] then
			sums[k] = {stat = e.stat, value = 0, theme = e.theme, minTier = e.minTier}
			order[#order + 1] = k
		end
		sums[k].value = sums[k].value + e.value
	end
	table.sort(order, function(a, b)
		local sa, sb = sums[a], sums[b]
		if (sa.theme ~= nil) ~= (sb.theme ~= nil) then
			return sa.theme == nil
		end
		return a < b
	end)
	local lines = {}
	for _, k in ipairs(order) do
		local s = sums[k]
		local cap = cfg.caps and cfg.caps[s.stat]
		if cap and s.stat ~= "themeWeight" and s.value > cap then
			s.value = cap
		end
		lines[#lines + 1] = A.statLine(cfg, s)
	end
	for _, n in ipairs(A.index(cfg).list) do
		if alloc[n.id] and n.kind == "keystone" then
			lines[#lines + 1] = n.name .. ": " .. tostring(n.text or "")
		end
	end
	return lines
end

-- ===================================================================== respec
function A.refundPrice(cfg, nodes)
	nodes = math.max(1, nodes or 1)
	local r = cfg.respec
	return {gold = r.gold * nodes, orbs = r.orbCount * nodes}
end

function A.resetPrice(cfg, alloc)
	local n = count(alloc)
	if n == 0 then
		return {gold = 0, orbs = 0}
	end
	local r = cfg.respec
	return {gold = floor(r.gold * n * r.resetShare), orbs = math.max(1, math.ceil(r.orbCount * n * r.resetShare))}
end

-- ===================================================================== payloads (game_riftatlas)
-- the tree (sent once per session, chunked): nodes {i, n, k, b, x, y, c, l, t, g}, branches, grid
function A.treePayload(cfg, rcfg)
	local nodes = {}
	for _, n in ipairs(A.index(cfg).list) do
		local links = {}
		for _, l in ipairs(n.links or {}) do
			links[#links + 1] = l
		end
		nodes[#nodes + 1] = {i = n.id, n = n.name, k = n.kind or "small", b = n.branch or "", x = n.x, y = n.y,
			c = A.cost(cfg, n), l = links, t = A.nodeLines(cfg, n), g = n.glyph or "density"}
	end
	local branches = {}
	for _, b in ipairs(cfg.branches) do
		branches[#branches + 1] = {k = b.key, n = b.name, th = b.theme, d = b.dir, c = b.color}
	end
	local themes = {}
	for _, th in ipairs(rcfg.themes) do
		themes[#themes + 1] = th.name
	end
	local omens = {}
	for _, k in ipairs(rcfg.omen and rcfg.omen.kinds or {}) do
		omens[#omens + 1] = {k = k.key, n = k.name, b = k.boss}
	end
	return {nodes = nodes, branches = branches, start = cfg.startId, keystoneMax = cfg.keystoneMax,
		grid = {themes = themes, tiers = cfg.tiers, omens = omens, points = cfg.points,
			swift = floor(rcfg.timeLimit * cfg.swiftShare), swiftTiers = A.swiftTable(cfg, rcfg)},
		max = A.maxPoints(cfg, rcfg)}
end

-- the state of one character
function A.statePayload(cfg, rcfg, st, msg)
	local alloc = {}
	for id, v in pairs(st.alloc) do
		if v then
			alloc[#alloc + 1] = id
		end
	end
	table.sort(alloc)
	local done = {}
	for k, v in pairs(st.done) do
		if v then
			done[#done + 1] = k
		end
	end
	table.sort(done)
	local earned, spent = A.earned(cfg, rcfg, st.done), A.spent(cfg, st.alloc)
	return {earned = earned, spent = spent, points = earned - spent, max = A.maxPoints(cfg, rcfg), alloc = alloc,
		done = done, refund = A.refundPrice(cfg, 1), reset = A.resetPrice(cfg, st.alloc), orb = cfg.respec.orbName,
		totals = A.totals(cfg, st.alloc), msg = msg}
end

-- ===================================================================== layout
-- problems of the map (empty list = fine): nodes closer than minDist, links passing within clearance of a node that is
-- not one of their ends, links to unknown nodes, nodes the start cannot reach
function A.layoutProblems(cfg, minDist, clearance)
	local idx = A.index(cfg)
	local out = {}
	local list = idx.list
	for i = 1, #list do
		for j = i + 1, #list do
			local a, b = list[i], list[j]
			local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
			if d < minDist then
				out[#out + 1] = string.format("nodes %d and %d are %.0f apart", a.id, b.id, d)
			end
		end
	end
	for _, n in ipairs(list) do
		for _, l in ipairs(n.links or {}) do
			local m = idx.byId[l]
			if not m then
				out[#out + 1] = string.format("node %d links unknown %s", n.id, tostring(l))
			elseif m.id == n.id then
				out[#out + 1] = string.format("node %d links itself", n.id)
			else
				local dx, dy = m.x - n.x, m.y - n.y
				local len2 = dx * dx + dy * dy
				for _, o in ipairs(list) do
					if o.id ~= n.id and o.id ~= m.id then
						local t = ((o.x - n.x) * dx + (o.y - n.y) * dy) / len2
						if t > 0 and t < 1 then
							local px, py = n.x + t * dx, n.y + t * dy
							local d = math.sqrt((o.x - px) ^ 2 + (o.y - py) ^ 2)
							if d < clearance then
								out[#out + 1] = string.format("link %d-%d passes %.0f from node %d", n.id, m.id, d, o.id)
							end
						end
					end
				end
			end
		end
	end
	-- reachability over all links
	local all = {}
	for _, n in ipairs(list) do
		all[n.id] = true
	end
	all[cfg.startId] = nil
	if not A.connected(cfg, all) then
		out[#out + 1] = "not every node is reachable from the start"
	end
	return out
end

return A
