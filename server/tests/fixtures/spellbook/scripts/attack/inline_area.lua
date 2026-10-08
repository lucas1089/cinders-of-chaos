local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_PHYSICALDAMAGE)
combat:setArea(createCombatArea({
	{1, 1, 1},
	{1, 3, 1},
	{1, 1, 1}
}))
function onGetFormulaValues(player, skill, attack, factor)
	return -skill * attack, -skill * attack * 2
end
combat:setCallback(CALLBACK_PARAM_SKILLVALUE, "onGetFormulaValues")
function onCastSpell(creature, variant)
	return combat:execute(creature, variant)
end
