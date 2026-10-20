-- Temple cleanse, pure logic (temple_cleanse.lua; server/README.md "Temple cleanse"): a player in a protection zone who is
-- not flagged for fighting other players loses the debuffs of monsters and bosses (burning, poison, bleeding, freezing,
-- curse, ...) and the battle lock they hold open, so a boss's 10-minute fire cannot keep a character from the town
-- portal, the NPCs or a logout. Tested by tests/temple_cleanse_test.lua. Lua 5.1 / LuaJIT and 5.3 compatible.

ChaosTempleCleanseCore = ChaosTempleCleanseCore or {}
local K = ChaosTempleCleanseCore

-- engine condition constants to remove (names; the engine file resolves them), harmful ones only
K.conditions = {"CONDITION_FIRE", "CONDITION_POISON", "CONDITION_ENERGY", "CONDITION_BLEEDING", "CONDITION_FREEZING",
	"CONDITION_DAZZLED", "CONDITION_CURSED", "CONDITION_DROWN", "CONDITION_PARALYZE", "CONDITION_ROOT", "CONDITION_INFIGHT"}

-- clear only inside a protection zone and never for a player locked for attacking players or carrying a skull
-- (the zone is a refuge from monsters, not from the consequences of PvP)
function K.shouldClear(state)
	if not state or not state.inProtectionZone then
		return false
	end
	if state.pzLocked or state.skulled then
		return false
	end
	return state.hasDebuff == true
end

return K
