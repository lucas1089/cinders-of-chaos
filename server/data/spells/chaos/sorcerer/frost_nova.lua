-- Rime Bloom: ice burst around the caster, chills everything it hits.
dofile('data/spells/scripts/chaos/_common.lua')

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_ICEDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, Fx("frost_burst", CONST_ME_ICEAREA))
combat:setArea(createCombatArea(AREA_CIRCLE3X3))

function onGetFormulaValues(player, level, magicLevel)
	local min = (level / 5) + (magicLevel * 2.5) + 23
	local max = (level / 5) + (magicLevel * 4.15) + 40
	return -min, -max
end

function onFrostNovaTarget(creature, target)
	ChaosSpell.slow(target, 4000, 0.4)
	return true
end

combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")
combat:setCallback(CALLBACK_PARAM_TARGETCREATURE, "onFrostNovaTarget")

function onCastSpell(creature, variant, isHotkey)
	return combat:execute(creature, variant)
end
