-- Poison Blades: for 20 seconds your weapon hits poison the target.
--
-- Each weapon hit (and weapon strike of a spell) adds a share of its damage as earth damage over 4 seconds
-- (Chaos.classes.poisonBlades; applied by data/scripts/chaos/thief_combat.lua, which sees the buff as a condition
-- with the class sub id).
dofile('data/spells/scripts/chaos/_common.lua')
ChaosSpell.loadClasses()

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local cfg = Chaos.classes
	local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT)
	c:setParameter(CONDITION_PARAM_SUBID, cfg.subId.poisonBlades)
	c:setParameter(CONDITION_PARAM_TICKS, cfg.poisonBlades.durationMs)
	player:addCondition(c)
	ChaosSpell.fx(player:getPosition(), "poison_cloud", CONST_ME_GREEN_RINGS)
	return true
end
