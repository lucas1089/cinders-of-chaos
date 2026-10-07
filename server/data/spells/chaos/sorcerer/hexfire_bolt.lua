-- Hexfire Bolt: single target fire bolt that leaves the target burning.
dofile('data/spells/scripts/chaos/_common.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_FIREDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("fire_nova", CONST_ME_FIREAREA))
combat:setParameter(COMBAT_PARAM_DISTANCEEFFECT, FxMissile("fire_bolt", CONST_ANI_FIRE))

function onGetFormulaValues(player, level, magicLevel)
	local min = (level / 5) + (magicLevel * 3.0) + 15
	local max = (level / 5) + (magicLevel * 5.0) + 30
	return -min, -max
end

combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")

function onCastSpell(creature, variant, isHotkey)
	if not creature:isPlayer() then
		return false
	end
	if not combat:execute(creature, variant) then
		return false
	end
	local target = ChaosSpell.targetOf(variant)
	if target and target ~= creature then
		local dmg = math.max(2, math.floor(creature:getMagicLevel() * 0.15) + 3)
		creature:addDamageCondition(target, CONDITION_FIRE, DAMAGELIST_VARYING_PERIOD, dmg, {10, 12}, 4)
	end
	return true
end
