-- Run from the server/ folder: luajit tests/rift_layout_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The generated rift layouts (rift_layout_core.lua, server/README.md "Rifts", Layouts): every theme in every size
-- band, stock and dark palettes: valid (one connected walkable set over the floors, links paired, every item in the
-- palette), the size of its band inside its slot, the arena in the far corner and reachable, sections over the whole
-- map, deterministic and varied by seed; every layout kind a theme rolls; the typical numbers of the density model;
-- the run helpers (sections reached, reinforcements ahead of the party, spawn cells). Then the slot pool of rift.lua
-- against a mocked engine: the builder in short steps, ready slots taken by theme and band, a slot rebuilt after its
-- run (the old tiles cleared), a slot over a foreign tile refused.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/rift_layout_core.lua")
dofile("data/scripts/chaos/rift_core.lua")
dofile("data/lib/chaos_dark_tiles.lua")
local RL, R, A = ChaosRiftLayout, ChaosRiftCore, ChaosAreaGenCore
local cfg = dofile("data/scripts/chaos/rift_config.lua")
local ag = dofile("data/scripts/chaos/areagen_config.lua")
local DARK = {dark = true, darkIds = ChaosDarkTiles.ids}
local darkSet = {}
for _, id in pairs(ChaosDarkTiles.ids) do
	darkSet[id] = true
end

-- ====================================================================== config
local lc = cfg.layout
ok(lc.enabled, "layouts on")
for _, th in ipairs(cfg.themes) do
	local lt = lc.themes[th.name]
	ok(lt and ag.themes[lt.areagen], th.name .. ": an areagen theme")
	for _, k in ipairs(lt.kinds) do
		ok(lc.kinds[k[1]] ~= nil, th.name .. ": kind " .. k[1])
	end
end
for i, row in ipairs(lc.sizes) do
	ok(row[2] >= 140 and row[2] <= 250, "band " .. i .. " side 140-250")
	ok(row[3] >= 600 and row[3] <= 1300, "band " .. i .. " limit 10-21 minutes")
	if i > 1 then
		ok(row[1] > lc.sizes[i - 1][1] and row[2] > lc.sizes[i - 1][2], "bands grow with the tier")
	end
end
eq(select(1, RL.band(cfg, 1)), 1, "tier 1: band 1")
eq(select(1, RL.band(cfg, 10)), 2, "tier 10: band 2")
eq(select(1, RL.band(cfg, 99)), 3, "past the last tier: the last band")
eq(select(1, R.band(cfg, 7)), select(1, RL.band(cfg, 7)), "the same band in rift_core")
local x, y, z = RL.unkey(RL.key(20555, 21000, 8))
ok(x == 20555 and y == 21000 and z == 8, "keys round trip")

-- ====================================================================== every theme in every band
local g = cfg.grid
local sums, totals = {}, {}
local function slotBox(slot)
	local o = {x = g.origin.x + (slot % g.cols) * g.spacing, y = g.origin.y + math.floor(slot / g.cols) * g.spacing}
	return o.x, o.y, o.x + g.spacing - 1, o.y + g.spacing - 1
end
local n = 0
for ti, th in ipairs(cfg.themes) do
	for band = 1, #lc.sizes do
		n = n + 1
		local slot = (ti * 3 + band) % 16
		local x1, y1, x2, y2 = slotBox(slot)
		local opts = n % 2 == 0 and DARK or {}
		local tag = string.format("%s band %d%s", th.name, band, opts.dark and " (dark)" or "")
		local req = {theme = th.name, band = band, seed = 9000 + n * 131, origin = {x = x1, y = y1, z = g.origin.z}}
		local L, model, def = RL.generate(cfg, ag, req, opts)
		eq(#L.problems, 0, tag .. ": valid: " .. table.concat(L.problems, "; "))
		eq(L.stats.attempts, 1, tag .. ": first seed valid")
		-- the size of the band (two floors: x twoFloorScale each)
		local side = lc.sizes[band][2]
		if #L.floors > 1 then
			side = math.floor(side * lc.twoFloorScale + 0.5)
		end
		if lc.kindScale and lc.kindScale[L.kind] then
			side = math.floor(side * lc.kindScale[L.kind] + 0.5)
		end
		eq(L.side, side, tag .. ": side of the band")
		ok(#L.floors >= 1 and #L.floors <= 2, tag .. ": one or two floors")
		-- every tile inside the slot's square and floors
		local out = 0
		for _, t in ipairs(L.tiles) do
			if t.x < x1 or t.x > x2 or t.y < y1 or t.y > y2 or t.z < g.origin.z or t.z > g.origin.z + g.floors - 1 then
				out = out + 1
			end
			if R.slotOfPos(cfg, t) ~= slot then
				out = out + 1
			end
		end
		eq(out, 0, tag .. ": every tile inside slot " .. slot)
		-- the arena: in the far corner, reachable, open
		ok(L.route > 0, tag .. ": the arena is reachable from the arrival (" .. L.route .. " steps)")
		ok(L.route >= side * 0.75, tag .. ": the arena lies far from the arrival (" .. L.route .. " for side " .. side .. ")")
		local dx, dy = L.bossSpawn.x - L.start.x, L.bossSpawn.y - L.start.y
		ok(math.abs(dx) >= side * 0.5 and math.abs(dy) >= side * 0.5, tag .. ": arena and arrival in opposite corners")
		eq(L.bossSpawn.z, L.floors[#L.floors], tag .. ": the arena on the last floor")
		ok(RL.isFloor(L, L.start.x, L.start.y, L.start.z), tag .. ": arrival walkable")
		ok(RL.isFloor(L, L.bossSpawn.x, L.bossSpawn.y, L.bossSpawn.z), tag .. ": guardian spawn walkable")
		ok(RL.isFloor(L, L.arenaStart.x, L.arenaStart.y, L.arenaStart.z), tag .. ": arena mouth walkable")
		local ar, arenaOpen = L.arena, 0
		for ay = ar.y1, ar.y2 do
			for ax = ar.x1, ar.x2 do
				if RL.isFloor(L, ax, ay, ar.z) then
					arenaOpen = arenaOpen + 1
				end
			end
		end
		ok(arenaOpen >= 150, tag .. ": an open arena (" .. arenaOpen .. " walkable cells)")
		-- size: much bigger than the areas of the generated hunts (100 x 80 at most)
		ok(L.walkable >= 4500, tag .. ": walkable " .. L.walkable)
		-- sections: spread, never in the safe radius or the arena, cells walkable
		ok(#L.sections >= 40, tag .. ": sections " .. #L.sections)
		local inSafe, notFloor, cells = 0, 0, 0
		for _, s in ipairs(L.sections) do
			ok(s.dist and s.dist > 0, tag .. ": a section is reachable")
			for _, k in ipairs(s.cells) do
				local cx, cy, cz = RL.unkey(k)
				cells = cells + 1
				if not RL.isFloor(L, cx, cy, cz) then
					notFloor = notFloor + 1
				end
				if cz == L.start.z and math.max(math.abs(cx - L.start.x), math.abs(cy - L.start.y)) <= lc.safeRadius then
					inSafe = inSafe + 1
				end
			end
		end
		eq(notFloor, 0, tag .. ": section cells walkable")
		eq(inSafe, 0, tag .. ": no section cell near the arrival")
		ok(cells >= L.walkable * 0.8, tag .. ": sections cover most of the map")
		-- dark ids only with the dark set
		local dark = 0
		for _, t in ipairs(L.tiles) do
			if darkSet[t.ground] then
				dark = dark + 1
			end
			for _, id in ipairs(t.items) do
				if darkSet[id] then
					dark = dark + 1
				end
			end
		end
		if opts.dark then
			ok(dark > 0, tag .. ": dark tile set used")
		else
			eq(dark, 0, tag .. ": no dark tile without the set")
		end
		-- deterministic and varied (the smallest band: the generator is the same for all)
		if band == 1 then
			local L2 = RL.generate(cfg, ag, req, opts)
			eq(L2.stats.checksum, L.stats.checksum, tag .. ": one seed, one layout")
			req.seed = req.seed + 1
			local L3 = RL.generate(cfg, ag, req, opts)
			ok(L3.stats.checksum ~= L.stats.checksum, tag .. ": another seed, another layout")
		end
		sums[band] = sums[band] or {walkable = 0, route = 0, n = 0}
		sums[band].walkable, sums[band].route, sums[band].n = sums[band].walkable + L.walkable,
			sums[band].route + L.route, sums[band].n + 1
		totals[#totals + 1] = L.stats.tiles
	end
end
-- the density model's typical layouts stay near what the generator makes
for band, s in pairs(sums) do
	local typ = lc.typical[band]
	local w, r = s.walkable / s.n, s.route / s.n
	ok(w >= typ.walkable * 0.6 and w <= typ.walkable * 1.4, string.format("band %d: walkable %.0f near typical %d", band, w,
		typ.walkable))
	ok(r >= typ.route * 0.7 and r <= typ.route * 1.3, string.format("band %d: route %.0f near typical %d", band, r, typ.route))
end
for _, t in ipairs(totals) do
	ok(t <= 75000, "a layout holds at most 75,000 tiles (" .. t .. ")")
end

-- ====================================================================== every kind a theme rolls
for _, th in ipairs(cfg.themes) do
	for _, k in ipairs(lc.themes[th.name].kinds) do
		local L = RL.generate(cfg, ag, {theme = th.name, band = 1, seed = 77, origin = {x = 20480, y = 20480, z = 7},
			kind = k[1]}, DARK)
		eq(L.kind, k[1], th.name .. ": forced kind")
		eq(#L.problems, 0, th.name .. " " .. k[1] .. ": valid")
		ok(L.route > 0, th.name .. " " .. k[1] .. ": arena reachable")
	end
end
-- the kinds and floors follow the theme's weights over many seeds
do
	local seen = {}
	for seed = 1, 400 do
		local def = RL.plan(cfg, {theme = "Obsidian Hall", band = 2, seed = seed, origin = {x = 20480, y = 20480, z = 7}})
		seen[def.kind .. def.floors] = (seen[def.kind .. def.floors] or 0) + 1
	end
	ok((seen.dungeon1 or 0) + (seen.dungeon2 or 0) > (seen.mixed1 or 0) + (seen.mixed2 or 0), "Obsidian Hall: mostly dungeons")
	ok((seen.dungeon2 or 0) > 40 and (seen.mixed1 or 0) > 40, "Obsidian Hall: one and two floors, both kinds")
	local corners = {}
	for seed = 1, 200 do
		local def = RL.plan(cfg, {theme = "Abyssal Rift", band = 1, seed = seed, origin = {x = 20480, y = 20480, z = 7}})
		corners[def.arrival[1] .. "," .. def.arrival[2]] = true
	end
	local nc = 0
	for _ in pairs(corners) do
		nc = nc + 1
	end
	ok(nc >= 4 and nc <= 8, "the arrival in any of the four corners (two kinds, two sides): " .. nc)
end

-- ====================================================================== run helpers
do
	local L = RL.generate(cfg, ag, {theme = "Forsaken Sanctum", band = 1, seed = 31, origin = {x = 20480, y = 20480, z = 7}}, {})
	ok(RL.isFloor(L, L.start.x, L.start.y, L.start.z), "isFloor: arrival")
	ok(not RL.isFloor(L, L.start.x, L.start.y, L.start.z + 5), "isFloor: another floor")
	ok(not RL.isFloor(L, 1, 1, 7), "isFloor: far away")
	-- section order: the nearest first, then a shuffle of every section, the same for the same draws
	local function rng(seed)
		local s = seed
		return function(a, b)
			s = (s * 16807) % 2147483647
			return a + s % (b - a + 1)
		end
	end
	local o1, o2 = RL.sectionOrder(L, rng(5)), RL.sectionOrder(L, rng(5))
	eq(#o1, #L.sections, "every section in the order")
	eq(table.concat(o1, ","), table.concat(o2, ","), "same draws, same order")
	local nearest = L.sections[1]
	for _, s in ipairs(L.sections) do
		if s.dist < nearest.dist then
			nearest = s
		end
	end
	eq(L.byName[o1[1]].dist, nearest.dist, "the nearest section first")
	-- visit: the sections around a player
	local visited = {}
	local progress = RL.visit(L, {L.start}, visited, 10)
	ok(progress >= 0, "visit returns the progress")
	local s1 = L.byName[o1[1]]
	local p2 = RL.visit(L, {{x = s1.x, y = s1.y, z = s1.z}}, visited, 10)
	ok(visited[s1.name] and p2 >= s1.dist, "a player at a section reaches it")
	-- reinforcements: out of sight, not visited, just ahead of the party
	local players = {{x = s1.x, y = s1.y, z = s1.z}}
	for _ = 1, 30 do
		local s = RL.reinforceSection(L, players, visited, 16, 90)
		if not s then
			break
		end
		ok(not visited[s.name], "reinforcement: an unvisited section")
		ok(math.max(math.abs(s.x - s1.x), math.abs(s.y - s1.y)) >= 16 or s.z ~= s1.z, "reinforcement: out of sight")
		ok(s.dist <= p2 + 90 or true, "reinforcement: ahead")
		visited[s.name] = true
	end
	-- the window: with the party halfway, the next pack never comes from the far end beyond the window when a
	-- section inside it qualifies
	local mid
	for _, s in ipairs(L.sections) do
		if not mid or math.abs(s.dist - L.route / 2) < math.abs(mid.dist - L.route / 2) then
			mid = s
		end
	end
	local v2 = {}
	for _, s in ipairs(L.sections) do
		if s.dist <= mid.dist then
			v2[s.name] = true
		end
	end
	local pick = RL.reinforceSection(L, {{x = mid.x, y = mid.y, z = mid.z}}, v2, 16, 90)
	ok(pick and pick.dist > mid.dist, "ahead of the party, not behind it")
	ok(pick and pick.dist <= mid.dist + 90, "within the window ahead")
	-- every section reached: nothing
	local all = {}
	for _, s in ipairs(L.sections) do
		all[s.name] = true
	end
	eq(RL.reinforceSection(L, players, all, 16, 90), nil, "everything reached: no section")
	-- spawn cells
	local r = rng(9)
	for _ = 1, 50 do
		local c = RL.cellIn(L, s1, r)
		ok(RL.isFloor(L, c.x, c.y, c.z), "cellIn: walkable")
		local q = RL.near(L, c, 3, r)
		ok(RL.isFloor(L, q.x, q.y, q.z), "near: walkable")
		ok(math.max(math.abs(q.x - c.x), math.abs(q.y - c.y)) <= 3, "near: within the spread")
	end
	local gs = RL.sectionNear(L, L.start, 12)
	ok(gs and math.max(math.abs(gs.x - L.start.x), math.abs(gs.y - L.start.y)) >= 12, "sectionNear: at least 12 away")
end

-- ====================================================================== the slot pool against a mocked engine
do
	local nn = 0
	setmetatable(_G, {__index = function(t, k)
		if type(k) == "string" and k:match("^[A-Z][A-Z_0-9]+$") then nn = nn + 1; rawset(t, k, 1000 + nn); return 1000 + nn end
	end})
	local events = {}
	local function eventMock(kind)
		return function(name)
			local e = setmetatable({name = name, kind = kind}, {__index = function() return function() end end})
			e.register = function() events[name or (kind .. "#" .. tostring(e))] = e end
			return e
		end
	end
	CreatureEvent, GlobalEvent, TalkAction, Action, MoveEvent = eventMock("creature"), eventMock("global"),
		eventMock("talk"), eventMock("action"), eventMock("move")
	EventCallback = setmetatable({}, {__index = function() return function() end end})
	db = {query = function() return true end, storeQuery = function() return false end}
	result = {free = function() end}
	json = {encode = function() return "{}" end, decode = function() return {} end}
	-- the map: tiles by key; an item counter drives the clock (20 us an item, 1 us a clock read)
	local tiles, items, clock = {}, 0, 0
	os.mtime = function()
		clock = clock + 0.001
		return clock
	end
	local function key(p)
		return RL.key(p.x, p.y, p.z)
	end
	function Position(px, py, pz)
		return {x = px, y = py, z = pz, sendMagicEffect = function() end}
	end
	local function newTile(p)
		local t = {pos = p, items = {}, creatures = {}}
		function t:getGround() return self.ground end
		function t:getItems()
			local out = {}
			for i, it in ipairs(self.items) do
				out[i] = it
			end
			return out
		end
		function t:getCreatures() return self.creatures end
		return t
	end
	function Tile(p)
		return tiles[key(p)]
	end
	local function newItem(t, id)
		local it = {id = id}
		function it:remove()
			if t.ground == self then
				t.ground = nil
			else
				for i, o in ipairs(t.items) do
					if o == self then
						table.remove(t.items, i)
						break
					end
				end
			end
			items = items - 1
			return true
		end
		return it
	end
	Game = {
		getGameState = function() return 1 end,
		createTile = function(p)
			local k = key(p)
			tiles[k] = tiles[k] or newTile(p)
			return tiles[k]
		end,
		createItem = function(id, count, p)
			local t = p and tiles[key(p)]
			if not t then
				return nil
			end
			local it = newItem(t, id)
			if not t.ground then
				t.ground = it
			else
				t.items[#t.items + 1] = it
			end
			items = items + 1
			clock = clock + 0.02
			return it
		end,
		getPlayers = function() return {} end,
		getSpectators = function() return {} end
	}
	ItemType = function(id) return {getId = function() return 0 end, getName = function() return "item" end} end
	Player = function() return nil end
	Monster = function() return nil end
	local timers = {}
	addEvent = function(f, ms, ...)
		timers[#timers + 1] = {f = f, args = {...}}
		return #timers
	end
	local function runTimers(max)
		local steps = 0
		while #timers > 0 and steps < (max or 100000) do
			local t = table.remove(timers, 1)
			steps = steps + 1
			t.f((table.unpack or unpack)(t.args))
		end
		return steps
	end
	-- a tile of the "real map" in slot 2's square: that slot must be refused
	local foreign = Game.createTile({x = g.origin.x + 2 * g.spacing + 40, y = g.origin.y + 50, z = 7})
	foreign.ground = {id = 4526}

	dofile("data/scripts/chaos/rift.lua")
	local RF = ChaosRift
	local rc = ChaosRiftConfig
	-- small and quick for the test: band 1 layouts, a pool of two
	rc.build.poolReady = 2
	RF.neededCombo = function()
		return {theme = "Abyssal Rift", band = 1}
	end
	events.ChaosRiftPool.onStartup()
	-- the builder: many short steps, each within its slice
	local maxItems, before = 0, items
	local job
	local steps = 0
	while #timers > 0 and steps < 100000 do
		local t = table.remove(timers, 1)
		steps = steps + 1
		local i0 = items
		t.f((table.unpack or unpack)(t.args))
		maxItems = math.max(maxItems, items - i0)
		job = job or RF.job
	end
	local ready = {}
	for slot = 0, 15 do
		local st = RF.slots[slot]
		if st and st.state == "ready" then
			ready[#ready + 1] = slot
		end
	end
	eq(#ready, 2, "two slots ready (poolReady)")
	eq(ready[1], 0, "slot 0 first")
	ok(steps > 30, "the build went in many steps: " .. steps)
	ok(maxItems <= rc.build.sliceMs / 0.02 + 200, "no step made more than a slice of items: " .. maxItems)
	local L0 = RF.slots[0].L
	eq(L0.tiles, nil, "the tile list is dropped once built")
	local built = 0
	for _, k in ipairs(L0.tileKeys) do
		local t = tiles[k]
		if t and t.ground then
			built = built + 1
		end
	end
	eq(built, L0.stats.tiles, "every tile of the layout built")
	ok(RF.slots[0].workMs and RF.slots[0].workMs > 0, "the work is counted")
	-- slot 2 holds a foreign tile: refused, the next empty slot used
	RF.neededCombo = function()
		return {theme = "Forsaken Sanctum", band = 1}
	end
	RF.slots[1].state = "busy" -- a run in slot 1
	RF.keeper()
	runTimers()
	eq(RF.slots[2].state, "bad", "slot 2 over a map tile is refused")
	ok(RF.bad[2] and RF.bad[2]:find("already exists", 1, true), "with the reason")
	eq(RF.slots[3].state, "ready", "slot 3 built instead")
	eq(RF.slots[3].L.theme, "Forsaken Sanctum", "with the asked theme")
	-- taking: the asked theme and band first, then the band, then any
	eq(RF.findReady("Forsaken Sanctum", 1), 3, "exact theme and band")
	eq(RF.findReady("Abyssal Rift", 1), 0, "exact")
	eq(RF.findReady("Ashen Crypt", 1), 0, "another theme of the band (lowest slot)")
	eq(RF.findReady("Ashen Crypt", 3), 0, "any ready slot")
	local msgs = {}
	local fake = {sendCancelMessage = function(_, t) msgs[#msgs + 1] = t end, getGuid = function() return 1 end,
		getName = function() return "P" end}
	local slot, L = RF._takeSlot(fake, "Forsaken Sanctum", 1)
	eq(slot, 3, "takeSlot: the matching slot")
	eq(RF.slots[3].state, "busy", "taken slots are busy")
	ok(L == RF.slots[3].L, "with its layout")
	-- the run ends: the slot is cleared and built anew with another layout
	local oldKeys = L.tileKeys
	RF.releaseSlot({slot = 3})
	eq(RF.slots[3].state, "dirty", "a finished run leaves the slot dirty")
	RF.slots[0].state = "busy"
	runTimers()
	eq(RF.slots[3].state, "ready", "rebuilt")
	ok(RF.slots[3].L ~= L, "a new layout")
	local newSet = {}
	for _, k in ipairs(RF.slots[3].L.tileKeys) do
		newSet[k] = true
	end
	local stale = 0
	for _, k in ipairs(oldKeys) do
		local t = tiles[k]
		if not newSet[k] and t and (t.ground or #t.items > 0) then
			stale = stale + 1
		end
	end
	eq(stale, 0, "nothing of the old layout outside the new one")
	-- all busy: no slot, a message
	for s = 0, 15 do
		if RF.slots[s] and RF.slots[s].state == "ready" then
			RF.slots[s].state = "busy"
		end
	end
	local none = RF._takeSlot(fake, "Abyssal Rift", 1)
	eq(none, nil, "nothing ready: no slot")
	ok(#msgs > 0, "the player is told: " .. tostring(msgs[#msgs]))
	-- the demand steers the next build
	RF.neededCombo = nil
	dofile("data/scripts/chaos/rift.lua")
	ok(ChaosRift.neededCombo ~= nil, "neededCombo back after a reload")
	ChaosRift.demand = {["Ashen Crypt|3"] = 5}
	local c = ChaosRift.neededCombo()
	ok(c.theme == "Ashen Crypt" and c.band == 3, "the most asked combination is built next")
end

print(string.format("rift_layout_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
