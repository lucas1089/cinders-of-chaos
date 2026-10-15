-- Shadow Ricochet: a shadow-wrapped strike that leaps from your target to up to 4 more monsters nearby.
--
-- The Shadowfist's pack strike (level 150, range 4): the target, then each jump to the nearest monster within 3 sqm of
-- the last one hit, none twice, a Monk strike each (Pressure Points and the focus crit apply). Players are only hit
-- when they are the target. Numbers and rules: _packtools.lua.
dofile('data/spells/scripts/chaos/_monk.lua')
dofile('data/spells/scripts/chaos/_packtools.lua')

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
	ChaosPackTools.jumpStrike(player, target, "ricochet", "shadow_bolt", CONST_ANI_DEATH, "void_eye", CONST_ME_MORTAREA)
	return true
end
