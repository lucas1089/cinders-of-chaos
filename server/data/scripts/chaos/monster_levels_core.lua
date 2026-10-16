-- Monster levels in the name (monster_levels.lua; server/README.md "Monster levels in the name"): the pure part.
-- A level-scaled monster (a <level min max> in its XML) shows its rolled level after the name through the engine
-- ("Black Stag [777]"). Every other monster gets the level the Chaos systems already use for it
-- (ChaosLoot.monsterLevel: the bounty pool's hunting level, else the experience / health estimate) as a display level
-- (engine patch 0040, monster:setDisplayLevel): shown only, no stat change. A monster a system scaled (rift, invasion,
-- generated area or dungeon) shows that level instead, even over its own (patch 0044). tests/monster_levels_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3.

ChaosMonsterLevelsCore = ChaosMonsterLevelsCore or {}
local K = ChaosMonsterLevelsCore

local function level(v)
	local lv = tonumber(v)
	if not lv or lv ~= lv or lv <= 0 or lv == math.huge then
		return nil
	end
	return math.max(1, math.floor(lv + 0.5))
end

-- the display level of a monster: nil when it is a player's summon (a pet or a conjured creature: its level is the
-- owner's business); else `scaled` when given (the level a rift, an invasion or a generated area scaled it to:
-- Chaos.spawnLevel; it wins over the own level, engine patch 0044); else nil when it shows its own (own > 0) or no
-- estimate is known; else the estimate, at least 1
function K.displayLevel(own, estimate, playerSummon, scaled)
	if playerSummon then
		return nil
	end
	local forced = level(scaled)
	if forced then
		return forced
	end
	if (tonumber(own) or 0) > 0 then
		return nil
	end
	return level(estimate)
end

return K
