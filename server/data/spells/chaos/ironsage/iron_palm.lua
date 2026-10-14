-- Iron Palm: spend all chi on an iron-hard palm at the target next to you; it stuns a monster for 1-2.6 s and a
-- player for 0.6-1 s.
--
-- Finisher: damage x the finisher scale; a stunned monster stands still and cannot attack (monk_combat.lua cancels
-- its attacks while the stun condition lasts). Stun 0.6 s + 0.4 s per chi; afterwards the monster cannot be stunned
-- for 4 s. A monster with more than 50000 max health is only slowed by 50%.
-- A player is stunned by monk_combat.lua when the strike's damage lands on it (ChaosMonk.cfg.stun.pvp: 0.5 s + 0.1 s
-- per chi, 6 s immunity, half as long within 15 s of the last stun); the spell only tells it the chi spent.
dofile('data/spells/scripts/chaos/_monk.lua')
-- status words (data/lib/chaos_status_fx.lua, switch off: nothing more is sent)
if not ChaosStatusFx then
	pcall(dofile, "data/lib/chaos_status_fx.lua")
end

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
		ChaosSpell.vfxOr(target:getPosition(), "punch_hit_gold", "ground_slam", CONST_ME_STUN)
		if ChaosStatusFx then
			ChaosStatusFx.send(target:getPosition(), "stun", nil, target:getId())
		end
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
	local pvp = target:isPlayer()
	if pvp then
		player:setStorageValue(ChaosMonk.ids.storage.palmChi, spent)
	end
	MonkSpell.strike(player, target, ChaosMonk.formula.ironPalm, ChaosMonk.finisherScale(spent), CONST_ME_GROUNDSHAKER)
	if pvp then
		player:setStorageValue(ChaosMonk.ids.storage.palmChi, -1)
	elseif target:getHealth() > 0 then
		stun(target, spent)
	end
	return true
end
