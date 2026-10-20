local condition = Condition(CONDITION_LIGHT)
condition:setParameter(CONDITION_PARAM_TICKS, 6 * 60 * 1000)
function onCastSpell(creature, variant)
	return creature:addCondition(condition)
end
