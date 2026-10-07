-- Soul Aegis: mana shield for 15s plus mana regeneration while it lasts (stock "Magic Shield" has no regen).
dofile('data/spells/scripts/chaos/_common.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local ticks = 15000

	local shield = Condition(CONDITION_MANASHIELD)
	shield:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.soul_aegis)
	shield:setParameter(CONDITION_PARAM_TICKS, ticks)
	player:addCondition(shield)

	local regen = Condition(CONDITION_REGENERATION)
	regen:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.soul_aegis + 1000)
	regen:setParameter(CONDITION_PARAM_TICKS, ticks)
	regen:setParameter(CONDITION_PARAM_MANAGAIN, 20 + math.floor(player:getLevel() / 10))
	regen:setParameter(CONDITION_PARAM_MANATICKS, 1000)
	player:addCondition(regen)

	local pos = player:getPosition()
	ChaosSpell.fx(pos, "arcane_circle", CONST_ME_MAGIC_BLUE)
	return true
end
