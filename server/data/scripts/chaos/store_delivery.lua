-- Store delivery: every physical item the Store gives goes into the character's purse (the engine's store inbox,
-- item 26052, the client's "Open purse" button under the equipment). Rules in store_delivery_core.lua; README "Store",
-- Delivery to the purse. Owner 2026-10-16: "Make the things bought in the store go to the purse."
--
--   ChaosStoreDelivery.place(player, item)   one item made by the caller (Game.createItem, attributes already set):
--       purse, else the depot inbox, else the backpack; never the ground. Returns where ("purse" | "inbox" |
--       "backpack") and the reason it missed the purse, or nil when nothing took it (the caller still owns the item).
--   ChaosStoreDelivery.giveItems(player, itemId, count)   creates and places count of an item (stacks of 100).
--       Returns a receipt {items, counts, reason} or nil, error text; on a failure every item placed is taken back.
--   ChaosStoreDelivery.takeBack(receipt)   removes the items of a receipt (a bundle part that failed later).
--   ChaosStoreDelivery.tell(player, receipt)   the one chat line (where the items went and why).
--
-- The purse respects capacity as the backpack delivery did: the base engine counts the store inbox in the inventory
-- weight, so an item the character cannot carry goes to the depot inbox (weight free) instead. Items keep every
-- attribute the caller set (the store-bound chaos_storebound / chaos_locked of the pouches and the Everfull Ration).
-- The purse only takes items from the server (the engine refuses a player's move of a normal item into it), so it is
-- a one-way delivery box: the player takes the items out into the backpack. Lua 5.1 / LuaJIT compatible.

dofile("data/scripts/chaos/store_delivery_core.lua")

ChaosStoreDelivery = ChaosStoreDelivery or {}
local D = ChaosStoreDelivery
local K = ChaosStoreDeliveryCore
local NOERR = RETURNVALUE_NOERROR or 0

-- server placement: no slot or capacity limit inside the purse / inbox, and never merged into a stack already there
-- (the receipt keeps the very items, so a failed bundle can take them back)
local function placeFlags()
	return (FLAG_NOLIMIT or 1) + (FLAG_IGNOREAUTOSTACK or 128)
end

function D.purse(player)
	if not player.getStoreInbox then
		return nil
	end
	local ok, purse = pcall(function() return player:getStoreInbox() end)
	return ok and purse or nil
end

local function inbox(player)
	local ok, box = pcall(function() return player:getInbox() end)
	return ok and box or nil
end

local function canCarry(player, item)
	local okC, free = pcall(function() return player:getFreeCapacity() end)
	local okW, weight = pcall(function() return item:getWeight() end)
	if not okC or not okW or type(free) ~= "number" or type(weight) ~= "number" then
		return true -- an engine without these calls: as the purse itself (no check)
	end
	return free >= weight
end

local function tryAt(player, where, item, box)
	if where == "backpack" then
		local ok, ret = pcall(function() return player:addItemEx(item, false, INDEX_WHEREEVER or -1, FLAG_IGNOREAUTOSTACK or 128) end)
		return ok and ret == NOERR
	end
	if not box then
		return false
	end
	local ok, ret = pcall(function() return box:addItemEx(item, INDEX_WHEREEVER or -1, placeFlags()) end)
	return ok and ret == NOERR
end

function D.place(player, item)
	local purse, box = D.purse(player), inbox(player)
	local route, reason = K.route({purse = purse ~= nil, purseCapOk = purse ~= nil and canCarry(player, item), inbox = box ~= nil})
	for _, where in ipairs(route) do
		if tryAt(player, where, item, where == "purse" and purse or box) then
			return where, reason
		end
		if where == "purse" then
			reason = K.FULL
		end
	end
	return nil, reason
end

function D.takeBack(receipt)
	for _, it in ipairs(receipt and receipt.items or {}) do
		pcall(function() it:remove() end)
	end
	if receipt then
		receipt.items = {}
	end
end

-- a receipt to add placed items to (several offers of a bundle share one line)
function D.newReceipt()
	return {items = {}, counts = {}, reason = nil}
end

function D.record(receipt, item, where, reason)
	receipt.items[#receipt.items + 1] = item
	receipt.counts[where] = (receipt.counts[where] or 0) + 1
	receipt.reason = receipt.reason or reason
end

function D.giveItems(player, itemId, count, receipt)
	local it = ItemType(itemId)
	if not it or it:getId() == 0 then
		return nil, "This offer cannot be bought."
	end
	local mine = D.newReceipt()
	for _, n in ipairs(K.stacks(count, it:isStackable(), 100)) do
		local item = Game.createItem(itemId, n)
		if not item then
			D.takeBack(mine)
			return nil, "This offer cannot be bought."
		end
		local where, reason = D.place(player, item)
		if not where then
			pcall(function() item:remove() end)
			D.takeBack(mine)
			local fmt = "%s has no room in the purse, the depot inbox or the backpack."
			return nil, ChaosI18n and ChaosI18n.msg and ChaosI18n.msg(fmt, player:getName()) or string.format(fmt, player:getName())
		end
		D.record(mine, item, where, reason)
	end
	if receipt then
		for _, item in ipairs(mine.items) do
			receipt.items[#receipt.items + 1] = item
		end
		for w, n in pairs(mine.counts) do
			receipt.counts[w] = (receipt.counts[w] or 0) + n
		end
		receipt.reason = receipt.reason or mine.reason
	end
	return receipt or mine
end

function D.tell(player, receipt)
	local key, args = K.message(receipt and receipt.counts or {}, receipt and receipt.reason)
	if not key then
		return nil
	end
	local tr = Chaos and Chaos.t or function(_, fmt, ...) return string.format(fmt, ...) end
	local out = {}
	for n, a in ipairs(args) do
		out[n] = type(a) == "table" and tr(player, a.word) or a
	end
	local text = tr(player, key, (table.unpack or unpack)(out))
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, text)
	return text
end

return D
