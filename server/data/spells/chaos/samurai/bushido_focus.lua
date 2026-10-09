-- Bushido Focus: for 30 seconds your critical chance grows while you take no damage.
--
-- Every second without taking damage adds a stack (3 at once, 10 at most); each stack is +3% critical chance on weapon
-- hits and weapon strikes (Iaijutsu), a critical hit does x1.5. A hit taken starts the stacks again from zero.
-- (Chaos.classes.bushido; counted by data/scripts/chaos/thief_combat.lua, which sees the buff as a condition with the
-- class sub id.) Recasting refreshes the time and keeps the stacks.
dofile('data/spells/scripts/chaos/_common.lua')
ChaosSpell.loadClasses()

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local cfg = Chaos.classes
	local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT)
	c:setParameter(CONDITION_PARAM_SUBID, cfg.subId.bushido)
	c:setParameter(CONDITION_PARAM_TICKS, cfg.bushido.durationMs)
	player:addCondition(c)
	if not ChaosSpell.vfx(player:getPosition(), "aura_burst_gold") then
		player:getPosition():sendMagicEffect(CONST_ME_HOLYDAMAGE)
	end
	return true
end
