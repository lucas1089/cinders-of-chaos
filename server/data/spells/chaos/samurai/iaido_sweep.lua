-- Iaido Sweep: draw and cut wide; the target and every monster in front of you are struck.
--
-- The Samurai's area strike (level 200): the target within 2 sqm and every monster in the 3 x 2 tiles in front of you,
-- towards it, take a melee weapon strike of half an Iaijutsu, without a charge. Other players are only hit when they
-- are the target. Each hit rolls the Bushido crit and carries Poison Blades. Numbers and rules: _blades.lua.
dofile('data/spells/scripts/chaos/_common.lua')
dofile('data/spells/scripts/chaos/_blades.lua')

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
	ChaosBlades.sweep(player, target, "heavy_cleave", "ground_slam")
	return true
end
