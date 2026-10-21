-- Run from the server/ folder: luajit tests/prizes_test.lua (and lua5.3; CI runs both)
-- Prizes into the backpack (server/README.md "Prizes into the backpack"): prizes_core.lua (the roulette tile's winner,
-- the rare prize rule, the pool without the retired items, the exact odds of the base draw) and the glue prizes.lua on
-- a mocked engine: give (the backpack, a container in it, the store inbox, the ground; never an inventory slot; stacks
-- split at 100; charges), stow, toInbox (the store inbox, else the depot inbox, else nothing moved), rouletteReward (the
-- prize given, the free spin storage cleared, the broadcast; a tile with nothing, a creature or the ground: no crash,
-- nothing given, the next spin stays free). The base script side is tools/patch_prizes_test.py.

local checks, failures = 0, 0
local function ok(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	ok(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end
local function near(a, b, label)
	ok(math.abs(a - b) < 1e-9, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

-- ---------------------------------------------------------------- core
dofile("data/scripts/chaos/prizes_core.lua")
local K = ChaosPrizesCore

eq(K.winner(nil), nil, "nothing on the tile")
eq(K.winner({isItem = false}), nil, "a creature on the tile")
eq(K.winner({isItem = true, id = 406}, 406), nil, "the ground")
eq(K.winner({isItem = true, id = 18007}, 406, {18007, 18008}), nil, "an ignored decoration")
eq(K.winner({isItem = true, id = 0}), nil, "id 0")
local w = K.winner({isItem = true, id = 27822, count = 1}, 406, {18007})
eq(w and w.id, 27822, "a badge wins") eq(w and w.count, 1, "one of it") eq(w and w.charges, nil, "no charges")
w = K.winner({isItem = true, id = 2160, count = 37}, 406)
eq(w.count, 37, "a stack keeps its count")
w = K.winner({isItem = true, id = 32384, count = 1, charges = 500, showCharges = true}, 406)
eq(w.count, 1, "an item with charges is one item") eq(w.charges, 500, "its charges")
w = K.winner({isItem = true, id = 32384, count = 7, showCharges = true}, 406)
eq(w.charges, 7, "charges from the count when the tile item has none")

local pool = {{itemId = 1, chance = 7000}, {itemId = 2, chance = 800}, {itemId = 1, chance = 300}}
ok(K.isRare(pool, 2, 5000), "800 <= 5000 is rare")
ok(not K.isRare({{itemId = 1, chance = 7000}}, 1, 5000), "7000 > 5000 is not")
ok(K.isRare(pool, 1, 5000), "the lowest chance of an item counts")
ok(not K.isRare(pool, 9, 10000), "an item not in the pool is never broadcast")
ok(not K.isRare(pool, 2, nil), "no threshold: no broadcast")
ok(K.isRare({{itemId = 5, chance = 10000}}, 5, 10000), "threshold 10000 broadcasts everything (the premium roulette)")

local cleaned, gone = K.cleanPool({{itemId = 27633}, {itemId = 27822}, {itemId = 27797}},
	function(id) return id == 27633 or id == 27797 end)
eq(#cleaned, 1, "two retired entries out") eq(cleaned[1].itemId, 27822, "the badge stays")
eq(#gone, 2, "the ids taken out") eq(gone[1], 27633, "the deck first")

-- odds: one entry at 100 percent wins always; two equal entries split; the sum is 1
local o = K.odds({{chance = 10000}})
near(o[1], 1, "one sure entry")
o = K.odds({{chance = 5000}, {chance = 5000}})
near(o[1], 0.5, "two equal entries split") near(o[2], 0.5, "the other half")
o = K.odds({{chance = 10000}, {chance = 10000}, {chance = 0}})
near(o[1], 0.5, "two sure entries") near(o[3], 0, "a 0 chance never wins")
-- brute force over the hit sets for a small uneven pool
local small = {{chance = 7000}, {chance = 2500}, {chance = 800}}
o = K.odds(small)
local p = {0.7, 0.25, 0.08}
local exact, none = {0, 0, 0}, (1 - p[1]) * (1 - p[2]) * (1 - p[3])
for mask = 1, 7 do
	local pr, hits = 1, {}
	for i = 1, 3 do
		local hit = math.floor(mask / 2 ^ (i - 1)) % 2 == 1
		pr = pr * (hit and p[i] or (1 - p[i]))
		if hit then hits[#hits + 1] = i end
	end
	for _, i in ipairs(hits) do exact[i] = exact[i] + pr / #hits end
end
for i = 1, 3 do near(o[i], exact[i] / (1 - none), "odds of entry " .. i .. " by brute force") end

-- the boss roulette's pool (the base chances) before and after the retired entries go
local BOSS = {
	{itemId = 27633, chance = 7000}, {itemId = 27822, chance = 6800}, {itemId = 27808, chance = 6500},
	{itemId = 27804, chance = 6100}, {itemId = 27634, chance = 5800}, {itemId = 27812, chance = 5000},
	{itemId = 27826, chance = 4800}, {itemId = 27797, chance = 4400}, {itemId = 27817, chance = 4100},
	{itemId = 27831, chance = 3500}, {itemId = 27835, chance = 3000}, {itemId = 27839, chance = 2500},
	{itemId = 27547, chance = 800}, {itemId = 27595, chance = 800}, {itemId = 27613, chance = 800},
	{itemId = 27571, chance = 800},
}
local RETIRED = {[27633] = true, [27634] = true, [27797] = true}
local before, after = K.odds(BOSS), nil
local boss2 = K.cleanPool(BOSS, function(id) return RETIRED[id] end)
eq(#boss2, 13, "13 prizes left in the boss roulette")
after = K.odds(boss2)
local function total(t) local s = 0 for _, v in pairs(t) do s = s + v end return s end
near(total(before), 1, "the old odds sum to 1") near(total(after), 1, "the new odds sum to 1")
local retiredBefore = before[1] + before[5] + before[8]
ok(retiredBefore > 0.27 and retiredBefore < 0.28, "a deck or ship was 27.8 percent of the boss spins")
-- every remaining prize gets more likely, the order of the chances is kept
for i, e in ipairs(boss2) do
	local j
	for k, b in ipairs(BOSS) do if b.itemId == e.itemId then j = k end end
	ok(after[i] > before[j], "prize " .. e.itemId .. " is more likely now")
	if i > 1 then ok(after[i] <= after[i - 1] + 1e-12, "the order of the chances is kept at " .. i) end
end
local lv6 = after[10] + after[11] + after[12] + after[13]
ok(lv6 > 0.064 and lv6 < 0.065, "the four 800 prizes: 4.8 percent of the spins before, 6.4 now")
if os.getenv("PRIZES_ODDS") then
	for i, e in ipairs(BOSS) do print(string.format("before %d %.2f", e.itemId, before[i] * 100)) end
	for i, e in ipairs(boss2) do print(string.format("after %d %.2f", e.itemId, after[i] * 100)) end
end

-- ---------------------------------------------------------------- mocked engine
MESSAGE_INFO_DESCR = 22
MESSAGE_EVENT_ADVANCE = 19
RETURNVALUE_NOERROR = 0
RETURNVALUE_NOTENOUGHROOM = 5
CONST_SLOT_BACKPACK = 3
INDEX_WHEREEVER = -1
FLAG_NOLIMIT, FLAG_IGNOREAUTOSTACK = 1, 32
ITEM_ATTRIBUTE_CHARGES = 4

local STACKABLE = {[2160] = true}
local SHOWCHARGES = {[32384] = true}
local NAMES = {[27797] = "The Awakener", [27822] = "Furious Badge", [2160] = "crystal coin", [32384] = "exercise rod"}
function ItemType(id)
	return {
		isStackable = function() return STACKABLE[id] or false end,
		hasShowCharges = function() return SHOWCHARGES[id] or false end,
		getName = function() return NAMES[id] or ("item " .. id) end,
	}
end

local function newItem(id, count)
	local it = {id = id, count = count or 1, attrs = {}, parent = nil}
	function it:getId() return self.id end
	function it:getCount() return self.count end
	function it:getName() return NAMES[self.id] or ("item " .. self.id) end
	function it:isItem() return true end
	function it:isContainer() return self.cap ~= nil end
	function it:getCharges() return self.attrs[ITEM_ATTRIBUTE_CHARGES] or 0 end
	function it:setAttribute(k, v) self.attrs[k] = v end
	function it:moveTo(target, flags)
		if target.full then return false end
		target.items[#target.items + 1] = self
		target.flags = flags
		if self.parent then self.parent[self.slot] = nil end
		self.parent, self.slot = target, nil
		return true
	end
	return it
end
local function newContainer(cap)
	local c = newItem(1988, 1)
	c.cap, c.items = cap, {}
	function c:addItemEx(item, index, flags)
		if #self.items >= self.cap and not (flags and flags % 2 == 1 and self.nolimit) then
			return RETURNVALUE_NOTENOUGHROOM
		end
		self.items[#self.items + 1] = item
		item.parent = self
		self.lastIndex, self.lastFlags = index, flags
		return RETURNVALUE_NOERROR
	end
	function c:getItems(recursive)
		local out = {}
		for _, i in ipairs(self.items) do
			out[#out + 1] = i
			if recursive and i.items then
				for _, j in ipairs(i:getItems(true)) do out[#out + 1] = j end
			end
		end
		return out
	end
	return c
end

local made = {}
local broadcasts = {}
Game = {
	createItem = function(id, count)
		if id == 99999 then return nil end
		local it = newItem(id, count)
		made[#made + 1] = it
		return it
	end,
	broadcastMessage = function(text, kind) broadcasts[#broadcasts + 1] = text end,
}

local tiles = {}
function Tile(pos)
	return pos and tiles[pos.x] or nil
end
local function newTile(x, groundId)
	local t = {items = {}, ground = groundId and newItem(groundId) or nil}
	function t:getGround() return self.ground end
	function t:getTopVisibleThing() return self.top end
	function t:addItemEx(item, flags)
		if self.blocked then return RETURNVALUE_NOTENOUGHROOM end
		self.items[#self.items + 1] = item
		return RETURNVALUE_NOERROR
	end
	tiles[x] = t
	return t
end

local players = {}
function Player(id)
	if type(id) == "table" then return id end
	return players[id]
end
local function newPlayer(id, bpCap, storeCap)
	local p = {id = id, msgs = {}, storage = {}, slots = {}, pos = {x = 100}}
	p.slots[CONST_SLOT_BACKPACK] = bpCap and newContainer(bpCap) or nil
	p.store = newContainer(storeCap or 100)
	p.depot = newContainer(100)
	p.depot.full = false
	function p:getId() return self.id end
	function p:getName() return "Tester" end
	function p:getSlotItem(slot) return self.slots[slot] end
	function p:getStoreInbox() return self.store end
	function p:getInbox() return self.depot end
	function p:getPosition() return self.pos end
	function p:sendTextMessage(kind, text) self.msgs[#self.msgs + 1] = text end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:addItem() error("addItem must never be called: it can reach an inventory slot") end
	function p:addItemEx() error("addItemEx must never be called: it can reach an inventory slot") end
	players[id] = p
	return p
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/prizes.lua")
local P = ChaosPrizes
local realPrint = print
print = function() end -- the glue logs; keep the test output short

-- ---------------------------------------------------------------- give
newTile(100, 406)
local pl = newPlayer(1, 20)
eq(P.give(pl, 27797, 1), "backpack", "a ship goes into the backpack")
eq(#pl.slots[CONST_SLOT_BACKPACK].items, 1, "it is in the backpack") eq(#pl.msgs, 0, "no message for the backpack")
eq(pl.slots[CONST_SLOT_BACKPACK].items[1].id, 27797, "the ship")

pl = newPlayer(2, 1)
local inner = newContainer(5)
pl.slots[CONST_SLOT_BACKPACK].items[1] = inner
eq(P.give(pl, 27822, 1), "backpack", "a full backpack: a container in it")
eq(#inner.items, 1, "the prize is in the inner bag")

pl = newPlayer(3, 0)
pl.store.nolimit = true
eq(P.give(pl, 27797, 1), "store inbox", "no room: the store inbox")
eq(pl.store.items[1].id, 27797, "the ship in the Purse") eq(pl.store.lastFlags, FLAG_NOLIMIT, "with FLAG_NOLIMIT")
ok(pl.msgs[1] and pl.msgs[1]:find("Purse") and pl.msgs[1]:find("The Awakener"), "the player is told: " .. tostring(pl.msgs[1]))

pl = newPlayer(4, nil, 0)
eq(P.give(pl, 27797, 1), "ground", "no backpack, full store inbox: the ground")
eq(tiles[100].items[#tiles[100].items].id, 27797, "the ship lies under the player")
ok(pl.msgs[1] and pl.msgs[1]:find("ground"), "the player is told it is on the ground")

pl = newPlayer(5, nil, 0)
tiles[100].blocked = true
eq(P.give(pl, 27797, 1), nil, "nowhere at all: nil (the caller falls back)")
tiles[100].blocked = false

pl = newPlayer(6, 10)
eq(P.give(pl, 2160, 250), "backpack", "a stack of 250")
local bp = pl.slots[CONST_SLOT_BACKPACK]
eq(#bp.items, 3, "split into 100 + 100 + 50")
eq(bp.items[1].count + bp.items[2].count + bp.items[3].count, 250, "all 250 given")
eq(bp.items[3].count, 50, "the rest last")

pl = newPlayer(7, 10)
eq(P.give(pl, 27822, 3), "backpack", "three of a non stackable item")
eq(#pl.slots[CONST_SLOT_BACKPACK].items, 3, "three items")

pl = newPlayer(8, 10)
eq(P.give(pl, 32384, 1, 500), "backpack", "an item with charges")
eq(pl.slots[CONST_SLOT_BACKPACK].items[1]:getCharges(), 500, "its charges set")

pl = newPlayer(9, 1)
pl.store.nolimit = true
eq(P.give(pl, 27822, 2), "store inbox", "the worst place is reported (one in the backpack, one in the Purse)")
eq(#pl.slots[CONST_SLOT_BACKPACK].items + #pl.store.items, 2, "both given")

eq(P.give(pl, 99999, 1), nil, "an item the engine can't make: nil")
eq(P.give(nil, 27822, 1), nil, "no player: nil")
eq(P.give(pl, nil, 1), nil, "no id: nil")

-- ---------------------------------------------------------------- stow
pl = newPlayer(10, 1)
local it = newItem(27822)
eq(P.stow(pl, it), RETURNVALUE_NOERROR, "stow into the backpack")
eq(P.stow(pl, newItem(27822)), nil, "a full backpack without bags: nil")
pl = newPlayer(11, nil)
eq(P.stow(pl, newItem(27822)), nil, "no backpack: nil")

-- ---------------------------------------------------------------- toInbox
pl = newPlayer(12, 5)
local ship = newItem(27797)
pl.slots[14] = ship
ship.parent, ship.slot = pl.slots, 14
eq(P.toInbox(pl, ship), "store inbox", "a worn ship goes to the store inbox")
eq(pl.slots[14], nil, "out of the slot") eq(pl.store.flags, FLAG_NOLIMIT + FLAG_IGNOREAUTOSTACK, "no limit, no merge")
pl = newPlayer(13, 5)
pl.store.full = true
eq(P.toInbox(pl, newItem(27797)), "inbox", "a full store inbox: the depot inbox")
pl.depot.full = true
eq(P.toInbox(pl, newItem(27797)), nil, "both full: nothing moved (never deleted)")

-- ---------------------------------------------------------------- rouletteReward
local function roulette(threshold)
	return {
		rouletteOptions = {rareItemChance_broadcastThreshold = threshold or 5000, ignoredItems = {18007, 18008},
			rouletteStorage = 48550},
		prizePool = {{itemId = 27822, chance = 6800}, {itemId = 27547, chance = 800}},
	}
end
local winTile = newTile(7, 406)
local WIN = {x = 7}

pl = newPlayer(20, 10)
pl.storage[48550] = 1
winTile.top = newItem(27822)
broadcasts = {}
ok(P.rouletteReward(20, roulette(), WIN, "boss"), "a prize is given")
eq(pl.slots[CONST_SLOT_BACKPACK].items[1].id, 27822, "into the backpack") eq(pl.storage[48550], -1, "the free spin is used")
eq(#broadcasts, 0, "6800 is not rare")

pl = newPlayer(21, 10)
pl.storage[48550] = 1
winTile.top = newItem(27547)
ok(P.rouletteReward(21, roulette(), WIN, "boss"), "a rare prize")
eq(broadcasts[1], "The player Tester has won item 27547 from the boss roulette!", "the broadcast is kept")

for label, top in pairs({nothing = false, creature = {isItem = function() return false end},
		ground = winTile.ground, decoration = newItem(18007)}) do
	pl = newPlayer(22, 10)
	pl.storage[48550] = 1
	winTile.top = top or nil
	broadcasts = {}
	local okCall, res = pcall(P.rouletteReward, 22, roulette(), WIN, "boss")
	ok(okCall, label .. ": no crash (" .. tostring(res) .. ")")
	ok(okCall and res == false, label .. ": nothing given")
	eq(#pl.slots[CONST_SLOT_BACKPACK].items, 0, label .. ": the backpack is empty")
	eq(pl.storage[48550], 1, label .. ": the next spin stays free")
	ok(pl.msgs[1] and pl.msgs[1]:find("free"), label .. ": the player is told")
	eq(#broadcasts, 0, label .. ": no broadcast")
end

local noTile = {x = 999}
pl = newPlayer(23, 10)
ok(pcall(P.rouletteReward, 23, roulette(), noTile, "boss"), "no tile at that position: no crash")
ok(pcall(P.rouletteReward, 23, roulette(), nil, "boss"), "no position: no crash")
eq(P.rouletteReward(999, roulette(), WIN, "boss"), false, "the player logged out: nothing")

-- nowhere to put it: nothing given, the spin stays free
pl = newPlayer(24, nil, 0)
pl.storage[48550] = 1
winTile.top = newItem(27822)
tiles[100].blocked = true
eq(P.rouletteReward(24, roulette(), WIN, "boss"), false, "no room anywhere: false")
eq(pl.storage[48550], 1, "no room anywhere: the next spin stays free")
tiles[100].blocked = false

_G.print = realPrint
print(string.format("prizes_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
