-- fist_weapons.lua: the Monk line's fist weapons in the monster loot (docs/CLASSES.md "Monk", server/README.md "Fist
-- weapons"). The items themselves (items.otb / items.xml, the Monk-only equip entries, the NPC shops) are installed by
-- server/tools/install_fist_weapons.py; their attack is used by monk_combat.lua (ChaosMonk.cfg.unarmed.fistWeapons).
--
-- At startup every row of ChaosFistWeapons.loot (data/lib/chaos_fist_weapons.lua: monster, item id, chance per 100000)
-- is added to that monster type with MonsterType:addLoot, so no monster file changes. Monster types are loaded after
-- data/scripts, hence the startup event. A missing monster or item is reported and skipped. The chaos loot layer's extra
-- rolls and the bestiary read MonsterType:getLoot(), so they see the rows too.
if not ChaosFistWeapons then
	dofile('data/lib/chaos_fist_weapons.lua')
end

ChaosFistLoot = ChaosFistLoot or {}

-- adds the loot rows once per server run; returns added, skipped
function ChaosFistLoot.addAll(rows)
	if ChaosFistLoot.done then
		return 0, 0
	end
	local added, skipped = 0, 0
	for _, row in ipairs(rows or ChaosFistWeapons.loot) do
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
			print(string.format('[Chaos fist weapons] loot of %s skipped: %s', mon, mt and ('no item ' .. id) or 'no such monster'))
		end
	end
	ChaosFistLoot.done = true
	return added, skipped
end

local startup = GlobalEvent("ChaosFistWeaponLoot")
function startup.onStartup()
	local added, skipped = ChaosFistLoot.addAll()
	print(string.format('[Chaos fist weapons] %d loot rows added to the monster types (%d skipped)', added, skipped))
	return true
end
startup:register()
