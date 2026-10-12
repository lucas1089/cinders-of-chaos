-- Bloodrage: pay 10% of your current health; for 12 s Rage gets +10% on top and every melee weapon hit also strikes
-- up to 4 other enemies next to you for 40% of the hit.
--
-- The Berserker's frenzy. The health it costs feeds Rage (the passive bonus grows as health drops). Applied by
-- data/scripts/chaos/berserker_combat.lua, which sees the buff as a condition with the class sub id
-- (Chaos.classes.subId.bloodrage, numbers in Chaos.classes.bloodrage).
dofile('data/spells/scripts/chaos/_common.lua')
ChaosSpell.loadClasses()

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local cfg = Chaos.classes
	local cost = ChaosClasses.bloodrageCost(player:getHealth())
	if cost > 0 then
		doTargetCombatHealth(0, player, COMBAT_UNDEFINEDDAMAGE, -cost, -cost, CONST_ME_DRAWBLOOD)
	end
	local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT)
	c:setParameter(CONDITION_PARAM_SUBID, cfg.subId.bloodrage)
	c:setParameter(CONDITION_PARAM_TICKS, cfg.bloodrage.durationMs)
	player:addCondition(c)
	local pos = player:getPosition()
	ChaosSpell.vfxOr(pos, "aura_burst_red", "blood_rune", CONST_ME_DRAWBLOOD)
	pos:sendMagicEffect(CONST_ME_MAGIC_RED)
	return true
end
