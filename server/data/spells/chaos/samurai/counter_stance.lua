-- Counter Stance: for 2 seconds the next melee hit you take is parried and answered with a strike.
--
-- The answer does 1.5x the parried hit (Chaos.classes.counter; done by data/scripts/chaos/thief_combat.lua, which sees
-- the stance as a condition with the class sub id).
dofile('data/spells/scripts/chaos/_common.lua')
ChaosSpell.loadClasses()

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local cfg = Chaos.classes
	local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT)
	c:setParameter(CONDITION_PARAM_SUBID, cfg.subId.counter)
	c:setParameter(CONDITION_PARAM_TICKS, cfg.counter.windowMs)
	player:addCondition(c)
	player:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
	return true
end
