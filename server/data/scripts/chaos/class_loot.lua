-- class_loot.lua: bows, crossbows, wands, rods, quivers and spellbooks in the loot of the bounty pool monsters (server/README.md
-- "Gear coverage"). The rules and numbers are data/lib/chaos_class_loot.lua. At startup every row of
-- ChaosClassLoot.lootRows (the hunt monsters and bosses by their hunting level) is added to that monster type with
-- MonsterType:addLoot, as gear_sets.lua and jewelry.lua do, so no monster file changes. The chaos loot layer then rolls
-- rarity, item level and modifiers as for any gear drop.
ChaosClassLoot = ChaosClassLoot or dofile("data/lib/chaos_class_loot.lua")

ChaosClassLootAdd = ChaosClassLootAdd or {}

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
function ChaosClassLootAdd.addAll(rows)
	if ChaosClassLootAdd.done then
		return 0, 0
	end
	if not rows then
		if not ChaosPaceCore then
			pcall(dofile, "data/scripts/chaos/pace_core.lua")
		end
		local ok, pool = pcall(dofile, "data/scripts/chaos/bounty_pool.lua")
		rows = ChaosClassLoot.lootRows(ok and pool or {}, levelOf)
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
				print(string.format("[Chaos class loot] loot of %s skipped: %s", tostring(mon), why))
			end
		end
	end
	ChaosClassLootAdd.done = true
	return added, skipped
end

local startup = GlobalEvent("ChaosClassLoot")
function startup.onStartup()
	local added, skipped = ChaosClassLootAdd.addAll()
	print(string.format("[Chaos class loot] %d launcher, wand, quiver and spellbook loot rows added (%d skipped)", added,
		skipped))
	return true
end
startup:register()
