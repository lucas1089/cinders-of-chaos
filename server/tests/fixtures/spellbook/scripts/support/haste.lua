local combat = Combat()
combat:setParameter(COMBAT_PARAM_AGGRESSIVE, false)
local condition = Condition(CONDITION_HASTE)
condition:setParameter(CONDITION_PARAM_TICKS, 33000)
combat:addCondition(condition)
function onCastSpell(creature, variant)
	return combat:execute(creature, variant)
end
