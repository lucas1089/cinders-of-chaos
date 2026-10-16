-- Monster levels in the name (monster_levels.lua; server/README.md "Monster levels in the name"): the pure part.
-- A level-scaled monster (a <level min max> in its XML) shows its rolled level after the name through the engine
-- ("Black Stag [777]"). Every other monster gets the level the Chaos systems already use for it
-- (ChaosLoot.monsterLevel: the bounty pool's hunting level, else the experience / health estimate) as a display level
-- (engine patch 0040, monster:setDisplayLevel): shown only, no stat change. tests/monster_levels_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3.

ChaosMonsterLevelsCore = ChaosMonsterLevelsCore or {}
local K = ChaosMonsterLevelsCore

-- the display level of a monster: nil when it shows its own (own > 0), when it is a player's summon (a pet or a
-- conjured creature: its level is the owner's business) or when no estimate is known; else the estimate, at least 1
function K.displayLevel(own, estimate, playerSummon)
	if (tonumber(own) or 0) > 0 or playerSummon then
		return nil
	end
	local lv = tonumber(estimate)
	if not lv or lv ~= lv or lv <= 0 then
		return nil
	end
	return math.max(1, math.floor(lv + 0.5))
end

return K
