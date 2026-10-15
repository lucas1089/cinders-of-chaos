-- Fan of Knives: throw a fan of knives at your target and up to 5 more monsters around you.
--
-- The Thief's pack spell (the Thief only, level 80, range 4): a ranged weapon strike of Shuriken Toss's formula on the
-- target and on the nearest 5 monsters within 4 sqm of you (stealth crit, Poison Blades). Players are only hit when
-- they are the target. Numbers and rules: _packtools.lua.
dofile('data/spells/scripts/chaos/_common.lua')
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
	ChaosPackTools.fan(player, target, "razor_disc")
	return true
end
