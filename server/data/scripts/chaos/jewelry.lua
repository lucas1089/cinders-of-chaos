-- jewelry.lua: rings and necklaces as ordinary equipment, the game side (server/README.md "Rings and necklaces as
-- gear"). The rules and numbers are data/lib/chaos_jewelry.lua; server/tools/patch_base_jewelry.py (install step
-- `jewelry`) makes the base rings and necklaces permanent in items.xml and movements.xml.
--
--   1. the loot: at startup every row of ChaosJewelry.lootRows (the bounty pool's hunt monsters and bosses by their
--      hunting level, a few bases each) is added to that monster type with MonsterType:addLoot, as gear_sets.lua does,
--      so no monster file changes. The chaos loot layer then rolls rarity, item level, prefixes and suffixes as for any
--      gear drop; extra rolls, smart loot, the Item Finder and the bestiary read MonsterType:getLoot() and see them.
--   2. old copies: a ring or necklace made before the install step may still carry charges or a time left; they come
--      off when the item is moved and at login (ChaosJewelry.normalize), so the engine never counts them down.
--   3. old uniques on consumable bases (Ring of the Last Ember on the worn time ring 2206 or, taken off, the time ring
--      2169; Heart of Cinders 10218; Heartbleed Pendant 10221) turn into their own bases 41640-41642
--      (ChaosJewelry.uniqueBases): name, stats, rarity and sockets stay (they are item attributes). A copy in a
--      container turns when moved and at login; a worn copy is taken off into the backpack at login first (so the
--      engine removes the old type's stats), then turns; the player puts it on again.
ChaosJewelry = ChaosJewelry or dofile("data/lib/chaos_jewelry.lua")

ChaosJewelryLoot = ChaosJewelryLoot or {}

local function levelOf(e)
	if ChaosPaceCore and ChaosPaceCore.entryLevel then
		local cfg = ChaosPaceConfig
		if not cfg then
			local ok, c = pcall(dofile, "data/scripts/chaos/pace_config.lua")
			cfg = ok and c or nil
		end
		local ok, level = pcall(ChaosPaceCore.entryLevel, cfg, e)
		if ok and tonumber(level) then
			return level
		end
	end
	return (tonumber(e.level) or 1) * 2
end

-- adds the loot rows once per server run; returns added, skipped
function ChaosJewelryLoot.addAll(rows)
	if ChaosJewelryLoot.done then
		return 0, 0
	end
	if not rows then
		if not ChaosPaceCore then
			pcall(dofile, "data/scripts/chaos/pace_core.lua")
		end
		local ok, pool = pcall(dofile, "data/scripts/chaos/bounty_pool.lua")
		rows = ChaosJewelry.lootRows(ok and pool or {}, levelOf)
	end
	local added, skipped, missing = 0, 0, {}
	for _, row in ipairs(rows) do
		local mon, id, chance = row[1], row[2], row[3]
		local mt = MonsterType(mon)
		local it = ItemType(id)
		if mt and it and it:getId() == id then
			local loot = Loot()
			loot:setId(id)
			loot:setChance(chance)
			loot:setMaxCount(1)
			if mt:addLoot(loot) then
				added = added + 1
			else
				skipped = skipped + 1
			end
		else
			skipped = skipped + 1
			local why = mt and ("no item " .. id) or "no such monster"
			if not missing[mon .. why] then
				missing[mon .. why] = true
				print(string.format("[Chaos jewelry] loot of %s skipped: %s", tostring(mon), why))
			end
		end
	end
	ChaosJewelryLoot.done = true
	return added, skipped
end

local startup = GlobalEvent("ChaosJewelryLoot")
function startup.onStartup()
	local added, skipped = ChaosJewelryLoot.addAll()
	print(string.format("[Chaos jewelry] %d ring and necklace loot rows added to the monster types (%d skipped)", added,
		skipped))
	return true
end
startup:register()

-- ---------------------------------------------------------------- old copies
local ATTR = {charges = ITEM_ATTRIBUTE_CHARGES, duration = ITEM_ATTRIBUTE_DURATION}

function ChaosJewelryLoot.normalize(item)
	if not item or not ItemType then
		return 0
	end
	local ok, n = pcall(function()
		return ChaosJewelry.normalize(item, ItemType(item:getId()), ATTR)
	end)
	return ok and n or 0
end

-- the new id of an old unique copy on a consumable base, or nil
function ChaosJewelryLoot.uniqueTarget(item)
	if not item then
		return nil
	end
	local ok, target = pcall(function()
		local marker = item:getCustomAttribute("chaos_unique")
		local name = ITEM_ATTRIBUTE_NAME and item:getAttribute(ITEM_ATTRIBUTE_NAME) or nil
		return ChaosJewelry.uniqueTarget(item:getId(), marker ~= nil and marker ~= 0 and marker ~= false, name)
	end)
	return ok and target or nil
end

-- turns an old unique copy (not worn) into its own base; true when it did
function ChaosJewelryLoot.migrateUnique(item)
	local target = ChaosJewelryLoot.uniqueTarget(item)
	if not target then
		return false
	end
	local ok, done = pcall(function() return item:transform(target) end)
	if not ok or not done then
		return false
	end
	ChaosJewelryLoot.normalize(item)
	return true
end

local function inSlot(position)
	-- an inventory slot: x 0xFFFF, y the slot (a container is y 0x40 + its index)
	return position and position.x == 65535 and position.y < 64
end

local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	if not inSlot(toPosition) then
		ChaosJewelryLoot.migrateUnique(item)
	end
	ChaosJewelryLoot.normalize(item)
end
moved:register(9) -- before base_rarity.lua (10) and item_mods.lua (11) read the worn item

-- at login: worn old uniques go to the backpack and turn; the backpack's old uniques turn. Returns how many turned.
function ChaosJewelryLoot.migratePlayer(player)
	local n = 0
	local backpack = player:getSlotItem(CONST_SLOT_BACKPACK)
	local bag = backpack and backpack:isContainer() and backpack or nil
	for slot = CONST_SLOT_FIRST or 1, CONST_SLOT_LAST or 10 do
		local item = player:getSlotItem(slot)
		if item and slot ~= CONST_SLOT_BACKPACK and ChaosJewelryLoot.uniqueTarget(item) and bag then
			-- the move runs the old type's DeEquip (the time ring turns back into 2169 on the way)
			local ok, moved = pcall(function() return item:moveTo(bag) end)
			if ok and moved and ChaosJewelryLoot.migrateUnique(item) then
				n = n + 1
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
					Chaos.t(player, "Your unique ring or amulet was renewed and put in your backpack. Put it on again."))
			end
		end
	end
	if bag then
		local ok, items = pcall(function() return bag:getItems(true) end)
		for _, item in ipairs(ok and items or {}) do
			if ChaosJewelryLoot.migrateUnique(item) then
				n = n + 1
			end
		end
	end
	return n
end

local login = CreatureEvent("ChaosJewelryLogin")
function login.onLogin(player)
	ChaosJewelryLoot.migratePlayer(player)
	for slot = CONST_SLOT_FIRST or 1, CONST_SLOT_LAST or 10 do
		local item = player:getSlotItem(slot)
		if item then
			ChaosJewelryLoot.normalize(item)
		end
	end
	return true
end
login:register()
