-- Run from the server/ folder: luajit tests/spectate_test.lua (or lua5.3; CI runs both)
-- Live spectator (spectate_core.lua, spectate.lua): the watch (start, renew, end), a tile's items in drawing order
-- (ground, top items, other items oldest first, the newest kept when there are too many), the creatures (look, item
-- looks, health %, direction, ghosts and invisible ones left out), the snapshot's area and stats, its shape (only
-- arrays and objects, as the server's json encodes them), and the engine file against a mocked engine (the poll, the
-- file written through .tmp, an offline name, the watch's end). Made-up names only.
local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/spectate_core.lua")
local K = ChaosSpectateCore
local cfg = dofile("data/scripts/chaos/spectate_config.lua")

-- ================================================================== names and the watch
for _, good in ipairs({"Bob", "Gm Ana", "Sir O'Neil", "Anna-Lee"}) do
	check(K.isName(good), "a name: " .. good)
end
for _, bad in ipairs({"", "ab", "1abc", "Bob;ls", "Bob$(id)", "Bob\n", string.rep("a", 30), 42}) do
	check(not K.isName(bad), "not a name: " .. tostring(bad):gsub("%c", "?"))
end
local st = {}
eq(K.active(st, 100), nil, "no watch at first")
eq(K.watch(st, "Bob", 100, cfg), true, "the first line starts a watch")
eq(K.active(st, 110), "Bob", "it lasts")
eq(K.watch(st, "bob", 110, cfg), false, "the same name (any case) renews it")
eq(K.active(st, 110 + cfg.watchSeconds), "bob", "renewed: it lasts watchSeconds from the renewal")
eq(K.active(st, 111 + cfg.watchSeconds), nil, "then it ends")
eq(st.name, nil, "and is forgotten")
eq(K.watch(st, "Bob", 200, cfg), true, "after the end a line starts a new watch")
eq(K.watch(st, "Alice", 201, cfg), true, "another name starts a new watch")
eq(K.active(st, 202), "Alice", "the newest name wins")

-- ================================================================== a mocked world
local function item(id, sub)
	return {kind = "item", id = id, sub = sub, getId = function(self) return self.id end}
end
local nextId = 1000
local function creature(t)
	nextId = nextId + 1
	t.cid = t.cid or nextId
	t.getId = function(self) return self.cid end
	t.getName = function(self) return self.name end
	t.getOutfit = function(self) return self.outfit end
	t.getDirection = function(self) return self.dir or 2 end
	t.getHealth = function(self) return self.hp end
	t.getMaxHealth = function(self) return self.maxhp end
	t.getSkull = function(self) return self.skull or 0 end
	t.isPlayer = function(self) return self.kind == "player" end
	t.isMonster = function(self) return self.kind == "monster" end
	t.isNpc = function(self) return self.kind == "npc" end
	t.isInvisible = function(self) return self.invisible == true end
	t.isInGhostMode = function(self) return self.ghost == true end
	return t
end
-- a tile as TFS keeps it: ground, top items, creatures, other items newest first
local function tile(ground, top, creatures, down)
	local things = {}
	if ground then things[#things + 1] = ground end
	for _, v in ipairs(top or {}) do things[#things + 1] = v end
	for _, v in ipairs(creatures or {}) do things[#things + 1] = v end
	for _, v in ipairs(down or {}) do things[#things + 1] = v end
	return {
		getGround = function() return ground end,
		getTopItemCount = function() return #(top or {}) end,
		getDownItemCount = function() return #(down or {}) end,
		getCreatureCount = function() return #(creatures or {}) end,
		getCreatures = function() return creatures or {} end,
		getThing = function(_, i) return things[i + 1] end
	}
end
-- client id = server id + 10000; 3031 stackable, 2006 a fluid container
local api = {
	item = function(it)
		if it.id == 0 then return nil end
		if it.id == 3031 or it.id == 2006 then return {it.id + 10000, it.sub or 0} end
		return it.id + 10000
	end,
	clientId = function(sid) return sid + 10000 end
}

-- ================================================================== a tile's items
local t1 = tile(item(100), {item(200), item(201)}, {}, {item(303), item(302), item(301)})
local list = K.tileItems(t1, api, 12)
local want = {10100, 10200, 10201, 10301, 10302, 10303}
eq(#list, #want, "ground, two top items, three other items")
for i, v in ipairs(want) do
	eq(list[i], v, "drawing order " .. i)
end
-- creatures between the top items and the others do not shift the items
local mob = creature({name = "Rat", kind = "monster", hp = 5, maxhp = 10, outfit = {lookType = 21}})
local t2 = tile(item(100), {item(200)}, {mob}, {item(302), item(301)})
list = K.tileItems(t2, api, 12)
eq(table.concat(list, ","), "10100,10200,10301,10302", "creatures are skipped, items keep their order")
-- too many: the newest are kept
local downs = {}
for i = 20, 1, -1 do downs[#downs + 1] = item(400 + i) end   -- 420 newest ... 401 oldest
list = K.tileItems(tile(item(100), {}, {}, downs), api, 5)
eq(table.concat(list, ","), "10100,10417,10418,10419,10420", "the ground and the four newest items")
-- no ground, a stackable and a fluid, an item without a client id
list = K.tileItems(tile(nil, {}, {}, {item(2006, 5), item(3031, 7), item(0)}), api, 12)
eq(#list, 2, "an item without a client id is skipped")
eq(type(list[1]) == "table" and list[1][1], 13031, "the stackable (oldest first)")
eq(type(list[1]) == "table" and list[1][2], 7, "with its count")
eq(type(list[2]) == "table" and list[2][2], 5, "the fluid with its kind")

-- ================================================================== creatures
local c = K.creature(creature({name = "Gm Ana", kind = "player", hp = 33, maxhp = 100, dir = 1, skull = 4,
	outfit = {lookType = 130, lookHead = 1, lookBody = 2, lookLegs = 3, lookFeet = 4, lookAddons = 3, lookMount = 368}}),
	5, 6, api, false)
eq(c.x, 5, "x")
eq(c.y, 6, "y")
eq(c.o.t, 130, "look type")
eq(c.o.h + c.o.b + c.o.l + c.o.f, 10, "colours")
eq(c.o.a, 3, "addons")
eq(c.o.m, 368, "mount")
eq(c.hp, 33, "health %")
eq(c.d, 1, "direction")
eq(c.skull, 4, "skull")
eq(c.k, "player", "kind")
eq(c.me, nil, "not the watched one")
c = K.creature(creature({name = "Mimic", kind = "monster", hp = 1, maxhp = 3, outfit = {lookType = 0, lookTypeEx = 1987}}),
	0, 0, api, true)
eq(c.o.x, 11987, "an item look: its client id")
eq(c.hp, 34, "health rounds up (the client never shows 0 for a living creature)")
eq(c.me, true, "the watched one is marked")
c = K.creature(creature({name = "Odd", kind = "npc", hp = 10, maxhp = 0, dir = 7, outfit = {}}), 0, 0, api, false)
eq(c.hp, 0, "no max health: 0")
eq(c.d, 3, "a direction out of range wraps")
eq(c.k, "npc", "an NPC")
check(not K.visible(creature({kind = "player", ghost = true}), false), "a ghost is not shown")
check(K.visible(creature({kind = "player", ghost = true}), true), "unless it is the watched player")
check(not K.visible(creature({kind = "monster", invisible = true}), false), "an invisible creature is not shown")

-- ================================================================== the snapshot
local me = creature({name = "Bob", kind = "player", hp = 150, maxhp = 200, dir = 2,
	outfit = {lookType = 128, lookHead = 78, lookBody = 69, lookLegs = 58, lookFeet = 76}})
local ghost = creature({name = "Gm Ana", kind = "player", ghost = true, hp = 1, maxhp = 1, outfit = {lookType = 75}})
local rat = creature({name = "Rat", kind = "monster", hp = 5, maxhp = 10, dir = 3, outfit = {lookType = 21}})
local world = {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
for y = 90, 110 do
	for x = 90, 110 do
		world[key(x, y, 7)] = tile(item(100))
	end
end
world[key(100, 100, 7)] = tile(item(100), {}, {me, ghost}, {})
world[key(102, 101, 7)] = tile(item(101), {item(200)}, {rat}, {item(3031, 3)})
world[key(100, 100, 6)] = tile(item(999))   -- another floor: never read
world[key(92, 94, 7)] = nil                  -- a hole in the map
local player = {
	getPosition = function() return {x = 100, y = 100, z = 7} end,
	getId = function() return me.cid end,
	getName = function() return "Bob" end,
	getLevel = function() return 123 end,
	getVocation = function() return {getName = function() return "Warrior" end} end,
	getHealth = function() return 150 end, getMaxHealth = function() return 200 end,
	getMana = function() return 40 end, getMaxMana = function() return 80 end,
	getFreeCapacity = function() return 123456 end, getSoul = function() return 100 end,
	getStamina = function() return 2520 end, getSkull = function() return 0 end
}
api.tile = function(x, y, z) return world[key(x, y, z)] end
local snap = K.snapshot(api, player, "bob", 5000, cfg)
eq(snap.v, 1, "version")
eq(snap.watch, "bob", "the name as asked (the script finds its answer by it)")
eq(snap.name, "Bob", "the real name")
eq(snap.t, 5000, "time")
eq(snap.online, true, "online")
eq(snap.w, 18, "18 tiles wide (15 + 1 west + 2 east)")
eq(snap.h, 14, "14 tiles high (11 + 1 north + 2 south)")
eq(snap.x0, 92, "west edge")
eq(snap.y0, 94, "north edge")
eq(#snap.tiles, 18 * 14, "one entry per tile")
eq(#snap.tiles[1], 0, "the hole is an empty tile")
eq(snap.tiles[(100 - 94) * 18 + (100 - 92) + 1][1], 10100, "the player's tile, its own floor")
local rt = snap.tiles[(101 - 94) * 18 + (102 - 92) + 1]
eq(rt[1], 10101, "the rat's tile: ground")
eq(rt[2], 10200, "a top item")
eq(type(rt[3]) == "table" and rt[3][2], 3, "a stack of three")
eq(#snap.creatures, 2, "the player and the rat (the ghost left out)")
eq(snap.creatures[1].name, "Bob", "the player first (its tile comes first)")
eq(snap.creatures[1].me, true, "marked as the watched one")
eq(snap.creatures[2].x, 102, "the rat's x")
eq(snap.creatures[2].hp, 50, "the rat at 50 %")
eq(snap.level, 123, "level")
eq(snap.voc, "Warrior", "class")
eq(snap.hp, 150, "health")
eq(snap.maxmp, 80, "max mana")
eq(snap.cap, 1234, "capacity in oz")
eq(snap.pos.x, 100, "position")

-- the shape the server's json (rxi) encodes: every table an array (1..n) or an object with string keys, no mix
local function shapeOk(v, path)
	if type(v) ~= "table" then
		return type(v) ~= "function" and type(v) ~= "userdata", path
	end
	local n, strings, ints = 0, 0, 0
	for k in pairs(v) do
		n = n + 1
		if type(k) == "string" then strings = strings + 1
		elseif type(k) == "number" and k == math.floor(k) and k >= 1 then ints = ints + 1
		else return false, path end
	end
	if strings > 0 and ints > 0 then return false, path end
	if ints > 0 then
		for i = 1, ints do
			if v[i] == nil then return false, path .. " sparse" end
		end
	end
	for k, x in pairs(v) do
		local ok, where = shapeOk(x, path .. "." .. tostring(k))
		if not ok then return false, where end
	end
	return true
end
local ok, where = shapeOk(snap, "snap")
check(ok, "the snapshot encodes as JSON: " .. tostring(where))
eq(K.offline("bob", 7).online, false, "offline answer")

-- a limit on creatures
local crowd = {}
for i = 1, 5 do crowd[i] = creature({name = "Rat", kind = "monster", hp = 1, maxhp = 1, outfit = {lookType = 21}}) end
world[key(101, 100, 7)] = tile(item(100), {}, crowd, {})
snap = K.snapshot(api, player, "Bob", 5000, {maxCreatures = 3})
eq(#snap.creatures, 3, "at most maxCreatures")

-- ================================================================== the engine file
local events, files = {}, {}
GlobalEvent = function(name)
	local ev = {name = name}
	function ev:interval(ms) self.ms = ms end
	function ev:register() events[self.name] = self end
	return ev
end
Chaos = {}
local encoded = 0
json = {encode = function(v) encoded = encoded + 1 return "{watch=" .. tostring(v.watch) .. ",online=" .. tostring(v.online) .. "}" end}
local itemTypes = {
	[100] = {getClientId = function() return 4526 end},
	[3031] = {getClientId = function() return 3031 end, isStackable = function() return true end},
	[2006] = {getClientId = function() return 2874 end, isFluidContainer = function() return true end},
	[5] = {getClientId = function() return 0 end}
}
function ItemType(id) return itemTypes[id] or {getClientId = function() return 0 end} end
function Tile(x, y, z) return world[key(x, y, z)] end
local online = {bob = player}
function Player(name) return online[name:lower()] end
local renames = 0
ChaosSpectate = {fs = {
	write = function(n, text, mode) files[n] = text return true end,
	rename = function(a, b)
		renames = renames + 1
		if renames == 2 and files[b] then return false end   -- once: a rename that cannot replace (Windows)
		files[b], files[a] = files[a], nil
		return true
	end,
	remove = function(n) files[n] = nil return true end
}}
dofile("data/scripts/chaos/spectate.lua")
local S = ChaosSpectate
check(events.ChaosSpectate ~= nil, "the poll is registered")
eq(events.ChaosSpectate.ms, 1000, "every second")
-- the engine api on mocked items
local realItem = {getId = function() return 3031 end, getSubType = function() return 9 end}
local e = S.api.item(realItem)
eq(type(e) == "table" and e[1], 3031, "a stackable: client id")
eq(type(e) == "table" and e[2], 9, "and count")
eq(S.api.item({getId = function() return 100 end, getSubType = function() return 1 end}), 4526, "a plain item: its client id")
eq(S.api.item({getId = function() return 5 end}), nil, "no client id: skipped")
eq(S.api.item({}), nil, "not an item: skipped")
eq(S.api.clientId(100), 4526, "lookTypeEx to client id")
-- no watch: nothing written
eq(S.tick(1000), false, "no watch, no snapshot")
eq(files["remote.spectate"], nil, "no file")
-- a watch writes at once
eq(S.watch("bob", 1000), true, "a new watch")
eq(files["remote.spectate"], "{watch=bob,online=true}", "the snapshot is written at once")
eq(files["remote.spectate.tmp"], nil, "through a temporary file")
eq(S.watch("Bob", 1005), false, "a renewal")
eq(files["remote.spectate"], "{watch=Bob,online=true}", "a rename that cannot replace removes the old file first")
eq(S.watch("Bob;ls", 1006), false, "a bad name is refused")
eq(S.state.name, "Bob", "and changes nothing")
check(S.tick(1010), "the poll writes while the watch lasts")
online.bob = nil
S.tick(1011)
eq(files["remote.spectate"], "{watch=Bob,online=false}", "an offline player: online = false")
local before = encoded
eq(S.tick(1005 + cfg.watchSeconds + 1), false, "after watchSeconds the watch ends")
eq(encoded, before, "and nothing is written")
-- an encoder error is logged, not thrown, and leaves the old file
online.bob = player
json.encode = function() error("boom") end
S.watch("Bob", 3000)
eq(S.tick(3001), false, "an encoder error writes nothing")

print(string.format("spectate_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
