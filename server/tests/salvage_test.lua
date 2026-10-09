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
		gems = o.gems or 0, chaosMods = o.chaosMods or 0, locked = o.locked or false, unique = o.unique or false,
		riftKey = o.riftKey or false, stackable = o.stackable or false, inBackpack = o.inBackpack}
	if o.gear == false then
		info.gear = false
	end
	return info
end

-- ---------------------------------------------------------------- config sanity
eq(#cfg.baseShards, 15, "a yield per rarity")
eq(#cfg.orbChance, 15, "an orb chance per rarity")
local known = {transmutation = 1, alchemy = 1, exalted = 1, annulment = 1, scouring = 1, chaos = 1, divine = 1, sockets = 1}
for i = 2, 15 do
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
	assert(r.cost >= 10, "no orb for less than 10 shards")
end
-- recipe costs follow the store prices (about 2.5 shards per coin): the cheap orbs cheap, the Exalted dearest
local store = {transmutation = 5, chaos = 10, scouring = 12, alchemy = 15, annulment = 20, divine = 25, sockets = 25, exalted = 40}
for _, r in ipairs(cfg.recipes) do
	local ratio = r.cost / store[r.key]
	assert(ratio >= 2.3 and ratio <= 2.7, "shards per coin for " .. r.key .. ": " .. ratio)
end
assert(cfg.batchCap == 50, "hard cap of 50 items per batch")
assert(not cfg.allowUniques, "uniques are not salvaged")

-- ---------------------------------------------------------------- yields
eq(K.shards(gear(1), cfg), 1, "Common, bottom of the window")
eq(K.shards(gear(1, 10), cfg), 1, "Common, top: floor(1.5)")
eq(K.shards(gear(3, 21), cfg), 2, "Rare bottom")
eq(K.shards(gear(3, 30), cfg), 3, "Rare top: +50%")
eq(K.shards(gear(5, 41), cfg), 3, "Legendary bottom")
eq(K.shards(gear(5, 50), cfg), 4, "Legendary top")
eq(K.shards(gear(10, 91), cfg), 7, "Divine bottom")
eq(K.shards(gear(10, 100), cfg), 10, "Divine top")
eq(K.shards(gear(15, 141), cfg), 18, "Transcendent bottom")
eq(K.shards(gear(15, 150), cfg), 27, "Transcendent top")
eq(K.shards(gear(5, 0), cfg), 3, "a level outside the window counts as the bottom")
eq(K.shards(gear(5, 999), cfg), 3, "a level above the window too")
eq(K.shards(gear(4, 31, {chaosMods = 2}), cfg), 4, "+1 per Chaos modifier")
eq(K.shards(gear(4, 31, {sockets = 3}), cfg), 5, "+1 per empty socket")
eq(K.shards(gear(99, 0), cfg), cfg.baseShards[15], "rarity clamped to 15")
eq(K.orbChance(gear(1), cfg), 50, "0.5% on a Common")
eq(K.orbChance(gear(15), cfg), 500, "5% on a Transcendent")
eq(K.percent(50), "0.5", "percent text")
eq(K.percent(100), "1", "whole percent")
eq(K.percent(75), "0.75", "two decimals")

-- ---------------------------------------------------------------- checks and the lock
eq(K.check(gear(3), cfg), nil, "a rolled item may be salvaged")
eq(K.check(gear(3, nil, {locked = true}), cfg), "locked", "locked")
eq(K.check(gear(3, nil, {unique = true}), cfg), "unique", "unique")
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
local p = K.preview(gear(5, 50), cfg)
eq(p.ok, true, "preview ok")
eq(p.shards, 4, "preview shards")
eq(p.orbChance, "1", "preview orb chance")
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
local r = K.roll(gear(5, 41), cfg, seq({101}))
eq(r.shards, 3, "roll shards")
eq(r.orb, nil, "101 > 100: no orb")
r = K.roll(gear(5, 41), cfg, seq({100, 1}))
eq(r.orb, "transmutation", "100 <= 100: an orb, the first by weight")
r = K.roll(gear(5, 41), cfg, seq({1, 100}))
eq(r.orb, "exalted", "the last weight")
-- the orb mix over many rolls follows the weights
math.randomseed(7)
local counts, orbs = {}, 0
for _ = 1, 200000 do
	local x = K.roll(gear(15, 141), cfg, math.random)
	if x.orb then
		orbs = orbs + 1
		counts[x.orb] = (counts[x.orb] or 0) + 1
	end
end
assert(orbs > 9000 and orbs < 11000, "5% orbs on Transcendent: " .. orbs)
assert(counts.transmutation > counts.chaos and counts.chaos > counts.exalted, "Transmutation most, Exalted least")

-- ---------------------------------------------------------------- economy: the stock rarity roll
-- default_onDropLoot.lua: 70% of gear passes, then each rarity in order with its own chance
local stock = {15.0, 14.0, 12.0, 10.0, 8.5, 7.0, 6.0, 4.5, 3.8, 3.0, 2.3, 1.7, 1.2, 0.8, 0.5}
local left, total, shards, orbChance = 1, 0, 0, 0
for rr, c in ipairs(stock) do
	local pr = left * c / 100
	left = left * (1 - c / 100)
	total = total + pr
	local s = 0
	for lv = rr * 10 - 9, rr * 10 do
		s = s + K.shards(gear(rr, lv), cfg)
	end
	shards = shards + pr * s / 10
	orbChance = orbChance + pr * K.orbChance(gear(rr), cfg)
end
shards, orbChance = shards / total, orbChance / total / 10000
assert(shards > 2.2 and shards < 3.5, "an average rolled drop gives 2.2-3.5 shards: " .. shards)
assert(orbChance > 0.005 and orbChance < 0.015, "about 1% orb chance per item: " .. orbChance)
-- a Chaos Orb's worth of shards takes about 10 rolled items (without modifiers and sockets)
local chaosCost = K.recipe("chaos", cfg).cost
assert(chaosCost / shards >= 8, "at least 8 rolled items per Chaos Orb: " .. chaosCost / shards)

-- ---------------------------------------------------------------- salvage all
local list = {}
for i = 1, 60 do
	list[i] = gear(1 + (i % 2), nil) -- Common / Uncommon
end
local b = K.batch(list, 2, cfg)
eq(b.count, 50, "cap of 50 items")
eq(b.capped, true, "capped")
eq(b.skipped.cap, 10, "10 left for the next batch")
eq(b.shards, 50, "1 shard each")
eq(b.picked[1], 1, "in container order")
eq(b.picked[50], 50, "the first fifty")
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
eq(ok, true, "25 shards make a Chaos Orb")
eq(cost, 25, "cost")
ok, cost = K.combineCheck(24, "chaos", 1, cfg)
eq(ok, nil, "24 do not")
eq(cost, "shards", "reason")
ok, cost = K.combineCheck(1000, "chaos", 10, cfg)
eq(cost, 250, "ten at once")
eq(select(2, K.combineCheck(1000, "chaos", 11, cfg)), "count", "more than maxCombine")
eq(select(2, K.combineCheck(1000, "chaos", 0, cfg)), "count", "zero")
eq(select(2, K.combineCheck(1000, "mirror", 1, cfg)), "unknownRecipe", "unknown orb")

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
local STACKABLE = {[cfg.shard.id] = true, [29856] = true, [29851] = true}
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

local backpack = newItem(1988, {container = true, size = 80})
local inbox = newItem(14404, {container = true, size = 1000})
function inbox:addItemEx(item) put(self, item) return RETURNVALUE_NOERROR end
local full = false
local player = {id = 1, guid = 7, effects = 0, messages = {}}
function player:getId() return self.id end
function player:getGuid() return self.guid end
function player:getInbox() return inbox end
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
function player:removeItem(id, n)
	if countIn(backpack, id) < n then return false end
	for i = #backpack.items, 1, -1 do
		local it = backpack.items[i]
		if it.id == id and n > 0 then
			local take = math.min(n, it.count)
			it.count, n = it.count - take, n - take
			if it.count == 0 then table.remove(backpack.items, i) end
		end
	end
	return true
end
Game = {createItem = function(id, n) return newItem(id, {count = n}) end}

-- the crafting library and the bench, reduced to what salvage.lua reads
local NAMES = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Exotic", "Mythic", "Chaos", "Eternal", "Divine",
	"Phantasmal", "Celestial", "Cosmic", "Abyssal", "Transcendent"}
ChaosCrafting = {
	config = {historyTable = "chaos_crafting_log", rarityNames = NAMES},
	orbByKey = {chaos = {id = 29856, name = "Chaos Orb"}, transmutation = {id = 29851, name = "Orb of Transmutation"},
		exalted = {id = 29855, name = "Exalted Orb"}, scouring = {id = 24688, name = "Orb of Scouring"},
		alchemy = {id = 24691, name = "Orb of Alchemy"}, annulment = {id = 24697, name = "Orb of Annulment"},
		divine = {id = 29857, name = "Divine Orb"}, sockets = {id = 24692, name = "Orb of Sockets"}},
	isGear = function(item) return item.id >= 2000 and item.id < 3000 end,
	isRiftKey = function(item) return item.id == 10155 end,
	rarityOf = function(item) return tonumber(item.custom.rarity) or 0 end,
	customNumber = function(item, k) return tonumber(item.custom[k]) or 0 end,
	isUnique = function(item) return item.custom.chaos_unique ~= nil end,
	itemName = function(item) return "item" .. item.id end,
	rarityName = function(r) return NAMES[r] end,
	signature = function(item) return item.id .. ";" .. tostring(item.custom.rarity) .. ";" .. tostring(item.custom.combatPowerLevel) end
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
	inBackpack = function(pl, item) return item ~= equipped and item.parent ~= nil end,
	sendState = function() states = states + 1 end,
	sendResult = function(pl, ok, orb, text) results[#results + 1] = {ok = ok, text = text} end,
	select = function(pl, sel) selection = sel end
}
local clock = 0
os.mtime = function() return clock end

dofile("data/scripts/chaos/salvage.lua")
local S = ChaosSalvage
local function lastResult() return results[#results] end
local function act(action, data)
	clock = clock + 5000
	S.onAction(player, action, data)
end

-- one item
local sword = put(backpack, newItem(2400, {custom = {rarity = 5, combatPowerLevel = 50}}))
local state = {items = {{path = "0", id = 2400}}, item = {path = "0", id = 2400}}
S.benchState(player, state)
eq(state.item.salvage.ok, true, "the bench previews the salvage")
eq(state.item.salvage.shards, 4, "Legendary at the top: 4 shards")
eq(state.salvage.installed, true, "the shard item exists")
eq(#state.salvage.recipes, #cfg.recipes, "every recipe on the bench")
eq(state.salvage.batch, nil, "no batch preview outside the Salvage mode")
act("salvage", {path = "0", id = 2400, sig = "wrong"})
eq(lastResult().ok, false, "a changed item is refused")
eq(sword.removed, nil, "and kept")
math.randomseed(1)
act("salvage", {path = "0", id = 2400, sig = ChaosCrafting.signature(sword)})
eq(lastResult().ok, true, "salvaged: " .. tostring(lastResult().text))
eq(sword.removed, true, "the item is gone")
eq(player:getItemCount(cfg.shard.id), 4, "4 shards in the backpack")
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
for _ = 1, 55 do
	put(backpack, newItem(2405, {custom = {rarity = 1, combatPowerLevel = 1}}))
end
put(backpack, newItem(2406, {custom = {rarity = 9, combatPowerLevel = 81}}))
act("salvageScope", {mode = "salvage", bag = "", maxRarity = 1})
state = {items = {}}
S.benchState(player, state)
local batch = state.salvage.batch
eq(batch.count, 50, "50 of the 55 Commons")
eq(batch.capped, true, "capped")
eq(batch.skipped.above, 1, "the Eternal is above Common")
eq(batch.skipped.locked, 1, "the locked item")
eq(batch.skipped.gems, 1, "the socketed one")
eq(batch.skipped.unique, nil, "uniques have no rarity: not candidates")
eq(#batch.paths, 50, "the paths for the grid")
act("salvageBatch", {bag = "", maxRarity = 1, sig = "0:1"})
eq(lastResult().ok, false, "a wrong signature is refused")
local before = #backpack.items
queries = {}
act("salvageBatch", {bag = "", maxRarity = 1, sig = batch.sig})
eq(lastResult().ok, true, "batch: " .. tostring(lastResult().text))
eq(#backpack.items, before - 50 + 1, "50 items gone, one shard stack more (or merged)")
eq(player:getItemCount(cfg.shard.id), shardsBefore + 50, "50 shards")
eq(#queries, 1, "one INSERT for the batch")
local rows = 0
for _ in queries[1]:gmatch("'Salvage'") do rows = rows + 1 end
eq(rows, 50, "a log row per item")
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
-- a batch rate limit
clock = clock + 5000
S.onAction(player, "salvageBatch", {bag = "", maxRarity = 1, sig = "x"})
S.onAction(player, "salvageBatch", {bag = "", maxRarity = 1, sig = "x"})
eq(lastResult().text, "Wait a moment before the next batch.", "one batch per interval")

-- combining
local have = player:getItemCount(cfg.shard.id)
assert(have >= 25, "enough shards for a Chaos Orb: " .. have)
act("combine", {key = "chaos", count = 1})
eq(lastResult().ok, true, "combined")
eq(player:getItemCount(cfg.shard.id), have - 25, "25 shards spent")
eq(player:getItemCount(29856), 1, "a Chaos Orb")
act("combine", {key = "exalted", count = 1})
eq(lastResult().ok, false, "not enough for an Exalted Orb")
eq(player:getItemCount(29855), 0, "no Exalted Orb")
act("combine", {key = "chaos", count = 99})
eq(lastResult().ok, false, "more than maxCombine refused")
-- a full backpack: the orb goes to the inbox
full = true
put(backpack, newItem(cfg.shard.id, {count = 25}))
act("combine", {key = "chaos", count = 1})
eq(lastResult().ok, true, "combined with a full backpack")
eq(countIn(inbox, 29856), 1, "the orb is in the inbox")
full = false

-- an orb that makes a new copy keeps the lock
local copy = newItem(2401)
S.copyLock(locked, copy)
eq(copy.custom.chaos_locked, 1, "copyLock")
S.copyLock(sword, copy)
eq(copy.custom.chaos_locked, 1, "copyLock never unlocks")

print("salvage_test: ok")
