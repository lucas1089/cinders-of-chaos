-- spell_guard.lua: damage reduction granted by chaos spells.
-- Iron Will (Iron Bellow, knights): while the condition with sub id 71009 (ChaosSpell.SUBID.iron_will in
-- data/spells/scripts/chaos/_common.lua) is on the player, health damage taken is reduced by 25%.
-- The spells run in another Lua state, so the condition itself is the shared signal.

local IRON_WILL_SUBID = 71009
local IRON_WILL_REDUCTION = 0.25

-- the engine hands damage over as positive values; keep whatever sign arrives
local function reduce(value)
	local v = math.floor(math.abs(value) * (1 - IRON_WILL_REDUCTION) + 0.5)
	return value < 0 and -v or v
end

local guard = CreatureEvent("ChaosSpellGuard")
function guard.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType ~= COMBAT_HEALING and creature:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, IRON_WILL_SUBID) then
		primaryDamage = reduce(primaryDamage)
		if secondaryType ~= COMBAT_HEALING then
			secondaryDamage = reduce(secondaryDamage)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
guard:register()

local login = CreatureEvent("ChaosSpellGuardLogin")
function login.onLogin(player)
	player:registerEvent("ChaosSpellGuard")
	return true
end
login:register()
