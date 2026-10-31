-- Red Frenzy: +30% melee skill, -30% shield skill for 12s.
-- Not the stock Bloodlust.
dofile('data/spells/scripts/chaos/_common.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local buff = Condition(CONDITION_ATTRIBUTES)
	buff:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.crimson_fury)
	buff:setParameter(CONDITION_PARAM_TICKS, 12000)
	buff:setParameter(CONDITION_PARAM_SKILL_MELEEPERCENT, 130)
	buff:setParameter(CONDITION_PARAM_SKILL_SHIELDPERCENT, 70)
	buff:setParameter(CONDITION_PARAM_BUFF_SPELL, true)
	player:addCondition(buff)

	local pos = player:getPosition()
	ChaosSpell.vfxOr(pos, "aura_burst_red", "blood_rune", CONST_ME_DRAWBLOOD)
	pos:sendMagicEffect(CONST_ME_MAGIC_RED)
	return true
end
