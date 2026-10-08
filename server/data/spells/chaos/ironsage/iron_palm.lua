-- Iron Palm: spend all chi on an iron-hard palm at the target next to you; it stuns a monster for 1-2.6 s.
--
-- Finisher: damage x the finisher scale; a stunned monster stands still and cannot attack (monk_combat.lua cancels
-- its attacks while the stun condition lasts). Stun 0.6 s + 0.4 s per chi; afterwards the monster cannot be stunned
-- for 4 s. A monster with more than 50000 max health is only slowed by 50%. Players are not stunned.
dofile('data/spells/scripts/chaos/_monk.lua')

local function stun(target, spent)
	local M = ChaosMonk
	if not target:isMonster() then
		return
	end
	local immune = target:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, M.ids.subId.stunImmune) ~= nil
	local ms, locks = M.stunFor(spent, target:getMaxHealth(), immune)
	if ms <= 0 then
		return
	end
	local c = Condition(CONDITION_PARALYZE)
	c:setParameter(CONDITION_PARAM_TICKS, ms)
	if locks then
		c:setParameter(CONDITION_PARAM_SUBID, M.ids.subId.stun)
		c:setFormula(-1, 0, -1, 0)
		ChaosSpell.fx(target:getPosition(), "ground_slam", CONST_ME_STUN)
	else
		c:setFormula(-M.cfg.stun.bossSlow, 0, -M.cfg.stun.bossSlow, 0)
	end
	target:addCondition(c)
	MonkSpell.timer(target, M.ids.subId.stunImmune, ms + M.cfg.stun.immuneMs)
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local target = MonkSpell.meleeTarget(player, variant)
	if not target then
		return false
	end
	local spent = MonkSpell.finisher(player)
	if not spent then
		return false
	end
	MonkSpell.strike(player, target, ChaosMonk.formula.ironPalm, ChaosMonk.finisherScale(spent), CONST_ME_GROUNDSHAKER)
	if target:getHealth() > 0 then
		stun(target, spent)
	end
	return true
end
