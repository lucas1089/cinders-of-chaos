-- Run from the server/ folder: luajit tests/groundloot_test.lua (and lua5.3; CI runs both).
-- Ground loot labels (data/scripts/chaos/groundloot_core.lua and groundloot.lua) against a mocked engine: positions
-- from client input, the view range, the request budget, the decay time, the wire rows, the message split, and the
-- handler: only tiles in view are read, house tiles of other players and corpses the player may not loot reveal
-- nothing, items that cannot be picked up get no label, every asked tile is answered, the tooltip checks the item.
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- a small JSON encoder (objects with sorted keys; arrays when the table has [1] or is empty)
local function encode(v)
	local t = type(v)
	if t == "nil" then
		return "null"
	elseif t == "boolean" or t == "number" then
		return tostring(v)
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
	end
	local parts = {}
	if v[1] ~= nil or next(v) == nil then
		for _, x in ipairs(v) do
			parts[#parts + 1] = encode(x)
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	local keys = {}
	for k in pairs(v) do
		keys[#keys + 1] = tostring(k)
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		parts[#parts + 1] = encode(k) .. ":" .. encode(v[k])
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/groundloot_core.lua")
local G = ChaosGroundLoot

-- ---------------------------------------------------------------- opcode
eq(ChaosOpcodes.groundLoot, 230, "opcode 230")
local seen = {}
for name, op in pairs(ChaosOpcodes) do
	eq(seen[op], nil, "opcode " .. op .. " used twice (" .. name .. ")")
	seen[op] = name
end

-- ---------------------------------------------------------------- positions
local p = G.parsePos({100, 200, 7})
eq(p.x .. ":" .. p.y .. ":" .. p.z, "100:200:7", "array form")
p = G.parsePos({x = 5, y = 6, z = 0})
eq(p.x + p.y + p.z, 11, "object form")
eq(G.parsePos({1.5, 2, 7}), nil, "fraction")
eq(G.parsePos({1, 2, 16}), nil, "floor 16")
eq(G.parsePos({-1, 2, 7}), nil, "negative")
eq(G.parsePos({65535, 2, 7}), nil, "inventory x is no map position")
eq(G.parsePos({"a", 2, 7}), nil, "text")
eq(G.parsePos({0 / 0, 2, 7}), nil, "nan")
eq(G.parsePos({1, 2}), nil, "missing z")
eq(G.parsePos("1,2,7"), nil, "not a table")

local me = {x = 1000, y = 1000, z = 7}
eq(G.inView(me, {x = 1008, y = 994, z = 7}), true, "corner of the view")
eq(G.inView(me, {x = 1009, y = 1000, z = 7}), false, "9 squares east")
eq(G.inView(me, {x = 1000, y = 1007, z = 7}), false, "7 squares south")
eq(G.inView(me, {x = 1000, y = 1000, z = 6}), false, "another floor")

local req = G.parseTiles({{1000, 1000, 7}, {1000, 1000, 7}, {1020, 1000, 7}, {1001, 1000, 6}, {"x"}, 5, {1002, 1001, 7}}, me)
eq(#req.valid, 2, "two valid tiles (one duplicate dropped)")
eq(#req.refused, 2, "out of view and another floor are refused, not dropped")
local many = {}
for i = 1, 100 do
	many[i] = {1000 - 4 + i % 9, 1000, 7}
end
req = G.parseTiles(many, me)
eq(#req.valid <= G.config.maxTiles, true, "at most maxTiles read")
eq(#G.parseTiles(nil, me).valid, 0, "nil list")

-- ---------------------------------------------------------------- budget
local st = {}
eq(G.allow(st, 0, G.config.bucketSize), true, "a full bucket")
eq(G.allow(st, 0, 1), false, "empty")
eq(G.allow(st, 1000, G.config.bucketPerSecond), true, "refilled after a second")
eq(G.allow(st, 1000, 1), false, "empty again")
eq(G.allow(st, 100000, G.config.bucketSize + 1), false, "never more than the bucket")

-- ---------------------------------------------------------------- decay
eq(G.expiry(1, 90500), 91, "decaying: seconds left, rounded up")
eq(G.expiry(0, 90500), nil, "not decaying (a ring on the ground keeps its duration)")
eq(G.expiry(2, 90500), nil, "pending is not running yet")
eq(G.expiry(1, 0), nil, "nothing left")
eq(G.expiry(1, nil), nil, "no duration")
eq(G.expiry(nil, nil), nil, "no decay state at all")

-- a demon: 10 s fresh, then slain stages of 900 and 600 s (containers), then a non-container
eq(G.lootExpiry(7, {{container = true, seconds = 900}, {container = true, seconds = 600}, {container = false}}), 1507, "corpse stages summed")
eq(G.lootExpiry(7, {{container = false}}), 7, "the next stage holds nothing")
eq(G.lootExpiry(7, {}), 7, "no known next stage")
eq(G.lootExpiry(7, {{container = true, seconds = 0}}), nil, "a container stage that stays: the loot stays")
eq(G.lootExpiry(nil, {{container = true, seconds = 900}}), nil, "not decaying")

-- ---------------------------------------------------------------- corpses and wire rows
eq(G.isCorpse({container = true, corpseType = true, owner = 0}), true, "monster corpse type")
eq(G.isCorpse({container = true, corpseType = false, owner = 77}), true, "an owned container corpse")
eq(G.isCorpse({container = true, corpseType = false, owner = 0}), false, "a bag")
eq(G.isCorpse({container = false, corpseType = true, owner = 0}), false, "a decayed corpse without room")
eq(G.clip("a\nb\0c"), "a b c", "control characters")
eq(#G.clip(string.rep("x", 100)), G.config.maxNameLength, "clipped")

local sword = {clientId = 3264, count = 1, name = "sword", rarity = 3, unique = false, orb = false, category = "equipment", bestTier = 4, level = 57}
local w = G.wireItem(sword, 2, 61)
eq(w.id, 3264, "client id")
eq(w.s, 2, "index on the tile")
eq(w.r, 3, "rarity")
eq(w.u, nil, "not unique")
eq(w.t, 4, "best tier")
eq(w.il, 57, "item level")
eq(w.e, 61, "decay seconds")
eq(w.g, "equipment", "category")
local coins = G.wireItem({clientId = 3031, count = 100, name = "gold coin", rarity = 0, category = "currency"}, 1)
eq(coins.r, nil, "no rarity key")
eq(coins.c, 100, "count")
eq(coins.e, nil, "no decay")
local infos = {}
for i = 1, 20 do
	infos[i] = {clientId = 1, count = 1, name = "item " .. i, rarity = i % 4, category = "equipment"}
end
local c = G.wireCorpse(1, 4240, infos, 290)
eq(c.k, 1, "corpse flag")
eq(c.n, 20, "count of everything in it")
eq(#c.i, G.config.maxCorpseItems, "summary capped")
eq(c.e, 290, "corpse decay")

-- ---------------------------------------------------------------- message split
local tiles = {}
for i = 1, 40 do
	local items = {}
	for j = 1, 10 do
		items[j] = G.wireItem({clientId = 3264, count = 1, name = string.rep("n", 40), rarity = 5, category = "equipment", bestTier = 8, level = 120}, j, 100)
	end
	tiles[i] = {p = {1000 + i, 1000, 7}, i = items}
end
local payloads = G.pack(tiles, encode, 7000)
eq(#payloads > 1, true, "split into several messages")
local total = 0
for _, s in ipairs(payloads) do
	eq(#s <= 7000, true, "each at most 7000 bytes")
	total = total + select(2, s:gsub('"p":', ""))
end
eq(total, 40, "every tile answered once")
local huge = {{p = {1, 1, 7}, i = {}}}
for j = 1, 200 do
	huge[1].i[j] = G.wireItem({clientId = 1, count = 1, name = string.rep("y", 40), category = "other"}, j)
end
payloads = G.pack(huge, encode, 2000)
eq(#payloads, 1, "one tile alone")
eq(#payloads[1] <= 2000, true, "trimmed to fit")
eq(#G.pack({}, encode), 0, "nothing to send")

-- ---------------------------------------------------------------- handler (mocked engine)
ITEM_ATTRIBUTE_DURATION, ITEM_ATTRIBUTE_DECAYSTATE, ITEM_ATTRIBUTE_UNIQUEID = 1, 2, 3
local sent = {}
local events = {}
local inbox, nIn = {}, 0
json = {encode = encode, decode = function(s) return inbox[s] end}
local function msg(t) -- what the client would send, as the string the engine hands over
	if type(t) ~= "table" then return t end
	nIn = nIn + 1
	inbox["#" .. nIn] = t
	return "#" .. nIn
end
function CreatureEvent(name)
	local o = {}
	function o:type() end
	function o:register() events[name] = o end
	return o
end
function Position(x, y, z) return {x = x, y = y, z = z} end

local itemTypes = { -- decay chain of the corpse 4240: 4241 (container, 600 s) -> 4242 (no container)
	[4241] = {container = true, decayTo = 4242, duration = 600},
	[4242] = {container = false, decayTo = 0, duration = 60}
}
function ItemType(id)
	local d = itemTypes[id]
	return d and {getId = function() return id end, isContainer = function() return d.container end,
		getDecayId = function() return d.decayTo end, getDuration = function() return d.duration end} or {getId = function() return 0 end}
end
local function itemType(o)
	return {isPickupable = function() return o.pick ~= false end, isMovable = function() return o.move ~= false end,
		isCorpse = function() return o.corpseType == true end, getClientId = function() return o.cid end,
		isContainer = function() return o.container == true end, getDecayId = function() return o.decayTo or -1 end}
end
local function item(o)
	local it = {o = o}
	function it:getType() return itemType(o) end
	function it:isItem() return true end
	function it:isContainer() return o.container == true end
	function it:getCorpseOwner() return o.owner or 0 end
	function it:getItems() return o.items or {} end
	function it:getCount() return o.count or 1 end
	function it:getUniqueId() return o.uid or 70001 end -- the engine hands out a script id when there is none
	function it:hasAttribute(k) return k == ITEM_ATTRIBUTE_UNIQUEID and o.uid ~= nil end
	function it:getCustomAttribute(k) if k == "chaos_iid" then return o.iid end end
	function it:moveTo(dest)
		if self.tile then
			for n, x in ipairs(self.tile.items) do
				if x == self then table.remove(self.tile.items, n) break end
			end
			self.tile = nil
		end
		if dest.isBag then return true end
		local t = Tile(dest)
		if not t or o.stuck then return false end
		table.insert(t.items, 1, self) -- the newest item lies on top of the pile
		self.tile = t
		return true
	end
	function it:getAttribute(k)
		if k == ITEM_ATTRIBUTE_DECAYSTATE then return o.decay and 1 or 0 end
		if k == ITEM_ATTRIBUTE_DURATION then return o.ms or 0 end
	end
	return it
end
local world = {}
local function key(x, y, z) return x .. ":" .. y .. ":" .. z end
local function placeTile(x, y, z, items, house)
	local t = {items = items, house = house}
	function t:getItems() return self.items end
	function t:getHouse() return self.house end
	function t:getThingIndex(i)
		for n, x in ipairs(self.items) do
			if x == i then return n end -- index 0 is the ground
		end
		return -1
	end
	function t:getThing(n) return self.items[n] end
	function t:getTopDownItem() return self.items[1] end
	for _, i in ipairs(items) do i.tile = t end
	world[key(x, y, z)] = t
end
function Tile(pos) return world[key(pos.x, pos.y, pos.z)] end

ChaosLootFilter = {
	itemInfo = function(i)
		local o = i.o
		return {clientId = o.cid, count = o.count or 1, name = o.name or "thing", rarity = o.rarity or 0, unique = o.unique,
			orb = false, category = o.cat or "other", bestTier = 0, level = 0}
	end,
	canLoot = function(player, corpse)
		local owner = corpse:getCorpseOwner()
		return owner == 0 or owner == player:getId()
	end
}
ChaosItemTooltip = {build = function(i) return {name = i.o.name, id = i.o.cid} end}

local function newPlayer(id, x, y, z, guid)
	local pl = {id = id}
	function pl:getId() return self.id end
	function pl:getGuid() return guid or id end
	function pl:getPosition()
		return {x = x, y = y, z = z, isSightClear = function(_, to) return not (pl.walls and pl.walls[key(to.x, to.y, to.z)]) end}
	end
	function pl:canSee(pos) return pos.z == z and math.abs(pos.x - x) <= 8 and math.abs(pos.y - y) <= 6 end
	function pl:getSlotItem() return nil end
	function pl:getVocation() return {getAttackSpeed = function() return 1500 end} end
	function pl:sendExtendedOpcode(op, payload)
		sent[#sent + 1] = {op = op, payload = payload}
	end
	return pl
end

dofile("data/scripts/chaos/groundloot.lua")
local ext = events.ChaosGroundLootExtended
eq(ext ~= nil, true, "extended opcode event registered")

local rareSword = item({cid = 3264, name = "sword", rarity = 3, cat = "equipment"})
local statue = item({cid = 2000, name = "statue", pick = false})
local bag = item({cid = 1987, name = "bag", container = true, items = {}})
local field = item({cid = 2118, name = "fire field", decay = true, ms = 4200})
placeTile(1001, 1000, 7, {rareSword, statue, bag, field})
local myLoot = item({cid = 9, name = "gold coin", count = 30, cat = "currency"})
local mine = item({cid = 4240, container = true, corpseType = true, owner = 50, decay = true, ms = 120000, decayTo = 4241, items = {myLoot}})
local theirs = item({cid = 4240, container = true, corpseType = true, owner = 51, decay = true, ms = 120000,
	items = {item({cid = 3264, name = "sword", rarity = 9, cat = "equipment"})}})
local emptyCorpse = item({cid = 4240, container = true, corpseType = true, owner = 0, items = {}})
placeTile(1002, 1000, 7, {mine, theirs, emptyCorpse})
placeTile(1003, 1000, 7, {item({cid = 3264, name = "sword", rarity = 12, cat = "equipment"})}, {getOwnerGuid = function() return 999 end})
placeTile(1020, 1000, 7, {item({cid = 3264, name = "far sword", rarity = 12, cat = "equipment"})})

local me50 = newPlayer(50, 1000, 1000, 7)
local function lastTiles()
	local last = sent[#sent]
	eq(last.op, 230, "answered on opcode 230")
	return last.payload
end
sent = {}
ext.onExtendedOpcode(me50, 230, msg({action = "look", data = {t = {{1001, 1000, 7}, {1002, 1000, 7}, {1003, 1000, 7}, {1020, 1000, 7}}}}))
eq(#sent, 1, "one message")
local out = lastTiles()
eq(out:find('"nm":"sword"', 1, true) ~= nil, true, "the rare sword is described")
eq(out:find("statue", 1, true), nil, "furniture that cannot be picked up gets no label")
eq(out:find('"nm":"bag"', 1, true) ~= nil, true, "a bag is an item, not a corpse")
eq(out:find('"e":5', 1, true) ~= nil, true, "the decaying field carries its seconds (4.2 s -> 5)")
eq(out:find('"n":1', 1, true) ~= nil, true, "my corpse: one item")
eq(out:find('"nm":"gold coin"', 1, true) ~= nil, true, "my corpse's contents")
eq(out:find('"e":720', 1, true) ~= nil, true, "my corpse's loot lasts 120 s + the 600 s container stage")
eq(out:find('"r":9', 1, true), nil, "another player's corpse reveals nothing")
eq(out:find('"r":12', 1, true), nil, "another player's house and the far tile reveal nothing")
eq(select(2, out:gsub('"p":', "")), 4, "every asked tile is answered")

-- the budget: a flood is dropped, not answered
sent = {}
local flood = {}
for i = 1, 30 do flood[i] = {1001, 1000, 7} end
for _ = 1, 40 do
	ext.onExtendedOpcode(me50, 230, msg({action = "look", data = {t = {{1001, 1000, 7}, {1002, 1000, 7}, {1003, 1000, 7}, {1004, 1000, 7}, {1005, 1000, 7}}}}))
end
eq(#sent < 40, true, "the request budget stops a flood (" .. #sent .. " of 40 answered)")

-- another floor: refused tiles come back empty
local me60 = newPlayer(60, 1000, 1000, 6)
sent = {}
ext.onExtendedOpcode(me60, 230, msg({action = "look", data = {t = {{1001, 1000, 7}}}}))
out = lastTiles()
eq(out:find("sword", 1, true), nil, "nothing from another floor")
eq(out:find('"i":[]', 1, true) ~= nil, true, "answered empty")

-- tooltip
sent = {}
ext.onExtendedOpcode(newPlayer(70, 1000, 1000, 7), 230, msg({action = "tip", data = {p = {1001, 1000, 7}, s = 1, id = 3264}}))
out = lastTiles()
eq(out:find('"tip":{', 1, true) ~= nil, true, "tooltip of the sword")
ext.onExtendedOpcode(newPlayer(71, 1000, 1000, 7), 230, msg({action = "tip", data = {p = {1001, 1000, 7}, s = 1, id = 9999}}))
eq(sent[#sent].payload:find('"gone":1', 1, true) ~= nil, true, "another id at that index: gone")
ext.onExtendedOpcode(newPlayer(72, 1000, 1000, 7), 230, msg({action = "tip", data = {p = {1002, 1000, 7}, s = 2, id = 4240}}))
eq(sent[#sent].payload:find('"gone":1', 1, true) ~= nil, true, "no tooltip of a corpse")
ext.onExtendedOpcode(newPlayer(73, 1000, 1000, 7), 230, msg({action = "tip", data = {p = {1020, 1000, 7}, s = 1, id = 3264}}))
eq(sent[#sent].payload:find('"gone":1', 1, true) ~= nil, true, "out of view: gone")
ext.onExtendedOpcode(newPlayer(74, 1000, 1000, 7), 230, msg({action = "tip", data = {p = {1003, 1000, 7}, s = 1, id = 3264}}))
eq(sent[#sent].payload:find('"gone":1', 1, true) ~= nil, true, "another player's house: gone")
local before = #sent
ext.onExtendedOpcode(newPlayer(75, 1000, 1000, 7), 230, msg({action = "tip", data = {p = {1001, 1000, 7}, s = "x", id = 3264}}))
eq(#sent, before, "malformed: no answer")
ext.onExtendedOpcode(newPlayer(76, 1000, 1000, 7), 231, msg({action = "look", data = {t = {{1001, 1000, 7}}}}))
eq(#sent, before, "another opcode is ignored")
ext.onExtendedOpcode(newPlayer(77, 1000, 1000, 7), 230, "not json")
eq(#sent, before, "garbage is ignored")

-- ---------------------------------------------------------------- raise
eq(G.parseIid(nil), 0, "no iid")
eq(G.parseIid("0"), 0, "iid 0")
eq(G.parseIid("1878611511476211"), 1878611511476211, "a 16-digit iid as text")
eq(G.parseIid("12a"), nil, "malformed iid")
eq(G.parseIid(string.rep("9", 18)), nil, "too long")
eq(G.parseIid(-1), nil, "negative")
eq(G.parseIid(7), 7, "a number")
FLAG_NOLIMIT = 1
Game = {createItem = function() return {isBag = true, moveTo = function() return true end} end}
local legendary = item({cid = 3280, name = "fire sword", rarity = 5, cat = "equipment", iid = 222})
local rareFs = item({cid = 3280, name = "fire sword", rarity = 3, cat = "equipment", iid = 111})
local stone = item({cid = 1294, name = "small stone", count = 3, cat = "other"})
placeTile(1001, 1001, 7, {legendary, rareFs, stone})
local function raiseReply(pl, data)
	sent = {}
	ext.onExtendedOpcode(pl, 230, msg({action = "raise", data = data}))
	return sent[#sent] and sent[#sent].payload or ""
end
local t1001 = world[key(1001, 1001, 7)]
local out1 = raiseReply(newPlayer(80, 1000, 1000, 7), {p = {1001, 1001, 7}, s = 2, id = 3280, c = 1, iid = "111"})
eq(out1:find('"action":"raised"', 1, true) ~= nil and out1:find('"err"', 1, true) == nil, true, "raised")
eq(t1001.items[1], rareFs, "the Rare sword is on top of its pile now")
eq(#t1001.items, 3, "nothing left the tile")
-- the index moved since the client asked: found by its per-item id
out1 = raiseReply(newPlayer(81, 1000, 1000, 7), {p = {1001, 1001, 7}, s = 1, id = 3280, c = 1, iid = "222"})
eq(t1001.items[1], legendary, "found by iid at another index")
-- already on top: nothing moves, still answered
out1 = raiseReply(newPlayer(82, 1000, 1000, 7), {p = {1001, 1001, 7}, s = 1, id = 3280, c = 1, iid = "222"})
eq(out1:find('"err"', 1, true), nil, "on top already")
-- refusals
eq(raiseReply(newPlayer(83, 1000, 1000, 7), {p = {1001, 1001, 7}, s = 1, id = 3280, c = 1, iid = "999"}):find('"err":"gone"', 1, true) ~= nil, true, "another per-item id: gone")
eq(raiseReply(newPlayer(84, 1000, 1000, 7), {p = {1001, 1001, 7}, s = 3, id = 1294, c = 2}):find('"err":"gone"', 1, true) ~= nil, true, "another count: gone")
eq(raiseReply(newPlayer(85, 1000, 1000, 7), {p = {1001, 1001, 7}, s = 3, id = 9999, c = 3}):find('"err":"gone"', 1, true) ~= nil, true, "another id: gone")
eq(raiseReply(newPlayer(86, 990, 1000, 7), {p = {1001, 1001, 7}, s = 2, id = 3280, c = 1}):find('"err":"far"', 1, true) ~= nil, true, "out of view")
eq(raiseReply(newPlayer(87, 1000, 1000, 6), {p = {1001, 1001, 7}, s = 2, id = 3280, c = 1}):find('"err":"far"', 1, true) ~= nil, true, "another floor")
local walled = newPlayer(88, 1004, 1001, 7)
walled.walls = {[key(1001, 1001, 7)] = true}
eq(raiseReply(walled, {p = {1001, 1001, 7}, s = 2, id = 3280, c = 1}):find('"err":"sight"', 1, true) ~= nil, true, "no line of sight")
local nextTo = newPlayer(89, 1002, 1001, 7)
nextTo.walls = {[key(1001, 1001, 7)] = true}
eq(raiseReply(nextTo, {p = {1001, 1001, 7}, s = 2, id = 3280, c = 1}):find('"err"', 1, true), nil, "next to it: no sight needed")
eq(raiseReply(newPlayer(90, 1000, 1000, 7), {p = {1003, 1000, 7}, s = 1, id = 3264, c = 1}):find('"err":"gone"', 1, true) ~= nil, true, "another player's house")
placeTile(999, 999, 7, {item({cid = 4240, container = true, corpseType = true, owner = 0, items = {}}), item({cid = 1, uid = 5000, name = "quest key"})})
eq(raiseReply(newPlayer(91, 1000, 1000, 7), {p = {999, 999, 7}, s = 1, id = 4240, c = 1}):find('"err":"fixed"', 1, true) ~= nil, true, "a corpse is not raised")
eq(raiseReply(newPlayer(92, 1000, 1000, 7), {p = {999, 999, 7}, s = 2, id = 1, c = 1}):find('"err":"fixed"', 1, true) ~= nil, true, "an item with a unique id is not raised")
eq(raiseReply(newPlayer(93, 1000, 1000, 7), {p = {1001, 1000, 7}, s = 2, id = 2000, c = 1}):find('"err":"fixed"', 1, true) ~= nil, true, "furniture is not raised")
eq(raiseReply(newPlayer(94, 1000, 1000, 7), {p = {1001, 1001, 7}, s = 2, id = 3280, c = 1, iid = "x1"}), "", "malformed iid: no answer")
-- the move back fails: the bag with the item stays on the tile, nothing is lost
local stuckBag
Game = {createItem = function() stuckBag = {isBag = true, moved = false, moveTo = function(self) self.moved = true return true end} return stuckBag end}
local stuck = item({cid = 3280, name = "fire sword", rarity = 9, cat = "equipment", iid = 333, stuck = true})
placeTile(1001, 999, 7, {stone, stuck})
eq(raiseReply(newPlayer(95, 1000, 1000, 7), {p = {1001, 999, 7}, s = 2, id = 3280, c = 1, iid = "333"}):find('"err":"gone"', 1, true) ~= nil, true, "move back failed: refused")
eq(stuckBag.moved, true, "the bag holding it is put on the tile")

print("groundloot_test: " .. checks .. " checks passed")
