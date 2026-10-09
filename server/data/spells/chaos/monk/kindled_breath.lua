-- Kindled Breath: breathe the chi in and heal yourself; the heal grows with the chi spent.
--
-- Finisher (needs 1 chi): heal (level x 2 + fist x 6) x the finisher scale. The Iron Sage's breath also heals
-- 60% more over 6 s (CONDITION_REGENERATION, sub id ChaosMonk.ids.subId.breath).
dofile('data/spells/scripts/chaos/_monk.lua')

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local spent = MonkSpell.finisher(player)
	if not spent then
		return false
	end
	local M = ChaosMonk
	local heal, tick = M.breathHeal(player:getLevel(), player:getEffectiveSkillLevel(SKILL_FIST), spent,
		M.isIronSage(player:getVocation():getId()))
	ChaosSpell.healTarget(player, player, heal, heal, Fx("heal_sparkle", CONST_ME_MAGIC_BLUE))
	ChaosSpell.vfx(player:getPosition(), "chi_charge")
	if tick > 0 then
		local c = Condition(CONDITION_REGENERATION)
		c:setParameter(CONDITION_PARAM_SUBID, M.ids.subId.breath)
		c:setParameter(CONDITION_PARAM_TICKS, M.cfg.breath.hotTicks * 1000)
		c:setParameter(CONDITION_PARAM_HEALTHGAIN, tick)
		c:setParameter(CONDITION_PARAM_HEALTHTICKS, 1000)
		player:addCondition(c)
	end
	return true
end
