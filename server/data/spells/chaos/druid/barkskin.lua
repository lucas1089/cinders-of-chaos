-- Barkskin: +20% max health and steady regeneration for 20s.
dofile('data/spells/scripts/chaos/_common.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local ticks = 20000

	local hp = Condition(CONDITION_ATTRIBUTES)
	hp:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.barkskin)
	hp:setParameter(CONDITION_PARAM_TICKS, ticks)
	hp:setParameter(CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT, 120)
	hp:setParameter(CONDITION_PARAM_BUFF_SPELL, true)
	player:addCondition(hp)

	local regen = Condition(CONDITION_REGENERATION)
	regen:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.barkskin + 1000)
	regen:setParameter(CONDITION_PARAM_TICKS, ticks)
	regen:setParameter(CONDITION_PARAM_HEALTHGAIN, 20 + math.floor(player:getMagicLevel() * 0.5))
	regen:setParameter(CONDITION_PARAM_HEALTHTICKS, 2000)
	player:addCondition(regen)

	ChaosSpell.fx(player:getPosition(), "heal_sparkle", CONST_ME_MAGIC_GREEN)
	return true
end
