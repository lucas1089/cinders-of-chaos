-- gear_sets.lua: the equipment sets of client pair 28 in the monster loot (server/README.md "Equipment sets (pair 28)").
-- The items themselves (items.otb, items.xml, equip and weapon entries) are installed by server/tools/install_gear_sets.py;
-- the switch, the sources and the rules are data/lib/chaos_gear_sets.lua.
--
-- Only while ChaosGearSets.PAIR28 is on: at startup every row of ChaosGearSets.lootRows() (monster, item id, chance per
-- 100000) is added to that monster type with MonsterType:addLoot, as fist_weapons.lua does, so no monster file changes.
-- Monster types are loaded after data/scripts, hence the startup event. A missing monster or item is reported and
-- skipped. The chaos loot layer's extra rolls, smart loot, the Item Finder and the bestiary read MonsterType:getLoot(),
-- so they see the rows too.
ChaosGearSets = ChaosGearSets or dofile("data/lib/chaos_gear_sets.lua")

ChaosGearSetLoot = ChaosGearSetLoot or {}

-- adds the loot rows once per server run; returns added, skipped (0, 0 while the switch is off)
function ChaosGearSetLoot.addAll(rows)
	if ChaosGearSetLoot.done or not ChaosGearSets.PAIR28 then
		return 0, 0
	end
	local added, skipped, missing = 0, 0, {}
	for _, row in ipairs(rows or ChaosGearSets.lootRows()) do
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
				print(string.format("[Chaos gear sets] loot of %s skipped: %s", mon, why))
			end
		end
	end
	ChaosGearSetLoot.done = true
	return added, skipped
end

local startup = GlobalEvent("ChaosGearSetLoot")
function startup.onStartup()
	if not ChaosGearSets.PAIR28 then
		return true
	end
	local added, skipped = ChaosGearSetLoot.addAll()
	print(string.format("[Chaos gear sets] %d loot rows added to the monster types (%d skipped)", added, skipped))
	return true
end
startup:register()
