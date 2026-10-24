-- Soulward: mana shield for 15s plus mana regeneration while it lasts (the stock Ward of the Mind has no regen).
dofile('data/spells/scripts/chaos/_common.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local ticks = 15000

	-- The engine's mana shield (Game::combatChangeHealth, and the Chaos mana events) asks hasCondition(CONDITION_MANASHIELD)
	-- with sub id 0, so only a sub id 0 condition shields. This one does the work (O162: Soulward alone, with the
	-- buff bar's sub id, shielded nothing). A longer Ward of the Mind keeps its time (a shorter condition of the same sub
	-- id never cuts a longer one).
	local shield = Condition(CONDITION_MANASHIELD)
	shield:setParameter(CONDITION_PARAM_TICKS, ticks)
	player:addCondition(shield)

	-- the buff bar's marker (chaos_buffs.lua "soul_aegis"): shows Soulward by name and time, shields nothing
	local mark = Condition(CONDITION_MANASHIELD)
	mark:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.soul_aegis)
	mark:setParameter(CONDITION_PARAM_TICKS, ticks)
	player:addCondition(mark)

	local regen = Condition(CONDITION_REGENERATION)
	regen:setParameter(CONDITION_PARAM_SUBID, ChaosSpell.SUBID.soul_aegis + 1000)
	regen:setParameter(CONDITION_PARAM_TICKS, ticks)
	regen:setParameter(CONDITION_PARAM_MANAGAIN, 20 + math.floor(player:getLevel() / 10))
	regen:setParameter(CONDITION_PARAM_MANATICKS, 1000)
	player:addCondition(regen)

	local pos = player:getPosition()
	ChaosSpell.vfxOr(pos, "shield_bubble", "arcane_circle", CONST_ME_MAGIC_BLUE)
	return true
end
