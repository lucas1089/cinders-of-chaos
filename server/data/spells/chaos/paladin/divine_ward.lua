-- Lightward: cleanses harmful conditions and grants 8s of strong regeneration.
dofile('data/spells/scripts/chaos/_common.lua')

local CLEANSE = {
	CONDITION_POISON, CONDITION_FIRE, CONDITION_ENERGY, CONDITION_BLEEDING,
	CONDITION_CURSED, CONDITION_FREEZING, CONDITION_DAZZLED, CONDITION_DROWN,
	CONDITION_PARALYZE,
}

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	for _, ctype in ipairs(CLEANSE) do
		player:removeCondition(ctype)
	end

	local regen = Condition(CONDITION_REGENERATION)
	regen:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.divine_ward)
	regen:setParameter(CONDITION_PARAM_TICKS, 8000)
	regen:setParameter(CONDITION_PARAM_HEALTHGAIN, 60 + math.floor(player:getMagicLevel() * 1.5))
	regen:setParameter(CONDITION_PARAM_HEALTHTICKS, 1000)
	regen:setParameter(CONDITION_PARAM_MANAGAIN, 15)
	regen:setParameter(CONDITION_PARAM_MANATICKS, 1000)
	player:addCondition(regen)

	local pos = player:getPosition()
	ChaosSpell.vfxOr(pos, "dawn_aegis", "aura_ring", CONST_ME_HOLYAREA)
	pos:sendMagicEffect(CONST_ME_MAGIC_BLUE)
	return true
end
