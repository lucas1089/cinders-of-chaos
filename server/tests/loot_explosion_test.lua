-- Run from the server/ folder: luajit tests/loot_explosion_test.lua (and lua5.3; CI runs both)
-- Loot explosion (O669; server/README.md "Loot explosion (O669)"). Part 1, the pure core (loot_explosion_core.lua): the shipped
-- config, the spread of the items over the free tiles (no pile before every tile has one, the death tile last, occupied tiles
-- late), gold in one stack, the per-kill cap (the rarest fly, the rest stays in the bag), the order and the stagger, the
-- fallbacks, the per-area and per-second caps, the ownership rule (owner, party, stranger before and after the owner time,
-- strict items, staff). Part 2, the engine glue loot_explosion.lua on a mocked engine: a kill's loot flies out and lands, the
-- gold stack, the attributes, the switch, nobody owns the kill, an instance, no free tile, a pull over the cap, the sweeper,
-- Player:onMoveItem (a stranger is refused, the owner and the party take it, the attribute leaves the item, a part of a
-- stack), Loot all, the season attributes carried, the groundloot hooks. Part 3, the other files that know about it: the
-- install hook, the config's names, the main quest's quest item.

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	checks = checks + 1
	if not v then
		error(m or "expected true", 2)
	end
end
local function readFile(path)
	local f = assert(io.open(path, "r"), "cannot open " .. path)
	local s = f:read("*a")
	f:close()
	return s
end

Chaos = {}
dofile("data/scripts/chaos/loot_explosion_core.lua")
local X = ChaosLootExplosion
local cfg = dofile("data/scripts/chaos/loot_explosion_config.lua")
local corpseCfg = dofile("data/scripts/chaos/corpse_config.lua")

-- a seeded random: the same numbers on both interpreters
local seed = 12345
local function rng(a, b)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return a + math.floor((seed / 2147483648) * (b - a + 1))
end

local function copy(t)
	local o = {}
	for k, v in pairs(t) do
		o[k] = v
	end
	return o
end

-- ---------------------------------------------------------------- part 1: the core
eq(#X.validate(cfg, corpseCfg), 0, "the shipped config is valid")
ok(X.active(cfg, corpseCfg), "on by default (owner 2026-11-19)")
ok(not X.active(nil, corpseCfg), "no config: off")
local off = copy(cfg)
off.enabled = false
ok(not X.active(off, corpseCfg), "the switch off")
eq(X.decaySeconds(cfg, corpseCfg), corpseCfg.seconds, "the items vanish after the bag's time")
eq(X.ownerSeconds(cfg, corpseCfg), corpseCfg.seconds, "the owner rule lasts the bag's whole life (the same timings the bag had)")
eq(X.ownerSeconds(copy(cfg), nil), nil, "no bag config and no own time: no time")
local own60 = copy(cfg)
own60.ownerSeconds = 60
eq(X.ownerSeconds(own60, corpseCfg), 60, "an own owner time")
eq(#X.validate(own60, corpseCfg), 0, "60 s of owner time is valid")

local function bad(key, value, text)
	local c = copy(cfg)
	c[key] = value
	local p = X.validate(c, corpseCfg)
	ok(#p > 0, text .. " is refused")
end
bad("radius", 3, "radius 3")
bad("radius", 0, "radius 0")
bad("maxItems", 0, "no item cap")
bad("maxPerAreaSecond", 3, "an area cap below one kill")
bad("maxPerSecond", 10, "a total cap below the area cap")
bad("staggerMaxMs", 10, "a stagger maximum below the minimum")
bad("decaySeconds", 400, "loot that stays over 5 minutes")
bad("ownerSeconds", 999, "an owner time over the loot's life")
bad("index", 120, "an index after the loot line")
bad("epicRank", 1, "an epic rank below the rare rank")
bad("strictAttributes", "chaos_unique", "a strict attribute list that is a text")
ok(#X.validate(nil) > 0, "no config is a problem")

-- groups and strictness
local function drop(t)
	return t
end
eq(X.groupOf(cfg, drop({gold = true})), "gold", "gold group")
eq(X.groupOf(cfg, drop({unique = true, rank = 100})), "unique", "unique group")
eq(X.groupOf(cfg, drop({rank = 0})), "plain", "no rarity is plain")
eq(X.groupOf(cfg, drop({rank = 2})), "plain", "Uncommon is plain")
eq(X.groupOf(cfg, drop({rank = 3})), "rare", "Magic is the rare group")
eq(X.groupOf(cfg, drop({rank = 4})), "rare", "Rare is the rare group")
eq(X.groupOf(cfg, drop({rank = 5})), "epic", "Legendary is the epic group")
eq(X.groupOf(cfg, drop({rank = 6})), "epic", "Divine is the epic group")
ok(X.isStrict(cfg, drop({unique = true})), "a unique keeps the owner rule")
ok(X.isStrict(cfg, drop({id = 5, attrs = {chaos_set = true}})), "a set piece keeps the owner rule")
ok(X.isStrict(cfg, drop({id = 5, attrs = {chaos_mq = true}})), "a main quest item keeps the owner rule")
ok(not X.isStrict(cfg, drop({id = 5, attrs = {}})), "a plain item does not")
local withIds = copy(cfg)
withIds.strictIds = {7777}
ok(X.isStrict(withIds, drop({id = 7777, attrs = {}})), "an id of strictIds keeps the owner rule")

-- tiles: the 24 ring 1 and 2 tiles and the death tile
local function ring(n)
	local out = {}
	for dx = -n, n do
		for dy = -n, n do
			local r = math.max(math.abs(dx), math.abs(dy))
			if r >= 1 then
				out[#out + 1] = {dx = dx, dy = dy, ring = r, items = 0}
			end
		end
	end
	return out
end
local function withOrigin(facts)
	facts[#facts + 1] = {dx = 0, dy = 0, ring = 0, items = 0}
	return facts
end
local facts = withOrigin(ring(2))
eq(#facts, 25, "25 tiles in radius 2")

for run = 1, 20 do
	local picks = X.pickTiles(cfg, facts, 14, rng)
	eq(#picks, 14, "one tile per drop")
	local seen = {}
	for _, idx in ipairs(picks) do
		ok(not seen[idx], "no tile twice while others are free (run " .. run .. ")")
		seen[idx] = true
		ok(facts[idx].ring ~= 0, "the death tile is a last resort (run " .. run .. ")")
	end
end
local many = X.pickTiles(cfg, facts, 24, rng)
local usedOrigin = false
for _, idx in ipairs(many) do
	usedOrigin = usedOrigin or facts[idx].ring == 0
end
ok(not usedOrigin, "24 drops fit on the 24 ring tiles: the death tile stays free")
local over = X.pickTiles(cfg, facts, 40, rng)
local perTile = {}
for _, idx in ipairs(over) do
	perTile[idx] = (perTile[idx] or 0) + 1
end
local most = 0
for _, n in pairs(perTile) do
	most = math.max(most, n)
end
ok(most <= 2, "40 drops on 25 tiles: at most 2 on one tile")
-- ring 1 is preferred
local ring1 = 0
local ringN = 0
for run = 1, 200 do
	local one = X.pickTiles(cfg, facts, 1, rng)
	ringN = ringN + 1
	if facts[one[1]].ring == 1 then
		ring1 = ring1 + 1
	end
end
eq(ring1, ringN, "ring 1 is the first choice (" .. ring1 .. " of " .. ringN .. ")")
local fourteen, outer = X.pickTiles(cfg, facts, 14, rng), 0
for _, idx in ipairs(fourteen) do
	if facts[idx].ring == 2 then
		outer = outer + 1
	end
end
eq(outer, 6, "14 drops: the 8 ring 1 tiles first, then 6 on ring 2 (radius 1-2)")
-- tiles that hold items are used last
local busy = withOrigin(ring(1))
for i = 1, 4 do
	busy[i].items = 3
end
local pick4 = X.pickTiles(cfg, busy, 4, rng)
for _, idx in ipairs(pick4) do
	ok(busy[idx].items == 0, "four drops go to the four free ring tiles first")
end
-- only the death tile
local only = X.pickTiles(cfg, {{dx = 0, dy = 0, ring = 0, items = 0}}, 3, rng)
eq(#only, 3, "the death tile alone takes the drops (piled)")
eq(X.pickTiles(cfg, {}, 3, rng), nil, "no tiles: nil")
eq(X.pickTiles(cfg, facts, 0, rng), nil, "no drops: nil")

-- the plan
local function items(spec)
	local out = {}
	for i, s in ipairs(spec) do
		out[i] = {key = i, rank = s.rank or 0, gold = s.gold or false}
	end
	return out
end
local plan = X.plan(cfg, items({{rank = 0}, {rank = 5}, {rank = 2}, {gold = true}, {rank = 100}, {gold = true}, {rank = 3}}), facts, rng)
eq(plan.fallback, nil, "a normal plan has no fallback")
eq(#plan.bag, 0, "all of seven fly")
eq(#plan.drops, 6, "two gold stacks are one drop: 5 items + 1 gold")
ok(plan.drops[1].gold, "gold leaves first")
eq(#plan.drops[1].keys, 2, "both gold stacks in the one drop")
local lastRank = -1
for i = 2, #plan.drops do
	ok(plan.drops[i].rank >= lastRank, "ranks rise: the rarest last")
	lastRank = plan.drops[i].rank
end
eq(plan.drops[#plan.drops].rank, 100, "the unique is the last to leave")
for i, d in ipairs(plan.drops) do
	ok(d.tile >= 1 and d.tile <= #facts, "a tile of the facts")
	if i == 1 then
		eq(d.delay, 0, "the first leaves at once")
	else
		local gap = d.delay - plan.drops[i - 1].delay
		ok(gap >= cfg.staggerMinMs and gap <= cfg.staggerMaxMs, "a stagger of 50-80 ms between two: " .. gap)
	end
	eq(d.flight, cfg.flightBaseMs + cfg.flightPerTileMs * math.max(1, facts[d.tile].ring), "flight time by distance")
end

-- the cap
local spec = {}
for i = 1, 30 do
	spec[i] = {rank = i % 7}
end
spec[31] = {gold = true}
local capped = X.plan(cfg, items(spec), facts, rng)
eq(#capped.drops, cfg.maxItems, "at most maxItems drops (gold counted as one)")
eq(#capped.bag, 31 - (cfg.maxItems - 1) - 1, "the rest stays in the bag")
local flyKeys = {}
for _, d in ipairs(capped.drops) do
	for _, k in ipairs(d.keys) do
		flyKeys[k] = true
	end
end
ok(flyKeys[31], "the gold flies")
local lowestFlying, highestBag = 99, -1
for k in pairs(flyKeys) do
	if k ~= 31 then
		lowestFlying = math.min(lowestFlying, spec[k].rank)
	end
end
for _, k in ipairs(capped.bag) do
	highestBag = math.max(highestBag, spec[k].rank)
end
ok(lowestFlying >= highestBag, "the rarest fly and the lowest stay in the bag")
local total = 0
for _, d in ipairs(capped.drops) do
	total = total + #d.keys
end
eq(total + #capped.bag, 31, "every item is either flying or in the bag")

-- fallbacks
local none = X.plan(cfg, items({{rank = 1}, {rank = 2}}), {}, rng)
eq(none.fallback, "tiles", "no free tile: fallback")
eq(#none.bag, 2, "everything stays in the bag")
eq(#none.drops, 0, "nothing flies")
eq(X.plan(cfg, {}, facts, rng).fallback, "empty", "no items: nothing to do")

-- the caps per area and per second
local gate = X.newGate()
local area = X.areaKey(cfg, {x = 1000, y = 1000, z = 7})
eq(X.areaKey(cfg, {x = 1000 + cfg.areaSize, y = 1000, z = 7}) ~= area, true, "a neighbouring square is another area")
eq(X.areaKey(cfg, {x = 1001, y = 1001, z = 7}), area, "the same square")
eq(X.areaKey(cfg, {x = 1001, y = 1001, z = 8}) ~= area, true, "another floor is another area")
ok(X.gateTake(cfg, gate, area, cfg.maxPerAreaSecond, 5000), "the area's cap in one go is granted")
ok(not X.gateTake(cfg, gate, area, 1, 5400), "one more in the same second: refused")
ok(X.gateTake(cfg, gate, "other", 10, 5400), "another area has its own cap")
ok(X.gateTake(cfg, gate, area, 5, 6000), "the next second starts fresh")
local gate2 = X.newGate()
local granted = 0
for i = 1, 100 do
	if X.gateTake(cfg, gate2, "area" .. i, cfg.maxPerAreaSecond, 9000) then
		granted = granted + 1
	end
end
eq(granted, math.floor(cfg.maxPerSecond / cfg.maxPerAreaSecond), "the whole map's cap per second holds across areas")

-- ownership
local info = {owner = 77, ownUntil = 1000, expiry = 1180, strict = false, seq = 5}
local text = X.encode(info)
local back = X.decode(text)
eq(back.owner, 77, "owner round trip")
eq(back.ownUntil, 1000, "owner time round trip")
eq(back.expiry, 1180, "expiry round trip")
eq(back.strict, false, "strict round trip")
eq(back.seq, 5, "seq round trip")
eq(X.decode(X.encode({owner = 1, ownUntil = 2, expiry = 3, strict = true, seq = 9})).strict, true, "strict true round trip")
eq(X.decode("junk"), nil, "junk is no record")
eq(X.decode(nil), nil, "no text is no record")
eq(X.decode(42), nil, "a number is no record")
ok(X.canTake(info, 900, 77, false, false), "the owner takes it")
ok(X.canTake(info, 900, 5, true, false), "the party takes it")
local okT, why, left = X.canTake(info, 900, 5, false, false)
ok(not okT and why == "wait" and left == 100, "a stranger waits until the owner time ran out: " .. tostring(why))
ok(X.canTake(info, 1000, 5, false, false), "a stranger takes it when the owner time ran out")
ok(X.canTake(info, 900, 5, false, true), "staff takes it")
local strict = copy(info)
strict.strict = true
local okS, whyS = X.canTake(strict, 5000, 5, false, false)
ok(not okS and whyS == "strict", "a strict item never frees up")
ok(X.canTake(strict, 5000, 77, false, false), "the owner takes a strict item")
ok(X.canTake({owner = 0, ownUntil = 0, expiry = 0, strict = true, seq = 1}, 1, 5, false, false), "no owner: anyone")
ok(X.expired(info, 1180), "expired at the vanish time")
ok(not X.expired(info, 1179), "not before")
ok(not X.expired({owner = 1, ownUntil = 0, expiry = 0, strict = false, seq = 0}, 99999), "no expiry: never")
eq(X.left(info, 1100), 80, "seconds left")
eq(X.left(info, 5000), 0, "no negative seconds")
eq(X.left({expiry = 0}, 5), nil, "no expiry: no timer")

-- ---------------------------------------------------------------- part 2: the glue on a mocked engine
local unpack_ = table.unpack or unpack
local clock = {ms = 1000000}
os.mtime = function() return clock.ms end
local realTime = os.time
os.time = function() return math.floor(clock.ms / 1000) end

TILESTATE_BLOCKSOLID, TILESTATE_BLOCKPATH, TILESTATE_PROTECTIONZONE, TILESTATE_FLOORCHANGE = 1, 2, 3, 4
TILESTATE_TELEPORT, TILESTATE_MAGICFIELD = 5, 6
CONST_ME_POFF, CONST_ME_MAGIC_BLUE, CONST_ME_MAGIC_GREEN, CONST_ME_FIREWORK_YELLOW = 10, 11, 12, 13
CONST_ANI_SMALLSTONE, CONST_ANI_ENERGY, CONST_ANI_FIRE = 20, 21, 22
RETURNVALUE_NOERROR, RETURNVALUE_NOTPOSSIBLE = 0, 5
CONTAINER_POS = 0xFFFF
MESSAGE_STATUS_SMALL = 30
ITEM_ATTRIBUTE_CORPSEOWNER = 99
FLAG_NOLIMIT = 1

local world, log, events

local function posKey(p)
	return p.x .. "," .. p.y .. "," .. p.z
end

local PosMT = {}
PosMT.__index = {
	sendMagicEffect = function(self, e)
		log.effects[#log.effects + 1] = {pos = posKey(self), effect = e}
	end,
	sendDistanceEffect = function(self, to, a)
		log.missiles[#log.missiles + 1] = {from = posKey(self), to = posKey(to), ani = a}
	end,
	isSightClear = function(self, to)
		return not world.noSight[posKey(to)]
	end,
}
PosMT.__eq = function(a, b)
	return a.x == b.x and a.y == b.y and a.z == b.z
end
function Position(x, y, z)
	if type(x) == "table" then
		x, y, z = x.x, x.y, x.z
	end
	return setmetatable({x = x, y = y, z = z}, PosMT)
end

local ItemMT = {}
ItemMT.__index = ItemMT
local function newItem(id, count, props)
	local it = setmetatable({id = id, count = count or 1, attrs = {}, children = {}, parent = nil, removed = false}, ItemMT)
	for k, v in pairs(props or {}) do
		it[k] = v
	end
	return it
end
Game = {createItem = function(id, count) return newItem(id, count, {container = id == 6068}) end}
function ItemMT:getId() return self.id end
function ItemMT:getCount() return self.count end
function ItemMT:getCustomAttribute(k) return self.attrs[k] end
function ItemMT:setCustomAttribute(k, v) self.attrs[k] = v return true end
function ItemMT:removeCustomAttribute(k) self.attrs[k] = nil return true end
function ItemMT:isContainer() return self.container == true end
function ItemMT:getSize() return #self.children end
function ItemMT:getItem(slot) return self.children[slot + 1] end
function ItemMT:getItems() return {unpack_(self.children)} end
function ItemMT:getCorpseOwner() return self.owner or 0 end
function ItemMT:getType()
	local me = self
	return {getName = function() return me.name or "item" end, isStackable = function() return me.stackable == true end}
end
function ItemMT:getPosition()
	local p = self.parent
	while p and p.kind ~= "tile" do
		p = p.parent
	end
	if p then
		return Position(p.pos.x, p.pos.y, p.pos.z)
	end
	return Position(0, 0, 0)
end
local function detach(item)
	local p = item.parent
	if not p then
		return
	end
	local list = p.kind == "tile" and p.items or p.children
	for i, x in ipairs(list) do
		if x == item then
			table.remove(list, i)
			break
		end
	end
	item.parent = nil
end
local function sameAttrs(a, b)
	for k, v in pairs(a) do
		if b[k] ~= v then
			return false
		end
	end
	for k, v in pairs(b) do
		if a[k] ~= v then
			return false
		end
	end
	return true
end
local function attach(item, parent)
	local list = parent.kind == "tile" and parent.items or parent.children
	if item.stackable then
		for _, other in ipairs(list) do
			if other.id == item.id and other.stackable and other.count + item.count <= 100 and sameAttrs(other.attrs, item.attrs) then
				other.count = other.count + item.count
				item.removed = true
				return other
			end
		end
	end
	list[#list + 1] = item
	item.parent = parent
	return item
end
function ItemMT:moveTo(dest)
	if self.removed then
		return false
	end
	local target
	if getmetatable(dest) == PosMT then
		target = world.tiles[posKey(dest)]
		if not target then
			return false
		end
	else
		target = dest
	end
	detach(self)
	attach(self, target)
	return true
end
function ItemMT:addItem(id, count)
	local it = newItem(id, count, {stackable = id == 2148 or id == 7618 or id == 7620})
	attach(it, self)
	return it
end
function ItemMT:setAttribute(key, v)
	if key == ITEM_ATTRIBUTE_CORPSEOWNER then
		self.owner = v
	end
	return true
end
function ItemMT:remove()
	detach(self)
	self.removed = true
	return true
end

local function newTile(x, y, z, props)
	local t = {kind = "tile", pos = {x = x, y = y, z = z}, items = {}, flags = {}, ground = newItem(1, 1, {name = "grass"})}
	for k, v in pairs(props or {}) do
		t[k] = v
	end
	world.tiles[x .. "," .. y .. "," .. z] = t
	return t
end
local TileObj = {}
function Tile(a, b, c)
	local key = type(a) == "table" and posKey(a) or (a .. "," .. b .. "," .. c)
	local t = world.tiles[key]
	if not t then
		return nil
	end
	return setmetatable({}, {__index = function(_, name)
		if name == "getItems" then
			return function() if #t.items == 0 then return nil end return {unpack_(t.items)} end
		elseif name == "getItemCount" then
			return function() return #t.items end
		elseif name == "getGround" then
			return function() return t.ground end
		elseif name == "getHouse" then
			return function() return t.house end
		elseif name == "hasFlag" then
			return function(_, f) return t.flags[f] == true end
		elseif name == "addItemEx" then
			return function(_, item) attach(item, t) return RETURNVALUE_NOERROR end
		elseif name == "getThingIndex" then
			return function(_, item)
				for i, x in ipairs(t.items) do
					if x == item then return i end
				end
				return -1
			end
		elseif name == "getTopDownItem" then
			return function() return t.items[#t.items] end
		elseif name == "getCreatureCount" then
			return function() return t.creatures or 0 end
		end
	end})
end

local queue
function addEvent(fn, delay)
	queue[#queue + 1] = {at = clock.ms + (delay or 0), fn = fn}
	return #queue
end
local function runEvents(untilMs)
	local guard = 0
	while guard < 5000 do
		guard = guard + 1
		local best
		for i, e in ipairs(queue) do
			if e.at <= untilMs and (not best or e.at < queue[best].at) then
				best = i
			end
		end
		if not best then
			break
		end
		local e = table.remove(queue, best)
		clock.ms = math.max(clock.ms, e.at)
		e.fn()
	end
	clock.ms = math.max(clock.ms, untilMs)
end

local callbacks
EventCallback = {register = function(self, prio)
	callbacks[#callbacks + 1] = {prio = prio, onDropLoot = self.onDropLoot, onItemMoved = self.onItemMoved}
	self.onDropLoot, self.onItemMoved = nil, nil
end}

local players
local PlayerMT = {}
PlayerMT.__index = PlayerMT
function PlayerMT:getId() return self.id end
function PlayerMT:getParty() return self.party end
function PlayerMT:getPosition() return self.pos end
function PlayerMT:sendCancelMessage(t) self.cancel[#self.cancel + 1] = t end
function PlayerMT:sendTextMessage(_, t) self.texts[#self.texts + 1] = t end
function Player(id)
	if type(id) == "string" then -- by name (O671: the tester join)
		for _, p in pairs(players) do
			if p.name == id then return p end
		end
		return nil
	end
	return players[id]
end
function ItemType(id) return {getClientId = function() return id + 1000 end} end
function PlayerMT:getName() return self.name or ("Player" .. self.id) end
function PlayerMT:teleportTo(pos) self.pos = pos end
local function newPlayer(id, x, y)
	local p = setmetatable({id = id, cancel = {}, texts = {}, pos = Position(x or 100, y or 100, 7), bp = newItem(2854, 1, {container = true})}, PlayerMT)
	p.bp.kind = "bag"
	players[id] = p
	return p
end
local function party(leader, members)
	local par = {getLeader = function() return leader end, getMembers = function() return members end}
	return par
end

Chaos = {isTester = function(p) return p.tester == true end, isStaff = function(p) return p.staff == true end, tx = function(_, t) return t end, instanceAt = function() return world.instance end}
dofile("data/lib/chaos_rarity.lua")
ChaosLootFilter = {
	killOf = function(corpse) return corpse:getCustomAttribute("lf_kill") end,
	onExploded = function(id, origin, tiles) log.exploded[#log.exploded + 1] = {id = id, origin = origin, tiles = tiles} end,
	touchKill = function(id) log.touched[#log.touched + 1] = id end,
	intoBags = function(player, item)
		if player.full then
			return false
		end
		item:moveTo(player.bp)
		return true
	end,
}

local function reset()
	world = {tiles = {}, noSight = {}}
	log = {effects = {}, missiles = {}, exploded = {}, touched = {}}
	queue, callbacks, players = {}, {}, {}
	events = nil
	clock.ms = 1000000
	math.randomseed(7)
end

local function openGround(cx, cy, radius)
	for dx = -radius, radius do
		for dy = -radius, radius do
			newTile(cx + dx, cy + dy, 7)
		end
	end
end

local function load()
	Chaos.corpseConfig = nil
	Chaos.lootExplosionConfig = nil
	X.gate = nil
	dofile("data/scripts/chaos/loot_explosion.lua")
	return Chaos.lootExplosionConfig
end

local function runDrop(corpse)
	for _, c in ipairs(callbacks) do
		if c.onDropLoot then
			c.onDropLoot({}, corpse)
		end
	end
end

local function makeBag(x, y, ownerId, contents, bagId)
	local bag = newItem(bagId or 6068, 1, {container = true, owner = ownerId})
	local tile = world.tiles[x .. "," .. y .. ",7"]
	attach(bag, tile)
	for _, c in ipairs(contents) do
		local it = newItem(c.id, c.count or 1, {stackable = c.stackable, name = c.name})
		for k, v in pairs(c.attrs or {}) do
			it.attrs[k] = v
		end
		attach(it, bag)
	end
	return bag
end

local function tileItems(x, y)
	return world.tiles[x .. "," .. y .. ",7"].items
end

local function loose()
	local out = {}
	for key, tile in pairs(world.tiles) do
		for _, it in ipairs(tile.items) do
			if it.attrs.chaos_loot and it.id ~= 6068 then
				out[#out + 1] = {item = it, key = key}
			end
		end
	end
	return out
end

reset()
openGround(100, 100, 4)
local conf = load()
eq(#callbacks, 2, "two callbacks: the move cleanup and the drop")
local dropCb
for _, c in ipairs(callbacks) do
	if c.onDropLoot then
		dropCb = c
	end
end
eq(dropCb.prio, 98, "the explosion runs at the end of the loot chain, before the empty corpse check (99)")
eq(#X.problems, 0, "the glue found no config problem")

-- 1. a kill: seven items and two gold stacks fly out and land
local owner = newPlayer(1)
local bag = makeBag(100, 100, 1, {
	{id = 2148, count = 100, stackable = true}, {id = 2148, count = 60, stackable = true},
	{id = 7618, count = 3, stackable = true, attrs = {}},
	{id = 2400, attrs = {rarity = 1}}, {id = 2401, attrs = {rarity = 3}}, {id = 2402, attrs = {rarity = 5}},
	{id = 2403, attrs = {chaos_unique = "x", rarity = 4}},
})
bag:setCustomAttribute("lf_kill", 41)
bag:setCustomAttribute("chaos_realm", 3)
bag:setCustomAttribute("chaos_owner", 999)
runDrop(bag)
eq(bag:getSize(), 7, "nothing has left the bag yet: the items fly first")
eq(#log.exploded, 1, "the loot filter is told about the explosion")
eq(log.exploded[1].id, 41, "with the kill id")
eq(#log.exploded[1].tiles, 6, "and the six tiles (gold and five items)")
ok(bag:getCustomAttribute("chaos_exploded") ~= nil, "the bag is marked exploded")
ok(X.isExploded(bag), "isExploded says so")
eq(#log.effects, 1, "the burst effect on the death tile")
eq(log.effects[1].pos, "100,100,7", "on the death tile")
eq(log.effects[1].effect, CONST_ME_POFF, "the configured burst")
runEvents(clock.ms + 3000)
eq(bag:getSize(), 0, "after the flight everything is out of the bag")
eq(#log.missiles, 6, "one distance effect per drop (gold counts as one)")
local landed = loose()
eq(#landed, 7, "seven loose items on the ground (two gold stacks, five items)")

local function looseOf(id)
	local out = {}
	for _, row in ipairs(loose()) do
		if row.item.id == id then
			out[#out + 1] = row
		end
	end
	return out
end
local goldRows = looseOf(2148)
eq(#goldRows, 2, "two gold stacks")
eq(goldRows[1].key, goldRows[2].key, "gold lands on one tile")
local tilesUsed, ringOk = {}, true
for _, row in ipairs(landed) do
	if row.item.id ~= 2148 then
		ok(not tilesUsed[row.key], "no two items on one tile: " .. row.key)
		tilesUsed[row.key] = true
	end
	local x, y = row.key:match("^(%d+),(%d+)")
	ringOk = ringOk and math.max(math.abs(tonumber(x) - 100), math.abs(tonumber(y) - 100)) <= 2
end
ok(ringOk, "every item lies within 2 tiles of the death tile")
ok(not tilesUsed["100,100,7"], "the death tile stays free")
for _, row in ipairs(landed) do
	local info = X.decode(row.item.attrs.chaos_loot)
	ok(info ~= nil, "every loose item has its record")
	eq(info.owner, 1, "owned by the killer")
	eq(info.expiry - info.ownUntil, 0, "the owner rule lasts the item's whole life (same timings as the bag)")
	eq(row.item.attrs.lf_loot, 41, "the loot filter's kill id")
	eq(row.item.attrs.chaos_realm, 3, "the season realm of the bag")
	eq(row.item.attrs.chaos_owner, 999, "the Self-Found owner of the bag")
end
eq(X.decode(looseOf(2403)[1].item.attrs.chaos_loot).strict, true, "a unique is strict")
eq(X.decode(looseOf(2400)[1].item.attrs.chaos_loot).strict, false, "a plain item is not")
-- the effects: missiles by group, sparkles for the rare groups
local ani = {}
for _, m in ipairs(log.missiles) do
	ani[m.ani] = (ani[m.ani] or 0) + 1
	eq(m.from, "100,100,7", "every item leaves the death tile")
end
ok(ani[CONST_ANI_FIRE] == 1 and ani[CONST_ANI_ENERGY] == 2, "a unique flies with fire, the Magic and Legendary ones with energy")
local sparks = {}
for _, e in ipairs(log.effects) do
	sparks[e.effect] = (sparks[e.effect] or 0) + 1
end
ok(sparks[CONST_ME_MAGIC_BLUE] == 1 and sparks[CONST_ME_MAGIC_GREEN] == 1 and sparks[CONST_ME_FIREWORK_YELLOW] == 1,
	"the landing sparkle of the rare, epic and unique groups")
-- the staggered launch: the rarest last
eq(log.missiles[#log.missiles].ani, CONST_ANI_FIRE, "the unique leaves last")
ok(X.watched() >= 1, "the landing tiles are watched")

-- 2. ownership by Player:onMoveItem
local stranger = newPlayer(2)
local friend = newPlayer(3)
friend.party = party(owner, {friend})
owner.party = friend.party
local potion = looseOf(7618)[1].item
local toBp = {x = CONTAINER_POS, y = 3, z = 0}
local fromGround = {x = 101, y = 101, z = 7}
eq(X.onMoveItem(stranger, potion, 3, fromGround, toBp), RETURNVALUE_NOTPOSSIBLE, "a stranger may not take the killer's loot")
ok(#stranger.cancel == 1 and stranger.cancel[1]:find("more seconds"), "and is told how long it is not theirs: " .. tostring(stranger.cancel[1]))
ok(potion.attrs.chaos_loot ~= nil, "a refused move leaves the record")
eq(X.onMoveItem(friend, potion, 3, fromGround, toBp), RETURNVALUE_NOERROR, "a party member may take it")
ok(potion.attrs.chaos_loot == nil and potion.attrs.lf_loot == nil, "it leaves the ground with no record (it stacks again)")
local unique = looseOf(2403)[1].item
-- a stranger, far after the owner time: plain items free up only when ownerSeconds is shorter than the life
clock.ms = clock.ms + 1000 * (corpseCfg.seconds - 5)
eq(X.onMoveItem(stranger, unique, 1, fromGround, toBp), RETURNVALUE_NOTPOSSIBLE, "a unique stays the killer's for the whole life")
local sword = looseOf(2400)[1].item
eq(X.onMoveItem(stranger, sword, 1, fromGround, toBp), RETURNVALUE_NOTPOSSIBLE, "so does a plain item with the bag's own timing")
eq(X.onMoveItem(owner, sword, 1, fromGround, toBp), RETURNVALUE_NOERROR, "the killer takes it")
-- a part of a stack: the record stays (the part gets cleaned after the move)
local gold1 = goldRows[1].item
eq(X.onMoveItem(owner, gold1, 40, fromGround, toBp), RETURNVALUE_NOERROR, "a part of a stack is allowed")
ok(gold1.attrs.chaos_loot ~= nil, "the rest on the ground keeps its record")
-- the cleanup after a move
for _, c in ipairs(callbacks) do
	if c.onItemMoved then
		local part = newItem(2148, 40, {stackable = true})
		part.attrs.chaos_loot = gold1.attrs.chaos_loot
		c.onItemMoved(owner, part, 40, fromGround, toBp)
		ok(part.attrs.chaos_loot == nil, "the part that was taken loses the record after the move")
		local onGround = newItem(2148, 5, {stackable = true})
		onGround.attrs.chaos_loot = gold1.attrs.chaos_loot
		c.onItemMoved(owner, onGround, 5, fromGround, {x = 102, y = 102, z = 7})
		ok(onGround.attrs.chaos_loot ~= nil, "a move on the ground keeps it")
	end
end
-- the item moved to another tile is watched there
local before = X.watched()
eq(X.onMoveItem(owner, gold1, 60, fromGround, {x = 103, y = 103, z = 7}), RETURNVALUE_NOERROR, "the owner moves it on the ground")
ok(X.watched() >= before, "the new tile is watched")
-- the move that fails after the hook: the record comes back by itself (no onItemMoved fired), and a move that worked leaves nothing pending
do
	runEvents(clock.ms + 500) -- the moves above that "failed" in this mock put their records back
	eq(X.pendingCount(), 0, "nothing pending before")
	local fx, fy = 104, 104
	local item = newItem(2400)
	attach(item, world.tiles[fx .. "," .. fy .. ",7"])
	item.attrs.chaos_loot = X.encode({owner = 1, ownUntil = 0, expiry = 9999999999, strict = false, seq = 77})
	item.attrs.lf_loot = 41
	local at = {x = fx, y = fy, z = 7}
	eq(X.onMoveItem(owner, item, 1, at, toBp), RETURNVALUE_NOERROR, "the owner's move is allowed")
	ok(item.attrs.chaos_loot == nil, "the record is off the item for the move")
	eq(X.pendingCount(), 1, "and waits to be put back")
	runEvents(clock.ms + 500)
	ok(item.attrs.chaos_loot ~= nil and item.attrs.lf_loot == 41, "the move failed: the record is back")
	eq(X.pendingCount(), 0, "nothing pending")
	-- the move that worked: onItemMoved clears it
	eq(X.onMoveItem(owner, item, 1, at, toBp), RETURNVALUE_NOERROR, "again")
	for _, c in ipairs(callbacks) do
		if c.onItemMoved then
			c.onItemMoved(owner, item, 1, at, toBp)
		end
	end
	item:moveTo(owner.bp)
	eq(X.pendingCount(), 0, "the move worked: nothing pending")
	eq(log.touched[#log.touched], 41, "the loot filter re-reads the kill the item came from")
	runEvents(clock.ms + 500)
	ok(item.attrs.chaos_loot == nil, "and the record stays off")
end
-- O671: a plain stack of the same id lies on the tile (live run: 7 gold of a test took the record of the 100 gold that stayed)
do
	local fx, fy = 98, 98
	local tile = world.tiles[fx .. "," .. fy .. ",7"]
	local plain = newItem(2148, 7, {stackable = true})
	attach(plain, tile)
	local loot = newItem(2148, 100, {stackable = true})
	loot.attrs.chaos_loot = X.encode({owner = 1, ownUntil = 0, expiry = 9999999999, strict = false, seq = 78})
	loot.stackable = true
	tile.items[#tile.items + 1] = loot
	loot.parent = tile
	local at = {x = fx, y = fy, z = 7}
	eq(X.onMoveItem(owner, loot, 100, at, toBp), RETURNVALUE_NOERROR, "the owner starts to drag the 100 gold")
	ok(loot.attrs.chaos_loot == nil, "its record is off")
	runEvents(clock.ms + 250)
	ok(loot.attrs.chaos_loot ~= nil, "the move failed: the record is back on the 100 gold")
	ok(plain.attrs.chaos_loot == nil, "and not on the plain 7 gold beside it")
	plain:remove()
	loot:remove()
end
-- an item with no record or a broken one
local plain = newItem(2400)
eq(X.onMoveItem(stranger, plain, 1, fromGround, toBp), RETURNVALUE_NOERROR, "an ordinary item is not touched")
local broken = newItem(2400)
broken.attrs.chaos_loot = "junk"
eq(X.onMoveItem(stranger, broken, 1, fromGround, toBp), RETURNVALUE_NOERROR, "a broken record is no block")
ok(broken.attrs.chaos_loot == nil, "and is cleaned")
local staffer = newPlayer(9)
staffer.staff = true
eq(X.onMoveItem(staffer, unique, 1, fromGround, toBp), RETURNVALUE_NOERROR, "staff may take anything")

-- 3. the vanishing: the sweeper removes what ran out, only that
local remaining = loose()
ok(#remaining > 0, "loot still lies there")
local twoKept = newItem(2500)
attach(twoKept, world.tiles["101,101,7"]) -- an unrelated item on a watched tile
clock.ms = clock.ms + 1000 * 200
runEvents(clock.ms + 10000)
eq(#loose(), 0, "after the bag's time every loose item is gone")
local survived = false
for _, it in ipairs(tileItems(101, 101)) do
	survived = survived or it == twoKept
end
ok(survived, "an item that is not loot is never swept")
eq(X.watched(), 0, "no tile is watched any more")
eq(#queue, 0, "the sweeper's timer stopped with it")

-- 4. no owner, an instance, the switch, no free tile, a pull over the cap
reset()
openGround(100, 100, 4)
load()
local o2 = newPlayer(1)
local ownerless = makeBag(100, 100, 0, {{id = 2400}})
runDrop(ownerless)
runEvents(clock.ms + 3000)
eq(ownerless:getSize(), 1, "nobody owns the kill: the item stays in the bag")
local gone = makeBag(101, 100, 55, {{id = 2400}})
runDrop(gone)
runEvents(clock.ms + 3000)
eq(gone:getSize(), 1, "the owner is not in the game: the bag as before")
world.instance = "rift"
local inRift = makeBag(100, 101, 1, {{id = 2400}})
runDrop(inRift)
runEvents(clock.ms + 3000)
eq(inRift:getSize(), 1, "inside an instance the bag stays (it clears its area when it ends)")
world.instance = nil
local notBag = newItem(2400, 1, {container = true, owner = 1})
attach(notBag, world.tiles["100,102,7"])
attach(newItem(2401), notBag)
runDrop(notBag)
runEvents(clock.ms + 3000)
eq(notBag:getSize(), 1, "only the loot bag explodes: another container (a player's corpse) is never touched")
local emptyBag = makeBag(102, 100, 1, {})
runDrop(emptyBag)
eq(#queue, 0, "an empty bag does nothing")
Chaos.lootExplosionConfig.enabled = false
local offBag = makeBag(100, 103, 1, {{id = 2400}})
runDrop(offBag)
runEvents(clock.ms + 3000)
eq(offBag:getSize(), 1, "the switch off: the bag, as before")
Chaos.lootExplosionConfig.enabled = true

-- no free tile around: walls, water, stairs, a house, a protection zone, a teleport
reset()
openGround(200, 200, 2)
for dx = -2, 2 do
	for dy = -2, 2 do
		local t = world.tiles[(200 + dx) .. "," .. (200 + dy) .. ",7"]
		local r = math.max(math.abs(dx), math.abs(dy))
		if r == 1 then
			local k = (dx + dy + 4) % 6
			if k == 0 then t.flags[TILESTATE_BLOCKSOLID] = true
			elseif k == 1 then t.ground = newItem(1, 1, {name = "shallow water"})
			elseif k == 2 then t.flags[TILESTATE_FLOORCHANGE] = true
			elseif k == 3 then t.house = {}
			elseif k == 4 then t.flags[TILESTATE_PROTECTIONZONE] = true
			else t.flags[TILESTATE_TELEPORT] = true end
		end
	end
end
load()
newPlayer(1, 200, 200)
local fenced = makeBag(200, 200, 1, {{id = 2400}, {id = 2401}, {id = 2402}, {id = 2403}, {id = 2404}, {id = 2405}})
runDrop(fenced)
runEvents(clock.ms + 3000)
for _, row in ipairs(loose()) do
	local x, y = row.key:match("^(%d+),(%d+)")
	local dx, dy = tonumber(x) - 200, tonumber(y) - 200
	local r = math.max(math.abs(dx), math.abs(dy))
	ok(r == 2 or r == 0, "nothing lands on a wall, water, stairs, a house, a protection zone or a teleport: " .. row.key)
end
eq(#loose(), 6, "all six landed on the free tiles")

-- a tile the death tile cannot see is skipped
reset()
openGround(300, 300, 2)
for dx = -2, 2 do
	for dy = -2, 2 do
		if dx ~= 0 or dy ~= 0 then
			world.noSight[(300 + dx) .. "," .. (300 + dy) .. ",7"] = true
		end
	end
end
load()
newPlayer(1, 300, 300)
local walled = makeBag(300, 300, 1, {{id = 2400}, {id = 2401}})
runDrop(walled)
runEvents(clock.ms + 3000)
for _, row in ipairs(loose()) do
	eq(row.key, "300,300,7", "no tile in sight: the death tile takes them (never through a wall)")
end
eq(#loose(), 2, "both landed")

-- the cap per kill: 20 items, 14 fly, the rest stays in the small bag
reset()
openGround(400, 400, 4)
load()
newPlayer(1, 400, 400)
local contents = {}
for i = 1, 20 do
	contents[i] = {id = 3000 + i, attrs = {rarity = (i % 5) + 1}}
end
local big = makeBag(400, 400, 1, contents)
runDrop(big)
runEvents(clock.ms + 5000)
eq(#loose(), 14, "at most 14 things on the ground")
eq(big:getSize(), 6, "the other six stay in the small bag on the death tile")
for _, child in ipairs(big.children) do
	ok(child.attrs.chaos_loot == nil, "what stays in the bag has no ground record")
end
local lowestFlew = 9
for _, row in ipairs(loose()) do
	lowestFlew = math.min(lowestFlew, row.item.attrs.rarity)
end
for _, child in ipairs(big.children) do
	ok(child.attrs.rarity <= lowestFlew, "the items in the bag are not rarer than the ones that flew")
end

-- a pull over the area's cap: the bag, as before
reset()
openGround(500, 500, 4)
load()
newPlayer(1, 500, 500)
local bags = {}
for i = 1, 6 do
	bags[i] = makeBag(500, 500, 1, {{id = 4001}, {id = 4002}, {id = 4003}, {id = 4004}, {id = 4005}, {id = 4006}, {id = 4007}, {id = 4008}})
end
for i = 1, 6 do
	runDrop(bags[i])
end
local exploded, stayed = 0, 0
for i = 1, 6 do
	if X.isExploded(bags[i]) then
		exploded = exploded + 1
	else
		stayed = stayed + 1
	end
end
eq(exploded, 5, "five kills of 8 items fit the area's 40 items a second")
eq(stayed, 1, "the sixth stays a bag")
clock.ms = clock.ms + 1000
local later = makeBag(500, 500, 1, {{id = 4001}})
runDrop(later)
ok(X.isExploded(later), "the next second has room again")
runEvents(clock.ms + 5000)

-- 5. Loot all
reset()
openGround(600, 600, 8)
load()
local me = newPlayer(1, 600, 600)
local other = newPlayer(2, 600, 600)
local lootBag = makeBag(601, 600, 1, {{id = 5001}, {id = 5002}, {id = 5003}, {id = 5004}})
lootBag:setCustomAttribute("lf_kill", 12)
runDrop(lootBag)
runEvents(clock.ms + 3000)
eq(#loose(), 4, "four items lie around")
local oneOfOthers = makeBag(602, 601, 2, {{id = 5100}})
oneOfOthers:setCustomAttribute("lf_kill", 13)
runDrop(oneOfOthers)
runEvents(clock.ms + 3000)
eq(#loose(), 5, "and one of another player's")
local took, failed, seen = X.lootAll(me)
eq(took, 4, "Loot all takes the four of mine")
eq(failed, 0, "all fit")
eq(seen, 4, "four seen")
eq(#loose(), 1, "the other player's loot stays")
eq(me.bp:getSize(), 4, "in the backpack")
for _, child in ipairs(me.bp.children) do
	ok(child.attrs.chaos_loot == nil, "with no ground record")
end
eq(log.touched[1], 12, "the loot filter re-reads the kill")
local t2, f2, s2 = X.lootAll(me)
eq(t2 + f2 + s2, 0, "nothing more to take")
-- a full backpack: the items stay, with their records
local lootBag2 = makeBag(599, 600, 1, {{id = 5201}, {id = 5202}})
runDrop(lootBag2)
runEvents(clock.ms + 3000)
me.full = true
local t3, f3 = X.lootAll(me)
eq(t3, 0, "a full backpack takes nothing")
eq(f3, 2, "two did not fit")
local still = 0
for _, row in ipairs(loose()) do
	if row.item.id == 5201 or row.item.id == 5202 then
		still = still + 1
		ok(X.decode(row.item.attrs.chaos_loot) ~= nil, "the item keeps its record when it does not fit")
	end
end
eq(still, 2, "both still lie there")
me.full = false
-- a stranger's Loot all takes nothing of mine, the party's does
local ts = X.lootAll(other)
eq(ts, 1, "another player takes only their own loot (5100), nothing of the killer's")
other.party = party(me, {other})
me.party = other.party
local tp = X.lootAll(other)
eq(tp, 2, "a party member takes what lies there")
-- the reach
reset()
openGround(700, 700, 12)
load()
local far = newPlayer(1, 700, 700)
local reachBag = makeBag(700, 700, 1, {{id = 6001}})
runDrop(reachBag)
runEvents(clock.ms + 3000)
for _, row in ipairs(loose()) do
	local ix = tonumber(row.key:match("^(%d+)"))
	row.item:moveTo(Position(ix + 9, 700, 7))
end
local tf = X.lootAll(far)
eq(tf, 0, "loot beyond the reach (7 x 5) is not taken")
-- the expiry the client's timer reads
local timed = looseOf(6001)[1].item
ok(X.expiryLeft(timed) > 0 and X.expiryLeft(timed) <= corpseCfg.seconds, "the despawn timer for the labels")
eq(X.expiryLeft(newItem(1)), nil, "no timer on an ordinary item")
ok(X.visibleTo(far, timed), "the killer sees the label")
ok(not X.visibleTo(newPlayer(5), timed), "another player does not see the killer's label")
ok(X.visibleTo(newPlayer(6), newItem(1)), "an ordinary item is visible to everyone")

-- the tester bots' probes (TEST ONLY, tools/tester_helper.lua `!tester explode`)
reset()
openGround(800, 800, 6)
load()
local bot = newPlayer(1, 800, 800)
local ran, why = X.testerRun(bot)
ok(ran ~= nil, "the helper's bag explodes: " .. tostring(why))
eq(ran.items, 6, "six things in the test bag")
runEvents(clock.ms + 4000)
local probe = X.testerProbe(bot)
eq(probe.loose, 6, "six loose items (the two gold stacks, three potions, two swords: gold merges to 150 in two stacks of 100 and 50)")
eq(probe.mine, probe.loose, "all the bot's")
eq(probe.foreign, 0, "none of another")
eq(probe.bagItems, 0, "nothing left in the bag")
ok(probe.maxRing <= 2, "within 2 tiles")
ok(probe.tiles >= 5, "on at least five tiles (the gold shares one)")
ok(#probe.list >= 5 and probe.list[1].cid and probe.list[1].sp and probe.list[1].x and probe.list[1].mine == true, "the list names the items by tile, client id and stack place (O671)")
eq(probe.at.x, 800, "and where the asker stands")
eq(probe.strangerRefused, true, "a stranger is refused")
eq(probe.ownerAllowed, true, "the owner is allowed")
ok(probe.expiry and probe.expiry > 0, "a vanish time")
-- O671: a bot in the temple (a protection zone) is put on an open tile first; a player or a bot already in the open stays where it is
do
	local zone = newPlayer(20, 900, 900)
	zone.name, zone.tester = "Tester Zone", true
	for dx = -3, 3 do
		for dy = -3, 3 do
			newTile(900 + dx, 900 + dy, 7, {flags = {[TILESTATE_PROTECTIONZONE] = true}})
		end
	end
	openGround(908, 900, 4)   -- free ground just outside the zone, to the east
	local r = X.testerRun(zone)
	ok(r and r.moved == true, "a tester in a protection zone steps out first")
	ok(not world.tiles[zone.pos.x .. "," .. zone.pos.y .. ",7"].flags[TILESTATE_PROTECTIONZONE], "onto a tile outside the zone")
	ok(zone.pos.x > 903, "the nearest open ground: " .. zone.pos.x)
	runEvents(clock.ms + 4000)
	eq(X.testerProbe(zone).mine, X.testerProbe(zone).loose, "and its loot lies there")
	ok(X.testerProbe(zone).loose >= 5, "all of it")
	local open = newPlayer(21, 800, 800)
	open.name, open.tester = "Tester Open", true
	local r2 = X.testerRun(open)
	ok(r2 and not r2.moved and open.pos.x == 800, "a bot in the open is not moved")
	local plain = newPlayer(22, 900, 900)
	plain.name = "Plain Walker"
	local r3 = X.testerRun(plain)
	ok(r3 == nil and plain.pos.x == 900, "a player in a protection zone is never moved: nothing explodes")
	for _, id in ipairs({20, 21, 22}) do
		X.testerOrigins[id] = nil
	end
end

-- O671: a hunting bot walks on while the loot flies; the rings are read from the death tile of its last run
bot.pos = Position(802, 800, 7)
local drift = X.testerProbe(bot)
eq(drift.loose, probe.loose, "a bot two tiles off still finds all its loot (the first live run read ring 3 of its new tile)")
ok(drift.maxRing <= 2, "and the rings are the death tile's: " .. tostring(drift.maxRing))
eq(drift.at.x, 802, "the asker's place is where it stands now")
bot.pos = Position(812, 800, 7)
eq(X.testerProbe(bot).loose, 0, "a bot far from the death tile reads only what lies around itself")
bot.pos = Position(800, 800, 7)
-- ten bots share a hunt spot: the loot of another bot's run beside it, and an older run of its own, are not its state
do
	local other = newPlayer(9, 801, 801)
	other.name, other.tester = "Tester Neighbour", true
	local before = X.testerProbe(bot).loose
	ok(X.testerRun(other) ~= nil, "a neighbour's loot flies beside the bot")
	runEvents(clock.ms + 4000)
	local after = X.testerProbe(bot)
	eq(after.loose, before, "the neighbour's loot is not counted in the bot's state")
	eq(after.foreign, 0, "and is not 'another's loot' in it")
	local theirBag = makeBag(803, 803, 9, {{id = 2148, count = 3, stackable = true}})
	eq(X.testerProbe(bot).bagItems, 0, "a neighbour's bag with things in it is not the bot's loot left in the bag")
	theirBag:remove()
	ok(after.maxRing <= 2, "nor does it stretch the rings: " .. tostring(after.maxRing))
	eq(X.testerProbe(other).mine, X.testerProbe(other).loose, "the neighbour's own state is its own run")
	local older = X.testerRun(bot)
	ok(older ~= nil, "a second run of the bot")
	runEvents(clock.ms + 4000)
	eq(X.testerProbe(bot).loose, older.items, "after it the state holds that run's items and not the first run's")
	for _, p in ipairs({other, bot}) do
		X.testerOrigins[p:getId()] = nil
	end
end
-- O671: the stranger stands beside the owner's loot (TEST ONLY join): only a tester next to a tester
local stranger = newPlayer(2, 900, 900)
stranger.name = "Tester Bbb"
bot.name = "Tester Aaa"
local noJoin, noWhy = X.testerJoin(stranger, "Tester Aaa")
eq(noJoin, nil, "join: a player that is no tester is not moved")
ok(noWhy == "not a tester", "join: says so")
bot.tester, stranger.tester = true, true
local joined = X.testerJoin(stranger, "Tester Aaa")
ok(joined and math.max(math.abs(stranger.pos.x - 800), math.abs(stranger.pos.y - 800)) == 1, "join: the stranger stands on a tile next to the owner")
local sprobe = X.testerProbe(stranger)
ok(sprobe.foreign >= 5 and sprobe.mine == 0, "the stranger reads the owner's loot as another's")
eq(X.testerJoin(stranger, "Tester Nobody"), nil, "join: no such tester")
eq(X.testerJoin(stranger, "Tester Bbb"), nil, "join: not itself")
local ply = newPlayer(3, 800, 801)
ply.name = "Plain"
eq(X.testerJoin(stranger, "Plain"), nil, "join: never a player")
local took2, failed2 = X.lootAll(bot)
eq(took2, 12, "Loot all takes what the helper put there: both runs of the bot")
eq(X.testerProbe(bot).mine, 0, "and nothing of the bot's lies there after it (the neighbour's loot does)")
Chaos.lootExplosionConfig.enabled = false
local none, whyNot = X.testerRun(bot)
eq(none, nil, "off: the helper's bag does not explode")
ok(whyNot:find("off"), "and says why: " .. tostring(whyNot))
Chaos.lootExplosionConfig.enabled = true

-- ---------------------------------------------------------------- part 3: the other files
local glue = readFile("data/scripts/chaos/loot_explosion.lua")
ok(glue:find("drop:register(cfg.index)", 1, true), "the drop callback is registered at the config's index")
local lootCfg = dofile("data/scripts/chaos/loot_config.lua")
ok(cfg.index < lootCfg.emptyCorpseIndex, "the explosion runs before the empty corpse check")
ok(cfg.index > 8, "and after the globes (8), the autoloot (3, 3.5), the loot filter's finish (4.5) and the pouches (2.7)")
-- the attributes the loot layers write on the bag are the ones the items inherit
local seasonCfg = dofile("data/scripts/chaos/season_config.lua")
local inherit = {}
for _, name in ipairs(cfg.inheritAttributes) do
	inherit[name] = true
end
ok(inherit[seasonCfg.isolation.tagKey], "the season realm tag is inherited: " .. tostring(seasonCfg.isolation.tagKey))
ok(inherit[seasonCfg.modes.ownerKey], "the Self-Found owner is inherited: " .. tostring(seasonCfg.modes.ownerKey))
local mqCfg = dofile("data/scripts/chaos/mainquest_config.lua")
local strictSet = {}
for _, name in ipairs(cfg.strictAttributes) do
	strictSet[name] = true
end
ok(strictSet[mqCfg.questItem.quest], "main quest items are strict: " .. tostring(mqCfg.questItem.quest))
ok(strictSet["chaos_unique"] and strictSet["chaos_set"], "uniques and set pieces are strict")
local setLib = readFile("data/lib/chaos_item_sets.lua")
ok(setLib:find('S.ATTR = "chaos_set"', 1, true), "the set attribute is the one the sets write")
-- the quest item goes to the backpack when the bag exploded
local mq = readFile("data/scripts/chaos/mainquest.lua")
ok(mq:find("ChaosLootExplosion.isExploded", 1, true) and mq:find("not exploded", 1, true), "giveQuestItem skips an exploded bag")
-- the loot filter knows the kill after the explosion
local lf = readFile("data/scripts/chaos/lootfilter.lua")
ok(lf:find("function F.onExploded", 1, true) and lf:find("function F.killOf", 1, true) and lf:find("F.intoBags = intoBags", 1, true),
	"the loot filter exports what the explosion needs")
ok(lf:find("kill.exploded", 1, true), "an exploded kill draws no kill beam (the client beams the ground rows)")
-- the ground labels
local gl = readFile("data/scripts/chaos/groundloot.lua")
ok(gl:find('msg.action == "lootall"', 1, true), "the ground labels' opcode answers lootall")
ok(gl:find("LE.expiryLeft", 1, true) and gl:find("LE.visibleTo", 1, true), "the labels carry the timer and hide other players' loot")

-- 6. O674 (live run O671: 192 of 803 kills of the waystone maps' monsters left the stock Loot Bag 26691, the corpse their Lua files name, and
-- nothing flew): every id the corpse config counts as a loot bag explodes, read from the config and not written here
reset()
openGround(100, 100, 4)
load()
newPlayer(1)
ok(#corpseCfg.lootBagIds >= 1, "the corpse config lists the stock loot bag ids")
for _, id in ipairs(corpseCfg.lootBagIds) do
	ok(id ~= corpseCfg.bagId, "the list holds the other ids only: " .. id)
	local before = #loose()
	local stock = makeBag(100, 100, 1, {{id = 2148, count = 40, stackable = true}, {id = 2400, attrs = {rarity = 1}}, {id = 2401, attrs = {rarity = 2}}}, id)
	stock:setCustomAttribute("lf_kill", 77)
	runDrop(stock)
	ok(X.isExploded(stock), "a loot bag of id " .. id .. " is marked exploded")
	runEvents(clock.ms + 3000)
	eq(stock:getSize(), 0, "id " .. id .. ": everything is out of the bag")
	eq(#loose() - before, 3, "id " .. id .. ": the gold and the two items lie on the ground")
end
local notBag = makeBag(101, 100, 1, {{id = 2148, count = 5, stackable = true}}, 2590)
runDrop(notBag)
ok(not X.isExploded(notBag), "a container that is no loot bag id of the config does not explode")
eq(notBag:getSize(), 1, "and keeps its content")

os.time = realTime
print("loot_explosion_test: " .. checks .. " checks ok")
