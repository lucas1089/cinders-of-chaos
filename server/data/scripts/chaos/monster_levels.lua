-- Monster levels in the name (server/README.md "Monster levels in the name"). Owner, 2026-10-16: only the
-- level-scaled monsters showed "[level]" after the name; stock monsters (no <level> in their XML) showed none.
-- At every spawn (EventCallback onSpawn, before the placement, so the first creature packet carries it) a monster
-- without a level of its own gets a display level (engine patch 0040, monster:setDisplayLevel): its HUNTING level
-- (ChaosLoot's pool level x pace_config.lua baseLevelMult, owner 2026-10-27; loot, damage and pace keep the pool level). Display only: health, speed, damage, experience,
-- skull and getMonsterLevel() stay as they were. The decision is monster_levels_core.lua.
-- Rift, invasion and generated area / dungeon monsters show the level their system scaled them to instead: the system
-- passes it as Chaos.spawnLevel (Chaos.createMonsterNamed's shownLevel); with engine patch 0044 it wins over a level of
-- the monster's own. Without patch 0040 (no setDisplayLevel) this does nothing.
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

local function paceMult()
	local pc = ChaosPaceConfig
	if not pc then
		local ok, c = pcall(dofile, "data/scripts/chaos/pace_config.lua")
		pc = ok and c or nil
	end
	return pc and tonumber(pc.baseLevelMult) or 1
end

-- the level a monster without a level of its own is shown at: its HUNTING level (owner 2026-10-27). A generated
-- area / dungeon point and a waystone tier give the hunting level already; the bounty pool's level (ChaosLoot) or the
-- experience / health estimate is on the pool scale and is multiplied by pace_config.lua baseLevelMult. Second result:
-- false for a monster that is not in the bounty pool (its level is then raised to its hunt's, see ML.apply)
function ML.estimate(monster)
	local id = try(function() return monster:getId() end)
	local point = id and ChaosAreaGen and ChaosAreaGen.pointOf and ChaosAreaGen.pointOf[id]
	if point and tonumber(point.level) and tonumber(point.level) > 0 then
		return tonumber(point.level), true
	end
	local pool
	-- a type that is not in the bounty pool has only the experience / health estimate (see K.raise below)
	local listed = true
	if ChaosLoot and ChaosLoot.poolLevelOf then
		listed = try(function() return ChaosLoot.poolLevelOf(monster) end) ~= nil
	end
	if ChaosLoot and ChaosLoot.baseMonsterLevel then
		pool = try(function() return ChaosLoot.baseMonsterLevel(monster) end)
	elseif ChaosLoot and ChaosLoot.monsterLevel then
		pool = try(function() return ChaosLoot.monsterLevel(monster) end)
	end
	if ChaosWaystoneTiers and ChaosWaystoneTiers.levelOf then
		local wl = try(function() return ChaosWaystoneTiers.levelOf(monster, pool) end)
		if tonumber(wl) and tonumber(wl) > 0 then
			return tonumber(wl), true
		end
	end
	if not pool then
		local mt = try(function() return monster:getType() end)
		if mt and ChaosItemMods and ChaosItemMods.estimateMonsterLevel then
			pool = ChaosItemMods.estimateMonsterLevel(try(function() return mt:getExperience() end) or 0,
				try(function() return mt:getMaxHealth() end) or 0)
		end
	end
	return K.huntingLevel(pool, paceMult()), listed
end

-- sets the display level of one monster; returns the level shown (nil when none was set). scaled (optional): the
-- level its system scaled it to (Chaos.spawnLevel), shown even over a level of its own (engine patch 0044)
local huntIndex
local function hunts()
	if huntIndex == nil then
		huntIndex = false
		local file = (ChaosPoiConfig and ChaosPoiConfig.dataFile) or "data/chaos_poi.lua"
		local ok, data = pcall(dofile, file)
		if ok and type(data) == "table" and type(data.marks) == "table" then
			huntIndex = K.indexHunts(data.marks)
		end
	end
	return huntIndex or nil
end
ML.hunts = hunts

-- a monster that is not in the bounty pool (a Sheep, a Mirror Image, a rare spawn: only the experience / health
-- estimate) standing in a high-level hunt showed a level below 10 (beta 2026-10-27): it is shown at the lower end of
-- the hunting area it stands in. The summon of a monster is shown at least at its master's level.
local function raisedLevel(monster, lv, listed, position)
	local floor
	local pos = position or try(function() return monster:getPosition() end)
	if pos then
		floor = K.areaFloor(hunts(), pos.x, pos.y, pos.z)
		-- a monster of the pool keeps its level unless it is far below the hunt (a Badger in a level 120 hunt)
		if floor and listed and lv >= floor * K.farBelow then
			floor = nil
		end
	end
	local master = try(function() return monster:getMaster() end)
	if master and master ~= monster and try(function() return master:isMonster() end) == true then
		local own = try(function() return master:getMonsterLevel() end) or 0
		local ml = own > 0 and own or ML.estimate(master)
		if ml and (not floor or ml > floor) then
			floor = ml
		end
	end
	return K.raise(lv, floor)
end

function ML.apply(monster, scaled, position)
	if not monster or not monster.setDisplayLevel then
		return nil
	end
	local own = try(function() return monster:getMonsterLevel() end) or 0
	-- O163: a stock level range (1-10) on a type with the stats of level 150+ is not its level: show the hunting level
	-- (the display level wins over the engine's own level, patch 0044)
	if own > 0 and ChaosLoot and ChaosLoot.ownLevel then
		own = try(function() return ChaosLoot.ownLevel(monster) end) or own
	end
	local master = try(function() return monster:getMaster() end)
	local playerSummon = master ~= nil and try(function() return master:isPlayer() end) == true
	local estimate, listed
	if not (own > 0 or playerSummon or scaled) then
		estimate, listed = ML.estimate(monster)
	end
	local lv = K.displayLevel(own, estimate, playerSummon, scaled)
	if lv and estimate then
		lv = K.displayLevel(0, raisedLevel(monster, lv, listed, position), false, nil) or lv
	end
	if lv then
		pcall(function() monster:setDisplayLevel(lv) end)
	end
	return lv
end

local spawnCb = EventCallback
spawnCb.onSpawn = function(self, position, startup, artificial)
	-- one monster per call (Chaos.createMonsterNamed sets it around one Game.createMonster): a creature made inside
	-- another callback gets its own
	local scaled = Chaos and Chaos.spawnLevel
	if Chaos then
		Chaos.spawnLevel = nil
	end
	ML.apply(self, scaled, position)
	return true
end
spawnCb:register(50) -- after the renames (monster_tiers.lua, index -100): the type behind the shown name is read anyway
