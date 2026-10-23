-- Run from the server/ folder: luajit tests/waystone_atlas_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Waystone Atlas (waystone_atlas_core.lua + waystone_atlas_config.lua): the node graph (the Rift Atlas's rules), the
-- grid (map x tier, Rare per tier) and its points, the effects of an allocation on a run (band, keystones, caps), the
-- drop helpers and the payloads; then waystone_atlas.lua against a mocked engine (open, credit on a boss's death,
-- allocate / refund / reset, the opener's atlas on a run) and its hooks in waystone_mods.lua / waystone_tiers.lua.
local cfg = dofile("data/scripts/chaos/waystone_atlas_config.lua")
local tcfg = dofile("data/scripts/chaos/waystone_tiers_config.lua")
dofile("data/scripts/chaos/waystone_atlas_core.lua")
local A = ChaosAtlasCore
local WC = ChaosWaystoneAtlasCore

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
local function set(list)
	local s = {}
	for _, v in ipairs(list) do
		s[v] = true
	end
	return s
end

-- the nodes on the way from the start to `id` (BFS parents)
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
	local out, cur = {}, id
	while cur and cur ~= cfg.startId do
		out[#out + 1] = cur
		cur = parent[cur]
	end
	return out
end

-- ------------------------------------------------------------------ the graph
do
	local idx = A.index(cfg)
	local kinds, total = {}, 0
	for _, n in ipairs(idx.list) do
		kinds[n.kind] = (kinds[n.kind] or 0) + 1
		total = total + A.cost(cfg, n)
		for _, s in ipairs(n.stats or {}) do
			ok(cfg.statText[s.stat] ~= nil, "node " .. n.id .. ": known stat " .. tostring(s.stat))
			ok(s.theme == nil or s.theme == cfg.bandThemes[1] or s.theme == cfg.bandThemes[2] or s.theme == cfg.bandThemes[3],
				"node " .. n.id .. ": a band theme")
		end
		if n.kind == "keystone" then
			ok(cfg.keystones[n.keystone] ~= nil, "keystone " .. n.name .. " defined")
		end
	end
	eq(#idx.list, 81, "81 nodes")
	eq(kinds.keystone, 4, "four keystones")
	eq(total, 108, "the tree costs 108")
	eq(#A.layoutProblems(cfg, 60, 20), 0, "layout clean")
	local all = {}
	for _, n in ipairs(idx.list) do
		if n.kind ~= "start" then
			all[n.id] = true
		end
	end
	ok(A.connected(cfg, all), "every node reachable")
end

-- ------------------------------------------------------------------ the grid
do
	local cells = WC.cells(cfg, tcfg)
	eq(#cells, 75, "60 map cells + 15 Rare")
	eq(WC.maxPoints(cfg, tcfg), 75, "75 points")
	ok(WC.maxPoints(cfg, tcfg) < 108, "the tree cannot be filled")
	local bm = WC.bandMaps(tcfg)
	eq(#bm[1], 4, "four low maps")
	eq(bm[1][1], 1, "low: maps 1-4")
	eq(bm[3][4], 12, "high: maps 9-12")
	eq(WC.bandOfMap(tcfg, 6), 2, "map 6 is middle")
	local map = WC.cellMap(cfg, tcfg)
	ok(map["m1.1"] and map["m4.5"] and map["m9.15"], "band cells exist")
	eq(map["m1.6"], nil, "a low map has no middle tier")
	eq(map["m12.10"], nil, "a high map has no tier X")
	eq(WC.cellName(cfg, map["m3.4"]), "Ashen Plain, Tier IV", "cell name")
	eq(WC.cellName(cfg, map["r12"]), "Rare, Tier XII", "rare name")
	local keys = WC.runCells(cfg, tcfg, {map = 3, tier = 4, rare = true})
	eq(#keys, 2, "a Rare run: map cell + Rare")
	eq(#WC.runCells(cfg, tcfg, {map = 3, tier = 9}), 0, "a tier outside the map's band earns nothing")
	eq(#WC.runCells(cfg, tcfg, {map = 3, tier = 0}), 0, "no tier")
	local done = {}
	local new, pts = WC.credit(cfg, tcfg, done, keys)
	eq(#new, 2, "two new")
	eq(pts, 2, "two points")
	new = WC.credit(cfg, tcfg, done, keys)
	eq(#new, 0, "only once")
	eq(WC.earned(cfg, tcfg, {["m3.4"] = true, junk = true, r4 = true}), 2, "unknown keys count nothing")
	-- sanitize against the waystone grid's points
	local alloc = set(pathTo(116))
	local clean, changed = WC.sanitize(cfg, tcfg, alloc, {["m1.1"] = true, ["m1.2"] = true})
	ok(changed, "over budget: trimmed")
	ok(A.spent(cfg, clean) <= 2, "within 2 points")
	ok(A.connected(cfg, clean), "still connected")
	-- the client's rows
	local rows = WC.gridRows(cfg, tcfg)
	eq(#rows, 5, "four map rows and Rare")
	eq(#rows[1].cells, 15, "a map row: 15 cells")
	eq(rows[1].cells[6].c, 6, "cells keep their tier's column")
	eq(rows[2].cells[1].n, "Ember Cave, Tier I", "row 2 starts with map 2")
	eq(rows[2].cells[6].n, "Gloom Cave, Tier VI", "and holds the band's second map")
	eq(#rows[5].cells, 15, "Rare row")
end

-- ------------------------------------------------------------------ effects
do
	local LOW, MID = cfg.bandThemes[1], cfg.bandThemes[2]
	local none = WC.resolve(cfg, {}, {theme = LOW, mods = 0})
	eq(none.quantity, 0, "empty: no quantity")
	eq(none.modRewardMult, 1, "empty: x1")
	-- the north gate (quantity in Low Maps) counts only in low maps
	local alloc = set(pathTo(101))
	local lo = WC.resolve(cfg, alloc, {theme = LOW, mods = 0})
	local mi = WC.resolve(cfg, alloc, {theme = MID, mods = 0})
	eq(lo.quantity - mi.quantity, 4, "Lowland Path +4% in low maps only")
	-- caps
	local every = {}
	for _, n in ipairs(A.index(cfg).list) do
		if n.kind ~= "start" and n.kind ~= "keystone" then
			every[n.id] = true
		end
	end
	local full = WC.resolve(cfg, every, {theme = LOW, mods = 3})
	for k, cap in pairs(cfg.caps) do
		ok(full[k] <= cap, k .. " capped at " .. cap)
	end
	eq(full.quantity, 20, "quantity at its cap with everything")
	-- keystones
	local function with(ks)
		local a = set(pathTo(ks))
		for id in pairs(every) do
			a[id] = true
		end
		a[ks] = true
		return a
	end
	local pure = WC.resolve(cfg, with(116), {theme = LOW, mods = 0})
	eq(pure.keystone, "Pure Stone", "keystone name")
	eq(pure.quantity, 60, "Pure Stone: +40% on a Normal waystone")
	eq(pure.modRewardMult, 1.25 * 0.5, "and halved modifier rewards")
	eq(WC.resolve(cfg, with(116), {theme = LOW, mods = 2}).quantity, 20, "not with modifiers")
	local vow = WC.resolve(cfg, with(216), {theme = MID, mods = 1})
	eq(vow.bossExtraFlat, 2, "Hunter's Vow: two more")
	eq(vow.dropLoss, 50, "and half lost")
	local asc = WC.resolve(cfg, with(316), {theme = LOW, mods = 1})
	eq(asc.tierStep, 1, "Ascendant Path: a tier higher")
	ok(asc.noBossDrop, "and no boss drop")
	local rp = WC.resolve(cfg, with(416), {theme = LOW, mods = 1})
	eq(rp.rarer, 100, "Rare Pursuit: never Normal")
	eq(rp.quantity, 0, "and -20% quantity (20 - 20)")
	-- drop helpers
	local rows = WC.dropRows({{"Normal", 55}, {"Magic", 30}, {"Rare", 15}}, 20)
	eq(rows[1][2], 4400, "Normal 55 x 0.8 (x100)")
	eq(rows[2][2], 3000, "Magic x100")
	eq(WC.dropRows({{"Normal", 55}}, 100)[1][2], 0, "rarer 100: no Normal")
	for _, r in ipairs(WC.dropRows({{"Normal", 55}, {"Magic", 30}}, 33)) do
		eq(r[2], math.floor(r[2]), "whole weights")
	end
	eq(WC.dropTier({tierStep = 1, tierUp = 0}, 7, 15, 50), 8, "step")
	eq(WC.dropTier({tierStep = 1, tierUp = 10}, 15, 15, 1), 15, "XV stays")
	eq(WC.dropTier({tierStep = 0, tierUp = 10}, 7, 15, 10), 8, "tierUp hit")
	eq(WC.dropTier({tierStep = 0, tierUp = 10}, 7, 15, 11), 7, "tierUp miss")
	eq(WC.dropTier(nil, 7, 15, 1), 7, "no atlas")
	-- payloads
	local tree = WC.treePayload(cfg, tcfg)
	eq(tree.kind, "waystone", "tree kind")
	eq(#tree.nodes, 81, "tree nodes")
	eq(tree.max, 75, "tree max")
	ok(tree.grid.rows and #tree.grid.rows == 5, "tree grid rows")
	local sp = WC.statePayload(cfg, tcfg, {alloc = {[2] = true}, done = {["m1.1"] = true, r1 = true}}, "hi")
	eq(sp.earned, 2, "state earned")
	eq(sp.points, 1, "state points")
	eq(sp.max, 75, "state max")
	ok(sp.totals[1]:find("item quantity", 1, true) ~= nil, "totals text")
end

-- ------------------------------------------------------------------ waystone_atlas.lua against a mocked engine
do
	local rows = {}
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
			return id and rows[id] and id or false
		end,
		escapeString = function(s) return "'" .. s .. "'" end
	}
	_G.result = {
		getString = function(rid, col) return rows[rid][col == "done" and "done" or "nodes"] end,
		free = function() end
	}
	_G.json = {encode = function(t) return t end}
	local clock = 1000
	os.time = function() return clock end -- luacheck: ignore
	local MAP3 = {x = 33350, y = 33050, z = 7} -- map 3 (base tier II, low band)
	local players = {}
	local function mkPlayer(guid, cid, pos)
		local p = {guid = guid, cid = cid, gold = 1000000, orbs = 3, msgs = {}, pos = pos}
		function p:getGuid() return self.guid end
		function p:getId() return self.cid end
		function p:isPlayer() return true end
		function p:getPosition() return self.pos end
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
		players[#players + 1] = p
		return p
	end
	_G.Position = function(x, y, z) return {x = x, y = y, z = z} end
	_G.Game = {getSpectators = function(center, multi, onlyPlayers, minX, maxX, minY, maxY)
		local out = {}
		for _, p in ipairs(players) do
			local q = p.pos
			if q.z == center.z and math.abs(q.x - center.x) <= maxX and math.abs(q.y - center.y) <= maxY then
				out[#out + 1] = p
			end
		end
		return out
	end}
	_G.MESSAGE_EVENT_ADVANCE, _G.MESSAGE_INFO_DESCR = 1, 2
	_G.CreatureEvent = function(name)
		local ev = {}
		function ev.type() end
		function ev.register() end
		events[name] = ev
		return ev
	end
	dofile("data/lib/chaos_pay.lua")
	_G.Chaos = {
		pay = function(player, n, quiet) return ChaosPay.pay(player, n, quiet) end,
		t = function(_, f, ...) return string.format(f, ...) end,
		send = function(player, op, action, data) sent[#sent + 1] = {p = player, op = op, action = action, data = data} end,
		sendChunked = function(player, op, payload) sent[#sent + 1] = {p = player, op = op, action = payload.action, data = payload.data} end,
		decode = function(b) return b end,
		toInt = function(v, lo, hi)
			v = tonumber(v)
			if not v or v < lo or v > hi then
				return nil
			end
			return math.floor(v)
		end,
		tables = {waystoneAtlas = "chaos_waystone_atlas"}
	}
	_G.ChaosOpcodes = {waystoneAtlas = 159}
	_G.ChaosWaystoneAtlasConfig = cfg
	_G.ChaosWaystoneTiersConfig = tcfg
	dofile("data/scripts/chaos/waystone_atlas.lua")
	local WA = ChaosWaystoneAtlas
	local p = mkPlayer(500, 9001, MAP3)
	local q = mkPlayer(600, 9002, MAP3)
	local far = mkPlayer(700, 9003, {x = 100, y = 100, z = 7})
	for _, pl in ipairs(players) do
		events.ChaosWaystoneAtlasLogin.onLogin(pl)
	end
	local function last() return sent[#sent] end
	local function op(pl, action, data)
		events.ChaosWaystoneAtlasExtended.onExtendedOpcode(pl, 159, {action = action, data = data})
	end
	op(p, "open")
	eq(sent[#sent - 1].action, "tree", "tree first")
	eq(sent[#sent - 1].data.kind, "waystone", "the waystone tree")
	eq(last().data.points, 0, "no points")
	events.ChaosWaystoneAtlasExtended.onExtendedOpcode(p, 210, {action = "open"})
	eq(last().action, "state", "another opcode is ignored")
	-- a boss dies in map 3 during a tier-4 run opened from a Rare waystone by p
	local rare = {}
	for _, k in ipairs({"vitality", "brutality", "withering"}) do
		rare[#rare + 1] = {key = k, value = 10}
	end
	rare.opener = 500
	_G.ChaosWaystoneModsCore = {rarityOf = function(_, mods) return #mods >= 3 and 3 or (#mods > 0 and 2 or 1) end}
	_G.ChaosWaystoneMods = {config = {runSeconds = 1860}}
	WA.beginRun(3, 4, rare)
	ok(WA.runs[3].rare, "a Rare run")
	eq(WA.runs[3].opener, 500, "opener kept")
	eq(WA.onBossDeath({map = 3, run = 4, boss = true}), 2, "both players inside credited")
	eq(rows[500].done, "m3.4,r4", "saved: map cell and Rare")
	eq(rows[700], nil, "a player outside the map: nothing")
	ok(p.msgs[1]:find("Ashen Plain, Tier IV", 1, true) ~= nil, "message names the cell")
	local pState = false
	for k = #sent, 1, -1 do
		if sent[k].p == p and sent[k].action == "state" then
			pState = true
			break
		end
		if sent[k].p == p and sent[k].action == "credit" then
			break
		end
	end
	ok(pState, "state pushed to the open window")
	eq(WA.onBossDeath({map = 3, run = 4, boss = true}), 0, "only once")
	eq(WA.onBossDeath({map = 3, run = nil, boss = true}), 0, "no waystone run: nothing")
	eq(WA.onBossDeath({map = 3, run = 4, boss = false}), 0, "not the boss")
	-- a Normal run of tier 5: the map cell only
	WA.beginRun(3, 5, {opener = 600})
	WA.onBossDeath({map = 3, run = 5, boss = true})
	eq(rows[600].done, "m3.4,m3.5,r4", "q: tier 5 added, no Rare 5")
	eq(rows[500].done, "m3.4,m3.5,r4", "p was inside too: 3 points")
	-- allocate along the north spoke: 2, 3, 4; refuse a far node and a fourth point
	op(p, "alloc", {id = 2})
	eq(last().data.points, 2, "allocated one")
	op(p, "alloc", {id = 101})
	ok(last().data.msg and last().data.msg:find("not connected", 1, true), "far node refused")
	op(p, "alloc", {id = 3})
	op(p, "alloc", {id = 4})
	op(p, "alloc", {id = 101})
	ok(last().data.msg and last().data.msg:find("complete new maps", 1, true), "out of points")
	eq(rows[500].nodes, "2,3,4", "saved nodes")
	-- the opener's atlas on a run
	WA.beginRun(3, 4, {opener = 500})
	local am = WA.fxOfMap(3)
	eq(am.quantity, 4, "+4% quantity from two Steady Hands")
	eq(WA.stat(mkPlayer(0, 0, MAP3), "quantity"), 4, "stat at a position in the map")
	eq(WA.stat(far, "quantity"), 0, "outside: 0")
	WA.beginRun(3, 4, {})
	eq(WA.fxOfMap(3), nil, "no opener: no atlas")
	WA.beginRun(3, 4, {opener = 500})
	clock = clock + 2000
	eq(WA.fxOfMap(3), nil, "the run ends")
	-- refund and reset
	op(p, "refund", {id = 3, pay = "gold"})
	ok(last().data.msg:find("depend", 1, true), "bridge refused")
	op(p, "refund", {id = 4, pay = "gold"})
	eq(p.gold, 750000, "250k paid")
	eq(rows[500].nodes, "2,3", "4 refunded")
	op(p, "reset", {pay = "orb"})
	eq(rows[500].nodes, "", "reset")
	eq(p.orbs, 1, "two orbs (2 nodes x 0.8, rounded up)")
	events.ChaosWaystoneAtlasLogout.onLogout(p)
	eq(WA.state[500], nil, "cache cleared")
	_G.ChaosWaystoneModsCore, _G.ChaosWaystoneMods = nil, nil
end

-- ------------------------------------------------------------------ the hooks in waystone_mods.lua / waystone_tiers.lua
do
	local WA = ChaosWaystoneAtlas
	local events = {}
	_G.CreatureEvent = function(name)
		local ev = {name = name}
		function ev:type() end
		function ev:register() events[name] = self end
		return ev
	end
	_G.addEvent = function() end
	_G.COMBAT_HEALING, _G.COMBAT_PHYSICALDAMAGE, _G.COMBAT_FIREDAMAGE, _G.COMBAT_ICEDAMAGE = 128, 1, 8, 512
	_G.COMBAT_ENERGYDAMAGE, _G.COMBAT_NONE = 2, 0
	_G.ITEM_ATTRIBUTE_NAME, _G.ITEM_ATTRIBUTE_DESCRIPTION, _G.ITEM_ATTRIBUTE_ARTICLE = 1, 2, 3
	_G.ChaosWaystoneTiers = {config = tcfg}
	dofile("data/scripts/chaos/waystone_mods.lua")
	local WM = ChaosWaystoneMods
	local MAP3 = {x = 33350, y = 33050, z = 7}
	local mon = {getId = function() return 1 end, getPosition = function() return MAP3 end, isPlayer = function() return false end}
	-- an atlas run with +10% quantity, rarity, experience, +100% waystone and x2 modifier rewards
	WA.runs[3] = {tier = 4, untilAt = os.time() + 100, am = {quantity = 10, rarity = 7, experience = 20, waystone = 100,
		rarer = 100, modRewardMult = 2}}
	eq(WM.lootMult({monster = mon}), 1.1, "loot x1.1 without modifiers")
	eq(WM.rarityFind(mon), 7, "rarity +7")
	eq(WM.expMult(mon), 1.2, "experience x1.2")
	ok(WM.extraWaystone(mon), "waystone 100%: always")
	local run = WM.begin(3, 4, {{key = "vitality", value = 20}})
	local plain = ChaosWaystoneModsCore.bonuses(WM.config, {{key = "vitality", value = 20}}, 4)
	eq(run.bonus.quantity, math.floor(plain.quantity * 2 + 0.5), "modifier rewards x2")
	eq(WM.lootMult({monster = mon}), (1 + run.bonus.quantity / 100) * 1.1, "both multiply")
	-- rarer 100: a drop inside is never Normal
	local function item()
		local it = {custom = {}, attrs = {}}
		function it:getId() return 29848 end
		function it:getCustomAttribute(k) return self.custom[k] end
		function it:setCustomAttribute(k, v) self.custom[k] = v end
		function it:removeCustomAttribute(k) self.custom[k] = nil end
		function it:setAttribute(k, v) self.attrs[k] = v end
		function it:removeAttribute(k) self.attrs[k] = nil end
		return it
	end
	local normal = 0
	for _ = 1, 100 do
		local it = WM.rollDrop(item(), 4, true, mon)
		if not it.custom[WM.config.attribute] then
			normal = normal + 1
		end
	end
	eq(normal, 0, "Rare Pursuit / rarer 100: no Normal drop")
	WA.runs[3] = nil
	WM.finish(3)
	eq(WM.lootMult({monster = mon}), 1, "no run, no atlas: x1")
end

print(string.format("waystone_atlas_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
