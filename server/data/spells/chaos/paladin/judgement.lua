-- Final Verdict: heavy holy strike, +50% damage against targets below 25% health.
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
	if not ChaosSpell.canAttack(player, target) then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER)
	end
	local dist = player:getEffectiveSkillLevel(SKILL_DISTANCE)
	local power = dist * ChaosSpell.distanceAttack(player)
	local level, ml = player:getLevel() / 5, player:getMagicLevel()
	local min = level + power * 0.143 + ml * 3 + 60
	local max = level + power * 0.234 + ml * 5 + 110
	if target:getHealth() < target:getMaxHealth() * 0.25 then
		min, max = min * 1.5, max * 1.5
	end
	ChaosSpell.pshoot(player:getPosition(), target:getPosition(), "proj_piercing_arrow_holy", "holy_spear", "holy_arrow", CONST_ANI_HOLY)
	ChaosSpell.vfx(target:getPosition(), "holy_smite")
	ChaosSpell.damageTarget(player, target, COMBAT_HOLYDAMAGE, min, max, Fx("holy_smite", CONST_ME_HOLYDAMAGE))
	return true
end
