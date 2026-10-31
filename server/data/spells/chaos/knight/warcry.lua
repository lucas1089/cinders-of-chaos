-- Iron Bellow: taunts every monster within 4 sqm and slows them 25% for 6s. The knight gains Iron Will for 8s:
-- 25% less damage taken and +15% shielding.
-- The damage cut is applied by data/scripts/chaos/spell_guard.lua.
dofile('data/spells/scripts/chaos/_common.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local guard = Condition(CONDITION_ATTRIBUTES)
	guard:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.iron_will)
	guard:setParameter(CONDITION_PARAM_TICKS, 8000)
	guard:setParameter(CONDITION_PARAM_SKILL_SHIELDPERCENT, 115)
	guard:setParameter(CONDITION_PARAM_BUFF_SPELL, true)
	player:addCondition(guard)

	local pos = player:getPosition()
	ChaosSpell.fx(pos, "blood_ring", CONST_ME_SOUND_RED)
	ChaosSpell.vfx(pos, "aura_burst_gold")
	for _, c in ipairs(ChaosSpell.enemiesAround(player, pos, 4)) do
		doChallengeCreature(player, c)
		ChaosSpell.slow(c, 6000, 0.25)
		ChaosSpell.fx(c:getPosition(), "blood_rune", CONST_ME_SOUND_RED)
	end
	return true
end
