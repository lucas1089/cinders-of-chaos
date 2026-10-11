-- Run from the server/ folder: luajit tests/hideout_test.lua (and lua5.3; CI runs both)
-- Hideouts: the pure rules of hideout_core.lua with the real hideout_config.lua (catalogue checks against
-- achievements_data.lua, factions_config.lua and the store; the grid against every other runtime grid; placement,
-- rotation, walls, rugs, limits, the path to the fixtures; unlock sources; permissions; likes and visits; the showcase;
-- slot pooling), then hideout.lua on a mocked engine and database (enter, build, place / move / remove, theme, the
-- depot locker, permissions and visitors, likes, the store unlock, teardown and slot reuse, login inside).
local unpack = table.unpack or unpack
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then
		n = n + 1
		rawset(t, k, 9000 + n)
		return 9000 + n
	end
end})

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	eq(not not v, true, m)
end

dofile("data/scripts/chaos/hideout_core.lua")
local K = ChaosHideoutCore
local cfg = dofile("data/scripts/chaos/hideout_config.lua")
local achievements = dofile("data/scripts/chaos/achievements_data.lua")
local factions = dofile("data/scripts/chaos/factions_config.lua")
dofile("data/scripts/chaos/shop_core.lua")
local shop = dofile("data/scripts/chaos/shop_config.lua")

-- ---------------------------------------------------------------- the shipped config
local problems = K.validate(cfg, achievements, factions, shop)
for _, p in ipairs(problems) do
	print("problem: " .. p)
end
eq(#problems, 0, "validate")
eq(cfg.opcode, 192, "opcode")
dofile("data/scripts/chaos/chaos_constants.lua")
eq(ChaosOpcodes.hideout, cfg.opcode, "ChaosOpcodes.hideout")
eq(Chaos.storage.hideout, cfg.storage.returnX, "storage base")
-- the opcode collides with nothing (every ChaosOpcodes entry and the reference server's list)
local REF = {1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202}
-- and the reference client's own (gamelib ExtendedIds and 0x8C): 140, 144 - 146, 210, 212, 213, 230, 246
for _, r in ipairs({140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	REF[#REF + 1] = r
end
for _, r in ipairs(REF) do
	ok(r ~= cfg.opcode, "reference opcode " .. r)
end
for name, op in pairs(ChaosOpcodes) do
	ok(name == "hideout" or op ~= cfg.opcode, "opcode shared with " .. name)
end
-- storages inside the Chaos range and nobody else's
for _, v in pairs(cfg.storage) do
	ok(v >= 7100180 and v <= 7100189, "storage " .. v)
end
-- themes: four, the default one first; every source type is used somewhere
eq(#cfg.themes, 4, "four themes")
eq(K.defaultTheme(cfg).key, "ashen_crypt", "the Ashen Crypt is free")
local types = {}
for _, d in ipairs(cfg.decorations) do
	types[d.source.type .. (d.source.group or "")] = true
end
for _, t in ipairs({"default", "achievement", "statevent", "stattrophy", "faction", "descent", "journey", "store"}) do
	ok(types[t], "a decoration from " .. t)
end

-- validation catches mistakes
do
	local bad = {}
	for k, v in pairs(cfg) do
		bad[k] = v
	end
	bad.decorations = {
		{key = "x", name = "X", cat = "nope", layer = "object", ids = {1}, source = {type = "default"}},
		{key = "x", name = "X", cat = "furniture", layer = "wall", wall = {n = 1}, source = {type = "default"}},
		{key = "y", name = "Y", cat = "furniture", layer = "object", ids = {1}, buff = 5, source = {type = "achievement", id = "nope"}},
		{key = "z", name = "Z", cat = "rug", layer = "floor", ids = {1}, block = true, source = {type = "faction", faction = "x", rank = "y"}},
		{key = "w", name = "W", cat = "furniture", layer = "object", ids = {1}, source = {type = "store"}}
	}
	bad._decoIndex = nil
	local list = K.validate(bad, achievements, factions, nil)
	local text = table.concat(list, "\n")
	for _, want in ipairs({"category nope", "twice", "wall = {n, w}", "field buff", "unknown achievement", "a rug cannot block",
			"unknown faction", "unknown rank", "store source without a price"}) do
		ok(text:find(want, 1, true), "validate finds: " .. want)
	end
	-- the store must sell exactly the store decorations
	local fake = {categories = {{name = "x", offers = {{kind = "unlock", unlock = "hideout_ashen_throne", cost = 5, name = "Ashen Throne"}}}}}
	text = table.concat(K.validate(cfg, achievements, factions, fake), "\n")
	ok(text:find("store decoration without its store offer", 1, true), "missing offer found")
	ok(text:find("sold in the store but its source is default", 1, true), "an earned decoration sold is found")
	cfg._decoIndex = nil
end

-- ---------------------------------------------------------------- the grid
local W, H = cfg.inner.w, cfg.inner.h
local o1 = K.slotOrigin(cfg, 1)
eq(o1.x, 12288, "slot 1 x")
eq(o1.y, 12288, "slot 1 y")
local o17 = K.slotOrigin(cfg, 17)
eq(o17.x, 12288, "slot 17 starts the second row")
eq(o17.y, 12288 + 32, "second row y")
local oLast = K.slotOrigin(cfg, cfg.grid.maxSlots)
ok(oLast.x + W + 1 < 12800 and oLast.y + H + 1 < 12800, "the last slot ends below 12800")
eq(#K.footprint(cfg, 5), (W + 2) * (H + 2), "footprint size")
ok(W + 2 <= cfg.grid.spacing and H + 2 <= cfg.grid.spacing, "rooms do not touch")
for _, s in ipairs({1, 2, 16, 17, 100, 256}) do
	local p = K.toWorld(cfg, s, 3, 4)
	local s2, gx, gy = K.fromWorld(cfg, p)
	eq(s2, s, "slot round trip " .. s)
	eq(gx, 3, "gx round trip")
	eq(gy, 4, "gy round trip")
end
eq(K.fromWorld(cfg, {x = 12288 + W + 2, y = 12288, z = 7}), nil, "between two rooms is outside")
eq(K.fromWorld(cfg, {x = 12287, y = 12288, z = 7}), nil, "west of the grid")
eq(K.fromWorld(cfg, {x = 12288, y = 12288, z = 6}), nil, "another floor")
eq(K.fromWorld(cfg, {x = 12288 + 16 * 32, y = 12288, z = 7}), nil, "east of the grid")
eq(K.fromWorld(cfg, {x = 12288, y = 12288 + 16 * 32, z = 7}), nil, "south of the last row")

-- no other runtime grid overlaps the hideout grid
do
	local function rect(name, g, rows, spacing, cols)
		spacing = spacing or g.spacing
		cols = cols or g.cols
		rows = rows or g.rows or math.ceil((g.slots or g.maxSlots or cols) / cols)
		return {name = name, x1 = g.origin.x, y1 = g.origin.y, x2 = g.origin.x + cols * spacing, y2 = g.origin.y + rows * spacing}
	end
	local mine = rect("hideout", cfg.grid)
	eq(mine.x2, 12288 + 512, "hideout grid width")
	local others = {}
	for _, f in ipairs({"rift", "raid", "descent", "guildboss", "battleground", "arena", "uber", "trials", "ascension_quest"}) do
		local okLoad, c = pcall(dofile, "data/scripts/chaos/" .. f .. "_config.lua")
		if okLoad and type(c) == "table" then
			local g = c.grid or (c.trial and c.trial.grid) or (c.arena and c.arena.grid)
			if not g then
				for _, v in pairs(c) do
					if type(v) == "table" and type(v.grid) == "table" and v.grid.origin then
						g = v.grid
					end
				end
			end
			if g and g.origin then
				others[#others + 1] = rect(f, g)
			end
		end
	end
	local guild = dofile("data/scripts/chaos/guild_config.lua").hall
	others[#others + 1] = rect("guild hall", {origin = guild.origin}, math.ceil(guild.maxSlots / guild.columns), guild.stride, guild.columns)
	ok(#others >= 8, "other grids read: " .. #others)
	for _, r in ipairs(others) do
		local overlap = r.x1 < mine.x2 and mine.x1 < r.x2 and r.y1 < mine.y2 and mine.y1 < r.y2
		ok(not overlap, "the hideout grid is clear of " .. r.name)
	end
end

-- wall pieces of a wall family: corner, horizontal, vertical, post; the dark tall wall only on the back walls
do
	local function piece(x, y) return (K.wallPiece(cfg, x, y)) end
	eq(piece(0, 0), "corner", "north-west")
	eq(piece(5, 0), "h", "north")
	eq(piece(5, H + 1), "h", "south")
	eq(piece(0, 5), "v", "west")
	eq(piece(W + 1, 5), "v", "east")
	eq(piece(W + 1, 0), "v", "north-east")
	eq(piece(0, H + 1), "h", "south-west")
	eq(piece(W + 1, H + 1), "pole", "south-east")
	eq(piece(5, 5), nil, "floor")
	eq(select(2, K.wallPiece(cfg, 5, 0)), true, "north is a back wall")
	eq(select(2, K.wallPiece(cfg, 5, H + 1)), false, "south is not")
	eq(select(2, K.wallPiece(cfg, W + 1, 5)), false, "east is not")
end

-- ---------------------------------------------------------------- placing
local res = K.reserved(cfg)
ok(res["8,10"] and res["8,11"] and res["2,1"] and res["4,1"], "arrival, exit, depot, stash are kept free")
eq(K.reachProblem(cfg, {}), nil, "the empty room reaches every fixture")
local placed = {}
local function place(key, x, y, rot)
	local c = {key = key, x = x, y = y, rot = rot or 1}
	local p = K.placeProblem(cfg, "ashen_crypt", placed, c)
	if not p then
		c.id = K.nextId(placed)
		placed[#placed + 1] = c
	end
	return p
end
eq(place("ashen_throne", 8, 5), nil, "a throne in the middle")
eq(placed[1].id, 1, "first id")
ok(place("dead_tree", 8, 5):find("already stands", 1, true), "one object per tile")
eq(place("crimson_rug", 8, 5), nil, "a rug under the throne")
ok(place("woven_rug", 8, 5):find("rug there", 1, true), "one rug per tile")
ok(place("dead_tree", 8, 10):find("kept free", 1, true), "not on the arrival tile")
ok(place("dead_tree", 2, 1):find("depot", 1, true), "not on the depot")
ok(place("dead_tree", 1, 1):find("a light", 1, true), "not on a corner light")
ok(place("dead_tree", 0, 5):find("floor of the room", 1, true), "not in a wall")
ok(place("dead_tree", W + 1, 5):find("floor of the room", 1, true), "not in the east wall")
ok(place("unknown_thing", 3, 3):find("Unknown", 1, true), "unknown decoration")
-- walls: north and west only, the side picks the id
eq(place("crimson_tapestry", 5, 0), nil, "a tapestry on the north wall")
eq(place("crimson_tapestry", 0, 5), nil, "a tapestry on the west wall")
ok(place("crimson_tapestry", 5, 0):find("already hangs", 1, true), "one per wall tile")
ok(place("crimson_tapestry", W + 1, 3):find("north or the west", 1, true), "not on the east wall")
ok(place("crimson_tapestry", 0, 0):find("north or the west", 1, true), "not in the corner")
ok(place("crimson_tapestry", 5, 3):find("north or the west", 1, true), "not on the floor")
local tap = K.deco(cfg, "crimson_tapestry")
eq(K.parts(tap, 1, "n")[1][3], tap.wall.n, "north id")
eq(K.parts(tap, 1, "w")[1][3], tap.wall.w, "west id")
local occ = K.occupancy(cfg, placed)
ok(occ.wall["5,0"] and occ.wall["0,5"], "wall occupancy")
-- rotation
local throne = K.deco(cfg, "ashen_throne")
eq(K.rotCount(throne), 4, "four rotations")
eq(K.parts(throne, 3)[1][3], 1648, "rotation 3")
eq(K.rot(throne, 9), 1, "an unknown rotation is the first")
eq(K.rot(throne, "2"), 2, "rotation from text")
-- per decoration limit
eq(place("ashen_throne", 3, 5), nil, "second throne")
ok(place("ashen_throne", 4, 5):find("At most 2", 1, true), "max 2 thrones")
-- the path to the fixtures: a wall of blocking decorations around the depot (2,1) is refused at its last tile
do
	placed = {}
	eq(place("stone_table", 1, 2), nil, "table 1")
	eq(place("stone_table", 2, 2), nil, "table 2")
	eq(place("stone_table", 3, 2), nil, "table 3")
	local p = place("stone_table", 3, 1)
	ok(p and p:find("depot", 1, true), "the last tile that walls off the depot is refused: " .. tostring(p))
	-- a non-blocking decoration may go there
	eq(place("bone_pile", 3, 1), nil, "bones do not block")
	-- the exit: a line of blocking objects across the room is refused at its last tile (no limits for this check)
	local big = {}
	for k, v in pairs(cfg) do
		big[k] = v
	end
	big.defaultMax = 99
	big.themes = {{key = "ashen_crypt", name = "Big", maxDecor = 99, source = {type = "default"}}}
	big.decorations = {{key = "wall_block", name = "Block", cat = "furniture", layer = "object", ids = {1}, block = true,
		source = {type = "default"}}}
	big._decoIndex = nil
	local line, refused = {}, nil
	for x = 1, W do
		local c = {key = "wall_block", x = x, y = 9, rot = 1}
		local q = K.placeProblem(big, "ashen_crypt", line, c)
		if q then
			refused = q
		else
			c.id = K.nextId(line)
			line[#line + 1] = c
		end
	end
	ok(refused and refused:find("wall off", 1, true), "a line across the room is refused: " .. tostring(refused))
	eq(#line, W - 1, "the line keeps one gap")
end
-- a multi-tile decoration (synthetic): footprint, rotation, collision
do
	local c2 = {}
	for k, v in pairs(cfg) do
		c2[k] = v
	end
	c2.decorations = {{key = "bench", name = "Bench", cat = "furniture", layer = "object", block = true,
		rots = {{{0, 0, 10}, {1, 0, 11}}, {{0, 0, 12}, {0, 1, 13}}}, source = {type = "default"}}}
	c2._decoIndex = nil
	local pl = {}
	eq(K.placeProblem(c2, "ashen_crypt", pl, {key = "bench", x = W, y = 5, rot = 1}) ~= nil, true, "east part out of the room")
	eq(K.placeProblem(c2, "ashen_crypt", pl, {key = "bench", x = W, y = 5, rot = 2}), nil, "rotated it fits")
	pl[1] = {id = 1, key = "bench", x = 5, y = 5, rot = 1}
	ok(K.placeProblem(c2, "ashen_crypt", pl, {key = "bench", x = 6, y = 4, rot = 2}) ~= nil, "overlaps the second tile")
	eq(K.placeProblem(c2, "ashen_crypt", pl, {key = "bench", x = 5, y = 6, rot = 1}), nil, "below is free")
	eq(K.placeProblem(c2, "ashen_crypt", pl, {key = "bench", x = 6, y = 5, rot = 1}, 1), nil, "moving onto its own old tiles")
	ok(K.placeProblem(c2, "ashen_crypt", pl, {key = "bench", x = 7, y = 10, rot = 1}):find("kept free", 1, true),
		"second part on the arrival tile")
end
-- the theme limit
do
	placed = {}
	local x, y, count = 1, 3, 0
	while count < 40 do
		local p = place("bone_pile", x, y)
		if p and p:find("holds at most", 1, true) then
			break
		end
		if p and p:find("At most", 1, true) then
			-- the per-decoration limit: use rugs too
			p = place("crimson_rug", x, y)
		end
		count = count + 1
		x = x + 1
		if x > W then
			x, y = 1, y + 1
		end
	end
	local p = place("crimson_rug", 9, 7)
	ok(p and p:find("Ashen Crypt holds at most 24", 1, true), "theme limit: " .. tostring(p))
	eq(#placed, 24, "24 placed")
	eq(K.placeProblem(cfg, "veiled_sanctum", placed, {key = "woven_rug", x = 9, y = 7, rot = 1}), nil,
		"the Veiled Sanctum holds more")
	local _, total = K.occupancy(cfg, placed)
	eq(total, 24, "occupancy count")
	eq(K.nextId({{id = 1}, {id = 3}}), 2, "next id fills a gap")
end

-- ---------------------------------------------------------------- unlock sources
local function facts(t)
	t = t or {}
	return {achievement = function(id) return (t.ach or {})[id] == true end,
		stat = function(s) return (t.stats or {})[s] or 0 end,
		factionRank = function(f) return (t.ranks or {})[f] end,
		descent = t.descent or {best = 0, clear = false}, journey = t.journey, store = t.store or {}, earned = t.earned or {}}
end
local F0 = facts()
ok(K.owned(cfg, K.deco(cfg, "ashen_throne"), F0), "default: every character")
ok(not K.owned(cfg, K.deco(cfg, "hero_statue"), F0), "achievement missing")
ok(K.owned(cfg, K.deco(cfg, "hero_statue"), facts({ach = {level_300 = true}})), "achievement met")
ok(not K.owned(cfg, K.deco(cfg, "trophy_sovereign"), F0), "no kill, no trophy")
ok(K.owned(cfg, K.deco(cfg, "trophy_sovereign"), facts({stats = {raid_sovereign = 1}})), "the owner's kill")
ok(not K.owned(cfg, K.deco(cfg, "blighted_banner"), facts({stats = {invasion_defended = 4}})), "event: 4 of 5")
ok(K.owned(cfg, K.deco(cfg, "blighted_banner"), facts({stats = {invasion_defended = 5}})), "event: 5 of 5")
-- faction ranks: 5 = honored
ok(not K.owned(cfg, K.deco(cfg, "obelisk"), facts({ranks = {compact = 4}})), "trusted is not honored")
ok(K.owned(cfg, K.deco(cfg, "obelisk"), facts({ranks = {compact = 5}})), "honored")
ok(K.owned(cfg, K.deco(cfg, "obelisk"), facts({ranks = {compact = 7}})), "exalted is more")
ok(not K.owned(cfg, K.deco(cfg, "obelisk"), facts({ranks = {vigil = 7}})), "another faction")
ok(not K.owned(cfg, K.deco(cfg, "obelisk"), {}), "no faction system")
-- descent
ok(not K.owned(cfg, K.deco(cfg, "ember_basin"), facts({descent = {best = 8}})), "depth 8 of 9")
ok(K.owned(cfg, K.deco(cfg, "ember_basin"), facts({descent = {best = 9}})), "depth 9")
ok(not K.owned(cfg, K.deco(cfg, "trophy_descent"), facts({descent = {best = 12, clear = false}})), "deep but no boss")
ok(K.owned(cfg, K.deco(cfg, "trophy_descent"), facts({descent = {best = 12, clear = true}})), "boss slain")
-- journey: only when the system is there
ok(not K.owned(cfg, K.deco(cfg, "wayfarer_banner"), facts({journey = nil})), "no journey system")
ok(not K.owned(cfg, K.deco(cfg, "pilgrim_shrine"), facts({journey = 2})), "chapter 2 of 3")
ok(K.owned(cfg, K.deco(cfg, "pilgrim_shrine"), facts({journey = 3})), "chapter 3")
-- store: only by buying, never by any other fact
ok(not K.owned(cfg, K.deco(cfg, "gargoyle"), facts({ach = {level_300 = true}, stats = {raid_sovereign = 9}})), "store: not earned")
ok(K.owned(cfg, K.deco(cfg, "gargoyle"), facts({store = {gargoyle = true}})), "store: bought")
-- earned stays earned (a faction rank lost to the rival)
ok(K.owned(cfg, K.deco(cfg, "obelisk"), facts({ranks = {compact = 3}, earned = {obelisk = true}})), "kept once earned")
-- themes
ok(K.owned(cfg, K.theme(cfg, "ashen_crypt"), F0, true), "default theme")
ok(not K.owned(cfg, K.theme(cfg, "ember_forge"), F0, true), "Ember Forge locked")
ok(K.owned(cfg, K.theme(cfg, "ember_forge"), facts({descent = {best = 5}}), true), "Ember Forge at depth 5")
ok(K.owned(cfg, K.theme(cfg, "veiled_sanctum"), facts({earned = {["theme:veiled_sanctum"] = true}}), true), "earned theme key")
-- texts
local names = {achievement = {level_300 = "Veteran"}, faction = {compact = "The Cinderforge Compact"}, rank = {honored = "Honored"}}
eq(K.sourceText(cfg, K.deco(cfg, "hero_statue").source, names), "Achievement: Veteran", "achievement text")
eq(K.sourceText(cfg, K.deco(cfg, "obelisk").source, names), "The Cinderforge Compact: Honored", "faction text")
ok(K.sourceText(cfg, K.deco(cfg, "gargoyle").source):find("200 Chaos Coins", 1, true), "store text")
eq(K.sourceText(cfg, K.deco(cfg, "blighted_banner").source), "Defend 5 invasions", "event label")
eq(K.sourceGroup(K.deco(cfg, "trophy_sovereign").source), "trophy", "trophy group")
eq(K.sourceGroup(K.deco(cfg, "blighted_banner").source), "event", "event group")
-- the catalogue view
do
	local rows = K.catalogueView(cfg, facts({store = {gargoyle = true}}), {{id = 1, key = "ashen_throne", x = 3, y = 3, rot = 1}}, names,
		function(id) return id + 100000 end)
	eq(#rows, #cfg.decorations, "one row per decoration")
	local byKey = {}
	for _, r in ipairs(rows) do
		byKey[r.key] = r
	end
	eq(byKey.ashen_throne.placed, 1, "placed count")
	eq(byKey.ashen_throne.rots[2][1][3], 1647 + 100000, "client ids")
	eq(byKey.gargoyle.owned, true, "bought")
	eq(byKey.gargoyle.price, 200, "price")
	eq(byKey.crimson_tapestry.wallW[1][3], 1868 + 100000, "west wall id")
	eq(byKey.crimson_tapestry.rots.w, nil, "no stray key in rots")
	eq(byKey.hero_statue.owned, false, "locked")
	ok(byKey.trophy_sovereign.trophy, "trophy flag")
	local lv = K.layoutView(cfg)
	eq(lv.w, W, "layout w")
	ok(#lv.reserved >= 8, "reserved list")
end

-- ---------------------------------------------------------------- access
ok(K.mayVisit(0, {self = true}), "owner always")
ok(not K.mayVisit(0, {vip = true, party = true, guild = true}), "private: nobody else")
ok(K.mayVisit(0, {staff = true}), "staff")
ok(K.mayVisit(1, {vip = true}), "friends: VIP")
ok(K.mayVisit(1, {party = true}), "friends: party")
ok(not K.mayVisit(1, {guild = true}), "friends: not the guild")
ok(K.mayVisit(2, {guild = true}), "guild")
ok(K.mayVisit(2, {vip = true}), "guild includes friends")
ok(not K.mayVisit(2, {}), "guild: strangers out")
ok(K.mayVisit(3, {}), "public")
local okV, why = K.mayVisit(3, {realmMismatch = true})
ok(not okV and why:find("Season", 1, true), "season and standard never mix")
okV, why = K.mayVisit(0, {})
eq(why, "That hideout is private.", "private text")
eq(K.enterProblem({}), nil, "free to enter")
ok(K.enterProblem({inFight = true}):find("fight", 1, true), "in a fight")
ok(K.enterProblem({pzLocked = true}), "pz-locked")
ok(K.enterProblem({skull = true}), "skull")
ok(K.enterProblem({rift = true}):find("own exit", 1, true), "inside a rift")
ok(K.enterProblem({full = true}):find("in use", 1, true), "every slot in use")

-- ---------------------------------------------------------------- likes, visits, showcase
eq(K.likeProblem({inside = true, today = 0, perDay = 10}), nil, "a like")
ok(K.likeProblem({self = true, inside = true}), "own account")
ok(K.likeProblem({inside = false}), "only from inside")
ok(K.likeProblem({inside = true, already = true}), "once per hideout")
ok(K.likeProblem({inside = true, today = 10, perDay = 10}), "daily cap")
ok(K.countsVisit(nil, 20261011), "first visit counts")
ok(not K.countsVisit(20261011, 20261011), "same day: once")
ok(K.countsVisit(20261010, 20261011), "next day counts again")
do
	local rows = {{name = "b", likes = 5, visits = 1}, {name = "a", likes = 5, visits = 1}, {name = "c", likes = 2, visits = 9},
		{name = "d", likes = 5, visits = 3}}
	local byLikes = K.showcase(rows, "likes", 3)
	eq(#byLikes, 3, "limit")
	eq(byLikes[1].name, "d", "likes, then visits")
	eq(byLikes[2].name, "a", "then the name")
	eq(K.showcase(rows, "visits")[1].name, "c", "by visits")
	eq(#rows, 4, "the input is not changed")
end

-- ---------------------------------------------------------------- slot pool
do
	local small = {grid = {maxSlots = 3}}
	local pool = K.poolNew(small)
	local s1, fresh = K.poolAcquire(pool, 101)
	eq(s1, 1, "first slot")
	eq(fresh, true, "fresh")
	local again, fresh2 = K.poolAcquire(pool, 101)
	eq(again, 1, "the same owner keeps its slot")
	eq(fresh2, false, "not fresh")
	-- slot 2 is unusable (a map tile): skipped for good
	local calls = 0
	local s2 = K.poolAcquire(pool, 102, function(s)
		calls = calls + 1
		return s ~= 2
	end)
	eq(s2, 3, "slot 2 skipped")
	eq(K.poolAcquire(pool, 103), nil, "full")
	eq(K.poolUsed(pool), 2, "two in use")
	eq(K.poolRelease(pool, 1), 101, "release returns the owner")
	eq(K.poolSlotOf(pool, 101), nil, "the owner has no slot now")
	eq(K.poolAcquire(pool, 103), 1, "a released slot is reused")
	eq(K.poolOwnerOf(pool, 1), 103, "new owner")
	eq(K.poolRelease(pool, 2), nil, "releasing a free slot")
end

-- ---------------------------------------------------------------- the store category
do
	local cat = dofile("data/scripts/chaos/hideout_store.lua")()
	eq(cat.name, "Hideout Decorations", "category name")
	local count = 0
	for _, d in ipairs(cfg.decorations) do
		if d.source.type == "store" then
			count = count + 1
		end
	end
	eq(#cat.offers, count, "one offer per store decoration")
	ok(count >= 8, "a few store decorations")
	for _, o in ipairs(cat.offers) do
		eq(o.kind, "unlock", "unlock offer")
		eq(o.gift, true, "giftable")
		ok(o.unlock:match("^hideout_"), "unlock key")
		ok(o.description:find("Cosmetic only", 1, true), "says cosmetic")
		ok(type(o.icon) == "number", "icon")
	end
	local inShop = false
	for _, c in ipairs(shop.categories) do
		if c.name == "Hideout Decorations" then
			inShop = true
		end
	end
	ok(inShop, "the store has the category")
	-- the store's generic rules still refuse every other unlock as a gift
	ok(not ChaosShopCore.GIFTABLE.unlock, "unlocks stay outside GIFTABLE")
	dofile("data/scripts/chaos/season_core.lua")
	local rules = dofile("data/scripts/chaos/season_config.lua").store
	eq(ChaosSeason.storeRefusal(cat.offers[1], rules), nil, "season characters may buy hideout decorations")
end

-- =====================================================================================================================
-- hideout.lua on a mocked engine
-- =====================================================================================================================
local events, globals, talks, actions, moves = {}, {}, {}, {}, {}
function CreatureEvent(name)
	local o = {name = name}
	function o:type() end
	function o:register() events[name] = o end
	return o
end
function GlobalEvent(name)
	local o = {}
	function o:interval() end
	function o:register() globals[name] = o end
	return o
end
function TalkAction(w)
	local o = {}
	function o:separator() end
	function o:register() talks[w] = o end
	return o
end
function Action()
	local o = {}
	function o:aid(a) self.a = a end
	function o:register() actions[self.a] = o end
	return o
end
function MoveEvent()
	local o = {}
	function o:type() end
	function o:aid(a) self.a = a end
	function o:register() moves[self.a] = o end
	return o
end
local callbacks = {}
EventCallback = setmetatable({register = function() end}, {__newindex = function(_, k, v) callbacks[k] = v end})

local sent, reqs = {}, {}
json = {encode = function(t) sent[#sent + 1] = t; return "#" .. #sent end,
	decode = function(s) return reqs[tonumber((s:gsub("^req", "")))] end}

local function pkey(p) return p.x .. "," .. p.y .. "," .. p.z end
Position = function(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function() end}
end
local tiles, mapTiles = {}, {}
local function newItem(id, tile)
	local it = {id = id, aid = 0, attrs = {}, tile = tile}
	function it:getId() return self.id end
	function it:getActionId() return self.aid end
	function it:setActionId(a) self.aid = a end
	function it:setAttribute(k, v) self.attrs[k] = v end
	function it:transform(to) self.id = to end
	function it:remove()
		local t = self.tile
		if not t then return true end
		for i, x in ipairs(t.items) do
			if x == self then
				table.remove(t.items, i)
				break
			end
		end
		self.tile = nil
		return true
	end
	function it:getPosition() return self.tile.pos end
	function it:unserializeAttributes(s) self.depotId = s:byte(2) + s:byte(3) * 256; return s:byte(1) == 10 end
	return it
end
local function newTile(pos)
	local t = {pos = pos, items = {}}
	function t:getGround() return self.ground end
	function t:getItemById(id)
		if self.ground and self.ground.id == id then return self.ground end
		for _, it in ipairs(self.items) do if it.id == id then return it end end
	end
	function t:getItems() local l = {}; for i, x in ipairs(self.items) do l[i] = x end; return l end
	function t:addItemEx(it) it.tile = self; self.items[#self.items + 1] = it end
	function t:getHouse() return nil end
	function t:hasProperty() return false end
	function t:getItemByType() return nil end
	tiles[pkey(pos)] = t
	return t
end
function Tile(pos) return tiles[pkey(pos)] end
local createdTiles = 0
Game = {
	createTile = function(pos) createdTiles = createdTiles + 1; return tiles[pkey(pos)] or newTile(pos) end,
	createItem = function(id, c, pos)
		if not pos then return newItem(id, nil) end
		local t = tiles[pkey(pos)]
		if not t then return nil end
		local it = newItem(id, t)
		if not t.ground and (id == 413 or id == 407 or id == 406 or id == 4526 or (id >= 30484 and id <= 30600)) then
			t.ground = it
		else
			t.items[#t.items + 1] = it
		end
		return it
	end,
	getTowns = function() return {} end,
	getSpectators = function(pos, _, _, rx, _, ry)
		local out = {}
		for _, pl in pairs(Game._players) do
			if math.abs(pl.pos.x - pos.x) <= rx and math.abs(pl.pos.y - pos.y) <= ry and pl.pos.z == pos.z then
				out[#out + 1] = pl
			end
		end
		return out
	end,
	_players = {}
}
function ItemType(id) return {getClientId = function() return id + 1 end} end

-- a tiny database: the tables of hideout.lua, players, the VIP list, guild members
local DB = {hideouts = {}, decor = {}, unlocks = {}, visits = {}, likes = {}, players = {}, vip = {}, guilds = {}}
local queries = {}
db = {
	escapeString = function(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end,
	query = function(q)
		queries[#queries + 1] = q
		local g, th, perm = q:match("INSERT INTO `chaos_hideouts` %(`player_id`, `theme`, `permission`, `updated_at`%) VALUES %((%d+), '([^']*)', (%d+)")
		if g then
			local r = DB.hideouts[tonumber(g)] or {visits = 0, likes = 0}
			r.theme, r.permission = th, tonumber(perm)
			DB.hideouts[tonumber(g)] = r
			return true
		end
		local col, g2 = q:match("INSERT INTO `chaos_hideouts` %(`player_id`, `theme`, `permission`, `(%a+)`, `updated_at`%) VALUES %((%d+)")
		if col then
			local r = DB.hideouts[tonumber(g2)]
			if r then r[col] = (r[col] or 0) + 1 else DB.hideouts[tonumber(g2)] = {theme = "", permission = 1, visits = 0, likes = 0, [col] = 1} end
			return true
		end
		local pg, did, key, x, y, rot = q:match("INSERT INTO `chaos_hideout_decor` .- VALUES %((%d+), (%d+), '([%w_]+)', (%d+), (%d+), (%d+)%)")
		if pg then
			DB.decor[#DB.decor + 1] = {player_id = tonumber(pg), decor_id = tonumber(did), decor = key, x = tonumber(x), y = tonumber(y), rot = tonumber(rot)}
			return true
		end
		local ux, uy, ur, upg, uid = q:match("UPDATE `chaos_hideout_decor` SET `x` = (%d+), `y` = (%d+), `rot` = (%d+) WHERE `player_id` = (%d+) AND `decor_id` = (%d+)")
		if ux then
			for _, r in ipairs(DB.decor) do
				if r.player_id == tonumber(upg) and r.decor_id == tonumber(uid) then r.x, r.y, r.rot = tonumber(ux), tonumber(uy), tonumber(ur) end
			end
			return true
		end
		local dpg, ddid = q:match("DELETE FROM `chaos_hideout_decor` WHERE `player_id` = (%d+) AND `decor_id` = (%d+)")
		local dall = q:match("DELETE FROM `chaos_hideout_decor` WHERE `player_id` = (%d+)$")
		if dpg or dall then
			for i = #DB.decor, 1, -1 do
				local r = DB.decor[i]
				if r.player_id == tonumber(dpg or dall) and (not ddid or r.decor_id == tonumber(ddid)) then table.remove(DB.decor, i) end
			end
			return true
		end
		local ua, up, uk, us = q:match("INSERT IGNORE INTO `chaos_hideout_unlocks` .- VALUES %((%d+), (%d+), '([^']+)', '?([%w]*)'?")
		if ua then
			local k = ua .. ":" .. up .. ":" .. uk
			DB.unlocks[k] = DB.unlocks[k] or {account_id = tonumber(ua), player_id = tonumber(up), unlock_key = uk, source = us}
			return true
		end
		local vo, vv, vd = q:match("INSERT INTO `chaos_hideout_visits` .- VALUES %((%d+), (%d+), (%d+)")
		if vo then
			DB.visits[vo .. ":" .. vv] = {owner_id = tonumber(vo), visitor_id = tonumber(vv), day = tonumber(vd), visited_at = os.time()}
			return true
		end
		local lo, la = q:match("INSERT IGNORE INTO `chaos_hideout_likes` .- VALUES %((%d+), (%d+)")
		if lo then
			DB.likes[lo .. ":" .. la] = DB.likes[lo .. ":" .. la] or {owner_id = tonumber(lo), account_id = tonumber(la), liked_at = os.time()}
			return true
		end
		return true
	end,
	storeQuery = function() return nil end,
	asyncQuery = function() end
}
-- Chaos.select answers from DB
local function select(q)
	local g = q:match("FROM `chaos_hideouts` WHERE `player_id` = (%d+)")
	if g then
		local r = DB.hideouts[tonumber(g)]
		return r and {{theme = r.theme, permission = r.permission, visits = r.visits, likes = r.likes}} or {}
	end
	g = q:match("FROM `chaos_hideout_decor` WHERE `player_id` = (%d+)")
	if g then
		local out = {}
		for _, r in ipairs(DB.decor) do if r.player_id == tonumber(g) then out[#out + 1] = r end end
		table.sort(out, function(a, b) return a.decor_id < b.decor_id end)
		return out
	end
	local a, p = q:match("FROM `chaos_hideout_unlocks` WHERE `account_id` = (%d+) AND `player_id` IN %(0, (%d+)%)")
	if a then
		local out = {}
		for _, r in pairs(DB.unlocks) do
			if r.account_id == tonumber(a) and (r.player_id == 0 or r.player_id == tonumber(p)) then out[#out + 1] = r end
		end
		return out
	end
	local sa, sk = q:match("FROM `chaos_hideout_unlocks` WHERE `account_id` = (%d+) AND `player_id` = 0 AND `unlock_key` = '([^']+)'")
	if sa then
		local r = DB.unlocks[sa .. ":0:" .. sk]
		return r and {r} or {}
	end
	g = q:match("SELECT `name` FROM `players` WHERE `id` = (%d+)")
	if g then
		local r = DB.players[tonumber(g)]
		return r and {{name = r.name}} or {}
	end
	g = q:match("SELECT `account_id` FROM `players` WHERE `id` = (%d+)")
	if g then
		local r = DB.players[tonumber(g)]
		return r and {{account_id = r.account}} or {}
	end
	g = q:match("SELECT `town_id` FROM `players` WHERE `id` = (%d+)")
	if g then
		return {{town_id = 3}}
	end
	local va, vp = q:match("FROM `account_viplist` WHERE `account_id` = (%d+) AND `player_id` = (%d+)")
	if va then
		return DB.vip[va .. ":" .. vp] and {{player_id = tonumber(vp)}} or {}
	end
	va = q:match("FROM `account_viplist` WHERE `account_id` = (%d+) LIMIT")
	if va then
		local out = {}
		for k in pairs(DB.vip) do
			local acc, pid = k:match("(%d+):(%d+)")
			if acc == va then out[#out + 1] = {player_id = tonumber(pid)} end
		end
		return out
	end
	g = q:match("SELECT `guild_id` FROM `guild_membership` WHERE `player_id` = (%d+)")
	if g then
		local gid = DB.guilds[tonumber(g)]
		return gid and {{guild_id = gid}} or {}
	end
	g = q:match("SELECT `player_id` FROM `guild_membership` WHERE `guild_id` = (%d+)")
	if g then
		local out = {}
		for pid, gid in pairs(DB.guilds) do if gid == tonumber(g) then out[#out + 1] = {player_id = pid} end end
		return out
	end
	local vo, vv = q:match("SELECT `day` FROM `chaos_hideout_visits` WHERE `owner_id` = (%d+) AND `visitor_id` = (%d+)")
	if vo then
		local r = DB.visits[vo .. ":" .. vv]
		return r and {{day = r.day}} or {}
	end
	if q:find("FROM `chaos_hideout_visits` v JOIN", 1, true) then
		local vid = tonumber(q:match("`visitor_id` = (%d+)"))
		local out = {}
		for _, r in pairs(DB.visits) do
			if r.visitor_id == vid then out[#out + 1] = {owner_id = r.owner_id, name = DB.players[r.owner_id].name, visited_at = r.visited_at} end
		end
		return out
	end
	local la = q:match("SELECT COUNT%(%*%) AS `n` FROM `chaos_hideout_likes` WHERE `account_id` = (%d+)")
	if la then
		local c = 0
		for _, r in pairs(DB.likes) do if r.account_id == tonumber(la) then c = c + 1 end end
		return {{n = c}}
	end
	local lo, la2 = q:match("FROM `chaos_hideout_likes` WHERE `owner_id` = (%d+) AND `account_id` = (%d+)")
	if lo then
		return DB.likes[lo .. ":" .. la2] and {{owner_id = tonumber(lo)}} or {}
	end
	if q:find("FROM `chaos_hideouts` h JOIN `players` p", 1, true) then
		local out = {}
		for pid, r in pairs(DB.hideouts) do
			if r.permission == 3 then
				out[#out + 1] = {player_id = pid, name = DB.players[pid].name, theme = r.theme, likes = r.likes, visits = r.visits}
			end
		end
		return out
	end
	return {}
end

-- players
local players = {}
local nextCid = 0x10000000
local function newPlayer(guid, name, account, pos)
	nextCid = nextCid + 1
	local p = {cid = nextCid, guid = guid, name = name, account = account, pos = pos or {x = 100, y = 100, z = 7}, st = {}, msgs = {},
		sends = {}, events = {}, group = 1, infight = false, pz = false}
	function p:getId() return self.cid end
	function p:getGuid() return self.guid end
	function p:getName() return self.name end
	function p:getAccountId() return self.account end
	function p:getPosition() return Position(self.pos.x, self.pos.y, self.pos.z) end
	function p:teleportTo(q) self.pos = {x = q.x, y = q.y, z = q.z} end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function p:sendCancelMessage(t) self.msgs[#self.msgs + 1] = t end
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:setStorageValue(k, v) self.st[k] = v end
	function p:getGroup() local me = self; return {getId = function() return me.group end, getAccess = function() return me.group >= 4 end} end
	function p:getTown() return {getId = function() return 2 end, getTemplePosition = function() return Position(50, 50, 7) end} end
	function p:getGuild() local gid = DB.guilds[self.guid]; return gid and {getId = function() return gid end} or nil end
	function p:getParty() return self.party end
	function p:isPzLocked() return self.pz end
	function p:getCondition(c) return (c == CONDITION_INFIGHT and self.infight) and {} or nil end
	function p:getSkull() return 0 end
	function p:registerEvent(e) self.events[e] = true end
	function p:sendExtendedOpcode(op, payload) self.sends[#self.sends + 1] = payload; return true end
	function p:isPlayer() return true end
	function p:getPlayer() return self end
	players[guid] = p
	Game._players[guid] = p
	DB.players[guid] = {name = name, account = account}
	newTile(p.pos).ground = newItem(100, nil)
	return p
end
function Player(x)
	if type(x) == "string" then
		for _, p in pairs(players) do if p.name == x then return p end end
		return nil
	end
	return players[x]
end
local achievementStats = {}
ChaosAchievements = {has = function(player, id) return id == "rift_t5" end, stats = achievementStats,
	data = {list = {{id = "rift_t5", name = "Rift Diver"}}}}

Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.select = select
ChaosRateLimit = nil
ChaosDarkTiles = {id = function(name, fallback) return fallback end}
dofile("data/scripts/chaos/hideout.lua")
local M = ChaosHideout
globals.ChaosHideoutStartup.onStartup()

local function req(p, action, data)
	local before = #sent
	reqs[#reqs + 1] = {action = action, data = data or {}}
	events.ChaosHideoutOpcode.onExtendedOpcode(p, cfg.opcode, "req" .. #reqs)
	local res
	for i = before + 1, #sent do
		if sent[i].action == "result" then res = sent[i].data end
	end
	return res
end
local function lastState()
	for i = #sent, 1, -1 do
		if sent[i].action == "state" then return sent[i].data end
	end
end
local function itemsAt(slot, gx, gy)
	local t = Tile(K.toWorld(cfg, slot, gx, gy))
	return t and t.items or {}
end
local function hasItem(slot, gx, gy, id)
	for _, it in ipairs(itemsAt(slot, gx, gy)) do
		if it.id == id then return it end
	end
	return nil
end

local ana = newPlayer(1, "Ana", 10)
local bo = newPlayer(2, "Bo", 20)
local cy = newPlayer(3, "Cy", 30)
events.ChaosHideoutLogin.onLogin(ana)
ok(ana.events.ChaosHideoutOpcode, "opcode event registered at login")

-- open: the catalogue, themes and permissions
req(ana, "open")
local st = lastState()
eq(st.open, true, "window opens")
eq(st.hideout.theme, "ashen_crypt", "default theme")
eq(st.hideout.perm, 1, "default permission: friends")
eq(#st.catalogue, #cfg.decorations, "catalogue")
eq(st.inside, nil, "not inside")
-- the achievement source was kept as an earned unlock
ok(DB.unlocks["10:1:skull_pillar"], "earned unlock stored (rift_t5)")

-- refused in a fight
ana.infight = true
local r = req(ana, "enter")
ok(r and not r.ok and r.text:find("fight", 1, true), "no entry in a fight")
ana.infight = false

-- enter: a slot is built and furnished
r = req(ana, "enter")
ok(r == nil or r.ok, "enter")
local slot = K.poolSlotOf(M.pool, 1)
eq(slot, 1, "slot 1")
local arrival = K.toWorld(cfg, 1, cfg.fixtures.arrival[1], cfg.fixtures.arrival[2])
eq(ana.pos.x, arrival.x, "arrival x")
eq(ana.pos.y, arrival.y, "arrival y")
eq(ana.st[cfg.storage.returnSet], 1, "return spot saved")
eq(ana.st[cfg.storage.returnX], 100, "return x")
ok(createdTiles >= (W + 2) * (H + 2), "tiles created")
ok(hasItem(1, 0, 0, 1052), "north-west corner piece")
ok(hasItem(1, 5, 0, 1050), "north wall: horizontal piece")
ok(hasItem(1, 0, 5, 1049), "west wall: vertical piece")
ok(hasItem(1, W + 1, H + 1, 1051), "south-east post")
ok(hasItem(1, 5, H + 1, 1050), "south wall: horizontal piece")
eq(Tile(K.toWorld(cfg, 1, 5, 5)).ground.id, 413, "ground of the default theme")
ok(hasItem(1, cfg.fixtures.exit[1], cfg.fixtures.exit[2], cfg.ids.portal), "exit portal")
local locker = hasItem(1, cfg.fixtures.depot[1], cfg.fixtures.depot[2], cfg.ids.depot)
ok(locker, "depot locker")
eq(locker.depotId, 2, "the locker opens the owner's home town depot")
ok(hasItem(1, cfg.fixtures.stash[1], cfg.fixtures.stash[2], cfg.ids.stash), "stash")
ok(hasItem(1, 1, 1, 1481), "corner light")
ok(M.isInside(ana:getPosition()), "isInside")

-- place, rotate, move, remove
r = req(ana, "place", {key = "ashen_throne", x = 8, y = 4, r = 2})
ok(r.ok, "placed: " .. r.text)
ok(hasItem(1, 8, 4, 1647), "the throne item, rotation 2")
eq(hasItem(1, 8, 4, 1647).aid, cfg.aid.decor, "decoration action id")
eq(#DB.decor, 1, "stored")
r = req(ana, "place", {key = "dead_tree", x = 8, y = 4})
ok(not r.ok, "collision refused")
r = req(ana, "place", {key = "hero_statue", x = 3, y = 4})
ok(not r.ok and r.text:find("locked", 1, true), "locked decoration refused: " .. r.text)
r = req(ana, "place", {key = "crimson_tapestry", x = 0, y = 3})
ok(r.ok, "west wall tapestry")
ok(hasItem(1, 0, 3, 1868), "west wall id")
r = req(ana, "move", {id = 1, x = 10, y = 6, r = 4})
ok(r.ok, "moved")
ok(not hasItem(1, 8, 4, 1647), "old place empty")
ok(hasItem(1, 10, 6, 1649), "new place, rotation 4")
eq(DB.decor[1].x, 10, "move stored")
st = lastState()
eq(st.inside.isOwner, true, "inside own hideout")
eq(st.hideout.count, 2, "two decorations")
eq(st.inside.origin.x, 12288, "origin for the client")
-- a trophy names the owner's kills
achievementStats[1] = {raid_sovereign = 3}
r = req(ana, "place", {key = "trophy_sovereign", x = 12, y = 8})
ok(r.ok, "trophy placed")
local tro = hasItem(1, 12, 8, 1445)
ok(tro and tro.attrs[ITEM_ATTRIBUTE_DESCRIPTION]:find("slain 3 times", 1, true), "trophy text")
r = req(ana, "remove", {id = 3})
ok(r.ok and not hasItem(1, 12, 8, 1445), "removed")

-- a store decoration: bought, then placed; gifts go through the same grant
local unlock = M.storeUnlock("hideout_gargoyle")
ok(unlock, "store unlock entry")
eq(M.storeUnlock("hideout_ashen_throne"), nil, "earned decorations are not sold")
eq(M.storeUnlock("cosmetic_x"), nil, "other unlocks are not ours")
eq(unlock.owned(ana), false, "not owned")
ok(unlock.grant(bo), "granted to Bo's account (a gift)")
eq(unlock.owned(bo), true, "Bo owns it")
eq(unlock.owned(ana), false, "Ana still does not")
ok(unlock.grant(ana), "Ana buys it")
r = req(ana, "place", {key = "gargoyle", x = 4, y = 6})
ok(r.ok, "store decoration placed")

-- themes
r = req(ana, "theme", {key = "ember_forge"})
ok(not r.ok and r.text:find("Ember Descent", 1, true), "locked theme: " .. r.text)
DB.unlocks["10:1:theme:veiled_sanctum"] = {account_id = 10, player_id = 1, unlock_key = "theme:veiled_sanctum"}
r = req(ana, "theme", {key = "veiled_sanctum"})
ok(r.ok, "theme changed")
eq(Tile(K.toWorld(cfg, 1, 5, 5)).ground.id, 406, "ground changed in place")
ok(hasItem(1, 0, 0, 1114) and hasItem(1, 5, H + 1, 1112) and hasItem(1, W + 1, 4, 1111), "walls changed piece by piece")
ok(hasItem(1, 1, 1, 9439) and not hasItem(1, 1, 1, 1481), "lights changed")
eq(DB.hideouts[1].theme, "veiled_sanctum", "theme stored")

-- visitors: friends (VIP), guild, public
r = req(bo, "visit", {guid = 1})
ok(r and not r.ok, "Bo is no friend yet")
DB.vip["10:2"] = true
r = req(bo, "visit", {guid = 1})
ok(r == nil or r.ok, "Bo visits as a VIP")
eq(K.fromWorld(cfg, bo:getPosition()), 1, "Bo in Ana's hideout")
eq(DB.hideouts[1].visits, 1, "a visit counted")
req(bo, "leave")
req(bo, "visit", {guid = 1})
eq(DB.hideouts[1].visits, 1, "the same day counts once")
-- likes: inside, once per account
r = req(bo, "like", {owner = 1})
ok(r.ok, "Bo likes it")
eq(DB.hideouts[1].likes, 1, "like stored")
r = req(bo, "like", {owner = 1})
ok(not r.ok, "once")
r = req(cy, "like", {owner = 1})
ok(not r.ok and r.text:find("Visit", 1, true), "only from inside")
-- Bo cannot decorate Ana's room
r = req(bo, "place", {key = "ashen_throne", x = 3, y = 3})
ok(not r.ok, "visitors do not decorate")
-- private: Bo is sent out at once
r = req(ana, "perm", {level = 0})
ok(r.ok, "private")
eq(K.fromWorld(cfg, bo:getPosition()), nil, "Bo was sent out")
eq(bo.pos.x, 100, "back where Bo came from")
-- guild
DB.guilds[1], DB.guilds[3] = 7, 7
req(ana, "perm", {level = 2})
r = req(cy, "visit", {guid = 1})
ok(r == nil or r.ok, "guild member visits")
-- the visit list
req(bo, "visits")
local vis
for i = #sent, 1, -1 do if sent[i].action == "visits" then vis = sent[i].data break end end
eq(#vis.friends, 0, "Bo's VIP list is empty (Ana's list has Bo)")
DB.vip["20:1"] = true
req(cy, "leave")
req(bo, "visits")
for i = #sent, 1, -1 do if sent[i].action == "visits" then vis = sent[i].data break end end
eq(#vis.friends, 1, "Ana is in Bo's list")
eq(vis.friends[1].name, "Ana", "Ana listed")
eq(#vis.recent, 1, "Bo's recent visit")
req(ana, "perm", {level = 3})
req(bo, "visits")
for i = #sent, 1, -1 do if sent[i].action == "visits" then vis = sent[i].data break end end
eq(vis.showcase.likes[1].name, "Ana", "showcase")

-- no PvP inside; items dropped inside go back; decorations cannot be pushed
eq(callbacks.onTargetCombat(ana, bo), RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "no pvp inside")
local dropped = {aid = 0, getActionId = function() return 0 end, getTopParent = function() return nil end}
function dropped:moveTo(to) self.movedTo = to end
callbacks.onItemMoved(ana, dropped, 1, Position(1, 1, 7), K.toWorld(cfg, 1, 5, 5), nil, nil)
eq(dropped.movedTo, ana, "dropped item back to the player")
local throneItem = hasItem(1, 10, 6, 1649)
function throneItem:moveTo(to) self.backTo = to end
local fromP = K.toWorld(cfg, 1, 10, 6)
callbacks.onItemMoved(ana, throneItem, 1, fromP, K.toWorld(cfg, 1, 11, 6), nil, nil)
eq(throneItem.backTo, fromP, "a decoration goes back")

-- the depot: owner only
eq(actions[cfg.aid.depot].onUse(bo, locker), true, "visitors cannot open the owner's depot")
eq(actions[cfg.aid.depot].onUse(ana, locker), false, "the engine opens the owner's depot")
eq(actions[cfg.aid.decor].onUse(ana, throneItem), true, "decorations do nothing on use")

-- the Town Portal is refused inside (townportal_core.lua)
dofile("data/scripts/chaos/townportal_core.lua")
ok(ChaosTownPortalCore.blockReason({hideout = true}):find("hideout", 1, true), "no town portal inside")

-- leave and teardown after emptySeconds; the slot goes back to the pool
moves[cfg.aid.exit].onStepIn(ana, nil, ana:getPosition(), ana:getPosition())
eq(ana.pos.x, 100, "exit leads back")
eq(ana.st[cfg.storage.returnSet], 0, "return spot used")
local realTime = os.time
local clock = realTime()
os.time = function(t) if t then return realTime(t) end return clock end
globals.ChaosHideoutThink.onThink(3000)
ok(M.rooms[1], "still up right after")
clock = clock + cfg.emptySeconds + 1
globals.ChaosHideoutThink.onThink(3000)
eq(M.rooms[1], nil, "torn down")
eq(K.poolSlotOf(M.pool, 1), nil, "slot released")
eq(#itemsAt(1, 10, 6), 0, "decorations gone")
eq(#itemsAt(1, 0, 0), 1, "only the wall stays")
-- the next owner reuses the slot (tiles are not created again)
local tilesBefore = createdTiles
r = req(bo, "enter")
eq(K.poolSlotOf(M.pool, 2), 1, "slot reused")
eq(createdTiles, tilesBefore, "no new tiles")
eq(Tile(K.toWorld(cfg, 1, 5, 5)).ground.id, 413, "Bo's room has Bo's theme")
ok(not hasItem(1, 4, 6, 1452), "Ana's decorations are not in Bo's room")
-- a second owner gets the next slot while the first is up
r = req(ana, "enter")
eq(K.poolSlotOf(M.pool, 1), 2, "Ana in slot 2")
ok(hasItem(2, 4, 6, 1452), "Ana's gargoyle rebuilt from the database")
eq(Tile(K.toWorld(cfg, 2, 5, 5)).ground.id, 406, "Ana's theme rebuilt")
-- login inside a hideout: sent out
ana.pos = {x = 12288 + 32 + 5, y = 12288 + 5, z = 7}
ana.st[cfg.storage.returnSet] = 0
events.ChaosHideoutLogin.onLogin(ana)
eq(ana.pos.x, 50, "login inside: to the temple")
-- clear
r = req(ana, "clear")
ok(r.ok, "clear")
eq(#select("FROM `chaos_hideout_decor` WHERE `player_id` = 1"), 0, "nothing stored")
-- staff command
cy.group = 5
cy.pos = {x = 100, y = 100, z = 7}
req(ana, "perm", {level = 0})
talks["/hideout"].onSay(cy, "/hideout", "Ana")
eq(K.fromWorld(cfg, cy:getPosition()), 2, "staff may enter a private hideout")

os.time = realTime
print(string.format("hideout_test: %d checks OK", checks))
