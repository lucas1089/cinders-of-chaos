-- Blightswarm: toxic cloud around the caster, poisons everything it hits.
dofile('data/spells/scripts/chaos/_common.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_EARTHDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("poison_cloud", CONST_ME_POISONAREA))
combat:setArea(createCombatArea(AREA_CIRCLE3X3))

function onGetFormulaValues(player, level, magicLevel)
	local min = ((level / 5) + (magicLevel * 2.4) + 18) * 0.85
	local max = ((level / 5) + (magicLevel * 4.1) + 36) * 0.85
	return -min, -max
end

function onVenomSwarmTarget(creature, target)
	local dmg = math.max(2, math.floor(creature:getMagicLevel() * 0.25) + 3)
	creature:addDamageCondition(target, CONDITION_POISON, DAMAGELIST_LOGARITHMIC_DAMAGE, dmg)
	return true
end

combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")
combat:setCallback(CALLBACK_PARAM_TARGETCREATURE, "onVenomSwarmTarget")

function onCastSpell(creature, variant, isHotkey)
	if not creature:isPlayer() then
		return false
	end
	return combat:execute(creature, variant)
end
