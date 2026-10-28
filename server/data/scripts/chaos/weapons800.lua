-- weapons800.lua: the 34 weapons above level 800 in the monster loot (server/README.md "Weapons above level 800"). The items
-- themselves (items.otb / items.xml, equip and weapon entries) are installed by server/tools/install_weapons800.py, which waits
-- for config.lua chaosClientPair >= 56 (README "Client pair guard"); their bases are also in the class loot families
-- (data/lib/chaos_class_loot.lua: bow, crossbow, wand, rod, melee2h), which carry them to every hunt of their level.
--
-- This file adds the own rows of ChaosWeapons800.loot (data/lib/chaos_weapons800.lua: monster, item id, chance per 100000: 150 on
-- a hunt monster, 1200 on a boss) to the monster types at startup with MonsterType:addLoot, so no monster file changes and the
-- weapon audit (tools/weapon_coverage.lua) has a source to count. They are NOT part of the equipment sets' level gear pool
-- (ChaosGearSets.levelDrop): more pieces there would dilute the set weapons' drop chance below the audit's minimum.
-- Monster types are loaded after data/scripts, hence the startup event. A missing monster or item (the items are installed only
-- with the matching client pair) is reported and skipped. The chaos loot layer's extra rolls and the bestiary read
-- MonsterType:getLoot(), so they see the rows too.
if not ChaosWeapons800 then
	ChaosWeapons800 = dofile('data/lib/chaos_weapons800.lua')
end

ChaosWeapons800Loot = ChaosWeapons800Loot or {}

-- adds the loot rows once per server run; returns added, skipped
function ChaosWeapons800Loot.addAll(rows)
	if ChaosWeapons800Loot.done then
		return 0, 0
	end
	local added, skipped, said = 0, 0, {}
	for _, row in ipairs(rows or ChaosWeapons800.loot) do
		local mon, id, chance = row[1], row[2], row[3]
		local mt = MonsterType(mon)
		local okT, it = pcall(ItemType, id)
		if mt and okT and it and it:getId() == id then
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
			local why = mt and ('no item ' .. id) or 'no such monster'
			if not said[mon .. why] then
				said[mon .. why] = true
				print(string.format('[Chaos weapons 800] loot of %s skipped: %s', tostring(mon), why))
			end
		end
	end
	ChaosWeapons800Loot.done = true
	return added, skipped
end

local startup = GlobalEvent("ChaosWeapons800Loot")
function startup.onStartup()
	local added, skipped = ChaosWeapons800Loot.addAll()
	print(string.format('[Chaos weapons 800] %d loot rows added to the monster types (%d skipped)', added, skipped))
	return true
end
startup:register()
