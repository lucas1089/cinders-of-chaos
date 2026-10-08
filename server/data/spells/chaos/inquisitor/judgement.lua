-- Judgement: the Inquisitor brands one target (range 5) with a holy strike. For 8 seconds the target takes 20% more
-- holy damage from every source, the party's included (ChaosTemplar.cfg.judgement; applied by
-- data/scripts/chaos/templar_combat.lua, which sees the brand as a timer condition on the target).
dofile('data/spells/scripts/chaos/_templar.lua')

local T = ChaosTemplar

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local target = ChaosSpell.targetOf(variant)
	if not target or target == player then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUCANONLYUSEITONCREATURES)
	end
	if not ChaosSpell.canAttack(player, target) then
		return ChaosSpell.cancel(player, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER)
	end
	-- the brand first, so the strike itself is raised too
	TemplarSpell.addTimer(target, T.cfg.ids.subId.judgement, T.cfg.judgement.durationMs)
	target:registerEvent("ChaosTemplarCombat")
	local min, max = TemplarSpell.values(player, 0.08, 0.12, 1.0, 1.5, 20, 40)
	ChaosSpell.shoot(player:getPosition(), target:getPosition(), "holy_arrow", CONST_ANI_HOLY)
	ChaosSpell.fx(target:getPosition(), "holy_cross", CONST_ME_HOLYAREA)
	TemplarSpell.holyStrike(player, target, min, max, CONST_ME_HOLYDAMAGE)
	return true
end
