-- Three of a stackable into one of the next quality: the part the gems (gems.lua G.combine) and the support runes
-- (supports.lua S.combine) share. Used by "use with" on a stack, also on the stack itself (server/README.md "Gems and
-- sockets", "Spell supports"). Tested by tests/gems_test.lua and tests/supports_test.lua against a mocked engine.
--
--   ChaosCombine.placeOf(player, item)   "carried" (equipment, backpack and the bags in it: what the engine's
--       player:getItemCount / removeItem see), "box" (the player's own but outside that walk: the purse = store inbox,
--       the depot inbox, the depot chest; only their owner can open them) or nil (the ground, someone else's)
--   ChaosCombine.take(player, id, need, used, target)   takes `need` of id: the clicked stacks outside the engine's
--       walk first, the rest from what is carried. Everything is counted before anything is taken; a removal that
--       fails gives back what was taken. Returns true, or false and a reason key: "notYours", "locked" (the item lock,
--       custom attribute chaos_locked), "needThree" (too few)
--   ChaosCombine.give(player, id, count)   into the backpack; what does not fit goes to the depot inbox, without one
--       to the player's feet (never lost). Returns false (all in the backpack), "inbox" or "ground"
--   ChaosCombine.whereText(where)   " It is in your inbox (no room)." / " It is at your feet (no room)." / ""
--
-- Why: TFS Player::getItemTypeCount / removeItemOfType (src-patch 0009) walk inventory slots 1-10 and their
-- containers. The purse is slot 11 and the depot hangs off the locker, so a stack there was never counted.
-- Lua 5.1 / LuaJIT and 5.3.

ChaosCombine = ChaosCombine or {}
local K = ChaosCombine

-- ITEM_STORE_INBOX, ITEM_INBOX, ITEM_LOCKER1 (TFS const.h; not Lua enums)
K.BOX = {[26052] = "purse", [14404] = "inbox", [2589] = "locker"}

local function holderOf(item)
	local ok, top = pcall(function() return item:getTopParent() end)
	if ok and top and top.isPlayer and top:isPlayer() then
		return top
	end
	return nil
end

function K.owns(player, item)
	local h = holderOf(item)
	return h ~= nil and h:getId() == player:getId()
end

local function idOf(thing)
	if not thing or not thing.isItem then
		return nil
	end
	local ok, id = pcall(function() return thing:isItem() and thing:getId() end)
	return ok and id or nil
end

function K.placeOf(player, item)
	local inBox = false
	local p = item
	for _ = 1, 32 do
		local ok, parent = pcall(function() return p:getParent() end)
		if not ok or not parent then
			break
		end
		local kind = K.BOX[idOf(parent)]
		if kind == "inbox" or kind == "locker" then
			return "box"
		elseif kind == "purse" then
			inBox = true
		end
		p = parent
	end
	if K.owns(player, item) then
		return inBox and "box" or "carried"
	end
	return nil
end

function K.isLocked(item)
	local ok, v = pcall(function() return item:getCustomAttribute("chaos_locked") end)
	return ok and (tonumber(v) or 0) ~= 0
end

local function same(a, b)
	local ok, r = pcall(function() return a == b end)
	return ok and r or rawequal(a, b)
end

function K.give(player, id, count)
	local rest = count - (tonumber(Chaos.giveItem(player, id, count)) or 0)
	if rest <= 0 then
		return false
	end
	local inbox = player:getInbox()
	if inbox then
		inbox:addItem(id, rest, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		return "inbox"
	end
	Game.createItem(id, rest, player:getPosition())
	return "ground"
end

function K.whereText(where)
	if where == "inbox" then
		return " It is in your inbox (no room)."
	elseif where == "ground" then
		return " It is at your feet (no room)."
	end
	return ""
end

function K.take(player, id, need, used, target)
	local boxed, extra = {}, 0
	local picked = {}
	for _, s in ipairs({used, target}) do
		if type(s) ~= "number" and s and s.getId and s:getId() == id and not (picked[1] and same(picked[1], s)) then
			picked[#picked + 1] = s
			local place = K.placeOf(player, s)
			if not place then
				return false, "notYours"
			end
			if K.isLocked(s) then
				return false, "locked"
			end
			if place == "box" then
				local n = tonumber(s:getCount()) or 0
				boxed[#boxed + 1] = {item = s, count = n}
				extra = extra + n
			end
		end
	end
	local carried = tonumber(player:getItemCount(id)) or 0
	if carried + extra < need then
		return false, "needThree"
	end
	local taken = 0
	for _, b in ipairs(boxed) do
		local n = math.min(need, b.count)
		if n > 0 then
			if b.item:remove(n) == false then
				if taken > 0 then
					K.give(player, id, taken)
				end
				return false, "needThree"
			end
			need, taken = need - n, taken + n
		end
	end
	if need > 0 and not player:removeItem(id, need) then
		if taken > 0 then
			K.give(player, id, taken)
		end
		return false, "needThree"
	end
	return true
end

return K
