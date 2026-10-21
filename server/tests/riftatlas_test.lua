-- Run from the server/ folder: luajit tests/riftatlas_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Rift Atlas (atlas_core.lua + atlas_config.lua): the node graph (size, every node reachable from the start, no orphan
-- or one-sided links, a layout without overlaps), the completion grid and its points, allocate / refund / sanitize,
-- the effects of an allocation, and their application in rift_core.lua (density, time, lives, boons, guardian,
-- reward bonuses, chest, fragments, next key, theme pick). Also the engine glue of atlas.lua against a mocked engine.
local cfg = dofile("data/scripts/chaos/atlas_config.lua")
local rcfg = dofile("data/scripts/chaos/rift_config.lua")
dofile("data/scripts/chaos/atlas_core.lua")
dofile("data/scripts/chaos/rift_core.lua")
local A = ChaosAtlasCore
local R = ChaosRiftCore

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

local function rng(seed)
	local s = seed
	return function(a, b)
		s = (s * 16807) % 2147483647
		return a + s % (b - a + 1)
	end
end

local function set(list)
	local s = {}
	for _, v in ipairs(list) do
		s[v] = true
	end
	return s
end

-- a full allocation path: every node on the way from the start to `id` (BFS parents)
local function pathTo(id)
	local idx = A.index(cfg)
	local parent, queue, i = {[cfg.startId] = false}, {cfg.startId}, 1
	while queue[i] do
		local cur = queue[i]
		i = i + 1
		local nbrs = {}
		for o in pairs(idx.adj[cur]) do
			nbrs[#nbrs + 1] = o
		end
		table.sort(nbrs)
		for _, o in ipairs(nbrs) do
			if parent[o] == nil then
				parent[o] = cur
				queue[#queue + 1] = o
			end
		end
	end
	local out = {}
	local cur = id
	while cur and cur ~= cfg.startId do
		out[#out + 1] = cur
		cur = parent[cur]
	end
	return out
end

-- ------------------------------------------------------------------ the graph
do
	local idx = A.index(cfg)
	local n, kinds = #idx.list, {}
	for _, node in ipairs(idx.list) do
		kinds[node.kind] = (kinds[node.kind] or 0) + 1
	end
	ok(n >= 60 and n <= 90, "60-90 nodes: " .. n)
	eq(kinds.start, 1, "one start")
	eq(kinds.keystone, 4, "four keystones")
	ok((kinds.notable or 0) >= 16, "notables: " .. tostring(kinds.notable))
	eq(idx.byId[cfg.startId].kind, "start", "start id")
	-- unique ids, known links, no self links; links symmetric in the index
	local seen = {}
	for _, node in ipairs(cfg.nodes) do
		ok(not seen[node.id], "unique id " .. node.id)
		seen[node.id] = true
		ok(node.name and node.name ~= "", "named " .. node.id)
		ok(cfg.costs[node.kind] ~= nil, "known kind " .. node.id)
		for _, l in ipairs(node.links) do
			ok(idx.byId[l] ~= nil, "link target exists " .. node.id .. "->" .. l)
			ok(l ~= node.id, "no self link " .. node.id)
		end
		for _, s in ipairs(node.stats) do
			ok(cfg.statText[s.stat] ~= nil, "stat has a text: " .. tostring(s.stat))
			ok(type(s.value) == "number" and s.value > 0, "stat value " .. node.id)
			if s.theme then
				ok(A.themeIndex(rcfg, s.theme) ~= nil, "stat theme is a rift theme: " .. s.theme)
			end
		end
		if node.kind == "keystone" then
			ok(cfg.keystones[node.keystone] ~= nil, "keystone effect " .. node.id)
			ok(node.text and #node.text > 20, "keystone text " .. node.id)
		end
		if node.kind ~= "start" then
			ok(next(idx.adj[node.id]) ~= nil, "no orphan node " .. node.id)
		end
	end
	for id, nb in pairs(idx.adj) do
		for o in pairs(nb) do
			ok(idx.adj[o][id], "symmetric link " .. id .. "-" .. o)
		end
	end
	-- each branch: 16 nodes, its keystone at the far end (a leaf), every theme branch matches a rift theme
	for _, b in ipairs(cfg.branches) do
		ok(A.themeIndex(rcfg, b.theme) ~= nil, "branch theme " .. b.key)
		local count = 0
		for _, node in ipairs(idx.list) do
			if node.branch == b.theme then
				count = count + 1
			end
		end
		eq(count, 16, "branch size " .. b.key)
	end
	for _, node in ipairs(idx.list) do
		if node.kind == "keystone" then
			local deg = 0
			for _ in pairs(idx.adj[node.id]) do
				deg = deg + 1
			end
			eq(deg, 1, "keystone is a leaf " .. node.id)
		end
	end
	-- layout: every node reachable, at least 60 apart, links clear of other nodes by 24
	local problems = A.layoutProblems(cfg, 60, 24)
	for _, p in ipairs(problems) do
		print("  layout: " .. p)
	end
	eq(#problems, 0, "layout problems")
	-- a broken copy is caught
	local bad = {nodes = {{id = 1, kind = "start", x = 0, y = 0, links = {}, stats = {}},
		{id = 2, x = 10, y = 0, links = {1}, stats = {}}, {id = 3, x = 200, y = 0, links = {9}, stats = {}},
		{id = 4, x = 100, y = 0, links = {}, stats = {}}, {id = 5, x = 300, y = 0, links = {2}, stats = {}}},
		startId = 1, costs = cfg.costs}
	local bp = A.layoutProblems(bad, 60, 24)
	local text = table.concat(bp, "|")
	ok(text:find("nodes 1 and 2"), "overlap caught")
	ok(text:find("unknown 9"), "orphan link caught")
	ok(text:find("reachable"), "unreachable caught")
	ok(text:find("passes"), "link through a node caught (2-5 over 4)")
end

-- ------------------------------------------------------------------ the grid
do
	local cells = A.cells(cfg, rcfg)
	eq(#cells, 4 * 15 + 15 + 15 + 3, "grid cells")
	eq(A.maxPoints(cfg, rcfg), 96, "96 points in all")
	-- costs: the whole tree costs more than the grid gives, but one keystone short of everything is about it
	local total, ksCost = 0, 0
	for _, node in ipairs(cfg.nodes) do
		total = total + A.cost(cfg, node)
		if node.kind == "keystone" then
			ksCost = ksCost + A.cost(cfg, node)
		end
	end
	eq(total, 108, "tree cost")
	ok(A.maxPoints(cfg, rcfg) < total - ksCost + cfg.costs.keystone, "a full grid cannot take everything")
	ok(A.maxPoints(cfg, rcfg) > 0.85 * (total - ksCost + cfg.costs.keystone), "but nearly")
	-- run cells
	local k = A.runCells(cfg, rcfg, {theme = "Ashen Crypt", tier = 4, deaths = 0, secs = 280})
	eq(table.concat(k, ","), "c3.4,f4,s4", "a fast flawless Ashen tier 4")
	k = A.runCells(cfg, rcfg, {theme = "Abyssal Rift", tier = 12, deaths = 2, secs = 361})
	eq(table.concat(k, ","), "c1.12", "deaths and slow: only the cell")
	k = A.runCells(cfg, rcfg, {theme = "Obsidian Hall", tier = 15, deaths = 0, secs = 465})
	eq(table.concat(k, ","), "c2.15,f15,s15", "exactly the tier's Swift time is swift")
	k = A.runCells(cfg, rcfg, {theme = "Obsidian Hall", tier = 15, deaths = 0, secs = 466})
	eq(table.concat(k, ","), "c2.15,f15", "a second over is not")
	k = A.runCells(cfg, rcfg, {theme = "Obsidian Hall", tier = 15, deaths = 0, secs = 420})
	eq(table.concat(k, ","), "c2.15,f15,s15", "tier 15 in 7:00: swift (was out of reach at 5:00)")
	k = A.runCells(cfg, rcfg, {theme = "Abyssal Rift", tier = 5, deaths = 0, secs = 330})
	eq(table.concat(k, ","), "c1.5,f5", "tier 5 in 5:30: not swift (5:15, the time of tier 1)")
	k = A.runCells(cfg, rcfg, {omen = "storm", tier = 15, deaths = 3, secs = 900})
	eq(table.concat(k, ","), "ostorm", "omen kill")
	eq(#A.runCells(cfg, rcfg, {theme = "Abyssal Rift", tier = 16, deaths = 0, secs = 1}), 0, "off the grid")
	-- the Swift times: the rift model's clear time of the tier on its band's typical map for a player with swiftDps x
	-- the model's damage, rounded down to swiftRound seconds (atlas_config.lua swiftDps / swiftRound)
	-- and never less than a lower tier's time (the model's own time falls inside a size band)
	local want = {315, 315, 315, 315, 315, 315, 315, 315, 315, 315, 330, 360, 390, 435, 465}
	local swiftT = A.swiftTable(cfg, rcfg)
	eq(#swiftT, 15, "a Swift time per tier")
	for tier = 1, 15 do
		local s = A.swiftSeconds(cfg, rcfg, tier)
		eq(s, want[tier], "swift seconds tier " .. tier)
		eq(swiftT[tier], s, "swift table tier " .. tier)
		eq(s % cfg.swiftRound, 0, "swift tier " .. tier .. " on whole steps")
		local strong = R.clearSeconds(rcfg, tier, 1, cfg.swiftDps)
		ok(strong < s + cfg.swiftRound, "swift tier " .. tier .. ": the strong player's model time or more")
		if tier > 1 then ok(s >= A.swiftSeconds(cfg, rcfg, tier - 1), "swift tier " .. tier .. ": not below tier " .. (tier - 1)) end
		-- a strong player can make it (well inside the limit), the model's typical player cannot
		local typical = R.clearSeconds(rcfg, tier, 1, 1)
		ok(s < typical, "swift tier " .. tier .. ": under the typical clear time")
		ok(R.clearSeconds(rcfg, tier, 1, 1.5) < s, "swift tier " .. tier .. ": a player with 1.5x the damage makes it")
		ok(s < 0.6 * R.timeLimit(rcfg, tier), "swift tier " .. tier .. ": well inside the run's limit")
		ok(s >= 0.25 * R.timeLimit(rcfg, tier), "swift tier " .. tier .. ": not a sprint")
		-- a party of five (the party model: 4.98 typical players) gets about the same time
		ok(math.abs(R.clearSeconds(rcfg, tier, 5, 4.98 * cfg.swiftDps) - strong) < 20, "swift tier " .. tier .. ": party")
	end
	ok(swiftT[15] > swiftT[11] and swiftT[11] > swiftT[10], "the big maps get more time")
	-- without the generated layouts, or without rift_core.lua: half of the base timeLimit (5:00), as before
	local flat = {}
	for key, v in pairs(rcfg) do flat[key] = v end
	flat.layout = {enabled = false, sizes = rcfg.layout.sizes}
	eq(A.swiftSeconds(cfg, flat, 15), 300, "no layouts: 5:00")
	local keep = R.clearSeconds
	R.clearSeconds = nil
	eq(A.swiftSeconds(cfg, rcfg, 15), 300, "no rift model: 5:00")
	eq(table.concat(A.runCells(cfg, rcfg, {theme = "Obsidian Hall", tier = 15, deaths = 0, secs = 301}), ","), "c2.15,f15",
		"no rift model: 5:01 is not swift")
	R.clearSeconds = keep
	-- Swift cells earned under the old 5:00 stay: sanitize and the points do not look at the times
	local old = A.decodeSet("c1.3,s15,s3")
	eq(A.earned(cfg, rcfg, old), 3, "earned swift cells count")
	local first
	for other in pairs(A.index(cfg).adj[cfg.startId]) do
		if A.cost(cfg, A.node(cfg, other)) == 1 and (not first or other < first) then first = other end
	end
	local kept = A.sanitize(cfg, rcfg, {[first] = true}, old)
	ok(kept[first], "a node bought with old swift points stays")
	ok(old.s3 and old.s15, "earned swift cells kept")
	eq(A.encodeSet(old), "c1.3,s15,s3", "the stored cells unchanged")
	-- credit only once
	local done = {}
	local new, pts = A.credit(cfg, rcfg, done, {"c3.4", "f4", "s4"})
	eq(#new, 3, "three new")
	eq(pts, 3, "three points")
	new, pts = A.credit(cfg, rcfg, done, {"c3.4", "f4", "s4", "ostorm", "bogus"})
	eq(#new, 1, "only the omen is new")
	eq(pts, 2, "omen worth 2")
	eq(A.earned(cfg, rcfg, done), 5, "earned")
	eq(A.cellName(rcfg, A.cellMap(cfg, rcfg)["c3.4"]), "Ashen Crypt tier 4", "cell name")
	eq(A.cellName(rcfg, A.cellMap(cfg, rcfg)["ostorm"]), "Omen: Stormcall", "omen name")
	-- encode / decode
	eq(A.encodeSet({[12] = true, [3] = true, [101] = true}), "3,12,101", "numeric sort")
	local back = A.decodeSet("3,12,101", true)
	ok(back[3] and back[12] and back[101], "decode ids")
	eq(A.encodeSet(A.decodeSet("s4,c3.4,f4")), "c3.4,f4,s4", "cells round trip")
	eq(next(A.decodeSet(nil)), nil, "nil decodes empty")
end

-- ------------------------------------------------------------------ allocate / refund / sanitize
do
	local alloc = {}
	eq(A.canAllocate(cfg, alloc, 2, 5), true, "next to the start")
	local okFar, why = A.canAllocate(cfg, alloc, 3, 5)
	eq(okFar, false, "not connected")
	eq(why, "path", "reason path")
	local okPts, whyPts = A.canAllocate(cfg, alloc, 2, 0)
	eq(whyPts, "points", "no points")
	eq(select(2, A.canAllocate(cfg, alloc, 1, 5)), "unknown", "start is not allocatable")
	eq(select(2, A.canAllocate(cfg, alloc, 9999, 5)), "unknown", "unknown id")
	alloc[2] = true
	eq(select(2, A.canAllocate(cfg, alloc, 2, 5)), "held", "held")
	ok(A.canAllocate(cfg, alloc, 3, 5), "chain")
	alloc[3] = true
	eq(select(2, A.canRefund(cfg, alloc, 2)), "path", "refund of a bridge refused")
	eq(A.canRefund(cfg, alloc, 3), true, "refund of a leaf")
	eq(alloc[3], true, "canRefund leaves the alloc unchanged")
	eq(select(2, A.canRefund(cfg, alloc, 5)), "not held", "refund of a node not held")
	-- 5 is linked to the start and to 2: still a leaf, and 2 stays a bridge for 3
	alloc[5] = true
	eq(A.canRefund(cfg, alloc, 5), true, "a ring node is a leaf")
	eq(select(2, A.canRefund(cfg, alloc, 2)), "path", "3 still hangs on 2")
	ok(not A.connected(cfg, {[3] = true, [5] = true}), "3 alone is not connected")
	-- a loop: 3 - 17 - 12 - 11 - 1 and 3 - 2 - 1; with both sides held, 2 is no longer a bridge
	local loop = {[2] = true, [3] = true, [17] = true, [12] = true, [11] = true}
	eq(A.canRefund(cfg, loop, 2), true, "a loop keeps 3 connected")
	-- keystone limit
	local ks1, ks2 = 116, 216
	local a1 = set(pathTo(ks1))
	ok(A.connected(cfg, a1), "path to the Abyssal keystone connected")
	local p2 = pathTo(ks2)
	for _, id in ipairs(p2) do
		if id ~= ks2 then
			a1[id] = true
		end
	end
	eq(select(2, A.canAllocate(cfg, a1, ks2, 99)), "keystone", "second keystone refused")
	-- sanitize: unknown ids, two keystones, a disconnected node, over budget
	local raw = {[2] = true, [3] = true, [4] = true, [9999] = true, [115] = true, [1] = true}
	local done = {}
	for _, c in ipairs(A.cells(cfg, rcfg)) do
		done[c.key] = true
	end
	local clean, changed = A.sanitize(cfg, rcfg, raw, done)
	ok(changed, "sanitize changed")
	ok(clean[2] and clean[3] and clean[4], "connected chain kept")
	ok(not clean[9999] and not clean[1], "unknown and start dropped")
	ok(not clean[115], "disconnected node dropped")
	local two = set(pathTo(ks1))
	for _, id in ipairs(pathTo(ks2)) do
		two[id] = true
	end
	local c2 = A.sanitize(cfg, rcfg, two, done)
	eq(A.keystones(cfg, c2), 1, "one keystone left")
	ok(c2[ks1] and not c2[ks2], "the lower id kept")
	ok(A.connected(cfg, c2), "still connected")
	-- budget: 5 points earned, a path costing more
	local small = {}
	A.credit(cfg, rcfg, small, {"c1.1", "c1.2", "c1.3", "c1.4", "c1.5"})
	local c3, ch3 = A.sanitize(cfg, rcfg, set(pathTo(ks1)), small)
	ok(ch3, "over budget changed")
	ok(A.spent(cfg, c3) <= 5, "within budget: " .. A.spent(cfg, c3))
	ok(A.connected(cfg, c3), "budget trim stays connected")
	local fine, chf = A.sanitize(cfg, rcfg, {[2] = true, [3] = true}, small)
	ok(not chf and fine[2] and fine[3], "a valid state is left alone")
	-- every single node is reachable with the points of a full grid (the whole graph is allocatable step by step)
	local all = {}
	local points = A.maxPoints(cfg, rcfg)
	local progress = true
	while progress do
		progress = false
		for _, n in ipairs(A.index(cfg).list) do
			if n.kind ~= "start" and n.kind ~= "keystone" and A.canAllocate(cfg, all, n.id, points - A.spent(cfg, all)) then
				all[n.id] = true
				progress = true
			end
		end
	end
	local smallNotables = 0
	for _, n in ipairs(A.index(cfg).list) do
		if n.kind ~= "start" and n.kind ~= "keystone" then
			smallNotables = smallNotables + 1
		end
	end
	eq(A.count(all), smallNotables, "a full grid buys every small node and notable")
	eq(select(2, A.canAllocate(cfg, all, ks1, points - A.spent(cfg, all))), "points", "but then no keystone: a choice")
	local withKs = set(pathTo(ks1))
	ok(A.spent(cfg, withKs) <= 20, "a keystone is reachable early: " .. A.spent(cfg, withKs))
	-- respec prices
	eq(A.refundPrice(cfg, 1).gold, 250000, "refund gold")
	eq(A.refundPrice(cfg, 1).orbs, 1, "refund orbs")
	eq(A.resetPrice(cfg, {[2] = true, [3] = true, [4] = true, [5] = true, [6] = true}).gold, 1000000, "reset 5 nodes x 250k x 0.8")
	eq(A.resetPrice(cfg, {}).gold, 0, "reset of nothing")
end

-- ------------------------------------------------------------------ effects
local function fullAtlas(ks)
	local all = {}
	for _, n in ipairs(A.index(cfg).list) do
		if n.kind ~= "start" and n.kind ~= "keystone" then
			all[n.id] = true
		end
	end
	if ks then
		all[ks] = true
	end
	return all
end

do
	eq(A.resolve(cfg, {}, {omen = "storm"}), nil, "no atlas in omen arenas")
	local am0 = A.resolve(cfg, {}, {theme = "Abyssal Rift", tier = 5})
	eq(am0.density, 0, "empty atlas: nothing")
	eq(am0.oneLife, nil, "empty atlas: no keystone")
	local am = A.resolve(cfg, {[2] = true, [3] = true}, {theme = "Obsidian Hall", tier = 1})
	eq(am.density, 6, "two density nodes")
	-- theme-specific: Abyssal gate + core path
	local path = set(pathTo(101))
	local inAbyss = A.resolve(cfg, path, {theme = "Abyssal Rift", tier = 3})
	local inHall = A.resolve(cfg, path, {theme = "Obsidian Hall", tier = 3})
	eq(inAbyss.density - inHall.density, 4, "the Abyssal gate counts only in Abyssal rifts")
	-- minTier: Second Wind (+1 life at tier 8+)
	local sw = set(pathTo(14))
	eq(A.resolve(cfg, sw, {theme = "Ashen Crypt", tier = 7}).lives, 0, "no life below tier 8")
	eq(A.resolve(cfg, sw, {theme = "Ashen Crypt", tier = 8}).lives, 1, "one life at tier 8")
	eq(A.resolve(cfg, sw, {theme = "Ashen Crypt"}).lives, 0, "no tier: no life")
	-- attunement weights always present
	local att = A.resolve(cfg, set(pathTo(102)), {})
	eq(att.themeWeights["Abyssal Rift"], 60, "attunement weight")
	-- caps on a full atlas
	for _, th in ipairs(rcfg.themes) do
		local full = A.resolve(cfg, fullAtlas(), {theme = th.name, tier = 15})
		for k, cap in pairs(cfg.caps) do
			if type(full[k]) == "number" then
				ok(full[k] <= cap, "cap " .. k .. " in " .. th.name .. ": " .. full[k])
			end
		end
		ok(full.density > 0 and full.time > 0 and full.modReward > 0, "a full atlas does something in " .. th.name)
		eq(full.lives, 2, "two lives at tier 15 in " .. th.name .. " (Ashen: capped)")
	end
	-- keystones
	local lone = A.resolve(cfg, fullAtlas(116), {theme = "Abyssal Rift", tier = 10})
	ok(lone.oneLife, "Lone Ember: one life")
	eq(lone.rewardMult, 60, "Lone Ember: +60%")
	eq(lone.keystone, "Lone Ember", "keystone name")
	local crown = A.resolve(cfg, fullAtlas(216), {theme = "Obsidian Hall", tier = 10})
	eq(crown.guardianMult, 2, "Obsidian Crown guardian")
	eq(crown.orbsMult, 1.5, "Obsidian Crown orbs")
	local ascent = A.resolve(cfg, fullAtlas(316), {theme = "Ashen Crypt", tier = 10})
	eq(ascent.keyChanceMult, 0.5, "Ashen Ascent halves")
	ok(ascent.keyAscend, "Ashen Ascent ascends")
	local fleet = A.resolve(cfg, fullAtlas(416), {theme = "Forsaken Sanctum", tier = 10})
	eq(fleet.timeMult, 0.65, "Fleeting Sanctum time")
	eq(fleet.density, A.resolve(cfg, fullAtlas(), {theme = "Forsaken Sanctum", tier = 10}).density + 40,
		"Fleeting Sanctum density on top of the cap")
	-- text
	eq(A.statLine(cfg, {stat = "density", value = 4, theme = "Abyssal Rift"}), "+4% monster packs in Abyssal Rift", "stat line")
	eq(A.statLine(cfg, {stat = "lives", value = 1, minTier = 8}), "+1 shared lives (tier 8+)", "min tier line")
	eq(A.statLine(cfg, {stat = "chaos", value = 0.25}), "+0.25 Orbs of Upheaval per chest", "fraction")
	eq(A.num(0.5), "0.5", "num half")
	local lines = A.totals(cfg, fullAtlas(116))
	ok(#lines > 10, "totals lines")
	ok(lines[#lines]:find("^Lone Ember"), "keystone last in the totals")
end

-- ------------------------------------------------------------------ in rift_core
do
	local tier = 10
	local types = {{name = "A", level = 600}, {name = "B", level = 650}, {name = "C", level = 700}}
	local rooms = {"east", "north", "west"}
	-- no atlas: identical to before (same rand sequence)
	local fx0 = R.effects(rcfg, {}, tier)
	local fx0b = R.applyAtlasFx(R.effects(rcfg, {}, tier), nil)
	local p0 = R.plan(rcfg, tier, fx0, 1, types, rooms, rng(5))
	local p0b = R.plan(rcfg, tier, fx0b, 1, types, rooms, rng(5))
	eq(p0.total, p0b.total, "no atlas: same plan")
	eq(R.startLives(rcfg, 1, fx0b), 3, "no atlas: 3 lives")
	eq(R.newRun(rcfg, 0, 10, 8, fx0b).limit, rcfg.timeLimit, "no atlas: same limit")
	eq(R.pickTheme(rcfg, rng(3), nil).name, rcfg.themes[rng(3)(1, #rcfg.themes)].name, "no weights: one rand as before")
	-- a full atlas in an Abyssal tier 10
	local am = A.resolve(cfg, fullAtlas(), {theme = "Abyssal Rift", tier = tier})
	local fx = R.applyAtlasFx(R.effects(rcfg, {}, tier), am)
	ok(math.abs(fx.packMult - (1 + am.density / 100)) < 1e-9, "packs x density")
	local packs0 = #p0.packs
	local p1 = R.plan(rcfg, tier, fx, 1, types, rooms, rng(5))
	ok(#p1.packs > packs0, "more packs: " .. #p1.packs .. " > " .. packs0)
	eq(R.newRun(rcfg, 0, 10, 8, fx).limit, math.floor(rcfg.timeLimit * (1 + am.time / 100) + 0.5), "longer time")
	eq(R.startLives(rcfg, 1, fx), 3 + am.lives, "atlas lives")
	ok(fx.elite > 1, "more elites in the Abyss")
	-- Lone Ember: one life, whatever the party
	local fxL = R.applyAtlasFx(R.effects(rcfg, {}, tier), A.resolve(cfg, fullAtlas(116), {theme = "Abyssal Rift", tier = tier}))
	eq(R.startLives(rcfg, 4, fxL), 1, "Lone Ember: one life for four")
	-- Fleeting Sanctum: shorter, denser
	local amF = A.resolve(cfg, fullAtlas(416), {theme = "Forsaken Sanctum", tier = tier})
	local fxF = R.applyAtlasFx(R.effects(rcfg, {}, tier), amF)
	ok(R.newRun(rcfg, 0, 10, 8, fxF).limit < rcfg.timeLimit, "Fleeting Sanctum shortens the run despite the time nodes")
	-- Sanctum boons without the modifiers: goblin and coffer chances
	ok(fxF.gilded > 0 and fxF.coffer > 0, "Sanctum goblin and coffer chances")
	local goblins, coffers = 0, 0
	for s = 1, 300 do
		local p = R.plan(rcfg, tier, fxF, 1, types, rooms, rng(s))
		goblins = goblins + (p.gildedAt and 1 or 0)
		coffers = coffers + (p.coffer and 1 or 0)
	end
	ok(goblins > 300 * fxF.gilded / 100 * 0.7 and goblins < 300 * fxF.gilded / 100 * 1.3, "goblin rate ~ " .. fxF.gilded .. "%: " .. goblins)
	ok(coffers > 0, "coffers appear: " .. coffers)
	-- Obsidian Crown: guardian x2
	local amC = A.resolve(cfg, fullAtlas(216), {theme = "Obsidian Hall", tier = tier})
	local fxC = R.applyAtlasFx(R.effects(rcfg, {}, tier), amC)
	ok(math.abs(R.guardianHealthMult(rcfg, fxC, 1) - 2 * R.guardianHealthMult(rcfg, R.effects(rcfg, {}, tier), 1)) < 1e-9,
		"Obsidian Crown doubles the guardian")
	-- reward bonuses x modReward
	local mods = {{key = "vitality", value = 60}, {key = "reflection", value = 15}}
	local b0 = R.bonuses(rcfg, mods, tier)
	local b1 = R.atlasBonus(R.bonuses(rcfg, mods, tier), am)
	eq(b1.quantity, math.floor(b0.quantity * (1 + am.modReward / 100) + 0.5), "modifier bonus raised")
	local b2 = R.atlasBonus(R.bonuses(rcfg, mods, tier), nil)
	eq(b2.quantity, b0.quantity, "no atlas: bonus unchanged")
	-- the chest: own (gold, orbs, rolls) and the run's keystone
	local base = R.reward(rcfg, tier, {quantity = 0}, rng(9))
	local same = R.atlasReward(rcfg, R.reward(rcfg, tier, {quantity = 0}, rng(9)), nil, nil, rng(1))
	eq(same.gold, base.gold, "no atlas: same chest")
	eq(same.chaos, base.chaos, "no atlas: same orbs")
	local amHall = A.resolve(cfg, fullAtlas(), {theme = "Obsidian Hall", tier = tier})
	local own = R.atlasReward(rcfg, R.reward(rcfg, tier, {quantity = 0}, rng(9)), amHall, nil, rng(1))
	eq(own.gold, math.floor(base.gold * (1 + amHall.goldMult / 100)), "gold bonus")
	ok(own.chaos >= base.chaos + math.floor(amHall.chaos), "more Orbs of Upheaval in the Hall")
	local lone = A.resolve(cfg, fullAtlas(116), {theme = "Abyssal Rift", tier = tier})
	local shared = R.atlasReward(rcfg, R.reward(rcfg, tier, {quantity = 0}, rng(9)), nil, lone, rng(1))
	eq(shared.gold, math.floor(base.gold * 1.6), "Lone Ember +60% gold for every finisher")
	eq(shared.chaos, base.chaos, "Lone Ember leaves the Orbs of Upheaval alone")
	eq(shared.divine, base.divine, "Lone Ember leaves the Orbs of Fate alone")
	ok(shared.rolls >= math.floor(base.rolls * 1.6), "Lone Ember +60% item rolls")
	local gm = R.atlasReward(rcfg, R.reward(rcfg, tier, {quantity = 0}, rng(9)), {goldMult = 25}, nil, rng(1))
	ok(gm.chaos == base.chaos and gm.divine == base.divine, "goldMult leaves the orbs alone")
	local sumC, sumC2 = 0, 0
	for s = 1, 400 do
		sumC = sumC + R.atlasReward(rcfg, R.reward(rcfg, tier, {quantity = 0}, rng(s)), nil, nil, rng(s)).chaos
		sumC2 = sumC2 + R.atlasReward(rcfg, R.reward(rcfg, tier, {quantity = 0}, rng(s)), nil, amC, rng(s)).chaos
	end
	ok(sumC2 > 1.35 * sumC and sumC2 < 1.65 * sumC, "Obsidian Crown +50% orbs: " .. sumC .. " -> " .. sumC2)
	-- fragments
	eq(R.atlasFragments(10, nil, rng(1)), 10, "no atlas: same fragments")
	local fr = 0
	for s = 1, 200 do
		fr = fr + R.atlasFragments(10, {fragments = 25}, rng(s))
	end
	ok(fr > 200 * 12 and fr < 200 * 13, "+25% fragments: " .. fr / 200)
	-- next key: chance and upgrade
	local o0 = R.keyOdds(rcfg, 1)
	local o1 = R.keyOdds(rcfg, 1, {keyChance = 10, keyUpgrade = 20})
	eq(o1.chance, o0.chance + 10, "key chance +10")
	eq(o1.nextTier, math.min(100, o0.nextTier + 20), "upgrade +20")
	eq(R.keyOdds(rcfg, 3, {keyChance = 10}).chance, rcfg.keyDrop.max + 10, "the cap moves with it")
	local oa = R.keyOdds(rcfg, 1, {keyChanceMult = 0.5, keyAscend = true})
	eq(oa.chance, o0.chance * 0.5, "Ashen Ascent halves")
	eq(oa.nextTier, 100, "Ashen Ascent: always a tier up")
	local ups, drops = 0, 0
	for s = 1, 500 do
		local k = R.rollKeyDrop(rcfg, 5, 1, rng(s), {keyChanceMult = 0.5, keyAscend = true})
		if k then
			drops = drops + 1
			if k.tier == 6 then
				ups = ups + 1
			end
		end
	end
	eq(ups, drops, "every ascended key is tier + 1")
	ok(drops > 500 * o0.chance / 100 * 0.35 and drops < 500 * o0.chance / 100 * 0.65, "half the drops: " .. drops)
	local kmax = R.rollKeyDrop(rcfg, rcfg.maxTier, 3, rng(4), {keyChance = 100, keyAscend = true})
	eq(kmax and kmax.tier, rcfg.maxTier, "no tier past the top")
	-- the same rand sequence without an atlas
	local plain = R.rollKeyDrop(rcfg, 5, 2, rng(77))
	local plainNil = R.rollKeyDrop(rcfg, 5, 2, rng(77), nil)
	eq(plain and plain.tier, plainNil and plainNil.tier, "no atlas: same key")
	-- theme pick: attunement weighs, unattuned themes still come up
	local counts = {}
	local r = rng(11)
	for _ = 1, 4000 do
		local th = R.pickTheme(rcfg, r, {["Ashen Crypt"] = 100})
		counts[th.name] = (counts[th.name] or 0) + 1
	end
	ok(counts["Ashen Crypt"] > 1400 and counts["Ashen Crypt"] < 1800, "attuned theme ~40%: " .. counts["Ashen Crypt"])
	ok((counts["Abyssal Rift"] or 0) > 600, "others still open")
	-- the HUD note
	eq(R.atlasNote(nil), nil, "no note")
	ok(R.atlasNote(lone):find("^Atlas: Lone Ember"), "note names the keystone")
end

-- ------------------------------------------------------------------ hooks through R.atlasMods (no engine)
do
	R.hooks.atlasMods = function(player, ctx)
		return A.resolve(cfg, player.alloc, ctx)
	end
	local p = {alloc = {[2] = true, [3] = true}}
	eq(R.atlasMods(p, {theme = "Abyssal Rift", tier = 1}).density, 6, "hook resolves")
	eq(R.atlasMods(nil, {}), nil, "no player")
	R.hooks.atlasMods = function()
		error("boom")
	end
	eq(R.atlasMods(p, {}), nil, "a failing hook is ignored")
	local got
	R.hooks.onSealed = function(info)
		got = info
	end
	R.atlasSealed({tier = 3})
	eq(got and got.tier, 3, "sealed hook")
	R.hooks.atlasMods, R.hooks.onSealed = nil, nil
	eq(R.atlasMods(p, {}), nil, "no hook: nil")
end

-- ------------------------------------------------------------------ payloads
do
	local tree = A.treePayload(cfg, rcfg)
	eq(#tree.nodes, #cfg.nodes, "every node sent")
	eq(#tree.grid.themes, 4, "four themes")
	eq(#tree.grid.omens, 3, "three omens")
	eq(tree.grid.swift, 300, "swift seconds of an older client (the base 5:00)")
	eq(#tree.grid.swiftTiers, 15, "swift seconds per tier")
	eq(tree.grid.swiftTiers[1], 315, "swift tier 1"); eq(tree.grid.swiftTiers[15], 465, "swift tier 15")
	eq(tree.max, 96, "max points")
	local st = {alloc = {[2] = true}, done = {["c1.1"] = true, ["f1"] = true}}
	local sp = A.statePayload(cfg, rcfg, st, "hi")
	eq(sp.earned, 2, "state earned")
	eq(sp.spent, 1, "state spent")
	eq(sp.points, 1, "state points")
	eq(sp.alloc[1], 2, "state alloc")
	eq(sp.done[1], "c1.1", "state done sorted")
	eq(sp.msg, "hi", "state message")
end

-- ------------------------------------------------------------------ atlas.lua against a mocked engine
do
	local rows = {} -- player_id -> {done, nodes}
	local sent = {}
	local events = {}
	_G.db = {
		query = function(q)
			local id, done, nodes = q:match("VALUES %((%d+), '([^']*)', '([^']*)'")
			if id then
				rows[tonumber(id)] = {done = done, nodes = nodes}
			end
			return true
		end,
		storeQuery = function(q)
			local id = tonumber(q:match("`player_id` = (%d+)"))
			if id and rows[id] then
				return id
			end
			return false
		end,
		escapeString = function(s)
			return "'" .. s .. "'"
		end
	}
	_G.result = {
		getString = function(rid, col)
			return rows[rid][col == "done" and "done" or "nodes"]
		end,
		free = function() end
	}
	_G.json = {encode = function(t)
		return t
	end}
	local players = {}
	local function mkPlayer(guid, cid)
		local p = {guid = guid, cid = cid, gold = 1000000, orbs = 3, msgs = {}}
		function p:getGuid() return self.guid end
		function p:getId() return self.cid end
		function p:getItemCount() return self.orbs end
		function p:removeItem(_, n) self.orbs = self.orbs - n return true end
		function p:removeTotalMoney(n)
			if self.gold < n then
				return false
			end
			self.gold = self.gold - n
			return true
		end
		function p:getMoney() return self.gold end
		p.removeMoney = p.removeTotalMoney
		function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
		function p:registerEvent() end
		function p:getGroup() return {getAccess = function() return true end, getId = function() return self.group or 5 end} end
		players[cid] = p
		return p
	end
	_G.Player = function(cid)
		return players[cid]
	end
	_G.MESSAGE_EVENT_ADVANCE, _G.MESSAGE_INFO_DESCR = 1, 2
	local function eventCtor()
		local ev = {}
		function ev.type() end
		function ev.register() end
		function ev.separator() end
		return ev
	end
	_G.CreatureEvent = function(name)
		local ev = eventCtor()
		events[name] = ev
		return ev
	end
	_G.TalkAction = function(name)
		local ev = eventCtor()
		events[name] = ev
		return ev
	end
	dofile("data/lib/chaos_pay.lua")
	_G.Chaos = {
		pay = function(player, n, quiet) return ChaosPay.pay(player, n, quiet) end, -- chaos_constants.lua Chaos.pay
		-- chaos_constants.lua Chaos.staffCommand: value needs group 5
		staffCommand = function(player, words, param, economy)
			local g = player:getGroup()
			return g.getAccess() and (not economy or g.getId() >= 5), g.getAccess()
		end,
		send = function(player, op, action, data)
			sent[#sent + 1] = {p = player, op = op, action = action, data = data}
		end,
		sendChunked = function(player, op, payload)
			sent[#sent + 1] = {p = player, op = op, action = payload.action, data = payload.data}
		end,
		decode = function(b)
			return b
		end,
		toInt = function(v, lo, hi)
			v = tonumber(v)
			if not v or v < lo or v > hi then
				return nil
			end
			return math.floor(v)
		end,
		tables = {riftAtlas = "chaos_rift_atlas"}
	}
	_G.ChaosOpcodes = {riftAtlas = 210}
	_G.ChaosRiftConfig = rcfg
	_G.ChaosAtlasConfig = cfg
	dofile("data/scripts/chaos/atlas.lua")
	local S = ChaosAtlas
	local p = mkPlayer(500, 9001)
	events.ChaosAtlasLogin.onLogin(p)
	local function last()
		return sent[#sent]
	end
	events.ChaosAtlasExtended.onExtendedOpcode(p, 210, {action = "open"})
	eq(sent[#sent - 1].action, "tree", "tree first")
	eq(last().action, "state", "then the state")
	eq(last().data.points, 0, "no points yet")
	-- a sealed fast flawless rift credits the online finisher and an offline one
	R.hooks.onSealed({theme = "Abyssal Rift", tier = 2, deaths = 0, secs = 200, guids = {500, 777}})
	eq(last().action, "state", "state pushed after the credit")
	eq(last().data.earned, 3, "three cells")
	ok(p.msgs[1] and p.msgs[1]:find("Abyssal Rift tier 2"), "message names the cell")
	ok(rows[777] and rows[777].done == "c1.2,f2,s2", "offline finisher written: " .. tostring(rows[777] and rows[777].done))
	-- the same again: nothing new
	local before = #sent
	R.hooks.onSealed({theme = "Abyssal Rift", tier = 2, deaths = 0, secs = 200, guids = {500}})
	eq(#sent, before, "no second credit")
	-- allocate 2, 3; refuse 4 without points? 3 points: 2, 3, 4 fit
	events.ChaosAtlasExtended.onExtendedOpcode(p, 210, {action = "alloc", data = {id = 2}})
	eq(last().data.points, 2, "allocated one")
	events.ChaosAtlasExtended.onExtendedOpcode(p, 210, {action = "alloc", data = {id = 115}})
	ok(last().data.msg and last().data.msg:find("not connected"), "far node refused")
	events.ChaosAtlasExtended.onExtendedOpcode(p, 210, {action = "alloc", data = {id = 3}})
	events.ChaosAtlasExtended.onExtendedOpcode(p, 210, {action = "alloc", data = {id = 4}})
	eq(last().data.points, 0, "all spent")
	events.ChaosAtlasExtended.onExtendedOpcode(p, 210, {action = "alloc", data = {id = 5}})
	ok(last().data.msg and last().data.msg:find("Not enough"), "no points left")
	eq(rows[500].nodes, "2,3,4", "saved")
	-- the hook sees the allocation
	local am = R.atlasMods(p, {theme = "Abyssal Rift", tier = 2})
	eq(am.density, 6, "hook through atlas.lua")
	-- refund: a bridge refused, a leaf with gold, then with an orb
	events.ChaosAtlasExtended.onExtendedOpcode(p, 210, {action = "refund", data = {id = 2, pay = "gold"}})
	ok(last().data.msg:find("depend"), "bridge refused")
	events.ChaosAtlasExtended.onExtendedOpcode(p, 210, {action = "refund", data = {id = 4, pay = "gold"}})
	eq(p.gold, 750000, "250k paid")
	eq(rows[500].nodes, "2,3", "refund saved")
	events.ChaosAtlasExtended.onExtendedOpcode(p, 210, {action = "refund", data = {id = 3, pay = "orb"}})
	eq(p.orbs, 2, "an orb paid")
	p.gold = 10
	events.ChaosAtlasExtended.onExtendedOpcode(p, 210, {action = "refund", data = {id = 2, pay = "gold"}})
	ok(last().data.msg:find("gold"), "not enough gold")
	eq(rows[500].nodes, "2", "nothing refunded without payment")
	events.ChaosAtlasExtended.onExtendedOpcode(p, 210, {action = "reset", data = {pay = "orb"}})
	eq(rows[500].nodes, "", "reset")
	eq(p.orbs, 1, "reset of one node: one orb")
	-- logout clears the cache; a relog loads from the database
	events.ChaosAtlasLogout.onLogout(p)
	eq(S.state[500], nil, "cache cleared")
	events.ChaosAtlasLogin.onLogin(p)
	eq(A.earned(cfg, rcfg, S.state[500].done), 3, "loaded again")
	-- the offline finisher logs in: the credit is there
	local q = mkPlayer(777, 9002)
	events.ChaosAtlasLogin.onLogin(q)
	eq(A.earned(cfg, rcfg, S.state[777].done), 3, "offline credit kept")
	-- omen arenas credit their cell, and nothing else
	R.hooks.onSealed({omen = "bloodmoon", tier = 15, deaths = 1, secs = 500, guids = {777}})
	eq(A.earned(cfg, rcfg, S.state[777].done), 5, "omen +2")
	-- staff grant: an administrator only (a gamemaster, group 4, is refused)
	q.group = 4
	events["/atlas"].onSay(q, "/atlas", "grant all")
	eq(A.earned(cfg, rcfg, S.state[777].done), 5, "a gamemaster cannot grant cells")
	q.group = 5
	events["/atlas"].onSay(q, "/atlas", "grant all")
	eq(A.earned(cfg, rcfg, S.state[777].done), 96, "grant all")
	R.hooks.atlasMods, R.hooks.onSealed = nil, nil
end

print(string.format("riftatlas_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
