-- Item fusion: which copies a fusion may take (O508). Pure logic, tested by server/tests/item_fusion_test.lua against
-- a mocked player. Lua 5.1 / LuaJIT and Lua 5.3.
--
-- The base item fusion (opcode 67, data/scripts/customs/item_fusion/item_fusion.lua of the base server) ran
-- player:removeItem(id, 3). The engine takes by item id only (src/player.cpp Player::removeItemOfType): the slots in
-- order (head, necklace, the backpack with everything inside it, armor, right hand, left hand, legs, feet, ring, ammo,
-- then the extra slots), the first three it meets. A unique is a stock item with a custom attribute, so a fusion of
-- three plain copies could take the unique lying before them in the bag, or worn in an earlier slot. The same held
-- for a set piece and for a copy with a rarity, modifiers, sockets, quality or a transmog look.
--
-- Install step `fusionplain` (server/tools/patch_base_fusion_plain.py) makes the base script call F.take instead.
--
--   ChaosItemFusion.keptWhy(item)             nil when the copy is plain, else why a fusion never takes it:
--                                             "locked"     the item lock (chaos_locked; the engine skipped it already,
--                                                          src-patch 0009)
--                                             "fixed"      unique, set piece, raid or faction gear, store-bound, store
--                                                          item (ChaosCrafting.hasFixedValues)
--                                             "rolled"     a rarity, modifiers or a +N level (not ChaosCrafting.isNormal)
--                                             "sockets"    sockets or a gem
--                                             "worked"     quality or a transmog look (F.OWN_WORK)
--                                             "container"  a container with something inside
--                                             "norules"    the crafting rules did not load, or a rule failed: no copy
--                                                          is plain (fail closed)
--   ChaosItemFusion.copies(player, id)        -> {{item = Item, count = n}, ...} the plain copies of server id `id` in
--                                             the engine's order, and how many copies were kept
--   ChaosItemFusion.take(player, id, amount)  removes `amount` plain copies; true only when all of them are gone.
--                                             Fewer plain copies than `amount`: false, nothing is removed.
--
-- The item level of a plain drop (chaos_ilvl) does not make a copy special: every gear drop carries one.

ChaosItemFusion = ChaosItemFusion or {}
local F = ChaosItemFusion

-- the player's own work on an item that ChaosCrafting.isNormal does not see
F.OWN_WORK = {"chaos_quality", "chaos_tmog"}
F.GEM_SLOTS = 6

local function custom(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	if not ok then
		return nil
	end
	return v
end

-- the crafting rules (data/lib/chaos_crafting.lua loads chaos_gems.lua); loaded on first use, never at file load
local function rules()
	if type(ChaosCrafting) ~= "table" then
		pcall(dofile, "data/lib/chaos_crafting.lua")
	end
	local C, G = ChaosCrafting, ChaosGems
	if type(C) ~= "table" or type(C.hasFixedValues) ~= "function" or type(C.isNormal) ~= "function"
		or type(C.customNumber) ~= "function" or type(G) ~= "table" or type(G.count) ~= "function" then
		return nil
	end
	return C, G
end

local function why(item, C, G)
	if C.customNumber(item, "chaos_locked") ~= 0 then
		return "locked"
	end
	if C.hasFixedValues(item) then
		return "fixed"
	end
	if not C.isNormal(item) then
		return "rolled"
	end
	if G.count(item) > 0 then
		return "sockets"
	end
	for i = 1, F.GEM_SLOTS do
		if custom(item, "chaos_gem" .. i) ~= nil then
			return "sockets"
		end
	end
	for _, key in ipairs(F.OWN_WORK) do
		if custom(item, key) ~= nil then
			return "worked"
		end
	end
	local okc, isContainer = pcall(function() return item:isContainer() end)
	if okc and isContainer then
		local oks, size = pcall(function() return item:getSize() end)
		if not oks or (tonumber(size) or 0) > 0 then
			return "container"
		end
	end
	return nil
end

function F.keptWhy(item)
	local C, G = rules()
	if not C then
		return "norules"
	end
	local ok, reason = pcall(why, item, C, G)
	if not ok then
		return "norules"
	end
	return reason
end

local function countOf(item)
	local oks, stackable = pcall(function() return item:getType():isStackable() end)
	if oks and stackable then
		local okc, count = pcall(function() return item:getCount() end)
		return math.max(math.floor(okc and tonumber(count) or 1), 1)
	end
	return 1
end

function F.copies(player, id)
	local out, kept = {}, 0
	local function see(item)
		if item:getId() ~= id then
			return false
		end
		if F.keptWhy(item) == nil then
			out[#out + 1] = {item = item, count = countOf(item)}
		else
			kept = kept + 1
		end
		return true
	end
	for slot = CONST_SLOT_FIRST or 1, CONST_SLOT_LAST or 16 do
		local item = player:getSlotItem(slot)
		-- as the engine: a slot item of this id is one copy, any other container is searched to the bottom
		if item and not see(item) then
			local okc, isContainer = pcall(function() return item:isContainer() end)
			if okc and isContainer then
				local oki, items = pcall(function() return item:getItems(true) end)
				if oki and type(items) == "table" then
					for _, inner in ipairs(items) do
						see(inner)
					end
				end
			end
		end
	end
	return out, kept
end

function F.take(player, id, amount)
	id, amount = tonumber(id), tonumber(amount)
	if not player or not id or not amount or amount < 1 or amount ~= math.floor(amount) then
		return false
	end
	local ok, list = pcall(F.copies, player, id)
	if not ok or type(list) ~= "table" then
		return false
	end
	local have = 0
	for _, e in ipairs(list) do
		have = have + e.count
	end
	if have < amount then
		return false
	end
	local left, clean = amount, true
	for _, e in ipairs(list) do
		if left <= 0 then
			break
		end
		local n = math.min(e.count, left)
		local okr, gone = pcall(function()
			if e.count > 1 then
				return e.item:remove(n)
			end
			return e.item:remove()
		end)
		if okr and gone == true then
			left = left - n
		else
			clean = false
		end
	end
	return clean and left <= 0
end

return F
