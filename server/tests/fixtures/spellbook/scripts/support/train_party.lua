local condition = Condition(CONDITION_ATTRIBUTES)
condition:setParameter(CONDITION_PARAM_TICKS, 2 * 60 * 1000)
condition:setParameter(CONDITION_PARAM_SKILL_MELEE, 15)
condition:setParameter(CONDITION_PARAM_SKILL_SHIELD, 5)
function onCastSpell(creature, variant)
	local party = creature:getParty()
	return party ~= nil
end
