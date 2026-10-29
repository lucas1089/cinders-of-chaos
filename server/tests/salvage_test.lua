-- Run from the server/ folder: luajit tests/salvage_test.lua (and lua5.3; CI runs both)
-- Salvage: the pure rules of salvage_core.lua with the real salvage_config.lua (yields per rarity and item level, the
-- orb chance, what is refused, the lock, "salvage all" with its cap and skips, the confirm signature, combining shards,
-- the economy against the stock rarity roll), then salvage.lua against a mocked engine and bench (single salvage, the
-- refusals, the lock, a batch with the cap and a changed backpack, combining, the log rows, the look text).
dofile("data/scripts/chaos/salvage_core.lua")
local K = ChaosSalvageCore
local cfg = dofile("data/scripts/chaos/salvage_config.lua")

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local function gear(rarity, level, o)
	o = o or {}
	local info = {gear = true, rarity = rarity, level = level or (rarity * 10 - 9), sockets = o.sockets or 0,
		gems = o.gems or 0, highTiers = o.highTiers or 0, locked = o.locked or false, unique = o.unique or false,
		riftKey = o.riftKey or false, stackable = o.stackable or false, inBackpack = o.inBackpack}
	if o.gear == false then
		info.gear = false
	end
	return info
end

-- ---------------------------------------------------------------- config sanity
eq(#cfg.baseShards, 6, "a yield per rarity (Common .. Divine)")
eq(#cfg.orbChance, 6, "an orb chance per rarity")
local known = {transmutation = 1, alchemy = 1, exalted = 1, annulment = 1, scouring = 1, chaos = 1, divine = 1, sockets = 1,
	tempering = 1, binding = 1, excision = 1, reforging = 1, ruin = 1, whetstone = 1, ember = 1, crown = 1,
	void = 1}
for i = 2, 6 do
	assert(cfg.baseShards[i] >= cfg.baseShards[i - 1], "yield never falls with the rarity")
	assert(cfg.orbChance[i] >= cfg.orbChance[i - 1], "orb chance never falls with the rarity")
end
for _, w in ipairs(cfg.orbWeights) do
	assert(known[w[1]], "orb weight for a known orb: " .. w[1])
end
local seen = {}
for _, r in ipairs(cfg.recipes) do
	assert(known[r.key], "recipe for a known orb: " .. r.key)
	assert(not seen[r.key], "one recipe per orb")
	seen[r.key] = true
	assert(r.cost >= 5, "no orb for less than 5 shards")
end
-- recipe costs follow reference coin prices (about 2.5 shards per coin): the cheap orbs cheap, the Grafting dearest. The
-- store sells only Whetstones, Excision and Binding; the other values are reference prices, not store offers
local store = {transmutation = 5, chaos = 10, scouring = 12, alchemy = 15, annulment = 20, divine = 25, sockets = 25, exalted = 40,
	whetstone = 2, tempering = 8, reforging = 20, excision = 25, binding = 30, ruin = 60, ember = 20, crown = 40, void = 50}
for _, r in ipairs(cfg.recipes) do
	local ratio = r.cost / store[r.key]
	assert(ratio >= 2.3 and ratio <= 2.7, "shards per coin for " .. r.key .. ": " .. ratio)
end
-- Ember / Crown Shards -> their orb: own keys, a known orb, the item names install_orbs.py writes, and costs that stay
-- in proportion to the orbs' reference prices over the shards' drop rates (README "Shards into orbs")
local renames = {}
for _, r in ipairs(dofile("data/lib/chaos_orbs_config.lua").renames) do
	renames[r.id] = r
end
eq(#cfg.shardRecipes, 3, "Ember, Crown and Void Shards")
for _, r in ipairs(cfg.shardRecipes) do
	assert(not seen[r.key] and not known[r.key], "a shard recipe key of its own: " .. r.key)
	seen[r.key] = true
	assert(known[r.orb], "a shard recipe makes a known orb: " .. r.orb)
	assert(renames[r.input], "the input is a renamed base currency item: " .. r.input)
	eq(r.name, renames[r.input].name, "the shard's name")
	eq(r.plural, renames[r.input].plural, "the shard's plural")
	assert(r.cost >= 1000 and r.cost <= 3000, "an orb takes hours of waystone shards: " .. r.cost)
end
local emberR, crownR = K.shardRecipe("embershard", cfg), K.shardRecipe("crownshard", cfg)
eq(emberR.orb .. "/" .. emberR.input .. "/" .. emberR.cost, "ember/29852/1000", "Ember Shards -> Ember Orb")
eq(crownR.orb .. "/" .. crownR.input .. "/" .. crownR.cost, "crown/29853/1000", "Crown Shards -> Crown Orb")
-- owner, 2026-10-21: "pode deixar 1000 shards por orb" (both orbs, the same count)
eq(emberR.cost, crownR.cost, "the same shard count for both orbs")
local voidR = K.shardRecipe("voidshard", cfg)
eq(voidR.orb .. "/" .. voidR.input .. "/" .. voidR.cost, "void/29854/1000", "Void Shards -> Void Orb (the same count)")
local lootSlots = math.min(dofile("data/scripts/chaos/pouches_config.lua").kinds.loot.capacity, 255) -- a bag filled to one batch
-- the Loot Bag has 500 slots since 2026-10-29 (paged window of 250): one batch covers a page, a second click the rest
assert(cfg.batchCap >= lootSlots, "one batch covers a filled bag: " .. cfg.batchCap)
assert(cfg.batchCap <= 255, "a batch stays inside one container's slots")
assert(not cfg.allowUniques, "uniques are not salvaged")

-- ---------------------------------------------------------------- yields
eq(K.shards(gear(1, 1), cfg), 1, "Common, item level 1")
eq(K.shards(gear(1, 150), cfg), 1, "Common, item level 150: floor(1.5)")
eq(K.shards(gear(3, 1), cfg), 2, "Magic at item level 1")
eq(K.shards(gear(3, 150), cfg), 3, "Magic at 150: +50%")
eq(K.shards(gear(5, 75), cfg), 6, "Legendary at 75: floor(6.25)")
eq(K.shards(gear(5, 150), cfg), 7, "Legendary at 150")
eq(K.shards(gear(10, 1), cfg), 12, "Divine at 1")
eq(K.shards(gear(10, 150), cfg), 18, "Divine at 150")
eq(K.shards(gear(7, 1), cfg), 5, "an old Mythic is Legendary")
eq(K.shards(gear(15, 1), cfg), 12, "an old Transcendent is Divine")
eq(K.shards(gear(15, 150), cfg), 18, "an old Transcendent at 150")
eq(K.shards(gear(5, 0), cfg), 5, "no item level counts as the bottom")
eq(K.shards(gear(5, 999), cfg), 7, "above the top counts as the top")
eq(K.shards(gear(4, 1, {highTiers = 2}), cfg), 5, "+1 per modifier of T6 or better")
eq(K.shards(gear(4, 1, {sockets = 3}), cfg), 6, "+1 per empty socket")
eq(K.shards(gear(99, 0), cfg), cfg.baseShards[1], "an id out of range counts as Common")
eq(K.orbChance(gear(1), cfg), 50, "0.5% on a Common")
eq(K.orbChance(gear(10), cfg), 300, "3% on a Divine")
eq(K.orbChance(gear(15), cfg), 300, "an old Transcendent is Divine")
eq(K.percent(50), "0.5", "percent text")
eq(K.percent(100), "1", "whole percent")
eq(K.percent(75), "0.75", "two decimals")

-- ---------------------------------------------------------------- checks and the lock
eq(K.check(gear(3), cfg), nil, "a rolled item may be salvaged")
eq(K.check(gear(3, nil, {locked = true}), cfg), "locked", "locked")
eq(K.check(gear(3, nil, {unique = true}), cfg), "unique", "unique")
-- a unique with a Conquest Token value (conquest.lua) may be salvaged: tokens + uniqueShards shards
do
	local u = gear(0, 60, {unique = true})
	u.tokens = 69
	eq(K.check(u, cfg), nil, "a unique salvages for Conquest Tokens")
	eq(K.shards(u, cfg), cfg.uniqueShards, "its fixed shards")
	local roll = K.roll(u, cfg, function(a) return 10000 end)
	eq(roll.tokens, 69, "the tokens are in the roll")
	eq(K.preview(u, cfg).tokens, 69, "the bench shows them")
	u.tokens = 0
	eq(K.check(u, cfg), "unique", "without a token value it stays refused")
	local off = {}
	for k, v in pairs(cfg) do off[k] = v end
	off.uniqueTokens = false
	u.tokens = 69
	eq(K.check(u, off), "unique", "switched off: refused")
	eq(K.batch({u}, 15, cfg).count, 0, "salvage all never takes a unique")
end
eq(K.check(gear(0), cfg), "normal", "no rarity")
eq(K.check(gear(3, nil, {gems = 1, sockets = 2}), cfg), "gems", "socketed gems: take them out first")
eq(K.check(gear(3, nil, {sockets = 2}), cfg), nil, "empty sockets are fine")
eq(K.check(gear(0, 0, {riftKey = true, gear = false}), cfg), "riftKey", "Rift Key")
eq(K.check(gear(3, nil, {gear = false}), cfg), "notGear", "not gear")
eq(K.check(gear(3, nil, {stackable = true}), cfg), "stack", "stack")
eq(K.check(gear(3, nil, {inBackpack = false}), cfg), "notBackpack", "equipped / outside the backpack")
eq(K.check(nil, cfg), "notGear", "nothing")
eq(K.check(gear(3, nil, {locked = true, unique = true}), cfg), "locked", "the lock is named first")
eq(K.isLocked(nil), false, "no attribute")
eq(K.isLocked(0), false, "0")
eq(K.isLocked(1), true, "1")
eq(K.isLocked("1"), true, "string 1")
eq(K.isLocked("0"), false, "string 0")
for reason in pairs({locked = 1, unique = 1, normal = 1, gems = 1, riftKey = 1, notGear = 1, stack = 1, notBackpack = 1,
	unknownRecipe = 1, shards = 1, count = 1}) do
	assert(type(K.reasons[reason]) == "string", "a text for " .. reason)
end
local p = K.preview(gear(5, 150), cfg)
eq(p.ok, true, "preview ok")
eq(p.shards, 7, "preview shards")
eq(p.orbChance, "1.5", "preview orb chance")
p = K.preview(gear(5, 50, {locked = true}), cfg)
eq(p.ok, false, "preview refused")
eq(p.why, K.reasons.locked, "preview reason")
eq(p.locked, true, "preview marks the lock")

-- ---------------------------------------------------------------- the roll
local function seq(values)
	local i = 0
	return function(a, b)
		i = i + 1
		local v = values[i] or a
		assert(v >= a and v <= b, "roll in range")
		return v
	end
end
local r = K.roll(gear(4, 41), cfg, seq({101}))
eq(r.shards, 3, "roll shards")
eq(r.orb, nil, "101 > 100: no orb")
r = K.roll(gear(4, 41), cfg, seq({100, 1}))
eq(r.orb, "transmutation", "100 <= 100: an orb, the first by weight")
r = K.roll(gear(4, 41), cfg, seq({1, 100}))
eq(r.orb, "exalted", "the last weight")
-- the orb mix over many rolls follows the weights
math.randomseed(7)
local counts, orbs = {}, 0
for _ = 1, 200000 do
	local x = K.roll(gear(10, 141), cfg, math.random)
	if x.orb then
		orbs = orbs + 1
		counts[x.orb] = (counts[x.orb] or 0) + 1
	end
end
assert(orbs > 5400 and orbs < 6600, "3% orbs on Divine: " .. orbs)
assert(counts.transmutation > counts.chaos and counts.chaos > counts.exalted, "Transmutation most, Exalted least")

-- ---------------------------------------------------------------- economy: the stock rarity roll
-- default_onDropLoot.lua: 70% of gear passes, then each rarity in order with its own chance (ChaosRarity.stockRolls)
local left, total, shards, orbChance = 1, 0, 0, 0
for rank, row in ipairs(ChaosRarity.stockRolls) do
	local c = row.chance
	local pr = left * c / 100
	left = left * (1 - c / 100)
	total = total + pr
	local s = 0
	for lv = rank * 20 - 19, rank * 20 do -- the better rarities come from the better levels
		s = s + K.shards(gear(row.id, lv), cfg)
	end
	shards = shards + pr * s / 20
	orbChance = orbChance + pr * K.orbChance(gear(row.id), cfg)
end
shards, orbChance = shards / total, orbChance / total / 10000
assert(shards > 2.0 and shards < 3.5, "an average rolled drop gives 2-3.5 shards: " .. shards)
assert(orbChance > 0.005 and orbChance < 0.015, "about 1% orb chance per item: " .. orbChance)
-- an Orb of Upheaval's worth of shards takes about 10 rolled items (without modifiers and sockets)
local chaosCost = K.recipe("chaos", cfg).cost
assert(chaosCost / shards >= 8, "at least 8 rolled items per Orb of Upheaval: " .. chaosCost / shards)

-- ---------------------------------------------------------------- salvage all
local list = {}
local CAP = cfg.batchCap
for i = 1, CAP + 10 do
	list[i] = gear(1 + (i % 2), nil) -- Common / Uncommon
end
local b = K.batch(list, 2, cfg)
eq(b.count, CAP, "cap of batchCap items")
eq(b.capped, true, "capped")
eq(b.skipped.cap, 10, "10 left for the next batch")
eq(b.shards, CAP, "1 shard each")
eq(b.picked[1], 1, "in container order")
eq(b.picked[CAP], CAP, "the first batchCap")
list = {gear(1), gear(3), gear(2, nil, {locked = true}), gear(1, nil, {unique = true}), gear(2, nil, {gems = 1, sockets = 1}),
	gear(0), gear(0, 0, {gear = false, stackable = true}), gear(0, 0, {riftKey = true, gear = false}), gear(2, 20)}
b = K.batch(list, 2, cfg)
eq(b.count, 2, "two of the list")
eq(b.picked[1], 1, "the Common")
eq(b.picked[2], 9, "the Uncommon")
eq(b.skipped.above, 1, "the Rare is above the chosen rarity")
eq(b.skipped.locked, 1, "locked skipped")
eq(b.skipped.unique, 1, "unique skipped")
eq(b.skipped.gems, 1, "socketed skipped")
eq(b.skipped.normal, nil, "normal items are not counted")
eq(b.capped, false, "not capped")
b = K.batch(list, 15, cfg)
eq(b.count, 3, "with every rarity the Rare comes too")
eq(K.batch(list, 0, cfg).maxRarity, 1, "maxRarity clamped to 1..15")
eq(K.batch({}, 3, cfg).count, 0, "an empty bag")
-- the confirm signature
local s1 = K.signature({"0:2400;3;25", "1:2466;1;5"})
eq(s1, K.signature({"0:2400;3;25", "1:2466;1;5"}), "same list, same signature")
assert(s1 ~= K.signature({"1:2466;1;5", "0:2400;3;25"}), "order matters")
assert(s1 ~= K.signature({"0:2400;3;26", "1:2466;1;5"}), "a changed item changes it")
assert(s1 ~= K.signature({"0:2400;3;25"}), "a missing item changes it")
eq(K.signature({}), "0:5381", "empty")

-- ---------------------------------------------------------------- combining
local ok, cost = K.combineCheck(25, "chaos", 1, cfg)
eq(ok, true, "25 shards make an Orb of Upheaval")
eq(cost, 25, "cost")
ok, cost = K.combineCheck(24, "chaos", 1, cfg)
eq(ok, nil, "24 do not")
eq(cost, "shards", "reason")
ok, cost = K.combineCheck(1000, "chaos", 10, cfg)
eq(cost, 250, "ten at once")
eq(select(2, K.combineCheck(1000, "chaos", 11, cfg)), "count", "more than maxCombine")
eq(select(2, K.combineCheck(1000, "chaos", 0, cfg)), "count", "zero")
eq(select(2, K.combineCheck(1000, "mirror", 1, cfg)), "unknownRecipe", "unknown orb")
-- the shard recipes: the owned count is the recipe's own input
ok, cost = K.combineCheck(1000, "embershard", 1, cfg)
eq(ok, true, "1,000 Ember Shards make an Ember Orb")
eq(cost, 1000, "and cost 1,000")
eq(select(2, K.combineCheck(999, "embershard", 1, cfg)), "input", "one Ember Shard short")
eq(K.reasonText("input", emberR), "You do not have enough Ember Shards.", "the reason names the shards")
eq(K.reasonText("shards", nil), K.reasons.shards, "a plain reason")
ok, cost = K.combineCheck(10000, "crownshard", 10, cfg)
eq(cost, 10000, "ten Crown Orbs")
eq(select(2, K.combineCheck(1e6, "crownshard", 11, cfg)), "count", "more than maxCombine")
eq(K.anyRecipe("chaos", cfg).cost, 25, "anyRecipe finds a rune shard recipe")
eq(K.anyRecipe("embershard", cfg), emberR, "and a shard recipe")
eq(K.inputRecipe(29853, cfg), crownR, "the recipe that eats Crown Shards")
eq(K.inputRecipe(cfg.shard.id, cfg), nil, "rune shards are no shard recipe input")
eq(K.shardHint(emberR, "Ember Orb"), "Combine 1,000 at the Crafting Bench (Salvage tab) into an Ember Orb.", "the Ember hint")
eq(K.shardHint(crownR, "Crown Orb"), "Combine 1,000 at the Crafting Bench (Salvage tab) into a Crown Orb.", "the Crown hint")
eq(K.thousands(17500), "17,500", "thousands")
eq(select(2, K.recycleCheck(5, "embershard", 1, cfg)), "unknownRecipe", "no recycling into Ember Shards")

-- recycling: an orb back into shards at recycleShare of its recipe cost, always less than the cost
eq(K.recycleShards("chaos", cfg), 10, "an Orb of Upheaval (25) recycles into 10 shards")
eq(K.recycleShards("whetstone", cfg), 2, "a Whetstone (5): 2")
ok, cost = K.recycleCheck(7, "chaos", 7, cfg)
eq(cost, 70, "seven at once")
eq(select(2, K.recycleCheck(6, "chaos", 7, cfg)), "orbs", "not that many")
eq(select(2, K.recycleCheck(500, "chaos", 101, cfg)), "count", "more than maxRecycle")
eq(select(2, K.recycleCheck(5, "mirror", 1, cfg)), "unknownRecipe", "unknown orb")
for _, r in ipairs(cfg.recipes) do
	assert(K.recycleShards(r.key, cfg) < r.cost, r.key .. ": recycling loses shards")
end

-- ================================================================ salvage.lua against a mocked engine
RETURNVALUE_NOERROR, INDEX_WHEREEVER, FLAG_NOLIMIT, MESSAGE_INFO_DESCR = 0, -1, 1, 22
CONST_ME_BLOCKHIT, CONST_ME_MAGIC_GREEN = 9, 13
local registered = {}
local function obj(name)
	local o = {name = name}
	function o:register() registered[#registered + 1] = self end
	function o:separator() end
	function o:id(id) self.itemId = id end
	return o
end
function CreatureEvent(name) return obj(name) end
function TalkAction(words) return obj(words) end
function Action() return obj("action") end
local lookFn
EventCallback = setmetatable({}, {
	__index = function(_, k)
		if k == "register" then return function() end end
	end,
	__newindex = function(_, k, v) if k == "onLook" then lookFn = v end end
})
local queries = {}
db = {query = function(q) queries[#queries + 1] = q return true end, escapeString = function(s) return "'" .. s .. "'" end}
Chaos = {toInt = function(v, lo, hi)
	local n = tonumber(v)
	if not n then return nil end
	n = math.floor(n)
	if (lo and n < lo) or (hi and n > hi) then return nil end
	return n
end}
ChaosOpcodes = {crafting = 232}
local STACKABLE = {[cfg.shard.id] = true, [29856] = true, [29851] = true, [29852] = true, [29853] = true, [32258] = true, [32259] = true}
function ItemType(id)
	return {getId = function() return id end, getClientId = function() return id - 1000 end,
		isStackable = function() return STACKABLE[id] == true end}
end

-- items and containers
local Item = {}
Item.__index = Item
local function newItem(id, o)
	o = o or {}
	return setmetatable({id = id, count = o.count or 1, custom = o.custom or {}, container = o.container,
		items = o.container and {} or nil, size = o.size or 20}, Item)
end
function Item:getId() return self.id end
function Item:getCount() return self.count end
function Item:isItem() return true end
function Item:isContainer() return self.container == true end
function Item:getSize() return self.size end
function Item:getItem(i) return self.items[i + 1] end
function Item:getType() local id = self.id return {isStackable = function() return STACKABLE[id] == true end} end
function Item:getCustomAttribute(k) return self.custom[k] end
function Item:setCustomAttribute(k, v) self.custom[k] = v end
function Item:removeCustomAttribute(k) self.custom[k] = nil end
function Item:getParent() return self.parent end
function Item:getTopParent()
	local it = self
	while it.parent do it = it.parent end
	return it
end
function Item:remove()
	if self.parent then
		for i, it in ipairs(self.parent.items) do
			if it == self then table.remove(self.parent.items, i) break end
		end
	end
	self.removed = true
	return true
end
local function put(container, item)
	container.items[#container.items + 1] = item
	item.parent = container
	return item
end

local backpack = newItem(1988, {container = true, size = 400})
local inbox = newItem(14404, {container = true, size = 1000})
function inbox:addItemEx(item) put(self, item) return RETURNVALUE_NOERROR end
local full = false
local player = {id = 1, guid = 7, effects = 0, messages = {}}
function player:getId() return self.id end
function player:getGuid() return self.guid end
function player:getInbox() return inbox end
function player:getSlotItem(slot) return self.slots and self.slots[slot] or nil end
function player:getContainerById(cid) return self.open and self.open[cid] or nil end
function player:getContainerIndex(cid) return self.pages and self.pages[cid] or 0 end
function player:getPosition() return {sendMagicEffect = function() player.effects = player.effects + 1 end} end
function player:sendTextMessage(_, text) self.messages[#self.messages + 1] = text end
function player:addItemEx(item, drop)
	if full and not drop then return 1 end
	put(backpack, item)
	return RETURNVALUE_NOERROR
end
local function countIn(c, id)
	local n = 0
	for _, it in ipairs(c.items) do
		if it.id == id then n = n + it.count end
		if it.items then n = n + countIn(it, id) end
	end
	return n
end
function player:getItemCount(id) return countIn(backpack, id) end
-- like the engine's Player::removeItemOfType: every stack in the backpack and its bags is counted first, and only when
-- there are enough are they removed (all or nothing)
function player:removeItem(id, n)
	if countIn(backpack, id) < n then return false end
	local function take(c)
		for i = #c.items, 1, -1 do
			local it = c.items[i]
			if n > 0 and it.id == id then
				local k = math.min(n, it.count)
				it.count, n = it.count - k, n - k
				if it.count == 0 then table.remove(c.items, i) end
			elseif n > 0 and it.items then
				take(it)
			end
		end
	end
	take(backpack)
	return true
end
Game = {createItem = function(id, n) return newItem(id, {count = n}) end}

-- the crafting library and the bench, reduced to what salvage.lua reads
local NAMES = ChaosRarity.storedNames()
ChaosCrafting = {
	config = {historyTable = "chaos_crafting_log", rarityNames = NAMES},
	orbByKey = {chaos = {id = 29856, name = "Orb of Upheaval"}, transmutation = {id = 29851, name = "Orb of Awakening"},
		exalted = {id = 29855, name = "Orb of Grafting"}, scouring = {id = 24688, name = "Orb of Erasure"},
		alchemy = {id = 24691, name = "Orb of Gilding"}, annulment = {id = 24697, name = "Orb of Unmaking"},
		divine = {id = 29857, name = "Orb of Fate"}, sockets = {id = 24692, name = "Orb of Sockets"},
		tempering = {id = 32251, name = "Orb of Tempering"}, binding = {id = 32252, name = "Orb of Binding"},
		excision = {id = 32253, name = "Orb of Excision"}, reforging = {id = 32254, name = "Orb of Reforging"},
		ruin = {id = 32255, name = "Orb of Ruin"}, whetstone = {id = 32256, name = "Whetstone"},
		ember = {id = 32258, name = "Ember Orb"}, crown = {id = 32259, name = "Crown Orb"},
		void = {id = 32260, name = "Void Orb"}},
	isGear = function(item) return item.id >= 2000 and item.id < 3000 end,
	isRiftKey = function(item) return item.id == 10155 end,
	rarityOf = function(item) return tonumber(item.custom.rarity) or 0 end,
	customNumber = function(item, k) return tonumber(item.custom[k]) or 0 end,
	isUnique = function(item) return item.custom.chaos_unique ~= nil end,
	itemName = function(item) return "item" .. item.id end,
	rarityName = function(r) return ChaosRarity.name(r) end,
	signature = function(item) return item.id .. ";" .. tostring(item.custom.rarity) .. ";" .. tostring(item.custom.combatPowerLevel) end,
	levelOf = function(item) return tonumber(item.custom.chaos_ilvl) or tonumber(item.custom.combatPowerLevel) or 0 end,
	readMods = function(item) return item.mods or {} end
}
ChaosGems = {read = function(item)
	local n, filled = tonumber(item.custom.chaos_sockets) or 0, 0
	for i = 1, n do
		if (tonumber(item.custom["chaos_gem" .. i]) or 0) > 0 then filled = filled + 1 end
	end
	return {count = n, filled = filled}
end}
ChaosItemMods = {read = function() return {} end}
local results, states, selection = {}, 0, "x"
local equipped = newItem(2400, {custom = {rarity = 3, combatPowerLevel = 25}})
local function itemAt(pl, path)
	local c, item = backpack, nil
	for index in tostring(path):gmatch("%d+") do
		if not c then return nil end
		item = c.items[tonumber(index) + 1]
		if not item then return nil end
		c = item.container and item or nil
	end
	return item
end
ChaosCraftingBench = {
	itemAt = itemAt,
	backpackOf = function() return backpack end,
	walk = function(pl, fn)
		for i, it in ipairs(backpack.items) do fn(it, tostring(i - 1)) end
	end,
	inBackpack = function(pl, item)
		local p = item.parent
		while p do
			if p == backpack then return item ~= equipped end
			p = p.parent
		end
		return false
	end,
	sendState = function() states = states + 1 end,
	sendResult = function(pl, ok, orb, text) results[#results + 1] = {ok = ok, text = text} end,
	select = function(pl, sel) selection = sel end
}
local clock = 0
os.mtime = function() return clock end
-- addEvent / Player for the batch chain (O319): events wait in a list until the test runs them
local unpack = table.unpack or unpack
local events, online = {}, true
function addEvent(fn, delay, ...) events[#events + 1] = {fn = fn, delay = delay, args = {...}} end
local function runEvent()
	local e = table.remove(events, 1)
	if e then e.fn(unpack(e.args)) end
	return e ~= nil
end

dofile("data/scripts/chaos/salvage.lua")
local S = ChaosSalvage
local function lastResult() return results[#results] end
local function act(action, data)
	clock = clock + 5000
	S.onAction(player, action, data)
end

-- one item
local sword = put(backpack, newItem(2400, {custom = {rarity = 5, chaos_ilvl = 150, combatPowerLevel = 150}}))
local state = {items = {{path = "0", id = 2400}}, item = {path = "0", id = 2400}}
S.benchState(player, state)
eq(state.item.salvage.ok, true, "the bench previews the salvage")
eq(state.item.salvage.shards, 7, "Legendary at item level 150: 7 shards")
eq(state.salvage.installed, true, "the shard item exists")
eq(#state.salvage.recipes, #cfg.recipes + #cfg.shardRecipes, "every recipe on the bench, the shard recipes too")
local benchEmber = state.salvage.recipes[#cfg.recipes + 1]
eq(benchEmber.key .. "/" .. benchEmber.input .. "/" .. benchEmber.inputName .. "/" .. benchEmber.have .. "/" .. benchEmber.back,
	"embershard/29852/Ember Shards/0/0", "the Ember Shard row: its input, none owned, no recycling")
eq(state.salvage.batch, nil, "no batch preview outside the Salvage mode")
act("salvage", {path = "0", id = 2400, sig = "wrong"})
eq(lastResult().ok, false, "a changed item is refused")
eq(sword.removed, nil, "and kept")
math.randomseed(1)
act("salvage", {path = "0", id = 2400, sig = ChaosCrafting.signature(sword)})
eq(lastResult().ok, true, "salvaged: " .. tostring(lastResult().text))
eq(sword.removed, true, "the item is gone")
eq(player:getItemCount(cfg.shard.id), 7, "7 shards in the backpack")
eq(#queries, 1, "one log row")
assert(queries[1]:find("chaos_crafting_log", 1, true) and queries[1]:find("'Salvage'", 1, true), "logged as Salvage")
eq(selection, nil, "the bench is cleared")
-- refusals
local locked = put(backpack, newItem(2401, {custom = {rarity = 2, combatPowerLevel = 15}}))
local path = tostring(#backpack.items - 1)
act("lock", {path = path, id = 2401, on = true})
eq(locked.custom.chaos_locked, 1, "locked by the bench")
eq(S.isLocked(locked), true, "isLocked")
assert(lookFn(nil, locked, nil, 1, "You see a sword."):find("It is locked", 1, true), "the look text says so")
eq(lookFn(nil, sword, nil, 1, "You see a sword."), "You see a sword.", "unlocked items say nothing")
act("salvage", {path = path, id = 2401})
eq(lastResult().ok, false, "a locked item is refused")
eq(lastResult().text, K.reasons.locked, "with the lock reason")
eq(locked.removed, nil, "kept")
act("lock", {path = path, id = 2401, on = false})
eq(locked.custom.chaos_locked, nil, "unlocked")
act("lock", {path = path, id = 2401, on = true})
local socketed = put(backpack, newItem(2402, {custom = {rarity = 4, combatPowerLevel = 35, chaos_sockets = 2, chaos_gem1 = 32001}}))
act("salvage", {path = tostring(#backpack.items - 1), id = 2402})
eq(lastResult().text, K.reasons.gems, "socketed gems refused")
local unique = put(backpack, newItem(2403, {custom = {chaos_unique = 1}}))
act("salvage", {path = tostring(#backpack.items - 1), id = 2403})
eq(lastResult().text, K.reasons.unique, "unique refused")
backpack.items[#backpack.items + 1] = equipped -- an item that is not in the backpack (equipped)
equipped.parent = nil
act("salvage", {path = tostring(#backpack.items - 1), id = 2400})
eq(lastResult().text, K.reasons.notBackpack, "equipped refused")
table.remove(backpack.items)
-- rate limit: two salvages in the same moment
local quick = put(backpack, newItem(2404, {custom = {rarity = 1, combatPowerLevel = 1}}))
local n = #results
clock = clock + 5000
S.onAction(player, "salvage", {path = tostring(#backpack.items - 1), id = 2404})
eq(#results, n + 1, "the first answers")
S.onAction(player, "salvage", {path = "0", id = 2400})
eq(#results, n + 1, "the second, within the interval, only refreshes the state")
eq(quick.removed, true, "the first went through")

-- a batch: 55 Commons and a few others directly in the backpack, the cap and the confirm
local shardsBefore = player:getItemCount(cfg.shard.id)
for _ = 1, cfg.batchCap + 5 do
	put(backpack, newItem(2405, {custom = {rarity = 1, combatPowerLevel = 1}}))
end
put(backpack, newItem(2406, {custom = {rarity = 9, combatPowerLevel = 81}}))
act("salvageScope", {mode = "salvage", bag = "", maxRarity = 1})
state = {items = {}}
S.benchState(player, state)
local batch = state.salvage.batch
eq(batch.count, cfg.batchCap, "batchCap of the Commons")
eq(batch.capped, true, "capped")
eq(batch.skipped.above, 1, "the Eternal is above Common")
eq(batch.skipped.locked, 1, "the locked item")
eq(batch.skipped.gems, 1, "the socketed one")
eq(batch.skipped.unique, nil, "uniques have no rarity: not candidates")
eq(#batch.paths, cfg.batchCap, "the paths for the grid")
act("salvageBatch", {bag = "", maxRarity = 1, sig = "0:1"})
eq(lastResult().ok, false, "a wrong signature is refused")
local before = #backpack.items
queries = {}
act("salvageBatch", {bag = "", maxRarity = 1, sig = batch.sig})
eq(lastResult().ok, true, "batch: " .. tostring(lastResult().text))
local left = 0
for _, it in ipairs(backpack.items) do
	if it.id == 2405 then left = left + 1 end
end
eq(left, 5, "batchCap Commons gone, the five over the cap left")
assert(#backpack.items <= before - cfg.batchCap + 1 + 20, "shards and a few orbs came in")
eq(player:getItemCount(cfg.shard.id), shardsBefore + cfg.batchCap, "1 shard each")
eq(#queries, 1, "one INSERT for the batch")
local rows = 0
for _ in queries[1]:gmatch("'Salvage'") do rows = rows + 1 end
eq(rows, cfg.batchCap, "a log row per item")
eq(locked.removed, nil, "the locked item stayed")
eq(socketed.removed, nil, "the socketed item stayed")
eq(unique.removed, nil, "the unique stayed")
-- the second batch takes the remaining 5
S.benchState(player, state)
eq(state.salvage.batch.count, 5, "five left")
act("salvageBatch", {bag = "", maxRarity = 1, sig = state.salvage.batch.sig})
eq(lastResult().ok, true, "second batch")
S.benchState(player, state)
eq(state.salvage.batch.count, 0, "none left")
act("salvageBatch", {bag = "", maxRarity = 1, sig = state.salvage.batch.sig})
eq(lastResult().ok, false, "nothing to salvage")

-- O319: a capped batch chains the next one by itself (a small cap stands in for 255)
do
	local cfg = S.config -- the one salvage.lua reads
	local realCap = cfg.batchCap
	cfg.batchCap = 10
	events = {}
	function Player(id) return online and player:getId() == id and player or nil end
	local function commons(n)
		for _ = 1, n do put(backpack, newItem(2405, {custom = {rarity = 1, combatPowerLevel = 1}})) end
	end
	local function commonsLeft()
		local c = 0
		for _, it in ipairs(backpack.items) do
			if it.id == 2405 then c = c + 1 end
		end
		return c
	end
	local function clean()
		for i = #backpack.items, 1, -1 do
			if backpack.items[i].id == 2405 then table.remove(backpack.items, i) end
		end
		events = {}
	end
	local function preview()
		act("salvageScope", {mode = "salvage", bag = "", maxRarity = 1})
		local st = {items = {}}
		S.benchState(player, st)
		return st.salvage.batch
	end
	-- 25 Commons: 10, then 10, then 5, one click
	commons(25)
	local pv = preview()
	eq(pv.capped, true, "capped") eq(pv.cap, 10, "the small cap")
	act("salvageBatch", {bag = "", maxRarity = 1, sig = pv.sig})
	eq(lastResult().ok, true, "first batch of the chain") eq(commonsLeft(), 15, "10 salvaged")
	eq(lastResult().text:find("The rest of the bag follows.", 1, true) ~= nil, true, "the text says more follows")
	eq(#events, 1, "the next batch is scheduled") eq(events[1].delay, cfg.chainDelayMs, "after the short delay")
	runEvent()
	eq(commonsLeft(), 5, "the second batch ran by itself") eq(#events, 1, "and chained the third")
	runEvent()
	eq(commonsLeft(), 0, "the third batch emptied it") eq(#events, 0, "the chain ends") eq(lastResult().ok, true, "result ok")
	eq(lastResult().text:find("follows", 1, true), nil, "the last batch says nothing follows")
	eq(runEvent(), false, "nothing left to run")
	-- exactly one batch: no chain
	commons(10)
	pv = preview()
	act("salvageBatch", {bag = "", maxRarity = 1, sig = pv.sig})
	eq(pv.capped, false, "10 fit the cap") eq(#events, 0, "not capped: no chain") eq(commonsLeft(), 0, "gone")
	-- the player logs out between two batches
	commons(25)
	pv = preview()
	act("salvageBatch", {bag = "", maxRarity = 1, sig = pv.sig})
	online = false
	runEvent()
	online = true
	eq(commonsLeft(), 15, "no batch for a player who logged out") eq(#events, 0, "and no more events")
	clean()
	-- the logout handler clears the chain too
	commons(25)
	pv = preview()
	act("salvageBatch", {bag = "", maxRarity = 1, sig = pv.sig})
	for _, r in ipairs(registered) do
		if r.name == "ChaosSalvageLogout" then r.onLogout(player) end
	end
	runEvent()
	eq(commonsLeft(), 15, "the logout event cleared the chain")
	clean()
	-- the bag changes between two batches: the chain stops and says so
	commons(25)
	pv = preview()
	act("salvageBatch", {bag = "", maxRarity = 1, sig = pv.sig})
	commons(1)
	runEvent()
	eq(commonsLeft(), 16, "nothing salvaged after a change") eq(#events, 0, "the chain stopped")
	eq(lastResult().ok, false, "a refusal is sent") eq(lastResult().text:find("bag changed", 1, true) ~= nil, true, "it says why")
	clean()
	-- a batch of the player's own ends the older chain
	commons(25)
	pv = preview()
	act("salvageBatch", {bag = "", maxRarity = 1, sig = pv.sig})
	local old = events[1]
	events = {}
	pv = preview()
	act("salvageBatch", {bag = "", maxRarity = 1, sig = pv.sig})
	eq(commonsLeft(), 5, "two batches by hand") eq(#events, 1, "the new chain")
	old.fn(unpack(old.args))
	eq(commonsLeft(), 5, "the old timer does nothing")
	runEvent()
	eq(commonsLeft(), 0, "the new chain finishes")
	clean()
	-- K.chainStep alone
	local st = {left = 5, batches = 1}
	eq(K.chainStep(st, nil, {chainMax = 8}), "gone", "no bag")
	eq(K.chainStep(st, {count = 0, skipped = {}}, {chainMax = 8}), "done", "nothing eligible")
	eq(K.chainStep(st, {count = 5, skipped = {}}, {chainMax = 8}), "go", "the five left")
	eq(K.chainStep(st, {count = 4, skipped = {cap = 1}}, {chainMax = 8}), "go", "a capped rest counts too")
	eq(K.chainStep(st, {count = 6, skipped = {}}, {chainMax = 8}), "changed", "one more than left")
	eq(K.chainStep(st, {count = 3, skipped = {}}, {chainMax = 8}), "changed", "fewer than left")
	eq(K.chainStep({left = 5, batches = 8}, {count = 5, skipped = {}}, {chainMax = 8}), "limit", "the batch limit")
	cfg.batchCap = realCap
	assert(cfg.chainMax >= math.ceil(500 / cfg.batchCap), "the chain covers a 500 slot bag")
	assert(cfg.chainDelayMs >= 100 and cfg.chainDelayMs <= 2000, "a short delay")
end
-- the Loot Bag (a store pouch in the purse, outside the backpack): offered after the main backpack, salvaged by key
local purse = newItem(26052, {container = true, size = 50})
local lootBag = put(purse, newItem(32081, {container = true, size = 255}))
local carriedPouches = {loot = lootBag}
ChaosPouches = {carried = function() return carriedPouches end}
local plainBag = put(backpack, newItem(1987, {container = true, size = 20})) -- an ordinary bag, listed after the Loot Bag
local plainPath
for i, it in ipairs(backpack.items) do
	if it == plainBag then plainPath = tostring(i - 1) end
end
local lootLock = put(lootBag, newItem(2410, {custom = {rarity = 1, combatPowerLevel = 1, chaos_locked = 1}}))
local lootUnique = put(lootBag, newItem(2411, {custom = {chaos_unique = 1}}))
local lootSocket = put(lootBag, newItem(2412, {custom = {rarity = 1, combatPowerLevel = 1, chaos_sockets = 1, chaos_gem1 = 32001}}))
local lootRare = put(lootBag, newItem(2413, {custom = {rarity = 3, combatPowerLevel = 25}}))
local lootCommon = {}
for _ = 1, lootSlots - 4 do
	lootCommon[#lootCommon + 1] = put(lootBag, newItem(2414, {custom = {rarity = 1, combatPowerLevel = 1}}))
end
eq(#lootBag.items, lootSlots, "a full Loot Bag")
state = {items = {}}
S.benchState(player, state)
eq(state.salvage.bags[1].path, "", "the main backpack first")
eq(state.salvage.bags[2].path, "loot", "the Loot Bag second")
eq(state.salvage.bags[2].name, "Loot Bag", "named")
eq(state.salvage.bags[3].path, plainPath, "an ordinary bag after it (a numeric path)")
carriedPouches.loot = nil
state = {items = {}}
S.benchState(player, state)
eq(state.salvage.bags[2].path, plainPath, "no Loot Bag carried: not offered")
eq(S.inScope(player, lootCommon[1]), false, "and its items are out of scope")
carriedPouches.loot = lootBag
act("salvageScope", {mode = "salvage", bag = "loot", maxRarity = 1})
state = {items = {}}
S.benchState(player, state)
batch = state.salvage.batch
eq(batch.bag, "loot", "the scope is the Loot Bag")
eq(batch.count, #lootCommon, "every Common of the full bag in one action")
eq(batch.capped, false, "not capped")
eq(batch.skipped.locked, 1, "the locked item")
eq(batch.skipped.gems, 1, "the socketed one")
eq(batch.skipped.above, 1, "the Rare is above Common")
eq(batch.paths[1]:sub(1, 5), "loot.", "paths are Loot Bag addresses")
local shardsLoot = player:getItemCount(cfg.shard.id)
queries = {}
act("salvageBatch", {bag = "loot", maxRarity = 1, sig = "bad"})
eq(lastResult().ok, false, "a wrong signature is refused for the Loot Bag too")
act("salvageBatch", {bag = "loot", maxRarity = 1, sig = batch.sig})
eq(lastResult().ok, true, "Loot Bag batch: " .. tostring(lastResult().text))
eq(#lootBag.items, 4, "only the four kept items are left")
eq(lootLock.removed, nil, "locked kept")
eq(lootUnique.removed, nil, "unique kept")
eq(lootSocket.removed, nil, "socketed kept")
eq(lootRare.removed, nil, "above the rarity kept")
eq(player:getItemCount(cfg.shard.id), shardsLoot + #lootCommon, "1 shard each")
eq(#queries, 1, "one INSERT")
-- a rarity up to Rare takes the Rare as well
act("salvageScope", {mode = "salvage", bag = "loot", maxRarity = 3})
S.benchState(player, state)
act("salvageBatch", {bag = "loot", maxRarity = 3, sig = state.salvage.batch.sig})
eq(lootRare.removed, true, "the Rare goes with a higher max rarity")
-- an item that is neither in the backpack nor in the Loot Bag is refused
local stray = newItem(2415, {custom = {rarity = 1, combatPowerLevel = 1}})
put(purse, stray)
eq(S.inScope(player, stray), false, "the purse itself is no salvage scope")
act("salvageScope", {mode = "orbs", bag = "", maxRarity = 1})
-- a batch rate limit
clock = clock + 5000
S.onAction(player, "salvageBatch", {bag = "", maxRarity = 1, sig = "x"})
S.onAction(player, "salvageBatch", {bag = "", maxRarity = 1, sig = "x"})
eq(lastResult().text, "Wait a moment before the next batch.", "one batch per interval")

-- combining
local have = player:getItemCount(cfg.shard.id)
local chaosBefore = player:getItemCount(29856) -- salvage may have rolled whole orbs
assert(have >= 25, "enough shards for an Orb of Upheaval: " .. have)
act("combine", {key = "chaos", count = 1})
eq(lastResult().ok, true, "combined")
eq(player:getItemCount(cfg.shard.id), have - 25, "25 shards spent")
eq(player:getItemCount(29856), chaosBefore + 1, "an Orb of Upheaval")
player:removeItem(cfg.shard.id, player:getItemCount(cfg.shard.id) - 5) -- the big batches left plenty
act("combine", {key = "exalted", count = 1})
eq(lastResult().ok, false, "not enough for an Orb of Grafting")
eq(player:getItemCount(29855), 0, "no Orb of Grafting")
act("combine", {key = "chaos", count = 99})
eq(lastResult().ok, false, "more than maxCombine refused")
-- a full backpack: the orb goes to the inbox
full = true
put(backpack, newItem(cfg.shard.id, {count = 25}))
act("combine", {key = "chaos", count = 1})
eq(lastResult().ok, true, "combined with a full backpack")
eq(countIn(inbox, 29856), 1, "the orb is in the inbox")
full = false

-- Ember / Crown Shards -> their orb (stacks of 100 spread over the backpack and a bag)
local bag = put(backpack, newItem(1987, {container = true, size = 20}))
for _ = 1, 8 do
	put(backpack, newItem(29852, {count = 100}))
	put(bag, newItem(29852, {count = 100}))
end
eq(player:getItemCount(29852), 1600, "1,600 Ember Shards in two places")
queries = {}
if player:getItemCount(32258) > 0 then player:removeItem(32258, player:getItemCount(32258)) end -- a batch may have rolled one
act("combine", {key = "embershard", count = 1})
eq(lastResult().ok, true, "Ember Shards combined: " .. tostring(lastResult().text))
eq(player:getItemCount(29852), 600, "1,000 taken from both places")
eq(player:getItemCount(32258), 1, "an Ember Orb")
eq(lastResult().text, "1,000 Ember Shards -> 1x Ember Orb.", "the message")
eq(#queries, 1, "one log row")
assert(queries[1]:find("chaos_crafting_log", 1, true) and queries[1]:find("'Shards'", 1, true)
	and queries[1]:find("1,000 Ember Shards -> 1x Ember Orb", 1, true), "logged: " .. queries[1])
-- not enough: refused, nothing taken
act("combine", {key = "embershard", count = 1})
eq(lastResult().ok, false, "600 Ember Shards are not enough")
eq(lastResult().text, "You do not have enough Ember Shards.", "the reason names them")
eq(player:getItemCount(29852), 600, "nothing taken")
eq(player:getItemCount(32258), 1, "no second orb")
-- Ctrl+click: ten at once, eleven refused
for _ = 1, 100 do
	put(bag, newItem(29852, {count = 100}))
end
act("combine", {key = "embershard", count = 11})
eq(lastResult().ok, false, "more than ten refused")
eq(player:getItemCount(29852), 10600, "nothing taken")
act("combine", {key = "embershard", count = 10})
eq(lastResult().ok, true, "ten Ember Orbs")
eq(player:getItemCount(29852), 600, "10,000 taken")
eq(player:getItemCount(32258), 11, "eleven Ember Orbs")
-- the rate limit: a second combine in the same moment only refreshes the state
put(bag, newItem(29853, {count = 999}))
act("combine", {key = "crownshard", count = 1})
eq(lastResult().text, "You do not have enough Crown Shards.", "one Crown Shard short")
put(backpack, newItem(29853, {count = 2751}))
n = #results
clock = clock + 5000
S.onAction(player, "combine", {key = "crownshard", count = 1})
eq(#results, n + 1, "the first answers")
clock = clock + 200 -- past the action limit of 150 ms, inside combineIntervalMs
S.onAction(player, "combine", {key = "crownshard", count = 1})
eq(#results, n + 1, "the second, within 300 ms, only refreshes the state")
eq(player:getItemCount(29853), 3750 - 1000, "one Crown Orb's worth taken")
eq(player:getItemCount(32259), 1, "a Crown Orb")
-- a full backpack: the orb goes to the inbox
full = true
act("combine", {key = "crownshard", count = 1})
eq(lastResult().ok, true, "combined with a full backpack")
eq(countIn(inbox, 32259), 1, "the Crown Orb is in the inbox")
eq(player:getItemCount(29853), 1750, "its shards taken")
full = false
-- the other uses stay: recycling never turns an orb into Ember Shards, the shards are plain items
act("recycle", {key = "embershard", count = 1})
eq(lastResult().ok, false, "no recycling into Ember Shards")
eq(player:getItemCount(32258), 11, "the Ember Orbs stay")
-- the look text says where the shards go; other items say nothing
local emberStack = newItem(29852, {count = 5})
eq(lookFn(nil, emberStack, nil, 1, "You see 5 Ember Shards."),
	"You see 5 Ember Shards.\nCombine 1,000 at the Crafting Bench (Salvage tab) into an Ember Orb.", "the Ember Shard look text")
eq(S.shardHint(29853), "Combine 1,000 at the Crafting Bench (Salvage tab) into a Crown Orb.", "the Crown Shard hint")
eq(S.shardHint(cfg.shard.id), nil, "rune shards have no hint")
eq(S.shardHint(2400), nil, "nor has gear")

-- an orb that makes a new copy keeps the lock
local copy = newItem(2401)
S.copyLock(locked, copy)
eq(copy.custom.chaos_locked, 1, "copyLock")
S.copyLock(sword, copy)
eq(copy.custom.chaos_locked, 1, "copyLock never unlocks")

-- ---------------------------------------------------------------- the bench history in pt-BR (told at display time)
dofile("data/scripts/chaos/i18n_core.lua")
do
	local function tpt(key, ...) return ChaosI18n.text("pt-BR", key, ...) end
	local kindName = function(k) return ({Rare = "Raro"})[k] end
	local function row(orb, text) local o, x = K.historyRow(orb, text, tpt, kindName) return o .. " | " .. x end
	eq(row("Salvage", "Rare (level 40): 5 rune shards + 1 Orb of Upheaval + 30 Conquest Tokens"),
		"Desmontar | Raro (nível 40): 5 rune shards + 1 Orb of Upheaval + 30 Conquest Tokens", "salvage row")
	eq(row("Salvage", "Set piece (level 12): 1 rune shard"), "Desmontar | Peça de set (nível 12): 1 rune shard", "set piece row")
	eq(row("Salvage", "Unique (level 60): 4 rune shards + 69 Conquest Tokens"), "Desmontar | Única (nível 60): 4 rune shards + 69 Conquest Tokens", "unique row")
	eq(row("Lock", "locked"), "Trava | Item trancado", "lock row")
	eq(row("Lock", "unlocked"), "Trava | Item destrancado", "unlock row")
	eq(row("Shards", "1,000 rune shards -> 1x Ember Orb"), "Fragmentos | 1,000 rune shards -> 1x Ember Orb", "shards row")
	eq(row("Recycle", "2x Orb of Upheaval -> 9 rune shards"), "Reciclar | 2x Orb of Upheaval -> 9 rune shards", "recycle row")
	eq(row("Orb of Upheaval", "Upgraded"), "Orb of Upheaval | Upgraded", "a crafting row is not touched")
	eq(row("Salvage", "something else"), "Desmontar | something else", "an unknown salvage text stays")
	local o, x = K.historyRow("Lock", "locked", nil)
	eq(o .. x, "Locklocked", "no translator: English")
	for _, k in ipairs({"Salvage", "Lock", "Shards", "Recycle", "Item locked", "Item unlocked", "%s (level %d): %d %s", " + %d Conquest Tokens"}) do
		assert(ChaosI18n.strings["pt-BR"][k], "pt-BR for " .. k)
	end
end

-- ================================================================ lockAt: the item right-click menu (client position)
do
	backpack.parent = player -- the backpack hangs on the player (Item:getTopParent)
	local function say() return player.messages[#player.messages] end
	local function fresh(o) return put(backpack, newItem(o.id, {custom = o.custom or {}})) end
	local gearItem = fresh({id = 2450, custom = {rarity = 2, combatPowerLevel = 20}})
	local key = fresh({id = 10155})
	local pebble = fresh({id = 3000})
	local gearInBag = put(backpack, newItem(1987, {container = true}))
	local inBag = put(gearInBag, newItem(2451, {custom = {rarity = 3}}))
	local worn = newItem(2452, {custom = {rarity = 3}})
	worn.parent = player
	player.slots = {[1] = worn}
	player.open = {[0] = backpack, [1] = gearInBag}
	local function pos(y, z) return {x = 0xFFFF, y = y, z = z or 0} end
	local function cidOf(it) return it.id - 1000 end
	local function at(index) -- the slot of an item in the backpack
		for i, it in ipairs(backpack.items) do if it == index then return i - 1 end end
	end

	-- a container slot, lock then unlock
	act("lockAt", {pos = pos(0x40, at(gearItem)), cid = cidOf(gearItem), on = true})
	eq(gearItem.custom.chaos_locked, 1, "lockAt: locked from the menu")
	assert(say():find("is locked", 1, true), "lockAt: says so")
	act("lockAt", {pos = pos(0x40, at(gearItem)), cid = cidOf(gearItem), on = false})
	eq(gearItem.custom.chaos_locked, nil, "lockAt: unlocked from the menu")
	act("lockAt", {pos = pos(0x40, at(gearItem)), cid = cidOf(gearItem)})
	eq(gearItem.custom.chaos_locked, 1, "lockAt: no `on` flips it on")
	act("lockAt", {pos = pos(0x40, at(gearItem)), cid = cidOf(gearItem)})
	eq(gearItem.custom.chaos_locked, nil, "lockAt: and off again")
	-- a Rift Key, a bag inside the backpack, a worn item
	act("lockAt", {pos = pos(0x40, at(key)), cid = cidOf(key), on = true})
	eq(key.custom.chaos_locked, 1, "lockAt: a Rift Key")
	act("lockAt", {pos = pos(0x41, 0), cid = cidOf(inBag), on = true})
	eq(inBag.custom.chaos_locked, 1, "lockAt: an item in an open bag")
	act("lockAt", {pos = pos(1, 0), cid = cidOf(worn), on = true})
	eq(worn.custom.chaos_locked, 1, "lockAt: an equipped item (inventory slot)")
	-- the page offset of a container
	player.pages = {[0] = 2}
	act("lockAt", {pos = pos(0x40, at(gearItem) - 2), cid = cidOf(gearItem), on = true})
	eq(gearItem.custom.chaos_locked, 1, "lockAt: slot on page 2 = first index + slot")
	gearItem.custom.chaos_locked = nil
	player.pages = nil
	-- refusals leave everything as it was
	local function refused(data, what)
		local before = #queries
		act("lockAt", data)
		eq(#queries, before, "lockAt refused: " .. what .. " (no log row)")
	end
	act("lockAt", {pos = pos(0x40, at(pebble)), cid = cidOf(pebble), on = true})
	eq(pebble.custom.chaos_locked, nil, "lockAt: not gear")
	assert(say():find("Only gear", 1, true), "lockAt: says why")
	act("lockAt", {pos = pos(0x40, at(gearItem)), cid = cidOf(gearItem) + 1, on = true})
	eq(gearItem.custom.chaos_locked, nil, "lockAt: the id does not match")
	assert(say():find("moved", 1, true), "lockAt: the item moved")
	act("lockAt", {pos = pos(0x40, at(gearItem))})
	eq(gearItem.custom.chaos_locked, nil, "lockAt: no id")
	refused({pos = pos(0x42, 0), cid = 1450, on = true}, "a container that is not open")
	refused({pos = {x = 100, y = 100, z = 7}, cid = cidOf(gearItem), on = true}, "a map position")
	refused({pos = pos(11, 0), cid = cidOf(gearItem), on = true}, "slot 11 (the store inbox)")
	refused({pos = pos(2, 0), cid = cidOf(gearItem), on = true}, "an empty slot")
	refused({pos = pos(0x40, 99), cid = cidOf(gearItem), on = true}, "past the container")
	refused({pos = {x = 0xFFFF, y = 0x40, z = -1}, cid = cidOf(gearItem), on = true}, "a negative slot")
	refused({pos = {x = "a", y = 1, z = 0}, cid = 1, on = true}, "a malformed position")
	refused({pos = "0.1", cid = 1, on = true}, "a position that is not a table")
	refused({cid = 1, on = true}, "no position")
	-- an item that hangs somewhere else than on the player (another player's container, a depot) is refused
	local strange = newItem(2460, {custom = {rarity = 2}})
	local foreign = newItem(1988, {container = true})
	put(foreign, strange)
	player.open[2] = foreign
	refused({pos = pos(0x42, 0), cid = cidOf(strange), on = true}, "a container that is not the player's")
	eq(strange.custom.chaos_locked, nil, "lockAt: kept unlocked")
	-- the rate limit: the same action twice inside singleIntervalMs does the second one never
	clock = clock + 5000
	S.onAction(player, "lockAt", {pos = pos(0x40, at(gearItem)), cid = cidOf(gearItem), on = true})
	clock = clock + cfg.singleIntervalMs + 1 -- past the 150 ms action limit and the single limit
	eq(gearItem.custom.chaos_locked, 1, "lockAt: the first one counts")
	S.onAction(player, "lockAt", {pos = pos(0x40, at(gearItem)), cid = cidOf(gearItem), on = false})
	eq(gearItem.custom.chaos_locked, nil, "lockAt: after the interval the next one works")
	S.onAction(player, "lockAt", {pos = pos(0x40, at(gearItem)), cid = cidOf(gearItem), on = true})
	eq(gearItem.custom.chaos_locked, nil, "lockAt: inside the interval it is dropped")
	-- the bench's own lock still works and takes only a real boolean
	act("lock", {path = tostring(at(gearItem)), id = 2450, on = "false"})
	eq(gearItem.custom.chaos_locked, nil, "lock: the string \"false\" is not true")
	act("lock", {path = tostring(at(gearItem)), id = 2450, on = true})
	eq(gearItem.custom.chaos_locked, 1, "lock: the bench path still works")
	eq(S.actions.lockAt, true, "lockAt is a salvage action")
end

print("salvage_test: ok")
