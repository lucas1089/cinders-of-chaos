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

local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	ChaosJewelryLoot.normalize(item)
end
moved:register(9) -- before base_rarity.lua (10) and item_mods.lua (11) read the worn item

local login = CreatureEvent("ChaosJewelryLogin")
function login.onLogin(player)
	for slot = CONST_SLOT_FIRST or 1, CONST_SLOT_LAST or 10 do
		local item = player:getSlotItem(slot)
		if item then
			ChaosJewelryLoot.normalize(item)
		end
	end
	return true
end
login:register()
