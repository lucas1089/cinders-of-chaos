-- ChaosItemPrices: what an NPC pays for an item. One source of truth for the Loot Buyer NPCs, the base NPC shops
-- (server/tools/install_item_prices.py writes the same prices into them) and the Auto Seller (autosell.lua, through
-- sell_prices.lua or ChaosItemPrices.sellPrice). Overview and rules: server/README.md "Item prices".
--
-- The numbers are generated: data/lib/chaos_item_prices_data.lua (server/tools/gen_item_prices.py). This file holds
-- only the formula and the API. It loads in any Lua state (scripts, NPCs) and needs no engine call for the id
-- functions; sellPrice(item) reads the item's attributes. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
-- Tested by server/tests/item_prices_test.lua.
--
-- API
--   ChaosItemPrices.basePrice(id)            gold for a plain copy (0: no NPC buys it)
--   ChaosItemPrices.unsellable(id)           reason key ("currency", "key", "quest", "store", "bound", "broker",
--                                            "unique") or nil
--   ChaosItemPrices.reasonText(id)           the reason as a sentence, or nil
--   ChaosItemPrices.priceFor(id, info)       gold for one copy described by info = {rarity = 0..15, ilvl = 0..150,
--                                            unique = name or nil, charmRarity = 0..3}; pure
--   ChaosItemPrices.instanceInfo(item)       info of an item (custom attributes "rarity", "chaos_ilvl", "chaos_unique"
--                                            with the item's name, "charm_r")
--   ChaosItemPrices.sellPrice(itemOrId[, count])
--                                            what an NPC pays: an item userdata is priced as that copy (rarity, item
--                                            level, unique), a number as a plain copy; count defaults to the item's
--                                            count (1 for a number). 0 when no NPC buys it.
--   ChaosItemPrices.prices()                 {[id] = plain price}: the flat table (the Auto Seller's sell_prices.lua)
--   ChaosItemPrices.minBuyPrice(id)          the least an NPC may ask for the item (no arbitrage): price / buyShare
--   ChaosItemPrices.saleBlock(item)          nil when a Loot Buyer may take this copy, else why not: "locked" (the item
--                                            lock), "unique" (never sold: salvage or market), "container" (not empty),
--                                            "price"
--   ChaosItemPrices.carried(player[, id])    the items in the player's containers (not the equipped ones), with that
--                                            id or all; walks the backpack and its containers
--   ChaosItemPrices.sell(player, items, amount)
--                                            sells up to `amount` units of these items: removes them and returns
--                                            gold, units, kept (copies refused by saleBlock), sold names; pays nothing
--
-- Formula: price of a copy = prices[id] x R x L, rounded down.
--   R: no rarity 1; rarity 1..15 rarityMult (Common 1, Uncommon 1.5, Rare 3, Epic 6, Legendary 12, ... Transcendent
--      32); a charm charmMult. A unique copy (chaos_unique) is never sold to an NPC: 0 (owner 2026-10-14: salvage or
--      market)
--   L: 1 + item level / ilvlDiv, for equipment and charms (`gear`); 1 for everything else

ChaosItemPrices = ChaosItemPrices or {}
local P = ChaosItemPrices

local function loadData()
	local ok, data = pcall(dofile, "data/lib/chaos_item_prices_data.lua")
	if ok and type(data) == "table" then
		return data
	end
	print("[ChaosItemPrices] data/lib/chaos_item_prices_data.lua not loaded: " .. tostring(data))
	return {prices = {}, unsellable = {}, gear = {}, reasons = {}, rarityMult = {}, charmMult = {}, ilvlDiv = 200,
		buyShare = 0.5}
end

P.data = P.data or loadData()

-- tests (and a reload) can hand in other data
function P.setData(data)
	P.data = data
end

local floor = math.floor

local function num(v)
	v = tonumber(v)
	if not v or v ~= v then
		return 0
	end
	return v
end

function P.basePrice(id)
	return P.data.prices[tonumber(id) or 0] or 0
end

function P.unsellable(id)
	return P.data.unsellable[tonumber(id) or 0]
end

function P.reasonText(id)
	local r = P.unsellable(id)
	return r and (P.data.reasons[r] or r) or nil
end

function P.prices()
	return P.data.prices
end

function P.minBuyPrice(id)
	local p = P.basePrice(id)
	if p <= 0 then
		return 0
	end
	return math.ceil(p / (P.data.buyShare or 0.5))
end

-- the multiplier of a rarity (0 = none)
function P.rarityMult(rarity)
	rarity = floor(num(rarity))
	if rarity < 1 then
		return 1
	end
	local m = P.data.rarityMult
	return m[math.min(rarity, #m)] or 1
end

function P.levelMult(id, ilvl)
	ilvl = num(ilvl)
	if ilvl <= 0 or not P.data.gear[tonumber(id) or 0] then
		return 1
	end
	return 1 + math.min(ilvl, 150) / (P.data.ilvlDiv or 200)
end

function P.priceFor(id, info)
	id = tonumber(id) or 0
	info = info or {}
	if P.data.unsellable[id] then
		return 0
	end
	if info.unique then
		return 0 -- a unique copy: salvage or market, never an NPC
	end
	local L = P.levelMult(id, info.ilvl)
	local base = P.basePrice(id)
	if base <= 0 then
		return 0
	end
	local R = P.rarityMult(info.rarity)
	local c = floor(num(info.charmRarity))
	if c >= 1 then
		local cm = P.data.charmMult
		R = cm[math.min(c, #cm)] or 1
	end
	return floor(base * R * L)
end

local function custom(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	if ok then
		return v
	end
	return nil
end

function P.instanceInfo(item)
	local info = {rarity = num(custom(item, "rarity")), ilvl = num(custom(item, "chaos_ilvl")),
		charmRarity = num(custom(item, "charm_r"))}
	if custom(item, "chaos_unique") ~= nil then
		local ok, name = pcall(function() return item:getName() end)
		info.unique = ok and name or ""
	end
	return info
end

function P.sellPrice(item, count)
	if type(item) == "number" or type(item) == "string" then
		return P.priceFor(item, nil) * floor(num(count ~= nil and count or 1))
	end
	if item == nil then
		return 0
	end
	local ok, id = pcall(function() return item:getId() end)
	if not ok or not id then
		return 0
	end
	if count == nil then
		local oks, stack = pcall(function() return item:getType():isStackable() end)
		local okc, c = pcall(function() return item:getCount() end)
		count = (oks and stack and okc) and c or 1
	end
	count = math.max(floor(num(count)), 1)
	return P.priceFor(id, P.instanceInfo(item)) * count
end

-- ---------------------------------------------------------------- selling (the Loot Buyer; any script)
function P.saleBlock(item)
	if num(custom(item, "chaos_locked")) ~= 0 then
		return "locked"
	end
	if custom(item, "chaos_unique") ~= nil then
		return "unique"
	end
	local okc, isContainer = pcall(function() return item:isContainer() end)
	if okc and isContainer then
		local oks, size = pcall(function() return item:getSize() end)
		if oks and (size or 0) > 0 then
			return "container"
		end
	end
	if P.sellPrice(item, 1) <= 0 then
		return "price"
	end
	return nil
end

local function walk(container, id, out, depth)
	if depth > 8 then
		return
	end
	local okz, size = pcall(function() return container:getSize() end)
	for i = (okz and size or 0) - 1, 0, -1 do
		local item = container:getItem(i)
		if item then
			if not id or item:getId() == id then
				out[#out + 1] = item
			end
			local okc, isContainer = pcall(function() return item:isContainer() end)
			if okc and isContainer then
				walk(item, id, out, depth + 1)
			end
		end
	end
end

function P.carried(player, id)
	local out = {}
	local bag = player:getSlotItem(CONST_SLOT_BACKPACK or 3)
	if bag then
		local okc, isContainer = pcall(function() return bag:isContainer() end)
		if okc and isContainer then
			walk(bag, id and tonumber(id) or nil, out, 0)
		end
	end
	return out
end

function P.sell(player, items, amount)
	amount = amount or math.huge
	local gold, units, kept, names = 0, 0, 0, {}
	for _, item in ipairs(items) do
		if units >= amount then
			break
		end
		local why = P.saleBlock(item)
		if why then
			kept = kept + 1
		else
			local oks, stack = pcall(function() return item:getType():isStackable() end)
			local count = (oks and stack) and math.max(floor(num(item:getCount())), 1) or 1
			local take = math.min(count, amount - units)
			local price = P.sellPrice(item, take)
			local okn, name = pcall(function() return item:getName() end)
			if price > 0 and item:remove(take) then
				gold = gold + price
				units = units + take
				names[#names + 1] = (take > 1 and (take .. "x ") or "") .. (okn and name or "item")
			end
		end
	end
	return gold, units, kept, names
end

return P
