-- Store delivery: pure rules (no engine calls), shared by store_delivery.lua and server/tests/store_delivery_test.lua.
-- README "Store", Delivery to the purse. Owner 2026-10-16: "Make the things bought in the store go to the purse."
-- The purse is the engine's store inbox (item 26052, inventory slot 11 of the 10.98 protocol): the client's "Open purse"
-- button under the equipment opens it, every character has one, it is never dropped at death.
--   ChaosStoreDeliveryCore.route(s)   s = {purse, purseCapOk, inbox} -> {destinations in order}, reason
--   ChaosStoreDeliveryCore.message(counts, reason)   the buyer's line: text key + arguments, or nil (nothing placed)
--   ChaosStoreDeliveryCore.text(counts, reason)   the same line in English
--   ChaosStoreDeliveryCore.stacks(count, stackable, maxStack)   the item counts to create for count of an item
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosStoreDeliveryCore = ChaosStoreDeliveryCore or {}
local K = ChaosStoreDeliveryCore

-- the places in the order they are tried. purse = the character has a store inbox, purseCapOk = the character can
-- carry the item's weight (the base engine counts the store inbox in the inventory weight, so the purse respects
-- capacity as the backpack delivery did), inbox = a depot inbox exists (weight free, reached at any depot).
-- The backpack is the last resort. Never the ground. reason: nil, "missing" or "capacity" (why not the purse).
function K.route(s)
	local out, reason = {}, nil
	if s.purse and s.purseCapOk then
		out[#out + 1] = "purse"
	elseif not s.purse then
		reason = "missing"
	else
		reason = "capacity"
	end
	if s.inbox then
		out[#out + 1] = "inbox"
	end
	out[#out + 1] = "backpack"
	return out, reason
end

-- after a purse attempt that the engine refused: the reason for the message
K.FULL = "full"

-- the texts (keys of i18n_strings.lua; the engine file translates the key and each word argument with Chaos.t)
K.ALL_PURSE = "Delivered to your purse (the button under your equipment)."
K.ONE_PLACE = "Delivered to your %s (%s)."
K.SPLIT = "Delivered: %d to your purse, %d to your depot inbox, %d to your backpack (%s)."
K.PLACE = {inbox = "depot inbox", backpack = "backpack"}
K.WHY = {
	missing = "you have no purse",
	capacity = "not enough capacity for the purse",
	full = "your purse could not take it"
}

-- counts = {purse = n, inbox = n, backpack = n} (items placed); reason = why some did not go to the purse.
-- Returns the text key and its arguments ({word = true} marks an argument to translate), or nil when nothing was placed.
function K.message(counts, reason)
	local p, i, b = counts.purse or 0, counts.inbox or 0, counts.backpack or 0
	if p + i + b == 0 then
		return nil
	end
	if i + b == 0 then
		return K.ALL_PURSE, {}
	end
	local why = K.WHY[reason] or K.WHY.full
	if p == 0 and (i == 0 or b == 0) then
		return K.ONE_PLACE, {{word = K.PLACE[i > 0 and "inbox" or "backpack"]}, {word = why}}
	end
	return K.SPLIT, {p, i, b, {word = why}}
end

-- the English line (tests, logs)
function K.text(counts, reason)
	local key, args = K.message(counts, reason)
	if not key then
		return nil
	end
	local plain = {}
	for n, a in ipairs(args) do
		plain[n] = type(a) == "table" and a.word or a
	end
	return string.format(key, (table.unpack or unpack)(plain))
end

-- the counts of the items to create: stackables in stacks of maxStack (100), others one by one
function K.stacks(count, stackable, maxStack)
	count = math.max(0, math.floor(tonumber(count) or 0))
	local out = {}
	if not stackable then
		for i = 1, count do
			out[i] = 1
		end
		return out
	end
	maxStack = maxStack or 100
	while count > 0 do
		local n = math.min(maxStack, count)
		out[#out + 1] = n
		count = count - n
	end
	return out
end

return K
