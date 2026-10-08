local arr = {
	{0, 1, 0},
	{1, 3, 1},
	{0, 1, 0}
}
local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_HOLYDAMAGE)
combat:setArea(createCombatArea(arr))
function onGetFormulaValues(player, level, magicLevel)
	local power = player:getEffectiveSkillLevel(SKILL_DISTANCE) * ChaosSpell.distanceAttack(player)
	return -power, -power * 2
end
combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")
function onCastSpell(creature, variant)
	return combat:execute(creature, variant)
end
