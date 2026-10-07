-- Judgement: heavy holy strike, +50% damage against targets below 25% health.
dofile('data/spells/scripts/chaos/_common.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local target = ChaosSpell.targetOf(variant)
	if not target or target == player then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUCANONLYUSEITONCREATURES)
	end
	local dist = player:getEffectiveSkillLevel(SKILL_DISTANCE)
	local min, max = ChaosSpell.mlValues(player, 3.4, 5.6, 60, 110)
	min = min + dist * 0.4
	max = max + dist * 0.7
	if target:getHealth() < target:getMaxHealth() * 0.25 then
		min, max = min * 1.5, max * 1.5
	end
	ChaosSpell.shoot(player:getPosition(), target:getPosition(), "holy_arrow", CONST_ANI_HOLY)
	ChaosSpell.damageTarget(player, target, COMBAT_HOLYDAMAGE, min, max, Fx("holy_smite", CONST_ME_HOLYDAMAGE))
	return true
end
