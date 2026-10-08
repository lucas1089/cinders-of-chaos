local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_FIREDAMAGE)
combat:setArea(createCombatArea(AREA_WAVE4))
function onGetFormulaValues(player, level, magicLevel)
	return -1, -2
end
combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")
function onCastSpell(creature, variant)
	return combat:execute(creature, variant)
end
