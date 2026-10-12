-- Run from the server/ folder: luajit tests/areagen_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- The area generator (data/scripts/chaos/areagen_core.lua, areagen_config.lua): the seeded generator's fixed values,
-- border pieces per neighbour pattern on synthetic cases (all 256 patterns), wall pieces as measured on the live map,
-- the level scaling; every configured area with and without the dark tile set: valid (one connected walkable set over
-- all floors from the arrival, links paired, no item outside the palette, spawns walkable, spread and inside the
-- density band), deterministic (fixed checksums, the same in both interpreters), borders on every transition; many
-- seeds of small caves, dungeons and wastes; then areagen.lua against a mocked engine: the build, the portals, the
-- spawns with their scaling, death, respawn after the spawntime and the view rule, the leash, the dungeon hook.
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

dofile("data/scripts/chaos/areagen_core.lua")
dofile("data/lib/chaos_dark_tiles.lua")
local A = ChaosAreaGenCore
local cfg = dofile("data/scripts/chaos/areagen_config.lua")
local DARK = {dark = true, darkIds = ChaosDarkTiles.ids}

local function copy(t)
	if type(t) ~= "table" then
		return t
	end
	local o = {}
	for k, v in pairs(t) do
		o[k] = copy(v)
	end
	return o
end

-- ====================================================================== the generator: fixed values
local r = A.rng(12345)
eq(r:next(), 1558181227, "first draw after the seed")
eq(r:int(1, 100), 90, "int")
eq(A.hash("emberdeep"), 1909986693, "hash")
local a1, a2 = A.rng(7), A.rng(7)
local same = true
for _ = 1, 500 do
	if a1:next() ~= a2:next() then
		same = false
	end
end
ok(same, "one seed, one sequence")

-- ====================================================================== border pieces (synthetic)
local function pieces(mask)
	local t = A.borderPieces(mask.n, mask.e, mask.s, mask.w, mask.ne, mask.nw, mask.se, mask.sw)
	table.sort(t)
	return table.concat(t, ",")
end
eq(pieces({}), "", "no higher neighbour: no piece")
eq(pieces({n = true}), "n", "north only")
eq(pieces({e = true}), "e", "east only")
eq(pieces({nw = true}), "cnw", "north-west corner only: outer corner")
eq(pieces({se = true}), "cse", "south-east corner only")
eq(pieces({n = true, w = true, nw = true}), "dnw", "north and west: inner corner")
eq(pieces({n = true, w = true}), "dnw", "north and west without the corner: still the inner corner")
eq(pieces({s = true, e = true, se = true}), "dse", "south and east")
eq(pieces({n = true, ne = true, nw = true}), "n", "a side covers its two corners")
eq(pieces({n = true, se = true}), "cse,n", "north side and the opposite corner")
eq(pieces({n = true, s = true}), "n,s", "a one-wide strip between two higher grounds")
eq(pieces({n = true, e = true, s = true, w = true}), "dnw,dse", "surrounded: two inner corners")
eq(pieces({n = true, e = true, s = true}), "dne,s", "three sides")
-- every pattern: each side and each lone corner is covered exactly once, nothing else is drawn
local cover = {n = {n = 1, dnw = 1, dne = 1}, e = {e = 1, dne = 1, dse = 1}, s = {s = 1, dsw = 1, dse = 1},
	w = {w = 1, dnw = 1, dsw = 1}}
local cornerSides = {nw = {"n", "w"}, ne = {"n", "e"}, sw = {"s", "w"}, se = {"s", "e"}}
local allGood = true
for m = 0, 255 do
	local mask = {}
	local names = {"n", "e", "s", "w", "ne", "nw", "se", "sw"}
	for b = 1, 8 do
		mask[names[b]] = math.floor(m / 2 ^ (b - 1)) % 2 == 1
	end
	local list = A.borderPieces(mask.n, mask.e, mask.s, mask.w, mask.ne, mask.nw, mask.se, mask.sw)
	local has = {}
	for _, p in ipairs(list) do
		if has[p] then
			allGood = false
		end
		has[p] = true
	end
	for side, by in pairs(cover) do
		local n = 0
		for p in pairs(has) do
			if by[p] then
				n = n + 1
			end
		end
		if mask[side] and n ~= 1 then
			allGood = false
		end
		if not mask[side] and n ~= 0 then
			allGood = false
		end
	end
	for c, sides in pairs(cornerSides) do
		local lone = mask[c] and not mask[sides[1]] and not mask[sides[2]]
		if lone ~= (has["c" .. c] == true) then
			allGood = false
		end
	end
end
ok(allGood, "all 256 neighbour patterns: every side and lone corner drawn once, nothing more")

-- ====================================================================== wall pieces (measured on the live map)
local wallCases = {
	["-"] = "pole", E = "horizontal", W = "horizontal", EW = "horizontal", N = "vertical", S = "vertical",
	NS = "vertical", ES = "pole", NW = "corner", NE = "vertical", SW = "horizontal", ESW = "horizontal",
	NES = "vertical", NEW = "corner", NSW = "corner", NESW = "corner"
}
for mask, want in pairs(wallCases) do
	local function has(c)
		return mask:find(c, 1, true) ~= nil
	end
	eq(A.wallPiece(has("N"), has("E"), has("S"), has("W")), want, "wall piece " .. mask)
end

-- ====================================================================== level scaling
local sc = A.levelScale(1000, 1000)
ok(sc.health == 1 and sc.damage == 1 and sc.experience == 1, "same level: x1")
sc = A.levelScale(980, 1250)
ok(math.abs(sc.health - (1 + 0.0074 * 1250) / (1 + 0.0074 * 980)) < 1e-9, "health ratio")
ok(sc.health > 1.2 and sc.health < 1.3, "980 -> 1250: about +25% health")
ok(sc.damage > 1.1 and sc.damage < 1.2, "about +16% damage")
ok(math.abs(sc.experience - 1250 / 980) < 1e-9, "experience x L'/L")

-- ====================================================================== config
eq(cfg.aid.entrance, 47950, "entrance action id in the free block")
eq(cfg.aid.exit, 47951, "exit action id")
local hunting = 0
local boxes = {}
for _, def in ipairs(cfg.areas) do
	ok(def.origin.x >= 14336 and def.origin.y >= 14336 and def.origin.x + def.size[1] <= 15359
		and def.origin.y + def.size[2] <= 15359, def.id .. ": inside the empty part of the map")
	for _, b in ipairs(boxes) do
		local apart = def.origin.x > b.x2 or def.origin.x + def.size[1] - 1 < b.x1 or def.origin.y > b.y2
			or def.origin.y + def.size[2] - 1 < b.y1 or def.origin.z > b.z2 or def.origin.z + (def.floors or 1) - 1 < b.z1
		ok(apart, def.id .. " does not overlap " .. b.id)
	end
	boxes[#boxes + 1] = {id = def.id, x1 = def.origin.x, x2 = def.origin.x + def.size[1] - 1, y1 = def.origin.y,
		y2 = def.origin.y + def.size[2] - 1, z1 = def.origin.z, z2 = def.origin.z + (def.floors or 1) - 1}
	-- every monster is one of ours (a monster file with that name)
	local names = {}
	for _, row in ipairs(def.spawns.monsters) do
		names[#names + 1] = row[1]
	end
	names[#names + 1] = def.boss and def.boss.monster
	for _, name in ipairs(names) do
		local f = io.open("data/monster/monsters/chaos/" .. name:lower():gsub(" ", "_") .. ".xml", "r")
		local text = f and f:read("*a") or ""
		if f then
			f:close()
		end
		ok(text:find('name="' .. name .. '"', 1, true) ~= nil, def.id .. ": monster file of " .. name)
	end
	if not def.dungeon then
		hunting = hunting + 1
		ok(def.spawns.level[1] >= 1000 and def.spawns.level[2] <= 1300, def.id .. ": levels inside 1000-1300")
		ok(def.entrance and def.back and def.minLevel, def.id .. ": entrance, way back and level gate")
		ok(def.entrance.x >= 30700 and def.entrance.x <= 34600 and def.entrance.y >= 30900 and def.entrance.y <= 33850,
			def.id .. ": the entrance lies in the world")
		local d = math.max(math.abs(def.entrance.x - def.back.x), math.abs(def.entrance.y - def.back.y))
		ok(d == 1 and def.entrance.z == def.back.z, def.id .. ": the way back is next to the entrance portal")
	end
end
eq(hunting, 3, "three hunting areas")

-- ====================================================================== the configured areas
-- Fixed checksums: change them together with the config (python3 -I server/tools/areagen_export.py summary prints them).
local SUMS = {emberdeep = 877547416, ossuary = 1345173580, cinderfall = 283090213, vault = 1403621262}

-- ground id -> family (stock and dark)
local famOf = {}
for name, f in pairs(cfg.families) do
	for _, row in ipairs(f.grounds) do
		local id = type(row[1]) == "number" and row[1] or ChaosDarkTiles.ids[row[1]]
		famOf[id] = name
	end
end

local function borderCheck(model, opts)
	-- every 4-neighbour transition between two families whose higher one has a border set over the lower one carries
	-- a piece of that set on the lower tile
	local at = {}
	for _, t in ipairs(model.tiles) do
		at[t.z * 2 ^ 32 + t.y * 65536 + t.x] = t
	end
	local missing, transitions = 0, 0
	for _, t in ipairs(model.tiles) do
		local f = famOf[t.ground]
		for _, d in ipairs({{0, -1}, {1, 0}, {0, 1}, {-1, 0}}) do
			local o = at[t.z * 2 ^ 32 + (t.y + d[2]) * 65536 + t.x + d[1]]
			local g = o and famOf[o.ground]
			if f and g and f ~= g and cfg.families[g].z > cfg.families[f].z then
				local set = cfg.borders[g] and (cfg.borders[g][f] or cfg.borders[g]["*"])
				if set then
					transitions = transitions + 1
					local ids = {}
					for _, v in pairs(cfg.pieces[set]) do
						ids[type(v) == "number" and v or ChaosDarkTiles.ids[v]] = true
					end
					local found = false
					for _, id in ipairs(t.items) do
						if ids[id] then
							found = true
						end
					end
					if not found then
						missing = missing + 1
					end
				end
			end
		end
	end
	return missing, transitions
end

for _, def in ipairs(cfg.areas) do
	for _, opts in ipairs({{}, DARK}) do
		local tag = def.id .. (opts.dark and " (dark)" or "")
		local m = A.generate(cfg, def, opts)
		local problems = A.validate(cfg, m, opts)
		eq(#problems, 0, tag .. ": valid: " .. table.concat(problems, "; "))
		eq(A.checksum(A.generate(cfg, def, opts)), A.checksum(m), tag .. ": the same seed gives the same model")
		if not opts.dark then
			eq(A.checksum(m), SUMS[def.id], tag .. ": fixed checksum")
		end
		local missing, transitions = borderCheck(m, opts)
		ok(transitions > 0 or def.kind == "dungeon", tag .. ": has bordered transitions")
		eq(missing, 0, tag .. ": every transition bordered (" .. transitions .. ")")
		-- spawns: spread and from the area's set
		local allowedMonster = {}
		for _, row in ipairs(def.spawns.monsters) do
			allowedMonster[row[1]] = true
		end
		local close = 0
		for i, s in ipairs(m.spawns) do
			ok(allowedMonster[s.monster], tag .. ": monster of the area's set")
			ok(s.level >= def.spawns.level[1] and s.level <= def.spawns.level[2], tag .. ": level inside the band")
			for j = i + 1, #m.spawns do
				local o = m.spawns[j]
				if o.z == s.z and (o.x - s.x) ^ 2 + (o.y - s.y) ^ 2 < def.spawns.minDistance ^ 2 then
					close = close + 1
				end
			end
		end
		eq(close, 0, tag .. ": spawn points at least minDistance apart")
		-- dungeon rooms: never more than roomCap monsters per 100 walkable tiles
		if def.spawns.roomCap and m.rooms then
			local over = 0
			for _, q in ipairs(m.rooms) do
				local w, n = 0, 0
				for y = q.y1, q.y2 do
					for x = q.x1, q.x2 do
						if m.walk[q.z][y * 65536 + x] then
							w = w + 1
						end
					end
				end
				for _, s in ipairs(m.spawns) do
					if s.z == q.z and s.x >= q.x1 and s.x <= q.x2 and s.y >= q.y1 and s.y <= q.y2 then
						n = n + s.count
					end
				end
				if n > math.max(1, math.floor(w * def.spawns.roomCap / 100 + 0.5)) then
					over = over + 1
				end
			end
			eq(over, 0, tag .. ": no room above its monster cap")
		end
		ok(m.boss ~= nil, tag .. ": a boss room with its boss")
		-- the guide's numbers: decoration and lights per walkable tile
		local deco = m.stats.deco / m.stats.walkable
		ok(deco >= 0.06 and deco <= 0.35, tag .. string.format(": decoration %.2f per tile", deco))
		if def.kind ~= "waste" then
			ok(m.stats.lights * 100 / m.stats.walkable >= 2, tag .. ": 2+ lights per 100 tiles")
		end
		-- dark ids only with the dark set
		local darkSet = {}
		for _, id in pairs(ChaosDarkTiles.ids) do
			darkSet[id] = true
		end
		local darkUsed = 0
		for _, t in ipairs(m.tiles) do
			if darkSet[t.ground] then
				darkUsed = darkUsed + 1
			end
			for _, id in ipairs(t.items) do
				if darkSet[id] then
					darkUsed = darkUsed + 1
				end
			end
		end
		if opts.dark then
			ok(darkUsed > 0, tag .. ": uses the dark tile set")
		else
			eq(darkUsed, 0, tag .. ": no dark tile without the set")
		end
	end
end

-- density of the three hunting areas against item 89 (normal hunts 2.7-4.4 per 100 tiles; 1000+ band 2.7)
local total = 0
for _, def in ipairs(cfg.areas) do
	if not def.dungeon then
		local m = A.generate(cfg, def, {})
		total = total + m.stats.monsters
		ok(m.stats.density >= 1.3 and m.stats.density <= 3.5, def.id .. ": density in the item 89 range")
	end
end
ok(total >= 150 and total <= 240, "the three areas hold about 150-200 monsters (" .. total .. ")")

-- ====================================================================== many seeds, small areas
local base = {}
for _, def in ipairs(cfg.areas) do
	base[def.id] = def
end
local variants = {
	{from = "emberdeep", size = {44, 34}, floors = 2, links = 1},
	{from = "emberdeep", size = {40, 30}, floors = 3, links = 1},
	{from = "ossuary", size = {56, 44}, floors = 2, links = 1},
	{from = "cinderfall", size = {50, 40}, floors = 1, links = 0},
	{from = "vault", size = {50, 44}, floors = 1, links = 0}
}
local bad, runs = 0, 0
for _, v in ipairs(variants) do
	for seed = 1, 12 do
		local def = copy(base[v.from])
		def.size, def.floors, def.linksPerFloor, def.seed = v.size, v.floors, math.max(1, v.links), seed * 7919
		def.spawns.band = nil
		if def.kind == "dungeon" then
			def.layout.rooms = {5, 7}
			def.layout.bossRoom = 9
		end
		local m = A.generate(cfg, def, {})
		local problems = A.validate(cfg, m, {})
		runs = runs + 1
		if #problems > 0 then
			bad = bad + 1
			print("  seed " .. seed .. " " .. v.from .. " " .. v.size[1] .. "x" .. v.size[2] .. ": " .. problems[1])
		end
	end
end
eq(bad, 0, "small areas over many seeds are valid (" .. runs .. " runs)")

-- ====================================================================== areagen.lua against a mocked engine
do
	local tiles, monsters, nextId, nowT = {}, {}, 1000, 0
	local registered = {}
	local function key(p)
		return p.z * 2 ^ 32 + p.y * 65536 + p.x
	end
	function Position(x, y, z)
		local p = {x = x, y = y, z = z}
		function p:sendMagicEffect() end
		return p
	end
	CONST_ME_TELEPORT, CONST_PROP_BLOCKSOLID, TILESTATE_TELEPORT, TILESTATE_FLOORCHANGE = 11, 1, 2, 4
	COMBAT_HEALING, COMBAT_PHYSICALDAMAGE, CONDITION_INFIGHT, MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR = 1, 2, 3, 4, 5
	local function newTile(p)
		local t = {pos = p, items = {}, ground = nil}
		function t:getGround() return self.ground end
		function t:getItemById(id)
			for _, it in ipairs(self.items) do
				if it.id == id then return it end
			end
		end
		function t:hasProperty() return false end
		function t:getHouse() return nil end
		function t:hasFlag() return false end
		return t
	end
	function Tile(p)
		return tiles[key(p)]
	end
	-- the live map has one tile at the entrance of each area (the mock's "world")
	for _, def in ipairs(cfg.areas) do
		if def.entrance then
			for _, p in ipairs({def.entrance, def.back}) do
				local t = newTile(p)
				t.ground = {id = 100}
				tiles[key(p)] = t
			end
		end
	end
	Game = {}
	function Game.createTile(p)
		local t = tiles[key(p)] or newTile(p)
		tiles[key(p)] = t
		return t
	end
	function Game.createItem(id, count, p)
		local t = tiles[key(p)]
		local it = {id = id}
		function it:setActionId(a) self.aid = a end
		function it:getActionId() return self.aid or 0 end
		if not t.ground then
			t.ground = it
		else
			t.items[#t.items + 1] = it
		end
		return it
	end
	local seers = {}
	function Game.getSpectators(p)
		local out = {}
		for _, s in ipairs(seers) do
			if s.pos.z == p.z and math.abs(s.pos.x - p.x) <= 9 and math.abs(s.pos.y - p.y) <= 7 then
				out[#out + 1] = s
			end
		end
		return out
	end
	local levels = {}
	function Game.createMonster(name, p)
		nextId = nextId + 1
		local m = {id = nextId, name = name, pos = {x = p.x, y = p.y, z = p.z}, hp = 100000, events = {}}
		function m:getId() return self.id end
		function m:getMonsterLevel() return 980 end
		function m:getMaxHealth() return self.hp end
		function m:setMaxHealth(v) self.hp = v end
		function m:setHealth() end
		function m:registerEvent(e) self.events[e] = true end
		function m:getPosition() return Position(self.pos.x, self.pos.y, self.pos.z) end
		function m:getTarget() return self.target end
		function m:teleportTo(q) self.pos = {x = q.x, y = q.y, z = q.z} end
		function m:remove() monsters[self.id] = nil end
		monsters[m.id] = m
		return m
	end
	function Monster(id)
		return monsters[id]
	end
	function ItemType(id)
		return {getId = function() return ChaosDarkTiles.ids.obsidian_floor == id and 0 or id end}
	end
	os.mtime = function() return nowT end
	local function event(kind)
		return function(name)
			local o = {name = name, kind = kind}
			function o:type(t) self.t = t end
			function o:interval(ms) self.ms = ms end
			function o:aid(...) self.aids = {...} end
			function o:separator() end
			function o:register(idx) registered[#registered + 1] = self end
			return o
		end
	end
	GlobalEvent, CreatureEvent, MoveEvent, TalkAction = event("global"), event("creature"), event("move"), event("talk")
	EventCallback = {register = function(self) registered[#registered + 1] = self end}
	DUNGEON_SYSTEM = {Dungeons = {}}
	Chaos = {isStaff = function() return false end, dungeons = {extra = {}}}
	ChaosRespawnConfig = dofile("data/scripts/chaos/respawn_config.lua")
	dofile("data/scripts/chaos/areagen.lua")
	local function find(name)
		for _, e in ipairs(registered) do
			if e.name == name then
				return e
			end
		end
	end
	-- startup: every area built (the dark set is "missing" one item here, so the stock palette is used)
	find("ChaosAreaGenStartup").onStartup()
	local AG = ChaosAreaGen
	for _, def in ipairs(cfg.areas) do
		ok(AG.built[def.id], def.id .. ": built at startup")
	end
	local em = AG.areas.emberdeep
	local model = em.model
	local t = Tile(Position(model.exit.x, model.exit.y, model.exit.z))
	ok(t and t:getItemById(cfg.items.portal) and t:getItemById(cfg.items.portal):getActionId() == cfg.aid.exit,
		"the exit portal carries its action id")
	local e = Tile(Position(em.def.entrance.x, em.def.entrance.y, em.def.entrance.z))
	ok(e:getItemById(cfg.items.portal) and e:getItemById(cfg.items.portal):getActionId() == cfg.aid.entrance,
		"the entrance portal is placed on the map with its action id")
	local count = 0
	for _ in pairs(monsters) do
		count = count + 1
	end
	local want = 0
	for _, def in ipairs(cfg.areas) do
		if not def.dungeon then
			local m = AG.areas[def.id].model
			want = want + m.stats.monsters + (m.boss and 1 or 0)
		end
	end
	eq(count, want, "every hunting area filled at startup (the dungeon waits for its run)")
	-- scaling: a level 980 monster in a level 1000-1100 area gets more health and a damage / experience factor
	local p1 = em.points[1]
	local m1 = monsters[p1.alive[1]]
	local s1 = A.levelScale(980, p1.level)
	eq(m1.hp, math.floor(100000 * s1.health), "health scaled to the point's level")
	ok(m1.events.ChaosAreaGenDeath, "the death event is on the monster")
	local dmg = find("ChaosAreaGenPlayerHit").onHealthChange(nil, m1, -1000, COMBAT_PHYSICALDAMAGE, -100, 0)
	eq(dmg, math.floor(-1000 * s1.damage), "damage to players scaled")
	local exp = EventCallback.onGainExperience(nil, m1, 1000, 1000)
	eq(exp, math.floor(1000 * s1.experience + 1e-9), "experience scaled")
	local boss
	for _, p in ipairs(em.points) do
		if p.boss then
			boss = monsters[p.alive[1]]
		end
	end
	ok(boss and boss.hp == math.floor(100000 * A.levelScale(980, em.def.boss.level).health * em.def.boss.healthMult),
		"the boss: its level and its health multiplier")
	-- death, then respawn after the spawntime (no hunters: 100%)
	find("ChaosAreaGenDeath").onDeath(m1)
	monsters[m1.id] = nil
	eq(#p1.alive, p1.count - 1, "death frees the point")
	local tick = find("ChaosAreaGenTick").onThink
	nowT = p1.spawntime * 1000 - 1
	tick()
	eq(#p1.alive, p1.count - 1, "not before the spawntime")
	-- a player sees the spot: the timer starts again
	seers[1] = {pos = {x = p1.x + 3, y = p1.y, z = p1.z}, isPlayer = function() return true end,
		getPlayer = function() return nil end}
	nowT = p1.spawntime * 1000
	tick()
	eq(#p1.alive, p1.count - 1, "a player in view: no respawn")
	seers[1] = nil
	nowT = p1.spawntime * 2000 - 1
	tick()
	eq(#p1.alive, p1.count - 1, "the timer started again")
	nowT = p1.spawntime * 2000 + 1
	tick()
	eq(#p1.alive, p1.count, "respawned after the second wait")
	-- leash: a monster far away without a target walks back
	local m2 = monsters[em.points[2].alive[1]]
	m2.pos = {x = m2.pos.x + 30, y = m2.pos.y, z = m2.pos.z}
	tick()
	eq(m2.pos.x, em.points[2].x, "leash: back to its point")
	-- the generated dungeon: registered, filled by the dungeon system's run start
	local vault = AG.areas.vault
	local d = vault.def.dungeon
	ok(DUNGEON_SYSTEM.Dungeons[d.id] and DUNGEON_SYSTEM.Dungeons[d.id].Level == d.level, "the vault is a base dungeon")
	-- its box (the area of a queue run in dungeons.lua: who is inside, the count, the clean-up) holds the entry point,
	-- the exit portal, the boss and every spawn
	do
		local dg = DUNGEON_SYSTEM.Dungeons[d.id]
		local f, t = dg.FromPos, dg.ToPos
		local function inside(q)
			return q.x >= f.x and q.x <= t.x and q.y >= f.y and q.y <= t.y and q.z >= f.z and q.z <= t.z
		end
		local vm = vault.model
		ok(inside(dg.DungeonPos) and inside(vm.exit) and inside(vm.boss), "the vault: entry, exit and boss in its box")
		local out = 0
		for _, s in ipairs(vm.spawns) do
			out = out + (inside(s) and 0 or 1)
		end
		eq(out, 0, "the vault: spawns outside its box")
	end
	local extra = Chaos.dungeons.extra[d.id]
	ok(extra and extra.populate and extra.bossType == vault.def.boss.monster, "the dungeon hook and the boss look")
	extra.populate()
	local n = 0
	for _, p in ipairs(vault.points) do
		n = n + #p.alive
	end
	eq(n, vault.model.stats.monsters + 1, "a run fills every point and the boss")
	extra.populate()
	local n2 = 0
	for _, m in pairs(monsters) do
		local o = vault.model.origin
		if m.pos.z == o.z and m.pos.x >= o.x and m.pos.x < o.x + vault.model.w and m.pos.y >= o.y
			and m.pos.y < o.y + vault.model.h then
			n2 = n2 + 1
		end
	end
	eq(n2, n, "a second run replaces the monsters, never doubles them")
end

print(string.format("areagen: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
