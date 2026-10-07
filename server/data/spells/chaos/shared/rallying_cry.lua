-- Rallying Cry: caster and party members within 5 sqm get +10% melee/distance/magic and speed for 12s.
dofile('data/spells/scripts/chaos/_common.lua')

local function buff(target)
	local c = Condition(CONDITION_ATTRIBUTES)
	c:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.rally)
	c:setParameter(CONDITION_PARAM_TICKS, 12000)
	c:setParameter(CONDITION_PARAM_SKILL_MELEEPERCENT, 110)
	c:setParameter(CONDITION_PARAM_SKILL_DISTANCEPERCENT, 110)
	c:setParameter(CONDITION_PARAM_STAT_MAGICPOINTSPERCENT, 110)
	c:setParameter(CONDITION_PARAM_BUFF_SPELL, true)
	target:addCondition(c)

	local h = Condition(CONDITION_HASTE)
	h:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.rally + 1000)
	h:setParameter(CONDITION_PARAM_TICKS, 12000)
	h:setFormula(0.2, -16, 0.2, -16)
	target:addCondition(h)
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	ChaosSpell.fx(player:getPosition(), "aura_ring", CONST_ME_MAGIC_GREEN)
	for _, ally in ipairs(ChaosSpell.alliesAround(player, player:getPosition(), 5, false)) do
		buff(ally)
		ChaosSpell.fx(ally:getPosition(), "aura_ring", CONST_ME_MAGIC_GREEN)
	end
	return true
end
