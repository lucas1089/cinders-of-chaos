-- Monster levels in the name (server/README.md "Monster levels in the name"). Owner, 2026-10-16: only the
-- level-scaled monsters showed "[level]" after the name; stock monsters (no <level> in their XML) showed none.
-- At every spawn (EventCallback onSpawn, before the placement, so the first creature packet carries it) a monster
-- without a level of its own gets a display level (engine patch 0040, monster:setDisplayLevel): ChaosLoot.monsterLevel,
-- the level the item level, monster damage and pace already use. Display only: health, speed, damage, experience,
-- skull and getMonsterLevel() stay as they were. The decision is monster_levels_core.lua.
-- Without patch 0040 (no setDisplayLevel) this does nothing.
-- Assumed engine API (TFS 1.4.2 + 0040): EventCallback onSpawn, Monster:getMonsterLevel / setDisplayLevel /
-- getMaster / getType, MonsterType:getExperience / getMaxHealth.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/monster_levels_core.lua")

ChaosMonsterLevels = ChaosMonsterLevels or {}
local ML = ChaosMonsterLevels
local K = ChaosMonsterLevelsCore

local function try(fn)
	local ok, res = pcall(fn)
	if ok then
		return res
	end
	return nil
end

-- the level the Chaos systems use for a monster (loot.lua), else the same estimate from its type
function ML.estimate(monster)
	if ChaosLoot and ChaosLoot.monsterLevel then
		local lv = try(function() return ChaosLoot.monsterLevel(monster) end)
		if lv then
			return lv
		end
	end
	local mt = try(function() return monster:getType() end)
	if mt and ChaosItemMods and ChaosItemMods.estimateMonsterLevel then
		return ChaosItemMods.estimateMonsterLevel(try(function() return mt:getExperience() end) or 0,
			try(function() return mt:getMaxHealth() end) or 0)
	end
	return nil
end

-- sets the display level of one monster; returns the level shown (nil when none was set)
function ML.apply(monster)
	if not monster or not monster.setDisplayLevel then
		return nil
	end
	local own = try(function() return monster:getMonsterLevel() end) or 0
	local master = try(function() return monster:getMaster() end)
	local playerSummon = master ~= nil and try(function() return master:isPlayer() end) == true
	local lv = K.displayLevel(own, (own > 0 or playerSummon) and nil or ML.estimate(monster), playerSummon)
	if lv then
		pcall(function() monster:setDisplayLevel(lv) end)
	end
	return lv
end

local spawnCb = EventCallback
spawnCb.onSpawn = function(self, position, startup, artificial)
	ML.apply(self)
	return true
end
spawnCb:register(50) -- after the renames (monster_tiers.lua, index -100): the type behind the shown name is read anyway
