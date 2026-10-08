-- Ashen Fist: a quick strike at the target next to you that builds 2 chi. The Monk's builder.
--
-- A Monk strike (fist power, or a staff's): Pressure Points and the Shadowfist focus crit apply.
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
	ChaosSpell.fx(target:getPosition(), "ground_slam", CONST_ME_HITAREA)
	MonkSpell.strike(player, target, ChaosMonk.formula.ashenFist, 1, CONST_ME_HITAREA)
	ChaosMonk.addChi(player, ChaosMonk.cfg.chi.ashenFist)
	return true
end
