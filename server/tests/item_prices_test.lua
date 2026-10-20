-- Run from the server/ folder: luajit tests/item_prices_test.lua (and lua5.3; CI runs both)
-- The item price table (data/lib/chaos_item_prices.lua, data/lib/chaos_item_prices_data.lua; server/README.md
-- "Item prices"): the formula (rarity, item level, uniques, charms), the unsellable list, the Auto Seller's flat table
-- (sell_prices.lua) against the table, no arbitrage against the Chaos NPCs that sell items (Wandering Merchant, rune
-- supply) and against the Gambler (the expected sale of a sealed piece stays under its price), the Loot Buyer's sale
-- rules against mocked items (locked, unique, a full container, stacks, the backpack walk) and the NPC placement
-- (item_prices.lua) against a mocked map.

local count, failures = 0, 0
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

dofile("data/lib/chaos_item_prices.lua")
local P = ChaosItemPrices
local D = P.data

-- ---------------------------------------------------------------- the data
local priced, unsell = 0, 0
for id, price in pairs(D.prices) do
	priced = priced + 1
	check(type(id) == "number" and price >= 1 and price == math.floor(price), "price of " .. tostring(id) .. " is a whole number >= 1")
	check(D.unsellable[id] == nil, "item " .. id .. " is not both priced and unsellable")
end
for id, reason in pairs(D.unsellable) do
	unsell = unsell + 1
	check(D.reasons[reason] ~= nil, "reason of " .. id .. " is documented: " .. tostring(reason))
end
check(priced > 2000, "more than 2000 priced items (" .. priced .. ")")
check(unsell > 50, "an unsellable list (" .. unsell .. ")")

-- currency, keys, store-bound and the profession materials are never sold
for id, why in pairs({[2148] = "currency", [2152] = "currency", [2160] = "currency", [29856] = "currency",
		[29857] = "currency", [24691] = "currency", [32256] = "store", [32051] = "currency", [32081] = "bound",
		[32082] = "bound", [32083] = "bound", [32084] = "bound", [10155] = "key", [32071] = "key", [32072] = "key",
		[32091] = "currency", [32351] = "broker", [28095] = "store", [27990] = "store", [32305] = "unique",
		[32306] = "unique"}) do
	eq(P.unsellable(id), why, "unsellable " .. id)
	eq(P.basePrice(id), 0, "no price for " .. id)
	eq(P.sellPrice(id, 10), 0, "sellPrice 0 for " .. id)
	check(P.reasonText(id) ~= nil, "reason text for " .. id)
end

-- the Auto Seller's table is this table, id for id
local flat = dofile("data/scripts/chaos/sell_prices.lua")
local same, n = true, 0
for id, price in pairs(flat) do
	n = n + 1
	if D.prices[id] ~= price then
		same = false
		print("  sell_prices.lua " .. id .. " = " .. price .. ", table " .. tostring(D.prices[id]))
	end
end
eq(n, priced, "sell_prices.lua has every priced item")
check(same, "sell_prices.lua and the price table agree")
check(P.prices() == D.prices, "prices() is the table")

-- ---------------------------------------------------------------- the formula (on test data)
local real = P.data
P.setData({
	prices = {[100] = 1000, [200] = 50, [300] = 2000}, gear = {[100] = true, [300] = true}, unsellable = {[400] = "quest"},
	reasons = {quest = "a quest item"}, rarityMult = real.rarityMult, charmMult = real.charmMult, ilvlDiv = 200,
	buyShare = 0.5
})
eq(P.priceFor(100, nil), 1000, "plain gear")
eq(P.priceFor(100, {rarity = 1}), 1000, "Common x1")
eq(P.priceFor(100, {rarity = 2}), 1500, "Uncommon x1.5")
eq(P.priceFor(100, {rarity = 3}), 3000, "Magic x3")
eq(P.priceFor(100, {rarity = 4}), 6000, "Rare x6")
eq(P.priceFor(100, {rarity = 5}), 12000, "Legendary x12")
eq(P.priceFor(100, {rarity = 10}), 24000, "Divine x24")
eq(P.priceFor(100, {rarity = 15}), 24000, "an old Transcendent is Divine: x24")
eq(P.priceFor(100, {rarity = 7}), 12000, "an old Mythic is Legendary: x12")
eq(P.priceFor(100, {rarity = 99}), 1000, "an id out of range: no rarity")
eq(P.priceFor(100, {ilvl = 100}), 1500, "item level 100: x1.5")
eq(P.priceFor(100, {ilvl = 150, rarity = 5}), 21000, "Legendary at item level 150: x12 x1.75")
eq(P.priceFor(100, {ilvl = 900}), 1750, "item level capped at 150")
eq(P.priceFor(200, {ilvl = 100, rarity = 3}), 150, "not gear: rarity counts, item level does not")
eq(P.priceFor(100, {unique = "Soulreaper"}), 0, "a unique copy is never sold (salvage or market)")
eq(P.priceFor(100, {unique = "Soulreaper", ilvl = 100, rarity = 5}), 0, "a unique copy: 0 whatever its level and rarity")
eq(P.priceFor(300, {charmRarity = 3}), 6000, "Radiant charm x3")
eq(P.priceFor(400, {rarity = 5}), 0, "unsellable stays 0")
eq(P.priceFor(999, {}), 0, "unknown item 0")
eq(P.sellPrice(100, 3), 3000, "an id: plain x count")
eq(P.minBuyPrice(100), 2000, "an NPC asks at least twice the sell price")
-- rarer and higher sells for more
for rank = 2, 6 do
	local r, below = ChaosRarity.idOfRank(rank), ChaosRarity.idOfRank(rank - 1)
	check(P.rarityMult(r) > P.rarityMult(below), ChaosRarity.name(r) .. " pays more than " .. ChaosRarity.name(below))
end
check(real.reasons.unique ~= nil and real.reasons.unique:find("salvage or market", 1, true) ~= nil, "unique reason documented")
check(real.uniques == nil and real.uniqueMult == nil, "no unique prices in the table")
check(P.levelMult(100, 120) > P.levelMult(100, 60), "a higher item level pays more")

-- ---------------------------------------------------------------- mocked items
local function item(id, opts)
	opts = opts or {}
	local it = {id = id, count = opts.count or 1, attrs = opts.attrs or {}, name = opts.name or ("item " .. id),
		stack = opts.stack or false, contents = opts.contents, removed = 0}
	function it:getId() return self.id end
	function it:getCount() return self.count end
	function it:getName() return self.name end
	function it:getCustomAttribute(k) return self.attrs[k] end
	function it:getType() local s = self.stack return {isStackable = function() return s end} end
	function it:isContainer() return self.contents ~= nil end
	function it:getSize() return self.contents and #self.contents or 0 end
	function it:getItem(i) return self.contents and self.contents[i + 1] end
	function it:remove(n)
		n = n or self.count
		if n > self.count then
			return false
		end
		self.count = self.count - n
		self.removed = self.removed + n
		return true
	end
	return it
end

local plain = item(100)
local rare = item(100, {attrs = {rarity = 3, chaos_ilvl = 50}})
local locked = item(100, {attrs = {rarity = 5, chaos_locked = 1}})
local uniq = item(100, {attrs = {chaos_unique = 1}, name = "Soulreaper"})
local stack = item(200, {count = 30, stack = true})
local inner = item(100, {attrs = {rarity = 2}})
local pouch = item(300, {contents = {inner}})
local quest = item(400)

local info = P.instanceInfo(rare)
eq(info.rarity, 3, "instanceInfo rarity")
eq(info.ilvl, 50, "instanceInfo item level")
eq(P.instanceInfo(uniq).unique, "Soulreaper", "instanceInfo unique name")
eq(P.sellPrice(rare), 3750, "Rare at item level 50: 1000 x3 x1.25")
eq(P.sellPrice(stack), 1500, "a stack: 30 x 50")
eq(P.sellPrice(stack, 10), 500, "part of a stack")
eq(P.sellPrice(uniq), 0, "a unique copy: 0")
eq(P.saleBlock(plain), nil, "plain: sold")
eq(P.saleBlock(locked), "locked", "locked: kept")
eq(P.saleBlock(uniq), "unique", "unique: always kept")
eq(P.saleBlock(pouch), "container", "a container with items: kept")
eq(P.saleBlock(quest), "price", "unsellable: kept")

-- the backpack walk: the equipped items are not touched, nested containers are
local bag = item(1988, {contents = {plain, rare, locked, uniq, stack, pouch, quest}})
local player = {slots = {[3] = bag}}
function player:getSlotItem(slot) return self.slots[slot] end
CONST_SLOT_BACKPACK = 3
local all = P.carried(player)
eq(#all, 8, "carried: seven in the backpack and one in the pouch")
local only = P.carried(player, 100)
eq(#only, 5, "carried with an id: the five copies of item 100")
local gold, units, kept, names = P.sell(player, only, 3)
eq(units, 3, "sold three units of item 100")
eq(kept >= 1, true, "the locked / unique copies were kept")
check(locked.removed == 0 and uniq.removed == 0, "locked and unique copies untouched")
eq(gold, 1000 + 3750 + 1500, "paid each copy at its own price (plain, rare, uncommon in the pouch)")
eq(#names, 3, "three sold names")
gold, units = P.sell(player, {stack}, 12)
eq(units, 12, "a stack sold in part")
eq(stack.count, 18, "the rest of the stack stays")
eq(gold, 600, "12 x 50")
gold = P.sell(player, {uniq}, nil)
eq(gold, 0, "a unique is never sold")
eq(uniq.removed, 0, "the unique stays")
P.setData(real)

-- ---------------------------------------------------------------- no arbitrage against the Chaos NPCs
local inv = dofile("data/scripts/chaos/invasion_config.lua")
for _, it in ipairs(inv.worldEvents.merchant.items) do
	check(P.basePrice(it.id) < it.price, "Wandering Merchant: " .. it.name .. " sells for more than an NPC pays")
	-- even the best copy: an orb is unsellable, a potion is no gear
	check(P.priceFor(it.id, {rarity = 10, ilvl = 150}) < it.price, "Wandering Merchant: the best copy of " .. it.name)
end
-- the Wandering Merchant's rarity orbs on a plain copy (owner 2026-10-14: Gilding 250,000): the expected gain at item
-- level 150 never reaches the orb's price, for any equipment (the real orb tables of chaos_crafting.lua)
local function merchantPrice(id)
	for _, it in ipairs(inv.worldEvents.merchant.items) do
		if it.id == id then
			return it.price
		end
	end
end
ChaosGems = ChaosGems or {config = dofile("data/lib/chaos_gems_config.lua")}
local okc = pcall(dofile, "data/lib/chaos_crafting.lua")
check(okc and ChaosCrafting and ChaosCrafting.config, "chaos_crafting.lua loads")
if okc and ChaosCrafting then
	local cc = ChaosCrafting.config
	local tot, gild = 0, 0
	for _, w in ipairs(cc.alchemy) do
		tot = tot + w[2]
	end
	for _, w in ipairs(cc.alchemy) do
		gild = gild + w[2] / tot * P.rarityMult(w[1])
	end
	local left, fate, got = cc.divineRollChance / 100, 0, 0
	for r, c in ipairs(cc.divineChances) do
		local p = left * math.floor(c) / 100
		fate, got = fate + p * P.rarityMult(ChaosRarity.idOfRank(r)), got + p
		left = left * (1 - math.floor(c) / 100)
	end
	fate = fate + (1 - got)
	eq(merchantPrice(24691), 250000, "the merchant's Orb of Gilding costs 250,000")
	local top, topId = 0, 0
	for id, price in pairs(D.prices) do
		if D.gear[id] and price > top then
			top, topId = price, id
		end
	end
	local lmax = P.levelMult(topId, 150)
	check(top * (gild - 1) * lmax < merchantPrice(24691), string.format("Gilding a plain copy (best %d: +%.0f) never pays", top, top * (gild - 1) * lmax))
	check(top * (fate - 1) * lmax < merchantPrice(29857), string.format("Fate on a plain copy (+%.0f) never pays", top * (fate - 1) * lmax))
end
dofile("data/lib/chaos_rune_supply.lua")
local R = ChaosRuneSupply or {}
for _, rune in ipairs(R.runes or {}) do
	check(P.basePrice(rune.id) <= rune.price, "rune supply: " .. rune.name .. " sold for " .. rune.price .. ", bought back for " .. P.basePrice(rune.id))
end

-- the Gambler: the expected sale of a sealed piece is below what it costs (no gold from gambling and selling)
local gcfg = dofile("data/scripts/chaos/gamble_config.lua")
dofile("data/scripts/chaos/gamble_core.lua")
dofile("data/lib/chaos_item_mods.lua")
local K, M = ChaosGambleCore, ChaosItemMods
local lootcfg = dofile("data/scripts/chaos/loot_config.lua")
local odds = K.odds(gcfg, lootcfg.gear)
local ev = 0
for rank = 0, 6 do -- odds are by place (0 none, 1 Common .. 6 Divine)
	ev = ev + (odds[rank] or 0) * (rank == 0 and 1 or P.rarityMult(ChaosRarity.idOfRank(rank)))
end
check(ev > 1 and ev < 20, "gamble expected rarity multiplier " .. ev)
local worst, worstText = 0, ""
for slot, list in pairs(gcfg.pool) do
	for _, entry in ipairs(list) do
		for level = math.max(entry[2], 1), 1500, 7 do
			local gate = M.sourceLevel({monsterLevel = level, tier = gcfg.itemLevel.tier})
			local low = math.max(1, gate - gcfg.itemLevel.spread)
			local cost = K.price(gcfg, low, slot)
			local sale = P.basePrice(entry[1]) * ev * P.levelMult(entry[1], gate)
			if cost > 0 and sale / cost > worst then
				worst, worstText = sale / cost, string.format("%s %d at level %d: sale %.0f, price %d", slot, entry[1], level, sale, cost)
			end
		end
	end
end
check(worst < 1, "the Gambler: expected sale under the price everywhere (worst " .. string.format("%.2f", worst) .. ": " .. worstText .. ")")

-- ---------------------------------------------------------------- the NPC placement (item_prices.lua)
local created = {}
Game = {
	getTowns = function() return {
		{getName = function() return "Cinderhold" end, getTemplePosition = function() return {x = 100, y = 100, z = 7} end},
		{getName = function() return "Thornmere" end, getTemplePosition = function() return {x = 300, y = 300, z = 7} end}} end,
	getSpectators = function() return {} end,
	createNpc = function(name, pos) created[#created + 1] = {name = name, pos = pos} return {} end
}
Position = function(x, y, z) return {x = x, y = y, z = z} end
CONST_PROP_BLOCKSOLID, TILESTATE_TELEPORT, TILESTATE_FLOORCHANGE = 1, 2, 4
Tile = function(pos)
	-- the first offset of the second town is blocked
	local blocked = pos.x == 296 and pos.y == 303
	return {getGround = function() return true end, hasProperty = function() return blocked end,
		getTopCreature = function() return nil end, hasFlag = function() return false end}
end
local events = {}
GlobalEvent = function(name) local e = {name = name} function e:register() events[#events + 1] = self end return e end
addEvent = function(fn) fn() end
local oldPrint = print
print = function() end
dofile("data/scripts/chaos/item_prices.lua")
check(#events == 1, "one startup event")
events[1].onStartup()
print = oldPrint
eq(#created, 2, "a Loot Buyer per town")
eq(created[1] and created[1].name, "Loot Buyer", "the NPC name")
eq(created[2] and created[2].pos.x, 304, "a blocked tile is skipped (next offset)")
check(ChaosItemPrices.sellPrice ~= nil, "the revscript keeps the API")

print(string.format("item_prices_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
