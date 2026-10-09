-- Sundering Palm: a heavy palm strike that spends all chi; the damage grows with the chi spent.
--
-- Finisher: x (0.30 + 0.14 per chi) of the 5-chi formula (ChaosMonk.finisherScale). Needs at least 1 chi.
dofile('data/spells/scripts/chaos/_monk.lua')

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
	ChaosSpell.fx(target:getPosition(), "shockwave", CONST_ME_GROUNDSHAKER)
	ChaosSpell.vfx(target:getPosition(), "punch_hit_red")
	MonkSpell.strike(player, target, ChaosMonk.formula.sunderingPalm, ChaosMonk.finisherScale(spent), CONST_ME_HITAREA)
	return true
end
