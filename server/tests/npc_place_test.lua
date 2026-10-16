-- Run from the server/ folder: luajit tests/npc_place_test.lua (and lua5.3; CI runs both)
-- Startup NPCs next to the temples (npc_place_core.lua, npc_place.lua) and the nearest-NPC greeting rule
-- (data/lib/chaos_npc_focus.lua). Live test 2026-10-14: no Loot Buyer at Nightwrack or Scorchveil ("no free tile":
-- every fixed offset a wall or taken), and the Loot Buyer next to the Gambler (one "hi" / "trade" opened both).
-- Checks: the configured offsets win when free; a temple in a walled room still gets an NPC through its door; nothing
-- outside the walls (unreachable) or on a door; every NPC keeps more than the talk radius from the others; the
-- result is the same every time; npc_place.lua on a mocked map places all six startup NPCs of a crowded temple apart;
-- only the nearest NPC answers a greeting.

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/npc_place_core.lua")
local K = ChaosNpcPlaceCore

-- a map from rows of text, the temple at "T": "." floor, "#" wall, "D" closed door, "x" floor someone stands on
local function grid(rows)
	local cells, tx, ty = {}, 0, 0
	for y, row in ipairs(rows) do
		for x = 1, #row do
			local ch = row:sub(x, x)
			cells[x .. ":" .. y] = ch
			if ch == "T" then
				tx, ty = x, y
			end
		end
	end
	local function at(dx, dy) return cells[(tx + dx) .. ":" .. (ty + dy)] end
	return {
		walkable = function(dx, dy) local c = at(dx, dy) return c == "." or c == "T" or c == "x" end,
		door = function(dx, dy) return at(dx, dy) == "D" end,
		free = function(dx, dy) return at(dx, dy) ~= "x" end
	}
end

local function spec(map, extra)
	local s = {walkable = map.walkable, door = map.door, free = map.free}
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	return s
end

-- ---------------------------------------------------------------- the configured offsets first
do
	local map = grid({
		"...........",
		"...........",
		"...........",
		".....T.....",
		"...........",
		"...........",
		"..........."})
	local x, y = K.pick(spec(map, {offsets = {{-4, 2}, {4, 2}}}))
	eq(x .. "," .. y, "-4,2", "a free offset wins")
	x, y = K.pick(spec(map, {offsets = {{-4, 2}, {4, 2}}, others = {{-5, 2}}}))
	eq(x .. "," .. y, "4,2", "an offset next to another NPC is skipped")
end

-- ---------------------------------------------------------------- Nightwrack: every offset a wall, a walled temple
do
	local map = grid({
		"###########",
		"#.........#",
		"#....T....#",
		"#.........#",
		"#####D#####",
		"...........",
		"...........",
		"..........."})
	local offsets = {{-4, 3}, {4, 3}, {-5, 0}, {5, 0}, {0, -5}, {0, 5}} -- the Loot Buyer's: walls, or outside
	local x, y = K.pick(spec(map, {offsets = offsets}))
	check(x ~= nil, "Nightwrack: a spot is found")
	check(x and K.cheb(x, y, 0, 0) >= 2, "not on or next to the temple tile")
	check(x and map.walkable(x, y) and not map.door(x, y), "a floor tile, not the door")
	local again = {K.pick(spec(map, {offsets = offsets}))}
	eq(again[1] .. "," .. again[2], x .. "," .. y, "the same spot every time")
	-- a closed room with no door: nothing outside counts
	local closed = grid({
		"#######",
		"#.....#",
		"#..T..#",
		"#.....#",
		"#######",
		"......."})
	x, y = K.pick(spec(closed, {offsets = {{0, 3}}}))
	check(x == nil or y < 2, "never behind a wall (unreachable)")
	-- crowded: everything near is taken, the search goes further out through the door
	local map2 = grid({
		"#####",
		"#xTx#",
		"##D##",
		".....",
		".....",
		"....."})
	x, y = K.pick(spec(map2, {}))
	check(x ~= nil and y >= 2, "through the door when the room is full: " .. tostring(x) .. "," .. tostring(y))
end

-- ---------------------------------------------------------------- spacing: more than the talk radius
do
	local rows = {}
	for i = 1, 21 do
		rows[i] = i == 11 and "..........T.........." or "....................."
	end
	local map = grid(rows)
	local placed = {}
	for i = 1, 6 do
		local x, y = K.pick(spec(map, {offsets = {{-4, 3}, {-5, 2}, {4, 3}}, others = placed}))
		check(x ~= nil, "NPC " .. i .. " placed")
		placed[#placed + 1] = {x, y}
	end
	for i = 1, #placed do
		for j = i + 1, #placed do
			check(K.cheb(placed[i][1], placed[i][2], placed[j][1], placed[j][2]) > K.TALK_RADIUS,
				"NPCs " .. i .. " and " .. j .. " further apart than the talk radius")
		end
	end
	-- a corridor tile is used only when nothing else is left
	local corridor = grid({
		"#######",
		"#..T..#",
		"###.###",
		"###.###",
		"###.###"})
	local x, y = K.pick(spec(corridor, {}))
	check(x ~= nil and y == 0, "the room before the corridor: " .. tostring(x) .. "," .. tostring(y))
end

-- ---------------------------------------------------------------- npc_place.lua on a mocked map
do
	local blocked, doors, creatures = {}, {}, {}
	local function k(x, y) return x .. ":" .. y end
	-- a temple at 100,100: a ring of walls 2 tiles out with a door south, open land beyond
	for x = 97, 103 do
		blocked[k(x, 97)], blocked[k(x, 103)] = true, true
	end
	for y = 97, 103 do
		blocked[k(97, y)], blocked[k(103, y)] = true, true
	end
	blocked[k(100, 103)], doors[k(100, 103)] = true, true
	CONST_PROP_BLOCKSOLID, CONST_PROP_BLOCKPATH, TILESTATE_TELEPORT, TILESTATE_FLOORCHANGE = 1, 2, 3, 4
	function Position(x, y, z) return {x = x, y = y, z = z} end
	function ItemType(id) return {isDoor = function() return id == 5000 end} end
	function Tile(p)
		if math.abs(p.x - 100) > 30 or math.abs(p.y - 100) > 30 then
			return nil
		end
		local key = k(p.x, p.y)
		return {
			getGround = function() return true end,
			hasFlag = function() return false end,
			hasProperty = function(_, prop) return prop == CONST_PROP_BLOCKSOLID and blocked[key] or false end,
			getHouse = function() return nil end,
			getItems = function() return doors[key] and {{getId = function() return 5000 end}} or {} end,
			getTopCreature = function() return creatures[key] end
		}
	end
	local npcs, nextId = {}, 1000
	Game = {
		getSpectators = function(pos, _, _, rx)
			local out = {}
			for _, c in ipairs(npcs) do
				if math.abs(c.pos.x - pos.x) <= rx and math.abs(c.pos.y - pos.y) <= rx then
					out[#out + 1] = c
				end
			end
			return out
		end,
		createNpc = function(name, pos)
			nextId = nextId + 1
			local c = {name = name, pos = pos, id = nextId}
			function c:isNpc() return true end
			function c:getName() return self.name end
			function c:getPosition() return self.pos end
			function c:getId() return self.id end
			npcs[#npcs + 1] = c
			creatures[k(pos.x, pos.y)] = c
			return c
		end
	}
	dofile("data/scripts/chaos/npc_place.lua")
	local temple = Position(100, 100, 7)
	local wanted = {
		{"Material Broker", dofile("data/scripts/chaos/professions_config.lua").broker.offsets},
		{"Loot Buyer", dofile("data/scripts/chaos/item_prices_config.lua").npc.offsets},
		{"Mordecai Ashwager", {{-5, -2}, {5, -2}, {-5, 2}, {5, 2}, {-1, -5}, {1, 5}}},
		{"Ascendant Oracle", {{2, -2}, {-2, -2}, {2, 2}, {-2, 2}, {3, 0}, {-3, 0}, {0, -3}, {0, 3}}},
		{"Archivist Maelis", {{5, 0}, {-5, 0}, {0, 5}, {0, -5}, {5, 3}, {-5, 3}}},
		{"Warden Ysolde", {{3, 3}}}
	}
	for _, w in ipairs(wanted) do
		local npc = ChaosNpcPlace.place(w[1], temple, w[2])
		check(npc ~= nil, w[1] .. " placed")
	end
	eq(#npcs, #wanted, "one NPC each")
	for i = 1, #npcs do
		local a = npcs[i].pos
		check(not blocked[k(a.x, a.y)], npcs[i].name .. " not on a wall or the door")
		for j = i + 1, #npcs do
			local b = npcs[j].pos
			check(math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) > 3,
				npcs[i].name .. " and " .. npcs[j].name .. " apart (" .. a.x .. "," .. a.y .. " / " .. b.x .. "," .. b.y .. ")")
		end
	end
	local again = ChaosNpcPlace.place("Loot Buyer", temple, {})
	check(again == npcs[2], "a second call keeps the Loot Buyer already there")

	-- start log 2026-10-16, Nightwrack: a temple room with no tile left (here: the room around 110,110 is one tile,
	-- walls all round) -> with depotFallback the NPC stands near the nearest depot of the map markers
	for x = 108, 112 do
		for y = 108, 112 do
			if x ~= 110 or y ~= 110 then
				blocked[k(x, y)] = true
			end
		end
	end
	ChaosNpcPlace.poiMarks = {
		{k = "temple", x = 110, y = 110, z = 7},
		{k = "depot", x = 120, y = 90, z = 7}, -- the nearest depot (open land)
		{k = "depot", x = 112, y = 112, z = 8}, -- nearer, another floor: after the same floor
		{k = "depot", x = 200, y = 200, z = 7}, -- too far
	}
	local small = Position(110, 110, 7)
	check(ChaosNpcPlace.place("Loot Buyer Two", small, {{1, 0}}) == nil, "no depotFallback: no spot, no NPC")
	local lb = ChaosNpcPlace.place("Loot Buyer Two", small, {{1, 0}}, {depotFallback = true})
	check(lb ~= nil, "depotFallback: placed")
	if lb then
		local p = lb:getPosition()
		check(math.max(math.abs(p.x - 120), math.abs(p.y - 90)) <= K.DEFAULTS.radius and p.z == 7,
			"near the same-floor depot (" .. p.x .. "," .. p.y .. "," .. p.z .. ")")
		check(not blocked[k(p.x, p.y)], "on a free tile")
		check(ChaosNpcPlace.place("Loot Buyer Two", small, {{1, 0}}, {depotFallback = true}) == lb,
			"a second call keeps the NPC at the depot")
	end
	ChaosNpcPlace.poiMarks = nil
end

-- the depot anchors (pure)
do
	local marks = {
		{k = "depot", x = 150, y = 100, z = 7}, {k = "depot", x = 130, y = 100, z = 7}, {k = "depot", x = 101, y = 100, z = 9},
		{k = "depot", x = 100, y = 100, z = 10}, {k = "bank", x = 101, y = 100, z = 7}, {k = "depot", x = 100, y = 300, z = 7},
		{k = "depot", x = 130, y = 99, z = 7},
	}
	local a = K.depotAnchors({x = 100, y = 100, z = 7}, marks)
	eq(#a, 4, "depots within 64 tiles and 2 floors")
	eq(a[1] and (a[1].x .. "," .. a[1].y), "130,99", "same floor, nearest, then row")
	eq(a[2] and (a[2].x .. "," .. a[2].y), "130,100", "then column")
	eq(a[3] and a[3].x, 150, "the farther one")
	eq(a[4] and a[4].z, 9, "another floor last")
	eq(#K.depotAnchors({x = 100, y = 100, z = 7}, nil), 0, "no marks: none")
end

-- ---------------------------------------------------------------- only the nearest NPC answers
do
	dofile("data/lib/chaos_npc_focus.lua")
	local F = ChaosNpcFocus
	local buyer, gambler = {id = 10, x = 100, y = 100}, {id = 11, x = 101, y = 100}
	local all = {buyer, gambler}
	check(F.answers(buyer, all, {x = 99, y = 100}) and not F.answers(gambler, all, {x = 99, y = 100}),
		"the nearer NPC answers, the other is silent")
	check(not F.answers(buyer, all, {x = 102, y = 101}) and F.answers(gambler, all, {x = 102, y = 101}),
		"the other side: the other one")
	local mid = {x = 100, y = 101} -- the same distance from both
	check(F.answers(buyer, all, mid) ~= F.answers(gambler, all, mid), "a tie: exactly one answers")
	check(F.answers(gambler, {gambler, {id = 1, x = 110, y = 110}}, {x = 101, y = 101}), "an NPC far away does not count")
	-- in an NPC script: focused players always reach their NPC
	local me = {id = 11, pos = {x = 101, y = 100, z = 7}}
	function Npc() return {getId = function() return me.id end, getPosition = function() return me.pos end} end
	function Player() return {getPosition = function() return {x = 99, y = 100, z = 7} end} end
	Game = {getSpectators = function()
		local mk = function(id, x) return {isNpc = function() return true end, getId = function() return id end,
			getPosition = function() return {x = x, y = 100, z = 7} end} end
		return {mk(10, 100), mk(11, 101)}
	end}
	local handler = {talkRadius = 3, focused = false}
	function handler:isFocused() return self.focused end
	check(not F.hears(5, handler), "a greeting near the Loot Buyer does not reach the Gambler")
	handler.focused = true
	check(F.hears(5, handler), "a player talking to the Gambler is heard")
end

if failures > 0 then
	error(string.format("%d of %d checks failed", failures, checks))
end
print(string.format("npc_place_test: %d checks passed", checks))
